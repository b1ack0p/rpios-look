#!/usr/bin/env bash
# =============================================================================
# Title       : rpios-look.sh
# Description : Makes Debian 13 and later on 64-bit PCs (x64, amd64) look
#               like Raspberry Pi OS, without breaking Debian: the official
#               PiXtrix, PiXonyx, PiXflat, PiXnoir and PiX themes with their
#               icons, cursors, fonts, wallpapers, panel, file manager and
#               login screen, as a "Raspberry Pi Desktop" session on the
#               login screen. For Debian 9 to 12, also on 32-bit PCs, use
#               rpios-look-legacy.sh from https://github.com/b1ack0p/rpios-look.
#
# Usage       : bash rpios-look.sh                    install; run again, reinstall clean
#                                                     with default settings
#               bash rpios-look.sh --refresh          list updates, then ask to apply them;
#                                                     keeps your settings
#               bash rpios-look.sh --uninstall        remove the look, restore Debian's setup
#               bash rpios-look.sh --help             show this text
#               Safe to run again.
#
# Look        : The look is Raspberry Pi OS's for this Debian release:
#               PiXtrix, with its icons, cursor, font, window frames and
#               wallpaper. The themes and wallpapers of this and every
#               earlier Raspberry Pi OS release are installed; each user can
#               change theirs with rpios-look-set --theme NAME. The session
#               runs on X (Openbox); a second one, "Raspberry Pi Desktop
#               (Wayland)", runs Raspberry Pi OS's labwc desktop with
#               Debian's labwc. Both are on the login screen; X is the
#               default, and the session a user picks is remembered
#               (rpios-look-set --session x|wayland switches it).
#
# Options     :     --size SIZE      small, medium, large or larger: Raspberry Pi OS's
#                                    size presets for fonts, icons, the panel and the
#                                    cursor; large and larger also widen the
#                                    title bars, scrollbars and window borders.
#                                    Default: medium, Raspberry Pi OS's own.
#                                    Saved; --refresh reuses it unless it is
#                                    given again; a plain run goes back to medium
#               --no-reboot          do not restart the computer at the end: an
#                                    install and --uninstall restart it after a
#                                    60-second countdown, which Enter shortens
#                                    and n cancels; --refresh asks first when
#                                    what it changed needs a restart
#               -v, --verbose        also print the commands run as root, the
#                                    files downloaded and other details
#               -V, --version        print the version
#
# Refresh     : --refresh lists what an update would change: newer official
#               packages, missing ones, a Debian change, a changed size. It
#               asks before applying anything.
#
# Undo        : bash rpios-look.sh --uninstall removes the session, the
#               packages it installed and the login screen style, and restores
#               the settings of the user running it. It also removes an
#               installation made by rpios-look-legacy.sh.
#
# Upgrade     : Debian upgrades itself; this script never checks for a new
#               release. Before a Debian release upgrade, uninstall the
#               rpios-look script (--uninstall); after it, run a clean
#               install (rpios-look.sh on Debian 13 and later). --uninstall
#               works on any release, also after an upgrade made with the
#               rpios-look script still installed. --refresh only updates the
#               packages of the installed release. Each script stops when the
#               other one installed the rpios-look script: uninstall first.
#
# Requires    : Debian 13 or later (testing and unstable too) on amd64, with
#               Debian's LXDE desktop; a normal user (not root) with sudo
#               rights; internet access.
#
# Disclaimer  : Use at your own risk. This script installs packages and
#               changes system files as root. It is provided "as is", without
#               warranty of any kind (see LICENSE). The authors accept no
#               responsibility for a broken system, lost data, security issues
#               or any other damage, whether caused by the script, by the
#               packages it installs or by the release it runs on. Debian
#               releases older than the current stable one may no longer get
#               security updates and may contain known vulnerabilities. Back
#               up your data before running it.
# =============================================================================

# Contents
#   1. Settings     constants, options, state
#   2. Helpers      messages, questions, records, run lock
#   3. Packages     themes, package sets, host and release
#   4. Archives     signed indexes, resolution, download, repacking
#   5. Artwork      icon sets with the Debian logo
#   6. Session      the Raspberry Pi Desktop session and login screen
#   7. Install      packages, the generated package, records
#   8. User state   backups for --uninstall
#   9. Refresh      --refresh
#  10. Uninstall    --uninstall
#  11. Main         modes, run log, summary

set -Eeuo pipefail
umask 022

if [[ -z ${BASH_VERSINFO:-} ]] || (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404 )); then
	echo "rpios-look: bash 4.4 or newer is required" >&2
	exit 1
fi

###############################################################################
# 1. Settings: constants, options, state
###############################################################################

readonly APP_NAME="rpios-look"
readonly APP_VERSION="1.0.0"
# The edition, recorded in the state; rpios-look-legacy.sh is "legacy"
readonly APP_EDITION="main"
# The package this script generates. It holds the session, the login screen
# style and the adapted icon sets, so that dpkg tracks and removes them.
readonly APP_PKG="rpios-look-debian"
# Records of the install: installed packages, the saved size, replaced files.
readonly SYS_DIR="/var/lib/rpios-look"
# Configuration and data of the session, shipped in the generated package.
readonly SHARE="/usr/share/rpios-look"
# The wallpapers, a folder of links per wallpaper package (see wallpaper_links)
readonly WALLS="/usr/share/backgrounds/rpios-look"
readonly SESSION_ID="rpios-look"
# The Raspberry Pi Desktop session on Wayland (labwc), beside the X one
readonly WL_SESSION_ID="rpios-look-wayland"
# APT options: never remove a package, never ask, and wait for another
# package manager to finish. Recommended packages are not installed: every
# needed package is named explicitly, and a recommendation (Raspberry Pi's
# plugins recommend PulseAudio) must not replace installed software.
readonly APT_OPTS=(-y --no-remove --no-install-recommends -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=300)
# For purges: the same wait for the package manager
readonly APT_PURGE=(-y -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=300)
# The lock a purge holds while its policy-rc.d denies service actions (_purge)
readonly PURGE_LOCK="/run/lock/rpios-look-purge"
# The network and Bluetooth tools an install may add (tray_debs): --uninstall
# removes them without asking, so that the network setup from before the
# install comes back
readonly NET_PKGS_RE="network-manager|wpasupplicant|iw|wireless-regdb|rfkill|dnsmasq-base|bluez|libspa-0[.]2-bluetooth|pulseaudio-module-bluetooth"
readonly RPI_ARCHIVE="https://archive.raspberrypi.org/debian"
# Raspberry Pi's archive in APT, so that "apt upgrade" updates the
# unmodified Raspberry Pi packages this script installed (see apt_files).
readonly APT_SRC="/etc/apt/sources.list.d/rpios-look.sources" APT_PIN="/etc/apt/preferences.d/rpios-look"
readonly APT_HOOK="/etc/apt/apt.conf.d/50rpios-look" APT_KEY="/usr/share/keyrings/rpios-look-archive-keyring.gpg"
# Raspberry Pi's builds that would clash with Debian's packages are repacked
# to install beside them (see beside_build): named BESIDE_PREFIX + their name,
# with the names that the repacking renames recorded (BESIDE_CONF). --refresh
# updates them.
readonly BESIDE_PREFIX="rpios-look-" BESIDE_CONF="$SYS_DIR/beside.conf"
# wicd's settings, whose Wi-Fi interface rpios-look-legacy.sh may set (wicd_restore)
readonly WICD_CONF="/etc/wicd/manager-settings.conf"
readonly RPI_KEY_URL="${RPI_ARCHIVE}/raspberrypi.gpg.key"
readonly RPI_KEY_FPR="CF8A1AF502A2AA2D763BAE7E82B129927FA3303E"
# Raspberry Pi OS configuration packages. They are downloaded and verified
# but never installed: rpd-common provides the menu (Raspberry Pi OS 13 and
# later), rpd-x-core the panel layout.
readonly ART_PKG="rpd-common" PANEL_PKG="rpd-x-core"
# The panel's layout in PANEL_PKG
readonly PANEL_LAYOUT="etc/xdg/lxpanel-pi/panels/panel"
# Raspberry Pi OS's Wayland desktop (labwc), the second session
readonly WL_PKG="rpd-wayland-core"
# The PC architectures that rpios-look has installed on, as grep -E
# alternatives: --uninstall accepts them all. An install needs INSTALL_ARCH.
readonly PC_ARCHES="amd64|i386" INSTALL_ARCH="amd64"
# The only other files read online, as data (fetch_extra): Debian's release
# table and the published version of this script.
readonly RELEASES_URL="https://salsa.debian.org/debian/distro-info-data/-/raw/main/debian.csv"
readonly SELF_URL="https://raw.githubusercontent.com/b1ack0p/rpios-look/main/rpios-look.sh"
readonly EXTRA_URLS=("$RELEASES_URL" "$SELF_URL")
# Debian releases by major version. Debian's distro-info-data, if installed,
# adds releases named after this script was written.
readonly KNOWN_RELEASES=(9:stretch 10:buster 11:bullseye 12:bookworm 13:trixie 14:forky 15:duke)
# Debian releases' life cycle, as distro-info-data gives it: major version,
# release date, end of regular security support, end of LTS. Debian's
# distro-info-data, if installed, corrects and extends it (load_releases).
readonly KNOWN_LIFECYCLE=(
	9:2017-06-17:2020-07-18:2022-06-30
	10:2019-07-06:2022-09-10:2024-06-30
	11:2021-08-14:2024-08-14:2026-08-31
	12:2023-06-10:2026-07-11:2028-06-30
	13:2025-08-09:2028-08-09:2030-06-30
)
# HOST_OLDEST: the oldest Debian release this script installs on; older ones
# use rpios-look-legacy.sh (LEGACY_*). OLDEST: the oldest Raspberry Pi OS
# release whose indexes are read, for the looks of earlier releases.
readonly HOST_OLDEST=13 OLDEST=9
readonly LEGACY_SCRIPT="rpios-look-legacy.sh" LEGACY_URL="https://github.com/b1ack0p/rpios-look"
# Raspberry Pi OS theme packages that are built per architecture but contain
# no compiled code, so the build of any Raspberry Pi OS release can be used.
readonly DATA_PKGS=(pixflat-theme pixtrix-theme pix-theme)

# Dependency names of earlier releases' packages that Debian has since renamed,
# mapped to their successors; the first available candidate is used.
declare -grA DEP_RENAMES=(
	[libgdk-pixbuf2.0-0]="libgdk-pixbuf-2.0-0"
	[libglib2.0-0]="libglib2.0-0t64"
	[libgtk2.0-0]="libgtk2.0-0t64"
	[libatk1.0-0]="libatk1.0-0t64"
)

# Cursor names that toolkits request, mapped to equivalents in the official
# cursor themes. A missing name becomes a symlink to an official file.
readonly CURSOR_ALIASES=(
	"default:left_ptr arrow"            "left_ptr:default arrow"
	"pointer:hand2 hand1 hand"          "hand1:pointer hand2"          "hand2:pointer hand1"
	"help:question_arrow left_ptr_help" "question_arrow:help"          "left_ptr_help:help"
	"context-menu:left_ptr"             "progress:left_ptr_watch half_busy"
	"half_busy:progress left_ptr_watch" "left_ptr_watch:progress"      "wait:watch"   "watch:wait"
	"cell:plus crosshair cross"         "crosshair:cross tcross"       "text:xterm ibeam"
	"xterm:text"                        "vertical-text:text xterm"     "copy:dnd-copy"
	"dnd-copy:copy"                     "alias:dnd-link link copy"     "link:alias dnd-link copy"
	"dnd-link:alias link copy"          "move:fleur dnd-move"          "dnd-move:move fleur"
	"fleur:move size_all all-scroll"    "all-scroll:fleur size_all move" "size_all:fleur all-scroll"
	"pointer-move:move fleur"           "not-allowed:crossed_circle forbidden no-drop"
	"no-drop:dnd-no-drop not-allowed"   "dnd-no-drop:no-drop not-allowed"
	"crossed_circle:not-allowed"        "forbidden:not-allowed"        "dnd-none:dnd-move move"
	"grab:openhand hand1"               "openhand:grab hand1"          "grabbing:closedhand closehand fleur"
	"closedhand:grabbing"               "closehand:grabbing"
	"col-resize:sb_h_double_arrow ew-resize" "row-resize:sb_v_double_arrow ns-resize"
	"ew-resize:sb_h_double_arrow h_double_arrow size_hor col-resize"
	"ns-resize:sb_v_double_arrow v_double_arrow size_ver row-resize"
	"h_double_arrow:ew-resize sb_h_double_arrow" "v_double_arrow:ns-resize sb_v_double_arrow"
	"sb_h_double_arrow:ew-resize"       "sb_v_double_arrow:ns-resize"
	"size_hor:ew-resize sb_h_double_arrow" "size_ver:ns-resize sb_v_double_arrow"
	"nesw-resize:fd_double_arrow size_bdiag ne-resize sw-resize top_right_corner"
	"nwse-resize:bd_double_arrow size_fdiag nw-resize se-resize top_left_corner"
	"fd_double_arrow:nesw-resize"       "bd_double_arrow:nwse-resize"
	"size_bdiag:nesw-resize"            "size_fdiag:nwse-resize"
	"n-resize:top_side"    "s-resize:bottom_side"    "e-resize:right_side"   "w-resize:left_side"
	"top_side:n-resize"    "bottom_side:s-resize"    "right_side:e-resize"   "left_side:w-resize"
	"ne-resize:top_right_corner"    "nw-resize:top_left_corner"
	"se-resize:bottom_right_corner" "sw-resize:bottom_left_corner"
	"top_right_corner:ne-resize"    "top_left_corner:nw-resize"
	"bottom_right_corner:se-resize" "bottom_left_corner:sw-resize"
	"left_tee:left_side"   "right_tee:right_side"   "top_tee:top_side"      "bottom_tee:bottom_side"
	"ul_angle:top_left_corner"      "ur_angle:top_right_corner"
	"ll_angle:bottom_left_corner"   "lr_angle:bottom_right_corner"
	"zoom-in:plus cell"    "zoom-out:zoom-in"
	# Hashed names used by Qt and older X11 toolkits.
	"00008160000006810000408080010102:ns-resize"   "028006030e0e7ebffc7f7070c0600140:ew-resize"
	"03b6e0fcb3499374a867c041f52298f0:not-allowed" "08e8e1c95fe2fc01f976f1e063a24ccd:progress"
	"1081e37283d90000800003c07f3ef6bf:copy"        "14fef782d02440884392942c11205230:col-resize"
	"2870a09082c103050810ffdffffe0204:row-resize"  "3085a0e285430894940527032f8b26df:alias"
	"3ecb610c1bf2410f44200f48c40d3599:progress"    "4498f0e0c1937ffe01fd06f973665830:move"
	"5c6cd98b3f3ebcb1f9c7f1c204630408:help"        "6407b0e94181790501fd1e167b474872:copy"
	"640fb0e74195791501fd1ed57b41487f:alias"       "9081237383d90e509aa00f00170e968f:move"
	"9d800788f1b08800ae810202380a0822:pointer"     "a2a266d0498c3104214a47bd64ab0fc8:alias"
	"b66166c04f8c3109214a4fbd64a50fc8:copy"        "c7088f0f3e6c8088236ef8e1e3e70000:nwse-resize"
	"d9ce0ab605698f320427677b458ad60b:help"        "e29285e634086352946a0e7090d73106:pointer"
	"fcf1c3c7cd4491d801f1e1c78f100000:nesw-resize"
)

# Icon names that Debian's programs request, mapped to Raspberry Pi OS icons:
# the notification area (sound, network, Bluetooth) and the folder, drive and
# network names used by file managers and dialogs. A missing name becomes a
# symlink to an official image. A leading "!" also replaces the name where the
# theme maps it to an image that Raspberry Pi OS's panel does not show.
# Secure connections show the plain signal icon, as on Raspberry Pi OS.
readonly ICON_ALIASES=(
	"audio-volume-high-panel:audio-volume-high"     "audio-volume-medium-panel:audio-volume-medium"
	"audio-volume-low-panel:audio-volume-low"       "audio-volume-muted-panel:audio-volume-muted"
	"nm-secure-lock:network-wireless-encrypted"    "nm-device-wired-secure:nm-device-wired"
	"nm-signal-00-secure:nm-signal-00"              "nm-signal-25-secure:nm-signal-25"
	"nm-signal-50-secure:nm-signal-50"              "nm-signal-75-secure:nm-signal-75"
	"nm-signal-100-secure:nm-signal-100"
	"inode-directory:folder"                        "folder-open:folder"
	"media-optical:media-removable"                 "drive-optical:media-removable"
	"drive-removable-media:media-removable"         "media-flash:media-removable"
	"network-wired:network-transmit-receive"        "network-wireless:network-wireless-connected-100"
	"network-workgroup:network"                     "network-server:network"
	"blueman:bluetooth-active"                      "blueman-tray:bluetooth-active"
	"blueman-active:bluetooth-online"               "blueman-disabled:bluetooth-offline"
	"bluetooth-symbolic:bluetooth-active"           "!bluetooth-disabled:bluetooth-offline"
	"!bluetooth-disabled-symbolic:bluetooth-offline" "bluetooth-disconnected-symbolic:bluetooth-inactive"
	"!rpi:system-shutdown"
)
# Icon names drawn as the Raspberry Pi logo for the menu button; each shows the
# Debian logo instead. "rpi" (the Shutdown dialog's icon before Raspberry Pi OS
# 13) shows the Shutdown icon, as from 13 on (see ICON_ALIASES).
readonly LOGO_ICONS=(start-here distributor-logo launch rpi-logo)

# Options (O_*). An install saves the size in $SYS_DIR/options; --refresh
# reuses it unless --size is given again, an install starts from medium.
O_MODE="install"        # install | refresh | uninstall
O_SIZE=medium           # the size preset: small, medium (Raspberry Pi OS's default), large or larger
O_SIZE_GIVEN=0          # 1 when --size is given on this command line
O_VERBOSE=0
O_NO_REBOOT=0          # 1 with --no-reboot: never restart the computer at the end
O_INTERACTIVE=0        # 1 when a terminal can answer questions (ask)
REBOOT_WHY=""           # why the changes of --refresh need a restart, if they do

# Host (H_*) and run state. The theme variables (T_*) are set by set_theme.
H_ARCH="" H_ID="" H_CODENAME="" H_PRETTY="" H_SUITE=""
# The computer (see detect_machine)
H_MODEL="" H_CPU="" H_MEM_MB=0 H_GPU="" H_GPU_DRV="" H_GPU_DRVS=""
H_VIRT="" H_KERNEL="" H_LXDE=0 H_DM=""
FETCH_PKGS=()           # installed from verified .deb files
PIN_PKGS=()             # those installed as Raspberry Pi ships them, which APT updates
HW_PKGS=()              # hardware support (X server, network, Bluetooth, sound, login screen)
POLICY_RC=""            # the policy-rc.d file a purge made, removed on exit
ROOT_PKGS=()            # what is installed for its own sake, not as a dependency
APT_PKGS=()             # installed by name from the APT sources
STALE_PKGS=()           # installed by this script, no longer part of the look (stale_pkgs)
USE_NETMAN=0            # 1 when Raspberry Pi's network plugin and its libnma build are used
PURGED=0                # 1 once this run removed packages (_purge)
DESKTOP_KNOWN=0         # 1 when this script knows the release's desktop (desktop_known)
WAYLAND=0               # 1 when the Wayland session is installed too (wayland_known)
TWINS=()                # Raspberry Pi's builds of Debian's packages, installed beside them (beside_build)
BESIDE=()               # the other packages repacked beside Debian's (beside_plan)
BESIDE_DONE=0           # 1 once this run decided which packages are repacked
declare -gA PKG_VER=() PKG_FILE=() PKG_SHA=() PKG_SIZE=() PKG_SUITE=() PKG_DEPS=()
declare -gA IDX_LOADED=() IDX_FAILED=() IN_SET=()
WORKDIR="" KEYRING="" LOG_FILE="" PKG_DEB=""
ARGV=()
NOTES=()                # lines for the summary at the end
STEP=0                  # the number of the step being shown
SYS_ROOT=""             # filesystem root from which the package builder reads themes (tests)

###############################################################################
# 2. Helpers: messages, questions, records, run lock
###############################################################################

C_B="" C_D="" C_R="" C_G="" C_Y="" C_C="" C_0=""

# Enable colours when stderr is a terminal and NO_COLOR is unset.
init_colors() {
	if [[ -t 2 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
		C_B=$'\e[1m' C_D=$'\e[2m' C_R=$'\e[31m' C_G=$'\e[32m' C_Y=$'\e[33m' C_C=$'\e[1;96m' C_0=$'\e[0m'
	fi
}
# Messages, all on stderr: plain, information, success, warning, fatal error,
# numbered step heading, and detail shown only with --verbose.
log()   { printf '%s\n' "$*" >&2; }
info()  { printf '%s::%s %s\n' "$C_C" "$C_0" "$*" >&2; }
ok()    { printf '%s✔%s %s\n' "$C_G" "$C_0" "$*" >&2; }
warn()  { printf '%s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()   { printf '%s✘ error:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
step()  { STEP=$(( STEP + 1 )); printf '\n%s==> %d. %s%s\n' "$C_C" "$STEP" "$*" "$C_0" >&2; }
debug() { if (( O_VERBOSE )); then printf '%s   %s%s\n' "$C_D" "$*" "$C_0" >&2; fi; }
# Print a warning now and keep it for the summary at the end.
note()  { warn "$*"; NOTES+=("$*"); }

# Print the first line of stdin. All input is read, so the writing command
# never fails on a closed pipe under pipefail.
first_line() { awk 'NR == 1'; }

# Read the lines that a command prints into the array NAME. A command behind
# "< <(...)" that fails ends early unseen, so its output ends with a mark here,
# and output without the mark stops the run: a package set cut short must never
# pass. Usage: read_lines NAME COMMAND [ARG]...
read_lines() {
	local -n _lines=$1
	local end=$'\x01end'
	mapfile -t _lines < <("${@:2}"; echo "$end")
	[[ ${_lines[*]: -1} == "$end" ]] || die "could not work out the package set ($2 stopped early)"
	unset '_lines[-1]'
}

# Quote arguments for display.
_q() { local a q out=""; for a; do printf -v q '%q' "$a"; out+="${out:+ }$q"; done; printf '%s' "$out"; }

# Run a command as root through sudo; with --verbose, print it first.
as_root() { if (( O_VERBOSE )); then debug "sudo $(_q "$@")"; fi; sudo -- "$@"; }

# Ask a yes/no question on the terminal, also when the script is read from a
# pipe. Without a terminal, the default answer is taken.
# Usage: ask QUESTION y|n
ask() {
	local q=$1 def=$2 ans hint="[y/N]"
	[[ $def == y ]] && hint="[Y/n]"
	if (( ! O_INTERACTIVE )); then [[ $def == y ]]; return; fi
	read -r -p "$(printf '%s?%s %s %s ' "$C_C" "$C_0" "$q" "$hint")" ans </dev/tty || ans=""
	ans=${ans,,}
	[[ -z $ans ]] && ans=$def
	[[ $ans == y || $ans == yes ]]
}

# Finish a run that needs a restart: say so at the end of the run, then
# restart the computer. "auto" counts down 60 seconds and restarts unless n
# (or Ctrl+C) cancels; Enter restarts at once. "ask" restarts only on a yes.
# Without a terminal, or with --no-reboot, it only says so.
# Usage: offer_reboot auto|ask REASON
offer_reboot() {
	local how=$1 why=$2 key t rc go=0 stop=0
	log ""
	warn "A restart is needed to finish: $why."
	if (( O_NO_REBOOT || ! O_INTERACTIVE )); then
		info "Restart the computer when you are ready."
		return 0
	fi
	if [[ $how == ask ]]; then
		sleep 0.5
		ask "Restart the computer now" n && go=1
	else
		# The countdown goes to the terminal only, not to the log. The lines
		# before it reach the terminal through the log's pipe (start_log):
		# they are let through first.
		sleep 0.5
		trap 'stop=1' INT
		for (( t = 60; t > 0 && ! stop; t-- )); do
			printf '\r%s?%s Restarting in %2d s. Enter: restart now, n: cancel ' "$C_C" "$C_0" "$t" >/dev/tty
			rc=0; key=""; IFS= read -r -s -n 1 -t 1 key </dev/tty || rc=$?
			(( stop )) && break
			if (( rc > 128 )); then continue; fi
			(( rc == 0 )) || { stop=1; break; }
			case ${key,,} in
				'') go=1; break ;;
				n|$'\e') stop=1; break ;;
			esac
		done
		trap 'die "interrupted"' INT TERM
		printf '\n' >/dev/tty
		(( stop )) || go=1
	fi
	if (( ! go )); then
		info "Not restarted. Restart the computer when you are ready."
		return 0
	fi
	ok "Restarting the computer"
	sleep 1
	if command -v systemctl >/dev/null; then as_root systemctl reboot; else as_root reboot; fi
}

# Print the installed packages with their versions, one "name version" line
# each, to see what a run changed.
pkg_versions() {
	dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' 2>/dev/null | awk '$1 ~ /^.i/ { print $2, $3 }' | LC_ALL=C sort
}

# Print why the packages a run changed need a restart, or nothing when
# logging out is enough: the login screen, the display server, sound and
# network services, which keep running across a logout.
# Usage: reboot_reason BEFORE AFTER (pkg_versions outputs)
reboot_reason() {
	local p c out=""
	local -A seen=()
	while read -r p; do
		[[ -n $p ]] && seen[$(pkg_category "$p")]=1
	done < <(LC_ALL=C comm -3 <(printf '%s\n' "$1" | LC_ALL=C sort) <(printf '%s\n' "$2" | LC_ALL=C sort) \
		| awk '{ print $1 }' | LC_ALL=C sort -u)
	for c in "greeter|the login screen" "display|the display server" "sound|the sound server" \
		"network|network and Bluetooth services"; do
		[[ -z ${seen[${c%%|*}]:-} ]] || out+="${out:+, }${c#*|}"
	done
	[[ -z $out ]] || printf 'updated: %s\n' "$out"
}

# Format a byte count, e.g. 27MB.
human_size() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || printf '%s bytes' "${1:-0}"; }

# Print the command that runs this script again.
self_cmd() { printf 'bash %s' "$(basename -- "${BASH_SOURCE[0]:-$APP_NAME.sh}")"; }

# Print the installed version of a package, or nothing. A package installed
# for several architectures gives the first version only.
installed_version() {
	{ dpkg-query -W -f='${db:Status-Abbrev} ${Version}\n' "$1" 2>/dev/null || true; } | awk '$1 ~ /^.i/ && !n++ { print $2 }'
}
# Print those of the given packages that are installed. Usage: installed_of PACKAGE...
installed_of() {
	local p
	for p; do [[ -z $(installed_version "$p") ]] || echo "$p"; done
}

# Print the names of all installed packages, sorted.
installed_names() {
	dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1 ~ /^.i/ { print $2 }' | LC_ALL=C sort
}

# The lookups below leave out Raspberry Pi's archive, which the install adds
# to APT: they ask what Debian and the system have.

# Print the versions of a package in the APT sources.
apt_versions() {
	LC_ALL=C apt-cache madison "$1" 2>/dev/null \
		| awk -F' *[|] *' -v rpi="${RPI_ARCHIVE#*://}" 'index($3, rpi) == 0 { print $2 }'
}

# Succeed if a package is installed or in the APT sources.
_apt_known() {
	LC_ALL=C apt-cache showpkg "$1" 2>/dev/null | awk -v rpi="${RPI_ARCHIVE#*://}" '
		BEGIN { sub(/\/.*/, "", rpi) }
		/^Versions:/        { s = 1; next }
		/^[A-Z][A-Za-z ]*:/ { s = 0; next }
		s && NF { n = split($0, f, "("); for (i = 2; i <= n; i++) if (index(f[i], rpi) == 0) found = 1 }
		END { exit !found }'
}

# Succeed if APT knows a package or a package that provides it.
apt_has() {
	local p
	_apt_known "$1" && return 0
	for p in $(LC_ALL=C apt-cache showpkg "$1" 2>/dev/null \
		| awk '/^Reverse Provides:/ { s = 1; next } /^[A-Z][A-Za-z ]*:/ { s = 0 } s && NF { print $1 }' | sort -u); do
		_apt_known "$p" && return 0
	done
	return 1
}

# Write stdin to a root-owned, world-readable system file. The file is written
# under a temporary name and renamed, so an interrupted write leaves the old
# file intact.
# Usage: sys_write FILE
sys_write() {
	local tmp rc=0
	# In WORKDIR when set, so that cleanup() removes it after an interruption
	tmp=$(mktemp -p "${WORKDIR:-${TMPDIR:-/tmp}}") || return 1
	cat >"$tmp"
	as_root install -D -m 0644 -- "$tmp" "$1.new" && as_root mv -f -- "$1.new" "$1" || rc=1
	rm -f -- "$tmp"
	return "$rc"
}

# Add lines from stdin to a system record, keeping it sorted and unique.
# Usage: record_add FILE
record_add() { { cat "$1" 2>/dev/null || true; cat; } | LC_ALL=C sort -u | sys_write "$1"; }

# Succeed if a size preset name is valid.
size_ok() { [[ $1 == small || $1 == medium || $1 == large || $1 == larger ]]; }

# Read the saved size, unless --size is given. Only the line "size=" of the
# file is read; the file is parsed, never sourced, and other lines are ignored.
load_size() {
	local val
	(( ! O_SIZE_GIVEN )) && [[ -f $SYS_DIR/options ]] || return 0
	# Only --refresh reuses it; an install, also over an installed look,
	# starts from the default, as every other setting does.
	[[ $O_MODE == refresh && -n $(installed_version "$APP_PKG") ]] || return 0
	val=$(sed -n 's/^size=//p' "$SYS_DIR/options" 2>/dev/null | first_line) || val=""
	if size_ok "$val"; then O_SIZE=$val; else debug "ignoring saved size '$val'"; fi
}

# Save the size of this install run for later runs.
save_size() {
	# Compared without a pipe: a reader that stops early breaks the writer's
	[[ $(cat -- "$SYS_DIR/options" 2>/dev/null) == "size=$O_SIZE" ]] && return 0
	printf 'size=%s\n' "$O_SIZE" | sys_write "$SYS_DIR/options" || note "The size could not be saved; give --size again next time."
}

# Take the run lock, waiting while another run holds it, so that two runs
# never change the system at the same time.
take_run_lock() {
	local lock=/run/lock/$APP_NAME.lock
	{ [[ -e $lock ]] || : >"$lock"; } 2>/dev/null
	{ exec 9<"$lock"; } 2>/dev/null || die "cannot open the run lock $lock"
	if ! flock -n 9; then
		info "Another $APP_NAME run is in progress; waiting for it to finish"
		flock 9
	fi
}

# Stop if an interrupted dpkg run must be repaired first: APT would refuse
# every change, and its errors would appear to come from this script.
require_dpkg_ready() {
	# A policy-rc.d that a purge of this script left behind (the computer
	# stopped meanwhile) would keep Debian from starting services
	if [[ $(sed -n 2p /usr/sbin/policy-rc.d 2>/dev/null) == "# Written by $APP_NAME while it removes packages" ]]; then
		as_root rm -f -- /usr/sbin/policy-rc.d
		info "Removed /usr/sbin/policy-rc.d, which an earlier run left behind"
	fi
	[[ -z $(ls -A /var/lib/dpkg/updates 2>/dev/null) ]] \
		&& ! grep -qvxE 'installed|config-files|not-installed' <<<"$(dpkg-query -W -f='${db:Status-Status}\n' 2>/dev/null)" \
		&& return 0
	die "dpkg was interrupted earlier: run 'sudo dpkg --configure -a' and 'sudo apt-get -f install', then run this again"
}

# Obtain root rights through sudo once, before the system is changed.
prepare_root() {
	command -v sudo >/dev/null || die "sudo is needed: install it and add $(id -un) to the sudo group"
	sudo true || die "$(id -un) cannot use sudo"
}

# Use the user's session bus and display when the script runs outside the
# desktop (SSH, a text console), so that the session can be reloaded and the
# settings that --uninstall resets reach the running desktop.
adopt_session() {
	local uid pid p line
	uid=$(id -u)
	[[ -S /run/user/$uid/bus ]] && export XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
	[[ -n ${DISPLAY:-} ]] && return 0
	for p in lxsession openbox; do
		pid=$(pgrep -u "$uid" -n -x "$p" 2>/dev/null) && break
	done
	[[ -n ${pid:-} ]] || return 0
	while IFS= read -r -d '' line; do
		case $line in
			DISPLAY=*|XAUTHORITY=*|XDG_CURRENT_DESKTOP=*|DESKTOP_SESSION=*) export "${line?}" ;;
		esac
	done < <(cat -- "/proc/$pid/environ" 2>/dev/null || true)
}

# Print the host name of a URL. Usage: _host URL
_host() { local u=${1#*://}; echo "${u%%/*}"; }
# Succeed if the user runs a process of that name.
_running() { pgrep -u "$(id -u)" -x "$1" >/dev/null 2>&1; }
# Succeed if this runs in the Raspberry Pi Desktop session on Wayland: the
# login manager may name it by labwc's desktop name (XDG_SESSION_DESKTOP=labwc),
# so the session's own DESKTOP_SESSION counts too, as for rpios-look-set.
_in_wl_session() { [[ -n ${WAYLAND_DISPLAY:-} && ( ${XDG_SESSION_DESKTOP:-} == "$WL_SESSION_ID" || ${DESKTOP_SESSION:-} == rpd-labwc ) ]]; }

###############################################################################
# 3. Packages: themes, package sets, host and release
###############################################################################

# Set the T_* variables for a theme. T_GTK names the GTK and Openbox themes
# alike; the icons, cursor, font and wallpaper follow the theme.
# Usage: set_theme THEME
set_theme() {
	case $1 in
		pixflat) T_GTK=PiXflat T_ICON_BASE=PiXflat T_ERA=bookworm T_DARK=0
		         T_DESC="PiXflat — light, Raspberry Pi OS Buster to Bookworm" ;;
		pixnoir) T_GTK=PiXnoir T_ICON_BASE=PiXflat T_ERA=bookworm T_DARK=1
		         T_DESC="PiXnoir — dark, Raspberry Pi OS Bookworm" ;;
		pixtrix) T_GTK=PiXtrix T_ICON_BASE=PiXtrix T_ERA=trixie T_DARK=0
		         T_DESC="PiXtrix — light, Raspberry Pi OS Trixie" ;;
		pixonyx) T_GTK=PiXonyx T_ICON_BASE=PiXtrix T_ERA=trixie T_DARK=1
		         T_DESC="PiXonyx — dark, Raspberry Pi OS Trixie" ;;
		pix)     T_GTK=PiX T_ICON_BASE=PiX T_ERA=legacy T_DARK=0
		         T_DESC="PiX — legacy, Raspbian Stretch" ;;
		*) die "unknown theme '$1'" ;;
	esac
	# Raspberry Pi OS's size presets, from its Appearance Settings (Defaults):
	# font, cursor, panel icons and taskbar buttons, toolbar, file manager and
	# terminal. Medium is Raspberry Pi OS's default.
	case ${O_SIZE:-medium} in
		small)  T_FONT_SIZE=8  T_CURSOR_SIZE=24 T_PANEL_ICON=20 T_TASK_WIDTH=150 T_TB_ICON=16 \
		        T_FOLDER_ICON=32 T_SMALL_ICON=16 T_PANE_ICON=16 T_THUMB=64 T_TERM_FONT="Monospace 8" ;;
		large)  T_FONT_SIZE=16 T_CURSOR_SIZE=36 T_PANEL_ICON=52 T_TASK_WIDTH=300 T_TB_ICON=48 \
		        T_FOLDER_ICON=80 T_SMALL_ICON=32 T_PANE_ICON=32 T_THUMB=160 T_TERM_FONT="Monospace 15" ;;
		larger) T_FONT_SIZE=24 T_CURSOR_SIZE=48 T_PANEL_ICON=68 T_TASK_WIDTH=300 T_TB_ICON=48 \
		        T_FOLDER_ICON=96 T_SMALL_ICON=48 T_PANE_ICON=48 T_THUMB=192 T_TERM_FONT="Monospace 20" ;;
		*)      T_FONT_SIZE=12 T_CURSOR_SIZE=24 T_PANEL_ICON=36 T_TASK_WIDTH=200 T_TB_ICON=24 \
		        T_FOLDER_ICON=48 T_SMALL_ICON=24 T_PANE_ICON=24 T_THUMB=80 T_TERM_FONT="Monospace 10" ;;
	esac
	# GTK's toolbar icon size for the size, as the Appearance Settings set it
	# (small toolbar at Small, dialog at Large and Larger, else large toolbar)
	case $T_TB_ICON in 16) T_TB_SIZE=2 ;; 48) T_TB_SIZE=6 ;; *) T_TB_SIZE=3 ;; esac
	# Raspberry Pi OS 12 and 13 give the Large and Larger sizes the theme's
	# large window theme, <theme>_l (14-pixel title bar buttons instead of 8;
	# PiX has none), 17-pixel scrollbars and 20-pixel invisible resize
	# borders (its Appearance Settings: scrollbar width 17); otherwise its
	# Openbox's 10-pixel borders.
	T_OB=$T_GTK T_HANDLE=10 T_SCROLL=0
	if [[ ${O_SIZE:-medium} == large || ${O_SIZE:-medium} == larger ]]; then
		T_HANDLE=20 T_SCROLL=17
		[[ $T_GTK == PiX ]] || T_OB=${T_GTK}_l
	fi
	if [[ $T_ERA == trixie ]]; then
		T_FONT_FAMILY="Nunito Sans" T_FONT_WEIGHT=Light T_FONT="Nunito Sans Light $T_FONT_SIZE"
	else
		T_FONT_FAMILY=PibotoLt T_FONT_WEIGHT=Normal T_FONT="PibotoLt $T_FONT_SIZE"
	fi
	# The default wallpaper of the look in Raspberry Pi OS, as PACKAGE/FILE
	# under $WALLS: PiXflat's is Bookworm's, PiX's Raspbian Stretch's.
	case $T_ERA in
		trixie)   T_WALL_DEFAULT="rpd-wallpaper-trixie/sunrise.jpg" ;;
		legacy)   T_WALL_DEFAULT="rpd-wallpaper/road.jpg" ;;
		*)        T_WALL_DEFAULT="rpd-wallpaper/fisherman.jpg" ;;
	esac
	# The adapted icon set, with the Debian logo and the icon names that
	# Debian's programs use (see gen_icon_overlay).
	T_ICONS=$T_ICON_BASE-Debian
	# Dark themes show Debian's white logo, where Debian ships it
	if (( T_DARK )) && _white_logo; then T_ICONS=$T_GTK-Debian; fi
	# Values that Raspberry Pi OS uses (raspberrypi-ui-mods, rpd-x-core).
	T_COLOR_SCHEME='selected_bg_color:#878791919b9b\nselected_fg_color:#f0f0f0f0f0f0\nbar_bg_color:#ededececebeb\nbar_fg_color:#000000000000\n'
	T_DESK_BG="#d6d6d3d3dede" T_DESK_FG="#e8e8e8e8e8e8" T_DESK_SHADOW="#d6d6d3d3dede"
	T_SOUND_THEME=freedesktop   # Raspberry Pi OS enables event sounds with this theme
}

# Print the Raspberry Pi OS packages for a release: every theme with its icons,
# fonts, GTK 2 engines and wallpapers, also those of earlier releases,
# Raspberry Pi's Openbox (PI_WM), and Raspberry Pi's own panel and file
# manager where this script knows the release's desktop (pi_apps,
# DESKTOP_KNOWN).
# Usage: rpi_pkgs SUITE ARCH
rpi_pkgs() {
	local s n
	printf '%s\n' pixflat-theme pixtrix-theme pix-theme pixflat-icons pixtrix-icons rpd-icons \
		gtk2-engines-pixflat gtk2-engines-clearlookspix fonts-piboto fonts-nunito-sans
	printf '%s\n' "${PI_WM[@]}"
	qt_pkgs
	rpi_new_looks "$1" "$2"
	# The wallpaper sets (no code) of this and every earlier release: the
	# standard and 4K sets, any set released later and the Cambridge
	# wallpapers (not its screensaver), each in its own folder under $WALLS
	# (see wallpaper_links). Transitional packages are left out.
	for s in $(releases); do
		suite_ge "$1" "$s" || continue
		index_load "$s" "$2" || continue
		for n in $(index_names "$s" "$2" | grep -xE 'rpd-wallpaper[a-z0-9-]*|cantab-wallpaper' | grep -v -- '-dbgsym$'); do
			index_transitional "$WORKDIR/index/$s/Packages-$2" "$n" || echo "$n"
		done
	done | awk '!seen[$0]++'
	if (( DESKTOP_KNOWN )); then pi_apps "$1" "$2"; fi
	if (( WAYLAND )); then wl_apps "$1" "$2"; fi
}

# Succeed if a package of an index file is an empty transitional or dummy
# package, which brings nothing of its own. Usage: index_transitional FILE PACKAGE
index_transitional() {
	awk -v p="$2" 'BEGIN { RS = ""; FS = "\n" } index($0, "Package: " p "\n") == 1 {
		for (i = 1; i <= NF; i++) if ($i ~ /^Description: / && tolower($i) ~ /transitional|dummy/) found = 1 }
		END { exit !found }' "$1"
}

# Print the look packages of this and every earlier release that rpi_pkgs
# does not name, such as those released after this script was written: what
# rpd-theme asks for (Raspberry Pi OS's own list of its look), and every
# package named like its themes, icons, cursors, GTK 2 engines and fonts.
# Left out: Debian's own packages, debug symbols and transitional packages,
# and, from earlier releases, packages with compiled code (as in resolve_pkg).
# A release with none of them gives nothing, not an error.
# Usage: rpi_new_looks SUITE ARCH
rpi_new_looks() {
	local s f p a want known='pixflat-theme|pixtrix-theme|pix-theme|pixflat-icons|pixtrix-icons|rpd-icons|gtk2-engines-pixflat|gtk2-engines-clearlookspix|fonts-piboto|fonts-nunito-sans'
	for s in $(releases); do
		suite_ge "$1" "$s" || continue
		index_load "$s" "$2" || continue
		f=$WORKDIR/index/$s/Packages-$2
		want=$({
			awk 'BEGIN { RS = ""; FS = "\n" } index($0, "Package: rpd-theme\n") == 1 {
				for (i = 1; i <= NF; i++) if ($i ~ /^(Depends|Recommends): /) { sub(/^[^:]*: /, "", $i); print $i } }' "$f" | depnames
			sed -nE 's/^Package: (pix[a-z0-9]*-(theme|icons)|rpd-icons[a-z0-9-]*|[a-z0-9-]+-cursors?(-theme)?|gtk2-engines-(pix|clearlookspix)[a-z0-9]*|fonts-[a-z0-9-]+)$/\1/p' "$f"
		} | awk -v re="^($known|.*wallpaper.*|.*-dbgsym)\$" '$0 !~ re' | sort -u | paste -sd' ' -)
		# Each wanted package that is not transitional, with its architecture
		W=" $want " awk 'BEGIN { RS = ""; FS = "\n" } {
			p = a = ""; t = 0
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^Package: /) p = substr($i, 10)
				else if ($i ~ /^Architecture: /) a = substr($i, 15)
				else if ($i ~ /^Description: / && tolower($i) ~ /transitional|dummy/) t = 1
			}
			if (!t && index(ENVIRON["W"], " " p " ")) print p, a }' "$f" | sort -u \
			| while read -r p a; do
				[[ $s == "$1" || $a == all || " ${DATA_PKGS[*]} " == *" $p "* ]] || continue
				_debian_has "$p" || printf '%s\n' "$p"
			done
	done | awk '!seen[$0]++'
}

# Print the Debian packages of the X server, which the login screen always
# needs, and Mesa's 3D drivers.
x11_debs() { printf '%s\n' xserver-xorg x11-utils libgl1-mesa-dri; }
# Print the Debian packages of the login screen: LightDM with Debian's greeter
# in the Raspberry Pi OS style, where no other display manager is in use, and
# Debian's login artwork (desktop-base).
login_debs() {
	if [[ -z $H_DM || $H_DM == lightdm ]]; then printf '%s\n' lightdm lightdm-gtk-greeter; fi
	echo desktop-base
}

# Succeed if this script knows Raspberry Pi OS's X desktop of a release: its
# rpd-x-core runs Raspberry Pi's panel (lxpanel-pi) and holds the panel's
# layout, and the release has its file manager (pcmanfm-pi). A desktop of a
# new design is not guessed at. Usage: desktop_known SUITE ARCH
desktop_known() {
	local deps x
	index_load "$1" "$2" || return 1
	deps=$(index_candidates "$1" "$2" "$PANEL_PKG" | first_line | cut -f6 | depnames)
	grep -qx lxpanel-pi <<<"$deps" && grep -qx pcmanfm-pi <<<"$(index_names "$1" "$2")" || return 1
	x=$(pi_unpack "$PANEL_PKG" "$1" "$2") || die "cannot download Raspberry Pi OS $1's desktop package ($PANEL_PKG); check the network and run this again"
	[[ -f $x/$PANEL_LAYOUT ]]
}

# Raspberry Pi's own desktop programs that the session uses: the file manager,
# which draws the desktop and is installed beside Debian's (see beside_build),
# the Shutdown and Run dialogs and the panel.
readonly PI_APPS="pcmanfm-pi pishutdown gui-runcmd lxpanel-pi"
# The other Raspberry Pi packages that its desktop packages (rpd-x-core,
# rpd-common) depend on, left out on purpose: they set up a Raspberry Pi's
# boot splash, login screen, system tools or firmware, and would change
# Debian's own (see desktop_unknown).
readonly DESKTOP_SKIP="rpd-common pi-greeter rpd-plym-splash rpi-gui-nop gui-pkinst pprompt raspi-config firmware-brcm80211"

# Print Raspberry Pi's own programs (PI_APPS), and the panel's plugins: those
# of its layout (see _pi_panel_layout) and every other plugin that Raspberry
# Pi OS installs (rpd-x-core) and that works on Debian. Debian's panel and its
# plugins stay installed. The magnifier plugin comes with the program it
# starts (magnifier_pkg), or not at all. Usage: pi_apps SUITE ARCH
pi_apps() {
	local t mag drop
	drop=$(panel_drop)
	mag=$(magnifier_pkg "$1" "$2")
	[[ -n $mag ]] || drop+="|magnifier"
	# shellcheck disable=SC2086  # a list of names
	printf '%s\n' $PI_APPS
	{
		for t in $(panel_plugins "$1" "$2" | grep -vxE "$drop"); do printf 'lpplug-%s\n' "${t/#smenu/menu}"; done
		index_candidates "$1" "$2" "$PANEL_PKG" 2>/dev/null | first_line | cut -f6 | depnames \
			| grep '^lpplug-' | grep -vxE "lpplug-($drop)" | sed 's/^lpplug-//' | _no_battery | sed 's/^/lpplug-/' || true
		[[ -z $mag ]] || echo "$mag"
	} | awk '!seen[$0]++'
}
# Print the magnifier program that Raspberry Pi OS's magnifier plugin starts
# (mage-rpi), where the release has it. Raspberry Pi OS installs the plugin
# and offers the program in Recommended Software; here both are installed,
# with the plugin off the panel (see _pi_layout), for the user to add.
# Usage: magnifier_pkg SUITE ARCH
magnifier_pkg() { if grep -qx mage-rpi <<<"$(index_names "$1" "$2")"; then echo mage-rpi; fi; }

# Succeed if this script knows Raspberry Pi OS's Wayland desktop of a release
# and Debian can run it unchanged: its desktop package (WL_PKG) runs labwc and
# Raspberry Pi's panel (wf-panel-pi) and holds their settings, and Debian has
# labwc. Raspberry Pi's own labwc is not used: it needs newer core libraries
# than Debian's. Usage: wayland_known SUITE ARCH
wayland_known() {
	local deps x
	index_load "$1" "$2" || return 1
	deps=$(index_candidates "$1" "$2" "$WL_PKG" | first_line | cut -f6 | depnames)
	grep -qx labwc <<<"$deps" && grep -qx wf-panel-pi <<<"$deps" && apt_has labwc || return 1
	x=$(pi_unpack "$WL_PKG" "$1" "$2") || die "cannot download Raspberry Pi OS $1's desktop package ($WL_PKG); check the network and run this again"
	[[ -f $x/etc/xdg/labwc/rc.xml && -f $x/etc/xdg/wf-panel-pi/wf-panel-pi.ini ]]
}

# Raspberry Pi's own programs of the Wayland session: its panel, the
# screenshot tool that the Print key starts (gui-screenshot) and its screen
# lock (swaylock, repacked beside Debian's as swaylock-pi, see TWIN_RE).
readonly WL_APPS="wf-panel-pi gui-screenshot swaylock"
# The other Raspberry Pi packages of its Wayland desktop package that are
# left out: they set up a Raspberry Pi (touch screens on its display
# connectors, raspi-config).
readonly WL_SKIP="autotouch"

# Print Raspberry Pi's packages of the Wayland session: its programs
# (WL_APPS) and the panel plugins that its desktop package installs, less
# those the X session leaves out (panel_drop), Raspberry Pi Connect's (a
# service this look does not install) and the battery's without a battery.
# Usage: wl_apps SUITE ARCH
wl_apps() {
	# shellcheck disable=SC2086  # a list of names
	printf '%s\n' $WL_APPS
	index_candidates "$1" "$2" "$WL_PKG" 2>/dev/null | first_line | cut -f6 | depnames \
		| grep '^wfplug-' | grep -vxE "wfplug-($(panel_drop)|connect)" | sed 's/^wfplug-//' | _no_battery | sed 's/^/wfplug-/' || true
}
# Print the Debian packages of the Wayland session: labwc (with Xwayland),
# display layout (kanshi, wlr-randr), the GTK settings of X programs
# (xsettingsd) and the on-screen
# keyboard, which the session starts only with a touch screen.
wayland_debs() {
	(( WAYLAND )) || return 0
	printf '%s\n' labwc kanshi wlr-randr xsettingsd squeekboard
}

# Print the packages that Raspberry Pi OS's desktop packages depend on and
# that this script does not know: in Raspberry Pi's archive only, neither
# taken (PI_APPS, the panel plugins) nor left out on purpose (DESKTOP_SKIP).
# A new desktop program is thus noted, not installed unchecked, since such a
# package may as well set up a Raspberry Pi's system.
# Usage: desktop_unknown SUITE ARCH
desktop_unknown() {
	local p t names
	names=$(index_names "$1" "$2")
	for p in $(for t in "$PANEL_PKG" "$ART_PKG" $( (( ! WAYLAND )) || echo "$WL_PKG"); do index_candidates "$1" "$2" "$t" | first_line | cut -f6; done | depnames); do
		[[ " $PI_APPS $QT_STYLES $DESKTOP_SKIP $WL_APPS $WL_SKIP " != *" $p "* && $p != lpplug-* && $p != wfplug-* ]] || continue
		if grep -qxF -- "$p" <<<"$names" && ! _debian_has "$p"; then echo "$p"; fi
	done
}

# Print the plugin types of Raspberry Pi OS's panel layout (PANEL_LAYOUT in
# PANEL_PKG) that work on Debian, without the panel program's own.
# Usage: panel_plugins SUITE ARCH
panel_plugins() {
	local f
	f=$(pi_unpack "$PANEL_PKG" "$1" "$2" 2>/dev/null) && f+=/$PANEL_LAYOUT && [[ -f $f ]] || return 0
	sed -n 's/^[[:space:]]*type=//p' "$f" | grep -vxE "$(panel_drop)|space|separator|launchbar|taskbar|tray" | awk '!seen[$0]++' | _no_battery
}

# Copy plugin types from stdin, without the battery plugins where this
# computer has no battery.
_no_battery() { if has_battery; then cat; else grep -vxE 'batt|ptbatt' || true; fi; }

# Succeed if this computer has a battery of its own (not that of a mouse or a
# keyboard).
has_battery() {
	local d
	for d in /sys/class/power_supply/*; do
		[[ $(cat "$d/type" 2>/dev/null) == Battery && $(cat "$d/scope" 2>/dev/null) != Device ]] && return 0
	done
	return 1
}
# Print the panel plugins left out (grep -E alternatives): the updater (needs
# Raspberry Pi's system tools), power (reports Raspberry Pi supply problems),
# gpu (reads only a Raspberry Pi's GPU) and the network plugin unless it is
# used (USE_NETMAN).
panel_drop() { if (( USE_NETMAN )); then echo "updater|power|gpu"; else echo "updater|power|gpu|netman"; fi; }
# Raspberry Pi's build of Openbox, installed beside Debian's (beside_build)
# and started by the session only: it keeps a window's corners rounded while
# the window is moved or resized, as on Raspberry Pi OS; Debian's carries
# Raspberry Pi's earlier patch, whose corners turn square until the frame is
# redrawn. Its theme library adds a field (corner_radius) inside the RrTheme
# structure, so a program built for Debian's library must never load it:
# beside Debian's, it has its own library names, and Debian's obconf and
# lxappearance-obconf keep Debian's libraries.
readonly PI_WM=(openbox libobrender32v5)
# Print the Debian packages of the X session: the LXDE session manager,
# window manager, panel and file manager (also the fallback for Raspberry
# Pi's), gvfs for Trash and drives in the file managers, the appearance
# settings, and dconf for the session's settings. Raspberry Pi OS's xcompmgr
# needs an option that Debian's lacks; with NVIDIA's own driver, an installed
# picom is the compositor (compositor_build). picom is not installed: its
# autostart entry would start it in every session.
session_debs() {
	printf '%s\n' lxsession lxpolkit openbox lxpanel pcmanfm gvfs-backends gvfs-fuse lxappearance dconf-cli libglib2.0-bin python3
}
# Print the Debian packages the themes need: the GTK 2 pixmap engine and
# runtime, the icon sets that the Raspberry Pi sets inherit, the sound theme
# and Liberation Mono, the monospace font of Raspberry Pi OS.
theme_debs() {
	printf '%s\n' gtk2-engines-pixbuf libgtk2.0-bin gnome-icon-theme adwaita-icon-theme-legacy sound-theme-freedesktop fonts-liberation
}
# Raspberry Pi OS's GTK 2 styles for Qt 5 and Qt 6 programs (rpd-common), as
# its builds for this release. Both register the platform theme "gtk2", which
# the session alone names (QT_QPA_PLATFORMTHEME, see _session_programs).
# Raspberry Pi OS's qt5ct and qt6ct are not used: Debian's qt5ct sets itself
# up for every X session.
readonly QT_STYLES="qt5-style-plugins qt6gtk2"
# The packages of those styles, Raspberry Pi's builds they need included
readonly QT_STYLE_RE='qt5-style-plugins|qt5-style-plugin-[a-z]+|qt5-gtk2-platformtheme|qt6gtk2'
# The session's Qt platform theme: "gtk2", or "gtk3" where Raspberry Pi has no
# build of a style for this Debian's Qt version (qt_choose)
QT_THEME=gtk2
# Print the Qt styles that Debian lacks, from Raspberry Pi (qt_pkgs), or those
# Debian has, from the APT sources (qt_debs): with "gtk3", Debian's GTK 3
# platform themes for Qt 5 and Qt 6, which Raspberry Pi OS 13 also installs.
# APT brings the Qt libraries they need. Either way the session's platform
# theme has its plugin.
qt_pkgs() {
	local p
	for p in $QT_STYLES; do _debian_has "$p" || echo "$p"; done
}
qt_debs() {
	local p
	if [[ $QT_THEME == gtk3 ]]; then printf '%s\n' qt5-gtk-platformtheme qt6-gtk-platformtheme; return 0; fi
	for p in $QT_STYLES; do if _debian_has "$p"; then echo "$p"; fi; done
}
# Choose the session's Qt platform theme from the packages to fetch
# (FETCH_PKGS): where a GTK 2 style has no build for this Debian's Qt version
# (testing's Qt is often newer), Qt 5 and Qt 6 programs both use Debian's GTK 3
# platform themes, and the other style is not fetched.
qt_choose() {
	local p kept=()
	for p in $QT_STYLES; do
		_debian_has "$p" || [[ " ${FETCH_PKGS[*]} " == *" $p "* ]] || QT_THEME=gtk3
	done
	[[ $QT_THEME == gtk3 ]] || return 0
	for p in "${FETCH_PKGS[@]}"; do [[ $p =~ ^($QT_STYLE_RE)$ ]] || kept+=("$p"); done
	FETCH_PKGS=("${kept[@]}")
	note "Qt programs follow the GTK theme through Debian's GTK 3 platform themes: Raspberry Pi OS has no GTK 2 style built for this Debian's Qt version."
}
# Succeed if this computer has a Wi-Fi adapter.
has_wifi() { compgen -G '/sys/class/ieee80211/*' >/dev/null; }
# Succeed if NetworkManager runs the network: it is installed, and enabled or
# the only network manager (wicd and ConnMan are the others).
nm_runs() {
	[[ -n $(installed_version network-manager) ]] || return 1
	[[ -z $(installed_version connman)$(installed_version wicd) ]] \
		|| systemctl is-enabled --quiet NetworkManager.service 2>/dev/null
}
# Succeed if this computer has a Bluetooth adapter, or a Bluetooth radio that
# rfkill blocks (some laptops power the adapter off while it is blocked).
has_bluetooth() {
	local t
	compgen -G '/sys/class/bluetooth/hci*' >/dev/null && return 0
	for t in /sys/class/rfkill/rfkill*/type; do
		[[ -r $t && $(<"$t") == bluetooth ]] && return 0
	done
	return 1
}

# Print the Debian packages for the panel's network and Bluetooth icons, as on
# Raspberry Pi OS. With Raspberry Pi's network plugin
# (USE_NETMAN) and a Wi-Fi adapter: NetworkManager and the Wi-Fi tools, unless
# another network manager is installed. Debian's tray icon (nm-applet) is not
# installed: its autostart entry would start it in every session. With a
# Bluetooth adapter: BlueZ and Bluetooth audio for the sound server in use;
# Raspberry Pi's panel has its own Bluetooth plugin.
tray_debs() {
	local rfkill=0
	if (( USE_NETMAN )) && [[ -z $(installed_version network-manager) ]] && has_wifi \
		&& [[ -z $(installed_version connman)$(installed_version wicd) ]]; then
		rfkill=1
		# dnsmasq-base: NetworkManager's shared connections, the network
		# plugin's hotspot (Raspberry Pi OS has it through Recommends)
		printf '%s\n' network-manager wpasupplicant iw wireless-regdb rfkill dnsmasq-base
	fi
	if has_bluetooth; then
		echo bluez
		(( rfkill )) || echo rfkill
		if [[ -n $(installed_version pipewire) ]]; then echo libspa-0.2-bluetooth; fi
		if [[ -n $(installed_version pulseaudio) ]]; then echo pulseaudio-module-bluetooth; fi
	fi
}
# Leave out of the install set (APT_PKGS, HW_PKGS, ROOT_PKGS) what
# tray_debs gives only for Raspberry Pi's network plugin, once the plugin is
# left out (USE_NETMAN is 0): NetworkManager and the Wi-Fi tools, which
# nothing else of the look uses. A NetworkManager installed already stays.
netman_debs_drop() {
	local p
	local -a gone=()
	mapfile -t gone < <(LC_ALL=C comm -23 <(USE_NETMAN=1 tray_debs | LC_ALL=C sort -u) <(USE_NETMAN=0 tray_debs | LC_ALL=C sort -u))
	(( ${#gone[@]} )) || return 0
	[[ " ${APT_PKGS[*]} " != *" network-manager "* ]] || info "NetworkManager is not installed: only the network plugin would use it"
	mapfile -t APT_PKGS < <(for p in "${APT_PKGS[@]}"; do [[ " ${gone[*]} " == *" $p "* ]] || echo "$p"; done)
	mapfile -t HW_PKGS < <(for p in "${HW_PKGS[@]}"; do [[ " ${gone[*]} " == *" $p "* ]] || echo "$p"; done)
	mapfile -t ROOT_PKGS < <(for p in "${ROOT_PKGS[@]}"; do [[ " ${gone[*]} " == *" $p "* ]] || echo "$p"; done)
}
# Print the Debian packages for sound, where a sound card exists and no sound
# server is installed: PipeWire, whose PulseAudio interface Raspberry Pi OS's
# volume plugin needs.
audio_debs() {
	compgen -G '/sys/class/sound/card*' >/dev/null || return 0
	[[ -z $(installed_version pipewire-pulse)$(installed_version pulseaudio) ]] || return 0
	echo pipewire-audio
}

# Load the Debian release numbers (REL_VER) and life cycle (REL_DATES: a
# major version mapped to "RELEASE EOL EOL-LTS" dates, "-" when not known):
# the built-in tables, then Debian's distro-info-data, then Debian's current
# table saved by update_release_table. Each adds to and corrects the one
# before, so that releases named later are known too.
declare -gA REL_VER=() REL_DATES=()
load_releases() {
	local e v rel eol lts
	for e in "${KNOWN_RELEASES[@]}"; do REL_VER[${e#*:}]=${e%%:*}; done
	for e in "${KNOWN_LIFECYCLE[@]}"; do IFS=: read -r v rel eol lts <<<"$e"; _rel_dates "$v" "$rel" "$eol" "$lts"; done
	_release_csv /usr/share/distro-info/debian.csv
	_release_csv "$(release_cache)"
}

# Read a release table in distro-info-data's debian.csv format into REL_VER
# and REL_DATES, as data only. Rows without a numeric version and a lowercase
# codename are skipped, and dates not in the form YYYY-MM-DD are ignored.
# Usage: _release_csv FILE
_release_csv() {
	local v c rel eol lts
	[[ -r $1 ]] || return 0
	while IFS=, read -r v _ c _ rel eol lts _; do
		[[ $v =~ ^[0-9]+(\.[0-9]+)*$ && $c =~ ^[a-z]+$ ]] || continue
		REL_VER[$c]=${v%%.*}
		[[ $rel =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
		_rel_dates "${v%%.*}" "$rel" "$eol" "$lts"
	done <"$1"
}

# Set the life cycle dates of a major version in REL_DATES, field by field:
# a date that is missing or not in the form YYYY-MM-DD keeps the one known
# before (old distro-info-data has rows without end dates).
# Usage: _rel_dates VERSION RELEASE EOL EOL-LTS
_rel_dates() {
	local i date='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
	local -a old new=("$2" "$3" "$4")
	read -r -a old <<<"${REL_DATES[$1]:-- - -}"
	for i in 0 1 2; do [[ ${new[i]} =~ $date ]] || new[i]=${old[i]:--}; done
	REL_DATES[$1]="${new[*]}"
}

# Print the path of the saved copy of Debian's release table.
release_cache() { printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/$APP_NAME/debian.csv"; }

# Save Debian's current release table (RELEASES_URL) for load_releases, at most
# once a day, in the user's cache folder when it exists. Any failure keeps the
# saved copy and is shown only with --verbose.
update_release_table() {
	local f new
	f=$(release_cache)
	[[ -d ${f%/*/*} && -z $(find "$f" -mmin -1440 2>/dev/null) ]] || return 0
	new=$f.new
	if mkdir -p -- "${f%/*}" && fetch_extra "$RELEASES_URL" 65536 >"$new" && _release_table_ok "$new"; then
		mv -f -- "$new" "$f"
	else
		rm -f -- "$new"
		debug "Debian's release table could not be read online; using the saved or built-in one"
	fi
}

# Succeed if a file is a complete debian.csv: its header, a final newline and
# Debian 13's row. Usage: _release_table_ok FILE
_release_table_ok() {
	[[ $(head -n 1 -- "$1") == version,codename,series,created,release,eol* && -z $(tail -c 1 -- "$1") ]] \
		&& grep -q '^13,Trixie,trixie,' -- "$1"
}

# Print the major version of the current Debian stable release: the newest
# one released by today, from REL_DATES.
stable_rank() {
	local v rel today best=0
	printf -v today '%(%Y-%m-%d)T' -1
	for v in "${!REL_DATES[@]}"; do
		read -r rel _ <<<"${REL_DATES[$v]}"
		[[ $rel == - || $rel > $today ]] || (( v <= best )) || best=$v
	done
	echo "$best"
}
# Print the Debian releases from Debian $OLDEST on, newest first.
releases() {
	local c
	for c in "${!REL_VER[@]}"; do if (( REL_VER[$c] >= OLDEST )); then echo "${REL_VER[$c]} $c"; fi; done | sort -rn | cut -d' ' -f2
}
# Succeed if the first release is the second one or newer, without subshells.
# Usage: suite_ge SUITE OTHER-SUITE
suite_ge() { local a=0 b=0; [[ -z $1 ]] || a=${REL_VER[$1]:-0}; [[ -z $2 ]] || b=${REL_VER[$2]:-0}; (( a >= b )); }

# The session's names, as in Raspberry Pi OS: its lxsession profile, the
# prefix of its application menu file and its Openbox settings file. The
# names of Raspberry Pi OS 10 to 12 (LXDE-pi), which rpios-look-legacy.sh
# uses, are only removed (see reset_session_settings).
readonly SESSION_PROFILE="rpd-x" MENU_PREFIX="rpd-" OB_FILE="rpd-rc.xml"

# Print a field of /etc/os-release, without quotes. Usage: os_release KEY
os_release() { sed -n "s/^$1=//p" /etc/os-release | first_line | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"; }

# Detect the architecture, the distribution and the computer.
detect_host() {
	command -v dpkg >/dev/null && command -v apt-get >/dev/null || die "Debian is needed (dpkg and apt not found)"
	H_ARCH=$(dpkg --print-architecture)
	[[ $H_ARCH =~ ^($PC_ARCHES)$ ]] || die "this script is for 32-bit (x86, i386) and 64-bit (x64, amd64) PCs; this system is $H_ARCH"
	if [[ -r /etc/os-release ]]; then
		H_ID=$(os_release ID)
		H_CODENAME=$(os_release VERSION_CODENAME) H_PRETTY=$(os_release PRETTY_NAME)
	fi
	[[ $H_ID == debian ]] || die "rpios-look supports Debian with LXDE only; this system is ${H_PRETTY:-unknown}"
	detect_machine
}

# Detect the computer: model, processor, memory, graphics, kernel, installed
# LXDE desktop and display manager.
detect_machine() {
	local d drv slot name p
	local -a dmi=(product_name)
	H_KERNEL=$(uname -r)
	H_MODEL=""
	if [[ -r /sys/class/dmi/id/product_name ]]; then
		# Lenovo keeps the model name in product_version; other vendors keep a
		# revision there. Placeholders such as "To be filled by O.E.M." are dropped.
		[[ $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) != LENOVO ]] || dmi=(product_version product_name)
		H_MODEL=$(cd /sys/class/dmi/id && cat sys_vendor "${dmi[@]}" 2>/dev/null \
			| grep -viE '^[[:space:]]*((to be filled|system (product|manufacturer|version)|default string|not specified).*|none[[:space:]]*)?$' \
			| awk '!seen[$0]++' | paste -sd' ' - || true)
	fi
	H_CPU=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | first_line)
	[[ -n $H_CPU ]] || H_CPU=$(uname -m)
	H_CPU="$(tr -s ' ' <<<"$H_CPU") ($(nproc 2>/dev/null || echo 1) cores)"
	H_MEM_MB=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
	H_VIRT=$(systemd-detect-virt 2>/dev/null || true)
	[[ -n $H_VIRT ]] || H_VIRT=none
	# The first real graphics driver, not the boot framebuffer.
	H_GPU="" H_GPU_DRV="" H_GPU_DRVS=""
	for d in /sys/class/drm/card[0-9]*; do
		[[ ${d##*/} != *-* && -e $d/device/driver ]] || continue
		drv=$(basename "$(readlink -f "$d/device/driver")")
		H_GPU_DRVS+=" $drv"
		[[ -z $H_GPU_DRV && $drv != simple-framebuffer && $drv != simpledrm && $drv != efi-framebuffer ]] || continue
		H_GPU_DRV=$drv name=""
		slot=$(sed -n 's/^PCI_SLOT_NAME=//p' "$d/device/uevent" 2>/dev/null)
		if [[ -n $slot ]] && command -v lspci >/dev/null; then name=$(lspci -s "$slot" 2>/dev/null | cut -d: -f3- | sed 's/^ *//; s/ (rev [0-9a-f]*)$//'); fi
		H_GPU=${name:-$drv}
	done
	# NVIDIA's driver may not register a DRM card.
	if [[ -z $H_GPU_DRV && -d /sys/module/nvidia ]]; then H_GPU_DRV=nvidia H_GPU="NVIDIA"; fi
	[[ -n $H_GPU_DRV ]] || H_GPU_DRV=$(awk '{ print $1 }' <<<"$H_GPU_DRVS")
	# Debian's LXDE desktop: its task, metapackage or core
	H_LXDE=0
	for p in task-lxde-desktop lxde lxde-core; do [[ -z $(installed_version "$p") ]] || { H_LXDE=1; break; }; done
	H_DM=$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service 2>/dev/null)
	[[ -n $H_DM && $H_DM != display-manager ]] || H_DM=$(basename "$(cat /etc/X11/default-display-manager 2>/dev/null)" 2>/dev/null)
}

# Print the detected computer.
print_machine() {
	local mem
	mem=$(awk -v m="$H_MEM_MB" 'BEGIN { if (m >= 1024) printf "%.1f GB", m / 1024; else printf "%d MB", m }')
	step "This computer"
	[[ -z $H_MODEL ]] || log "  Model        $H_MODEL"
	log "  Processor    $H_CPU"
	log "  Memory       $mem"
	log "  Graphics     ${H_GPU:-none found} (${H_GPU_DRV:-no driver})"
	[[ $H_VIRT == none ]] || log "  Virtual      $H_VIRT"
	log "  System       ${H_PRETTY:-unknown}, $H_ARCH, kernel $H_KERNEL"
	log "  Desktop      $( (( H_LXDE )) && echo LXDE || echo "no LXDE")${H_DM:+; login screen: $H_DM}"
	_print_look
}

# Print the theme, icons and size that the running user's Raspberry Pi
# Desktop session uses, when the look is installed: the user's own choice
# (rpios-look-set, Customize Look and Feel), else the session's default; and the
# Raspberry Pi OS release that its packages come from.
_print_look() {
	local f k v theme="" icons="" size
	for f in "${XDG_CONFIG_HOME:-$HOME/.config}/lxsession/$SESSION_PROFILE/desktop.conf" \
		"$SHARE/xdg/lxsession/$SESSION_PROFILE/desktop.conf"; do
		[[ -f $f ]] || continue
		while IFS='=' read -r k v; do
			case $k in
				sNet/ThemeName)     [[ -n $theme ]] || theme=$v ;;
				sNet/IconThemeName) [[ -n $icons ]] || icons=$v ;;
			esac
		done <"$f"
	done
	[[ -n $theme && -n $(installed_version "$APP_PKG") ]] || return 0
	size=$(sed -n 's/^size=//p' "$SYS_DIR/options" 2>/dev/null | first_line) || size=""
	local wm panel fm now=""
	wm=$(installed_version "${BESIDE_PREFIX}openbox") wm=${wm%%-*}
	[[ -n $wm ]] || { wm=$(installed_version openbox) wm=${wm%%-*}; }
	panel="lxpanel-pi $(installed_version lxpanel-pi)" fm="pcmanfm-pi $(installed_version pcmanfm-pi)"
	if [[ ${XDG_SESSION_DESKTOP:-} == "$SESSION_ID" ]] || _in_wl_session; then now="running now"
	elif [[ -n ${XDG_SESSION_DESKTOP:-} ]]; then now="running now: ${XDG_SESSION_DESKTOP}"; fi
	log "  Session      Raspberry Pi Desktop on X${now:+, $now}"
	[[ ! -e /usr/share/wayland-sessions/$WL_SESSION_ID.desktop ]] || log "               and on Wayland (labwc $(installed_version labwc | sed 's/-.*//'), panel wf-panel-pi $(installed_version wf-panel-pi))"
	log "               Openbox ${wm:-?}, panel ${panel% }, file manager ${fm% }"
	log "  Look         $theme theme${icons:+, $icons icons}, ${size:-medium} size"
	log "  Packages     Raspberry Pi OS ${REL_VER[$H_SUITE]:+${REL_VER[$H_SUITE]} }($H_SUITE), $H_ARCH"
}

# Print the major Debian version of this system: from os-release, otherwise
# (testing, unstable) from /etc/debian_version, which names the release
# followed ("forky/sid", "13.1"); fail if it is unknown.
host_rank() {
	local v
	if [[ -n $H_CODENAME && $H_CODENAME != sid && -n ${REL_VER[$H_CODENAME]:-} ]]; then echo "${REL_VER[$H_CODENAME]}"; return; fi
	v=$(cat /etc/debian_version 2>/dev/null) v=${v%%/*}
	if [[ -n $v && -n ${REL_VER[$v]:-} ]]; then echo "${REL_VER[$v]}"
	elif [[ $v =~ ^[0-9]+ ]]; then echo "${v%%.*}"
	elif [[ $(os_release VERSION_ID) =~ ^[0-9]+$ ]]; then os_release VERSION_ID
	else return 1; fi
}

# Stop, before anything changes, unless this script installs on this system:
# Debian $HOST_OLDEST or later on $INSTALL_ARCH. Others are pointed to the
# legacy script.
require_host() {
	local rank legacy="use $LEGACY_SCRIPT from $LEGACY_URL: it supports Debian 9 to 12, also on 32-bit PCs"
	rank=$(host_rank) || die "this script supports Debian $HOST_OLDEST and later; this release is unknown (${H_PRETTY:-no /etc/os-release})"
	(( rank >= HOST_OLDEST )) || die "this script supports Debian $HOST_OLDEST and later; this system is ${H_PRETTY:-Debian $rank}. For Debian 9 to 12, $legacy"
	[[ $H_ARCH == "$INSTALL_ARCH" ]] || die "Debian $HOST_OLDEST and later support only 64-bit PCs (x64, amd64); this system is $H_ARCH. $LEGACY_SCRIPT ($LEGACY_URL) supports 32-bit PCs up to Debian 12"
}

# Stop, before Debian's release table is downloaded, when the built-in tables
# show already that require_host refuses this system: the wrong architecture
# or a release before Debian $HOST_OLDEST. A release named after the built-in
# tables (a new testing) passes here, for require_host to check.
require_host_early() {
	local rank
	[[ $H_ARCH == "$INSTALL_ARCH" ]] || require_host
	rank=$(host_rank) || return 0
	(( rank >= HOST_OLDEST )) || require_host
}

# Choose the Raspberry Pi OS release for this system: the newest release, from
# Debian $HOST_OLDEST up to this Debian release, for which Raspberry Pi
# publishes the themes. A Debian release that Raspberry Pi OS has not reached
# yet thus uses the newest Raspberry Pi OS, and moves on once Raspberry Pi
# publishes its own.
pick_suite() {
	local rank s
	rank=$(host_rank) || die "this Debian release is unknown (${H_PRETTY:-no /etc/os-release})"
	H_SUITE=""
	for s in $(releases); do
		(( REL_VER[$s] >= HOST_OLDEST )) || break
		rpi_populated "$s" || continue
		H_SUITE=$s
		(( REL_VER[$s] > rank )) || break
	done
	[[ -n $H_SUITE ]] || die "Raspberry Pi publishes nothing of the look for Debian $HOST_OLDEST or later"
	grep -qxF "$H_ARCH" <<<"$(rpi_arches "$H_SUITE")" || die "Raspberry Pi publishes no $H_ARCH packages for $H_SUITE"
	debug "Debian $rank on $H_ARCH: Raspberry Pi OS $H_SUITE"
}

# Print the PC architectures (PC_ARCHES) that Raspberry Pi publishes for a
# release, as listed by its signed Release file. Usage: rpi_arches SUITE
rpi_arches() {
	release_load "$1" || return 0
	sed -n 's/^Architectures:[[:space:]]*//p' "$WORKDIR/index/$1/Release" | tr ' ' '\n' | grep -xE "$PC_ARCHES" || true
}

# Succeed if Raspberry Pi publishes the look for a release: its themes, icons
# or GTK 2 engines, and its desktop (PANEL_PKG); a new release starts empty
# and fills over time. For the given architecture, else for this one or the
# first published. Usage: rpi_populated SUITE [ARCH]
rpi_populated() {
	local a=${2:-}
	if [[ -z $a ]]; then
		a=$(rpi_arches "$1")
		a=$(grep -xF "$H_ARCH" <<<"$a" || first_line <<<"$a")
	fi
	local names
	[[ -n $a ]] || return 1
	names=$(index_names "$1" "$a")
	grep -qxE 'pix(flat|trix)?-(theme|icons)|rpd-icons|gtk2-engines-pixflat' <<<"$names" && grep -qxF "$PANEL_PKG" <<<"$names"
}

# The theme of the look, as Raspberry Pi OS 13 sets it.
readonly DEFAULT_THEME="pixtrix"

###############################################################################
# 4. Archives: signed indexes, resolution, download, repacking
#   Raspberry Pi's archive, checked against its pinned key
###############################################################################

# Fetch and verify the signed Release file of a release, once. Fails if the
# archive lacks the release.
# Usage: release_load SUITE
release_load() {
	local suite=$1 d="$WORKDIR/index/$1" rc=0
	[[ ! -f $d/Release ]] || return 0
	# Failures are recorded on disk, since subshells (rpi_arches, index_names)
	# load releases too
	[[ ! -f $WORKDIR/unreachable ]] || die "cannot reach the archives; check the internet connection"
	[[ ! -f $d/missing ]] || return 1
	mkdir -p "$d"
	setup_keyring
	fetch "$RPI_ARCHIVE/dists/$suite/InRelease" "$d/InRelease" 2>/dev/null || rc=$?
	# A failed connection stops the run; an error answer (such as 404) means
	# the archive lacks the release. Network codes: curl 6, 7, 28 and 35
	# (name, connection, timeout, TLS); wget 4 and 5 (network, TLS).
	if (( rc )); then
		if { command -v curl >/dev/null && [[ $rc =~ ^(6|7|28|35)$ ]]; } \
			|| { ! command -v curl >/dev/null && [[ $rc =~ ^(4|5)$ ]]; }; then
			: >"$WORKDIR/unreachable"
			die "cannot reach ${RPI_ARCHIVE%/debian}; check the internet connection"
		fi
		: >"$d/missing"
		return 1
	fi
	# Release is trusted when present, so it is written only once verified
	verify_inrelease "$d/InRelease" "$d/Release.new"
	release_ok "$d/Release.new" "$suite" || die "the signed index at $RPI_ARCHIVE/dists/$suite is not a current $suite index"
	mv -f -- "$d/Release.new" "$d/Release"
}

# Print the package names of an index, loading it first.
# Usage: index_names SUITE ARCH
index_names() {
	index_load "$@" || return 0
	sed -n 's/^Package: //p' "$WORKDIR/index/$1/Packages-$2" | sort -u
}

# Unpack a Raspberry Pi OS package that is read but never installed (for its
# settings or artwork) into a directory under $WORKDIR/pi, once, and print
# that directory.
# Usage: pi_unpack PACKAGE SUITE ARCH
pi_unpack() {
	local pkg=$1 suite=$2 arch=$3 line v a f sha z d x=$WORKDIR/pi/$1-$2-$3
	[[ ! -d $x ]] || { printf '%s\n' "$x"; return 0; }
	index_load "$suite" "$arch" || return 1
	line=$(index_candidates "$suite" "$arch" "$pkg" | first_line)
	[[ -n $line ]] || return 1
	IFS=$'\t' read -r v a f sha z d <<<"$line"
	PKG_VER[$pkg]=$v PKG_FILE[$pkg]=$f PKG_SHA[$pkg]=$sha PKG_SIZE[$pkg]=${z:-0} PKG_SUITE[$pkg]=$suite
	f=$(download_pkg "$pkg") || return 1
	mkdir -p "$x"
	dpkg-deb -x "$f" "$x" || { rm -rf -- "$x"; return 1; }
	printf '%s\n' "$x"
}

# Download a file from Raspberry Pi's archive. Only HTTPS URLs of the archive
# are accepted and redirects are refused, so nothing can come from another
# host. Usage: fetch URL OUTPUT [SHOW-PROGRESS]
fetch() {
	local url=$1 out=$2 progress=${3:-0}
	[[ $url == "$RPI_ARCHIVE"/* ]] || die "refusing to download from an unofficial source: $url"
	debug "GET $url"
	if command -v curl >/dev/null; then
		local -a a=(-f -L --proto '=https' --max-redirs 0 --retry 3 --retry-delay 2 --connect-timeout 20 \
			--speed-limit 1024 --speed-time 60 -o "$out")
		if (( progress )) && [[ -t 2 ]]; then a+=(--progress-bar); else a+=(-sS); fi
		curl "${a[@]}" "$url"
	elif command -v wget >/dev/null; then
		local -a a=(--max-redirect=0 --tries=3 --timeout=20 -O "$out")
		if (( progress )) && [[ -t 2 ]]; then a+=(-q --show-progress); else a+=(-q); fi
		wget "${a[@]}" "$url"
	else
		die "curl or wget is required"
	fi
}

# Print at most the first MAX bytes of one of EXTRA_URLS, small text files
# that are read as data only: HTTPS, no redirects, a 5-second timeout. Fails
# quietly. Usage: fetch_extra URL MAX
fetch_extra() {
	local url=$1 max=$2
	[[ " ${EXTRA_URLS[*]} " == *" $url "* ]] || return 1
	debug "GET $url"
	if command -v curl >/dev/null; then
		curl -fsS --proto '=https' --max-redirs 0 --max-time 5 --max-filesize "$max" --range "0-$(( max - 1 ))" "$url" 2>/dev/null
	elif command -v wget >/dev/null; then
		wget -q -O - --https-only --max-redirect=0 --timeout=5 --tries=1 --header "Range: bytes=0-$(( max - 1 ))" "$url" 2>/dev/null
	else
		return 1
	fi
}

# Stop unless a file has the expected SHA256.
sha256_check() {
	local got
	got=$(sha256sum "$1" | cut -d' ' -f1)
	[[ $got == "$2" ]] || die "checksum mismatch for $(basename "$1") (expected $2, got $got)"
}

# Fetch the Raspberry Pi archive key once and convert it to a gpgv keyring.
setup_keyring() {
	# On disk, as subshells (rpi_arches) set it up too
	if [[ -s $WORKDIR/rpi.gpg ]]; then KEYRING=$WORKDIR/rpi.gpg; return 0; fi
	fetch "$RPI_KEY_URL" "$WORKDIR/rpi.asc" || die "cannot download the Raspberry Pi archive key from $RPI_KEY_URL"
	# Dearmor without gpg: decode the base64 body, without headers or checksum
	awk '/^-----BEGIN PGP PUBLIC KEY BLOCK-----/ { b = 1; next }
		/^-----END PGP PUBLIC KEY BLOCK-----/ { b = 0 }
		b { sub(/\r$/, "") } b && NF && !/^[A-Za-z-]+: / && !/^=/' "$WORKDIR/rpi.asc" \
		| base64 -d >"$WORKDIR/rpi.gpg" 2>/dev/null || die "could not decode the Raspberry Pi archive key"
	[[ -s $WORKDIR/rpi.gpg ]] || die "the Raspberry Pi archive key is empty"
	KEYRING=$WORKDIR/rpi.gpg
}

# Verify an InRelease file and write its signed content. As with APT, one good
# signature by a trusted key suffices and a bad one fails; the key must be
# Raspberry Pi's pinned one. Usage: verify_inrelease IN OUT
verify_inrelease() {
	local in=$1 out=$2 status fpr
	rm -f -- "$out"
	status=$(gpgv --status-fd 1 --keyring "$KEYRING" --output "$out" "$in" 2>/dev/null) || true
	if grep -qE '^\[GNUPG:\] (BADSIG|REVKEYSIG)' <<<"$status" || ! grep -q '^\[GNUPG:\] GOODSIG' <<<"$status"; then
		die "signature verification failed for $in"
	fi
	fpr=$(awk '$2 == "VALIDSIG" { print $NF }' <<<"$status")
	grep -qxi "$RPI_KEY_FPR" <<<"$fpr" || die "$in is not signed by the Raspberry Pi archive key"
	[[ -s $out ]] || die "no signed content in $in"
}

# Succeed if a verified Release file belongs to the given release and has not
# expired. Usage: release_ok FILE SUITE
release_ok() {
	local codename until t
	codename=$(sed -n 's/^Codename:[[:space:]]*//p' "$1" | first_line)
	[[ -z $codename || $codename == "$2" ]] || return 1
	until=$(sed -n 's/^Valid-Until:[[:space:]]*//p' "$1" | first_line)
	[[ -n $until ]] || return 0
	t=$(date -u -d "$until" +%s 2>/dev/null) || return 0
	(( t > $(date -u +%s) ))
}

# Load the package index of a release and architecture into $WORKDIR/index,
# once, and check it against the signed Release file.
# Usage: index_load SUITE ARCH
index_load() {
	local suite=$1 arch=$2 key="$1/$2" d="$WORKDIR/index/$1" base=$RPI_ARCHIVE comp="" sha="" c
	[[ -n ${IDX_LOADED[$key]:-} ]] && return 0
	[[ -z ${IDX_FAILED[$key]:-} ]] || return 1
	if [[ -f $d/Packages-$arch ]]; then IDX_LOADED[$key]=1; return 0; fi
	release_load "$suite" || { IDX_FAILED[$key]=1; return 1; }
	debug "loading $key index"
	for c in xz gz; do
		[[ $c == xz ]] && ! command -v xz >/dev/null && continue
		sha=$(awk -v f="main/binary-$arch/Packages.$c" '
			/^SHA256:/ { s = 1; next } /^[^ ]/ { s = 0 } s && $3 == f { print $1; exit }' "$d/Release")
		if [[ -n $sha ]]; then comp=$c; break; fi
	done
	if [[ -z $comp ]]; then debug "no $arch index in $suite"; IDX_FAILED[$key]=1; return 1; fi
	fetch "$base/dists/$suite/main/binary-$arch/Packages.$comp" "$d/Packages-$arch.$comp" \
		|| die "cannot download the $suite/$arch package index from $base"
	sha256_check "$d/Packages-$arch.$comp" "$sha"
	local -a unpack=(gzip -dc)
	[[ $comp != xz ]] || unpack=(xz -dc)
	if ! "${unpack[@]}" "$d/Packages-$arch.$comp" >"$d/Packages-$arch"; then
		rm -f -- "$d/Packages-$arch"
		die "cannot unpack the $suite/$arch package index from $base"
	fi
	rm -f -- "$d/Packages-$arch.$comp"
	IDX_LOADED[$key]=1
}

# Print "version<TAB>arch<TAB>filename<TAB>sha256<TAB>size<TAB>depends" for each
# version of a package in one index, newest first. Depends includes Pre-Depends.
# Usage: index_candidates SUITE ARCH PACKAGE
index_candidates() {
	local suite=$1 arch=$2 pkg=$3 line v i
	local -a lines=()
	while IFS= read -r line; do
		v=${line%%$'\t'*}
		for (( i = ${#lines[@]}; i > 0; i-- )); do
			dpkg --compare-versions "$v" gt "${lines[i-1]%%$'\t'*}" || break
			lines[i]=${lines[i-1]}
		done
		lines[i]=$line
	done < <(awk -v p="$pkg" 'BEGIN { RS = ""; FS = "\n" }
		# Every paragraph starts with its Package field: skip others unparsed
		index($0, "Package: " p "\n") != 1 { next }
		{
			n = v = a = f = s = z = d = ""
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^Package: /)                n = substr($i, 10)
				else if ($i ~ /^Version: /)           v = substr($i, 10)
				else if ($i ~ /^Architecture: /)      a = substr($i, 15)
				else if ($i ~ /^Filename: /)          f = substr($i, 11)
				else if ($i ~ /^SHA256: /)            s = substr($i, 9)
				else if ($i ~ /^Size: /)              z = substr($i, 7)
				else if ($i ~ /^(Pre-)?Depends: /)    { x = $i; sub(/^[^:]*: /, "", x); d = d (d == "" ? "" : ", ") x }
			}
			if (n == p && f != "" && s != "") print v "\t" a "\t" f "\t" s "\t" z "\t" d
		}' "$WORKDIR/index/$suite/Packages-$arch")
	if (( ${#lines[@]} )); then printf '%s\n' "${lines[@]}"; fi
}

# Compare two Debian versions with a Depends operator (<<, <=, =, >=, >>).
_vcmp() {
	local op
	case $2 in '<<') op=lt ;; '<='|'<') op=le ;; '=') op=eq ;; '>='|'>') op=ge ;; '>>') op=gt ;; *) return 1 ;; esac
	dpkg --compare-versions "$1" "$op" "$3"
}

# Set AV to the space-separated versions of a package available on the target:
# its resolved version if it is in the install set, else the installed version
# and the APT candidate, or for a virtual package the versions it is provided
# at (_provided). "*" stands for any version (an unresolved package), "-" for
# one provided without a version.
declare -gA AVAIL=()
_avail() {
	local n=$1
	# Not cached: the version is known only once the package is resolved
	if [[ -n ${IN_SET[$n]:-} ]]; then AV=${PKG_VER[$n]:-*}; return 0; fi
	if [[ -z ${AVAIL[$n]+set} ]]; then
		AVAIL[$n]=$(printf '%s %s' "$(installed_version "$n")" \
			"$(LC_ALL=C apt-cache policy "$n" 2>/dev/null | awk '/Candidate:/ && $2 != "(none)" { print $2 }')" | xargs)
		[[ -n ${AVAIL[$n]} ]] || AVAIL[$n]=$(_provided "$n")
		if [[ -z ${AVAIL[$n]} ]] && apt_has "$n"; then AVAIL[$n]="*"; fi
	fi
	AV=${AVAIL[$n]}
}
# Print the versions at which the installed and candidate versions of the
# packages that provide a virtual package provide it, as the APT sources and
# dpkg list them; "-" for a Provides without a version, which satisfies only
# a dependency without one (Debian Policy 7.5). Usage: _provided PACKAGE
_provided() {
	local rp
	local -a provs
	rp=$(LC_ALL=C apt-cache showpkg "$1" 2>/dev/null | awk '/^Reverse Provides:/ { s = 1; next } /^[A-Z][A-Za-z ]*:/ { s = 0 }
		s && NF >= 2 { v = "-"; if ($4 ~ /[^)]\)$/) { v = $4; sub(/\)$/, "", v) }; print $1, $2, v }')
	[[ -n $rp ]] || return 0
	mapfile -t provs < <(cut -d' ' -f1 <<<"$rp" | sort -u)
	LC_ALL=C apt-cache policy "${provs[@]}" 2>/dev/null | awk '
		NR == FNR { v[$1 " " $2] = $3; next }
		/^[^ ]/ { p = $1; sub(/:$/, "", p); next }
		$1 ~ /^(Installed|Candidate):$/ && ((p " " $2) in v) { print v[p " " $2] }' <(printf '%s\n' "$rp") - | sort -u | xargs
}

# Succeed if every dependency in a Depends field, including its version
# constraint, can be satisfied on the target. A dependency that Debian has
# renamed (DEP_RENAMES) is satisfied by its successor.
_deps_satisfiable() {
	local group alt name op ver r v ok
	local -a groups alts avs
	IFS=, read -ra groups <<<"$1"
	for group in "${groups[@]}"; do
		[[ -n ${group//[[:space:]]/} ]] || continue
		ok=0
		IFS='|' read -ra alts <<<"$group"
		for alt in "${alts[@]}"; do
			name=${alt%%(*} op="" ver=""
			name=${name%%:*}; name=${name//[[:space:]]/}
			if [[ $alt =~ \(([\<\>=]+)[[:space:]]*([^\)[:space:]]+)\) ]]; then op=${BASH_REMATCH[1]} ver=${BASH_REMATCH[2]}; fi
			for r in "$name" ${DEP_RENAMES[$name]:-}; do
				_avail "$r"
				read -ra avs <<<"$AV"   # read splits without expanding "*"
				for v in "${avs[@]}"; do
					if [[ -z $op || $v == "*" ]] || { [[ $v != - ]] && _vcmp "$v" "$op" "$ver"; }; then ok=1; break 3; fi
				done
			done
		done
		(( ok )) || return 1
	done
}

# Print a twin's Depends field (TWIN_RE) as repacking leaves it (relations in
# beside_build): without the exact Raspberry Pi version asked of a package
# that is not a twin, whose Debian build is used (libnma0's libnma-common).
# The fields of other packages print unchanged. Usage: twin_deps PACKAGE DEPENDS
twin_deps() {
	if [[ ! $1 =~ ^($TWIN_RE)$ ]]; then printf '%s\n' "$2"; return 0; fi
	printf '%s\n' "$2" | T="^($TWIN_RE)\$" awk '{
		n = split($0, g, ","); out = ""
		for (i = 1; i <= n; i++) {
			m = split(g[i], a, "|"); grp = ""
			for (j = 1; j <= m; j++) {
				x = a[j]; gsub(/^[ \t]+|[ \t]+$/, "", x)
				name = x; sub(/[ (:].*/, "", name); rest = substr(x, length(name) + 1)
				if (name == "") continue
				if (name !~ ENVIRON["T"] && rest ~ /\(=[^)]*\+rp[it]/) sub(/[ \t]*\(.*/, "", rest)
				grp = grp (j > 1 ? " | " : "") name rest
			}
			if (grp != "") out = out (out != "" ? ", " : "") grp
		}
		print out }'
}

# Find the newest compatible version of a package and record it in PKG_*.
# A version is compatible when all its dependencies, with their versions, are
# available on this Debian release; a version that needs a Raspberry Pi
# rebuild of a Debian package is passed over for an older one that does not.
# The indexes searched, in order:
#  * The target release: any architecture (its binaries match this system).
#  * Later Raspberry Pi OS releases: architecture-independent packages
#    (icons, fonts, wallpapers) and, built for this architecture, the theme
#    packages without compiled code (DATA_PKGS), in their newest version that
#    this Debian release supports. Which looks are installed is decided
#    before (rpi_pkgs); this only picks their versions.
#  * Only if neither has the package: earlier releases, with the same
#    restriction.
# Usage: resolve_pkg PACKAGE
resolve_pkg() {
	local pkg=$1 s x line best="" best_v="" skipped="" v a f sha z d arch=$H_ARCH data=0
	[[ " ${DATA_PKGS[*]} " == *" $pkg "* ]] && data=1
	local -a newer=() older=()
	for s in $(releases); do
		# releases prints known releases only, so REL_VER has each of them
		if (( REL_VER[$s] > REL_VER[$H_SUITE] )); then newer+=("$s/$arch")
		elif (( REL_VER[$s] < REL_VER[$H_SUITE] )); then older+=("$s/$arch"); fi
	done
	for x in "$H_SUITE/$arch" "${newer[@]}" "${older[@]}"; do
		[[ -n $best && " ${older[*]} " == *" $x "* ]] && break   # earlier releases are only a fallback
		index_load "${x%/*}" "${x#*/}" || continue
		while IFS= read -r line; do
			IFS=$'\t' read -r v a f sha z d <<<"$line"
			# Raspberry Pi's builds of these, with their plugins and data, the
			# magnifier of its plugin and its Openbox, come from the target
			# release only, since they must match each other
			if [[ $x != "$H_SUITE/$arch" && $pkg =~ ^(lpplug-|libnma|mage|openbox|libob|wfplug-|swaylock) ]]; then continue; fi
			[[ $x == "$H_SUITE/$arch" || $a == all ]] || { [[ $a == "$arch" ]] && (( data )); } || continue
			d=$(twin_deps "$pkg" "$d")
			if ! _deps_satisfiable "$d"; then
				[[ -n $skipped ]] || skipped=$v
				continue
			fi
			# The release goes first: tab is an IFS whitespace character, so a
			# final empty Depends field would otherwise shift it when read back
			if [[ -z $best_v ]] || dpkg --compare-versions "$v" gt "$best_v"; then best="${x%/*}"$'\t'"$line" best_v=$v; fi
			break
		done < <(index_candidates "${x%/*}" "${x#*/}" "$pkg")
	done
	if [[ -z $best ]]; then
		# A Qt style without a build for this Qt version is replaced (qt_choose)
		[[ -z $skipped || $pkg =~ ^($QT_STYLE_RE)$ ]] || warn "$pkg $skipped needs packages that Debian does not provide; no compatible version found"
		return 1
	fi
	IFS=$'\t' read -r s v a f sha z d <<<"$best"
	d=$(twin_deps "$pkg" "$d")
	if [[ -n $skipped ]] && dpkg --compare-versions "$skipped" gt "$v"; then
		warn "$pkg $skipped needs packages that Debian does not provide; using $v"
	fi
	PKG_VER[$pkg]=$v PKG_FILE[$pkg]=$f PKG_SHA[$pkg]=$sha PKG_SIZE[$pkg]=${z:-0}
	PKG_SUITE[$pkg]=$s PKG_DEPS[$pkg]=$d
}

# Download a resolved package, verify it and print its local path.
download_pkg() {
	local pkg=$1 out big=0
	out="$WORKDIR/debs/$(basename "${PKG_FILE[$pkg]}")"
	mkdir -p "$WORKDIR/debs"
	if [[ -f $out ]] && [[ $(sha256sum "$out" | cut -d' ' -f1) == "${PKG_SHA[$pkg]}" ]]; then
		printf '%s\n' "$out"; return 0
	fi
	(( ${PKG_SIZE[$pkg]:-0} > 5000000 )) && big=1
	info "Downloading $pkg ${PKG_VER[$pkg]} ($(human_size "${PKG_SIZE[$pkg]}"))"
	fetch "$RPI_ARCHIVE/${PKG_FILE[$pkg]}" "$out" "$big" || die "cannot download $pkg from $RPI_ARCHIVE"
	sha256_check "$out" "${PKG_SHA[$pkg]}"
	chmod 0644 "$out"
	printf '%s\n' "$out"
}

# Succeed if a dependency can be satisfied on the target: by the install set
# or by the APT sources.
_dep_ok() { [[ -n ${IN_SET[$1]:-} ]] || apt_has "$1"; }

# Rewrite the dependency names that Debian has since renamed (DEP_RENAMES) in
# the Depends and Pre-Depends fields. Prints the path of the package to install.
compat_fix() {
	local deb=$1 deps group names n c repl changed=0 re field
	local -A value=()
	for field in Depends Pre-Depends; do
		deps=$(dpkg-deb -f "$deb" "$field")
		[[ -n $deps ]] || continue
		# Each comma-separated group needs one of its alternatives (a | b)
		while IFS= read -r group; do
			names=$(depnames <<<"$group")
			[[ -n $names ]] || continue
			repl=""
			for n in $names; do if _dep_ok "$n"; then repl=ok; break; fi; done
			[[ -z $repl ]] || continue
			for n in $names; do
				for c in ${DEP_RENAMES[$n]:-}; do
					if _dep_ok "$c"; then repl=$c; break; fi
				done
				[[ -z $repl ]] || break
			done
			[[ -n $repl ]] || die "$(basename "$deb") depends on '${names//$'\n'/' | '}', which is not available for $H_SUITE/$H_ARCH"
			re=${n//./\\.}
			re=${re//+/\\+}
			deps=$(sed -E "s/(^|[ ,|])${re}([ ,(|:]|\$)/\\1${repl}\\2/g" <<<"$deps")
			info "Compatibility: $(dpkg-deb -f "$deb" Package) $field $n -> $repl"
			changed=1
		done < <(tr ',' '\n' <<<"$deps")
		value[$field]=$deps
	done
	if (( ! changed )); then printf '%s\n' "$deb"; return 0; fi
	deb_unpack "$deb" "debcompat-$H_SUITE"
	control_set Depends "${value[Depends]:-}"
	control_set Pre-Depends "${value[Pre-Depends]:-}"
	deb_pack
}

# Unpack a .deb into R_DIR for repacking. Sets R_OUT to the repacked file
# (the name with a suffix) and R_STAMP to the original time, so that the same
# input always gives an identical file. Usage: deb_unpack DEB SUFFIX
deb_unpack() {
	R_DIR="$WORKDIR/repack/$(basename "$1" .deb)"
	R_OUT="$WORKDIR/debs/$(basename "$1" .deb)+$2.deb"
	rm -rf -- "$R_DIR"; mkdir -p "$(dirname "$R_DIR")" "$WORKDIR/debs"
	dpkg-deb -R "$1" "$R_DIR"
	R_STAMP=$(stat -c %Y "$R_DIR/DEBIAN/control")
}

# Replace a field of the unpacked control file, or drop it when the value is
# empty. A field that is not there is not added. Usage: control_set FIELD VALUE
control_set() {
	F=$1 V=$2 awk '
		index($0, ENVIRON["F"] ":") == 1 { if (ENVIRON["V"] != "") print ENVIRON["F"] ": " ENVIRON["V"]; folded = 1; next }
		folded && /^[ \t]/ { next }                      # continuation lines of the old value
		{ folded = 0; print }' "$R_DIR/DEBIAN/control" >"$R_DIR/DEBIAN/control.new"
	mv -- "$R_DIR/DEBIAN/control.new" "$R_DIR/DEBIAN/control"
}

# Build the repacked package from R_DIR, with new checksums and the original
# time on every file and link, and print its path.
deb_pack() {
	( cd "$R_DIR" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z \
		| xargs -0r md5sum >DEBIAN/md5sums )
	chmod 0644 "$R_DIR/DEBIAN/md5sums"
	find "$R_DIR" -exec touch -h -d "@$R_STAMP" {} +
	build_deb "$R_DIR" "$R_OUT" "$R_STAMP"
	[[ -s $R_OUT ]] || die "cannot build $(basename "$R_OUT")"
	printf '%s\n' "$R_OUT"
}

# Build a package with every file owned by root. Usage: build_deb DIR OUT [STAMP]
build_deb() {
	SOURCE_DATE_EPOCH=${3:-$(date +%s)} dpkg-deb --root-owner-group -Zxz -b "$1" "$2" >/dev/null || die "cannot build $(basename "$2")"
	chmod 0644 "$2"
}

# Write the helper that repacks Raspberry Pi's builds that would clash with
# Debian's packages to install beside them, for the Raspberry Pi Desktop
# session only; an install and --refresh run it. Usage: beside_build FILE
beside_build() {
	sed -e "s|@PREFIX@|$BESIDE_PREFIX|" <<'HELPER' | _write "$1"
#!/bin/bash
# Raspberry Pi's builds that clash with Debian's packages, repacked to install
# beside them, for the Raspberry Pi Desktop session only. Written by rpios-look
# and removed with its package.
#
# A repacked package has its own name (rpios-look-NAME), its programs their
# own names (NAME-pi), its data and plugin folders their own names (the last
# two letters become "pi": pcmanfm -> pcmanpi) and its libraries their own
# file names and sonames (libnma.so.0 -> libnmapi.so). Each name is written into
# the programs and libraries in place, at the same length, so no environment
# variable is needed: no Debian program can load a Raspberry Pi library, and
# no Raspberry Pi program loads a Debian copy of one. Files that Debian's
# package already provides (translations, icons, menu entries, settings
# under /etc) and Raspberry Pi system extras (services, udev rules, autostart
# entries, maintainer scripts) are left out.
#
# Usage: beside sonames DEB...        print the sonames of the packages' libraries
#        beside need CONF DEB         succeed if DEB needs repacking
#        beside pack CONF DEB OUTDIR  repack DEB where it needs it and print the
#                                     new file; print nothing where it does not
# CONF holds the names of Raspberry Pi's builds of Debian's packages
# (twins=NAME...), the sonames of their libraries (libs=SONAME...) and the
# names of every package repacked (beside=NAME...).
set -uo pipefail
umask 022
# The prefix of the repacked packages
readonly PREFIX=@PREFIX@
# The programs that keep a place, renamed NAME-pi; the folders renamed
readonly PROGRAMS=" openbox pcmanfm swaylock " DIRS="pcmanfm"
export DIRS
# Where the folders are, as a regular expression over a path
readonly WHERE='/usr/(share|lib(/[a-z0-9_]+-linux-gnu[a-z0-9_]*)?)/'
# A folder for this run's files, removed at the end
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rpios-look-beside.XXXXXX") || exit 1
trap 'rm -rf -- "$TMP"' EXIT

say() { printf 'rpios-look: %s\n' "$*" >&2; }
die() { say "$*"; exit 1; }

# Print the new name of a folder or a soname.
dir_new() { printf '%spi\n' "${1%??}"; }
lib_new() {
	local base=${1%.so.*} v=${1##*.so.} pad
	pad=$(printf '%*s' $(( ${#v} - 1 )) '' | tr ' ' -)
	printf '%s%spi.so\n' "$base" "$pad"
}

# Rewrite the folders and sonames inside ELF files in place, or with -c only
# count what would change. LIBS (environment): the sonames to rename.
# Usage: elf_edit [-c] FILE...
elf_edit() {
	local count=0
	[[ $1 != -c ]] || { count=1; shift; }
	(( $# )) || return 0
	COUNT=$count perl -e '
		use strict; use warnings;
		my %map;
		for my $s (split " ", $ENV{LIBS} // "") {
			(my $b = $s) =~ s/\.so\.([^.]+(?:\.[^.]+)*)$//; my $v = $1;
			$map{$s} = $b . ("-" x (length($v) - 1)) . "pi.so";
		}
		my $libs = join "|", map { quotemeta } sort keys %map;
		my $n = 0;
		for my $f (@ARGV) {
			open(my $in, "<:raw", $f) or die "$f: $!\n"; local $/; my $d = <$in>; close $in;
			next unless substr($d, 0, 4) eq "\x7fELF";
			my $c = 0;
			$c += ($d =~ s{(?<=\0)($libs)(?=\0)}{$map{$1}}g) if $libs ne "";
			$c += ($d =~ s{(/usr/(?:share|lib(?:/[a-z0-9_]+-linux-gnu[a-z0-9_]*)?)/)($ENV{DIRS})(?=[/\0])}{$1 . substr($2, 0, -2) . "pi"}ge);
			$n += $c;
			next if $ENV{COUNT} or !$c;
			open(my $out, "+<:raw", $f) or die "$f: $!\n"; print $out $d; close $out;
		}
		print "$n\n";' "$@"
}

# Print the dependency field VALUE with the repacked packages renamed, and
# without the exact Raspberry Pi version asked of a Debian package whose
# Debian build is used (the data of a library: libnma-common).
# BESIDE (environment): " NAME... ". Usage: relations VALUE
relations() {
	printf '%s\n' "$1" | P=$PREFIX awk '{
		n = split($0, g, ","); out = ""
		for (i = 1; i <= n; i++) {
			m = split(g[i], a, "|"); grp = ""
			for (j = 1; j <= m; j++) {
				x = a[j]; gsub(/^[ \t\n]+|[ \t\n]+$/, "", x)
				name = x; sub(/[ (:].*/, "", name); rest = substr(x, length(name) + 1)
				if (name == "") continue
				if (index(ENVIRON["BESIDE"], " " name " ")) name = ENVIRON["P"] name
				else if (rest ~ /\(=[^)]*\+rp[it]/) sub(/[ \t]*\(.*/, "", rest)
				grp = grp (j > 1 ? " | " : "") name rest
			}
			if (grp != "") out = out (out != "" ? ", " : "") grp
		}
		print out }'
}

# Read the configuration: TWINS, LIBS, BESIDE. Usage: read_conf FILE
read_conf() {
	[[ -r $1 ]] || die "cannot read $1"
	TWINS=" $(sed -n 's/^twins=//p' "$1" | head -n1) "
	LIBS=$(sed -n 's/^libs=//p' "$1" | head -n1)
	BESIDE=" $(sed -n 's/^beside=//p' "$1" | head -n1)$TWINS"
	export TWINS LIBS BESIDE
}

# Print the sonames of the libraries in the packages: the names of the links
# and files called lib*.so.N, which Debian names after the soname.
cmd_sonames() {
	local deb
	for deb; do
		dpkg-deb -c "$deb" | awk '{ print $6 }' | sed -n 's|.*/\(lib[^/]*\.so\.[0-9][0-9]*\)$|\1|p'
	done | sort -u
}

# Succeed if a package needs repacking: it is a twin (Raspberry Pi's build of
# a Debian package), installs into a twin's folders or depends on a repacked
# package (a program that uses a twin's library depends on it, as the
# library's package names it). Usage: cmd_need CONF DEB
cmd_need() {
	local deb=$2 name
	read_conf "$1"
	name=$(dpkg-deb -f "$deb" Package)
	[[ $TWINS != *" $name "* ]] || return 0
	[[ -z $(relations "$(dpkg-deb -f "$deb" Pre-Depends), $(dpkg-deb -f "$deb" Depends)" | grep -F "$PREFIX") ]] || return 0
	# grep -c reads to the end: a reader that stops early breaks the pipe
	dpkg-deb -c "$deb" | awk '{ print $6 }' | sed 's|^\.||' | grep -cE "^${WHERE}(${DIRS})(/|\$)" >/dev/null
}

# Repack DEB beside Debian's package, into OUTDIR, and print the new file;
# print nothing for a package that does not need it (cmd_need).
cmd_pack() {
	local deb=$2 outdir=$3 dir name twin=0 f n new v arch out r
	local -a elves=()
	cmd_need "$1" "$deb" || return 0
	dir=$TMP/pack; rm -rf -- "$dir"; mkdir -p "$dir"
	dpkg-deb -R "$deb" "$dir/r" || die "cannot unpack $deb"
	r=$dir/r
	name=$(dpkg-deb -f "$deb" Package)
	[[ $TWINS != *" $name "* ]] || twin=1
	new=$PREFIX$name
	# Raspberry Pi system extras, in every repacked package
	rm -rf -- "$r/etc/xdg/autostart" "$r/etc/systemd" "$r/lib/systemd" "$r/usr/lib/systemd" "$r/lib/udev" \
		"$r/usr/lib/udev" "$r/etc/dbus-1" "$r/usr/share/dbus-1" "$r/etc/init.d" "$r/etc/cron.d"
	if (( twin )); then
		# What Debian's package provides, and what the session does not start
		rm -rf -- "${r:?}/etc" "$r/usr/include" "$r/usr/share/"{locale,man,icons,themes,mime,pixmaps,lintian,apport,doc-base,menu,xsessions,info,bash-completion,fish,zsh} \
			"$r/usr/lib/"*/pkgconfig "$r/usr/lib/"*/openbox-*autostart
		rm -f -- "$r/DEBIAN/"{preinst,postinst,prerm,postrm,config,templates,conffiles}
		for f in "$r"/usr/bin/*; do
			[[ -e $f || -L $f ]] || continue
			n=${f##*/}
			if [[ $PROGRAMS == *" $n "* ]]; then mv -- "$f" "$f-pi"; else rm -f -- "$f"; fi
		done
		rmdir --ignore-fail-on-non-empty "$r/usr/bin" 2>/dev/null || true
	fi
	rm -f -- "$r/DEBIAN/"{shlibs,symbols}
	# The folders, under /usr/share and /usr/lib/TRIPLET
	while IFS= read -r f; do
		mv -- "$r$f" "$r${f%/*}/$(dir_new "${f##*/}")"
	done < <(find "$r/usr" -mindepth 2 -maxdepth 3 -type d 2>/dev/null | sed "s|^$r||" | grep -xE "${WHERE}(${DIRS})" | sort -r)
	# A file manager's menu entry, for the session only, in its own folder
	for f in "$r"/usr/share/applications/*.desktop; do
		[[ -f $f ]] || continue
		n=${f##*/}; n=${n%.desktop}
		if (( twin )) && [[ $PROGRAMS == *" $n "* && -d $r/usr/share/$(dir_new "$n") ]]; then
			sed -E "s/^(Exec|TryExec)=$n( |\$)/\\1=$n-pi\\2/" "$f" >"$r/usr/share/$(dir_new "$n")/$n-pi.desktop"
		fi
		(( ! twin )) || rm -f -- "$f"
	done
	(( ! twin )) || rmdir --ignore-fail-on-non-empty "$r/usr/share/applications" 2>/dev/null || true
	# The libraries, under their new sonames; their links go
	for n in $LIBS; do
		[[ -d $r/usr/lib ]] || break
		find "$r/usr/lib" -type l \( -name "$n" -o -name "$n.*" \) -delete
		while IFS= read -r f; do
			mv -- "$f" "${f%/*}/$(lib_new "$n")"
		done < <(find "$r/usr/lib" -type f \( -name "$n" -o -name "$n.*" \))
	done
	if (( twin )) && [[ -d $r/usr/lib ]]; then find "$r/usr/lib" -type l -name 'lib*.so' -delete; fi
	[[ ! -d $r/usr/share/doc/$name ]] || mv -- "$r/usr/share/doc/$name" "$r/usr/share/doc/$new"
	mapfile -t elves < <(find "$r" -path "$r/DEBIAN" -prune -o -type f -print)
	elf_edit "${elves[@]}" >/dev/null || die "cannot rewrite the programs of $name"
	# Nothing of Debian's may remain: no twin path, library name or folder
	n=$(elf_edit -c "${elves[@]}")
	(( ${n:-0} == 0 )) || die "$name still refers to $n of Debian's names after repacking"
	if find "$r" -path "$r/DEBIAN" -prune -o -print | sed "s|^$r||" | grep -cE "^${WHERE}(${DIRS})(/|\$)" >/dev/null; then
		die "$name still installs into Debian's folders"
	fi
	if (( twin )); then
		f=$(find "$r" -path "$r/DEBIAN" -prune -o \( -type f -o -type l \) -print | sed "s|^$r||" \
			| grep -vE "^/usr/bin/[^/]+-pi\$|^/usr/share/doc/$new/|^${WHERE}[^/]*pi(/|\.so\$)" | sed -n 1p || true)
		[[ -z $f ]] || die "$name has a file that may be Debian's: $f"
	fi
	# The control file: the new name, the twins renamed, no relations to
	# Debian's packages (Breaks, Replaces, Conflicts, Provides), no recommends
	v=$(dpkg-deb -f "$deb" Version) arch=$(dpkg-deb -f "$deb" Architecture)
	{
		printf 'Package: %s\nSource: %s\nVersion: %s\nArchitecture: %s\n' "$new" "$(dpkg-deb -f "$deb" Source | grep . || echo "$name")" "$v" "$arch"
		for n in Maintainer Multi-Arch Section Priority Homepage; do
			f=$(dpkg-deb -f "$deb" "$n")
			[[ -z $f ]] || printf '%s: %s\n' "$n" "$f"
		done
		printf 'Installed-Size: %s\n' "$(du -sk --exclude=DEBIAN "$r" | cut -f1)"
		for n in Pre-Depends Depends; do
			f=$(dpkg-deb -f "$deb" "$n" | tr '\n' ' ')
			[[ -z ${f// } ]] || printf '%s: %s\n' "$n" "$(relations "$f")"
		done
		dpkg-deb -f "$deb" Description | sed '1s/^/Description: /'
		printf ' .\n Repacked by rpios-look to install beside Debian'"'"'s packages, for the\n Raspberry Pi Desktop session only.\n'
	} >"$dir/control" && mv -- "$dir/control" "$r/DEBIAN/control"
	( cd "$r" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z | xargs -0r md5sum >DEBIAN/md5sums )
	[[ -s $r/DEBIAN/md5sums ]] || rm -f -- "$r/DEBIAN/md5sums"
	find "$r" -depth -type d -empty -delete
	mkdir -p "$outdir"
	out=$outdir/${new}_${v//:/%3a}_$arch.deb
	f=$(stat -c %Y "$deb")
	find "$r" -exec touch -h -d "@$f" {} +
	# dpkg 1.19 and later (every Debian release this script supports)
	SOURCE_DATE_EPOCH=$f dpkg-deb --root-owner-group -Zxz -b "$r" "$out" >/dev/null || die "cannot build $(basename "$out")"
	chmod 0644 "$out"
	printf '%s\n' "$out"
}

case ${1:-} in
	sonames) shift; cmd_sonames "$@" ;;
	need)    (( $# == 3 )) || die "usage: beside need CONF DEB"; cmd_need "$2" "$3" ;;
	pack)    (( $# == 4 )) || die "usage: beside pack CONF DEB OUTDIR"; cmd_pack "$2" "$3" "$4" ;;
	*) die "usage: beside sonames|need|pack" ;;
esac
HELPER
	chmod 0755 "$1"
}
# Build this run's copy of the helper (beside_build) on first use.
beside_ready() { [[ -x $WORKDIR/beside ]] || beside_build "$WORKDIR/beside"; }
# Run this run's copy of the helper. Usage: beside COMMAND ARG...
beside() {
	beside_ready
	"$WORKDIR/beside" "$@"
}
# Repack a package beside Debian's where it needs it (the run's
# configuration, beside_plan), and print the path of the package to install.
# Usage: beside_pack FILE
beside_pack() {
	local out
	out=$(beside pack "$WORKDIR/beside.conf" "$1" "$WORKDIR/debs/beside") || return 1
	printf '%s\n' "${out:-$1}"
}

# The Cambridge wallpapers (cantab-wallpaper) are in /usr/share/rpd-wallpaper
# too, under names that the standard sets use (sunrise.jpg). Repack them into
# a Cambridge folder there, so that no file of another set is replaced.
# Prints the path of the package to install.
wall_own_dir() {
	local deb=$1 n dir
	n=$(dpkg-deb -f "$deb" Package)
	[[ $n == cantab-wallpaper ]] || { printf '%s\n' "$deb"; return 0; }
	deb_unpack "$deb" folder
	dir=$R_DIR/usr/share/rpd-wallpaper
	[[ -d $dir ]] || { deb_pack; return 0; }
	mkdir -p "$R_DIR/.wall"
	find "$dir" -mindepth 1 -maxdepth 1 -exec mv -t "$R_DIR/.wall" {} +
	mv -- "$R_DIR/.wall" "$dir/Cambridge"
	deb_pack
}

# Print the wallpapers (pictures) of an installed wallpaper package, one path
# per line, as the package installs them under /usr/share/rpd-wallpaper.
# Usage: wall_files PACKAGE
wall_files() {
	local f
	[[ $(dpkg-query -W -f '${db:Status-Abbrev}' "$1" 2>/dev/null) == ii* ]] || return 0
	while read -r f; do
		[[ $f == /usr/share/rpd-wallpaper/*.* && -f $f ]] || continue
		[[ ${f,,} == *.jpg || ${f,,} == *.jpeg || ${f,,} == *.png ]] || continue
		printf '%s\n' "$f"
	done < <(dpkg -L "$1" 2>/dev/null)
	return 0
}

# Add to the session package a folder of links under $WALLS for each
# installed wallpaper package (rpd-wallpaper*, cantab-wallpaper), named after
# the package, so that the wallpaper picker offers the sets one by one in one
# place. The files stay where Raspberry Pi OS installs them, so that its
# packages update them.
# Usage: wallpaper_links STAGE
wallpaper_links() {
	local stage=$1 p f
	for p in $(dpkg-query -W -f '${Package}\n' 'rpd-wallpaper*' cantab-wallpaper 2>/dev/null); do
		while read -r f; do
			mkdir -p "$stage$WALLS/$p"
			ln -sfn "../../../${f#/usr/share/}" "$stage$WALLS/$p/${f##*/}"
		done < <(wall_files "$p")
	done
}

# Succeed if the APT sources have a Debian package of that name, in a version
# that satisfies OP VERSION when given. Usage: _debian_has NAME [OP VERSION]
_debian_has() {
	local v
	while read -r v; do
		[[ -z ${2:-} ]] || dpkg --compare-versions "$v" "$2" "$3" && return 0
	done < <(apt_versions "$1")
	return 1
}

# Check that a Raspberry Pi package leaves Debian's alone. It may not replace,
# break, conflict with or stand in for a Debian package (Raspberry Pi's builds
# of Debian's packages are repacked first, see beside_build). Its maintainer
# scripts may not edit a file under /etc that the package does not ship. Any
# other such package is refused. Prints the path of the package to install,
# or nothing for a refused one.
scripts_coinstall() {
	local deb=$1 dir=$WORKDIR/scripts s f n bad="" paths
	# A versioned relation counts only where a Debian version satisfies it
	for s in Replaces Breaks Conflicts Provides; do
		while read -r n op v; do
			[[ -n $n ]] || continue
			[[ $s != Provides ]] || op="" v=""
			# shellcheck disable=SC2086  # no relation: both are left out
			if _debian_has "$n" $op $v; then bad+="$s:$n "; fi
		done < <(dpkg-deb -f "$deb" "$s" | tr ',|' '\n' | sed -E 's/^( *[^ :(]+):[^ (]*/\1/; s/\( *([<>=]+) */ \1 /; s/\)//')
	done
	rm -rf -- "$dir"; mkdir -p "$dir"
	dpkg-deb -e "$deb" "$dir"
	paths=$(dpkg-deb --fsys-tarfile "$deb" | tar -t | sed 's:^\./:/:; s:/$::')
	# dpkg-maintscript-helper's conffile commands act only on the package's own
	# former conffiles
	for s in preinst postinst prerm postrm config; do
		[[ -f $dir/$s ]] || continue
		while read -r f; do
			grep -qxF -- "$f" <<<"$paths" || bad+="$s:$f "
		done < <(grep -v 'dpkg-maintscript-helper [a-z_]*_conffile ' "$dir/$s" | grep -oE '/etc/[A-Za-z0-9._/+-]*[A-Za-z0-9_]' | sort -u)
	done
	if [[ -z $bad ]]; then printf '%s\n' "$deb"; return 0; fi
	warn "$(dpkg-deb -f "$deb" Package) is left out: it would change Debian's packages or files (${bad% })"
}

# Print the package names of a Depends-style field read from stdin, one per
# line, without versions, alternative separators or architecture qualifiers.
depnames() { tr ',|' '\n' | sed 's/(.*//; s/:.*//; s/[[:space:]]//g' | awk 'NF' | sort -u; }

###############################################################################
# 5. Artwork: icon sets with the Debian logo
###############################################################################

# Print the other Raspberry Pi OS icon sets that an icon set falls back to.
# Only the legacy PiX does, to PiXflat, the set closest to it in style. The
# others keep the fallback that the official theme names (GNOME, Adwaita), so
# that no set is mixed with icons from another era.
_icon_fallbacks() {
	case $1 in PiX) echo PiXflat ;; esac
}

# Link each cursor name of CURSOR_ALIASES that the base set lacks to the first
# equivalent cursor it has. Repeated passes let an alias point to another.
# Usage: _cursor_aliases BASE-CURSOR-DIR OUT-DIR BASE-NAME
_cursor_aliases() {
	local basecur=$1 outcur=$2 base=$3 pass entry name c made
	mkdir -p "$outcur"
	for pass in 1 2 3 4 5; do
		made=0
		for entry in "${CURSOR_ALIASES[@]}"; do
			name=${entry%%:*}
			[[ -e $basecur/$name || -L $outcur/$name ]] && continue
			for c in ${entry#*:}; do
				if [[ -e $basecur/$c ]]; then ln -s "../../$base/cursors/$c" "$outcur/$name"; made=1; break
				elif [[ -L $outcur/$c ]]; then ln -s "$c" "$outcur/$name"; made=1; break
				fi
			done
		done
		(( made )) || break
	done
	debug "$base: $(find "$outcur" -type l | wc -l) cursor aliases (pass $pass)"
}

# Link the icon names that Debian's programs request to the official images,
# at every size the base theme has them. A name the base theme already has is
# kept, unless the alias is marked with "!".
# Usage: _icon_aliases BASE-DIR OUT-DIR BASE-NAME
_icon_aliases() {
	local bdir=$1 out=$2 base=$3 entry name target rel f n i force
	local -a pairs=("${ICON_ALIASES[@]}")
	local -A imgs=()
	# nm-applet's animation frames while connecting, and those of its VPN icon
	for n in 01 02 03; do for i in $(seq -w 1 11); do pairs+=("nm-stage$n-connecting$i:network-idle"); done; done
	for i in $(seq -w 1 14); do pairs+=("nm-vpn-connecting$i:nm-vpn-active-lock"); done
	# File types: the official sets use the old GNOME names (gnome-mime-*);
	# current programs ask for the freedesktop.org names, linked to those images.
	pairs+=("application-octet-stream:unknown"    "application-x-generic:unknown"
		"text-plain:text-x-generic"              "application-x-zerosize:empty"
		"inode-x-empty:empty"
		"application-x-sharedlib:application-x-executable"
		"application-x-firmware:unknown"         "application-certificate:unknown"
		# Office documents, which file managers ask for by their full MIME names
		"application-vnd.openxmlformats-officedocument.wordprocessingml.document:x-office-document"
		"application-vnd.openxmlformats-officedocument.spreadsheetml.sheet:x-office-spreadsheet"
		"application-vnd.openxmlformats-officedocument.presentationml.presentation:x-office-presentation"
		"application-vnd.ms-word:x-office-document"   "application-msword:x-office-document"
		"application-vnd.ms-excel:x-office-spreadsheet"
		"application-vnd.ms-powerpoint:x-office-presentation"
		"application-vnd.oasis.opendocument.spreadsheet:x-office-spreadsheet"
		"application-vnd.oasis.opendocument.presentation:x-office-presentation"
		"application-vnd.oasis.opendocument.graphics:x-office-drawing")
	while IFS= read -r rel; do
		f=${rel##*/}; f=${f%.*}
		imgs[$f]+="$rel "
	done < <(cd "$bdir" && find . -mindepth 3 -maxdepth 3 \( -name '*.png' -o -name '*.svg' \) -printf '%P\n')
	for f in "${!imgs[@]}"; do
		[[ $f == gnome-mime-* ]] && pairs+=("${f#gnome-mime-}:$f")
	done
	for entry in "${pairs[@]}"; do
		name=${entry%%:*} target=${entry#*:} force=0
		if [[ $name == '!'* ]]; then name=${name#!} force=1; fi
		[[ -n ${imgs[$target]:-} ]] || continue
		if [[ -n ${imgs[$name]:-} ]] && (( ! force )); then continue; fi
		for rel in ${imgs[$target]}; do
			mkdir -p "$out/${rel%/*}"
			ln -sfn "../../../$base/$rel" "$out/${rel%/*}/$name.${rel##*.}"
		done
	done
}

# The menu button's Debian logo: Debian's white swirl on a red circle, made
# from desktop-base's white logo, the same file from Debian 10 on. Sets
# LOGO_BADGE to its path on the installed system; without that logo there is
# none, and the menu button shows Debian's plain logo. Usage: logo_badge_build ROOT
LOGO_BADGE=""
logo_badge_build() {
	local root=$1 f t paths
	LOGO_BADGE=""
	for f in "$SYS_ROOT"/usr/share/icons/{desktop-base,hicolor}/scalable/emblems/emblem-debian-white.svg; do
		[[ -f $f ]] && break
	done
	[[ -f $f ]] || return 0
	f=$(tr '\n\t' '  ' <"$f")
	# Its paths, white, in a group placed by the transform of the first group
	t=$(sed -n 's/^[^>]*>.*<g [^>]*transform="\([^"]*\)".*/\1/p' <<<"$f")
	paths=$(grep -o ' d="[^"]*"' <<<"$f" | sed 's/^ d=/<path d=/; s/$/\/>/')
	[[ -n $paths ]] || return 0
	# The swirl is 87 by 108 of 128; at 0.72 it sits well inside the circle
	{
		printf '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">\n'
		printf '<circle cx="64" cy="64" r="64" fill="#d70a53"/>\n'
		printf '<g fill="#ffffff" transform="translate(64 64) scale(0.72) translate(-64 -64) %s">\n%s\n</g>\n</svg>\n' \
			"${t:-translate(20.52,9.78)}" "$paths"
	} | _write "$root$SHARE/debian-menu.svg"
	LOGO_BADGE=$SHARE/debian-menu.svg
}

# Point the theme's Raspberry Pi logo names (LOGO_ICONS), such as the menu
# button's, at the Debian logo: LOGO_BADGE when built, else Debian's emblem
# from desktop-base or hicolor, else /usr/share/pixmaps/debian-logo.png (as in
# _logo_path). Files are looked up under SYS_ROOT; links use the paths on the
# installed system. VARIANT -white selects the white emblem for dark themes
# and fails when Debian has none; it is ignored when LOGO_BADGE is set.
# Usage: _logo_aliases OUT-DIR [VARIANT]
_logo_aliases() {
	local out=$1 v=${2:-} t f dir size ext n found=0
	if [[ -n $LOGO_BADGE ]]; then
		mkdir -p "$out/scalable/places"
		for n in "${LOGO_ICONS[@]}"; do ln -sfn "$LOGO_BADGE" "$out/scalable/places/$n.svg"; done
		return 0
	fi
	for t in desktop-base hicolor; do
		for f in "$SYS_ROOT/usr/share/icons/$t"/*/emblems/emblem-debian"$v".png \
			"$SYS_ROOT/usr/share/icons/$t/scalable/emblems/emblem-debian$v.svg"; do
			[[ -f $f ]] || continue
			f=${f#"$SYS_ROOT"}
			size=${f#/usr/share/icons/"$t"/}; size=${size%%/*}
			dir=$out/$size/places ext=${f##*.}
			mkdir -p "$dir"
			for n in "${LOGO_ICONS[@]}"; do ln -sfn "$f" "$dir/$n.$ext"; done
			found=1
		done
		(( ! found )) || return 0
	done
	[[ -z $v ]] || return 1
	if [[ -f $SYS_ROOT/usr/share/pixmaps/debian-logo.png ]]; then
		mkdir -p "$out/48x48/places"
		for n in "${LOGO_ICONS[@]}"; do ln -sfn /usr/share/pixmaps/debian-logo.png "$out/48x48/places/$n.png"; done
	fi
}

# Succeed if Debian ships its white logo (desktop-base), for dark themes.
_white_logo() {
	local t
	for t in desktop-base hicolor; do
		compgen -G "$SYS_ROOT/usr/share/icons/$t/*/emblems/emblem-debian-white.png" >/dev/null && return 0
		[[ -f $SYS_ROOT/usr/share/icons/$t/scalable/emblems/emblem-debian-white.svg ]] && return 0
	done
	return 1
}

# Create a dark theme's icon theme: the light theme's adapted set with
# Debian's white logo (or LOGO_BADGE), hidden from the appearance settings.
# Fails when Debian has no white logo. Usage: gen_logo_overlay NAME LIGHT-SET OUTPUT-DIR
gen_logo_overlay() {
	local name=$1 light=$2 out=$3 d dirs=""
	_logo_aliases "$out" -white || return 1
	for d in "$out"/*/places; do dirs+="${dirs:+,}${d#"$out"/}"; done
	{
		printf '[Icon Theme]\nName=%s\nComment=%s with the Debian logo for dark themes\nInherits=%s\nHidden=true\nDirectories=%s\n' \
			"$name" "$light" "$light" "$dirs"
		for d in ${dirs//,/ }; do
			if [[ $d == scalable/* ]]; then printf '\n[%s]\nSize=48\nMinSize=8\nMaxSize=512\nContext=Places\nType=Scalable\n' "$d"
			else printf '\n[%s]\nSize=%s\nContext=Places\nType=Fixed\n' "$d" "${d%%x*}"; fi
		done
	} >"$out/index.theme"
}

# Create the "<Base>-Debian" icon theme: it inherits the official set and adds
# the Debian logo and the cursor and icon names that Debian's programs ask for.
# Usage: gen_icon_overlay BASE-NAME OUTPUT-DIR
gen_icon_overlay() {
	local base=$1 out=$2 bdir=$SYS_ROOT/usr/share/icons/$1 inh d
	local -a dirs=()
	mkdir -p "$out"
	[[ -d $bdir/cursors ]] && _cursor_aliases "$bdir/cursors" "$out/cursors" "$base"
	_icon_aliases "$bdir" "$out" "$base"
	_logo_aliases "$out"
	mapfile -t dirs < <(cd "$out" && find . -mindepth 2 -maxdepth 2 -type d ! -path './cursors*' -printf '%P\n' | sort)
	debug "$base: icon aliases in ${#dirs[@]} directories"
	inh=$(sed -n 's/^Inherits[[:space:]]*=[[:space:]]*//p' "$bdir/index.theme" | first_line)
	# An icon that the set lacks comes first from the other Raspberry Pi OS sets
	# it falls back to, so that it keeps the Raspberry Pi OS look
	local pi=""
	for d in $(_icon_fallbacks "$base"); do
		[[ -f $SYS_ROOT/usr/share/icons/$d/index.theme ]] && pi+="$d,"
	done
	inh=$(tr ',' '\n' <<<"$base,$pi$inh,Adwaita,hicolor" | awk 'NF && !seen[$0]++' | paste -sd, -)
	{
		printf '[Icon Theme]\nName=%s (Debian)\n' "$base"
		printf 'Comment=Raspberry Pi OS %s icons and cursors with Debian compatibility names\n' "$base"
		printf 'Inherits=%s\nExample=folder\nDirectories=%s\n' "$inh" "$(IFS=,; echo "${dirs[*]}")"
		for d in "${dirs[@]}"; do   # the official theme's section for the directory, or a new one
			printf '\n'
			if grep -qxF "[$d]" "$bdir/index.theme"; then
				D="[$d]" awk '$0 == ENVIRON["D"] { p = 1; print; next } /^\[/ { p = 0 } p && NF' "$bdir/index.theme"
			elif [[ $d == scalable/* ]]; then
				printf '[%s]\nContext=Places\nSize=48\nMinSize=8\nMaxSize=512\nType=Scalable\n' "$d"
			else
				printf '[%s]\nContext=Places\nSize=%s\nType=Fixed\n' "$d" "${d%%x*}"
			fi
		done
	} >"$out/index.theme"
}

###############################################################################
# 6. Session: the Raspberry Pi Desktop session and login screen
#
# Raspberry Pi OS's desktop is an LXDE session profile: its login screen entry
# starts lxsession with its own profile, menu prefix and data directories, and
# this session is built the same way. Its configuration lives in the generated
# package under $SHARE/xdg and $SHARE/data, which only this session puts first
# in XDG_CONFIG_DIRS and XDG_DATA_DIRS, so Debian's LXDE session and all other
# sessions are unaffected. Settings a user makes in the session are saved in
# the user's own files and take precedence over these defaults.
###############################################################################

# File editors, used for the generated package and, through _track_file, for
# the user's own files (section 8).

# Replace a file's content with stdin, keeping its inode and permissions.
_write() {
	local tmp
	tmp=$(mktemp -p "${WORKDIR:-${TMPDIR:-/tmp}}")
	cat >"$tmp"
	mkdir -p -- "${1%/*}"
	cat "$tmp" >"$1"
	rm -f "$tmp"
}

# Set keys in a section of an INI file, creating them as needed.
# Usage: _ini_set FILE SECTION KEY VALUE [KEY VALUE]...
_ini_set() {
	local file=$1 sec=$2; shift 2
	_track_file "$file"
	while (( $# >= 2 )); do
		{ [[ -f $file ]] && cat -- "$file"; true; } \
			| S="[$sec]" K=$1 V=$2 awk '
				BEGIN { s = ENVIRON["S"]; k = ENVIRON["K"]; v = ENVIRON["V"] }
				/^[ \t]*\[.*\][ \t]*$/ {
					if (ins && !done) { print k "=" v; done = 1 }
					h = $0; gsub(/^[ \t]+|[ \t]+$/, "", h); ins = (h == s)
				}
				ins && index($0, "=") {
					kk = substr($0, 1, index($0, "=") - 1); gsub(/^[ \t]+|[ \t]+$/, "", kk)
					# The first line with this key gets the new value; later ones are dropped
					if (kk == k) { if (!done) { print k "=" v; done = 1 }; next }
				}
				{ print }
				END { if (!done) { if (!ins) { if (NR) print ""; print s } print k "=" v } }' \
			| _write "$file"
		shift 2
	done
}

# Copy the first existing system default into place, if the file is missing.
# Usage: _seed FILE DEFAULT...
_seed() {
	local dst=$1 src
	shift
	[[ -e $dst ]] && return 0
	for src; do
		if [[ -f $src ]]; then
			mkdir -p "$(dirname "$dst")"
			cp -- "$src" "$dst"
			return 0
		fi
	done
	return 1
}

# Replace the first <TAG>…</TAG> element of an Openbox rc.xml with
# CONTENT, or add CONTENT before the closing root tag if there is none.
# Usage: _xml_block FILE TAG CONTENT
_xml_block() {
	T=$2 C=$3 awk '
		BEGIN { t = ENVIRON["T"] }
		!done && $0 ~ "<" t "[ >]" { skip = 1 }
		skip { if ($0 ~ "</" t ">") { print ENVIRON["C"]; skip = 0; done = 1 }; next }
		!done && /<\/openbox_config>/ { print ENVIRON["C"]; done = 1 }
		{ print }' "$1" | _write "$1"
}

# Set <CHILD>VALUE</CHILD> inside the <PARENT> element, adding it if missing.
# Usage: _xml_child FILE PARENT CHILD VALUE
_xml_child() {
	P=$2 C=$3 V=$4 awk '
		BEGIN { p = ENVIRON["P"]; c = ENVIRON["C"]; el = "<" c ">" ENVIRON["V"] "</" c ">" }
		$0 ~ "<" p ">" { in_p = 1 }
		in_p && !done && $0 ~ "<" c ">.*</" c ">" { sub("<" c ">.*</" c ">", el); done = 1 }
		in_p && !done && $0 ~ "</" p ">" { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) "  " el; done = 1 }
		$0 ~ "</" p ">" { in_p = 0 }
		{ print }' "$1" | _write "$1"
}

# Print <font> elements for the given places, as Raspberry Pi OS sets them,
# with the theme's font and size. Usage: _xml_fonts PLACE...
_xml_fonts() {
	local p
	for p; do
		printf '    <font place="%s">\n      <name>%s</name>\n      <size>%s</size>\n      <weight>%s</weight>\n      <slant>Normal</slant>\n    </font>\n' \
			"$p" "$T_FONT_FAMILY" "$T_FONT_SIZE" "$T_FONT_WEIGHT"
	done
}

# Print yes when the Openbox theme THEME has rounded corners, else no.
# Raspberry Pi's Openbox reads the radius from the theme (border.radius: 2 for
# PiX, 1 for PiXflat and PiXnoir, 0 for PiXtrix and PiXonyx); Debian's has
# only roundCorners (Raspberry Pi's earlier patch), on or off.
# Usage: _ob_round THEME
_ob_round() {
	local r
	r=$(sed -n 's/^border\.radius:[[:space:]]*//p' "$SYS_ROOT/usr/share/themes/$1/openbox-3/themerc" 2>/dev/null | head -n 1)
	if [[ ${r:-0} == 0 ]]; then echo no; else echo yes; fi
}

# Apply the Raspberry Pi OS Openbox settings (rpd-rc.xml):
# the <theme> section with the theme's corners and invisible handles, one
# desktop and focusDesktop. Usage: _openbox_rc FILE
_openbox_rc() {
	local file=$1 fonts ob=$T_OB
	# The large window theme only where the theme package has it
	[[ -f $SYS_ROOT/usr/share/themes/$ob/openbox-3/themerc ]] || ob=$T_GTK
	fonts=$(_xml_fonts ActiveWindow InactiveWindow MenuHeader MenuItem ActiveOnScreenDisplay InactiveOnScreenDisplay)
	# The invisible resize borders are 10 pixels wide, Raspberry Pi's Openbox
	# default, and 20 for the Large and Larger sizes, as Raspberry Pi OS's
	# Appearance Settings set them; a theme without a border, such as PiXtrix,
	# has none otherwise.
	_xml_block "$file" theme "$(printf '  <theme>\n    <name>%s</name>\n    <titleLayout>LIMC</titleLayout>\n    <keepBorder>yes</keepBorder>\n    <roundCorners>%s</roundCorners>\n    <invisibleHandles>yes</invisibleHandles>\n    <invHandleWidth>%s</invHandleWidth>\n    <animateIconify>yes</animateIconify>\n%s\n  </theme>' "$ob" "$(_ob_round "$ob")" "$T_HANDLE" "$fonts")"
	# Use Openbox's own menu when LXDE's is missing
	if [[ ! -f /usr/share/lxde/openbox/menu.xml ]]; then
		sed -i 's#<file>/usr/share/lxde/openbox/menu.xml</file>#<file>menu.xml</file>#' "$file"
	fi
	_xml_child "$file" desktops number 1
	_xml_child "$file" focus focusDesktop yes
	# Windows redraw while being resized, as in Debian's session (Raspberry
	# Pi OS leaves them blank until the mouse is released)
	_xml_child "$file" resize drawContents yes
}

# Bind the Openbox keys of Raspberry Pi OS (rpd-rc.xml) whose program is
# installed: the panel's menu and dialogs, the terminal, the task manager,
# window halves and the Shutdown dialog. With RASPBERRY-PI-FILE set, the file
# is Raspberry Pi OS's own for this release and keeps its keys, as they are
# its behaviour; two get the program the session has in place of Raspberry
# Pi's: the terminal (LXTerminal, see _term_cmd) and the power button
# (Raspberry Pi's pwrkey, not installed: the session's own does the same,
# see pwrkey_build). Without it (Debian's LXDE settings), Raspberry Pi OS 13's
# keys are bound over Debian's. A key's existing binding is replaced.
# Of the keys that Raspberry Pi OS leaves unbound, only the display key of
# laptops (XF86Display, often Fn+F7) is bound, as Debian's LXDE session
# binds it: it opens LXRandR, and no program or Raspberry Pi OS key uses it.
# Debian's other LXDE keys are not added: Raspberry Pi OS's Super key opens
# the menu at once (Super+E and the like would reach the menu), and it
# leaves the rest to programs. Keys that neither binds stay unbound, such as
# Ctrl+Alt+L (Raspberry Pi OS locks the screen in its Wayland session only:
# LightDM's lock alone lets the session's console be switched back to), the
# lock key and the wireless key (a laptop's firmware switches its radios
# itself, where it does).
# Usage: _openbox_keys RC-XML [RASPBERRY-PI-FILE]
_openbox_keys() {
	local file=$1 k c ctl=lxpanelctl mag=""
	local -a keys
	if [[ -n ${2:-} ]]; then
		keys=("C-A-T|$(_term_cmd)")
		if grep -q 'key="XF86PowerOff"' "$2"; then keys+=("XF86PowerOff|$SHARE/pwrkey"); fi
	elif (( S_PI_PANEL )); then
		ctl=lxpanelctl-pi
		keys=("Super_L|$ctl command smenu menu" "C-Escape|$ctl command smenu menu" "A-F2|gui-runcmd"
			"C-A-B|$ctl command bluetooth menu")
	else
		keys=("Super_L|$ctl menu" "C-Escape|$ctl menu" "A-F2|$ctl run")
	fi
	[[ -n ${2:-} ]] || keys+=("C-A-S|$ctl move" "C-A-T|$(_term_cmd)" "C-S-Escape|lxtask" "Print|scrot"
		"C-A-End|pishutdown" "C-A-Delete|pishutdown" "XF86PowerOff|$SHARE/pwrkey")
	# The volume keys and the magnifier, through the panel's plugins
	if [[ -z ${2:-} ]] && (( S_PI_PANEL )); then
		keys+=("XF86AudioRaiseVolume|$ctl command volumepulse volu" "XF86AudioLowerVolume|$ctl command volumepulse vold"
			"XF86AudioMute|$ctl command volumepulse mute" "C-A-M|$ctl command magnifier toggle")
	fi
	[[ -n ${2:-} ]] || ! (( USE_NETMAN )) || keys+=("C-A-W|$ctl command netman menu")
	keys+=("XF86Display|lxrandr")
	for k in "${keys[@]}"; do
		c=${k#*|} k=${k%%|*}
		# The session's own helpers are installed with it
		[[ $c == "$SHARE"/* ]] || command -v "${c%% *}" >/dev/null || [[ -x $SYS_ROOT/usr/bin/${c%% *} ]] || continue
		# Every binding of the key is replaced, however its modifiers are
		# ordered (C-A-Delete and A-C-Delete are the same keys to Openbox)
		K=$k C=$c awk '
			function norm(s,  n, p, i, j, t) {
				n = split(s, p, "-")
				for (i = 1; i < n - 1; i++) for (j = i + 1; j < n; j++) if (p[j] < p[i]) { t = p[i]; p[i] = p[j]; p[j] = t }
				t = ""; for (i = 1; i <= n; i++) t = t (i > 1 ? "-" : "") p[i]
				return t
			}
			BEGIN {
				want = norm(ENVIRON["K"])
				nb = "    <keybind key=\"" ENVIRON["K"] "\">\n      <action name=\"Execute\">\n        <command>" ENVIRON["C"] "</command>\n      </action>\n    </keybind>"
			}
			!inb && match($0, /<keybind key="[^"]+"/) && norm(substr($0, RSTART + 14, RLENGTH - 15)) == want {
				if (!done) { print nb; done = 1 }
				inb = ($0 !~ /<\/keybind>/); next
			}
			inb { if ($0 ~ /<\/keybind>/) inb = 0; next }
			!done && /<\/keyboard>/ { print nb; done = 1 }
			{ print }' "$file" | _write "$file"
	done
	# Remove the keys of Raspberry Pi OS whose program is not installed, and
	# the magnifier's (Ctrl+Alt+M) unless its panel plugin is (see pi_apps)
	compgen -G "$SYS_ROOT/usr/lib/*/lxpanel-pi/magnifier.so" >/dev/null && mag=1
	SH=$SHARE MAG=$mag awk '
		/<keybind[ >]/ && !inb { blk = $0; inb = 1; if ($0 ~ /<\/keybind>/) { inb = 0; flush() }; next }
		inb { blk = blk "\n" $0; if ($0 ~ /<\/keybind>/) { inb = 0; flush() }; next }
		{ print }
		function flush(  c) {
			if (ENVIRON["MAG"] == "" && blk ~ /<command>lxpanelctl(-pi)? command magnifier /) return
			if (match(blk, /<command>[^< ]+/)) {
				c = substr(blk, RSTART + 9, RLENGTH - 9)
				if (index(c, ENVIRON["SH"] "/") != 1 && system("command -v \"" c "\" >/dev/null 2>&1") != 0) return
			}
			print blk
		}' "$file" | _write "$file"
}

# Print the terminal command. Raspberry Pi OS's x-terminal-emulator is
# LXTerminal, while Debian ranks xterm above it; so LXTerminal, unless the
# user chose the default terminal (update-alternatives) or it is missing.
_term_cmd() {
	if command -v lxterminal >/dev/null \
		&& ! update-alternatives --query x-terminal-emulator 2>/dev/null | grep -qx 'Status: manual'; then
		echo lxterminal
	else echo x-terminal-emulator; fi
}

# Print the terminal's launcher, for the command of _term_cmd.
_terminal() {
	if [[ $(_term_cmd) == lxterminal ]]; then _launcher lxterminal.desktop x-terminal-emulator.desktop lxde-x-terminal-emulator.desktop
	else _launcher x-terminal-emulator.desktop lxterminal.desktop lxde-x-terminal-emulator.desktop; fi
}

# Print the first installed application launcher (.desktop file) of a list.
_launcher() {
	local id
	for id; do
		if [[ -f /usr/share/applications/$id ]]; then printf '%s\n' "$id"; return 0; fi
	done
	return 1
}
# Print the browser launcher: the generic "Web Browser" entry when Debian has
# a default browser, as in Raspberry Pi OS; otherwise an installed browser.
# Panels name it by id (found in the session's applications folder although
# hidden from the menu); by path, the X panels would ask to execute the file.
_browser() {
	if [[ -x /usr/bin/x-www-browser ]]; then echo x-www-browser.desktop
	else _launcher firefox-esr.desktop chromium.desktop lxde-x-www-browser.desktop; fi
}

# Print the parts of the Raspberry Pi OS panel (rpd-x-core) that both panel
# programs share. Usage: _panel_global [KEY=VALUE]...
_panel_global() {
	printf '# lxpanel <profile> config file. Manually editing is not recommended.\n'
	printf '# Use preference dialog in lxpanel to adjust config when you can.\n\n'
	printf 'Global {\n'
	printf '  %s\n' edge=top align=left margin=0 widthtype=percent width=100 "height=$T_PANEL_ICON" transparent=0 \
		tintcolor=#000000 alpha=0 autohide=0 heightwhenhidden=2 setdocktype=1 setpartialstrut=1 \
		usefontcolor=0 fontsize=12 fontcolor=#ffffff usefontsize=0 background=0 \
		backgroundfile=/usr/share/lxpanel/images/background.png "iconsize=$T_PANEL_ICON" monitor=0 "$@"
	printf '}\n'
}
# Print one panel plugin. Usage: _panel_plugin TYPE [CONFIG-LINE]...
_panel_plugin() {
	local t=$1; shift
	printf 'Plugin {\n  type=%s\n' "$t"
	[[ $t == taskbar ]] && printf '  expand=1\n'
	printf '  Config {\n'
	if (( $# )); then printf '    %s\n' "$@"; fi
	printf '  }\n}\n'
}
# Print the launchers (web browser, file manager, terminal) and the taskbar.
_panel_tasks() {
	local id fm=pcmanfm.desktop
	local -a buttons=()
	(( S_PI_FM )) && fm=pcmanfm-pi.desktop
	for id in "$(_browser)" \
		"$fm" "$(_terminal)"; do
		if [[ -n $id ]]; then buttons+=("Button {" "  id=$id" "}"); fi
	done
	_panel_plugin space Size=4
	_panel_plugin launchbar "${buttons[@]}"
	_panel_plugin space Size=8
	_panel_plugin taskbar tooltips=1 IconsOnly=0 ShowAllDesks=0 UseMouseWheel=1 UseUrgencyHint=1 FlatButton=0 \
		"MaxTaskWidth=$T_TASK_WIDTH" spacing=1 GroupedTasks=0
	_panel_plugin space Size=2
}

# Print the Raspberry Pi OS panel for Debian's lxpanel: the menu with the
# Debian logo, launchers, taskbar, tray, volume, clock and,
# if there is a battery, the battery, spaced as in Raspberry Pi OS. Plugins
# only Raspberry Pi has are left out; network and Bluetooth appear in the
# tray through Debian's applets.
_lxpanel_layout() {
	local plugins="$SYS_ROOT/usr/lib/*/lxpanel/plugins"
	_panel_global point_at_menu=0
	_panel_plugin menu padding=4 image=start-here "system {" "}" "separator {" "}" \
		"item {" "  image=system-run" "  command=run" "}" "separator {" "}" \
		"item {" "  image=system-shutdown" "  command=logout" "}"
	[[ $T_ERA == trixie ]] && _panel_plugin separator
	_panel_tasks
	_panel_plugin tray
	if compgen -G "$plugins/volume.so" >/dev/null; then _panel_plugin space Size=2; _panel_plugin volume; fi
	_panel_plugin space Size=2
	_panel_plugin dclock ClockFmt=%R 'TooltipFmt=%A %x' BoldFont=0 IconOnly=0 CenterText=1
	if compgen -G "$plugins/batt.so" >/dev/null && has_battery; then _panel_plugin space Size=2; _panel_plugin batt HideIfNoBattery=1; fi
}

# Print the panel for Raspberry Pi's own panel program, as this release's
# rpd-x-core defines it (see _pi_layout; desktop_known checked that it does).
_pi_panel_layout() {
	local f
	f=$(pi_unpack "$PANEL_PKG" "$H_SUITE" "$H_ARCH") || f=""
	[[ -f $f/$PANEL_LAYOUT ]] || die "cannot read Raspberry Pi OS $H_SUITE's panel layout ($PANEL_PKG)"
	_pi_layout "$f/$PANEL_LAYOUT" lxpanel-pi
}
# Print a Raspberry Pi OS panel layout with its spaces and separators, so that
# later releases' layouts are followed. Removed, keeping their spaces as on
# Raspberry Pi OS: plugins left out (panel_drop), the magnifier (Raspberry Pi
# OS shows it only with its program, which it does not install; here it stays
# off the panel for the user to add), plugins not installed and, without a
# battery, the battery plugin.
# The launchers name the browser, file manager and terminal installed here.
# Usage: _pi_layout FILE PLUGIN-DIR (under /usr/lib/*/)
_pi_layout() {
	local f=$1 dir=$2 t keep="" fm=pcmanfm.desktop nobatt=0
	(( S_PI_FM )) && fm=pcmanfm-pi.desktop
	while read -r t; do
		if compgen -G "$SYS_ROOT/usr/lib/*/$dir/$t.so" >/dev/null; then keep+="$t|"; fi
	done < <(sed -n 's/^[[:space:]]*type=//p' "$f" | sort -u)
	has_battery || nobatt=1
	KEEP="${keep}space|separator|launchbar|taskbar|tray|menu|dclock" DROP="$(panel_drop)|magnifier" FM=$fm \
	NOBATT=$nobatt B=$(_browser || true) \
	T=$(_terminal || true) awk '
		depth == 0 && !/\{/ { if (n == 0) head = head $0 "\n"; next }
		{
			if (depth == 0) { n++; blk[n] = ""; typ[n] = "" }
			if ($0 ~ /^[ \t]*type=/ && typ[n] == "") { typ[n] = $0; sub(/^[ \t]*type=/, "", typ[n]) }
			if ($0 ~ /^[ \t]*id=/) {
				id = $0; sub(/^[ \t]*id=/, "", id); r = ""
				if (id == "x-www-browser.desktop" || id == "lxde-x-www-browser.desktop") r = ENVIRON["B"]
				else if (id == "x-terminal-emulator.desktop" || id == "lxterminal.desktop") r = ENVIRON["T"]
				else if (id == "pcmanfm.desktop") r = ENVIRON["FM"]
				if (r != "") sub(/id=.*/, "id=" r)
			}
			blk[n] = blk[n] $0 "\n"
			depth += gsub(/\{/, "{") - gsub(/\}/, "}")
		}
		END {
			keep = "^(" ENVIRON["KEEP"] ")$"; drop = "^(" ENVIRON["DROP"] ")$"
			printf "%s", head
			for (i = 1; i <= n; i++) {
				if (typ[i] != "" && (typ[i] ~ drop || typ[i] !~ keep)) continue
				if (ENVIRON["NOBATT"] == 1 && typ[i] ~ /^(batt|ptbatt)$/) continue
				printf "%s", blk[i]
			}
		}' "$f"
}

# Print Raspberry Pi OS's panel button rules: flat buttons with its spacing,
# so that 36 px icons fit the 36 px panel.
_panel_button_css() {
	printf '%s\n' \
		'#PanelToplevel button { padding: 2px 3px; margin: 0px; border: 0px; background-image: none; }' \
		'#PanelToplevel button image { -gtk-icon-shadow: none; -gtk-icon-effect: none; }' \
		'#launchbar button { padding: 0px; }'
}

# The categories of the Raspberry Pi OS menu, in its order: id, name, icon,
# freedesktop category, and the matching Debian directory file (lxmenu-data),
# whose translations are kept.
readonly MENU_CATS=(
	"development|Programming|applications-development|Development|lxde-development"
	"education|Education|applications-engineering|Education|lxde-education"
	"science|Science|applications-science|Science|lxde-science"
	"office|Office|applications-office|Office|lxde-office"
	"network|Internet|applications-internet|Network|lxde-network"
	"audio-video|Sound & Video|applications-multimedia|AudioVideo|lxde-audio-video"
	"graphics|Graphics|applications-graphics|Graphics|lxde-graphics"
	"game|Games|applications-games|Game|lxde-game"
	"other|Other|applications-other||lxde-other"
	"system-tools|System Tools|applications-system|System|lxde-system"
	"utility|Accessories|applications-accessories|Utility|lxde-utility"
	"help|Help|gnome-help|Help|"
	"settings|Preferences|preferences-desktop|Settings|lxde-settings"
)

# Write the Raspberry Pi OS application menu from this release's package, so
# that later releases' changes are followed: the menu file, its category
# names and the application entries it renames or moves (raspi-ui-overrides),
# for installed applications only. Debian's settings tools stay shown, as
# Debian has no Control Centre. Without the package, the built-in menu is
# written. Usage: _session_menu XDG-DIR DATA-DIR
_session_menu() {
	local xdg=$1 data=$2 prefix x f
	prefix=$MENU_PREFIX
	x=$( (pi_unpack "$ART_PKG" "$H_SUITE" "$H_ARCH") 2>/dev/null ) || x=$WORKDIR/none
	if [[ ! -f $x/etc/xdg/menus/${prefix}applications.menu ]]; then _menu_write "$xdg" "$data"; return 0; fi
	_write "$xdg/menus/${prefix}applications.menu" <"$x/etc/xdg/menus/${prefix}applications.menu"
	for f in "$x"/usr/share/desktop-directories/*.directory; do
		[[ -f $f ]] && _write "$data/desktop-directories/${f##*/}" <"$f"
	done
	for f in "$x"/usr/share/raspi-ui-overrides/applications/*.desktop; do
		[[ -f $f && -f /usr/share/applications/${f##*/} ]] && grep -q '^Exec=' "$f" || continue
		# Settings tools stay shown; other hidden entries (duplicates) stay hidden
		if grep -q '^Categories=.*Settings' "$f"; then grep -vE '^(NoDisplay|Hidden)=true' "$f"; else cat -- "$f"; fi \
			| _write "$data/applications/${f##*/}"
	done
	[[ ! -f $x/usr/share/raspi-ui-overrides/applications/mimeapps.list ]] \
		|| _write "$xdg/mimeapps.list" <"$x/usr/share/raspi-ui-overrides/applications/mimeapps.list"
	# A category file the menu names but neither the package nor Debian
	# provides (an older Debian may lack one) is written from MENU_CATS
	local d e id name icon
	while read -r d; do
		[[ -f $data/desktop-directories/$d || -f /usr/share/desktop-directories/$d ]] && continue
		# The category's id without the menu prefix: the session's (rpd-) or
		# LXDE's (lxde-help.directory in Raspberry Pi OS's own menu)
		id=${d%.directory} id=${id#"$prefix"} id=${id#lxde-} id=${id#rpd-}
		name=${id^} icon=applications-other
		for e in "${MENU_CATS[@]}"; do
			if [[ ${e%%|*} == "$id" ]]; then IFS='|' read -r _ name icon _ _ <<<"$e"; fi
		done
		printf '[Desktop Entry]\nType=Directory\nName=%s\nIcon=%s\n' "$name" "$icon" | _write "$data/desktop-directories/$d"
	done < <(sed -n 's/.*<Directory>\([^<]*\)<\/Directory>.*/\1/p' "$xdg/menus/${prefix}applications.menu" | sort -u)
}

# Write the built-in Raspberry Pi OS application menu: its category order,
# names and icons, separators before Help and Preferences, and uncategorised
# entries (Logout) at the end. Category names that match Debian's
# (lxmenu-data) keep Debian's translations. Usage: _menu_write XDG-DIR DATA-DIR
_menu_write() {
	local xdg=$1 data=$2 prefix entry id name icon cat deb f
	local -a cats=("${MENU_CATS[@]}")
	prefix=$MENU_PREFIX
	{
		printf '<?xml version="1.0"?>\n<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"\n'
		printf ' "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">\n'
		printf '<!-- The Raspberry Pi OS application menu, written by %s -->\n<Menu>\n  <Name>Applications</Name>\n' "$APP_NAME"
		printf '  <Directory>%sapplications.directory</Directory>\n  <DefaultAppDirs/>\n  <DefaultDirectoryDirs/>\n  <DefaultMergeDirs/>\n' "$prefix"
		for entry in "${cats[@]}"; do
			IFS='|' read -r id name icon cat deb <<<"$entry"
			printf '  <Menu>\n    <Name>%s</Name>\n    <Directory>%s%s.directory</Directory>\n' "$id" "$prefix" "$id"
			if [[ -n $cat ]]; then
				printf '    <Include>\n      <Category>%s</Category>\n    </Include>\n  </Menu>\n' "$cat"
			else
				printf '    <OnlyUnallocated/>\n    <Include>\n      <All/>\n    </Include>\n  </Menu>\n'
			fi
		done
		printf '  <Layout>\n'
		for id in development education science office network audio-video graphics game other system-tools utility; do
			printf '    <Menuname>%s</Menuname>\n' "$id"
		done
		printf '    <Merge type="menus"/>\n    <Separator/>\n    <Menuname>help</Menuname>\n    <Separator/>\n'
		printf '    <Menuname>settings</Menuname>\n    <Separator/>\n    <Merge type="files"/>\n  </Layout>\n</Menu>\n'
	} | _write "$xdg/menus/${prefix}applications.menu"
	printf '[Desktop Entry]\nType=Directory\nName=Applications\nIcon=applications-other\n' \
		| _write "$data/desktop-directories/${prefix}applications.directory"
	for entry in "${cats[@]}"; do
		IFS='|' read -r id name icon cat deb <<<"$entry"
		f=/usr/share/desktop-directories/$deb.directory
		{
			printf '[Desktop Entry]\nType=Directory\nName=%s\nIcon=%s\n' "$name" "$icon"
			if [[ -n $deb && -f $f ]] && [[ $(sed -n 's/^Name=//p' "$f") == "$name" ]]; then grep '^Name\[' "$f" || true; fi
		} | _write "$data/desktop-directories/$prefix$id.directory"
	done
}

# Print the Debian logo for the menu button, from packages every Debian
# desktop has: desktop-base (emblem-debian), else debconf (debian-logo).
_logo_path() {
	local f
	for f in /usr/share/icons/desktop-base/64x64/emblems/emblem-debian.png \
		/usr/share/icons/hicolor/64x64/emblems/emblem-debian.png \
		/usr/share/icons/desktop-base/48x48/emblems/emblem-debian.png \
		/usr/share/icons/hicolor/48x48/emblems/emblem-debian.png \
		/usr/share/pixmaps/debian-logo.png; do
		if [[ -f $f ]]; then printf '%s\n' "$f"; return 0; fi
	done
	return 1
}

# Print a large Debian logo for the login screen's default user picture.
_greeter_logo() {
	local f
	for f in /usr/share/icons/desktop-base/128x128/emblems/emblem-debian.png \
		/usr/share/icons/hicolor/128x128/emblems/emblem-debian.png \
		/usr/share/icons/desktop-base/scalable/emblems/emblem-debian.svg; do
		if [[ -f $f ]]; then printf '%s\n' "$f"; return 0; fi
	done
	_logo_path
}

# Print the theme's wallpaper; print nothing (and warn) if it is not installed.
# The session package brings the link (see wallpaper_links), so the package's
# file is checked.
_wallpaper_path() {
	local w=$WALLS/$T_WALL_DEFAULT files
	# Not a pipe into grep -q: with pipefail, its early exit fails the pipe
	files=$'\n'$(wall_files "${T_WALL_DEFAULT%%/*}")$'\n'
	if [[ $files == *$'\n'"/usr/share/rpd-wallpaper/${T_WALL_DEFAULT##*/}"$'\n'* ]]; then
		printf '%s\n' "$w"
	else
		warn "Wallpaper $w not found; the desktop shows its background colour."
	fi
}

# Write the session's lxsession profile: Raspberry Pi OS's desktop.conf with
# the chosen theme, and the autostart list. Usage: _session_profile XDG-DIR
_session_profile() {
	local dir=$1/lxsession/$S_PROFILE ctl=lxpanelctl images=1 fm=pcmanfm
	(( S_PI_PANEL )) && ctl=lxpanelctl-pi
	(( S_PI_FM )) && fm=pcmanfm-pi
	# Raspberry Pi OS turns menu images off, and Raspberry Pi's panel shows
	# menu icons regardless; Debian's panel shows them only when it is on
	(( S_PI_PANEL )) && images=0
	{
		# LXDE's authentication agent, as in Raspberry Pi OS's X session
		printf '[Session]\nwindow_manager=%s/openbox\ndisable_autostart=no\npolkit/command=lxpolkit\n' "$SHARE"
		printf 'clipboard/command=lxclipboard\nxsettings_manager/command=build-in\nproxy_manager/command=build-in\n'
		# No keyring/command: Raspberry Pi OS's ssh-agent there would be a
		# second SSH agent, whose socket nothing uses. The session has
		# Debian's, as Debian's LXDE does: the X session's (Xsession) or the
		# user's systemd one, which sets SSH_AUTH_SOCK
		printf 'quit_manager/command=lxsession-logout\n'
		printf 'quit_manager/image=/usr/share/lxde/images/logout-banner.png\nquit_manager/layout=top\n'
		# The lock command as Raspberry Pi OS and Debian's LXDE name it
		printf 'lock_manager/command=lxlock\nterminal_manager/command=%s\nlauncher_manager/command=%s\n' "$(_term_cmd)" "$ctl"
		# The session's own applications that lxsession starts only on request,
		# for its settings window; those it starts at login are left empty
		printf 'file_manager/command=%s\nwebbrowser/command=x-www-browser\n' "$fm"
		# LXDE's task manager, which Debian's LXDE desktop installs
		if command -v lxtask >/dev/null; then printf 'tasks/command=lxtask\n'; fi
		printf '\n'
		printf '[GTK]\nsNet/ThemeName=%s\nsNet/IconThemeName=%s\nsGtk/FontName=%s\n' "$T_GTK" "$T_ICONS" "$T_FONT"
		printf 'iGtk/ToolbarStyle=3\niGtk/ButtonImages=0\niGtk/MenuImages=%s\niGtk/CursorThemeSize=%s\n' "$images" "$T_CURSOR_SIZE"
		printf 'iXft/Antialias=1\niGtk/AutoMnemonics=1\niGtk/EnableMnemonics=1\nsGtk/ColorScheme=%s\n' "$(color_scheme)"
		printf 'sGtk/CursorThemeName=%s\niGtk/ToolbarIconSize=%s\nsGtk/IconSizes=gtk-large-toolbar=%s,%s\n' "$T_ICONS" "${T_TB_SIZE:-3}" "$T_TB_ICON" "$T_TB_ICON"
		printf 'sNet/SoundThemeName=%s\niNet/EnableEventSounds=1\niNet/EnableInputFeedbackSounds=1\n' "$T_SOUND_THEME"
		printf 'iXft/Hinting=1\nsXft/HintStyle=hintfull\nsXft/RGBA=rgb\n\n'
		printf '[Mouse]\nAccFactor=20\nAccThreshold=10\nLeftHanded=0\n\n[Keyboard]\nDelay=500\nInterval=30\nBeep=1\n\n'
		printf '[State]\nguess_default=true\n\n[Dbus]\nlxde=true\n\n[Environment]\nmenu_prefix=%s\n' "$MENU_PREFIX"
	} | _write "$dir/desktop.conf"
	{
		# Raspberry Pi OS's list also starts xscreensaver, which this look
		# never installs; the screen blanks after ten minutes by the X
		# server's own defaults, as there
		printf '@%s/panel\n@%s/desktop\n' "$SHARE" "$SHARE"
		printf '@%s/compositor\n' "$SHARE"
	} | _write "$dir/autostart"
}

# Write Raspberry Pi OS's desktop and file manager settings (pcmanfm.conf,
# desktop-items, libfm.conf): for Debian's file manager under the session's
# profile, and for Raspberry Pi's, which reads the 'default' profile.
# Usage: _session_files XDG-DIR
_session_files() {
	local xdg=$1 d i f
	for d in "$xdg/pcmanfm/$S_PROFILE" "$xdg/pcmanfm/default"; do
		for i in 0 1; do
			{
				printf '[*]\nwallpaper_mode=crop\nwallpaper_common=1\nwallpaper=%s\n' "$S_WALL"
				printf 'desktop_bg=%s\ndesktop_fg=%s\ndesktop_shadow=%s\ndesktop_font=%s\n' "$T_DESK_BG" "$T_DESK_FG" "$T_DESK_SHADOW" "$T_FONT"
				# Trash and drive icons on the first monitor only
				printf 'show_wm_menu=0\nsort=mtime;ascending;\nshow_documents=0\nshow_trash=%s\nshow_mounts=%s\n' $(( !i )) $(( !i ))
			} | _write "$d/desktop-items-$i.conf"
		done
		f=$d/pcmanfm.conf
		_ini_set "$f" config bm_open_method 0
		_ini_set "$f" volume mount_on_startup 0 mount_removable 0 autorun 0
		_ini_set "$f" ui always_show_tabs 0 max_tab_chars 32 win_width 640 win_height 480 splitter_pos 150 \
			view_mode icon show_hidden 0 sort "name;ascending;" columns "name;size;mtime;" \
			toolbar "newtab;navigation;home;" show_statusbar 1 pathbar_mode_buttons 0
		[[ $d == */default ]] || _ini_set "$f" ui side_pane_mode places
		_ini_set "$f" desktop desktop_bg "$T_DESK_BG" desktop_fg "$T_DESK_FG" desktop_shadow "$T_DESK_SHADOW" \
			show_wm_menu 0 wallpaper_mode crop wallpaper "$S_WALL"
		if [[ $d == */default ]]; then
			# Raspberry Pi's file manager keeps here what Debian's keeps in
			# libfm.conf: menus, side pane and icon sizes
			_fm_shared_conf "$f"
			_ini_set "$f" config terminal "$(_term_cmd) %s"
		fi
	done
	# Debian's libfm.conf, with Raspberry Pi OS's values
	_seed "$xdg/libfm/libfm.conf" "$SYS_ROOT"/etc/xdg/libfm/libfm.conf || true
	_fm_shared_conf "$xdg/libfm/libfm.conf"
}

# Set what both file managers read the same way: menus, thumbnails, icon
# sizes and the side pane's places. Usage: _fm_shared_conf FILE
_fm_shared_conf() {
	_ini_set "$1" config cutdown_menus 1 real_expanders 1 single_click 0 use_trash 1 confirm_del 1 \
		thumbnail_local 1 thumbnail_max 2048
	_ini_set "$1" ui big_icon_size "$T_FOLDER_ICON" small_icon_size "$T_SMALL_ICON" thumbnail_size "$T_THUMB" \
		pane_icon_size "$T_PANE_ICON" show_thumbnail 1
	_ini_set "$1" places places_home 1 places_desktop 0 places_root 1 places_computer 0 places_trash 0 \
		places_applications 0 places_network 0 places_unmounted 1 places_volmounts 1
}

# Write the session's application entries and autostart overrides, as
# Raspberry Pi OS keeps them in raspi-ui-overrides: Raspberry Pi's file manager as "File Manager" for folders and
# Desktop Preferences, the appearance settings with the session's themes, and
# hidden Blueman windows and tray applets that Raspberry Pi OS does not show.
# Usage: _session_entries XDG-DIR DATA-DIR
_session_entries() {
	local xdg=$1 apps=$2/applications f id
	if (( S_PI_FM )); then
		# Raspberry Pi's file manager entry, run as pcmanfm-pi on Debian (its
		# repacked package keeps it in its own folder, out of other sessions'
		# menus); Debian's entry is hidden in the session
		f=$apps/pcmanfm.desktop
		[[ -f $f ]] || f=/usr/share/pcmanpi/pcmanfm-pi.desktop
		[[ ! -f $f ]] || sed -E 's/^Name=.*/Name=File Manager/; s/^(Exec|TryExec)=pcmanfm( |$)/\1=pcmanfm-pi\2/' "$f" | _write "$apps/pcmanfm-pi.desktop"
		printf '[Desktop Entry]\nType=Application\nName=PCMan File Manager\nExec=pcmanfm %%U\nNoDisplay=true\n' \
			| _write "$apps/pcmanfm.desktop"
		f=$apps/pcmanfm-desktop-pref.desktop
		[[ -f $f ]] || f=/usr/share/applications/pcmanfm-desktop-pref.desktop
		[[ ! -f $f ]] || sed -E 's/^(Exec|TryExec)=pcmanfm( |$)/\1=pcmanfm-pi\2/' "$f" | _write "$apps/pcmanfm-desktop-pref.desktop"
		_ini_set "$xdg/mimeapps.list" 'Default Applications' inode/directory pcmanfm-pi.desktop
	fi
	# The generic "Web Browser" entry, also the default for web links
	if [[ -x /usr/bin/x-www-browser ]]; then
		printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Web Browser' 'TryExec=/usr/bin/x-www-browser' \
			'Exec=x-www-browser %U' 'Terminal=false' 'StartupNotify=true' 'Icon=web-browser' 'NoDisplay=true' \
			'MimeType=text/html;text/xml;application/xml;application/xhtml+xml;application/xhtml_xml;x-scheme-handler/http;x-scheme-handler/https;' \
			| _write "$apps/x-www-browser.desktop"
		for f in text/html text/xml application/xml application/xhtml+xml application/xhtml_xml x-scheme-handler/http x-scheme-handler/https; do
			_ini_set "$xdg/mimeapps.list" 'Default Applications' "$f" x-www-browser.desktop
		done
	fi
	# Appearance settings: Customize Look and Feel
	f=$apps/lxappearance.desktop
	[[ -f $f ]] || f=/usr/share/applications/lxappearance.desktop
	if [[ -f $f ]]; then
		sed -E "s|^Exec=.*|Exec=$SHARE/appearance|; /^TryExec=/d; /^NoDisplay=/d; /^OnlyShowIn=/d" "$f" \
			| { cat; echo 'OnlyShowIn=LXDE;'; } | _write "$apps/lxappearance.desktop"
	fi
	# Hide Blueman's windows where Raspberry Pi's panel has its Bluetooth plugin:
	# opening one would start a second Bluetooth icon and pairing agent
	if (( S_PI_PANEL )); then
		for f in /usr/share/applications/blueman-manager.desktop /usr/share/applications/blueman-adapters.desktop; do
			[[ ! -f $f ]] || { sed '/^NoDisplay=/d' "$f"; echo 'NoDisplay=true'; } | _write "$apps/${f##*/}"
		done
	fi
	# Hide clipboard managers and other volume applets, which Raspberry Pi OS
	# lacks; screen lockers and screensavers, as Raspberry Pi OS's session
	# starts none (a user's own start entry starts one); the program of
	# Debian's LXDE that adds bookmarks of the user's folders to the file
	# manager at each login (Raspberry Pi OS has no bookmarks of its own);
	# the Bluetooth applet where
	# Raspberry Pi's panel has its own plugin; nm-applet where its network
	# plugin is used; the tray icons of wicd and ConnMan where NetworkManager
	# runs the network, as the panel shows its own; and LXDE's authentication
	# agent, which the session starts itself, and the other desktops' agents
	# (MATE's comes with Debian's LXDE), which would race it at login and show
	# an "already exists" error; and compositors, which the
	# session starts only with NVIDIA's own driver (compositor_build). A user
	# can enable them again in Desktop Session Settings.
	local -a pats=(volumeicon pasystray pnmixer diodon clipit parcellite
		light-locker xscreensaver xss-lock xautolock lxpolkit polkit-mate-authentication-agent
		polkit-gnome-authentication-agent picom compton user-dirs-update-gtk)
	(( S_PI_PANEL )) && pats+=(blueman)
	(( USE_NETMAN )) && pats+=(nm-applet)
	nm_runs && pats+=(wicd-tray cmst connman-gtk)
	for id in "${pats[@]}"; do
		for f in /etc/xdg/autostart/"$id"*.desktop; do
			[[ -f $f ]] || continue
			printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "${f##*/}" | _write "$xdg/autostart/${f##*/}"
		done
	done
}

# Write the icon set overlays. Only the adapted sets are offered in the
# appearance settings; a copy of each official index.theme, hidden and
# inheriting the adapted set, keeps the official names working, with the
# Debian logo. Usage: _session_icons DATA-DIR
_session_icons() {
	local data=$1 b o inh f n rel size t logo out
	logo=${LOGO_BADGE:-/usr/share/icons/desktop-base/scalable/emblems/emblem-debian.svg}
	[[ -n $LOGO_BADGE || -f $logo ]] || logo=$(_logo_path) || logo=""
	for b in PiXflat PiXtrix PiX; do
		[[ -f $SYS_ROOT/usr/share/icons/$b/index.theme ]] || continue
		inh="$b-Debian,"
		for o in $(_icon_fallbacks "$b"); do [[ -d $SYS_ROOT/usr/share/icons/$o ]] && inh+="$o,"; done
		# Hidden and Inherits belong in the first section, [Icon Theme]
		f=$SYS_ROOT/usr/share/icons/$b/index.theme
		I=$inh H=$(grep -c '^Inherits[[:space:]]*=' "$f") awk '/^Hidden=/ { next }
			/^Inherits[[:space:]]*=/ { sub(/^Inherits[[:space:]]*=[[:space:]]*/, ""); print "Inherits=" ENVIRON["I"] $0; next }
			{ print }
			/^\[Icon Theme\]/ { print "Hidden=true"; if (!ENVIRON["H"]) print "Inherits=" ENVIRON["I"] "gnome,Adwaita,hicolor" }' "$f" \
			| _write "$data/icons/$b/index.theme"
		# The Shutdown dialog's window icon (rpi), as in the adapted set
		for f in "$SYS_ROOT/usr/share/icons/$b"/*/*/rpi.*; do
			rel=${f#"$SYS_ROOT/usr/share/icons/$b/"} size=${rel%%/*}
			for t in "$SYS_ROOT/usr/share/icons/$b/$size"/actions/system-shutdown.*; do
				[[ -f $f && -f $t ]] || continue
				out=$data/icons/$b/${rel%.*}
				mkdir -p "${out%/*}"
				ln -sfn "/usr/share/icons/$b/$size/actions/${t##*/}" "$out.${t##*.}"
			done
		done
		[[ -n $logo ]] || continue
		for n in "${LOGO_ICONS[@]}"; do
			for f in "$SYS_ROOT/usr/share/icons/$b"/*/*/"$n".*; do
				[[ -f $f ]] || continue
				rel=${f#"$SYS_ROOT/usr/share/icons/$b/"}
				out=$data/icons/$b/${rel%.*}
				mkdir -p "${out%/*}"
				ln -sfn "$logo" "$out.${logo##*.}"
			done
		done
	done
}

# Write the session's theme layers: each official GTK 3 theme plus Raspberry
# Pi OS's panel style (and, for the legacy PiX, the panel colours the newer
# themes define), and the Openbox theme with the button file names Openbox
# reads. Every file refers to the official one, so theme updates still apply.
# Usage: _session_themes DATA-DIR
_session_themes() {
	local data=$1 t src
	for t in PiXflat PiXnoir PiXtrix PiXonyx PiX; do
		src=$SYS_ROOT/usr/share/themes/$t
		[[ -f $src/gtk-3.0/gtk.css ]] || continue
		{
			printf '/* The official %s theme with the Raspberry Pi OS panel style, written by %s */\n' "$t" "$APP_NAME"
			printf '@import url("%s");\n\n' "/usr/share/themes/$t/gtk-3.0/gtk.css"
			if [[ $t == PiX ]]; then
				printf '@define-color bar_bg_color @theme_bg_color;\n@define-color bar_fg_color @theme_fg_color;\n'
				printf '#PanelToplevel { color: @bar_fg_color; background-color: @bar_bg_color; }\n'
				printf '#PanelToplevel button, #PanelToplevel:backdrop button > box > label {\n  color: @bar_fg_color; background-color: @bar_bg_color; }\n'
				printf '#PanelToplevel button:hover, #PanelToplevel button:checked:hover {\n  background-color: shade(@bar_bg_color, 0.877); }\n'
				printf '#PanelToplevel button:checked { background-color: shade(@bar_bg_color, 0.843); }\n'
				# The panel's notifications carry the style class "tooltip", which
				# the newer themes style; PiX styles only the element, so its own
				# tooltip rules are given to the class too
				printf '.tooltip { padding: 4px; box-shadow: none; }\n'
				printf '.tooltip.background { background-color: rgba(160, 160, 160, 0.8); background-clip: padding-box; border: none; }\n'
				printf '.tooltip decoration { background-color: transparent; }\n'
				printf '.tooltip * { padding: 4px; background-color: transparent; color: white; }\n'
			fi
			_panel_button_css
			# Raspberry Pi's tray does not clear an icon before redrawing it at
			# a new size; an opaque background in the panel colour hides the
			# old one. Tray icons are windows of their applets, not the panel.
			printf '#tray, #tray * { padding: 0px; margin: 0px; border: 0px; }\n'
			printf 'window > image { background-color: @bar_bg_color; }\n'
			# Rounded tooltips need a compositor (GTK then marks them "csd");
			# without one (Openbox) their corners are black, so they are made
			# square, as Raspberry Pi OS's X11 session does.
			printf 'tooltip:not(.csd), .tooltip:not(.csd) { border-radius: 0px; }\n'
			# The scrollbars of the Large and Larger sizes, as Raspberry Pi
			# OS's Appearance Settings write them
			if (( T_SCROLL )); then
				printf 'scrollbar button { min-width: %spx; min-height: %spx; }\n' "$T_SCROLL" "$T_SCROLL"
				printf 'scrollbar slider { min-width: %spx; min-height: %spx; }\n' "$((T_SCROLL - 6))" "$((T_SCROLL - 6))"
			fi
		} | _write "$data/themes/$t/gtk-3.0/gtk.css"
		# Openbox reads the hover image of a toggled title bar button from
		# "<button>_toggled_hover.xbm", but the official themes name it
		# "<button>_hover_toggled.xbm"; without a link, the maximise button
		# of a maximised window would not change on hover.
		_ob_links "$data" "$t"
	done
	# The large window themes (Openbox only) of the Large and Larger sizes
	for t in PiXflat_l PiXnoir_l PiXtrix_l PiXonyx_l; do _ob_links "$data" "$t"; done
}

# Link an Openbox theme's files into the session's theme layer, adding the
# button file names Openbox reads. Usage: _ob_links DATA-DIR THEME
_ob_links() {
	local data=$1 t=$2 f n src=$SYS_ROOT/usr/share/themes/$2
	[[ -f $src/openbox-3/themerc ]] || return 0
	mkdir -p "$data/themes/$t/openbox-3"
	for f in "$src"/openbox-3/*; do
		n=${f##*/}
		ln -sfn "/usr/share/themes/$t/openbox-3/$n" "$data/themes/$t/openbox-3/$n"
		[[ $n != *_hover_toggled* ]] || ln -sfn "/usr/share/themes/$t/openbox-3/$n" "$data/themes/$t/openbox-3/${n/_hover_toggled/_toggled_hover}"
	done
}

# Print the session's GTK 2 colour scheme (highlight and panel colours, as
# Raspberry Pi OS sets them) from the theme's own gtkrc, so dark themes get a
# dark panel; print Raspberry Pi OS's light values if the theme has none.
color_scheme() {
	local f=$SYS_ROOT/usr/share/themes/$T_GTK/gtk-2.0/gtkrc k v out=""
	for k in selected_bg_color selected_fg_color bar_bg_color bar_fg_color; do
		v=$(sed -n 's/^[[:space:]]*gtk-color-scheme[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$f" 2>/dev/null | first_line \
			| tr -s '\\' '\n' | sed -n "s/^n\{0,1\}$k:\(#[0-9A-Fa-f]\{6\}\)\$/\1/p" | first_line)
		[[ -n $v ]] || { printf '%s\n' "$T_COLOR_SCHEME"; return 0; }
		# Written as Raspberry Pi OS's Appearance Settings writes it: 16 bits a channel
		v=${v,,} v="#${v:1:2}${v:1:2}${v:3:2}${v:3:2}${v:5:2}${v:5:2}"
		out+="$k:$v\\n"
	done
	printf '%s\n' "$out"
}

# Write the session's programs: the shared session-env and the start
# script, modelled on Raspberry Pi OS's startx-rpd and Debian's startlxde;
# panel and desktop wrappers that run Raspberry Pi's program where installed
# and wanted, else Debian's, so a session keeps working when one is removed;
# and the appearance settings wrapper, which lists the session's themes.
# Usage: _session_programs ROOT
_session_programs() {
	local root=$1 f
	# Raspberry Pi's file manager runs as "pcmanfm" in the session, as on
	# Raspberry Pi OS, whose panel launcher and menu entries call it so
	if (( S_PI_FM )); then
		printf '#!/bin/sh\nif [ -x /usr/bin/pcmanfm-pi ]; then exec %s/bin/pcmanfm-pi "$@"; fi\nexec /usr/bin/pcmanfm "$@"\n' "$SHARE" | _write "$root$SHARE/bin/pcmanfm"
		# It reads pcmanfm.conf from every folder of XDG_CONFIG_DIRS in turn,
		# each over the one before, so Debian's file manager's (/etc/xdg)
		# would override the session's (automatic mounting among them): the
		# session's folder is named last too
		printf '#!/bin/sh\nXDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}:%s/xdg"\nexport XDG_CONFIG_DIRS\nexec /usr/bin/pcmanfm-pi "$@"\n' "$SHARE" \
			| _write "$root$SHARE/bin/pcmanfm-pi"
		chmod 0755 "$root$SHARE/bin/pcmanfm" "$root$SHARE/bin/pcmanfm-pi"
	fi
	# Raspberry Pi's Openbox (openbox-pi, repacked beside Debian's) where it is
	# installed: programs and keys of the session that run "openbox" (such as
	# "openbox --reconfigure") reach it
	printf '#!/bin/sh\nif [ -x /usr/bin/openbox-pi ]; then exec /usr/bin/openbox-pi "$@"; fi\nexec /usr/bin/openbox "$@"\n' | _write "$root$SHARE/bin/openbox"
	chmod 0755 "$root$SHARE/bin/openbox"
	# LXTerminal opens a window without an alpha channel, as Raspberry Pi OS
	# builds it: Raspberry Pi's Openbox gives a window with one (Debian's
	# LXTerminal asks for it) no invisible resize borders, so it could be
	# resized only from its frame's edge, or not at all with PiXtrix. Every
	# way the session starts it (menu, panel, keys, file manager) finds this
	# first; a second window shares the first one's process.
	printf '#!/bin/sh\n[ -x /usr/bin/lxterminal ] || exit 127\nXLIB_SKIP_ARGB_VISUALS=1 exec /usr/bin/lxterminal "$@"\n' | _write "$root$SHARE/bin/lxterminal"
	chmod 0755 "$root$SHARE/bin/lxterminal"
	# Raspberry Pi's Shutdown dialog shows the lock key only from labwc's
	# settings in the user's or the system's folder, and the Wayland
	# session's are in neither: there it reads a file of the session's own
	# that names the key, through a settings folder of its own that keeps
	# the user's GTK settings. In the X session, which has no lock key, the
	# dialog runs as it is
	if (( WAYLAND )); then
		printf '%s\n' '<?xml version="1.0"?>' '<openbox_config xmlns="http://openbox.org/3.4/rc">' '  <keyboard>' \
			'    <keybind key="C-A-l"><action name="Execute" command="swaylock -p"/></keybind>' '  </keyboard>' '</openbox_config>' \
			| _write "$root$SHARE/labwc/rc.xml"
		cat <<EOF | _write "$root$SHARE/bin/pishutdown"
#!/bin/sh
[ -x /usr/bin/pishutdown ] || exit 127
[ -n "\${WAYLAND_DISPLAY:-}" ] && [ -n "\${XDG_RUNTIME_DIR:-}" ] || exec /usr/bin/pishutdown "\$@"
d=\$XDG_RUNTIME_DIR/$APP_NAME-pishutdown
mkdir -p "\$d" && ln -sfn $SHARE/labwc "\$d/labwc" && ln -sfn "\${XDG_CONFIG_HOME:-\$HOME/.config}/gtk-3.0" "\$d/gtk-3.0"
XDG_CONFIG_HOME=\$d exec /usr/bin/pishutdown "\$@"
EOF
		chmod 0755 "$root$SHARE/bin/pishutdown"
	fi
	# GTK 2's scrollbars at the large sizes, as Raspberry Pi OS's Appearance
	# Settings writes them (into ~/.gtkrc-2.0 there; here only this session's)
	if (( ${T_SCROLL:-0} )); then
		printf 'style "%s-scrollbar"\n{\n\tGtkRange::slider-width = %s\n\tGtkRange::stepper-size = %s\n}\nclass "GtkRange" style "%s-scrollbar"\n' \
			"$APP_NAME" "$T_SCROLL" "$T_SCROLL" "$APP_NAME" | _write "$root$SHARE/gtkrc-2.0"
	fi
	cat <<EOF | _write "$root$SHARE/session-env"
# The environment and helpers of both Raspberry Pi Desktop sessions, written
# by $APP_NAME. Only these sessions put $SHARE first in the XDG paths.
profile=$S_PROFILE
share=$SHARE
config=\${XDG_CONFIG_HOME:-\$HOME/.config}
# The application entries the session tidies at login (menu_tidy)
menu=\${XDG_RUNTIME_DIR:-\$HOME/.cache}/$APP_NAME-menu
# The theme layers that give GTK 3 text the desktop font's weight (gtk_weight)
gtkw=\${XDG_RUNTIME_DIR:-\$HOME/.cache}/$APP_NAME-gtk
export XDG_CONFIG_DIRS="\$share/xdg:\${XDG_CONFIG_DIRS:-/etc/xdg}"
export XDG_DATA_DIRS="\$gtkw:\$share/data:\$menu:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XDG_MENU_PREFIX=$MENU_PREFIX
export FONTCONFIG_FILE=\$share/fonts.conf
[ ! -f "\$share/dconf/profile" ] || export DCONF_PROFILE=\$share/dconf/profile
export SAL_USE_VCLPLUGIN=gtk3
# Qt 5 and Qt 6 programs follow the GTK theme (qt_choose)
export QT_QPA_PLATFORMTHEME=$QT_THEME
export PATH="\$share/bin:\$PATH"
$( (( ! ${T_SCROLL:-0} )) || printf '# GTK 2 programs: the size'"'"'s scrollbars, before your own settings\nexport GTK2_RC_FILES="/etc/gtk-2.0/gtkrc:%s/gtkrc-2.0:%s/.gtkrc-2.0"\n' "$SHARE" "\$HOME" )

# Create the Desktop folder if it is missing
if [ -e "\$config/user-dirs.dirs" ]; then . "\$config/user-dirs.dirs"; fi
mkdir -p "\${XDG_DESKTOP_DIR:-\$HOME/Desktop}"
EOF
	cat <<'EOF' >>"$root$SHARE/session-env"

# Draw GTK 3 text in the weight and style of the desktop font, as Raspberry
# Pi's build of GTK 3 does (Debian's takes only the font's family and size,
# and the themes make some text bold). A layer per theme of the session, in
# the session's runtime folder, first in XDG_DATA_DIRS; written at login and
# by rpios-look-set. Bold or italic text that a program sets itself stays so.
gtk_weight() {
	# The font given (the Wayland session's, from GSettings), else the X session's
	_f=${1:-$(sed -n 's|^sGtk/FontName=||p' "$config/lxsession/$profile/desktop.conf" "$share/xdg/lxsession/$profile/desktop.conf" 2>/dev/null | head -n 1)}
	_w=400 _s=normal
	for _x in $_f; do
		case $_x in
			Thin|Hairline) _w=100 ;; ExtraLight|UltraLight) _w=200 ;; Light) _w=300 ;; Medium) _w=500 ;;
			SemiBold|DemiBold) _w=600 ;; Bold) _w=700 ;; ExtraBold|UltraBold) _w=800 ;; Black|Heavy) _w=900 ;;
			Italic) _s=italic ;; Oblique) _s=oblique ;;
		esac
	done
	for _t in "$share"/data/themes/*/gtk-3.0/gtk.css; do
		[ -f "$_t" ] || continue
		_n=${_t%/gtk-3.0/gtk.css}; _n=${_n##*/}
		mkdir -p "$gtkw/themes/$_n/gtk-3.0" || return 0
		# The ID selectors outrank every theme rule
		printf '@import url("%s");\n*:not(#w1):not(#w2):not(#w3) { font-weight: %s; font-style: %s; }\n' "$_t" "$_w" "$_s" \
			>"$gtkw/themes/$_n/gtk-3.0/gtk.css"
	done
}

# Show each installed application once in the menu. The menu shows an
# application in each of its categories (Settings is Preferences, System is
# System Tools, Utility is Accessories, ...); one whose entry names several
# of them keeps the first in this order, as Raspberry Pi OS tidies the
# applications it ships (raspi-ui-overrides). The tidied copies go to the
# session's runtime folder, which the menu reads before Debian's entries;
# Debian's files are not changed, and the session's own entries are kept.
# The folder is replaced only when its entries change: the menu cache is
# rebuilt on every change, and a panel that starts meanwhile (a new icon
# theme restarts it) shows an empty launch bar.
menu_tidy() {
	# Its own folder: login and rpios-look-set may tidy at the same time
	_new=$menu.new.$$
	rm -rf "$_new"
	mkdir -p "$_new/applications" || return 0
	set -- /usr/share/applications/*.desktop
	[ ! -e "$1" ] || _menu_tidy "$@"
	if diff -r "$menu" "$_new" >/dev/null 2>&1; then rm -rf "$_new"
	else rm -rf "$menu"; mv -T "$_new" "$menu" 2>/dev/null || rm -rf "$_new"; fi
}
_menu_tidy() {
	awk -v out="$_new/applications" -v own="$share/data/applications" '
		BEGIN {
			n = split("Settings System Development Education Science Office Graphics AudioVideo Network Game Help Utility", o, " ")
			for (i = 1; i <= n; i++) rank[o[i]] = i
		}
		FNR == 1 { flush(); file = FILENAME; k = 0; hidden = 0; hits = 0; best = ""; at = 0; entry = 0 }
		/^\[/ { entry = ($0 == "[Desktop Entry]") }
		entry && /^(NoDisplay|Hidden)=true/ { hidden = 1 }
		entry && /^Categories=/ && !at {
			m = split(substr($0, 12), c, ";")
			for (i = 1; i <= m; i++) if (c[i] in rank) { hits++; if (best == "" || rank[c[i]] < rank[best]) best = c[i] }
			at = FNR
		}
		{ line[++k] = $0 }
		END { flush() }
		function flush(   id, f, i, j, s) {
			if (file == "" || hidden || hits < 2) return
			id = file; sub(/.*\//, "", id)
			if ((getline s < (own "/" id)) >= 0) { close(own "/" id); return }
			f = out "/" id
			for (i = 1; i <= k; i++) {
				if (i != at) { print line[i] > f; continue }
				s = "Categories="
				for (j = 1; j <= m; j++) if (c[j] != "" && (!(c[j] in rank) || c[j] == best)) s = s c[j] ";"
				print s > f
			}
			close(f)
		}' "$@"
}
EOF
	cat <<'EOF' | _write "$root$SHARE/start"
#!/bin/sh
# The Raspberry Pi Desktop session on X.
. /usr/share/rpios-look/session-env
menu_tidy
gtk_weight
export XDG_CURRENT_DESKTOP=LXDE
# Raspberry Pi OS's session name (rpd-x)
export DESKTOP_SESSION=$profile

# lxsession reads the user's copy of the start list once there is one: an
# empty copy would start nothing (no panel, no desktop), so it is removed.
if [ -f "$config/lxsession/$profile/autostart" ] && [ ! -s "$config/lxsession/$profile/autostart" ]; then
	rm -f "$config/lxsession/$profile/autostart"
fi
lxs=$config/lxsession/$profile/desktop.conf

# Start D-Bus if needed
if command -v dbus-launch >/dev/null && [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
	if [ -z "$XDG_RUNTIME_DIR" ] || [ ! -S "$XDG_RUNTIME_DIR/bus" ] || [ ! -O "$XDG_RUNTIME_DIR/bus" ]; then
		eval "$(dbus-launch --sh-syntax --exit-with-session)"
	fi
fi

# lxsession writes back the settings it read at login whenever a setting
# changes through it: settings-keeper keeps the look set since (see rpios-look)
keeper=""
if [ -x "$share/settings-keeper" ] && command -v python3 >/dev/null; then
	"$share/settings-keeper" "$lxs" "$share/xdg/lxsession/$profile/desktop.conf" $$ </dev/null &
	keeper=$!
fi
# The power button opens the Shutdown dialog (pwrkey): systemd-logind leaves
# the key to the session while it runs, as on Raspberry Pi OS
set -- /usr/bin/lxsession -s "$profile" -e LXDE
if grep -qs "<command>$share/pwrkey</command>" "$share/xdg/openbox/"*-rc.xml \
	&& systemd-inhibit --what=handle-power-key --mode=block true 2>/dev/null; then
	set -- systemd-inhibit --what=handle-power-key --mode=block --who="Raspberry Pi Desktop" \
		--why="The power button opens the Shutdown dialog" "$@"
fi
"$@"
[ -z "$keeper" ] || kill "$keeper" 2>/dev/null
exit 0
EOF
	# Openbox with the user's file, as Raspberry Pi OS starts it (openbox-rpd).
	# Raspberry Pi's build reads the file of that name in the first folder of
	# XDG_CONFIG_DIRS first (the session's settings, see session_build), then
	# the user's over it, where there is one; Debian's reads the user's file,
	# else rc.xml: the session's settings, unless the user has an rc.xml of
	# their own (~/.config/openbox, Openbox's plain session)
	printf '#!/bin/sh\nexec %s/bin/openbox --config-file "${XDG_CONFIG_HOME:-$HOME/.config}/openbox/%s" "$@"\n' "$SHARE" "$OB_FILE" \
		| _write "$root$SHARE/openbox"
	{
		printf '#!/bin/sh\n'
		printf 'p="lxpanel --profile %s"\n' "$S_PROFILE"
		(( S_PI_PANEL )) && printf 'if command -v lxpanel-pi >/dev/null; then p=lxpanel-pi; fi\n'
		# lxsession restarts it if it crashes (@ in autostart), as on Raspberry Pi OS
		printf 'exec $p\n'
	} | _write "$root$SHARE/panel"
	{
		printf '#!/bin/sh\n# The desktop: wallpaper and icons.\n'
		(( S_PI_FM )) && printf 'if [ -x /usr/bin/pcmanfm-pi ]; then exec %s/bin/pcmanfm-pi --desktop --profile %s; fi\n' "$SHARE" "$S_FM_PROFILE"
		printf 'exec pcmanfm --desktop --profile %s\n' "$S_PROFILE"
	} | _write "$root$SHARE/desktop"
	cat <<'EOF' | _write "$root$SHARE/appearance"
#!/bin/sh
# Run the appearance settings. The panel follows their changes by itself.
#
# The settings list the themes found in the data directories. They are shown
# a filtered view: each Raspberry Pi OS icon set once, under its official
# name (the Debian-adapted set, which inherits the official one), cursor
# themes such as Adwaita by name, and none of Raspberry Pi's tPiX* helper
# themes. The names they save are the real ones.
key() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$2" | head -n1; }
view() {
	v=$1/share
	[ ! -d "$v" ] || chmod -R u+w "$v"
	rm -rf "$v" && mkdir -p "$v/icons" "$v/themes" || return 1
	dirs=${XDG_DATA_DIRS:-/usr/local/share:/usr/share} adapted=' '
	IFS=:
	for d in $dirs; do
		for t in "$d"/icons/*-Debian; do [ -d "$t" ] && adapted="$adapted${t##*/} "; done
	done
	for d in $dirs; do
		IFS=' '
		for e in "$d"/*; do
			n=${e##*/}
			case $n in icons|themes|'*') ;; *) [ -e "$v/$n" ] || ln -s "$e" "$v/$n" ;; esac
		done
		# Each part of a theme comes from the first directory that has it
		# (the session's GTK 3 layer, the official GTK 2 theme, ...)
		for t in "$d"/themes/*; do
			n=${t##*/}
			case $n in 'tPiX'*|'*') continue ;; esac
			[ -d "$t" ] && mkdir -p "$v/themes/$n" || continue
			for e in "$t"/*; do
				[ "${e##*/}" = '*' ] || [ -e "$v/themes/$n/${e##*/}" ] || ln -s "$e" "$v/themes/$n/${e##*/}"
			done
		done
		for t in "$d"/icons/*; do
			n=${t##*/} o=$v/icons/${t##*/} i=$t/index.theme
			[ "$n" != '*' ] && [ ! -e "$o" ] || continue
			case $adapted in *" $n-Debian "*)
				# An official set that has an adapted one: kept for the
				# adapted set to inherit, but hidden
				[ -f "$i" ] && [ -d "$d/icons/$n-Debian" ] || continue
				mkdir "$o" && ln -s "$t"/* "$o"/ && rm -f "$o/index.theme" "$o/cursors"
				awk '/^Hidden=/ { next } { print } /^\[Icon Theme\]/ { print "Hidden=true" }' "$i" >"$o/index.theme"
				continue ;;
			esac
			if [ -f "$i" ] && [ "${n%-Debian}" != "$n" ] && [ -d "$d/icons/${n%-Debian}" ]; then
				# The adapted set, listed under the official name
				mkdir "$o" && ln -s "$t"/* "$o"/ && rm -f "$o/index.theme"
				sed "s/^Name=\(.*\) (Debian)\$/Name=\1/" "$i" >"$o/index.theme"
			elif [ -f "$i" ] && [ -d "$t/cursors" ] && [ "$(key Hidden "$i")" = true ]; then
				# A hidden icon set with cursors (Adwaita), which the settings
				# would list without a name: shown by its name
				mkdir "$o" && ln -s "$t"/* "$o"/ && rm -f "$o/index.theme"
				grep -v '^Hidden=' "$i" >"$o/index.theme"
			else
				ln -s "$t" "$o"
			fi
		done
		IFS=:
	done
	IFS=' '
	# Read-only, like the system's themes, so nothing can be removed there
	chmod a-w "$v/icons" "$v/themes"
}
run=${XDG_RUNTIME_DIR:-}
if [ -n "$run" ] && [ -d "$run" ] && view "$run/rpios-look-appearance"; then
	exec env "XDG_DATA_DIRS=$run/rpios-look-appearance/share" "GTK_DATA_PREFIX=$run/rpios-look-appearance" lxappearance "$@"
fi
exec lxappearance "$@"
EOF
	for f in start openbox panel desktop appearance; do chmod 0755 "$root$SHARE/$f"; done
	printf '[Desktop Entry]\nType=Application\nName=Raspberry Pi Desktop\nComment=The Raspberry Pi OS desktop on X, on Debian\nExec=%s/start\nTryExec=/usr/bin/lxsession\nDesktopNames=LXDE\n' \
		"$SHARE" | _write "$root/usr/share/xsessions/$SESSION_ID.desktop"
	# Monospace is Liberation Mono, as in Raspberry Pi OS, in these sessions only
	cat <<'EOF' | _write "$root$SHARE/fonts.conf"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- The Raspberry Pi Desktop session's fonts: Debian's, with Monospace as
     Liberation Mono, as in Raspberry Pi OS -->
<fontconfig>
	<include>/etc/fonts/fonts.conf</include>
	<match target="pattern">
		<test name="family"><string>Monospace</string></test>
		<edit name="family" mode="assign" binding="same"><string>Liberation Mono</string></edit>
	</match>
</fontconfig>
EOF
}

# Write the session's GSettings defaults, which GTK 4 reads for its light or
# dark style, as a separate dconf database (DCONF_PROFILE): the user's
# settings still win, and other sessions never read it. IBus shows no tray
# icon, as Raspberry Pi OS has none; input methods keep working.
# Usage: _session_dconf ROOT
_session_dconf() {
	local root=$1 dir=$WORKDIR/dconf-keys scheme=default
	(( T_DARK )) && scheme=prefer-dark
	mkdir -p "$dir" "$root$SHARE/dconf"
	cat >"$dir/00-$APP_NAME" <<EOF
[org/gnome/desktop/interface]
gtk-theme='$T_GTK'
icon-theme='$T_ICONS'
cursor-theme='$T_ICONS'
cursor-size=$T_CURSOR_SIZE
font-name='$T_FONT'
monospace-font-name='${T_TERM_FONT:-Monospace 10}'
toolbar-icons-size='$( (( ${T_TB_ICON:-24} == 16 )) && echo small || echo large )'
color-scheme='$scheme'
font-antialiasing='rgba'
font-hinting='full'
font-rgba-order='rgb'
toolbar-style='both-horiz'

[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'

[org/gnome/desktop/sound]
theme-name='$T_SOUND_THEME'
event-sounds=true
input-feedback-sounds=true

[desktop/ibus/panel]
show-icon-on-systray=false
EOF
	if ! command -v dconf >/dev/null || ! dconf compile "$root$SHARE/dconf/settings" "$dir"; then
		warn "dconf is missing: the session starts without its GSettings defaults (install dconf-cli and run this again)."
		return 0
	fi
	# A separate user database keeps other sessions' settings apart (named
	# without "-", which D-Bus does not allow)
	printf 'user-db:%s\nfile-db:%s/dconf/settings\n' "${APP_NAME//-/}" "$SHARE" | _write "$root$SHARE/dconf/profile"
	# The Wayland session's own user database, so that a theme chosen in one
	# session leaves the other's as it is, and its defaults: Raspberry Pi OS
	# smooths text in grey with slight hinting there (rpd-wayland-core's
	# GSettings override), unlike its X session
	if (( WAYLAND )); then
		mkdir -p "$dir-wayland"
		sed -e "s/^font-antialiasing=.*/font-antialiasing='grayscale'/" -e "s/^font-hinting=.*/font-hinting='slight'/" \
			"$dir/00-$APP_NAME" >"$dir-wayland/00-$APP_NAME"
		if dconf compile "$root$SHARE/dconf/settings-wayland" "$dir-wayland"; then
			printf 'user-db:%swayland\nfile-db:%s/dconf/settings-wayland\n' "${APP_NAME//-/}" "$SHARE" | _write "$root$SHARE/dconf/profile-wayland"
		fi
	fi
	# The profile is set before Debian's X session starts the input method
	# (70im-config_launch), so that IBus reads it too; the start script sets it
	# too late. Only for this session, which the display manager names in
	# XDG_SESSION_DESKTOP, else GDMSESSION.
	cat <<EOF | _write "$root/etc/X11/Xsession.d/60${APP_NAME}_dconf"
# Written by $APP_NAME and removed with $APP_PKG: the dconf profile of the
# Raspberry Pi Desktop session, for the programs Debian's X session starts.
if [ "\${XDG_SESSION_DESKTOP:-\${GDMSESSION:-}}" = $SESSION_ID ]; then
	DCONF_PROFILE=$SHARE/dconf/profile
	export DCONF_PROFILE
fi
EOF
}

# Write the Raspberry Pi Desktop session on Wayland:
# Raspberry Pi OS's labwc settings from its Wayland desktop package (WL_PKG),
# with the look's window theme, fonts and keys; its panel layout; and start
# scripts that do what its labwc-pi, lwrespawn and xwayland-xauth do, without
# touching the user's own files. Debian's labwc and Raspberry Pi's panel run
# as they are shipped. Usage: _wayland_session ROOT
_wayland_session() {
	local root=$1 xdg=$1$SHARE/xdg pi="" rc ob=$T_OB
	pi=$( (pi_unpack "$WL_PKG" "$H_SUITE" "$H_ARCH") 2>/dev/null ) || pi=""
	[[ -f $SYS_ROOT/usr/share/themes/$ob/openbox-3/themerc ]] || ob=$T_GTK
	# PiX has no labwc look (an X theme only): the release's default theme
	[[ $ob != PiX ]] || ob=PiXtrix
	# labwc's settings, where Raspberry Pi OS keeps them (/etc/xdg/labwc): labwc
	# reads the session's (first in XDG_CONFIG_DIRS) and merges the user's
	# ~/.config/labwc over them (labwc -m)
	rc=$xdg/labwc/rc.xml
	_seed "$rc" ${pi:+"$pi/etc/xdg/labwc/rc.xml"} || die "cannot read Raspberry Pi OS $H_SUITE's labwc settings ($WL_PKG)"
	# The look's theme and fonts: the window theme (the large one for Large
	# and Larger), the desktop font, its size and weight
	sed -i -e "/<theme>/,/<\/theme>/ {
		/<font /,/<\/font>/ {
			s|<name>[^<]*</name>|<name>$T_FONT_FAMILY</name>|; s|<size>[^<]*</size>|<size>$T_FONT_SIZE</size>|
			s|<weight>[^<]*</weight>|<weight>$T_FONT_WEIGHT</weight>|
		}
		/<font /,/<\/font>/!s|<name>[^<]*</name>|<name>$ob</name>|
	}" "$rc"
	# Two keys run programs that only Raspberry Pi's packages have: the
	# terminal (lab-sensible-terminal, from its labwc) and the power button
	# (pwrkey, from rpd-common, not installed); the session's own do the same
	sed -i -e 's|command="lab-sensible-terminal"|command="lxterminal"|' \
		-e "s|command=\"pwrkey\"|command=\"$SHARE/pwrkey\"|" "$rc"
	# The desktop's menu: Raspberry Pi OS opens Desktop Preferences from its
	# Control Centre, which this look does not install; pcmanfm's own dialog
	if [[ -n $pi && -f $pi/etc/xdg/labwc/menu.xml ]]; then
		sed 's|command="rpcc desktop"|command="pcmanfm --desktop-pref"|' "$pi/etc/xdg/labwc/menu.xml" | _write "$xdg/labwc/menu.xml"
	fi
	# What labwc starts (Raspberry Pi OS's autostart): the desktop and the
	# panel, restarted if they stop, the display layout, the on-screen
	# keyboard (with a touch screen only) and the XDG autostart entries
	{
		printf '%s/lwrespawn %s/desktop &\n' "$SHARE" "$SHARE"
		printf '%s/lwrespawn wf-panel-pi &\n' "$SHARE"
		printf 'kanshi &\n'
		printf '%s/squeek &\n' "$SHARE"
		# The authentication agent for administrator tasks (Raspberry Pi OS
		# runs MATE's; the X session's, lxpolkit, is installed already)
		printf 'lxpolkit &\n'
		printf 'lxsession-xdg-autostart\n'
	} | _write "$xdg/labwc/autostart"
	_wl_environment | _write "$xdg/labwc/environment"
	# The panel: Raspberry Pi OS's layout without the plugins left out, where
	# Raspberry Pi OS keeps it: the panel reads /etc/xdg and ~/.config only
	_wl_panel_ini "$pi" | _write "$root/etc/xdg/wf-panel-pi/wf-panel-pi.ini"
	_wl_programs "$root"
	printf '[Desktop Entry]\nType=Application\nName=Raspberry Pi Desktop (Wayland)\nComment=The Raspberry Pi OS desktop on Wayland (labwc), written by %s\nExec=%s/start-wayland\nTryExec=/usr/bin/labwc\nDesktopNames=labwc;wlroots\n' \
		"$APP_NAME" "$SHARE" | _write "$root/usr/share/wayland-sessions/$WL_SESSION_ID.desktop"
}

# Print labwc's environment for the session, as Raspberry Pi OS's
# /etc/xdg/labwc/environment: Qt windows without their own frames, the
# session's name, Xwayland through the session's starter (xsettingsd for X
# programs), the look's cursor and the system's keyboard layout (Raspberry
# Pi OS sets the British one, which its first-boot wizard changes).
_wl_environment() {
	local k v
	printf 'QT_WAYLAND_DISABLE_WINDOWDECORATION=1\n\n'
	printf 'DESKTOP_SESSION=rpd-labwc\nWLR_XWAYLAND=%s/xwayland\n\n' "$SHARE"
	printf 'XCURSOR_THEME=%s\nXCURSOR_SIZE=%s\n\n' "$T_ICONS" "$T_CURSOR_SIZE"
	printf 'LABWC_FALLBACK_OUTPUT=NOOP-1\n'
	for k in XKBMODEL XKBLAYOUT XKBVARIANT XKBOPTIONS; do
		v=$(sed -n "s/^$k=//p" "$SYS_ROOT/etc/default/keyboard" 2>/dev/null | tr -d '"' | first_line) || v=""
		[[ -z $v ]] || printf 'XKB_DEFAULT_%s=%s\n' "${k#XKB}" "$v"
	done
}

# Print the panel's settings: Raspberry Pi OS's layout (its Wayland desktop
# package; wayland_known checked that it has one) without the plugins this
# look leaves out (see wl_apps) or does not have, with the size preset's
# icon size. Usage: _wl_panel_ini UNPACKED-PACKAGE-DIR
_wl_panel_ini() {
	local f=$1/etc/xdg/wf-panel-pi/wf-panel-pi.ini drop line w out skip wl
	[[ -f $f ]] || die "cannot read Raspberry Pi OS $H_SUITE's panel settings ($WL_PKG)"
	# As wl_apps: what the X session leaves out, Raspberry Pi Connect's, and
	# the battery's without a battery
	drop="$(panel_drop)|connect"
	has_battery || drop+="|batt|ptbatt"
	command -v squeekboard >/dev/null || [[ " ${APT_PKGS[*]} " == *" squeekboard "* ]] || drop+="|squeek"
	{ wl=0; while IFS= read -r line; do
		case $line in
			icon_size=*) [[ ${O_SIZE:-medium} != medium ]] || printf '%s\n' "$line" ;;
			max_width=*) [[ ${O_SIZE:-medium} != medium ]] || printf '%s\n' "$line" ;;
			launchers=*)
				# The panel finds a launcher by its .desktop name; Raspberry
				# Pi's x-www-browser and x-terminal-emulator come from its
				# rpd-common, so the session's launchers stand in, as on the X
				# panel (_pi_layout)
				out=""
				for w in ${line#*=}; do
					case $w in
						x-www-browser) w=$(_browser || true) ;;
						x-terminal-emulator) w=$(_terminal || true) ;;
						pcmanfm) w=pcmanfm; (( ! ${S_PI_FM:-0} )) || w=pcmanfm-pi ;;
					esac
					[[ -z $w ]] || out+=" ${w%.desktop}"
				done
				printf 'launchers=%s\n' "${out# }" ;;
			'[window-list]')
				# The window buttons' width of another size than Medium, as the
				# Appearance Settings write it (the panel's own is Medium's)
				printf '%s\n' "$line"; wl=1
				[[ ${O_SIZE:-medium} == medium ]] || printf 'max_width=%s\n' "$T_TASK_WIDTH" ;;
			'[panel]')
				printf '%s\n' "$line"
				# Another size than Medium, as Raspberry Pi OS's Appearance
				# Settings writes it (the panel's height less 4); Medium is the
				# panel's own
				[[ ${O_SIZE:-medium} == medium ]] || printf 'icon_size=%s\n' "$((T_PANEL_ICON - 4))" ;;
			widgets_left=*|widgets_right=*)
				# A left-out plugin goes, its spacers stay, as on the X
				# panel: two spacers that it leaves side by side become one,
				# and those left at the end go
				out="" last="" skip=0
				for w in ${line#*=}; do
					if [[ $w =~ ^($drop)$ ]]; then skip=1; continue; fi
					if (( skip )) && [[ $w == spacing* && $last == spacing* ]]; then continue; fi
					out+=" $w" last=$w skip=0
				done
				out=$(sed -E 's/( spacing[0-9]+)+$//' <<<"$out")
				printf '%s=%s\n' "${line%%=*}" "${out# }" ;;
			*) printf '%s\n' "$line" ;;
		esac
	done
	if (( ! wl )) && [[ ${O_SIZE:-medium} != medium ]]; then printf '\n[window-list]\nmax_width=%s\n' "$T_TASK_WIDTH"; fi
	} <"$f"
}

# Write the Wayland session's programs: its start script (as Raspberry Pi
# OS's labwc-pi), a restarter (lwrespawn), the Xwayland starter (as
# xwayland-xauth, without rewriting ~/.Xauthority) and the on-screen
# keyboard's starter (as Raspberry Pi OS's sbtest). Usage: _wl_programs ROOT
_wl_programs() {
	local root=$1
	cat <<EOF | _write "$root$SHARE/start-wayland"
#!/bin/sh
# The Raspberry Pi Desktop session on Wayland (labwc), written by $APP_NAME.
. $SHARE/session-env
menu_tidy
# The session's own GSettings (theme, fonts), apart from the X session's
[ ! -f "\$share/dconf/profile-wayland" ] || export DCONF_PROFILE=\$share/dconf/profile-wayland
gtk_weight "\$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")"
export DESKTOP_SESSION=rpd-labwc
# The settings X programs read under Xwayland (see $SHARE/xwayland)
$SHARE/xsettings >/dev/null 2>&1 || true
# Raspberry Pi OS's display tools keep the layout in kanshi's file
if [ ! -e "\$config/kanshi/config" ]; then mkdir -p "\$config/kanshi" && : >"\$config/kanshi/config"; fi
# Without 3D acceleration, software rendering, as Raspberry Pi OS does on
# graphics that lack it
if ! ls /dev/dri/renderD* >/dev/null 2>&1; then export WLR_RENDERER=pixman; fi
# The power button opens the Shutdown dialog (pwrkey): systemd-logind leaves
# the key to the session while it runs, as on Raspberry Pi OS
set -- /usr/bin/labwc -m "\$@"
if grep -qs 'command="$SHARE/pwrkey"' "\$share/xdg/labwc/rc.xml" \\
	&& systemd-inhibit --what=handle-power-key --mode=block true 2>/dev/null; then
	set -- systemd-inhibit --what=handle-power-key --mode=block --who="Raspberry Pi Desktop" \\
		--why="The power button opens the Shutdown dialog" "\$@"
fi
exec "\$@"
EOF
	# The screen lock as Raspberry Pi OS's keys and Shutdown dialog name it
	# ("swaylock -p", Pi mode): Raspberry Pi's build, which runs as swaylock-pi
	# beside Debian's; else Debian's swaylock, which has no Pi mode
	cat <<'EOF' | _write "$root$SHARE/bin/swaylock"
#!/bin/sh
if [ -x /usr/bin/swaylock-pi ]; then exec /usr/bin/swaylock-pi "$@"; fi
for a; do shift; [ "$a" = -p ] || set -- "$@" "$a"; done
exec /usr/bin/swaylock "$@"
EOF
	chmod 0755 "$root$SHARE/bin/swaylock"
	cat <<'EOF' | _write "$root$SHARE/lwrespawn"
#!/bin/sh
# Run a program again whenever it stops, for as long as this labwc runs (as
# Raspberry Pi OS's lwrespawn); not when it runs already.
pgrep -u "$(id -u)" -x "${1##*/}" >/dev/null && exit 0
w=$(pgrep -u "$(id -u)" -x labwc | head -n 1)
while [ -n "$w" ] && kill -0 "$w" 2>/dev/null; do
	"$@"
	sleep 1
done
EOF
	cat <<EOF | _write "$root$SHARE/xwayland"
#!/bin/sh
# Xwayland for labwc, with xsettingsd for its display, so that X programs get
# the look's GTK settings (as Raspberry Pi OS's xwayland-xauth)
(sleep 1 && DISPLAY="\$1" exec xsettingsd -c "\${XDG_RUNTIME_DIR:-/tmp}/$APP_NAME-xsettingsd.conf") >/dev/null 2>&1 &
exec /usr/bin/Xwayland "\$@"
EOF
	cat <<EOF | _write "$root$SHARE/xsettings"
#!/bin/sh
# Write the GTK settings for X programs under Xwayland from the session's
# GSettings (theme, icons, font, cursor), as /etc/xsettingsd on Raspberry Pi
# OS, and have a running xsettingsd read them again.
f=\${XDG_RUNTIME_DIR:-/tmp}/$APP_NAME-xsettingsd.conf
g() { gsettings get org.gnome.desktop.interface "\$1" 2>/dev/null | tr -d "'"; }
{
	printf 'Net/ThemeName "%s"\nNet/IconThemeName "%s"\nGtk/FontName "%s"\n' "\$(g gtk-theme)" "\$(g icon-theme)" "\$(g font-name)"
	s=\$(g cursor-size)
	printf 'Gtk/CursorThemeName "%s"\nGtk/CursorThemeSize %s\n' "\$(g cursor-theme)" "\${s:-24}"
	printf 'Net/EnableEventSounds 1\nNet/EnableInputFeedbackSounds 1\nGtk/ToolbarStyle 3\nGtk/ButtonImages 0\nGtk/MenuImages 0\n'
	printf 'Gtk/ToolbarIconSize %s\nGtk/IconSizes "gtk-large-toolbar=%s,%s"\n' "$T_TB_SIZE" "$T_TB_ICON" "$T_TB_ICON"
	printf 'Xft/Antialias 1\nXft/Hinting 1\nXft/HintStyle "hintfull"\nXft/RGBA "rgb"\n'
} >"\$f.new" && mv "\$f.new" "\$f"
pkill -HUP -u "\$(id -u)" -x xsettingsd 2>/dev/null || true
EOF
	cat <<'EOF' | _write "$root$SHARE/squeek"
#!/bin/sh
# The on-screen keyboard, only with a touch screen (as Raspberry Pi OS's
# sbtest); the panel's keyboard button shows while it runs.
command -v squeekboard >/dev/null || exit 0
grep -qs '^E:ID_INPUT_TOUCHSCREEN=1' /run/udev/data/c13:* || exit 0
exec squeekboard
EOF
	chmod 0755 "$root$SHARE/start-wayland" "$root$SHARE/lwrespawn" "$root$SHARE/xwayland" "$root$SHARE/xsettings" "$root$SHARE/squeek"
}

# Write rpios-look-set, which sets a user's theme for the Raspberry Pi
# Desktop session from the command line, with everything Raspberry Pi OS
# gives that theme: icons, cursor, font, window frames, colours and
# wallpaper. It writes the files the appearance and desktop settings write,
# which only this session reads, and applies them to a running session.
# Usage: _session_command ROOT
_session_command() {
	local root=$1 t
	{
		printf '#!/bin/bash\n# The look of the Raspberry Pi Desktop session for you, written by %s %s.\n' "$APP_NAME" "$APP_VERSION"
		printf 'APP=%s PROFILE=%s SHARE=%s OBFILE=%s FMPROFILE=%s\n' "$APP_NAME" "$S_PROFILE" "$SHARE" "$OB_FILE" "$S_FM_PROFILE"
		printf 'XSESSION=%s WLSESSION=%s\n' "$SESSION_ID" "$WL_SESSION_ID"
		printf 'WALLS=%s\n' "$WALLS"
		printf 'FONT_SIZE=%s\n' "$T_FONT_SIZE"
		printf 'CURSOR_SIZE=%s DESK_BG=%q DESK_FG=%q DESK_SHADOW=%q\n' "$T_CURSOR_SIZE" "$T_DESK_BG" "$T_DESK_FG" "$T_DESK_SHADOW"
		printf 'COLOR_SCHEME=%q\n' "$T_COLOR_SCHEME"
		# Each theme's look, as set_theme defines it for this Debian release
		printf '# The look of a theme, as Raspberry Pi OS gives it. Usage: theme_look NAME\n'
		printf 'theme_look() {\n\tcase ${1,,} in\n'
		# Each look's values; this group runs in a subshell (the pipe below), so
		# set_theme leaves the session's own look as it was
		for t in pixflat pixnoir pixtrix pixonyx pix; do
			set_theme "$t"
			printf '\t\t%s) gtk=%s wm_theme=%s icons=%s font=%q ob_font=%q ob_weight=%s wall=%s dark=%s ;;\n' \
				"$t" "$T_GTK" "$T_OB" "$T_ICONS" "$T_FONT" "$T_FONT_FAMILY" "$T_FONT_WEIGHT" "$T_WALL_DEFAULT" "$T_DARK"
		done
		printf '\t\t*) return 1 ;;\n\tesac\n}\n'
		# labwc's <theme> section: copied without it, and printed (see _labwc_undo)
		declare -f _strip_theme _theme_block
		cat <<'EOF'
set -u
config=${XDG_CONFIG_HOME:-$HOME/.config}
lxs=$config/lxsession/$PROFILE/desktop.conf lxs_sys=$SHARE/xdg/lxsession/$PROFILE/desktop.conf
fm=$config/pcmanfm/$FMPROFILE fm_sys=$SHARE/xdg/pcmanfm/$FMPROFILE
obrc=$config/openbox/$OBFILE ob_sys=$SHARE/xdg/openbox/$OBFILE
PI_THEMES="pixflat pixnoir pixtrix pixonyx pix"

usage() {
	cat <<'USAGE'
Usage: rpios-look-set [OPTION]...
The look of the Raspberry Pi Desktop session, for you only. It changes the
running session at once and is kept for your next logins; other sessions
and other users are not changed.

  --theme NAME         pixflat, pixnoir, pixtrix, pixonyx or pix, with
                       everything Raspberry Pi OS gives it: icons, cursor,
                       font, window frames, colours and wallpaper
  --animations on|off|default
                       window and application animations, such as the
                       outline when a window is minimized; default is the
                       session's, as Raspberry Pi OS has them (on)
  --list               the themes installed
  --show               print the current look
  --reset              back to the session's look, as installed; this also
                       resets your Openbox settings, such as window keys
  --session x|wayland  the session your next login starts: Raspberry Pi
                       Desktop on X or on Wayland (both are on the login
                       screen; the one you pick there is remembered too)
  -h, --help           this text

In the Wayland session, --theme, --reset and --show work on that session's
own look; PiX is a theme of the X session only.

Examples: rpios-look-set --theme pixonyx
          rpios-look-set --animations off
          rpios-look-set --reset
USAGE
}
die() { printf 'rpios-look-set: %s\n' "$*" >&2; exit 1; }

# Replace a file with stdin at once, through a temporary file in its folder,
# so that a program that watches it (settings-keeper, lxsession) never reads
# it half written. Usage: replace FILE
replace() {
	local f tmp
	mkdir -p -- "${1%/*}" && f=$(readlink -f -- "$1") && tmp=$(mktemp -- "$f.XXXXXX") || return 1
	{ cat >"$tmp" && { [[ ! -e $f ]] || chmod --reference="$f" -- "$tmp"; } && mv -f -- "$tmp" "$f"; } || { rm -f -- "$tmp"; return 1; }
}
# Write all the changes to a user's file at once: COMMAND reads the user's
# file, else the session's (the first change), on stdin and prints the new
# file. Usage: edit FILE SESSION_FILE COMMAND [ARG]...
edit() {
	local in=$1 out
	[[ -f $in ]] || in=$2
	{ out=$("${@:3}" <"$in") && printf '%s\n' "$out" | replace "$1"; } || die "cannot write $1"
}
# INI files. Usage: ini_get FILE SECTION KEY
ini_get() {
	S="[$2]" K=$3 awk '$0 == ENVIRON["S"] { f = 1; next } /^\[/ { f = 0 }
		f && index($0, ENVIRON["K"] "=") == 1 { print substr($0, length(ENVIRON["K"]) + 2); exit }' "$1" 2>/dev/null
}
# Change one section of an INI file on stdin: KEY=VALUE sets a key, KEY
# alone removes it. Usage: ini_edit SECTION CHANGE...
ini_edit() {
	S="[$1]" C=$(printf '%s\n' "${@:2}") awk '
		BEGIN { n = split(ENVIRON["C"], c, "\n")
			for (i = 1; i <= n; i++) { e = index(c[i], "=")
				if (e) { k[++m] = substr(c[i], 1, e - 1); v[k[m]] = substr(c[i], e + 1) } else del[c[i]] = 1 } }
		function put(key) { if (!(key in done)) print key "=" v[key]; done[key] = 1 }
		function rest(i) { for (i = 1; i <= m; i++) put(k[i]) }
		$0 == ENVIRON["S"] { print; ins = 1; seen = 1; next }
		/^\[/ { if (ins) rest(); ins = 0 }
		ins && (e = index($0, "=")) { key = substr($0, 1, e - 1); if (key in del) next; if (key in v) { put(key); next } }
		{ print }
		END { if (ins) rest(); if (!seen && m) { print ""; print ENVIRON["S"]; rest() } }'
}
# Change the [GTK] section of the user's desktop.conf. Usage: gtk_edit CHANGE...
gtk_edit() { edit "$lxs" "$lxs_sys" ini_edit GTK "$@"; }
# Print a value from the user's file, else from the session's
get() { local v; v=$(ini_get "$1" "$3" "$4"); [ -n "$v" ] || v=$(ini_get "$2" "$3" "$4"); printf '%s' "$v"; }

theme_dirs() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/$1" "$HOME/.$1" /usr/local/share/"$1" /usr/share/"$1"; }
gtk_theme() {
	local d
	while IFS= read -r d; do [[ -f $d/$1/gtk-3.0/gtk.css ]] && return 0; done < <(theme_dirs themes)
	return 1
}
icon_theme() {
	local d
	while IFS= read -r d; do [[ -f $d/$1/index.theme ]] && return 0; done < <(theme_dirs icons)
	return 1
}
# Set the window title font and size, as Raspberry Pi OS sets them
set_openbox_font() {
	ob+=(-e "/<theme>/,/<\/theme>/ { /<font /,/<\/font>/ {
		s|<name>[^<]*</name>|<name>$1</name>|; s|<weight>[^<]*</weight>|<weight>$2</weight>|
		s|<slant>[^<]*</slant>|<slant>Normal</slant>|; s|<size>[^<]*</size>|<size>$FONT_SIZE</size>| } }")
}

list() {
	local t
	printf 'Themes (--theme): '
	for t in $PI_THEMES; do
		# PiX is a theme of the X session only
		[[ $t != pix ]] || ! wl_session || continue
		theme_look "$t" && gtk_theme "$gtk" && printf '%s ' "$t"
	done
	printf '\n'
}

# The running X session of this user, if any, and its display and D-Bus
# address for the commands that reach it
session_pid() { pgrep -u "$(id -u)" -f "^/usr/bin/lxsession -s $PROFILE( |\$)" | head -n1; }
attach() {
	local p=$1 line
	[[ -n ${DISPLAY:-} ]] && return 0
	while IFS= read -r -d '' line; do
		case $line in DISPLAY=*|XAUTHORITY=*|DBUS_SESSION_BUS_ADDRESS=*) export "${line?}" ;; esac
	done </proc/"$p"/environ
}
running() { pgrep -u "$(id -u)" -x "$1" >/dev/null; }
# Print a colour as #rrggbb (GTK 2 writes #rrrrggggbbbb)
short() { local c=$1; (( ${#c} != 13 )) || c="#${c:1:2}${c:5:2}${c:9:2}"; printf '%s\n' "$c"; }
# Print a theme's own GTK 2 colour scheme (highlight and panel colours);
# fail if it is incomplete
theme_scheme() {
	local f k v out=""
	while IFS= read -r f; do [[ -f $f/$1/gtk-2.0/gtkrc ]] && break; done < <(theme_dirs themes)
	f=$f/$1/gtk-2.0/gtkrc
	for k in selected_bg_color selected_fg_color bar_bg_color bar_fg_color; do
		v=$(sed -n 's/^[[:space:]]*gtk-color-scheme[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$f" 2>/dev/null | head -n1 \
			| tr -s '\\' '\n' | sed -n "s/^n\{0,1\}$k:\(#[0-9A-Fa-f]\{6\}\)\$/\1/p" | head -n1)
		[[ -n $v ]] || return 1
		v=${v,,} v="#${v:1:2}${v:1:2}${v:3:2}${v:3:2}${v:5:2}${v:5:2}"
		out+="$k:$v\\n"
	done
	printf '%s\n' "$out"
}

show() {
	local w
	printf 'Theme          %s\n' "$(get "$lxs" "$lxs_sys" GTK sNet/ThemeName)"
	printf 'Icons          %s\n' "$(get "$lxs" "$lxs_sys" GTK sNet/IconThemeName)"
	w=$(ob_theme "$obrc" 2>/dev/null)
	printf 'Windows        %s\n' "${w:-$(ob_theme "$ob_sys")}"
	printf 'Cursor         %s, %s pixels\n' "$(get "$lxs" "$lxs_sys" GTK sGtk/CursorThemeName)" "$(get "$lxs" "$lxs_sys" GTK iGtk/CursorThemeSize)"
	printf 'Font           %s\n' "$(get "$lxs" "$lxs_sys" GTK sGtk/FontName)"
	case $(ini_get "$lxs" GTK iGtk/EnableAnimations) in
		0) echo 'Animations     off, set by you (default on)' ;;
		1) echo 'Animations     on, set by you (default on)' ;;
		*) echo 'Animations     on, default' ;;
	esac
	w=$(get "$fm/desktop-items-0.conf" "$fm_sys/desktop-items-0.conf" '*' wallpaper)
	printf 'Wallpaper      %s (%s)\n' "${w:-none}" "$(get "$fm/desktop-items-0.conf" "$fm_sys/desktop-items-0.conf" '*' wallpaper_mode)"
	printf 'Desktop        %s, text %s\n' "$(short "$(get "$fm/desktop-items-0.conf" "$fm_sys/desktop-items-0.conf" '*' desktop_bg)")" \
		"$(short "$(get "$fm/desktop-items-0.conf" "$fm_sys/desktop-items-0.conf" '*' desktop_fg)")"
}

# Print the window theme of an Openbox file (not a font name)
ob_theme() { sed -n '/<theme>/,/<\/theme>/ { /<font /,/<\/font>/!s|.*<name>\([^<]*\)</name>.*|\1|p }' "$1" | head -n1; }
# Print the start of the user's Openbox file, for the first change. Raspberry
# Pi's Openbox reads it over the session's settings: it holds the session's
# <theme> only, as the file of Raspberry Pi OS's Appearance Settings holds
# only what they set, so that the session's other settings (such as the keys)
# still apply. Debian's Openbox reads one file: a copy of the session's.
ob_start() {
	if [[ -x /usr/bin/openbox-pi ]]; then
		printf '<?xml version="1.0" encoding="UTF-8"?>\n<openbox_config xmlns="http://openbox.org/3.4/rc">\n'
		sed -n '/<theme>/,/<\/theme>/p' "$ob_sys"
		printf '</openbox_config>\n'
	else cat -- "$ob_sys"; fi
}
# Set Openbox's theme in the user's Openbox file, with the theme's corners:
# rounded unless its border.radius is 0 (see _ob_round in rpios-look). The
# size's window theme (the large one for Large and Larger), else the theme.
# Usage: set_openbox_theme WINDOW-THEME THEME
set_openbox_theme() {
	local r t=$1
	[[ -f /usr/share/themes/$t/openbox-3/themerc ]] || t=$2
	set -- "$t"
	r=$(sed -n 's/^border\.radius:[[:space:]]*//p' "/usr/share/themes/$1/openbox-3/themerc" 2>/dev/null | head -n 1)
	if [[ ${r:-0} == 0 ]]; then r=no; else r=yes; fi
	# The theme name only, not the font names inside <font>
	ob+=(-e "/<theme>/,/<\/theme>/ { /<font /,/<\/font>/!s|<name>[^<]*</name>|<name>$1</name>|; s|<roundCorners>[^<]*</roundCorners>|<roundCorners>$r</roundCorners>| }")
}

# Set the session's GSettings (org.gnome.desktop.interface), which GTK 4
# programs and others read, to the theme's look, all at once: KEY=VALUE
# sets a key, KEY alone resets it to the session's default. Only in the
# session's own dconf database (DCONF_PROFILE): other sessions keep theirs.
# Without a running D-Bus, a private one is started for the write.
# Usage: set_gsettings KEY=VALUE... | KEY...
set_gsettings() {
	local d=/org/gnome/desktop/interface/
	local prof=${GS_PROFILE:-$SHARE/dconf/profile}
	local -a run=(env DCONF_PROFILE="$prof")
	[[ -f $prof ]] && command -v dconf >/dev/null || return 0
	[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} || -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]] || run=(dbus-run-session -- "${run[@]}")
	if [[ $1 == *=* ]]; then { echo '[/]'; printf '%s\n' "$@"; } | "${run[@]}" dconf load "$d"
	else "${run[@]}" sh -c 'for k in "$@"; do dconf reset "$0$k" || exit; done' "$d" "$@"; fi >/dev/null 2>&1 \
		|| echo "rpios-look-set: the theme and light or dark style of GTK 4 programs could not be set" >&2
}

# Set the desktop settings per monitor, as Desktop Preferences keeps them:
# the session's (reset_desktop) or the theme's (write_desktop)
reset_desktop() {
	local i k s c
	for i in 0 1; do
		s=$fm_sys/desktop-items-$i.conf c=()
		[[ -f $s ]] || continue
		for k in wallpaper wallpaper_mode desktop_bg desktop_fg desktop_shadow desktop_font; do c+=("$k=$(ini_get "$s" '*' "$k")"); done
		edit "$fm/desktop-items-$i.conf" "$s" ini_edit '*' "${c[@]}"
	done
}
write_desktop() {
	local i
	for i in 0 1; do
		[[ -f $fm_sys/desktop-items-$i.conf ]] || continue
		edit "$fm/desktop-items-$i.conf" "$fm_sys/desktop-items-$i.conf" ini_edit '*' ${wall:+"wallpaper=$wall"} wallpaper_mode=crop \
			"desktop_bg=$DESK_BG" "desktop_fg=$DESK_FG" "desktop_shadow=$DESK_SHADOW" "desktop_font=$font"
	done
}

# The Wayland session (labwc), which keeps a look of its own: its own
# GSettings database (DCONF_PROFILE, see start-wayland), labwc's window
# theme in the user's labwc file, as Raspberry Pi OS's Appearance Settings
# keeps it there, and the cursor in labwc's environment file
wlrc=$config/labwc/rc.xml wlenv=$config/labwc/environment wl_sys=$SHARE/xdg/labwc/rc.xml
wl_session() { [[ ${XDG_SESSION_DESKTOP:-} == "$WLSESSION" || ( -n ${WAYLAND_DISPLAY:-} && ${DESKTOP_SESSION:-} == rpd-labwc ) ]]; }
wl_gs() { DCONF_PROFILE=$SHARE/dconf/profile-wayland gsettings get org.gnome.desktop.interface "$1" 2>/dev/null | tr -d "'"; }
wl_show() {
	local w
	printf 'Session        Raspberry Pi Desktop on Wayland\n'
	printf 'Theme          %s\n' "$(wl_gs gtk-theme)"
	printf 'Icons          %s\n' "$(wl_gs icon-theme)"
	w=$(ob_theme "$wlrc" 2>/dev/null)
	printf 'Windows        %s\n' "${w:-$(ob_theme "$wl_sys")}"
	printf 'Cursor         %s, %s pixels\n' "$(wl_gs cursor-theme)" "$(wl_gs cursor-size)"
	printf 'Font           %s\n' "$(wl_gs font-name)"
	w=$(get "$fm/desktop-items-0.conf" "$fm_sys/desktop-items-0.conf" '*' wallpaper)
	printf 'Wallpaper      %s\n' "${w:-none}"
}
# Write labwc's window theme and fonts into the user's labwc file: the
# session's <theme> section with the theme's name, as Openbox's (ob_start);
# labwc reads it over the session's settings (labwc -m)
wl_rc_theme() {
	local blk t=$1
	# The large window theme only where a theme folder has it (labwc
	# looks in the same folders)
	local d found=0
	while IFS= read -r d; do [[ -f $d/$t/openbox-3/themerc ]] && { found=1; break; }; done < <(theme_dirs themes)
	(( found )) || t=${t%_l}
	# The theme's name and fonts only: labwc adds a list such as the title
	# bar's buttons to the session's when it merges the files (labwc -m)
	blk=$(sed -n '/<theme>/,/<\/theme>/p' "$wl_sys" | sed '/<titlebar>/,/<\/titlebar>/d' | sed "/<font /,/<\/font>/!s|<name>[^<]*</name>|<name>$t</name>|; /<font /,/<\/font>/ { s|<name>[^<]*</name>|<name>$2</name>|; s|<weight>[^<]*</weight>|<weight>$3</weight>| }")
	mkdir -p "${wlrc%/*}" || die "cannot create ${wlrc%/*}"
	wl_track "$wlrc"
	if [[ ! -s $wlrc ]]; then printf '<?xml version="1.0" encoding="UTF-8"?>\n<openbox_config xmlns="http://openbox.org/3.4/rc">\n</openbox_config>\n' >"$wlrc"; fi
	{ _strip_theme <"$wlrc" | sed '/^[[:space:]]*<\/openbox_config>[[:space:]]*$/d; s|</openbox_config>||' | awk 'NF || !blank { print } { blank = !NF }'; printf '%s\n</openbox_config>\n' "$blk"; } >"$wlrc.new" && cat -- "$wlrc.new" >"$wlrc" && rm -f -- "$wlrc.new"
}
# Record a labwc file of the user's before its first change, as the install
# records the files it changes (see _track_file in rpios-look): --uninstall
# puts it back, and --reset takes its own theme and cursor from the record.
# Debian's labwc session reads these files too. Usage: wl_track FILE
wl_track() {
	local st=${XDG_STATE_HOME:-$HOME/.local/state}/$APP rel=${1#"$HOME"/}
	# Files outside the home folder are not recorded, as by the install
	[[ $1 == "$HOME"/* ]] || return 0
	mkdir -p "$st/files" && touch "$st/keys" "$st/created" || return 0
	grep -qxF "file:$rel" "$st/keys" && return 0
	if [[ -e $1 ]]; then mkdir -p "$(dirname "$st/files/$rel")" && cp -aL -- "$1" "$st/files/$rel"
	else printf '%s\n' "$rel" >>"$st/created"; fi
	printf 'file:%s\n' "$rel" >>"$st/keys"
}
# Print the record of a labwc file of the user's (wl_track), if any.
wl_recorded() {
	local f=${XDG_STATE_HOME:-$HOME/.local/state}/$APP/files/${1#"$HOME"/}
	[[ -f $f ]] && cat -- "$f"
}
# Set labwc's cursor (its environment file), or remove a look's cursor
# (PiX..., also -Debian), leaving the user's own. Usage: wl_cursor [THEME]
wl_cursor() {
	[[ -z ${1:-} ]] || wl_track "$wlenv"
	if [[ -f $wlenv ]]; then
		if [[ -n ${1:-} ]]; then sed -i --follow-symlinks '/^XCURSOR_THEME=/d' "$wlenv"
		else sed -i --follow-symlinks -E '/^XCURSOR_THEME=PiX[a-z]*(-Debian)?$/d' "$wlenv"; fi
		[[ -s $wlenv ]] || rm -f -- "$wlenv"
	fi
	[[ -n ${1:-} ]] || return 0
	mkdir -p "${wlenv%/*}" && printf 'XCURSOR_THEME=%s\n' "$1" >>"$wlenv"
}
wl_main() {
	local gs=() s
	# Animations are the X session's (Openbox): said also beside a theme
	if [[ -n $anim ]]; then
		echo "rpios-look-set: --animations applies to the X session (Openbox)" >&2
		[[ -n $theme ]] || (( reset )) || exit 2
	fi
	if (( reset )); then
		gs=(gtk-theme icon-theme cursor-theme font-name color-scheme)
		# Only a theme block that rpios-look-set wrote (a look's window theme)
		if grep -qs '<name>PiX[a-z]*\(_l\)\?</name>' "$wlrc"; then
			# The recorded theme block, also one written on a single line
			s=$(wl_recorded "$wlrc" | _theme_block -)
			{ _strip_theme <"$wlrc" | sed '/^[[:space:]]*<\/openbox_config>[[:space:]]*$/d; s|</openbox_config>||'; [[ -z $s ]] || printf '%s\n' "$s"; echo '</openbox_config>'; } >"$wlrc.new" \
				&& cat -- "$wlrc.new" >"$wlrc" && rm -f -- "$wlrc.new"
			# A file with nothing else in it goes
			grep -qvE '^[[:space:]]*(<\?xml[^>]*>|</?openbox_config[^>]*>)?[[:space:]]*$' "$wlrc" || rm -f -- "$wlrc"
		fi
		s=$(wl_recorded "$wlenv" | sed -n 's/^XCURSOR_THEME=//p' | tail -n 1)
		wl_cursor
		if [[ -n $s ]] && ! grep -qs '^XCURSOR_THEME=' "$wlenv"; then mkdir -p "${wlenv%/*}" && printf 'XCURSOR_THEME=%s\n' "$s" >>"$wlenv"; fi
		reset_desktop
	elif [[ -n $theme ]]; then
		wl_rc_theme "$wm_theme" "$ob_font" "$ob_weight"
		wl_cursor "$icons"
		write_desktop
		s=light; (( ! dark )) || s=dark
		gs=("gtk-theme='$gtk'" "icon-theme='$icons'" "cursor-theme='$icons'" "font-name='$font'" "color-scheme='prefer-$s'")
	fi
	(( ! ${#gs[@]} )) || GS_PROFILE=$SHARE/dconf/profile-wayland set_gsettings "${gs[@]}"
	DCONF_PROFILE=$SHARE/dconf/profile-wayland "$SHARE/xsettings" >/dev/null 2>&1 || true
	sh -c ". $SHARE/session-env && export DCONF_PROFILE=$SHARE/dconf/profile-wayland && gtk_weight \"\$(gsettings get org.gnome.desktop.interface font-name | tr -d \"'\")\"" >/dev/null 2>&1 || true
	if running labwc; then labwc --reconfigure >/dev/null 2>&1 || true; fi
	for p in pcmanfm-pi pcmanfm; do
		if running "$p"; then "$p" --profile "$FMPROFILE" --reconfigure >/dev/null 2>&1 || true; break; fi
	done
	# The panel takes a new icon theme when it starts again (the session
	# restarts it, see lwrespawn)
	if running wf-panel-pi; then pkill -u "$(id -u)" -x wf-panel-pi 2>/dev/null || true; fi
	wl_show
}
# The session the user's next login starts, as picking it on the login
# screen does: through AccountsService, else ~/.dmrc. Usage: set_session x|wayland
set_session() {
	local id u name
	case $1 in
		x) id=$XSESSION name="Raspberry Pi Desktop (X)" ;;
		wayland) id=$WLSESSION name="Raspberry Pi Desktop (Wayland)"
			[[ -f /usr/share/wayland-sessions/$WLSESSION.desktop ]] || die "the Wayland session is not installed on this computer" ;;
		*) die "--session takes x or wayland" ;;
	esac
	u=/org/freedesktop/Accounts/User$(id -u)
	if command -v busctl >/dev/null \
		&& busctl call org.freedesktop.Accounts "$u" org.freedesktop.Accounts.User SetXSession s "$id" >/dev/null 2>&1; then
		busctl call org.freedesktop.Accounts "$u" org.freedesktop.Accounts.User SetSession s "$id" >/dev/null 2>&1 || true
	else
		if grep -qs '^Session=' "$HOME/.dmrc"; then sed -i "s|^Session=.*|Session=$id|" "$HOME/.dmrc"
		else printf '[Desktop]\nSession=%s\n' "$id" >>"$HOME/.dmrc"; fi
		# LightDM's copy, which it reads where it cannot read the home folder
		# (an encrypted one): root's to write, without a password prompt here
		u=/var/cache/lightdm/dmrc/$(id -un).dmrc
		if [[ -f $u ]] && ! sudo -n tee "$u" <"$HOME/.dmrc" >/dev/null 2>&1; then
			echo "If the login screen still offers the other session, pick $name there once."
		fi
	fi
	echo "Your next login starts $name."
}

theme="" reset=0 anim="" session=""
(( $# )) || { usage; exit 2; }
while (( $# )); do
	o=$1
	case $o in --*=*) set -- "${o%%=*}" "${o#*=}" "${@:2}"; o=$1 ;; esac
	case $o in
		--show) if wl_session; then wl_show; else show; fi; exit 0 ;;
		--list) list; exit 0 ;;
		--session) [[ -n ${2:-} ]] || die "$o needs a value"; session=$2; shift ;;
		-h|--help) usage; exit 0 ;;
		--reset) reset=1 ;;
		--theme) [[ -n ${2:-} ]] || die "$o needs a value"; theme=$2; shift ;;
		--animations) (( $# >= 2 )) || die "$o needs a value"; anim=$2; shift
			[[ $anim =~ ^(on|off|default)$ ]] || die "--animations takes on, off or default" ;;
		*) die "unknown option '$o' (see --help)" ;;
	esac
	shift
done
[[ -z $theme ]] || (( ! reset )) || die "give --theme or --reset, not both"
[[ -z $anim ]] || (( ! reset )) || die "give --animations or --reset, not both"

[[ -f $lxs_sys ]] || die "the Raspberry Pi Desktop session is not installed"
if [[ -n $session ]]; then
	set_session "$session"
	[[ -n $theme$anim ]] || (( reset )) || exit 0
fi
gtk="" wm_theme="" icons="" font="" ob_font="" ob_weight="" wall="" dark=0
if [[ -n $theme ]]; then
	theme_look "$theme" || die "unknown theme '$theme': pixflat, pixnoir, pixtrix, pixonyx or pix"
	if wl_session && [[ $gtk == PiX ]]; then
		printf 'rpios-look-set: PiX is an X theme (Raspbian Stretch); log in to Raspberry Pi Desktop (X) to use it\n' >&2
		exit 2
	fi
	gtk_theme "$gtk" || die "the $gtk theme is not installed (see --list)"
	icon_theme "$icons" || die "the $icons icons are not installed"
	wall=$WALLS/$wall
	[[ -f $wall ]] || { printf 'rpios-look-set: the wallpaper %s is not installed; the desktop keeps its own\n' "$wall" >&2; wall=""; }
fi

if wl_session; then wl_main; exit 0; fi

old_theme=$(get "$lxs" "$lxs_sys" GTK sNet/ThemeName) old_icons=$(get "$lxs" "$lxs_sys" GTK sNet/IconThemeName)
old_cursor=$(get "$lxs" "$lxs_sys" GTK sGtk/CursorThemeName)/$(get "$lxs" "$lxs_sys" GTK iGtk/CursorThemeSize)
old_anim=$(ini_get "$lxs" GTK iGtk/EnableAnimations)
# The changes to desktop.conf's [GTK] (lx), the Openbox file (sed
# expressions, ob) and GSettings (gs), collected so that each is written once
lx=() ob=() gs=()
if (( reset )); then
	for k in sNet/ThemeName sNet/IconThemeName sGtk/CursorThemeName iGtk/CursorThemeSize sGtk/FontName sGtk/ColorScheme; do
		lx+=("$k=$(ini_get "$lxs_sys" GTK "$k")")
	done
	lx+=(iGtk/EnableAnimations)
	reset_desktop
	gs=(gtk-theme icon-theme cursor-theme font-name color-scheme)
	# Openbox follows the session's settings again, as after a reset in
	# Raspberry Pi OS's Appearance Settings: without the user's file
	rm -f -- "$obrc" || die "cannot remove $obrc"
elif [[ -n $theme ]]; then
	# The theme's look, with its own colours (a dark panel for a dark
	# theme), else Raspberry Pi OS's
	lx+=("sNet/ThemeName=$gtk" "sNet/IconThemeName=$icons" "sGtk/CursorThemeName=$icons"
		"iGtk/CursorThemeSize=$CURSOR_SIZE" "sGtk/FontName=$font"
		"sGtk/ColorScheme=$(theme_scheme "$gtk" || printf '%s\n' "$COLOR_SCHEME")")
	set_openbox_theme "$wm_theme" "$gtk"
	set_openbox_font "$ob_font" "$ob_weight"
	write_desktop
	# As XSETTINGS has them; light or dark as Raspberry Pi OS's Appearance
	# Settings sets it
	s=light; (( ! dark )) || s=dark
	gs=("gtk-theme='$gtk'" "icon-theme='$icons'" "cursor-theme='$icons'" "font-name='$font'" "color-scheme='prefer-$s'")
fi
# Animations: GTK's, which lxsession passes on, and Openbox's outline when a
# window is minimized or restored
if [[ -n $anim ]]; then
	case $anim in
		off) lx+=(iGtk/EnableAnimations=0); a=no ;;
		on) lx+=(iGtk/EnableAnimations=1); a=yes ;;
		default) lx+=(iGtk/EnableAnimations)
			a=$(sed -n 's|.*<animateIconify>\([^<]*\)</animateIconify>.*|\1|p' "$ob_sys" | head -n1) ;;
	esac
	ob+=(-e "s|<animateIconify>[^<]*</animateIconify>|<animateIconify>${a:-yes}</animateIconify>|")
fi
(( ! ${#lx[@]} )) || gtk_edit "${lx[@]}"
# GTK 3's text weight follows the font (gtk_weight); a theme change reloads it
sh -c ". $SHARE/session-env && gtk_weight" >/dev/null 2>&1 || true
(( ! ${#ob[@]} )) || edit "$obrc" <(ob_start) sed "${ob[@]}"
new_theme=$(ini_get "$lxs" GTK sNet/ThemeName)

# A running X session: lxsession passes the theme, icons, cursor, font and
# GTK 2 colours on by itself when its file changes
p=$(session_pid)
if [[ -z $p ]]; then
	(( ! ${#gs[@]} )) || set_gsettings "${gs[@]}"
	echo "Saved; the Raspberry Pi Desktop session uses it from your next login."
	show
	exit 0
fi
attach "$p"
# Through the session's D-Bus, so that open GTK 4 programs follow at once
(( ! ${#gs[@]} )) || set_gsettings "${gs[@]}"
if [[ -n $old_anim && -z $(ini_get "$lxs" GTK iGtk/EnableAnimations) ]]; then
	# lxsession keeps the last value of a removed key: set GTK's default (1)
	# briefly, then remove the key
	gtk_edit iGtk/EnableAnimations=1; sleep 0.1
	gtk_edit iGtk/EnableAnimations
fi
if [[ -z $theme ]] && (( ! reset )); then
	# Animations only: Openbox reloads its settings
	if running 'openbox(-pi)?'; then "$SHARE/bin/openbox" --reconfigure >/dev/null 2>&1 || true; fi
	show
	exit 0
fi
if [[ $new_theme == "$old_theme" ]]; then
	# GTK 3 reloads colours only on a theme change: switch to another theme
	# for 100 ms, as Raspberry Pi OS's Appearance Settings does
	tmp=Adwaita; [[ -d /usr/share/themes/t$new_theme ]] && tmp=t$new_theme
	gtk_edit "sNet/ThemeName=$tmp"; sleep 0.1
	gtk_edit "sNet/ThemeName=$new_theme"
fi
# Openbox restarts in place rather than reloading its settings: a reload
# leaves open windows without the theme's rounded corners (roundCorners).
# The panel restarts after Openbox is back, not while no window manager runs.
# Openbox names its version on the root window when it starts: the name is
# removed first and awaited. (Its check window can keep the same ID: the new
# X connection may get the old one's client slot.)
if running 'openbox(-pi)?'; then
	xprop -root -remove _OB_VERSION 2>/dev/null
	"$SHARE/bin/openbox" --restart >/dev/null 2>&1 || true
	for _ in {1..60}; do
		[[ $(xprop -root _OB_VERSION 2>/dev/null) == *\"* ]] && break
		sleep 0.05
	done
	sleep 0.2
fi
# The menu's entries are rebuilt. The panel reloads its icons, as Raspberry
# Pi OS's Appearance Settings has it; a new icon theme needs a restart, as
# the menu button, the menu and the notification area keep their old icons.
sh -c ". $SHARE/session-env && menu_tidy" >/dev/null 2>&1 || true
pc=refresh
[[ $(ini_get "$lxs" GTK sNet/IconThemeName) == "$old_icons" ]] || pc=restart
if running lxpanel-pi; then lxpanelctl-pi "$pc" >/dev/null 2>&1 || true
elif running lxpanel; then lxpanelctl "$pc" >/dev/null 2>&1 || true; fi
# The desktop rereads its settings: wallpaper, colours and font
for p in pcmanfm-pi pcmanfm; do
	if running "$p"; then "$p" --profile "$FMPROFILE" --reconfigure >/dev/null 2>&1 || true; break; fi
done
if [[ $(ini_get "$lxs" GTK sGtk/CursorThemeName)/$(ini_get "$lxs" GTK iGtk/CursorThemeSize) != "$old_cursor" ]]; then
	echo "Window borders keep the old cursor until your next login."
fi
show
EOF
	} | _write "$root/usr/bin/$APP_NAME-set"
	chmod 0755 "$root/usr/bin/$APP_NAME-set"
}

# Set the session's values (S_*): its profile, the wallpaper, and whether
# Raspberry Pi's panel (on a desktop this script knows: its layout comes
# from that release's package) and file manager are used. Run in the main
# shell before the package is built.
session_vars() {
	S_PROFILE=$SESSION_PROFILE
	S_WALL=$(_wallpaper_path)
	S_PI_PANEL=0 S_PI_FM=0
	if [[ -x /usr/bin/lxpanel-pi ]] && (( DESKTOP_KNOWN )); then S_PI_PANEL=1; fi
	if [[ -x /usr/bin/pcmanfm-pi ]]; then S_PI_FM=1; fi
	# Raspberry Pi's file manager uses its 'default' profile, as on Raspberry Pi OS
	S_FM_PROFILE=$S_PROFILE
	if (( S_PI_FM )); then S_FM_PROFILE=default; fi
}

# Keep the appearance in the user's lxsession settings file. lxsession reads
# desktop.conf once, at login. When the file changes it only passes the new
# look on (XSETTINGS) and keeps its own copy as it was. A setting changed
# through lxsession (LXSession Configuration's default applications, for
# example) makes it write that copy back over the whole file, so the theme,
# icons, cursor, font, mouse and keyboard return to their login values: the
# desktop redraws with the old icons. lxsession changes only settings outside
# [GTK], [Mouse] and [Keyboard]; rpios-look-set, Customize Look and Feel and
# LXInput change only these. settings-keeper watches the file: when one
# write changes both, it is lxsession's, and the three sections are put back
# as they were just before it. A file read half written (one that is not
# complete, or lacks a section it had) is skipped, never merged. A file that
# lacks some of the session's settings gets them, at the start and when it is
# created: Debian's lxsession reads the user's file alone, while Raspberry
# Pi's adds the session's settings that it lacks, and Customize Look and Feel
# (lxappearance) creates the file with its own settings only. The start
# script runs it for the session, and it ends with the process whose ID it
# is given. Usage: settings_keeper_build ROOT
settings_keeper_build() {
	cat <<'EOF' | _write "$1$SHARE/settings-keeper"
#!/usr/bin/python3
# Keep the appearance in lxsession's settings file (see rpios-look).
# Usage: settings-keeper USER-FILE SESSION-FILE PID
import ctypes
import ctypes.util
import os
import select
import struct
import sys

KEEP = ("[GTK]", "[Mouse]", "[Keyboard]")
IN_CLOSE_WRITE, IN_MOVED_TO = 0x8, 0x80


def read(path):
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            return f.read()
    except OSError:
        return None


def sections(text):
    """The file's sections in order, as [header, text]; '' for the lines before the first."""
    out = [["", ""]]
    for line in text.splitlines(keepends=True):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            out.append([s, ""])
        out[-1][1] += line
    return out


def values(secs, keep):
    d = {}
    for head, body in secs:
        if (head in KEEP) != keep:
            continue
        for line in body.splitlines()[1 if head else 0:]:
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                d[head, k.strip()] = v.strip()
    return d


def whole(prev, new):
    """Whether the new file is complete: every line ended and well formed, and
    every section of the previous copy still there. A program that writes the
    file in place can be read half way."""
    if not new.endswith("\n"):
        return False
    for line in new.splitlines():
        s = line.strip()
        if s and s[0] not in "#;" and "=" not in s and not (s[0] == "[" and s[-1] == "]"):
            return False
    return {h for h, _ in sections(prev)} <= {h for h, _ in sections(new)}


def merge(prev, new):
    """The new file with the previous appearance, if lxsession wrote it; else None."""
    ps, ns = sections(prev), sections(new)
    if not whole(prev, new) or values(ps, False) == values(ns, False) or values(ps, True) == values(ns, True):
        return None
    old = {h: b for h, b in ps if h in KEEP}
    out = []
    for head, body in ns:
        if head in KEEP:
            body = old.pop(head, "")
        out.append(body)
    for head, body in ps:
        if head in old:
            out.append(body)
    text = ""
    for body in out:
        if body and text and not text.endswith("\n"):
            text += "\n"
        if body.startswith("[") and text and not text.endswith("\n\n"):
            text += "\n"
        text += body
    return text


def complete(text, defaults):
    """The file with the session's settings that it lacks, if it lacks any;
    else None. Its own settings stay. Debian's lxsession reads only the
    user's file, where Raspberry Pi's adds the session's settings it lacks."""
    if not defaults or not whole("", text):
        return None
    secs = sections(text)
    have = values(secs, True)
    have.update(values(secs, False))
    add = {}
    for head, body in sections(defaults):
        for line in body.splitlines()[1 if head else 0:]:
            if head and "=" in line and not line.lstrip().startswith("#"):
                k = line.split("=", 1)[0].strip()
                if (head, k) not in have:
                    add.setdefault(head, []).append(line + "\n")
    if not add:
        return None
    out = ""
    for head, body in secs:
        if head in add:
            body = body.rstrip("\n") + "\n" + "".join(add.pop(head)) + ("\n" if body.endswith("\n\n") else "")
        out += body
    for head, lines in add.items():
        out = out.rstrip("\n") + ("\n\n" if out else "") + head + "\n" + "".join(lines)
    return out


def write(path, text):
    """Replace the file at once, through a temporary file beside it."""
    target = os.path.realpath(path)
    tmp = target + ".settings-keeper"
    try:
        with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
            f.write(text)
        os.replace(tmp, target)
        return True
    except OSError:
        return False


def main():
    if len(sys.argv) != 4 or not sys.argv[3].isdigit():
        sys.exit("usage: settings-keeper USER-FILE SESSION-FILE PID")
    path, pid = sys.argv[1], int(sys.argv[3])
    folder, name = os.path.split(path)
    os.makedirs(folder, exist_ok=True)
    defaults = read(sys.argv[2]) or ""
    # What lxsession read at login: the user's file, else the session's
    prev = read(path)
    exists = prev is not None
    if not exists:
        prev = defaults
    else:
        done = complete(prev, defaults)
        if done is not None and write(path, done):
            prev = done
    libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
    fd = libc.inotify_init1(os.O_CLOEXEC)
    if fd < 0 or libc.inotify_add_watch(fd, os.fsencode(folder), IN_CLOSE_WRITE | IN_MOVED_TO) < 0:
        sys.exit("settings-keeper: cannot watch " + folder)
    # It ends with the session (PID): told by the kernel from Linux 5.3
    # (pidfd_open, the same number on every architecture), else checked
    # every 5 seconds
    end = libc.syscall(434, pid, 0)
    while True:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        except PermissionError:
            pass
        if end >= 0:
            ready = select.select([fd, end], [], [])[0]
            if end in ready:
                return
        elif not select.select([fd], [], [], 5)[0]:
            continue
        data, i, hit = os.read(fd, 65536), 0, False
        while i + 16 <= len(data):
            _, _, _, n = struct.unpack_from("iIII", data, i)
            hit |= data[i + 16:i + 16 + n].rstrip(b"\0") == os.fsencode(name)
            i += 16 + n
        if not hit:
            continue
        new = read(path)
        if new is None:
            exists = False
            continue
        # A new file without some of the session's settings gets them, such
        # as the one Customize Look and Feel creates with its own settings;
        # later writes are merged as below
        if not exists:
            exists = True
            done = complete(new, defaults)
            if done is not None:
                if write(path, done):
                    prev = done
                continue
        # A file read half written is skipped, and compared with no longer
        if not whole(prev, new):
            continue
        fixed = merge(prev, new)
        if fixed is not None and write(path, fixed):
            new = fixed
        prev = new


if __name__ == "__main__":
    main()
EOF
	chmod 0755 "$1$SHARE/settings-keeper"
}

# Composite the X session with NVIDIA's own driver. Without a compositor that
# driver redraws what a moved window uncovers late: the window's rounded
# corners turn square and its frame breaks up while it is dragged. picom runs
# with its GL backend and no effects; it starts only while the session is on
# screen, as its GL backend fails behind the lock screen. The driver also
# drops picom's GL images while another virtual terminal is shown (the lock
# screen's login screen, a text console), and picom then shows a black
# screen on return: it starts again each time the session comes back. Other
# drivers, and a computer without picom, get no compositor, as on Raspberry
# Pi OS for PCs: Raspberry Pi OS 13 starts "xcompmgr -aR" (cmstart), but -R
# is only in Raspberry Pi's Arm build, and Debian's xcompmgr, which its PC
# edition uses, stops at the unknown option.
# Usage: compositor_build ROOT
compositor_build() {
	cat <<'EOF' | _write "$1$SHARE/compositor"
#!/bin/sh
# The X session's compositor with NVIDIA's own driver (see rpios-look).
[ -d /sys/module/nvidia ] && command -v picom >/dev/null || exit 0
run() { exec picom --config /dev/null --backend glx --vsync; }
[ -n "${XDG_VTNR:-}" ] && [ -r /sys/class/tty/tty0/active ] || { run; exit; }
shown() { [ "$(cat /sys/class/tty/tty0/active 2>/dev/null)" = "tty$XDG_VTNR" ]; }
while ! shown; do sleep 2; done
run & pid=$!
trap 'kill $pid 2>/dev/null; exit 0' TERM INT HUP
# Ends with picom: with the X server, or for the session to start it again
away=
while kill -0 $pid 2>/dev/null; do
	sleep 2
	if ! shown; then away=1
	elif [ -n "$away" ]; then
		away=; kill $pid 2>/dev/null; wait $pid; run & pid=$!
	fi
done
wait $pid
EOF
	chmod 0755 "$1$SHARE/compositor"
}

# Write the session's power button program, as Raspberry Pi OS's pwrkey: the
# Shutdown dialog; pressed again while the dialog is open, shut down. A key
# event repeated at once (some systems deliver the power key twice) finds
# the dialog just opened and is not a second press. Without the dialog, the
# computer shuts down, as systemd-logind would have it. The session's start
# scripts hold systemd-logind's own handling of the key back while the
# session runs. Usage: pwrkey_build ROOT
pwrkey_build() {
	cat <<'EOF' | _write "$1$SHARE/pwrkey"
#!/bin/sh
# The power button of the Raspberry Pi Desktop session (see rpios-look).
p=$(pgrep -u "$(id -u)" -f '(^|/)pishutdown( |$)' | head -n 1)
if [ -z "$p" ]; then
	[ ! -x /usr/bin/pishutdown ] || exec pishutdown
	exec systemctl poweroff
fi
[ "$(ps -o etimes= -p "$p" | tr -d ' ')" -lt 1 ] 2>/dev/null || exec systemctl poweroff
EOF
	chmod 0755 "$1$SHARE/pwrkey"
}

# Raspberry Pi's archive in APT, pinned to the packages installed unchanged
# (PIN_PKGS), so that "apt upgrade" updates the look as it updates Debian; all
# else from that archive is blocked. The packages repacked beside Debian's
# are updated by --refresh. After dpkg runs, a check names the packages of the
# look that are no longer installed (apt-check).
# Usage: apt_files ROOT
apt_files() {
	local root=$1 k="" d=$WORKDIR/apt-keyring
	{
		printf '// Written by %s and removed with %s (see %s/apt-check)\n' "$APP_NAME" "$APP_PKG" "$SHARE"
		printf 'DPkg::Post-Invoke { "[ ! -x %s/apt-check ] || %s/apt-check || true"; };\n' "$SHARE" "$SHARE"
	} | _write "$root$APT_HOOK"
	sed -e "s|@SYS@|$SYS_DIR|g; s|@APP@|$APP_NAME|g" <<'CHECK' | _write "$root$SHARE/apt-check"
#!/bin/sh
# Run by APT after dpkg: name the packages of the look that are no longer
# installed (APT removes one when a Debian update needs it gone) and how to
# bring them back. Quiet while the script itself runs; never fails.
list=@SYS@/look-packages
[ -r "$list" ] || exit 0
pgrep -f 'rpios-look(-legacy)?[.]sh' >/dev/null && exit 0
gone=""
for p in $(cat "$list"); do
	case $(dpkg-query -W -f='${db:Status-Abbrev}' "$p" 2>/dev/null) in
		?i*) ;;
		*) gone="$gone $p" ;;
	esac
done
[ -z "$gone" ] || echo "@APP@: part of the Raspberry Pi Desktop is no longer installed:$gone. Bring it back with: bash @APP@.sh --refresh" >&2
exit 0
CHECK
	chmod 0755 "$root$SHARE/apt-check"
	(( ${#PIN_PKGS[@]} )) || return 0
	# The key from raspberrypi-archive-keyring (current APT rejects the older
	# key file); only the key, as the package would trust it for every source.
	if resolve_pkg raspberrypi-archive-keyring && k=$(download_pkg raspberrypi-archive-keyring); then
		rm -rf -- "$d"; mkdir -p "$d"; dpkg-deb -x "$k" "$d"
		k=$(find "$d/usr/share/keyrings" -type f -name 'raspberrypi-archive-keyring.*' 2>/dev/null | head -n1)
	fi
	[[ -s $k ]] || { note "Raspberry Pi's archive key was not found: updates come with $(self_cmd) --refresh only."; return 0; }
	mkdir -p "$root${APT_KEY%/*}"
	install -m 0644 "$k" "$root$APT_KEY"
	printf 'Types: deb\nURIs: %s\nSuites: %s\nComponents: main\nArchitectures: %s\nSigned-By: %s\n' \
		"$RPI_ARCHIVE" "$H_SUITE" "$H_ARCH" "$APT_KEY" | _write "$root$APT_SRC"
	{
		printf '# Written by %s and removed with %s: from Raspberry Pi'"'"'s archive, APT\n' "$APP_NAME" "$APP_PKG"
		printf '# takes only the packages that %s installed as Raspberry Pi ships them.\n' "$APP_NAME"
		printf 'Package: %s\nPin: origin %s\nPin-Priority: 500\n\n' "${PIN_PKGS[*]}" "$(_host "$RPI_ARCHIVE")"
		printf 'Package: *\nPin: origin %s\nPin-Priority: -1\n' "$(_host "$RPI_ARCHIVE")"
	} | _write "$root$APT_PIN"
}

# Write the whole session into the package root: profile, Openbox, panels,
# menu, file manager, entries, icons, themes, programs and GSettings defaults.
# Usage: session_build ROOT
session_build() {
	local root=$1 xdg=$1$SHARE/xdg data=$1$SHARE/data rc pi
	_session_profile "$xdg"
	# The session's Openbox settings, where Raspberry Pi OS keeps its own
	# (/etc/xdg/openbox): its build of Openbox reads them from the first
	# folder of XDG_CONFIG_DIRS (the session's), then the user's own file over
	# them (see _session_programs)
	rc=$xdg/openbox/$OB_FILE
	# Raspberry Pi OS's own Openbox settings for this release, else Debian's
	pi=$( (pi_unpack "$PANEL_PKG" "$H_SUITE" "$H_ARCH") 2>/dev/null ) && pi+=/etc/xdg/openbox/$OB_FILE || pi=""
	_seed "$rc" ${pi:+"$pi"} "$SYS_ROOT"/etc/xdg/openbox/LXDE/rc.xml "$SYS_ROOT"/etc/xdg/openbox/rc.xml \
		|| die "Openbox's rc.xml is missing (install openbox)"
	_openbox_rc "$rc"
	_openbox_keys "$rc" "$pi"
	# Debian's Openbox, obconf and Customize Look and Feel read one file only:
	# without the user's, Openbox's rc.xml, which in this session is the
	# session's settings
	ln -sfn "$OB_FILE" "$xdg/openbox/rc.xml"
	_lxpanel_layout | _panel_size | _write "$xdg/lxpanel/$S_PROFILE/panels/panel"
	# The panel's logout opens Raspberry Pi's Shutdown dialog
	if command -v pishutdown >/dev/null; then printf '[Command]\nLogout=pishutdown\n' | _write "$xdg/lxpanel/$S_PROFILE/config"; fi
	(( S_PI_PANEL )) && _pi_panel_layout | _panel_size | _write "$xdg/lxpanel-pi/panels/panel"
	_session_files "$xdg"
	_session_menu "$xdg" "$data"
	_session_entries "$xdg" "$data"
	_session_icons "$data"
	_session_themes "$data"
	_session_programs "$root"
	_session_command "$root"
	_session_dconf "$root"
	(( ! WAYLAND )) || _wayland_session "$root"
}

# Copy a panel layout from stdin with the size preset's icon size, panel
# height and taskbar button width, as Appearance Settings sets them.
_panel_size() {
	sed -E -e "s/^([[:space:]]*)(iconsize|height)=[0-9]+[[:space:]]*\$/\1\2=$T_PANEL_ICON/" \
		-e "s/^([[:space:]]*MaxTaskWidth)=[0-9]+[[:space:]]*\$/\1=$T_TASK_WIDTH/"
}

# Print the login screen's background picture: Debian's login artwork, which
# follows Debian's active theme, else the session's wallpaper (without
# desktop-base), else nothing.
login_background() {
	local f=/usr/share/desktop-base/active-theme/login/background.svg
	if [[ -e $f ]]; then printf '%s\n' "$f"; return 0; fi
	# S_WALL is set only when its wallpaper is installed; the link comes
	# with the session package
	if [[ -n ${S_WALL:-} ]]; then printf '%s\n' "$S_WALL"; fi
}

# Write the Raspberry Pi OS login screen for LightDM: Debian's GTK greeter in
# its style, with the session chooser, and the list of users to choose from,
# as Raspberry Pi OS shows it. Usage: login_build ROOT
login_build() {
	local root=$1 logo bg
	# The user picture is the menu button's logo (logo_badge_build), else Debian's
	logo=${LOGO_BADGE:-$(_greeter_logo || true)}
	bg=$(login_background)
	[[ -n $bg ]] || { bg='#d6d3de'; warn "Debian's login screen artwork is unavailable; the login screen shows its colour."; }
	{
		printf '# Written by %s: the Raspberry Pi OS login screen style\n[greeter]\n' "$APP_NAME"
		printf 'theme-name=%s\nicon-theme-name=%s\ncursor-theme-name=%s\ncursor-theme-size=%s\n' \
			"$T_GTK" "$T_ICONS" "$T_ICONS" "$T_CURSOR_SIZE"
		printf 'font-name=%s\nxft-antialias=true\nxft-hintstyle=hintfull\nxft-rgba=rgb\n' "$T_FONT"
		printf 'background=%s\nuser-background=false\nposition=50%%,center 50%%,center\n' "$bg"
		# The session chooser and the power menu, without the other indicators
		printf 'indicators=~spacer;~session;~power\n'
		if [[ -n $logo ]]; then printf 'default-user-image=%s\n' "$logo"; fi
	} | _write "$root/usr/share/lightdm/lightdm-gtk-greeter.conf.d/60_$APP_NAME.conf"
	printf '# Written by %s: the Raspberry Pi OS login screen\n[Seat:*]\ngreeter-hide-users=false\n' "$APP_NAME" \
		| _write "$root/usr/share/lightdm/lightdm.conf.d/60_$APP_NAME.conf"
}

# Choose the Raspberry Pi Desktop session for this user's next logins, as
# picking it on the login screen does: through AccountsService, which LightDM
# reads, else in ~/.dmrc and LightDM's copy of it, which its greeter
# reads (it cannot read a private home folder). This is done on the first
# install, and later only where AccountsService has no session for the user
# yet (it was installed later); a session the user picks is kept.
choose_session() {
	local user cur m v first=0 want=$SESSION_ID
	_once session-chosen && first=1
	user=/org/freedesktop/Accounts/User$(id -u)
	if command -v busctl >/dev/null \
		&& cur=$(busctl get-property org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User XSession 2>/dev/null); then
		# Set on first install, or where no session is set yet
		(( first )) || [[ $cur == 's ""' ]] || return 0
		# A file this creates is removed on uninstall; a session chosen before
		# is put back
		as_root test -e "/var/lib/AccountsService/users/$(id -un)" || id -un | record_add "$SYS_DIR/accounts-created"
		for m in XSession Session; do
			v=$(busctl get-property org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User "$m" 2>/dev/null | sed -n 's/^s "\(.*\)"$/\1/p' || true)
			[[ -z $v || $v == "$SESSION_ID" || $v == "$WL_SESSION_ID" ]] || printf '%s\t%s\t%s\n' "$(id -un)" "$m" "$v" | record_add "$SYS_DIR/session-before"
		done
		as_root busctl call org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User SetXSession s "$want" >/dev/null 2>&1 || true
		as_root busctl call org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User SetSession s "$want" >/dev/null 2>&1 || true
	else
		(( first )) || return 0
		_ini_set "$HOME/.dmrc" Desktop Session "$want"
		chmod 0644 "$HOME/.dmrc"
		if [[ -d /var/cache/lightdm ]]; then sys_write "/var/cache/lightdm/dmrc/$(id -un).dmrc" <"$HOME/.dmrc"; fi
	fi
	ok "Your next login uses the Raspberry Pi Desktop session; the login screen offers the others too"
}

###############################################################################
# 7. Install: packages, the generated package, records
###############################################################################

# Stop if a required tool is missing.
preflight_tools() {
	local t missing=()
	for t in dpkg-deb gpgv base64 sha256sum awk sed gzip perl flock; do
		command -v "$t" >/dev/null || missing+=("$t")
	done
	(( ${#missing[@]} == 0 )) || die "missing tools: ${missing[*]} (install them with apt)"
	if ! command -v curl >/dev/null && ! command -v wget >/dev/null; then
		die "curl or wget is needed to download the packages; install curl with: sudo apt install curl ca-certificates"
	fi
}

# Decide whether Raspberry Pi OS's network plugin (netman) is used, as on
# Raspberry Pi OS: with Raspberry Pi's panel (DESKTOP_KNOWN), where
# NetworkManager runs the network (installed, or installed now for Wi-Fi), and
# where Raspberry Pi has its build of libnma, which the plugin needs (its
# hotspot dialog): that build is installed beside Debian's (TWINS), for the
# plugin and Raspberry Pi's connection editor only. Otherwise the panel shows
# only a network applet that is installed already.
# Sets USE_NETMAN.
netman_decide() {
	USE_NETMAN=0
	(( DESKTOP_KNOWN )) || return 0
	nm_runs || { [[ -z $(installed_version network-manager) ]] && has_wifi \
		&& [[ -z $(installed_version connman)$(installed_version wicd) ]]; } || return 0
	[[ $(index_candidates "$H_SUITE" "$H_ARCH" libnma0 2>/dev/null | first_line | cut -f1) == *+rpt* ]] || return 0
	USE_NETMAN=1
}

# Raspberry Pi's builds of Debian's packages (or, for pcmanfm-pi, of its
# program and files) that the look uses, as grep -E alternatives; each is
# repacked to install beside Debian's (beside_build): Openbox, the file
# manager, libnma and the Wayland session's screen lock
# (swaylock, whose Pi mode Debian's lacks; it runs as swaylock-pi and
# unlocks through PAM's "other" service, which Debian points at common-auth).
readonly TWIN_RE="openbox|libobrender32v5|pcmanfm-pi|libnma0|swaylock"

# Print the names that the last run's repacking decided (beside_plan): KIND is
# beside (repacked) or plain (used as Raspberry Pi ships them), or pairs
# (TWIN:SONAME, the twins' libraries). Usage: beside_seen KIND
beside_seen() { sed -n "s/^$1=//p" "$BESIDE_CONF" 2>/dev/null | first_line | tr ' ' '\n' | awk 'NF'; }
# Succeed if NAME is among them; read whole, as a reader that stops early
# breaks the pipe of the programs before it. Usage: beside_has KIND NAME
beside_has() { [[ $'\n'$(beside_seen "$1")$'\n' == *$'\n'"$2"$'\n'* ]]; }

# Print the name under which a Raspberry Pi package is installed: its own, or
# BESIDE_PREFIX and its own where it is repacked (a twin, or a package that
# this run's or else the last run's repacking decided so).
# Usage: inst_name PACKAGE
inst_name() {
	if [[ " ${TWINS[*]} ${BESIDE[*]} " == *" $1 "* ]] \
		|| { (( ! BESIDE_DONE )) && beside_has beside "$1"; }; then
		printf '%s%s\n' "$BESIDE_PREFIX" "$1"
	else printf '%s\n' "$1"; fi
}

# Succeed if it is known, without its file, whether a resolved package is
# repacked: a twin; one the last run decided; one without compiled code (an
# "all" package) that depends on no package repacked. Usage: beside_known PACKAGE
beside_known() {
	local d
	[[ " ${TWINS[*]} " != *" $1 "* ]] || return 0
	{ beside_has beside "$1" || beside_has plain "$1"; } && return 0
	[[ ${PKG_FILE[$1]:-} == *_all.deb ]] || return 1
	for d in $(depnames <<<"${PKG_DEPS[$1]:-}"); do
		if [[ " ${TWINS[*]} " == *" $d "* ]] || beside_has beside "$d"; then return 1; fi
	done
}

# Decide which Raspberry Pi packages are repacked beside Debian's (see
# beside_build): the twins, every downloaded package that needs it for them
# (it installs into their folders, uses their libraries or depends on a
# repacked package) and those the last run decided that are not downloaded
# now. Writes the run's configuration, with the sonames of the twins'
# libraries, and sets BESIDE and BESIDE_DONE.
# Usage: beside_plan PACKAGE=FILE...
beside_plan() {
	local pf p s add conf=$WORKDIR/beside.conf
	local -a asis=() pairs=()
	local -A file=()
	for pf; do file[${pf%%=*}]=${pf#*=}; done
	BESIDE=()
	for p in $(beside_seen beside); do
		[[ -z ${file[$p]:-} && " ${FETCH_PKGS[*]} " == *" $p "* && " ${TWINS[*]} " != *" $p "* ]] && BESIDE+=("$p")
	done
	for p in "${TWINS[@]}"; do
		if [[ -n ${file[$p]:-} ]]; then
			for s in $(beside sonames "${file[$p]}"); do pairs+=("$p:$s"); done
		else mapfile -t -O "${#pairs[@]}" pairs < <(beside_seen pairs | grep "^$p:" || true); fi
	done
	add=1
	while (( add )); do
		add=0
		printf 'twins=%s\nlibs=%s\nbeside=%s\npairs=%s\n' "${TWINS[*]}" "$(printf '%s\n' "${pairs[@]#*:}" | sort -u | xargs)" \
			"${BESIDE[*]}" "${pairs[*]}" >"$conf"
		for p in "${!file[@]}"; do
			[[ " ${TWINS[*]} ${BESIDE[*]} " != *" $p "* ]] || continue
			if beside need "$conf" "${file[$p]}"; then BESIDE+=("$p") add=1; fi
		done
	done
	for p in "${FETCH_PKGS[@]}"; do [[ " ${TWINS[*]} ${BESIDE[*]} " == *" $p "* ]] || asis+=("$p"); done
	printf 'plain=%s\n' "${asis[*]}" >>"$conf"
	BESIDE_DONE=1
}

# Record what is repacked (BESIDE_CONF), which --refresh reads, and the
# packages of the look, which APT's check after dpkg reads (apt_files).
look_record() {
	local p
	sys_write "$BESIDE_CONF" <"$WORKDIR/beside.conf"
	printf '%s\n' "${FETCH_PKGS[@]}" | while read -r p; do inst_name "$p"; done | sort -u | sys_write "$SYS_DIR/look-packages"
}

# Before the repacked packages are installed, remove the repacked packages
# that this run no longer uses (such as the network plugin's, once it is
# left out).
beside_tidy() {
	local p
	local -a unused=()
	while read -r p; do
		[[ $p == "$APP_PKG" || " ${TWINS[*]} ${BESIDE[*]} " == *" ${p#"$BESIDE_PREFIX"} "* ]] || unused+=("$p")
	done < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "$BESIDE_PREFIX*" 2>/dev/null | awk '$1 ~ /^.i/ { print $2 }')
	(( ${#unused[@]} )) || return 0
	info "Removing repacked packages that are no longer used: ${unused[*]}"
	# Never with packages that need them (Debian's LXDE needs openbox): then
	# nothing is removed and the install stops
	local safe rc=0
	safe=$(_safe_purge_set "${unused[@]}" 2>/dev/null) || rc=$?
	(( rc != 2 )) || die "APT cannot work out what removing ${unused[*]} would remove (see 'apt-get -s purge ${unused[*]}'); nothing was removed"
	[[ $(LC_ALL=C sort <<<"$safe") == "$(printf '%s\n' "${unused[@]}" | LC_ALL=C sort)" ]] \
		|| die "removing ${unused[*]} would change other packages; nothing was removed. Run $(self_cmd) --uninstall, then install again"
	_purge -q "${unused[@]}" >/dev/null || die "APT could not remove ${unused[*]}; nothing else was changed"
}

# Decide what to install. FETCH_PKGS holds the Raspberry Pi OS packages,
# installed from verified .deb files: every theme with its icons, fonts and
# wallpapers and, where they fit, Raspberry Pi's panel and file manager.
# APT_PKGS holds the Debian packages the session and the themes need,
# installed by name from Debian's own sources.
resolve_all() {
	local p q
	local -a wanted=() asked=() helpers=() kept=()
	step "Resolving the latest official packages ($H_SUITE, $H_ARCH)"
	index_load "$H_SUITE" "$H_ARCH" || die "cannot download the $H_SUITE package index from $RPI_ARCHIVE"
	ok "Package index signature verified (Raspberry Pi Archive Signing Key)"
	# A desktop of a new design is not guessed at: the looks are installed,
	# with Debian's panel and file manager
	DESKTOP_KNOWN=0 WAYLAND=0
	if desktop_known "$H_SUITE" "$H_ARCH"; then
		DESKTOP_KNOWN=1
		# The Wayland session too, where Debian runs Raspberry Pi OS's
		if wayland_known "$H_SUITE" "$H_ARCH"; then WAYLAND=1
		else note "Only the X session is installed: $APP_NAME $APP_VERSION does not know Raspberry Pi OS $H_SUITE's Wayland desktop, or Debian has no labwc for it."; fi
		p=$(desktop_unknown "$H_SUITE" "$H_ARCH" | paste -sd' ' -)
		[[ -z $p ]] || note "Raspberry Pi OS $H_SUITE's desktop also has $p, which $APP_NAME $APP_VERSION does not install; a newer $APP_NAME may."
	else note "Raspberry Pi OS $H_SUITE has a desktop that $APP_NAME $APP_VERSION does not know: its themes and wallpapers are installed, with Debian's panel and file manager. A newer $APP_NAME is needed for the rest."; fi
	netman_decide
	read_lines wanted rpi_pkgs "$H_SUITE" "$H_ARCH"
	# The plugin's Edit Connections opens Raspberry Pi's connection editor
	(( USE_NETMAN )) && wanted+=(libnma0 lp-connection-editor)
	# What is asked for; the Raspberry Pi packages they need are dependencies
	asked=("${wanted[@]}")
	read_lines wanted with_rpi_deps "$H_SUITE" "$H_ARCH" "${wanted[@]}"
	FETCH_PKGS=()
	for p in "${wanted[@]}"; do IN_SET[$p]=1; done
	for p in "${wanted[@]}"; do
		if resolve_pkg "$p"; then FETCH_PKGS+=("$p")
		# A package with no usable build for this release is skipped; a Qt
		# style built for another Qt version (such as testing's newer Qt) is
		# replaced by Debian's (qt_choose)
		elif [[ ! $p =~ ^($QT_STYLE_RE)$ ]]; then warn "$p is not available for $H_SUITE/$H_ARCH; skipping it"; fi
	done
	drop_unmet
	qt_choose
	[[ " ${FETCH_PKGS[*]} " == *-theme\ * ]] || die "no theme packages are available for $H_SUITE/$H_ARCH"
	# Raspberry Pi's Openbox needs all of its packages: without one, Debian's
	for p in "${PI_WM[@]}"; do
		[[ " ${FETCH_PKGS[*]} " == *" $p "* ]] && continue
		note "Debian's Openbox is used: Raspberry Pi OS has no build of $p for $H_SUITE/$H_ARCH."
		kept=()
		for q in "${FETCH_PKGS[@]}"; do [[ " ${PI_WM[*]} " == *" $q "* ]] || kept+=("$q"); done
		FETCH_PKGS=("${kept[@]}")
		break
	done
	# The network plugin, and Raspberry Pi's libnma build it needs
	if (( USE_NETMAN )); then
		q=$(printf '%s\n' "${FETCH_PKGS[@]}" | grep -xF lpplug-netman | first_line || true)
		for p in "${q:-the network plugin}" libnma0; do
			[[ " ${FETCH_PKGS[*]} " == *" $p "* ]] && continue
			note "The panel has no network icon: Raspberry Pi OS has no build of $p for $H_SUITE/$H_ARCH."
			USE_NETMAN=0 kept=()
			for q in "${FETCH_PKGS[@]}"; do [[ $q =~ netman|^libnma|^lp-connection-editor$ ]] || kept+=("$q"); done
			FETCH_PKGS=("${kept[@]}")
			break
		done
	fi
	# The Wayland session needs Raspberry Pi's panel: without it, X only
	if (( WAYLAND )) && [[ " ${FETCH_PKGS[*]} " != *" wf-panel-pi "* ]]; then
		note "Only the X session is installed: Raspberry Pi OS has no build of wf-panel-pi for $H_SUITE/$H_ARCH."
		WAYLAND=0 kept=()
		for q in "${FETCH_PKGS[@]}"; do [[ $q =~ ^(wf-panel-pi|wfplug-.*|gui-screenshot|swaylock)$ ]] || kept+=("$q"); done
		FETCH_PKGS=("${kept[@]}")
	fi
	mapfile -t TWINS < <(printf '%s\n' "${FETCH_PKGS[@]}" | grep -xE "$TWIN_RE" || true)
	_refuse_debian_names "${FETCH_PKGS[@]}"

	mapfile -t helpers < <(session_debs; theme_debs; qt_debs; wayland_debs)
	if [[ -n $H_DM && $H_DM != lightdm ]]; then
		note "The Raspberry Pi OS login screen needs LightDM; this computer uses $H_DM. To switch: sudo apt install lightdm lightdm-gtk-greeter && sudo dpkg-reconfigure lightdm, then run this again."
	fi
	# Hardware support: the X server, network and Bluetooth tools, sound and
	# the login screen.
	mapfile -t HW_PKGS < <(x11_debs; tray_debs; audio_debs; login_debs)
	helpers+=("${HW_PKGS[@]}")
	ROOT_PKGS=("${helpers[@]}")
	for p in "${FETCH_PKGS[@]}"; do [[ " ${asked[*]} " != *" $p "* ]] || ROOT_PKGS+=("$p"); done
	APT_PKGS=()
	for p in "${helpers[@]}"; do
		[[ " ${APT_PKGS[*]} " == *" $p "* || " ${FETCH_PKGS[*]} " == *" $p "* || -n $(installed_version "$p") ]] && continue
		if apt_has "$p"; then APT_PKGS+=("$p"); fi
	done
	for p in "${FETCH_PKGS[@]}" "${APT_PKGS[@]}"; do IN_SET[$p]=1; done
}

# Leave out every package of FETCH_PKGS that needs a package of the install
# set that did not resolve, and those that need them in turn: while
# resolving, a member of the set counts as available before it is resolved.
drop_unmet() {
	local p changed=1
	local -a kept
	for p in "${!IN_SET[@]}"; do [[ -n ${PKG_DEPS[$p]+set} ]] || unset 'IN_SET[$p]'; done
	while (( changed )); do
		changed=0 kept=()
		for p in "${FETCH_PKGS[@]}"; do
			if _deps_satisfiable "${PKG_DEPS[$p]}"; then kept+=("$p"); continue; fi
			warn "$p is left out: a package it needs is not available for $H_SUITE/$H_ARCH"
			unset 'IN_SET[$p]'
			changed=1
		done
		FETCH_PKGS=("${kept[@]}")
	done
}

# A Raspberry Pi package must never replace a package from the APT sources,
# except its builds of Debian's packages (TWINS), which are repacked to
# install beside them.
# Usage: _refuse_debian_names PACKAGE...
_refuse_debian_names() {
	local p
	for p; do
		[[ " ${TWINS[*]} " != *" $p "* ]] || continue
		if [[ -n $(apt_versions "$p") ]]; then
			die "refusing to install $p from Raspberry Pi OS: your APT sources provide a package with that name"
		fi
	done
}

# Print the state of a resolved package on this system: new, an update or up
# to date. A newer installed version is kept, never downgraded.
_pkg_status() {
	local cur from=""
	cur=$(installed_version "$(inst_name "$1")")
	[[ ${PKG_SUITE[$1]:-$H_SUITE} == "$H_SUITE" ]] || from=" (from ${PKG_SUITE[$1]})"
	if [[ -z $cur ]]; then echo "new$from"
	elif dpkg --compare-versions "$cur" lt "${PKG_VER[$1]}"; then echo "update from $cur$from"
	elif dpkg --compare-versions "$cur" eq "${PKG_VER[$1]}"; then echo "up to date"
	else echo "installed $cur is newer; kept"; fi
}

# Print one package line of a status table.
_pkg_line() { printf '    %-12s %-28s %-18s %s\n' "$(pkg_category "$1")" "$1" "$2" "$3" >&2; }

# Print the component type of a package.
pkg_category() {
	case $1 in
		sound-theme-*)               echo sounds ;;
		pipewire*|pulseaudio|wireplumber) echo sound ;;
		lightdm*|desktop-base)       echo greeter ;;
		pcmanfm-pi|pcmanfm)   echo files ;;
		lxpanel-pi|lpplug-*|pplug-*|wf-panel-pi|wfplug-*|pishutdown|gui-runcmd|gui-screenshot) echo panel ;;
		network-manager|wpasupplicant|iw|wireless-regdb|rfkill|dnsmasq-base|bluez|libspa-0.2-bluetooth|pulseaudio-module-bluetooth|libnma*|lp-connection-editor) echo network ;;
		lxsession|lxpolkit|openbox|lxappearance|gvfs*|lxmenu-data|python3|dconf-cli|libglib2.0-bin) echo session ;;
		labwc|kanshi|wlr-randr|xsettingsd|xwayland|grim|slurp|squeekboard|swaylock) echo wayland ;;
		xserver-*|x11-*|libgl1-mesa-dri) echo display ;;
		*icon-theme*|*-icons)        echo icons ;;
		*-theme)                     echo themes ;;
		fonts-*)                     echo fonts ;;
		gtk2-engines-*|libgtk2.0-*|libgdk-pixbuf*) echo engines ;;
		*wallpaper*|"$ART_PKG")      echo wallpapers ;;
		*)                           echo dependencies ;;
	esac
}

# Stop unless every package in APT's plan comes from an official source: the
# verified files, or the Debian archive and its security updates. This keeps
# third-party and Raspberry Pi rebuilds of Debian packages out, even when
# such a source is configured.
# APT names a verified file after the archive that has the same version, so
# the files are matched by name and version.
# Usage: _check_origins APT-SIMULATION-OUTPUT [DEB]...
_check_origins() {
	local line pkg ver f origins
	local -A verified=()
	for f in "${@:2}"; do verified[$(dpkg-deb -f "$f" Package)=$(dpkg-deb -f "$f" Version)]=1; done
	while IFS= read -r line; do
		pkg=$(awk '{ print $2 }' <<<"$line") pkg=${pkg%%:*}
		ver=$(sed -E 's/^Inst [^ ]+ (\[[^]]*\] )?\(([^ ]+) .*/\2/' <<<"$line")
		[[ -z ${verified[$pkg=$ver]:-} ]] || continue
		# The archive name before the release: "Debian" in "Debian:13/stable"
		origins=$(sed -E 's/^Inst [^ ]+ (\[[^]]*\] )?\([^ ]+ ([^[]*)\[.*/\2/' <<<"$line")
		origins=${origins%%:*}; origins=${origins%% }
		if [[ ! $origins =~ ^(local-deb|Debian|Debian-Security)$ ]]; then
			die "refusing to install $pkg from '${origins% }': Debian packages must come from Debian"
		fi
	done < <(grep '^Inst ' <<<"$1")
}

# Print the given packages and the Raspberry Pi packages they need that Debian
# does not have (such as a plugin's data), which are installed from Raspberry
# Pi too. Usage: with_rpi_deps SUITE ARCH PACKAGE...
with_rpi_deps() {
	local suite=$1 arch=$2 names p n i
	local -a list=("${@:3}")
	local -A seen=()
	names=$(index_names "$suite" "$arch")
	for (( i = 0; i < ${#list[@]}; i++ )); do
		p=${list[i]}
		[[ -z ${seen[$p]:-} ]] || continue
		seen[$p]=1
		echo "$p"
		for n in $(index_candidates "$suite" "$arch" "$p" | first_line | cut -f6 | depnames); do
			[[ -z ${seen[$n]:-} ]] && grep -qxF "$n" <<<"$names" && ! _dep_ok "$n" && list+=("$n")
		done
	done
	return 0
}

# Adapt a Raspberry Pi package for Debian and print its path, or nothing if
# it is refused (scripts_coinstall). It fails on any other error, which
# stops the run. Usage: adapt_deb FILE
adapt_deb() {
	local f
	f=$(compat_fix "$1") && f=$(beside_pack "$f") && f=$(wall_own_dir "$f") && f=$(bt_pin_entry "$f") \
		&& scripts_coinstall "$f"
}

# Raspberry Pi's Bluetooth plugins: the PIN field of their pairing dialog
# cannot take the keyboard focus (can-focus False), so the PIN that legacy
# pairing (Bluetooth 2.0) asks for cannot be typed. The field is made
# focusable; nothing else changes. Prints the path of the package to install.
bt_pin_entry() {
	local deb=$1 f
	f=$(dpkg-deb -f "$deb" Package)
	[[ ${f#"$BESIDE_PREFIX"} =~ ^(lp|wf)plug-bluetooth$ ]] || { printf '%s\n' "$deb"; return 0; }
	deb_unpack "$deb" pin
	for f in "$R_DIR"/usr/share/*/ui/lxplug-bluetooth.ui; do
		[[ -f $f ]] && _pin_focus <"$f" >"$f.new" && mv -- "$f.new" "$f"
	done
	deb_pack
}
# Copy a Bluetooth plugin dialog from stdin with its PIN field focusable.
_pin_focus() {
	awk '/id="pair_entry"/ { e = 1 }
		e && /name="can[-_]focus"/ { sub(/>False</, ">True<"); e = 0 }
		e && /<\/object>/ { e = 0 }
		{ print }'
}
# Succeed if an installed Bluetooth plugin still has the unfocusable PIN
# field (one installed as Raspberry Pi ships it). Usage: _pin_unfixed PACKAGE
_pin_unfixed() {
	local f
	[[ ${1#"$BESIDE_PREFIX"} =~ ^(lp|wf)plug-bluetooth$ ]] || return 1
	while read -r f; do
		[[ -f $f ]] && ! cmp -s "$f" <(_pin_focus <"$f") && return 0
	done < <(dpkg -L "$1" 2>/dev/null | grep '/ui/lxplug-bluetooth\.ui$')
	return 1
}

# Download, verify and install the packages. APT never removes packages
# (--no-remove). Every package installed is recorded for --uninstall.
install_all() {
	local p f q v cur sim had accts manual
	local -a files=() opts=("${APT_OPTS[@]}") new=() left=() kept=() got=()
	step "Downloading and verifying packages"
	info "Refreshing APT package lists"
	as_root apt-get update -q >/dev/null || die "apt-get update failed"
	for p in "${APT_PKGS[@]}"; do apt_has "$p" || die "the Debian package '$p' is not available from your APT sources"; done
	# The packages installed as Raspberry Pi ships them, from earlier runs
	local -A plain=()
	if [[ -f $SYS_DIR/apt-packages ]]; then while read -r p; do [[ -z $p ]] || plain[$p]=1; done <"$SYS_DIR/apt-packages"; fi
	# What is new or newer, and what must be seen to decide whether it is
	# repacked beside Debian's (beside_known), is downloaded
	for p in "${FETCH_PKGS[@]}"; do
		cur=$(installed_version "$(inst_name "$p")")
		if [[ -n $cur ]] && dpkg --compare-versions "$cur" ge "${PKG_VER[$p]}" && ! _pin_unfixed "$(inst_name "$p")" && beside_known "$p"; then
			debug "$p $cur is installed and up to date"
			continue
		fi
		got+=("$p=$(download_pkg "$p")")
	done
	beside_plan "${got[@]}"
	for f in "${got[@]}"; do
		p=${f%%=*} f=${f#*=} q=$f
		cur=$(installed_version "$(inst_name "$p")")
		if [[ -n $cur ]] && dpkg --compare-versions "$cur" ge "${PKG_VER[$p]}" && ! _pin_unfixed "$(inst_name "$p")"; then
			debug "$p $cur is installed and up to date"
			continue
		fi
		# A package fixed at its installed version (_pin_unfixed): APT takes
		# the same version with other contents for a downgrade
		if [[ -n $cur ]] && dpkg --compare-versions "$cur" eq "${PKG_VER[$p]}" && [[ " ${opts[*]} " != *" --reinstall "* ]]; then
			opts+=(--reinstall --allow-downgrades)
		fi
		f=$(adapt_deb "$f") || die "$p could not be prepared for Debian (see above); stopped before installing the look"
		[[ -n $f ]] || { left+=("$p"); continue; }
		# APT updates the packages used unchanged from this release's suite
		# from Raspberry Pi's archive (apt_files); --refresh the others
		if [[ $f == "$q" && ${PKG_SUITE[$p]:-} == "$H_SUITE" ]]; then plain[$p]=1; else unset 'plain[$p]'; fi
		files+=("$f")
	done
	# A package left out was warned about; it is not checked for after APT
	if (( ${#left[@]} )); then
		note "Left out, as they would change Debian's packages or files: ${left[*]}"
		for p in "${FETCH_PKGS[@]}"; do [[ " ${left[*]} " == *" $p "* ]] || kept+=("$p"); done
		FETCH_PKGS=("${kept[@]}") kept=()
	fi
	# The network plugin needs all of its packages: without one, none
	if (( USE_NETMAN )) && [[ " ${left[*]} " =~ \ (libnma[^\ ]*|[^\ ]*netman[^\ ]*|lp-connection-editor)\  ]]; then
		note "The panel has no network icon: a package of Raspberry Pi's network plugin was left out."
		USE_NETMAN=0
		for f in "${files[@]}"; do [[ $(dpkg-deb -f "$f" Package) =~ netman|libnma|lp-connection-editor$ ]] || kept+=("$f"); done
		files=("${kept[@]}") kept=()
		for p in "${FETCH_PKGS[@]}"; do [[ $p =~ netman|^libnma|^lp-connection-editor$ ]] || kept+=("$p"); done
		FETCH_PKGS=("${kept[@]}") kept=()
		netman_debs_drop
	fi
	# Raspberry Pi's Openbox needs all of its packages: without one, Debian's
	for p in "${left[@]}"; do
		[[ " ${PI_WM[*]} " == *" $p "* ]] || continue
		note "Debian's Openbox is used: Raspberry Pi's build of $p was left out."
		for f in "${files[@]}"; do [[ " ${PI_WM[*]/#/$BESIDE_PREFIX} " == *" $(dpkg-deb -f "$f" Package) "* ]] || kept+=("$f"); done
		files=("${kept[@]}") kept=()
		for q in "${FETCH_PKGS[@]}"; do [[ " ${PI_WM[*]} " == *" $q "* ]] || kept+=("$q"); done
		FETCH_PKGS=("${kept[@]}") kept=()
		break
	done
	PIN_PKGS=()
	for p in "${FETCH_PKGS[@]}"; do [[ -z ${plain[$p]:-} ]] || PIN_PKGS+=("$p"); done
	printf '%s\n' "${PIN_PKGS[@]}" | sys_write "$SYS_DIR/apt-packages"
	# The repacked packages that are asked for stay installed by name
	for p in "${ROOT_PKGS[@]}"; do [[ $(inst_name "$p") == "$p" ]] || ROOT_PKGS+=("$(inst_name "$p")"); done

	step "Installing packages"
	if (( ${#files[@]} + ${#APT_PKGS[@]} )); then
		if ! sim=$(LC_ALL=C apt-get install --simulate "${opts[@]}" "${files[@]}" "${APT_PKGS[@]}" 2>&1); then
			tail -n 15 <<<"$sim" >&2
			die "APT cannot install the packages on this system (see above); nothing was changed"
		fi
		_check_origins "$sim" "${files[@]}"
	fi
	beside_tidy
	look_record
	if (( ${#files[@]} + ${#APT_PKGS[@]} == 0 )); then
		ok "Every package is installed and up to date"; return 0
	fi
	had=$(installed_names) accts=$(_accounts) manual=$(apt-mark showmanual 2>/dev/null)
	# What APT is about to install that is not installed (its simulation):
	# should APT fail or the computer stop meanwhile, the next run or
	# --uninstall finds which of them APT installed, and nothing else
	awk '/^Inst / { sub(/:.*/, "", $2); print $2 }' <<<"$sim" | { grep -vxF -f <(printf '%s\n' "$had") || true; } \
		| sys_write "$SYS_DIR/installing"
	if ! as_root env DEBIAN_FRONTEND=noninteractive apt-get install "${opts[@]}" "${files[@]}" "${APT_PKGS[@]}" 2>&1 \
		| tee "$WORKDIR/apt.out"; then
		# APT downloads everything before it installs anything, so a 404 means
		# that nothing was installed.
		if grep -qE '404 +Not Found' "$WORKDIR/apt.out"; then
			_installing_end
			die "your APT sources point to files Debian has moved (404 Not Found), so nothing was installed. When a Debian release reaches its end, its packages and security updates move to archive.debian.org: change /etc/apt/sources.list to match (see https://www.debian.org/distrib/archive), run 'sudo apt update', then run this again"
		fi
		_installing_end
		die "APT could not install the packages (see above)"
	fi
	_verify_installed
	mapfile -t new < <(LC_ALL=C comm -13 <(printf '%s\n' "$had") <(installed_names))
	_record_installed "${new[@]}"
	as_root rm -f -- "$SYS_DIR/installing"
	_keep_auto "$manual"
	# The system users and groups the packages created, which a purge keeps
	LC_ALL=C comm -13 <(printf '%s\n' "$accts") <(_accounts) | record_add "$SYS_DIR/accounts-new"
	start_sound "${new[@]}"
}

# Print the system's users and groups, as "user:NAME" and "group:NAME".
_accounts() {
	{ sed 's/:.*//; s/^/user:/' /etc/passwd; sed 's/:.*//; s/^/group:/' /etc/group; } | LC_ALL=C sort
}

# Start a sound server installed in this run for the running user; otherwise
# the user's service manager starts it only at the next login.
start_sound() {
	local -a units=()
	[[ " $* " == *" pipewire-pulse "* ]] && units=(pipewire.socket pipewire-pulse.socket wireplumber.service)
	[[ " $* " == *" pulseaudio "* ]] && units=(pulseaudio.socket)
	(( ${#units[@]} )) && [[ -S ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus ]] || return 0
	systemctl --user daemon-reload 2>/dev/null && systemctl --user start "${units[@]}" 2>/dev/null \
		&& ok "Sound server started" || true
}

# Warn about any package that is missing or older than resolved after APT ran.
_verify_installed() {
	local p cur bad=0
	for p in "${FETCH_PKGS[@]}" "${APT_PKGS[@]}"; do
		cur=$(installed_version "$(inst_name "$p")")
		if [[ -z $cur ]]; then
			note "$p is not installed"; bad=1
		elif [[ -n ${PKG_VER[$p]:-} ]] && dpkg --compare-versions "$cur" lt "${PKG_VER[$p]}"; then
			note "$p $cur is installed, older than ${PKG_VER[$p]}"; bad=1
		fi
	done
	(( bad )) || ok "Installed versions verified"
}

# APT marks a package installed from its .deb file as installed by name,
# also a dependency the script installed earlier that a newer file updates:
# such a dependency stays automatically installed, unless it was marked by
# name before this run. Usage: _keep_auto MANUAL (apt-mark showmanual before)
_keep_auto() {
	local -a autos=()
	mapfile -t autos < <(apt-mark showmanual 2>/dev/null | grep -xF -f <(cat "$SYS_DIR/installed-auto" 2>/dev/null) \
		| grep -vxF -f <(printf '%s\n' "$1") || true)
	(( ${#autos[@]} == 0 )) || as_root apt-mark auto "${autos[@]}" >/dev/null
}

# Record newly installed packages for --uninstall. Only dependencies are
# marked as automatically installed, as APT does; the packages this script
# asks for stay manual, so 'apt autoremove' never removes them while the look
# is installed.
_record_installed() {
	local p
	local -a autos=()
	(( $# )) || return 0
	for p; do [[ " ${ROOT_PKGS[*]} " == *" $p "* ]] || autos+=("$p"); done
	if (( ${#autos[@]} )); then
		as_root apt-mark auto "${autos[@]}" >/dev/null
		printf '%s\n' "${autos[@]}" | record_add "$SYS_DIR/installed-auto"
	fi
	_record_names "$@"
}

# Record packages as installed by this script; hardware support apart, so
# that the uninstall can name it. Usage: _record_names PACKAGE...
_record_names() {
	local p
	local -a look=() hw=()
	for p; do if [[ " ${HW_PKGS[*]} " == *" $p "* ]]; then hw+=("$p"); else look+=("$p"); fi; done
	if (( ${#look[@]} )); then printf '%s\n' "${look[@]}" | record_add "$SYS_DIR/installed-packages"; fi
	if (( ${#hw[@]} )); then printf '%s\n' "${hw[@]}" | record_add "$SYS_DIR/hardware-packages"; fi
}

# Record, once, the packages installed before the first install, so that
# --uninstall never removes them.
record_packages_before() {
	[[ -f $SYS_DIR/packages-before ]] || installed_names | sys_write "$SYS_DIR/packages-before"
}

# Print the packages that an APT run which did not finish installed: those
# of its plan (record installing) that are installed now.
_installing_new() {
	[[ -s $SYS_DIR/installing ]] || return 0
	grep -xF -f "$SYS_DIR/installing" <(installed_names) || true
}

# Record what an APT run which did not finish installed, as installed by
# this script. APT marked them itself (dependencies as automatically
# installed); their marks stay as they are.
_installing_end() {
	local -a new=()
	mapfile -t new < <(_installing_new)
	(( ${#new[@]} == 0 )) || _record_names "${new[@]}"
	as_root rm -f -- "$SYS_DIR/installing"
}

# Build the generated package from the installed official themes: icon sets
# with the Debian logo and the names Debian's programs use, the session and
# the login screen. Sets PKG_DEB to the package's path. It runs in the main
# shell, so that any failure stops the build.
# shellcheck disable=SC2016  # maintainer scripts contain a literal $1
build_pkg() {
	local stage=$WORKDIR/pkg b f ver icons=() depends="lxsession, openbox, lxpanel | lxpanel-pi, pcmanfm, python3"
	rm -rf -- "$stage"; mkdir -p "$stage/DEBIAN"
	logo_badge_build "$stage"
	for b in PiXflat PiXtrix PiX; do
		[[ -f $SYS_ROOT/usr/share/icons/$b/index.theme ]] || continue
		gen_icon_overlay "$b" "$stage/usr/share/icons/$b-Debian"
		icons+=("$b-Debian")
	done
	# The dark themes' sets, with the white logo (see set_theme)
	for b in PiXnoir:PiXflat PiXonyx:PiXtrix; do
		[[ " ${icons[*]} " == *" ${b#*:}-Debian "* ]] || continue
		if gen_logo_overlay "${b%%:*}-Debian" "${b#*:}-Debian" "$stage/usr/share/icons/${b%%:*}-Debian"; then icons+=("${b%%:*}-Debian"); fi
	done
	session_build "$stage"
	settings_keeper_build "$stage"
	compositor_build "$stage"
	pwrkey_build "$stage"
	wallpaper_links "$stage"
	apt_files "$stage"
	if [[ -n $(installed_version lightdm) ]]; then login_build "$stage"; fi

	ver="${APP_VERSION}+$(date -u +%Y%m%d%H%M%S)"
	mkdir -p "$stage/usr/share/doc/$APP_PKG"
	cat >"$stage/usr/share/doc/$APP_PKG/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $APP_NAME
Comment: Generated by $APP_NAME from the installed Raspberry Pi OS packages,
 whose own copyright files apply to the artwork and settings taken from them.

Files: *
Copyright: 2026 b1ack0p
License: MIT
EOF
	cat >"$stage/DEBIAN/control" <<EOF
Package: $APP_PKG
Version: $ver
Architecture: all
Maintainer: $APP_NAME <root@localhost>
Section: x11
Priority: optional
Depends: $depends
Enhances: pixflat-theme, pixflat-icons, pixtrix-theme, pixtrix-icons, pix-theme, rpd-icons
Description: Raspberry Pi Desktop session for Debian
 Generated locally by $APP_NAME $APP_VERSION from the installed official
 Raspberry Pi OS packages: the Raspberry Pi Desktop session and its settings,
 icon sets carrying the Debian logo and the icon and cursor names Debian's
 programs ask for, and the Raspberry Pi OS login screen style.
EOF
	{
		printf '#!/bin/sh\nset -e\nif [ "$1" = configure ] && command -v gtk-update-icon-cache >/dev/null; then\n'
		for f in "${icons[@]}"; do printf '\tgtk-update-icon-cache -q -t -f /usr/share/icons/%s || true\n' "$f"; done
		printf '\t:\nfi\n'
	} >"$stage/DEBIAN/postinst"
	{
		printf '#!/bin/sh\nset -e\nif [ "$1" = remove ] || [ "$1" = purge ]; then\n'
		for f in "${icons[@]}"; do
			printf '\trm -f /usr/share/icons/%s/icon-theme.cache\n\trmdir /usr/share/icons/%s 2>/dev/null || true\n' "$f" "$f"
		done
		printf '\t:\nfi\n'
	} >"$stage/DEBIAN/postrm"
	chmod 0755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/postrm"
	PKG_DEB=$WORKDIR/${APP_PKG}_${ver}_all.deb
	build_deb "$stage" "$PKG_DEB"
}

# Build and install the generated package for the installed themes and the
# chosen look.
install_pkg() {
	step "Building the Raspberry Pi Desktop session ($APP_PKG)"
	session_vars
	build_pkg
	as_root env DEBIAN_FRONTEND=noninteractive apt-get install "${APT_OPTS[@]}" "$PKG_DEB" >/dev/null
	ok "Installed $(basename "$PKG_DEB")"
}

# Reload the running Raspberry Pi Desktop session so that the new look appears
# at once: Openbox, the panel and the desktop restart. Openbox restarts in
# place, so that open windows get the theme's corners too (a reload leaves
# them square). Open windows stay open.
reload_session() {
	# The Wayland session: labwc rereads its settings; the panel and the
	# desktop start again with the new ones (the session restarts them)
	if _in_wl_session; then
		local p
		_running labwc && labwc --reconfigure >/dev/null 2>&1 || true
		"$SHARE/xsettings" >/dev/null 2>&1 9<&- || true
		pkill -u "$(id -u)" -x wf-panel-pi 2>/dev/null || true
		for p in pcmanfm-pi pcmanfm; do
			if _running "$p"; then "$p" --profile "${S_FM_PROFILE:-default}" --reconfigure >/dev/null 2>&1 9<&- || true; break; fi
		done
		ok "The running session shows the new look; log out and back in for the theme of open applications"
		return 0
	fi
	[[ ${XDG_SESSION_DESKTOP:-} == "$SESSION_ID" && -n ${DISPLAY:-} ]] || return 0
	local p
	_running 'openbox(-pi)?' && "$SHARE/bin/openbox" --restart >/dev/null 2>&1 || true
	for p in lxpanel-pi lxpanel; do
		if _running "$p"; then "${p/lxpanel/lxpanelctl}" restart 2>/dev/null || true; fi
	done
	for p in pcmanfm-pi pcmanfm; do
		_running "$p" && "$p" --desktop-off 2>/dev/null || true
	done
	# With Raspberry Pi's network plugin, nm-applet no longer starts in the
	# session; one started before would show a second network icon
	if (( USE_NETMAN )); then pkill -u "$(id -u)" -x nm-applet 2>/dev/null || true; fi
	# Start the desktop with the session's own environment, not this script's,
	# and without the script's run lock (file descriptor 9).
	setsid -f sh -c ". $SHARE/session-env; exec $SHARE/desktop" >/dev/null 2>&1 9<&- || true
	# The compositor (NVIDIA's own driver), which starts at login otherwise
	_running picom || pgrep -u "$(id -u)" -f "^/bin/sh $SHARE/compositor\$" >/dev/null \
		|| setsid -f "$SHARE/compositor" >/dev/null 2>&1 9<&- || true
	# settings-keeper: started if it is not running; a running one starts
	# again as this version, for as long as lxsession runs
	local prof lx
	prof=$SESSION_PROFILE
	lx=$(pgrep -u "$(id -u)" -f "^/usr/bin/lxsession -s $prof( |\$)" | head -n1)
	if [[ -n $lx && -x $SHARE/settings-keeper ]]; then
		pkill -u "$(id -u)" -f "^/usr/bin/python3 $SHARE/settings-keeper " 2>/dev/null || true
		setsid -f "$SHARE/settings-keeper" "${XDG_CONFIG_HOME:-$HOME/.config}/lxsession/$prof/desktop.conf" \
			"$SHARE/xdg/lxsession/$prof/desktop.conf" "$lx" </dev/null >/dev/null 2>&1 9<&- || true
	fi
	ok "The running session shows the new look; log out and back in for the theme of open applications"
}

###############################################################################
# 8. User state: backups for --uninstall
#
# A user file that the script changes (such as ~/.dmrc) is backed up in the
# user's state directory before its first change; --uninstall restores it.
###############################################################################

# Print the user's state directory.
_st() { printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/$APP_NAME"; }

# Create the state directory and record the parent folders this creates.
_state_init() {
	A_STATE=$(_st)
	local new
	new=$(_missing_dirs "$(dirname "$A_STATE")")
	mkdir -p "$A_STATE/files"
	touch "$A_STATE/keys" "$A_STATE/created" "$A_STATE/created-dirs"
	if [[ -n $new ]]; then printf '%s\n' "$new" >>"$A_STATE/created-dirs"; fi
}

# Print the missing directories of a path below $HOME, relative to $HOME,
# deepest first.
_missing_dirs() {
	local d=$1
	while [[ ! -d $d && $d == "$HOME"/* ]]; do printf '%s\n' "${d#"$HOME"/}"; d=$(dirname "$d"); done
}

# Before a file of the user's is first changed, back it up, or record it as
# new. Files outside the home folder (those of the generated package) are
# left alone.
_track_file() {
	[[ -n ${A_STATE:-} && $1 == "$HOME"/* ]] || return 0
	local path=$1 rel=${1#"$HOME"/}
	grep -qxF "file:$rel" "$A_STATE/keys" && return 0
	if [[ -e $path || -L $path ]]; then
		mkdir -p "$(dirname "$A_STATE/files/$rel")"
		# A symbolic link is saved by its content: writing and restoring both
		# go through it, so the link stays
		cp -aL -- "$path" "$A_STATE/files/$rel" 2>/dev/null || cp -a -- "$path" "$A_STATE/files/$rel"
	else
		printf '%s\n' "$rel" >>"$A_STATE/created"
		_missing_dirs "$(dirname "$path")" >>"$A_STATE/created-dirs"
	fi
	printf 'file:%s\n' "$rel" >>"$A_STATE/keys"
}

# Succeed only the first time a one-time step runs for this user, so that
# later runs keep the user's own changes to what it set up. Usage: _once STEP
_once() {
	grep -qxF "once:$1" "$A_STATE/keys" && return 1
	printf 'once:%s\n' "$1" >>"$A_STATE/keys"
}

# Forget the session choice that LightDM itself wrote into ~/.dmrc at a
# login into the session: only that line goes, the file's others stay.
# Usage: forget_dmrc
forget_dmrc() {
	local f=$HOME/.dmrc re="^Session=($SESSION_ID|$WL_SESSION_ID)\$"
	grep -qsE "$re" "$f" || return 0
	sed -i -E "/$re/d" "$f"
	ok "Your login's session choice (~/.dmrc) no longer names the Raspberry Pi Desktop"
}

# The terminal's font for the size preset, as Raspberry Pi OS's Appearance
# Settings sets it: in the user's LXTerminal settings (the terminal reads no
# other), started from LXTerminal's defaults where the user has none. The
# medium size puts back the font this script changed before. The file is
# recorded first (_track_file), so --uninstall restores it. On an install,
# and on --refresh with --size. Usage: term_font
term_font() {
	local f=${XDG_CONFIG_HOME:-$HOME/.config}/lxterminal/lxterminal.conf sys=$SYS_ROOT/usr/share/lxterminal/lxterminal.conf font
	local rel=${f#"$HOME"/}
	if [[ ${O_SIZE:-medium} == medium ]]; then
		grep -qxF "file:$rel" "$A_STATE/keys" 2>/dev/null || return 0
		# A font chosen since stays
		[[ $(sed -n 's/^fontname=//p' "$f" 2>/dev/null | first_line) == "$(sed -n 's/^termfont://p' "$A_STATE/keys" | tail -n 1)" ]] || return 0
		# The font of the file as it was, else the terminal's default
		font=""
		if [[ -f $A_STATE/files/$rel ]]; then font=$(sed -n 's/^fontname=//p' "$A_STATE/files/$rel" | first_line); fi
		if [[ -z $font && -f $sys ]]; then font=$(sed -n 's/^fontname=//p' "$sys" | first_line); fi
		[[ -n $font ]] || return 0
	else
		font=$T_TERM_FONT
	fi
	if [[ ! -e $f ]]; then
		_track_file "$f"
		mkdir -p "${f%/*}" && { cat -- "$sys" 2>/dev/null || true; } >"$f"
	fi
	_ini_set "$f" general fontname "$font"
	# The font written, so that --uninstall leaves a font chosen since
	sed -i '/^termfont:/d' "$A_STATE/keys"; printf 'termfont:%s\n' "$font" >>"$A_STATE/keys"
}

# Restore the user's settings and files from their state directory, then
# remove it. If anything cannot be restored, the directory is kept.
restore_user() {
	local st rel dst fail=0
	st=$(_st)
	[[ -f $st/keys ]] || return 0
	while IFS= read -r rel; do
		[[ $rel == file:* ]] || continue
		rel=${rel#file:}
		dst=${HOME:?}/$rel
		# Files Debian's own sessions read too: undone key by key, below
		case $rel in
			*/labwc/rc.xml|*/labwc/environment|*/lxterminal/lxterminal.conf|*/gtk-3.0/bookmarks|.gtk-bookmarks) continue ;;
			*/libfm/libfm.conf) [[ ! -f $st/libfm-written ]] || continue ;;
		esac
		if grep -qxF "$rel" "$st/created" 2>/dev/null; then
			rm -f -- "$dst" || { warn "could not remove $rel"; fail=1; }
		elif [[ -e $st/files/$rel || -L $st/files/$rel ]]; then
			{ mkdir -p -- "$(dirname "$dst")" && cp -a -- "$st/files/$rel" "$dst"; } || { warn "could not restore $rel"; fail=1; }
		fi
	done <"$st/keys"
	_labwc_undo
	_term_font_undo "$st"
	_fm_undo "$st" || { warn "could not restore the file manager's settings"; fail=1; }
	_power_undo "$st" || { warn "could not restore labwc's start file"; fail=1; }
	# The desktop's shortcuts and the start entries that an install moved
	# away (reset_file_manager, reset_power); beside a file of that name that
	# is there now, under a numbered name
	local n d
	for rel in "$st/desktop"/* "$st/autostart"/*; do
		[[ -e $rel || -L $rel ]] || continue
		d=${XDG_CONFIG_HOME:-$HOME/.config}/autostart
		[[ $rel != "$st/desktop"/* ]] || d=$(_desktop_dir)
		dst=$d/${rel##*/} n=1
		while [[ -e $dst || -L $dst ]]; do dst=$d/${rel##*/}.~$n~ n=$(( n + 1 )); done
		{ mkdir -p -- "${dst%/*}" && mv -- "$rel" "$dst"; } || { warn "could not put back ${rel##*/}"; fail=1; }
	done
	if (( fail )); then
		warn "the backup of $(id -un)'s previous settings stays in $st"
		return 0
	fi
	local -a dirs=()
	if [[ -f $st/created-dirs ]]; then   # deepest first
		mapfile -t dirs < <(awk 'NF && !seen[$0]++ { print gsub("/", "/") "\t" $0 }' "$st/created-dirs" | sort -rn | cut -f2-)
	fi
	rm -rf -- "$st"
	for rel in "${dirs[@]}"; do
		if [[ -d $HOME/$rel ]]; then rmdir --ignore-fail-on-non-empty -- "$HOME/$rel"; fi
	done
	ok "Previous settings of $(id -un) restored"
}

###############################################################################
# 9. Refresh: --refresh
###############################################################################

# Print the system and version that a run resolves against.
state_lines() {
	printf 'debian %s\nrelease %s\narch %s\nversion %s\nedition %s\n' "${H_CODENAME:-?}" "$H_SUITE" "$H_ARCH" "$APP_VERSION" "$APP_EDITION"
}

# Stop, before anything changes, when the rpios-look script on this computer
# was installed by the other script (the edition its state names): it is
# uninstalled first, with --uninstall of either script, then this one
# installs. Nothing of the other install is taken over.
require_own_install() {
	local e
	e=$(sed -n 's/^edition //p' "$SYS_DIR/state" 2>/dev/null | first_line) || e=""
	[[ -n $e && $e != "$APP_EDITION" ]] || return 0
	die "the rpios-look script on this computer was installed by $LEGACY_SCRIPT, and nothing was changed. Uninstall it first: bash $LEGACY_SCRIPT --uninstall (or $(self_cmd) --uninstall), then run this again."
}

# --refresh updates the packages of the Raspberry Pi OS release that was
# installed (the release its state names), never another one: a newer
# release comes only with a clean install. When that release is not
# published for this architecture any more, pick_suite's choice stays.
keep_installed_release() {
	local s
	s=$(sed -n 's/^release //p' "$SYS_DIR/state" 2>/dev/null | first_line) || s=""
	[[ $s =~ ^[a-z]+$ && -n ${REL_VER[$s]:-} && $s != "$H_SUITE" ]] || return 0
	(( REL_VER[$s] >= HOST_OLDEST )) || return 0
	rpi_populated "$s" && grep -qxF "$H_ARCH" <<<"$(rpi_arches "$s")" || return 0
	if (( REL_VER[$H_SUITE] > REL_VER[$s] )); then
		note "Raspberry Pi OS $H_SUITE is available for this computer; --refresh keeps $s. To move to $H_SUITE: $(self_cmd) --uninstall, then a clean install: $(self_cmd)"
	fi
	H_SUITE=$s
}

# Save the state that later runs and --refresh compare against.
save_state() { [[ $(cat -- "$SYS_DIR/state" 2>/dev/null) == "$(state_lines)" ]] || state_lines | sys_write "$SYS_DIR/state"; }

# --refresh: list what an update would change, then ask. Exit when there is
# nothing to do or the answer is no; return to apply the update. Nothing is
# changed before the answer.
refresh_check() {
	local p st n=0 line key saved themes="" deb
	for p in "$SYS_ROOT"/usr/share/themes/PiX*/gtk-3.0; do
		p=${p%/gtk-3.0}; p=${p##*/}
		[[ -e $SYS_ROOT/usr/share/themes/$p/gtk-3.0 && $p != *_l ]] && themes+="${themes:+, }$p"
	done
	step "Updates for the Raspberry Pi OS look"
	log "  Checks all ${#FETCH_PKGS[@]} Raspberry Pi OS packages for $H_SUITE/$H_ARCH: every theme"
	log "  (${themes:-none installed yet}) with its icons, fonts and wallpapers,"
	log "  whichever one you use, and Raspberry Pi's programs that the look installs."
	while read -r line; do
		key=${line#?}
		case $line in
			">release "*) log "  + Raspberry Pi OS packages now come from ${key#release }" ;;
			">arch "*)    log "  + Architecture is now ${key#arch }" ;;
			">version "*) log "  + This script is version ${key#version }: the session is written again" ;;
			*) continue ;;
		esac
		n=$(( n + 1 ))
	done < <(diff "$SYS_DIR/state" <(state_lines) 2>/dev/null | sed -n 's/^\([<>]\) /\1/p')
	saved=$(sed -n 's/^size=//p' "$SYS_DIR/options" 2>/dev/null | first_line) || saved=""
	if (( O_SIZE_GIVEN )) && [[ $O_SIZE != "${saved:-medium}" ]]; then
		log "  + Size is now $O_SIZE"
		n=$(( n + 1 ))
	fi
	for p in "${FETCH_PKGS[@]}"; do
		st=$(_pkg_status "$p")
		[[ $st == "up to date" || $st == installed* ]] && continue
		_pkg_line "$p" "${PKG_VER[$p]}" "$st"
		n=$(( n + 1 ))
	done
	for p in "${APT_PKGS[@]}"; do _pkg_line "$p" "(APT)" "not installed"; n=$(( n + 1 )); done
	read_lines STALE_PKGS stale_pkgs
	for p in "${STALE_PKGS[@]}"; do
		_pkg_line "$p" "$(installed_version "$p")" "no longer part of the look for this release"
		n=$(( n + 1 ))
	done
	[[ -n $(installed_version "$APP_PKG") ]] || { log "  + The session package $APP_PKG is missing"; n=$(( n + 1 )); }
	if [[ ! -f $BESIDE_CONF ]]; then log "  + Raspberry Pi's builds of Debian's programs are installed beside Debian's"; n=$(( n + 1 )); fi
	# Debian's updates of the packages this script installed: APT installs them
	deb=$(LC_ALL=C apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | awk '/^Inst / { print $2 }' \
		| grep -xF -f "$SYS_DIR/installed-packages" 2>/dev/null | paste -sd' ' -) || deb=""
	[[ -z $deb ]] || log "  Debian has updates for the session's packages ($deb); 'sudo apt upgrade' installs them."
	log ""
	if (( n == 0 )); then ok "The Raspberry Pi OS look is up to date; nothing to apply."; exit 0; fi
	ask "$n update(s) found. Apply them now" n || { info "Nothing changed."; exit 0; }
}

# Print every package that the given packages depend on, directly or through
# others (Pre-Depends and Depends, each alternative): from Raspberry Pi's
# index for the resolved packages (PKG_DEPS) and from dpkg for installed ones.
# Usage: deps_closure PACKAGE...
deps_closure() {
	local p
	{
		for p in "${!PKG_DEPS[@]}"; do printf '%s\t%s\n' "$p" "${PKG_DEPS[$p]}"; done
		dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\t${Pre-Depends}, ${Depends}\n' 2>/dev/null \
			| awk -F'\t' '$1 ~ /^.i/ { print $2 "\t" $3 }'
	} | ROOTS="$*" awk -F'\t' '
		{ n = split($2, d, /[,|]/); for (i = 1; i <= n; i++) { x = d[i]; sub(/\(.*/, "", x); sub(/:.*/, "", x); gsub(/[ \t]/, "", x); if (x != "") deps[$1] = deps[$1] " " x } }
		END {
			n = split(ENVIRON["ROOTS"], q, " ")
			for (h = 1; h <= n; h++) {
				m = split(deps[q[h]], d, " ")
				for (i = 1; i <= m; i++) if (!(d[i] in seen)) { seen[d[i]] = 1; q[++n] = d[i]; print d[i] }
			}
		}'
}

# Print the packages that this script installed (its record) and that are no
# longer part of the look for this release: installed, outside the install
# set and what it depends on, and either Raspberry Pi OS's (not in the APT
# sources), such as an earlier release's panel, or repacked (BESIDE_PREFIX).
stale_pkgs() {
	local p
	local -a need=()
	read_lines need deps_closure "${FETCH_PKGS[@]}" "${APT_PKGS[@]}"
	while read -r p; do
		# A repacked package (BESIDE_PREFIX) stands for its Raspberry Pi package
		[[ -n $p && $p != "$APP_PKG" && " ${FETCH_PKGS[*]} ${APT_PKGS[*]} ${need[*]} " != *" ${p#"$BESIDE_PREFIX"} "* \
			&& -n $(installed_version "$p") ]] || continue
		grep -qxF -- "$p" "$SYS_DIR/packages-before" 2>/dev/null && continue
		if [[ $p == "$BESIDE_PREFIX"* || -z $(apt_versions "$p") ]]; then echo "$p"; fi
	done < <(cat "$SYS_DIR/installed-packages" 2>/dev/null)
}

# Give every wallpaper setting of the running user that names a Raspberry Pi
# OS wallpaper Debian's default: the desktop-base alternative, which points
# to the artwork of this Debian release; without desktop-base, a plain colour.
# Covers PCManFM, in every profile.
reset_wallpapers() {
	local def=/etc/alternatives/desktop-background f p k
	local rpd="/usr/share/(rpd-wallpaper|${WALLS#/usr/share/})/"
	[[ -e $def ]] || def=""
	for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/pcmanfm/*/desktop-items-*.conf "${XDG_CONFIG_HOME:-$HOME/.config}"/pcmanfm/*/pcmanfm.conf; do
		grep -qE "^wallpaper=$rpd" "$f" 2>/dev/null || continue
		if [[ -n $def ]]; then sed -i -E --follow-symlinks "s#^wallpaper=$rpd.*#wallpaper=$def#" "$f"
		else sed -i -E --follow-symlinks "\#^wallpaper=$rpd#d; s/^wallpaper_mode=.*/wallpaper_mode=color/" "$f"; fi
	done
}

# Purge packages without stopping their running services (the display
# manager, NetworkManager, the sound server): a running desktop or network
# connection stays until the next restart. A policy-rc.d file that denies
# service actions is in place during the purge, unless the system has one.
# Usage: _purge [-q] PACKAGE...
_purge() {
	local pol=/usr/sbin/policy-rc.d rc=0
	if [[ ! -e $pol ]]; then
		# It denies only while the purge holds its lock (/run empties at a
		# restart): left behind, it denies nothing. The lock stays with flock
		# alone (-o), not with a program that APT starts and that runs on
		printf '#!/bin/sh\n# Written by %s while it removes packages\nflock -n %s true 2>/dev/null && exit 0\nexit 101\n' "$APP_NAME" "$PURGE_LOCK" \
			| sys_write "$pol" && as_root chmod 0755 "$pol" && POLICY_RC=$pol
	fi
	as_root flock -o "$PURGE_LOCK" env DEBIAN_FRONTEND=noninteractive apt-get purge "${APT_PURGE[@]}" "$@" || rc=$?
	PURGED=1
	if [[ -n $POLICY_RC ]]; then as_root rm -f -- "$POLICY_RC"; POLICY_RC=""; fi
	return "$rc"
}

# Refresh APT's lists when Raspberry Pi's archive was added to its sources,
# changed there or removed from them (the generated package carries the
# source), so that APT offers at once what its sources name: Raspberry Pi's
# pinned builds, or only Debian's packages again. OLD is the source file's
# content before the change. Usage: apt_lists_sync [OLD]
apt_lists_sync() {
	local lists=0
	! compgen -G "/var/lib/apt/lists/*$(_host "$RPI_ARCHIVE")_*" >/dev/null || lists=1
	if [[ -f $APT_SRC ]]; then
		(( ! lists )) || [[ $(cat -- "$APT_SRC") != "${1:-}" ]] || return 0
		info "Refreshing APT package lists"
		as_root apt-get update -q >/dev/null 2>&1 || warn "apt-get update failed; run 'sudo apt update' before installing Raspberry Pi's builds with APT"
	elif (( lists )); then
		as_root apt-get update -q >/dev/null 2>&1 || true
	fi
}

# Print the part of a package set that APT can purge without removing any
# other package, as APT's simulation shows. Members that other installed
# packages depend on are left out. Return 1, printing nothing, if other
# packages would go only through indirect dependencies; return 2 if the
# simulation fails.
_safe_purge_set() {
	local -a set=("$@") extra=() keep=()
	local sim e
	while (( ${#set[@]} )); do
		sim=$(LC_ALL=C apt-get -s purge "${set[@]}" 2>/dev/null) || return 2
		# A purge that would install another alternative of a member ("a | b"
		# in an installed package's dependencies) keeps that member
		if grep -q '^Inst ' <<<"$sim"; then
			mapfile -t keep < <(dpkg-query -W -f='${Pre-Depends}, ${Depends}\n' 2>/dev/null | tr ',' '\n' | grep -F '|' \
				| INST=$(awk '/^Inst / { sub(/:.*/, "", $2); print $2 }' <<<"$sim" | xargs) SET="${set[*]}" awk '
					BEGIN { n = split(ENVIRON["INST"], a, " "); for (i = 1; i <= n; i++) inst[a[i]] = 1
						n = split(ENVIRON["SET"], a, " "); for (i = 1; i <= n; i++) member[a[i]] = 1 }
					{ m = split($0, g, "|"); hit = 0
						for (i = 1; i <= m; i++) { sub(/\(.*/, "", g[i]); sub(/:.*/, "", g[i]); gsub(/[ \t]/, "", g[i]); if (g[i] in inst) hit = 1 }
						if (hit) for (i = 1; i <= m; i++) if (g[i] in member) print g[i] }' | sort -u)
			(( ${#keep[@]} )) || return 1
			mapfile -t set < <(printf '%s\n' "${set[@]}" | grep -vxF -f <(printf '%s\n' "${keep[@]}") || true)
			continue
		fi
		mapfile -t extra < <(awk '/^(Purg|Remv) / { sub(/:.*/, "", $2); print $2 }' <<<"$sim" \
			| grep -vxF -f <(printf '%s\n' "${set[@]}") || true)
		if (( ${#extra[@]} == 0 )); then printf '%s\n' "${set[@]}"; return 0; fi
		# Leave out the members that those packages depend on, and try again
		mapfile -t keep < <(for e in "${extra[@]}"; do dpkg-query -W -f='${Pre-Depends}, ${Depends}\n' "$e" 2>/dev/null; done \
			| depnames | grep -xF -f <(printf '%s\n' "${set[@]}") || true)
		(( ${#keep[@]} )) || return 1
		mapfile -t set < <(printf '%s\n' "${set[@]}" | grep -vxF -f <(printf '%s\n' "${keep[@]}") || true)
	done
}

###############################################################################
# 10. Uninstall: --uninstall
###############################################################################

# Succeed if this user has settings of the Raspberry Pi Desktop session.
has_session_settings() {
	local f=${XDG_CONFIG_HOME:-$HOME/.config} p
	for p in "$f/lxsession/rpd-x" "$f/lxsession/LXDE-pi" "$f/lxpanel-pi" "$f/pcmanfm/rpd-x" "$f/pcmanfm/LXDE-pi" \
		"$f/openbox/rpd-rc.xml" "$f/openbox/lxde-pi-rc.xml" \
		"$f/lxpanel/rpd-x" "$f/lxpanel/LXDE-pi" "$f/dconf/${APP_NAME//-/}" "$f/menus/rpd-applications.menu" "$f/menus/lxde-pi-applications.menu" \
		"$f/wf-panel-pi" "$f/dconf/${APP_NAME//-/}wayland"; do
		[[ -e $p ]] && return 0
	done
	# A look's window theme in labwc's file, where rpios-look-set wrote it
	grep -qsxF "file:${f#"$HOME"/}/labwc/rc.xml" "$(_st)/keys" && grep -qs '<name>PiX[a-z]*\(_l\)\?</name>' "$f/labwc/rc.xml" && return 0
	# The empty kanshi file that a Wayland login creates, and labwc files
	# left with nothing in them
	[[ -e $f/kanshi/config && ! -s $f/kanshi/config ]] && return 0
	[[ -e $f/labwc/environment && ! -s $f/labwc/environment ]] && return 0
	[[ -f $f/labwc/rc.xml ]] && ! grep -qvE '^[[:space:]]*(<\?xml[^>]*>|</?openbox_config[^>]*>)?[[:space:]]*$' "$f/labwc/rc.xml" && return 0
	grep -qsE "^wallpaper=/usr/share/(rpd-wallpaper|${WALLS#/usr/share/})/" "$f/pcmanfm/default"/desktop-items-*.conf
}

# Copy a labwc file without its <theme> section, also where the section
# starts and ends on one line (also in rpios-look-set, see _session_command)
_strip_theme() {
	awk '!d && /<theme>/ {
			if (/<\/theme>/) { sub(/<theme>.*<\/theme>/, ""); if (NF) print; next }
			d = 1; sub(/<theme>.*/, ""); if (NF) print; next
		}
		d { if (/<\/theme>/) { d = 0; sub(/.*<\/theme>/, ""); if (NF) print } next }
		{ print }'
}

# Print the first <theme> block of a labwc rc.xml, also one written on a
# single line. Usage: _theme_block FILE
_theme_block() {
	awk '!d && /<theme>/ {
			s = $0; sub(/.*<theme>/, "<theme>", s)
			if (s ~ /<\/theme>/) { sub(/<\/theme>.*/, "</theme>", s); print s; exit }
			d = 1; print s; next
		}
		d { if (/<\/theme>/) { s = $0; sub(/<\/theme>.*/, "</theme>", s); print s; exit } print }' "$1" 2>/dev/null || true
}

# In labwc's files of the user's, which Debian's labwc session reads too,
# undo only what rpios-look-set wrote: a look's window theme and cursor give
# way to the user's own, from the record rpios-look-set made before its first
# change; a file left with nothing else in it goes.
_labwc_undo() {
	local f=${XDG_CONFIG_HOME:-$HOME/.config}/labwc st rel block cur
	st=$(_st) rel=${f#"$HOME"/}
	if grep -qxF "file:$rel/rc.xml" "$st/keys" 2>/dev/null && grep -qs '<name>PiX[a-z]*\(_l\)\?</name>' "$f/rc.xml"; then
		block=""
		if [[ -f $st/files/$rel/rc.xml ]]; then block=$(_theme_block "$st/files/$rel/rc.xml"); fi
		# Written through, so that a link stays a link
		{ _strip_theme <"$f/rc.xml" | sed '/^[[:space:]]*<\/openbox_config>[[:space:]]*$/d; s|</openbox_config>||'; [[ -z $block ]] || printf '%s\n' "$block"; echo '</openbox_config>'; } \
			>"$f/rc.xml.new" && cat -- "$f/rc.xml.new" >"$f/rc.xml" && rm -f -- "$f/rc.xml.new"
		if ! grep -qvE '^[[:space:]]*(<\?xml[^>]*>|</?openbox_config[^>]*>)?[[:space:]]*$' "$f/rc.xml"; then rm -f -- "$f/rc.xml"; fi
	fi
	if grep -qxF "file:$rel/environment" "$st/keys" 2>/dev/null && grep -qsE '^XCURSOR_THEME=PiX[a-z]*(-Debian)?$' "$f/environment"; then
		sed -i --follow-symlinks -E '/^XCURSOR_THEME=PiX[a-z]*(-Debian)?$/d' "$f/environment"
		cur=""
		if [[ -f $st/files/$rel/environment ]]; then cur=$(sed -n 's/^XCURSOR_THEME=//p' "$st/files/$rel/environment" | tail -n 1); fi
		if [[ -n $cur ]] && ! grep -q '^XCURSOR_THEME=' "$f/environment"; then printf 'XCURSOR_THEME=%s\n' "$cur" >>"$f/environment"; fi
		[[ -s $f/environment ]] || rm -f -- "$f/environment"
	fi
	# Undone: the next change records the files as they are then
	if [[ -f $st/keys ]]; then
		sed -i -E "\\#^file:$rel/(rc\\.xml|environment)\$#d" "$st/keys"
		sed -i -E "\\#^$rel/(rc\\.xml|environment)\$#d" "$st/created" 2>/dev/null || true
		rm -f -- "$st/files/$rel/rc.xml" "$st/files/$rel/environment"
	fi
}

# In LXTerminal's settings of the user's, which Debian's LXTerminal reads
# too, put back only the font that term_font set: the file's own as it was,
# else the terminal's default. A file the install made goes if it holds
# nothing else. Usage: _term_font_undo STATE_DIR
_term_font_undo() {
	local st=$1 f=${XDG_CONFIG_HOME:-$HOME/.config}/lxterminal/lxterminal.conf sys=$SYS_ROOT/usr/share/lxterminal/lxterminal.conf rel font=""
	rel=${f#"$HOME"/}
	grep -qxF "file:$rel" "$st/keys" 2>/dev/null && [[ -f $f ]] || return 0
	# A font chosen since stays
	[[ $(sed -n 's/^fontname=//p' "$f" | first_line) == "$(sed -n 's/^termfont://p' "$st/keys" | tail -n 1)" ]] || return 0
	if [[ -f $st/files/$rel ]]; then font=$(sed -n 's/^fontname=//p' "$st/files/$rel" | first_line); fi
	if [[ -z $font && -f $sys ]]; then font=$(sed -n 's/^fontname=//p' "$sys" | first_line); fi
	[[ -z $font ]] || _ini_set "$f" general fontname "$font"
	if grep -qxF "$rel" "$st/created" 2>/dev/null && { [[ ! -f $sys ]] || cmp -s -- "$f" "$sys"; }; then rm -f -- "$f"; fi
}

# Put the file manager's settings of this user back to the session's, on an
# install (not on --refresh). Raspberry Pi's own file manager keeps its
# preferences, the desktop's and the desktop icons' places in the 'default'
# profile, which Debian's file manager reads only outside LXDE: those files
# go. Otherwise the session's file manager keeps part of its preferences in
# libfm.conf, which Debian's LXDE reads too: there only the values the
# session sets go back to its own. The side pane's bookmarks and the
# desktop's shortcuts go too. All of it is recorded first, so --uninstall
# gives back what was there. The user's other files and folders, the
# desktop's among them, are not touched. Usage: reset_file_manager
reset_file_manager() {
	local f=${XDG_CONFIG_HOME:-$HOME/.config} p old add n=0
	if (( ${S_PI_FM:-0} )) && [[ ${S_FM_PROFILE:-$S_PROFILE} == default ]]; then
		# The desktop's file of each monitor, also of one not there yet: one
		# that the session writes later is then not taken for the user's own
		for p in pcmanfm.conf desktop-items-{0..5}.conf; do
			_track_file "$f/pcmanfm/default/$p"
			rm -f -- "$f/pcmanfm/default/$p"
		done
	elif [[ -f $f/libfm/libfm.conf ]]; then
		_fm_shared_conf "$f/libfm/libfm.conf"
		# The values as written: --uninstall undoes only those (_fm_undo)
		cp -- "$f/libfm/libfm.conf" "$A_STATE/libfm-written"
	fi
	# The bookmarks of the file manager's side pane (GTK's, which the file
	# dialogs of every session show too). On a later install those added
	# since join the ones kept from before
	for p in "$f/gtk-3.0/bookmarks" "$HOME/.gtk-bookmarks"; do
		old=$A_STATE/files/${p#"$HOME"/}
		if [[ -f $p ]] && grep -qxF "file:${p#"$HOME"/}" "$A_STATE/keys"; then
			mkdir -p "${old%/*}" && touch "$old"
			[[ -z $(tail -c 1 -- "$old") ]] || echo >>"$old"
			add=$(grep -vxF -f "$old" -- "$p" || true)
			[[ -z $add ]] || printf '%s\n' "$add" >>"$old"
		fi
		_track_file "$p"
		rm -f -- "$p"
	done
	# Raspberry Pi OS puts no shortcut on the desktop: its Trash and drive
	# icons are settings. Launchers and links there are moved into the state
	# directory, and --uninstall moves them back; the desktop's other files
	# and folders stay
	for p in "$(_desktop_dir)"/*; do
		[[ -L $p || ( -f $p && $p == *.desktop ) ]] || continue
		if mkdir -p "$A_STATE/desktop" && mv --backup=numbered -- "$p" "$A_STATE/desktop/"; then
			n=$(( n + 1 ))
		else
			warn "could not move ${p##*/} off the desktop; it stays"
		fi
	done
	ok "The file manager and the desktop are back to the defaults"
	(( ! n )) || info "$n shortcuts on the desktop were moved to $A_STATE/desktop; --uninstall puts them back"
}

# Set aside, on an install (not on --refresh), this user's own power settings
# for the session, which Raspberry Pi OS does not have (the README's "Your
# own power settings"): the start entries power-times and light-locker (one
# that only hides light-locker is Debian's LXDE's own and stays) and the
# swayidle commands in labwc's start file, each with the lines it goes on
# over. They are kept in the state directory, and --uninstall puts them
# back. The lid and power button settings of systemd-logind are the whole
# computer's and stay.
# Usage: reset_power
reset_power() {
	local f=${XDG_CONFIG_HOME:-$HOME/.config} p n=0 old new
	for p in "$f/autostart/power-times.desktop" "$f/autostart/light-locker.desktop"; do
		[[ -f $p ]] || continue
		if [[ $p == */light-locker.desktop ]] && grep -qix 'Hidden=true' "$p"; then continue; fi
		if mkdir -p "$A_STATE/autostart" && mv --backup=numbered -- "$p" "$A_STATE/autostart/"; then
			n=$(( n + 1 ))
		else
			warn "could not move ${p##*/} out of your start entries; it stays"
		fi
	done
	# The Wayland session's idle line in labwc's start file, which Debian's
	# labwc session runs too: only the swayidle commands go, with the lines
	# that one goes on over (a line that ends in a backslash)
	p=$f/labwc/autostart old=$A_STATE/files/${p#"$HOME"/}
	if [[ -f $p && -n $(_swayidle_cmds /dev/null "$p") ]]; then
		[[ -f $old ]] || { mkdir -p "${old%/*}" && : >"$old"; }
		# One kept already, from an earlier install, is not kept twice
		new=$(_swayidle_cmds "$old" "$p")
		[[ -z $new ]] || printf '%s\n' "$new" >>"$old"
		_swayidle_cmds "$p" | _write "$p"
		[[ -s $p ]] || rm -f -- "$p"
		n=$(( n + 1 ))
	fi
	(( ! n )) || ok "Your own power settings for the session are set aside; --uninstall puts them back"
}

# Undo, at --uninstall, what an install changed in the files that other
# sessions read too (reset_file_manager). libfm.conf: the values the install
# wrote, where they are still there, give way to those from before; your
# changes since stay. GTK's bookmarks: those from before the install come
# back beside the ones added since. Usage: _fm_undo STATE-DIR
_fm_undo() {
	local st=$1 f=${XDG_CONFIG_HOME:-$HOME/.config} p old add rc=0
	p=$f/libfm/libfm.conf old=$st/files/${p#"$HOME"/}
	if [[ -f $st/libfm-written && -s $old && -f $p ]]; then
		awk 'function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
			FNR == 1 { sec = ""; n++ }
			/^[ \t]*\[.*\][ \t]*$/ { sec = trim($0); if (n == 3) print; next }
			{
				i = index($0, "="); k = sec SUBSEP trim(substr($0, 1, i - 1)); v = substr($0, i + 1)
				if (n == 1) { if (i) { old[k] = v; has[k] = 1 }; next }
				if (n == 2) { if (i) wr[k] = v; next }
				# A value the install wrote and that differs from the one before
				if (i && (k in wr) && v == wr[k] && !(has[k] && old[k] == v)) {
					if (has[k]) print substr($0, 1, i) old[k]
					next
				}
				print
			}' "$old" "$st/libfm-written" "$p" | _write "$p" || rc=1
	fi
	for p in "$f/gtk-3.0/bookmarks" "$HOME/.gtk-bookmarks"; do
		old=$st/files/${p#"$HOME"/}
		[[ -f $old ]] || continue
		if [[ -s $p ]]; then
			[[ -z $(tail -c 1 -- "$p") ]] || echo >>"$p"
			add=$(grep -vxF -f "$p" -- "$old" | awk '!seen[$0]++' || true)
			[[ -z $add ]] || printf '%s\n' "$add" >>"$p"
		else
			{ mkdir -p -- "${p%/*}" && cp -a -- "$old" "$p"; } || rc=1
		fi
	done
	return $rc
}

# Print the swayidle commands of labwc's start file NEW that are not in the
# start file HAVE, each whole: a command goes on over the lines that end in
# a backslash; two that differ only in the spaces their lines begin with are
# one. With one file, print that file without its swayidle commands.
# Usage: _swayidle_cmds HAVE NEW | _swayidle_cmds FILE
_swayidle_cmds() {
	awk -v rest=$(( $# == 1 )) 'function end() { if (b != "" && !(k in seen)) { seen[k] = 1; if (src != ARGV[1]) printf "%s", b }; b = k = ""; more = 0 }
		FNR == 1 { end() }
		more || /^[ \t]*swayidle([ \t&]|$)/ { if (b == "") src = FILENAME; b = b $0 "\n"; l = $0; sub(/^[ \t]+/, "", l); k = k l "\n"; more = /\\$/; if (!more) end(); next }
		rest
		END { end() }' "$@"
}

# Put back, at --uninstall, the swayidle commands that an install took out of
# labwc's start file (reset_power): after what is there now, each one unless
# it is there already. Usage: _power_undo STATE-DIR
_power_undo() {
	local st=$1 p=${XDG_CONFIG_HOME:-$HOME/.config}/labwc/autostart old add
	old=$st/files/${p#"$HOME"/}
	[[ -f $old ]] || return 0
	if [[ -s $p ]]; then
		add=$(_swayidle_cmds "$p" "$old")
		[[ -n $add ]] || return 0
		[[ -z $(tail -c 1 -- "$p") ]] || echo >>"$p"
		printf '%s\n' "$add" >>"$p"
	else
		mkdir -p -- "${p%/*}" && cp -a -- "$old" "$p"
	fi
}

# Print the user's desktop folder.
_desktop_dir() {
	local d
	d=$(xdg-user-dir DESKTOP 2>/dev/null) || d=""
	[[ -n $d && $d != "$HOME" && $d != "$HOME/" ]] || d=${XDG_DESKTOP_DIR:-$HOME/Desktop}
	printf '%s\n' "$d"
}

# Remove this user's settings of the Raspberry Pi Desktop session, which no
# other session reads: theme, wallpaper, panel and window manager. The files the session changed outside them are
# given back. A clean install and --uninstall start from the defaults.
reset_session_settings() {
	local f d p k
	has_session_settings || return 0
	f=${XDG_CONFIG_HOME:-$HOME/.config}
	d=${XDG_DATA_HOME:-$HOME/.local/share}
	rm -f -- "$f/openbox/rpd-rc.xml" "$f/openbox/lxde-pi-rc.xml" "$f/menus/rpd-applications.menu" "$f/menus/lxde-pi-applications.menu"
	rm -rf -- "$f/lxsession/rpd-x" "$f/lxsession/LXDE-pi" "$f/lxpanel/rpd-x" "$f/lxpanel/LXDE-pi" "$f/lxpanel-pi" \
		"$f/pcmanfm/rpd-x" "$f/pcmanfm/LXDE-pi"
	# Debian's file manager reads its default profile in other sessions too:
	# only the desktop files with a Raspberry Pi OS wallpaper are the session's
	for p in "$f/pcmanfm/default"/desktop-items-*.conf; do
		if grep -qE "^wallpaper=/usr/share/(rpd-wallpaper|${WALLS#/usr/share/})/" "$p" 2>/dev/null; then rm -f -- "$p"; fi
	done
	# The session's own GSettings databases (X and Wayland)
	rm -f -- "$f/dconf/${APP_NAME//-/}" "$f/dconf/${APP_NAME//-/}wayland"
	# The Wayland session: Raspberry Pi's panel settings (only it reads them);
	# in labwc's files, which Debian's labwc session reads too, only what
	# rpios-look-set wrote there: the window theme and the cursor of a look
	rm -rf -- "$f/wf-panel-pi"
	_labwc_undo
	# kanshi's file that the Wayland session creates empty, if still empty
	[[ -s $f/kanshi/config || ! -e $f/kanshi/config ]] || rm -f -- "$f/kanshi/config"
	# Folders the session left empty; rmdir keeps folders with content
	rmdir -- "$f/pcmanfm/default" "$f/pcmanfm" "$f/dconf" "$f/lxpanel" "$f/menus" "$f/labwc" "$f/kanshi" \
		"$f/lxsession" "$f/openbox" "$d/desktop-directories" "$d/flatpak/db" "$d/flatpak" 2>/dev/null || true
}

# Purge the given packages that the script installed, as far as APT can
# without removing other packages, except dependencies that you have since
# installed by name; the others that stay are marked as automatically
# installed, so that 'apt autoremove' removes them once nothing needs them.
# Usage: _remove_recorded PACKAGE...
_remove_recorded() {
	local p why="other installed software needs them"
	local -a remove=() keep=() mine=() set=()
	# A dependency that you have since installed by name (apt install) is
	# yours, for a program APT does not know of: it stays as it is
	mapfile -t mine < <(apt-mark showmanual "$@" 2>/dev/null | grep -xF -f <(cat "$SYS_DIR/installed-auto" 2>/dev/null) || true)
	for p; do [[ " ${mine[*]} " == *" $p "* ]] || set+=("$p"); done
	(( ${#mine[@]} == 0 )) || info "Kept, because you installed them by name: ${mine[*]}"
	(( ${#set[@]} )) || return 0
	if _safe_purge_set "${set[@]}" >"$WORKDIR/purge-set"; then
		mapfile -t remove <"$WORKDIR/purge-set"
	else
		case $? in
			1) why="APT would also remove other packages with them" ;;
			*) why="APT could not work out what removing them would remove" ;;
		esac
	fi
	for p in "${set[@]}"; do [[ " ${remove[*]} " == *" $p "* ]] || keep+=("$p"); done
	if (( ${#remove[@]} )); then _purge "${remove[@]}"; fi
	if (( ${#keep[@]} )); then
		as_root apt-mark auto "${keep[@]}" >/dev/null
		info "Kept, because $why: ${keep[*]}"
		[[ $why == other* ]] || info "None of them was removed; later, 'sudo apt autoremove' removes those that nothing needs"
	fi
}

# Put wicd's Wi-Fi interface setting, which rpios-look-legacy.sh may have set
# (record wicd-interface), back to None, unless it was changed since. wicd is
# stopped meanwhile, so that it does not write its own value back.
wicd_restore() {
	local f=$SYS_DIR/wicd-interface new was=0
	[[ -f $f ]] || return 0
	new=$(sed -n 's/^new=//p' "$f" | first_line)
	step "Restoring wicd's Wi-Fi setting"
	if [[ $(sed -n 's/^old=//p' "$f" | first_line) != None || ! $new =~ ^[A-Za-z0-9_-]+$ ]] \
		|| ! grep -qxF "wireless_interface = $new" "$WICD_CONF" 2>/dev/null; then
		info "wicd's Wi-Fi interface setting was changed since the install; it stays"
	elif [[ ! -d /run/systemd/system ]]; then
		note "wicd's Wi-Fi interface setting stays $new: with wicd stopped, set wireless_interface = None in $WICD_CONF"
	else
		systemctl is-active --quiet wicd.service && was=1
		if { (( ! was )) || as_root systemctl stop wicd.service; } \
			&& as_root sed -i "s/^wireless_interface = $new\$/wireless_interface = None/" "$WICD_CONF"; then
			ok "wicd's Wi-Fi interface setting is None again"
		else
			warn "wicd's Wi-Fi interface setting could not be put back; it stays $new"
		fi
		(( ! was )) || as_root systemctl start wicd.service || true
	fi
	as_root rm -f -- "$f"
}

# Succeed if the look is installed, or a run left records of what it changed:
# anything in SYS_DIR, or the generated package.
look_installed() { [[ -n $(ls -A "$SYS_DIR" 2>/dev/null) || -n $(installed_version "$APP_PKG") ]]; }

# --uninstall: undo what the script did. For everyone: the session, the login
# screen, the generated package and the packages it installed. For the user
# running it: the settings it changed. Packages that were installed before, or
# that other software now needs, stay.
uninstall() {
	local p f u m v prev kind was=0
	local -a pkgs=() keep=()
	# The look itself, or only the record of packages an earlier uninstall kept
	if [[ -f $SYS_DIR/state || -n $(installed_version "$APP_PKG") ]]; then was=1; fi
	if [[ -f $SYS_DIR/installed-packages ]]; then mapfile -t pkgs <"$SYS_DIR/installed-packages"; fi
	if [[ -f $SYS_DIR/hardware-packages ]]; then mapfile -t -O "${#pkgs[@]}" pkgs <"$SYS_DIR/hardware-packages"; fi
	# And those of an APT run that did not finish
	mapfile -t -O "${#pkgs[@]}" pkgs < <(_installing_new)
	for p in "${pkgs[@]}"; do
		[[ -n $(installed_version "$p") ]] || continue
		grep -qxF "$p" "$SYS_DIR/packages-before" 2>/dev/null && continue
		keep+=("$p")
	done
	pkgs=("${keep[@]}")
	step "What the uninstall removes"
	if (( was )); then log "  For everyone: the Raspberry Pi Desktop session, the login screen style and $APP_PKG"
	else log "  The look itself is uninstalled already; what an earlier uninstall kept is offered again"; fi
	(( ${#pkgs[@]} )) && log "  Packages this script installed, hardware support included: ${pkgs[*]}"
	[[ ! -f $SYS_DIR/wicd-interface ]] || log "  wicd's Wi-Fi interface setting: None again, if it is still the one the install set"
	log "  For $(id -un): the settings it changed and your Raspberry Pi Desktop settings; other users keep theirs."
	log "  Packages you had before or installed by name since, and those software you installed later needs, stay."
	if printf '%s\n' "${pkgs[@]}" | grep -qxE "$NET_PKGS_RE"; then
		log "  The network and Bluetooth tools it added go, so that your network setup from before the install comes back."
	fi
	log "  Running services (login screen, network, sound) stop at the next restart."
	ask "Continue" n || die "aborted"
	prepare_root
	take_run_lock
	require_dpkg_ready

	step "Restoring the login screen and the users' session choice"
	# Users who chose the session get the login screen's default session
	for f in $(sudo sh -c "grep -lE '^X?Session=($SESSION_ID|$WL_SESSION_ID)\$' /var/lib/AccountsService/users/*" 2>/dev/null); do
		u=$(id -u "${f##*/}" 2>/dev/null) || continue
		prev=""
		for m in XSession Session; do
			# The session chosen before the install, else the login screen's default
			v=$(awk -F'\t' -v u="${f##*/}" -v m="$m" '$1 == u && $2 == m { print $3; exit }' "$SYS_DIR/session-before" 2>/dev/null || true)
			sudo grep -qE "^$m=($SESSION_ID|$WL_SESSION_ID)\$" "$f" && as_root busctl call org.freedesktop.Accounts \
				"/org/freedesktop/Accounts/User$u" org.freedesktop.Accounts.User "Set$m" s "$v" >/dev/null 2>&1 || true
			[[ -z $v ]] || prev=$v
		done
		if [[ -n $prev ]]; then ok "${f##*/} logs in to $prev again"; else ok "${f##*/} logs in to the login screen's default session again"; fi
	done
	# LightDM's own record of the users' session choice, used without AccountsService
	for f in $(sudo sh -c "grep -lE '^Session=($SESSION_ID|$WL_SESSION_ID)\$' /var/cache/lightdm/dmrc/*.dmrc" 2>/dev/null); do
		as_root rm -f -- "$f"
		ok "$(basename "$f" .dmrc) logs in to the login screen's default session again"
	done

	# This user's files: those this script backed up, and the files the
	# session wrote that are unchanged
	step "Restoring the settings of $(id -un)"
	restore_user
	forget_dmrc
	reset_session_settings
	rm -rf -- "${XDG_CACHE_HOME:-$HOME/.cache}/$APP_NAME"

	wicd_restore
	step "Removing packages"
	if [[ -n $(installed_version "$APP_PKG") ]]; then
		_purge -q "$APP_PKG" >/dev/null
		ok "Removed the Raspberry Pi Desktop session ($APP_PKG)"
	fi
	apt_lists_sync
	# Raspberry Pi's packages repacked beside Debian's serve this session
	# only, and go with it
	mapfile -t keep < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "$BESIDE_PREFIX*" 2>/dev/null \
		| awk -v s="$APP_PKG" '$1 ~ /^.i/ && $2 != s { print $2 }')
	if (( ${#keep[@]} )); then
		_purge -q "${keep[@]}" >/dev/null || die "APT could not remove ${keep[*]}"
		ok "Removed Raspberry Pi's programs repacked beside Debian's: ${keep[*]}"
	fi
	as_root rm -f -- "$BESIDE_CONF" "$SYS_DIR/look-packages"
	# Those that went with the repacked packages are left out. Wi-Fi firmware
	# is asked about apart, as removing it cuts Wi-Fi; the network and
	# Bluetooth tools go whether or not the others do.
	local -a fw=() net=() recorded=("${pkgs[@]}")
	keep=()
	for p in "${pkgs[@]}"; do
		[[ -n $(installed_version "$p") ]] || continue
		if [[ $p == firmware-* ]]; then fw+=("$p")
		elif [[ $p =~ ^($NET_PKGS_RE)$ ]]; then net+=("$p")
		else keep+=("$p"); fi
	done
	pkgs=("${keep[@]}")
	# APT still needs apt-transport-https (Debian 9) for an https source of yours
	if [[ " ${pkgs[*]} " == *" apt-transport-https "* ]] && grep -qsE '^[^#]*https://' /etc/apt/sources.list /etc/apt/sources.list.d/*; then
		info "Kept apt-transport-https: your APT sources use https"
		mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vx apt-transport-https)
	fi
	(( ${#pkgs[@]} )) && ask "Also remove the ${#pkgs[@]} packages this script installed" y || pkgs=()
	# The network setup from before the install comes back (the tools that
	# other software needs stay); in one APT run with the packages above, so
	# that what only the tools need goes too
	(( ${#net[@]} == 0 )) || info "Removing the network and Bluetooth tools the install added (${net[*]}): the network setup from before the install is back after the restart"
	(( ${#pkgs[@]} + ${#net[@]} == 0 )) || _remove_recorded "${pkgs[@]}" "${net[@]}"
	if (( ${#fw[@]} )) && ask "Also remove the Wi-Fi firmware installed for this computer (${fw[*]}); Wi-Fi may stop working" n; then
		_remove_recorded "${fw[@]}"
	fi
	# What stays of them stays recorded, so that a later --uninstall offers it
	# again: kept, or needed by other software
	mapfile -t pkgs < <(for p in "${recorded[@]}"; do [[ -z $(installed_version "$p") ]] || echo "$p"; done)
	# Icon caches left in icon set folders that no package owns any more
	for f in PiXflat PiXtrix PiX; do
		f=/usr/share/icons/$f
		[[ -d $f && $(ls -A "$f") == icon-theme.cache ]] && ! dpkg -S "$f" >/dev/null 2>&1 && as_root rm -rf -- "$f"
	done
	# The font folders in which only fontconfig's .uuid file is left
	for f in /usr/share/fonts/truetype/piboto /usr/share/fonts/truetype/nunito-sans; do
		[[ -d $f && $(ls -A "$f") == .uuid ]] && ! dpkg -S "$f" >/dev/null 2>&1 && as_root rm -rf -- "$f"
	done
	# Wallpapers that still name the removed Raspberry Pi OS wallpapers get
	# Debian's default for this release, as desktop-base names it
	reset_wallpapers
	# The system users and groups the install created, once no installed
	# package declares them (systemd-sysusers, maintainer scripts) and no
	# process runs as them; users first, then their groups
	while IFS=: read -r kind u; do
		[[ $u =~ ^[a-z_][a-z0-9_-]*$ ]] || continue
		grep -qsw -- "$u" /usr/lib/sysusers.d/*.conf /etc/sysusers.d/*.conf \
			/var/lib/dpkg/info/*.preinst /var/lib/dpkg/info/*.postinst && continue
		case $kind in
			user)  getent passwd "$u" >/dev/null && ! pgrep -u "$u" >/dev/null && as_root userdel "$u" 2>/dev/null || true ;;
			group) getent group "$u" >/dev/null && as_root groupdel "$u" 2>/dev/null || true ;;
		esac
	done < <(sort -r "$SYS_DIR/accounts-new" 2>/dev/null || true)
	# The AccountsService files the install created for its user: the session
	# lines go, and the file goes only when nothing else was set in it since
	# (the service's own lines for every user count as nothing)
	while IFS= read -r u; do
		[[ $u =~ ^[a-z_][a-z0-9_.-]*$ ]] || continue
		f=/var/lib/AccountsService/users/$u
		as_root sed -i -E '/^X?Session=/d' "$f" 2>/dev/null || continue
		as_root grep -qvE '^(\[User\]|SystemAccount=false|Icon=.*/\.face|[A-Za-z]+=)?[[:space:]]*$' "$f" || as_root rm -f -- "$f"
	done < <(cat "$SYS_DIR/accounts-created" 2>/dev/null || true)
	if [[ -z $(installed_version accountsservice) ]]; then
		as_root rmdir /var/lib/AccountsService/users /var/lib/AccountsService 2>/dev/null || true
	fi
	if (( ${#pkgs[@]} == 0 )); then
		as_root rm -rf -- "$SYS_DIR"
	else
		# The packages kept stay recorded, for a later --uninstall of either
		# script; the install's other records go, so that either script can
		# install again
		printf '%s\n' "${pkgs[@]}" | sys_write "$SYS_DIR/installed-packages"
		as_root find "$SYS_DIR" -mindepth 1 -maxdepth 1 ! -name packages-before ! -name installed-packages \
			! -name installed-auto -exec rm -rf -- {} +
	fi
	log ""
	ok "${C_B}Uninstalled.${C_0} Debian's own setup is back."
	if [[ -n $LOG_FILE ]]; then info "Log of this run: $LOG_FILE"; fi
	# Only kept packages were left and none was removed: nothing to restart for
	(( was || PURGED )) || return 0
	finish "Restart the computer to finish (the login screen and running services change at the restart)."
	offer_reboot auto "the login screen and running services change with it"
}

###############################################################################
# 11. Main: modes, run log, summary
###############################################################################

# Print the help: the header comment from "Usage" to the next "# ====" line.
usage() {
	local f=${BASH_SOURCE[0]:-}
	if [[ -f $f ]]; then sed -n '/^# Usage/,/^# ====/{/^# ====/q;s/^# \{0,1\}//;p}' "$f"
	else echo "Usage: bash $APP_NAME.sh [--refresh | --uninstall | --help]"; fi
}

# Parse the command line into the O_* options. A mode may appear anywhere.
parse_args() {
	local opt val eq mode=""
	while (( $# )); do
		opt=$1 eq=0
		# --option=value is read as --option value; eq marks it until the
		# option takes the value
		if [[ $opt == --*=* ]]; then val=${opt#*=}; opt=${opt%%=*}; set -- "$opt" "$val" "${@:2}"; eq=1; fi
		case $opt in
			--refresh|--uninstall)
				[[ -z $mode || $mode == "${opt#--}" ]] || die "give only one of --refresh and --uninstall"
				mode=${opt#--} ;;
			--size)           (( $# >= 2 )) || die "$opt needs a value"
				size_ok "${2,,}" || die "unknown size '$2' (small, medium, large or larger)"
				O_SIZE=${2,,} O_SIZE_GIVEN=1; shift; eq=0 ;;
			-v|--verbose)     O_VERBOSE=1 ;;
			--no-reboot)      O_NO_REBOOT=1 ;;
			-h|--help)        usage; exit 0 ;;
			-V|--version)     echo "$APP_NAME $APP_VERSION"; exit 0 ;;
			--download|--offline) die "$(self_cmd) installs online only; offline installs are in $LEGACY_SCRIPT (Debian 9 to 12)" ;;
			*) die "unknown argument '$opt'; see: $(self_cmd) --help" ;;
		esac
		(( ! eq )) || die "$opt takes no value"
		shift
	done
	O_MODE=${mode:-install}
	if { : </dev/tty; } 2>/dev/null; then O_INTERACTIVE=1; fi
}

# Copy everything this run prints to a log in the home folder, named after
# the mode (rpios-look-install-DATE-TIME.log), after a header that describes
# the system. Only the newest ten logs of each mode are kept.
start_log() {
	local log
	printf -v log '%s/%s-%s-%(%Y%m%d-%H%M%S)T.log' "$HOME" "$APP_NAME" "$O_MODE" -1
	{ : >>"$log"; } 2>/dev/null || return 0
	# shellcheck disable=SC2012
	ls -1t "$HOME/$APP_NAME-$O_MODE"-*.log 2>/dev/null | tail -n +11 | xargs -r -d '\n' rm -f --
	{
		printf '===== %s %s, %s =====\n' "$APP_NAME" "$APP_VERSION" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
		printf 'Command:  %s %s\n' "$0" "$(_q "${ARGV[@]}")"
		printf 'System:   %s (%s), %s\n' "${H_PRETTY:-unknown}" "${H_CODENAME:-?}" "$H_ARCH"
		printf 'User:     %s (uid %s)\n' "$(id -un)" "$(id -u)"
		printf 'Session:  %s (XDG_CURRENT_DESKTOP=%s, display %s)\n' "${DESKTOP_SESSION:-none}" \
			"${XDG_CURRENT_DESKTOP:-}" "${DISPLAY:-none}"
		printf 'Packages: %s\n' "$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}=${Version}\n' lxsession openbox \
			lxpanel lxpanel-pi pcmanfm pcmanfm-pi lightdm lightdm-gtk-greeter "$APP_PKG" 2>/dev/null \
			| awk '$1 ~ /^.i/ { print $2 }' | paste -sd' ' -)"
	} >>"$log"
	# Each line is logged with the date and time, without colour codes
	exec > >(tee -a >(sed -u 's/\x1b\[[0-9;]*m//g' \
		| while IFS= read -r line; do printf '%(%Y-%m-%d %H:%M:%S)T  %s\n' -1 "$line"; done >>"$log")) 2>&1
	LOG_FILE=$log
}

# Remove temporary files on exit.
cleanup() {
	if [[ -n $POLICY_RC ]]; then sudo rm -f -- "$POLICY_RC" || true; fi
	if [[ -n $WORKDIR && -d $WORKDIR ]]; then rm -rf -- "$WORKDIR"; fi
}

# Print the GTK theme that this user chose for the session (rpios-look-set,
# Customize Look and Feel), if it differs from the session's; print nothing else.
# Such a choice lives in the user's own files and survives an update.
user_theme() {
	local f t
	f=${XDG_CONFIG_HOME:-$HOME/.config}/lxsession/$SESSION_PROFILE/desktop.conf
	t=$(sed -n 's/^sNet\/ThemeName=//p' "$f" 2>/dev/null | first_line) || t=""
	[[ -z $t || $t == "$T_GTK" ]] || printf '%s\n' "$t"
}

# Summarise what an install will do.
print_plan() {
	local p st total=0
	local -A status=()
	for p in "${FETCH_PKGS[@]}"; do
		st=$(_pkg_status "$p") status[$p]=$st
		[[ $st == "up to date" || $st == installed* ]] || total=$(( total + ${PKG_SIZE[$p]:-0} ))
	done
	step "Plan"
	log "  Looks        every theme; the session uses ${T_DESC%% —*} (change it with: $APP_NAME-set --theme NAME)"
	if has_session_settings; then
		log "  Clean        $(id -un)'s Raspberry Pi Desktop settings (theme, wallpaper, panel)"
		log "               go back to the defaults; to update and keep them: $(self_cmd) --refresh"
	fi
	if [[ ${O_MODE:-} != refresh ]]; then
		log "  Reset        $(id -un)'s file manager and desktop preferences go back to the defaults;"
		log "               the file manager's bookmarks and the desktop's shortcuts (launchers and"
		log "               links) are removed; your own power settings for the session are set"
		log "               aside; files and folders stay; --uninstall puts all of it back"
	fi
	log "  Session      Raspberry Pi Desktop (X, Openbox), on the login screen for every user"
	(( ! WAYLAND )) || log "               Raspberry Pi Desktop (Wayland, labwc) beside it, to pick on the login screen"
	log "  Packages     from $RPI_ARCHIVE ($H_SUITE, $H_ARCH), up to $(human_size "$total") to download"
	for p in "${FETCH_PKGS[@]}"; do _pkg_line "$p" "${PKG_VER[$p]}" "${status[$p]}"; done
	for p in "${APT_PKGS[@]}"; do _pkg_line "$p" "(APT)" "new, from your Debian sources"; done
	if (( ${#TWINS[@]} )); then
		log "  Beside       Raspberry Pi's builds of ${TWINS[*]} are repacked to install"
		log "               beside Debian's packages ($BESIDE_PREFIX*), for this session only."
	fi
	log "  Debian's own packages, sessions and your settings in them are not changed."
}

# Print the closing summary.
summary() {
	local n own
	log ""
	if (( ${#NOTES[@]} )); then
		warn "Not done or worth knowing:"
		for n in "${NOTES[@]}"; do log "   - $n"; done
	fi
	if [[ $O_MODE == refresh ]]; then
		ok "${C_B}Updated.${C_0} Your Raspberry Pi Desktop settings are kept."
	else
		ok "${C_B}Installed.${C_0} $T_DESC is the look of the Raspberry Pi Desktop session."
	fi
	own=$(user_theme)
	if [[ -n $own ]]; then
		info "Your theme ($own) and wallpaper stay; every theme was updated. To go back to this release's default (${T_DESC%% —*}): $APP_NAME-set --reset"
	fi
	if [[ $O_MODE != refresh ]]; then
		finish "Restart the computer to finish; the login screen then offers ${C_B}Raspberry Pi Desktop${C_0} (chosen for you). Other sessions stay as they were."
		if (( WAYLAND )); then
			info "Raspberry Pi Desktop (X) is your session; ${C_B}Raspberry Pi Desktop (Wayland)${C_0} is on the login screen to try. The one you pick is remembered."
		fi
	elif [[ -n $REBOOT_WHY ]]; then
		finish "Restart the computer to finish ($REBOOT_WHY)."
	elif [[ ${XDG_SESSION_DESKTOP:-} == "$SESSION_ID" ]] || _in_wl_session; then
		finish "Log out and back in to finish: the session starts again with the new settings."
	else
		finish "Log out and choose ${C_B}Raspberry Pi Desktop${C_0} on the login screen to use it; other sessions stay as they were."
	fi
	info "Updates: $(self_cmd) --refresh    Clean install: $(self_cmd)    Undo: $(self_cmd) --uninstall"
	info "Before a Debian release upgrade: $(self_cmd) --uninstall; after it, a clean install"
	if [[ -n $LOG_FILE ]]; then info "Log of this run: $LOG_FILE"; fi
	# An install restarts the computer by itself after a countdown; an
	# update asks, when what it changed keeps running across a logout
	if [[ $O_MODE != refresh ]]; then
		offer_reboot auto "the login screen and the new session start with it"
	elif [[ -n $REBOOT_WHY ]]; then
		offer_reboot ask "$REBOOT_WHY"
	fi
}

# Print what the user has to do to finish, so that it stands out at the end.
# Usage: finish TEXT
finish() { log ""; log "${C_B}  ==> Next: $*${C_0}"; log ""; }

# Install, update or refresh the look.
install_mode() {
	local before src
	if [[ $O_MODE == refresh ]]; then
		[[ -f $SYS_DIR/state || -n $(installed_version "$APP_PKG") ]] \
			|| die "the Raspberry Pi OS look is not installed; install it with: $(self_cmd)"
	fi
	print_machine
	require_lxde
	set_theme "$DEFAULT_THEME"
	info "Administrator rights are needed (sudo)"
	prepare_root
	resolve_all
	if [[ $O_MODE == refresh ]]; then
		refresh_check
	else
		print_plan
		ask "Proceed" y || die "aborted"
	fi
	take_run_lock
	require_dpkg_ready
	as_root install -d -m 0755 "$SYS_DIR"
	record_packages_before
	# The edition is known from the first record on, so that the other script
	# never installs over an install that stopped halfway
	[[ -f $SYS_DIR/state ]] || save_state
	_installing_end
	before=$(pkg_versions)
	src=$(cat -- "$APT_SRC" 2>/dev/null || true)
	install_all
	install_pkg
	# Those that beside_tidy removed are gone already
	read_lines STALE_PKGS installed_of "${STALE_PKGS[@]}"
	if (( ${#STALE_PKGS[@]} )) && ask "Remove the ${#STALE_PKGS[@]} packages no longer part of the look (${STALE_PKGS[*]})" n; then
		_remove_recorded "${STALE_PKGS[@]}"
	fi
	apt_lists_sync "$src"
	step "Setting up the login screen and the session for $(id -un)"
	_state_init
	# An install starts clean; --refresh keeps the user's settings
	if [[ $O_MODE != refresh ]]; then
		if has_session_settings; then
			reset_session_settings
			ok "Your Raspberry Pi Desktop settings are back to the defaults"
		fi
		reset_file_manager
		reset_power
	fi
	# The terminal's font follows the size: on an install, and on --refresh
	# when --size is given
	if [[ $O_MODE != refresh ]] || (( O_SIZE_GIVEN )); then term_font; fi
	choose_session
	reload_session
	save_size
	save_state
	[[ $O_MODE != refresh ]] || REBOOT_WHY=$(reboot_reason "$before" "$(pkg_versions)")
	summary
}

# Stop unless Debian's LXDE desktop is installed: the look is made for it
# and tested with it only.
require_lxde() {
	(( H_LXDE )) || die "rpios-look supports Debian with LXDE only, and LXDE is not installed. Install it first: sudo apt install task-lxde-desktop"
}

# Warn that the run is at the user's own risk, before anything changes.
risk_warning() {
	log ""
	warn "${C_B}Use at your own risk.${C_0}"
	log "  This script installs packages and changes system files as root. It is"
	log "  provided \"as is\", without warranty of any kind (see LICENSE). The authors"
	log "  accept no responsibility for a broken system, lost data, security issues"
	log "  or any other damage, whether caused by the script, by the packages it"
	log "  installs or by the Debian release it runs on. Back up your data first."
}

# Print the version that a copy of this script on stdin declares in its
# APP_VERSION line, read as data.
script_version() { sed -n 's/^readonly APP_VERSION="\([0-9][0-9.]*\)"$/\1/p' | first_line; }

# Succeed if dotted version A is newer than B. Usage: version_newer A B
version_newer() {
	[[ $1 =~ ^[0-9]+(\.[0-9]+)*$ && $2 =~ ^[0-9]+(\.[0-9]+)*$ ]] && dpkg --compare-versions "$1" gt "$2"
}

# Note when a newer version of this script is published (SELF_URL); it is
# never downloaded or run here.
check_script_version() {
	local v
	v=$(fetch_extra "$SELF_URL" 16384 | script_version) || v=""
	if version_newer "$v" "$APP_VERSION"; then
		note "$APP_NAME $v is available (this is $APP_VERSION); to get it: curl -fLO $SELF_URL"
	else
		debug "no newer published version of $APP_NAME found${v:+ ($v)}"
	fi
}

# Warn when this Debian release is older than the current stable one: it may
# no longer get security updates, and neither may the packages installed for it.
old_release_warning() {
	local rank stable rel eol lts today status
	rank=$(host_rank) || return 0
	stable=$(stable_rank)
	(( stable && rank < stable )) || return 0
	printf -v today '%(%Y-%m-%d)T' -1
	read -r rel eol lts <<<"${REL_DATES[$rank]:-- - -}"
	if [[ $lts != - && ! $lts > $today ]]; then
		status="Debian's security support for it, LTS included, ended on $lts"
	elif [[ $eol != - && ! $eol > $today ]]; then
		status="its regular security support ended on $eol; only LTS updates follow"
		[[ $lts == - ]] || status+=", until $lts"
	elif [[ $eol != - ]]; then
		status="its regular security support ends on $eol"
	else
		status="its security support may have ended"
	fi
	log ""
	warn "${C_B}Old Debian release:${C_0} ${H_PRETTY:-Debian $rank} is older than the current stable release, Debian $stable."
	log "  ${status^}."
	log "  Old releases and the packages made for them (Debian's and Raspberry Pi"
	log "  OS's) may no longer be maintained and may contain known security"
	log "  vulnerabilities that will not be fixed. Use it at your own risk, ideally"
	log "  away from untrusted networks, and consider upgrading to Debian $stable."
	NOTES+=("${H_PRETTY:-Debian $rank} is older than the current stable release (Debian $stable) and may not get security fixes; at your own risk")
}

# Parse the command line, set up the run and start the chosen mode.
main() {
	ARGV=("$@")
	init_colors
	parse_args "$@"
	(( EUID != 0 )) || die "do not run this as root: run it as your normal user, which needs sudo rights"
	load_releases
	WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/$APP_NAME.XXXXXX")
	chmod 0755 "$WORKDIR"
	trap cleanup EXIT
	trap 'die "interrupted"' INT TERM
	detect_host
	# Before anything is written, the log included; an installation from any
	# release and architecture can be removed. A system known to be wrong
	# stops before Debian's release table is downloaded.
	if [[ $O_MODE != uninstall ]]; then
		require_host_early
		update_release_table
		load_releases
		require_host
		require_own_install
	fi
	# Nothing to undo: no log, no change, no restart
	if [[ $O_MODE == uninstall ]] && ! look_installed; then
		info "The Raspberry Pi OS look is not installed on this computer: nothing to uninstall."
		return 0
	fi
	adopt_session
	start_log
	log ""
	log "${C_B}  $APP_NAME $APP_VERSION${C_0} — the Raspberry Pi OS desktop look for Debian"
	risk_warning
	if [[ $O_MODE == uninstall ]]; then uninstall; return 0; fi
	check_script_version
	# Before pick_suite, which already downloads Raspberry Pi's indexes
	preflight_tools
	pick_suite
	[[ $O_MODE != refresh ]] || keep_installed_release
	old_release_warning
	load_size
	install_mode
}

# Run main unless this file is sourced (the tests source it).
if [[ ${BASH_SOURCE[0]:-} == "$0" || -z ${BASH_SOURCE[0]:-} ]]; then
	main "$@"
fi
