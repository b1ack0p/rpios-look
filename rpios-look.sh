#!/usr/bin/env bash
# =============================================================================
# Title       : rpios-look.sh
# Description : Makes Debian on 32-bit (x86, i386) and 64-bit (x64, amd64)
#               PCs look like Raspberry Pi OS, without breaking
#               Debian: the official PiXflat, PiXnoir, PiXtrix, PiXonyx and
#               PiX themes with their icons, cursors, fonts, wallpapers,
#               panel, file manager and login screen, as a "Raspberry Pi
#               Desktop" session on the login screen.
#
# Usage       : bash rpios-look.sh                   install or update
#               bash rpios-look.sh --refresh         list available updates, then
#                                                      ask to apply them
#               bash rpios-look.sh --uninstall       remove everything this script added
#                                                      and restore Debian's default setup
#               bash rpios-look.sh --prepare-upgrade before a Debian release upgrade
#               bash rpios-look.sh --download        build or refresh packages/ for
#                                                      an offline install (needs internet)
#               bash rpios-look.sh --offline         install from packages/, no network
#               bash rpios-look.sh --help            this text
#               Safe to re-run.
#
# Look        : The look is Raspberry Pi OS's for this Debian release:
#               PiXtrix on Debian 13 and later, else PiXflat, with its icons,
#               cursor, font, window frames and wallpaper. Every theme is
#               installed; each user can change theirs with
#               rpios-look-set --theme NAME. The session runs on Wayland
#               (labwc) where the computer suits it, else on X (Openbox).
#
# Options     :     --size SIZE      small, medium, large or larger: Raspberry Pi OS's
#                                    size presets for fonts, icons, the panel and the
#                                    cursor. Default: medium, Raspberry Pi OS's own.
#                                    An install run saves it; later runs reuse it
#                                    unless it is given again
#               -v, --verbose        also print the commands run as root, the
#                                    files downloaded and other details
#               -V, --version        print the version
#
# Offline     : Run --download on any machine with internet access; it builds
#               packages/ for Debian 10 to 12 on amd64 and i386, and 13 on amd64.
#               Copy this script and packages/ to the target; run --offline there.
#
# Refresh     : --refresh lists what an update would change: newer official
#               packages, missing ones, a Debian change, a changed size. It
#               asks before applying anything.
#
# Undo        : bash rpios-look.sh --uninstall removes the session, the
#               packages it installed and the login screen style, and restores
#               the settings of the user running it.
#
# Requires    : Debian 10 or later, or a derivative (Debian 9 is accepted but
#               not supported); a normal user (not root) with sudo rights;
#               internet access, except for --offline.
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
#   9. Offline      --download, --offline
#  10. Refresh      --refresh, --prepare-upgrade
#  11. Uninstall    --uninstall
#  12. Main         modes, run log, summary

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
readonly APP_VERSION="3.14.0"
# The package this script generates. It holds the session, the login screen
# style and the adapted icon sets, so that dpkg tracks and removes them.
readonly APP_PKG="rpios-look-debian"
# Records of the install: installed packages, the saved size, replaced files.
readonly SYS_DIR="/var/lib/rpios-look"
# Configuration and data of the session, shipped in the generated package.
readonly SHARE="/usr/share/rpios-look"
readonly SESSION_ID="rpios-look"
# APT options: never remove a package, never ask, and wait for another
# package manager to finish. Recommended packages are not installed: every
# needed package is named explicitly, and a recommendation (Raspberry Pi's
# plugins recommend PulseAudio) must not replace installed software.
readonly APT_OPTS=(-y --no-remove --no-install-recommends -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=300)
readonly RPI_ARCHIVE="https://archive.raspberrypi.org/debian"
# Raspberry Pi's archive in APT, so that "apt full-upgrade" updates the
# Raspberry Pi packages that this script installed unchanged (see apt_files)
readonly APT_SRC="/etc/apt/sources.list.d/rpios-look.sources" APT_PIN="/etc/apt/preferences.d/rpios-look"
readonly APT_HOOK="/etc/apt/apt.conf.d/50rpios-look" APT_KEY="/usr/share/keyrings/rpios-look-archive-keyring.gpg"
readonly RPI_KEY_URL="${RPI_ARCHIVE}/raspberrypi.gpg.key"
readonly RPI_KEY_FPR="CF8A1AF502A2AA2D763BAE7E82B129927FA3303E"
# Raspberry Pi OS configuration packages. They are downloaded and verified
# but never installed: rpd-common provides the menu (Raspberry Pi OS 13 and
# later), rpd-x-core the panel layout, and rpd-wayland-core the settings of
# the Wayland session (Raspberry Pi OS 13 and later).
readonly ART_PKG="rpd-common" PANEL_PKG="rpd-x-core" WAYLAND_PKG="rpd-wayland-core"
# Supported PC architectures, as grep -E alternatives.
readonly PC_ARCHES="amd64|i386"
readonly DEBIAN_ARCHIVE="https://deb.debian.org/debian"
# Debian's server for releases that have reached their end of life.
readonly DEBIAN_OLD_ARCHIVE="https://archive.debian.org/debian"
readonly DEBIAN_KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
# Retired Debian keys, which signed the archived releases.
readonly DEBIAN_OLD_KEYRING="/usr/share/keyrings/debian-archive-removed-keys.gpg"
# Debian releases by major version. Debian's distro-info-data, if installed,
# adds releases named after this script was written.
readonly KNOWN_RELEASES=(9:stretch 10:buster 11:bullseye 12:bookworm 13:trixie 14:forky 15:duke)
# OLDEST: the oldest Debian host accepted (pick_suite) and the oldest Raspberry
# Pi OS release whose indexes are read. Debian 9 is accepted but unsupported;
# the documented minimum, and the oldest release --download bundles, is 10.
readonly OLDEST=9 OFFLINE_OLDEST=10
# Raspberry Pi OS theme packages that are built per architecture but contain
# no compiled code, so the build of any Raspberry Pi OS release can be used.
readonly DATA_PKGS=(pixflat-theme pixtrix-theme pix-theme)

# Dependency names missing from some Debian releases, mapped to the packages
# that provide them there; the first available candidate is used. A newer
# release has the renamed successor (libgdk-pixbuf-2.0-0), an older one the
# package that was later split (adwaita-icon-theme).
declare -rA DEP_RENAMES=(
	[adwaita-icon-theme-legacy]="adwaita-icon-theme"
	[libgdk-pixbuf2.0-0]="libgdk-pixbuf-2.0-0"
	[libglib2.0-0]="libglib2.0-0t64"
	[libgtk2.0-0]="libgtk2.0-0t64"
	[libatk1.0-0]="libatk1.0-0t64"
	[libpng12-0]="libpng16-16t64 libpng16-16"
	[gtk-update-icon-cache]="libgtk-3-bin"
)
# Dependencies only a Raspberry Pi needs; they are dropped. The battery and CPU
# temperature plugins (Raspberry Pi OS 10, 11) use raspi-config only to detect
# a pi-top or a Raspberry Pi; without it they read the PC's battery and sensors.
declare -rA DEP_DROPS=(
	[lxplug-ptbatt]="raspi-config"
	[lxplug-cputemp]="raspi-config"
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
readonly LOGO_ICONS=(start-here distributor-logo gnome-main-menu launch rpi-logo)

# Options (O_*). An install run saves the size in $SYS_DIR/options; later
# runs reuse it unless --size is given again.
O_MODE="install"        # install | refresh | uninstall | prepare-upgrade | download | offline
O_SIZE=medium           # the size preset: small, medium (Raspberry Pi OS's default), large or larger
O_SIZE_GIVEN=0          # 1 when --size is given on this command line
O_VERBOSE=0
O_INTERACTIVE=0

# Host (H_*) and run state. The theme variables (T_*) are set by set_theme.
H_ARCH="" H_ID="" H_LIKE="" H_CODENAME="" H_PRETTY="" H_SUITE=""
# The computer (see detect_machine) and the display system chosen for it.
H_MODEL="" H_CPU="" H_MEM_MB=0 H_OLD_CPU=0 H_GPU="" H_GPU_DRV="" H_GPU_DRVS="" H_RENDER=0 H_KMS=0
H_VIRT="" H_KERNEL="" H_EDITION="" H_DM="" H_DISPLAY="x11" H_DISPLAY_WHY=""
FETCH_PKGS=()           # installed from verified .deb files
PIN_PKGS=()             # those installed as Raspberry Pi ships them, which APT updates
NO_APT_SOURCE=0         # 1 to build the package without Raspberry Pi's archive in APT
HW_PKGS=()              # hardware support (X server, network, Bluetooth, sound, login screen)
POLICY_RC=""            # the policy-rc.d file a purge made, removed on exit
ROOT_PKGS=()            # what is installed for its own sake, not as a dependency
APT_PKGS=()             # installed by name from the APT sources
USE_NETMAN=0            # 1 when Raspberry Pi's network plugin and its libnma build are used
NET_NAMES=()            # those Raspberry Pi builds that carry Debian's names (libnma)
USE_STACK=0             # 1 when Raspberry Pi's builds replace Debian's panel and file manager (PI_STACK)
STACK_NAMES=()          # those packages, with the other installed packages of their sources
USE_WM=0                # 1 when Raspberry Pi's build replaces Debian's Openbox (PI_WM)
WM_NAMES=()             # those packages, with the other installed packages of their source
declare -A PKG_VER=() PKG_FILE=() PKG_SHA=() PKG_SIZE=() PKG_SUITE=() PKG_AID=()
declare -A IDX_LOADED=() IDX_FAILED=() IN_SET=()
WORKDIR="" KEYRING="" DEP_INDEX="" BUILD_STAGE="" LOG_FILE="" REPO="" PKG_DEB=""
ARGV=()
NOTES=()                # lines for the summary at the end
STEP=0                  # the number of the step being shown
RELOGIN=0               # 1 when the user has to log in again to see the change
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

# Quote arguments for display.
_q() { local a out=""; for a; do out+="${out:+ }$(printf '%q' "$a")"; done; printf '%s' "$out"; }

# Run a command as root through sudo; with --verbose, print it first.
as_root() { debug "sudo $(_q "$@")"; sudo -- "$@"; }

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

# Format a byte count, e.g. 27MB.
human_size() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || printf '%s bytes' "${1:-0}"; }

# Print the command that runs this script again.
self_cmd() { printf 'bash %s' "$(basename -- "${BASH_SOURCE[0]:-$APP_NAME.sh}")"; }

# Print the installed version of a package, or nothing. A package installed
# for several architectures gives the first version only.
installed_version() {
	{ dpkg-query -W -f='${db:Status-Abbrev} ${Version}\n' "$1" 2>/dev/null || true; } | awk '$1 ~ /^.i/ && !n++ { print $2 }'
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
	tmp=$(mktemp) || return 1
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
	# Only an update reuses it; a fresh install starts from the default.
	[[ -n $(installed_version "$APP_PKG") ]] || return 0
	val=$(sed -n 's/^size=//p' "$SYS_DIR/options" 2>/dev/null | first_line) || val=""
	if size_ok "$val"; then O_SIZE=$val; else debug "ignoring saved size '$val'"; fi
}

# Save the size of this install run for later runs.
save_size() {
	if ! printf 'size=%s\n' "$O_SIZE" | cmp -s - "$SYS_DIR/options" 2>/dev/null; then
		printf 'size=%s\n' "$O_SIZE" | sys_write "$SYS_DIR/options" || note "The size could not be saved; give --size again next time."
	fi
}

# Take the run lock, waiting while another run holds it, so that two runs
# never change the system at the same time.
take_run_lock() {
	local lock=/run/lock/$APP_NAME.lock
	{ [[ -e $lock ]] || ( umask 022; : >"$lock" ); } 2>/dev/null
	{ exec 9<"$lock"; } 2>/dev/null || die "cannot open the run lock $lock"
	if ! flock -n 9; then
		info "Another $APP_NAME run is in progress; waiting for it to finish"
		flock 9
	fi
}

# Stop if an interrupted dpkg run must be repaired first: APT would refuse
# every change, and its errors would appear to come from this script.
require_dpkg_ready() {
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
	local uid pid p c line w x
	uid=$(id -u)
	[[ -S /run/user/$uid/bus ]] && export XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
	[[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && return 0
	for p in lxsession xfce4-session mate-session labwc openbox; do
		pid=$(pgrep -u "$uid" -n -x "$p" 2>/dev/null) && break
	done
	[[ -n ${pid:-} ]] || return 0
	while IFS= read -r -d '' line; do
		case $line in
			DISPLAY=*|WAYLAND_DISPLAY=*|XAUTHORITY=*|XDG_CURRENT_DESKTOP=*|DESKTOP_SESSION=*|LABWC_PID=*) export "${line?}" ;;
		esac
	done < <(cat -- "/proc/$pid/environ" 2>/dev/null || true)
	# labwc sets WAYLAND_DISPLAY and LABWC_PID only for its children: LABWC_PID
	# is labwc itself, and the display is read from its first child that has one.
	if [[ $p == labwc && -z ${LABWC_PID:-} ]]; then export LABWC_PID=$pid; fi
	[[ -z ${WAYLAND_DISPLAY:-} && $p == labwc ]] || return 0
	for c in $(pgrep -u "$uid" -P "$pid" 2>/dev/null || true); do
		w="" x=""
		while IFS= read -r -d '' line; do
			case $line in WAYLAND_DISPLAY=*) w=$line ;; DISPLAY=*) x=$line ;; esac
		done < <(cat -- "/proc/$c/environ" 2>/dev/null || true)
		[[ -n $w ]] || continue
		export "${w?}"
		if [[ -n $x && -z ${DISPLAY:-} ]]; then export "${x?}"; fi
		break
	done
}

###############################################################################
# 3. Packages: themes, package sets, host and release
###############################################################################

# Set the T_* variables for a theme. T_GTK names the GTK, Openbox and labwc
# themes alike; the icons, cursor, font and wallpaper follow the theme.
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
	if [[ $T_ERA == trixie ]]; then
		T_FONT_FAMILY="Nunito Sans" T_FONT_WEIGHT=Light T_FONT="Nunito Sans Light $T_FONT_SIZE"
	else
		T_FONT_FAMILY=PibotoLt T_FONT_WEIGHT=Normal T_FONT="PibotoLt $T_FONT_SIZE"
	fi
	# The default wallpaper of the look in Raspberry Pi OS. PiXflat's changed
	# with each release (raspberrypi-ui-mods); PiX uses Raspbian Stretch's.
	case $T_ERA in
		trixie) T_WALL_DEFAULT=sunrise.jpg ;;
		legacy) T_WALL_DEFAULT=road.jpg ;;
		*) case $H_SUITE in
			buster)   T_WALL_DEFAULT=temple.jpg ;;
			bullseye) T_WALL_DEFAULT=clouds.jpg ;;
			*)        T_WALL_DEFAULT=fisherman.jpg ;;
		   esac ;;
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
# fonts, GTK 2 engines and wallpapers, the window manager (PI_WM), and the
# panel and file manager (Raspberry Pi's own programs from Raspberry Pi OS 13,
# its builds of Debian's before; see pi_apps and pi_stack).
# Usage: rpi_pkgs SUITE ARCH
rpi_pkgs() {
	printf '%s\n' pixflat-theme pixtrix-theme pix-theme pixflat-icons pixtrix-icons rpd-icons \
		gtk2-engines-pixflat gtk2-engines-clearlookspix fonts-piboto fonts-nunito-sans "${PI_WM[@]}"
	[[ $O_MODE == download ]] || stack_extras "$PI_WM_SRC" "${PI_WM[@]}"
	# The standard wallpaper sets (no code) of this and every later release.
	local s
	for s in $(releases); do
		suite_ge "$s" "$1" || continue
		index_names "$(rpi_aid)" "$s" "$2" | grep -E '^rpd-wallpaper' | grep -v -- '-4k$' || true
	done | awk '!seen[$0]++'
	if suite_ge "$1" trixie; then pi_apps "$1" "$2"; wayland_pkgs "$1" "$2"; else pi_stack "$1" "$2"; fi
}

# Print Raspberry Pi's Wayland panel and every plugin that Raspberry Pi OS
# installs with it (rpd-wayland-core) and that works on Debian, and its
# screenshot tool, which its Print key runs. pipanel (Appearance Settings)
# runs inside rpcc (Control Centre) and needs sudopwd.
# Usage: wayland_pkgs SUITE ARCH
wayland_pkgs() {
	printf '%s\n' wf-panel-pi pipanel rpcc sudopwd gui-screenshot
	index_candidates "$(rpi_aid)" "$1" "$2" "$WAYLAND_PKG" 2>/dev/null | first_line | cut -f6 | depnames \
		| grep '^wfplug-' | grep -vxE "wfplug-($(wf_drop))" || true
}
# Print the Debian packages of the Wayland session: compositor, wallpaper,
# display settings, XSETTINGS for X applications, and Xwayland.
# Screen lock and blanking as in Raspberry Pi OS 13: swaylock, swayidle and,
# where Debian has it, wlopm to switch displays off. ALL (1) prints every
# one, for packages/. Usage: wayland_debs [ALL]
wayland_debs() {
	printf '%s\n' labwc swaybg kanshi xsettingsd wlr-randr xwayland swaylock swayidle
	if (( ${1:-0} )) || apt_has wlopm; then echo wlopm; fi
	# MATE's authentication agent, as Raspberry Pi OS uses on Wayland
	if (( ${1:-0} )) || apt_has mate-polkit; then echo mate-polkit; fi
}
# Print the Debian packages of the X server, which the login screen always
# needs, and Mesa's 3D drivers.
x11_debs() { printf '%s\n' xserver-xorg x11-utils libgl1-mesa-dri; }
# Print the Debian packages of the login screen: LightDM with Debian's greeter
# in the Raspberry Pi OS style, where no other display manager is in use, and
# Debian's login artwork (desktop-base). ALL (1) prints every one, for
# packages/.
# Usage: login_debs [ALL]
login_debs() {
	if [[ ${1:-0} == 1 || -z $H_DM || $H_DM == lightdm ]]; then printf '%s\n' lightdm lightdm-gtk-greeter; fi
	echo desktop-base
}
# Succeed if LightDM is installed or is about to be.
with_lightdm() { [[ -n $(installed_version lightdm) ]] || grep -qx lightdm <<<"$(login_debs)"; }

# Print Raspberry Pi's magnifier for a release, which Raspberry Pi OS offers
# in Recommended Software: mage-rpi (Raspberry Pi OS 12 and later), else mage
# where Debian has no package of that name. Its panel plugin is left off the
# panel (see _pi_layout), for the user to add. Usage: magnifier_pkg SUITE ARCH
magnifier_pkg() {
	local names
	names=$(index_names "$(rpi_aid)" "$1" "$2")
	if grep -qx mage-rpi <<<"$names"; then echo mage-rpi
	elif grep -qx mage <<<"$names" && ! _debian_has mage; then echo mage; fi
}

# Print Raspberry Pi's own programs (Raspberry Pi OS 13 and later): the file
# manager, which draws the desktop and is installed beside Debian's (see
# fm_coinstall); the Shutdown and Run dialogs; and the panel with the plugins
# of its layout (see _pi_panel_layout) and every other plugin that Raspberry Pi
# OS installs (rpd-x-core) and that works on Debian. Debian's panel and its
# plugins stay installed. Usage: pi_apps SUITE ARCH
pi_apps() {
	local t
	printf '%s\n' pcmanfm-pi pishutdown gui-runcmd lxpanel-pi
	{
		for t in $(panel_plugins "$1" "$2"); do printf 'lpplug-%s\n' "${t/#smenu/menu}"; done
		index_candidates "$(rpi_aid)" "$1" "$2" "$PANEL_PKG" 2>/dev/null | first_line | cut -f6 | depnames \
			| grep '^lpplug-' | grep -vxE "lpplug-($(panel_drop))" || true
	} | awk '!seen[$0]++'
}

# Print the plugin types of Raspberry Pi OS's panel layout (PATH in PACKAGE)
# that work on Debian, without the panel program's own (BUILT-IN), or the
# DEFAULT list if the layout cannot be read.
# Usage: _layout_plugins SUITE ARCH PACKAGE PATH BUILT-IN DEFAULT...
_layout_plugins() {
	local suite=$1 arch=$2 pkg=$3 path=$4 builtin=$5 f
	shift 5
	f=$(pi_unpack "$pkg" "$suite" "$arch" 2>/dev/null) && f+=/$path && [[ -f $f ]] \
		|| { printf '%s\n' "$@" | _no_battery; return 0; }
	sed -n 's/^[[:space:]]*type=//p' "$f" | grep -vxE "$(panel_drop)|$builtin" | awk '!seen[$0]++' | _no_battery
}
# Raspberry Pi OS 13's panel (lxpanel-pi). Usage: panel_plugins SUITE ARCH
panel_plugins() {
	_layout_plugins "$1" "$2" "$PANEL_PKG" etc/xdg/lxpanel-pi/panels/panel 'space|separator|launchbar|taskbar|tray' \
		smenu ejecter bluetooth volumepulse clock batt magnifier
}
# Raspberry Pi OS 10 to 12's panel, from raspberrypi-ui-mods. Usage: lx_panel_plugins SUITE ARCH
lx_panel_plugins() {
	_layout_plugins "$1" "$2" raspberrypi-ui-mods etc/xdg/lxpanel/LXDE-pi/panels/panel \
		'space|separator|launchbar|taskbar|tray|menu|dclock' smenu ejecter bluetooth volumepulse batt magnifier
}

# Copy plugin types from stdin, without the battery plugins where this
# computer has no battery (except with --download, which serves any computer).
_no_battery() { if [[ $O_MODE == download ]] || has_battery; then cat; else grep -vxE 'batt|ptbatt' || true; fi; }

# Print Raspberry Pi OS's panel and file manager before Raspberry Pi OS 13:
# its builds of Debian's packages (PI_STACK, with the other installed packages
# of their sources), the lxplug-* plugins of its panel layout, and the plugins
# raspberrypi-ui-mods recommends (such as CPU temperature) that work on Debian.
# Usage: pi_stack SUITE ARCH
pi_stack() {
	local t names drop
	printf '%s\n' "${PI_STACK[@]}"
	[[ $O_MODE == download ]] || stack_extras "$PI_STACK_SRC" "${PI_STACK[@]}"
	names=$(index_names "$(rpi_aid)" "$1" "$2")
	# The dhcpcd network plugin (dhcpcdui) is the package lxplug-network
	drop=$(panel_drop); drop=${drop//dhcpcdui/network}
	for t in $(lx_panel_plugins "$1" "$2" | sed 's/^smenu$/menu/'
		awk 'BEGIN { RS = ""; FS = "\n" } $0 ~ /(^|\n)Package: raspberrypi-ui-mods(\n|$)/ {
			for (i = 1; i <= NF; i++) if ($i ~ /^Recommends: /) print substr($i, 13) }' \
			"$WORKDIR/index/$(rpi_aid)/$1/Packages-$2" 2>/dev/null | depnames | sed -n 's/^lxplug-//p' \
			| grep -vxE "$drop" | _no_battery); do
		t=lxplug-$t
		if grep -qxF "$t" <<<"$names"; then echo "$t"; fi
	done | awk '!seen[$0]++'
	# Raspberry Pi OS's Appearance Settings and Shutdown dialog for that panel
	if grep -qx pipanel <<<"$names"; then echo pipanel; fi
	if grep -qx pishutdown <<<"$names"; then echo pishutdown; fi
}
# Print the other installed packages built from the sources SRC (grep -E
# alternatives) of the packages NAMES. Usage: stack_extras SRC NAMES...
stack_extras() {
	local re=$1
	shift
	dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${source:Package}\n' 2>/dev/null \
		| awk -v re="^($re)\$" '$1 ~ /^.i/ && $3 ~ re { print $2 }' \
		| grep -vxF -f <(printf '%s\n' "$@") || true
}
# Succeed if a .deb file is built from one of the sources of PI_STACK or PI_WM.
# Usage: stack_deb FILE
stack_deb() {
	local src
	src=$(dpkg-deb -f "$1" Source)
	src=${src%% *}
	[[ ${src:-$(dpkg-deb -f "$1" Package)} =~ ^($PI_STACK_SRC|$PI_WM_SRC)$ ]]
}
# Succeed if this computer has a battery of its own (not that of a mouse or a
# keyboard).
has_battery() {
	local d
	for d in /sys/class/power_supply/*; do
		[[ $(cat "$d/type" 2>/dev/null) == Battery && $(cat "$d/scope" 2>/dev/null) != Device ]] && return 0
	done
	return 1
}
# The network plugins of Raspberry Pi OS's panels: netman (NetworkManager,
# Raspberry Pi OS 12 and later) and dhcpcdui (dhcpcd, before).
readonly PANEL_NET="netman|dhcpcdui"
# Print the panel plugins left out (grep -E alternatives): the updater (needs
# Raspberry Pi's system tools), power (reports Raspberry Pi supply problems),
# and the network plugins unless netman is used (USE_NETMAN; else nm-applet).
# --download keeps netman from Debian 12, as the offline computer decides.
panel_drop() {
	local d="updater|power"
	if [[ $O_MODE == download ]]; then
		if suite_ge "$H_SUITE" bookworm; then d+="|dhcpcdui"; else d+="|$PANEL_NET"; fi
	elif (( USE_NETMAN )); then d+="|dhcpcdui"; else d+="|$PANEL_NET"; fi
	echo "$d"
}
# The same for the Wayland panel, with the Raspberry Pi Connect and on-screen
# keyboard plugins, which need Raspberry Pi's own services.
wf_drop() { echo "$(panel_drop)|connect|squeek"; }
# Before Raspberry Pi OS 13, Raspberry Pi's panel and file manager are its own
# builds of Debian's packages, under Debian's names. From Raspberry Pi OS 11
# they use GTK 3, while Debian 11 and 12 build theirs and their plugins for
# GTK 2, so the two cannot be mixed. On Debian 10 to 12 they replace Debian's,
# together with the other installed packages of their sources; --uninstall
# and --prepare-upgrade restore Debian's.
readonly PI_STACK=(lxpanel lxpanel-data pcmanfm libfm4 libfm-gtk4 libfm-modules libfm-data libfm-gtk-data libfm-extra4)
readonly PI_STACK_SRC="lxpanel|libfm|pcmanfm"
# On every release, Raspberry Pi's build of Openbox replaces Debian's, with
# the other installed packages of its source. It keeps a window's corners
# rounded while the window is moved or resized; Debian's carries Raspberry
# Pi's earlier patch, whose corners turn square until the frame is redrawn.
# --uninstall and --prepare-upgrade restore Debian's.
readonly PI_WM=(openbox libobrender32v5 libobt2v5)
readonly PI_WM_SRC="openbox"
# Print the Raspberry Pi OS programs that this script installed and that are
# built against the libraries of one Debian release; --prepare-upgrade removes
# them. The themes and their GTK 2 engines, which need only GTK 2, stay.
release_bound_pkgs() {
	local p
	while read -r p; do
		[[ $(dpkg-query -W -f='${Architecture}' "$p" 2>/dev/null) != all ]] || continue
		[[ " ${DATA_PKGS[*]} " != *" $p "* && $p != gtk2-engines-* ]] || continue
		if [[ -z $(apt_versions "$p") ]]; then echo "$p"; fi   # not in the APT sources
	done < <(cat "$SYS_DIR/installed-packages" 2>/dev/null)
}

# Print the Debian packages of the X session: the LXDE session manager,
# window manager, panel and file manager (also the fallback for Raspberry
# Pi's), gvfs for Trash and drives in the file managers, the appearance
# settings, and dconf for the session's settings. No compositor is installed:
# Raspberry Pi OS starts xcompmgr with an option that Debian's lacks.
# ALL (1) prints every one, for packages/. Usage: session_debs [ALL]
session_debs() {
	printf '%s\n' lxsession lxpolkit openbox lxpanel pcmanfm gvfs-backends gvfs-fuse lxappearance dconf-cli libglib2.0-bin python3
	# The power helper on X (power_build): blanking, idle time and, with
	# LightDM, the screen lock
	printf '%s\n' x11-xserver-utils libxss1
	if (( ${1:-0} )) || with_lightdm; then echo light-locker; fi
}
# Print the authentication agent of the Wayland session: MATE's, as Raspberry
# Pi OS uses there, else LXDE's lxpolkit. Its X session uses lxpolkit.
polkit_agent() {
	local f
	f=$(dpkg -L mate-polkit 2>/dev/null | grep -m1 '/polkit-mate-authentication-agent-1$' || true)
	if [[ -n $f && -x $f ]]; then echo "$f"; else echo lxpolkit; fi
}

# Print the Debian packages the themes need: the GTK 2 pixmap engine and
# runtime, the icon sets that the Raspberry Pi sets inherit, the sound theme
# and the monospace font. Usage: theme_debs SUITE
theme_debs() {
	printf '%s\n' gtk2-engines-pixbuf libgtk2.0-bin gnome-icon-theme sound-theme-freedesktop "$(mono_font_pkg "$1")"
	if suite_ge "$1" trixie; then printf '%s\n' adwaita-icon-theme-legacy; fi
}
# Print the Debian packages that let Qt applications follow the GTK theme in
# the session (QT_QPA_PLATFORMTHEME=gtk3); a release may lack one.
qt_debs() { printf '%s\n' qt5-gtk-platformtheme qt6-gtk-platformtheme; }
# Succeed if this computer has a Wi-Fi adapter.
has_wifi() { compgen -G '/sys/class/ieee80211/*' >/dev/null; }
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
# Raspberry Pi OS, and for its Help menu. With a Wi-Fi adapter: NetworkManager
# and the Wi-Fi tools, unless another network manager is installed; the tray
# icon (nm-applet) also where NetworkManager is already installed. With a
# Bluetooth adapter: BlueZ, Bluetooth audio for the sound server in use, and
# blueman where Debian's panel, which has no Bluetooth plugin, is used.
# ALL (1) prints every one, for packages/. Usage: tray_debs SUITE [ALL]
tray_debs() {
	local all=${2:-0} nm=0 rfkill=0
	[[ -n $(installed_version network-manager) ]] && nm=1
	if (( all )) || { (( ! nm )) && has_wifi && [[ -z $(installed_version connman)$(installed_version wicd) ]]; }; then
		nm=1 rfkill=1
		printf '%s\n' network-manager wpasupplicant iw wireless-regdb rfkill
	fi
	(( nm )) && (( ! USE_NETMAN )) && nm_applet_pkg "$1"
	if (( all )) || has_bluetooth; then
		echo bluez
		(( rfkill )) || echo rfkill
		if (( all )) || [[ -n $(installed_version pipewire) ]]; then echo libspa-0.2-bluetooth; fi
		if (( all )) || [[ -n $(installed_version pulseaudio) ]]; then echo pulseaudio-module-bluetooth; fi
		# Raspberry Pi's panel has its own Bluetooth plugin.
		suite_ge "$1" trixie || (( USE_STACK )) || echo blueman
	fi
	printf '%s\n' debian-reference-common debian-reference-en
}
# Print the Debian packages for sound, where a sound card exists and no sound
# server is installed: PipeWire from Debian 12, PulseAudio before. Raspberry Pi
# OS's volume plugin needs the PulseAudio interface, which both provide.
# ALL (1) prints it regardless, for packages/. Usage: audio_debs SUITE [ALL]
audio_debs() {
	if (( ! ${2:-0} )); then
		compgen -G '/sys/class/sound/card*' >/dev/null || return 0
		[[ -z $(installed_version pipewire-pulse)$(installed_version pulseaudio) ]] || return 0
	fi
	if suite_ge "$1" bookworm; then echo pipewire-audio; else echo pulseaudio; fi
}

# Print the Debian package that provides nm-applet (network-manager-gnome is
# a transitional package from Debian 13).
nm_applet_pkg() { if suite_ge "$1" trixie; then echo network-manager-applet; else echo network-manager-gnome; fi; }
# Print the Debian package that provides Liberation Mono, the monospace font
# of Raspberry Pi OS.
mono_font_pkg() { if suite_ge "$1" trixie; then echo fonts-liberation; else echo fonts-liberation2; fi; }

# Load the Debian release numbers from the built-in list, then from Debian's
# distro-info-data, which also names future releases.
declare -A REL_VER=()
load_releases() {
	local e v c
	for e in "${KNOWN_RELEASES[@]}"; do REL_VER[${e#*:}]=${e%%:*}; done
	[[ -r /usr/share/distro-info/debian.csv ]] || return 0
	while IFS=, read -r v _ c _; do
		if [[ $v =~ ^[0-9]+ && $c =~ ^[a-z]+$ ]]; then REL_VER[$c]=${v%%.*}; fi
	done </usr/share/distro-info/debian.csv
}
# Print the archive that provides the Raspberry Pi OS packages: packages/ for
# an offline install, otherwise Raspberry Pi's.
rpi_aid() { if [[ -n $REPO && $O_MODE != download ]]; then echo local; else echo rpi; fi; }

# Print the Debian releases from Debian $OLDEST on, newest first.
releases() {
	local c
	for c in "${!REL_VER[@]}"; do if (( REL_VER[$c] >= OLDEST )); then echo "${REL_VER[$c]} $c"; fi; done | sort -rn | cut -d' ' -f2
}
# Print the major version of a release; print 0 and fail if it is unknown.
suite_rank() { [[ -n ${REL_VER[$1]:-} ]] && echo "${REL_VER[$1]}" || { echo 0; return 1; }; }
# Succeed if the first release is the second one or newer.
# Usage: suite_ge SUITE OTHER-SUITE
suite_ge() { (( $(suite_rank "$1") >= $(suite_rank "$2") )); }

# Print the lxsession profile of the session, named as in Raspberry Pi OS:
# rpd-x from Raspberry Pi OS 13, LXDE-pi before.
session_profile() { if suite_ge "$H_SUITE" trixie; then echo rpd-x; else echo LXDE-pi; fi; }
# Print the prefix of its application menu file.
menu_prefix() { if suite_ge "$H_SUITE" trixie; then echo rpd-; else echo lxde-pi-; fi; }
# Print the name of the Openbox settings file, as in Raspberry Pi OS.
ob_file() { if suite_ge "$H_SUITE" trixie; then echo rpd-rc.xml; else echo lxde-pi-rc.xml; fi; }

# Print a field of /etc/os-release, without quotes. Usage: os_release KEY
os_release() { sed -n "s/^$1=//p" /etc/os-release | first_line | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"; }

# Detect the architecture, the distribution and the computer.
detect_host() {
	command -v dpkg >/dev/null && command -v apt-get >/dev/null || die "Debian or a derivative is needed (dpkg and apt not found)"
	H_ARCH=$(dpkg --print-architecture)
	[[ $H_ARCH =~ ^($PC_ARCHES)$ ]] || die "this script is for 32-bit (x86, i386) and 64-bit (x64, amd64) PCs; this system is $H_ARCH"
	if [[ -r /etc/os-release ]]; then
		H_ID=$(os_release ID) H_LIKE=$(os_release ID_LIKE)
		H_CODENAME=$(os_release VERSION_CODENAME) H_PRETTY=$(os_release PRETTY_NAME)
	fi
	if [[ $H_ID != debian && " $H_LIKE " != *" debian "* && " $H_LIKE " != *" ubuntu "* ]]; then
		warn "untested distribution '${H_PRETTY:-unknown}', continuing anyway"
	fi
	detect_machine
}

# Detect the computer: model, processor, memory, graphics, kernel, installed
# desktops and display manager.
detect_machine() {
	local d drv slot name t
	H_KERNEL=$(uname -r)
	H_MODEL=""
	if [[ -r /sys/class/dmi/id/product_name ]]; then
		# Firmware placeholders such as "To be filled by O.E.M." are dropped.
		H_MODEL=$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_version /sys/class/dmi/id/product_name 2>/dev/null \
			| grep -viE '^[[:space:]]*((to be filled|system (product|manufacturer|version)|default string|not specified).*|none[[:space:]]*)?$' \
			| awk '!seen[$0]++' | paste -sd' ' - || true)
	fi
	H_CPU=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | first_line)
	[[ -n $H_CPU ]] || H_CPU=$(uname -m)
	H_CPU="$(tr -s ' ' <<<"$H_CPU") ($(nproc 2>/dev/null || echo 1) cores)"
	H_MEM_MB=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
	# PC processors without SSE4.2 predate 2009.
	H_OLD_CPU=0
	if ! grep -qw sse4_2 /proc/cpuinfo; then H_OLD_CPU=1; fi
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
	H_RENDER=0; if compgen -G '/dev/dri/renderD*' >/dev/null; then H_RENDER=1; fi
	# Display outputs exist only with kernel modesetting, which Wayland needs.
	H_KMS=0; if compgen -G '/sys/class/drm/card[0-9]*-*' >/dev/null; then H_KMS=1; fi
	# The installed desktop: Debian's task packages, else the sessions offered.
	H_EDITION=""
	for t in gnome kde xfce cinnamon mate lxqt lxde gnome-flashback; do
		[[ -n $(installed_version "task-$t-desktop") ]] || continue
		case $t in gnome) name=GNOME ;; kde) name="KDE Plasma" ;; xfce) name=Xfce ;; lxqt) name=LXQt ;; lxde) name=LXDE ;;
			gnome-flashback) name="GNOME Flashback" ;; *) name=${t^} ;; esac
		H_EDITION+="${H_EDITION:+, }$name"
	done
	if [[ -z $H_EDITION ]]; then
		H_EDITION=$(grep -hs '^Name=' /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop \
			| grep -v 'Raspberry Pi Desktop' | sed 's/^Name=//' | sort -u | paste -sd, - | sed 's/,/, /g' || true)
	fi
	H_DM=$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service 2>/dev/null)
	[[ -n $H_DM && $H_DM != display-manager ]] || H_DM=$(basename "$(cat /etc/X11/default-display-manager 2>/dev/null)" 2>/dev/null)
}

# Choose Wayland or X for the session, with the reason: Wayland on capable
# PCs with Debian 13 and later; X otherwise.
pick_display() {
	local why=""
	H_DISPLAY=x11
	if ! suite_ge "$H_SUITE" trixie; then why="the Wayland session needs Debian 13 or later"
	elif (( ! H_KMS )) && [[ $H_GPU_DRV == nvidia ]]; then
		why="NVIDIA's driver has kernel modesetting off, which Wayland needs"
	elif (( ! H_KMS )); then
		why="the graphics have no kernel modesetting, which Wayland needs"
	elif (( H_MEM_MB < 2000 )); then why="less than 2 GB of memory"
	elif [[ $H_ARCH == i386 ]]; then why="a 32-bit system"
	elif (( H_OLD_CPU )); then why="an older processor (without SSE4.2)"
	elif [[ $H_GPU_DRV == nvidia ]]; then why="NVIDIA's own driver works best with X"
	elif [[ $H_GPU_DRV == nouveau ]]; then why="the open NVIDIA driver (nouveau) is more reliable with X"
	elif [[ -z $H_GPU_DRV ]]; then why="the graphics have no kernel driver"
	elif (( ! H_RENDER )); then why="the graphics ($H_GPU_DRV) have no 3D acceleration"
	else
		case $H_GPU_DRV in
			radeon) why="older AMD graphics (radeon driver)" ;;
			i915|xe|amdgpu|virtio_gpu|vmwgfx)
				H_DISPLAY=wayland ;;
			*) why="the graphics ($H_GPU_DRV) are untested with Wayland" ;;
		esac
	fi
	if [[ $H_DISPLAY == wayland ]]; then H_DISPLAY_WHY="$H_GPU_DRV graphics with 3D acceleration"
	else H_DISPLAY=x11 H_DISPLAY_WHY=$why; fi
}

# Print the chosen display system.
display_name() { if [[ $H_DISPLAY == wayland ]]; then echo "Wayland (labwc)"; else echo "X (Openbox)"; fi; }

# Print the detected computer and display system.
print_machine() {
	local mem
	mem=$(awk -v m="$H_MEM_MB" 'BEGIN { if (m >= 1024) printf "%.1f GB", m / 1024; else printf "%d MB", m }')
	step "This computer"
	[[ -z $H_MODEL ]] || log "  Model        $H_MODEL"
	log "  Processor    $H_CPU"
	log "  Memory       $mem"
	log "  Graphics     ${H_GPU:-none found} (${H_GPU_DRV:-no driver}, $( (( H_RENDER )) && echo "3D acceleration" || echo "no 3D acceleration"))"
	[[ $H_VIRT == none ]] || log "  Virtual      $H_VIRT"
	log "  System       ${H_PRETTY:-unknown}, $H_ARCH, kernel $H_KERNEL"
	log "  Desktop      ${H_EDITION:-none}${H_DM:+; login screen: $H_DM}"
	log "  Display      $(display_name)${H_DISPLAY_WHY:+: $H_DISPLAY_WHY}"
}

# Print the major Debian version that this system is or follows: from
# os-release, otherwise (testing, unstable, derivatives such as Ubuntu or
# Mint) from /etc/debian_version, which names the release followed
# ("forky/sid", "13.1"); fail if it is unknown.
host_rank() {
	local v
	if [[ $H_ID == debian && $H_CODENAME != sid && -n ${REL_VER[$H_CODENAME]:-} ]]; then echo "${REL_VER[$H_CODENAME]}"; return; fi
	v=$(cat /etc/debian_version 2>/dev/null) v=${v%%/*}
	if [[ -n ${REL_VER[$v]:-} ]]; then echo "${REL_VER[$v]}"
	elif [[ $v =~ ^[0-9]+ ]]; then echo "${v%%.*}"
	elif [[ $H_ID == debian && $(os_release VERSION_ID) =~ ^[0-9]+$ ]]; then os_release VERSION_ID
	else return 1; fi
}

# Choose the Raspberry Pi OS release and architecture for this system: the
# newest release, up to this Debian release, for which Raspberry Pi publishes
# the themes. A Debian release that Raspberry Pi OS has not reached yet thus
# uses the newest Raspberry Pi OS, and moves on once Raspberry Pi publishes
# its own. Hosts older than Debian $OLDEST are rejected here.
pick_suite() {
	local rank s
	rank=$(host_rank) && (( rank >= OLDEST )) || die "Debian $OLDEST or later is needed (found ${H_PRETTY:-an unknown release})"
	# The newest release up to this one. For an older Debian, the oldest
	# release is used, and its packages with compiled code are left out by
	# their dependencies.
	H_SUITE=""
	for s in $(releases); do
		if [[ $(rpi_aid) == local ]]; then [[ -d $REPO/dists/$s ]] || continue
		else rpi_populated "$s" || continue; fi
		H_SUITE=$s
		(( $(suite_rank "$s") > rank )) || break
	done
	[[ -n $H_SUITE ]] || die "Raspberry Pi publishes nothing of the look${REPO:+ in packages/}"
	# packages/ holds Debian's packages of each stable release; testing and
	# unstable change daily
	if [[ $(rpi_aid) == local ]] && (( $(suite_rank "$H_SUITE") != rank )); then
		die "packages/ has nothing for ${H_PRETTY:-this release}; it holds Debian's stable releases. Install online instead."
	fi
	grep -qxF "$H_ARCH" <<<"$(rpi_arches "$H_SUITE")" || die "Raspberry Pi publishes no $H_ARCH packages for $H_SUITE${REPO:+ in packages/}"
	debug "Debian $rank on $H_ARCH: Raspberry Pi OS $H_SUITE"
}

# Print the PC architectures (PC_ARCHES) that Raspberry Pi publishes for a
# release, as listed by its signed Release file or by packages/.
# Usage: rpi_arches SUITE
rpi_arches() {
	local d
	if [[ $(rpi_aid) == local ]]; then
		for d in "$REPO/dists/$1"/main/binary-*; do [[ -d $d ]] && echo "${d##*binary-}"; done
	else
		release_load rpi "$1" || return 0
		sed -n 's/^Architectures:[[:space:]]*//p' "$WORKDIR/index/rpi/$1/Release" | tr ' ' '\n' | grep -v '^$'
	fi | grep -xE "$PC_ARCHES" || true
}

# Succeed if Raspberry Pi publishes the look for a release (its themes, icons
# or GTK 2 engines; a new release starts empty), for the given architecture,
# else for this one or the first published. Usage: rpi_populated SUITE [ARCH]
rpi_populated() {
	local a=${2:-}
	if [[ -z $a ]]; then
		a=$(rpi_arches "$1")
		a=$(grep -xF "$H_ARCH" <<<"$a" || first_line <<<"$a")
	fi
	[[ -n $a ]] && grep -qxE 'pix(flat|trix)?-(theme|icons)|rpd-icons|gtk2-engines-pixflat' <<<"$(index_names rpi "$1" "$a")"
}


# Print the theme of the look: PiXtrix on Debian 13 and later, else PiXflat.
default_theme() { if suite_ge "$H_SUITE" trixie; then echo pixtrix; else echo pixflat; fi; }

###############################################################################
# 4. Archives: signed indexes, resolution, download, repacking
#   rpi     archive.raspberrypi.org, checked against the pinned key
#   debian  deb.debian.org (archive.debian.org for archived releases),
#           checked against debian-archive-keyring
#   local   the offline repository in packages/, checked by SHA256SUMS
###############################################################################

# Print the base URLs (or the path) of an archive, in the order they are tried.
archive_bases() {
	case $1 in
		rpi)    printf '%s\n' "$RPI_ARCHIVE" ;;
		debian) printf '%s\n' "$DEBIAN_ARCHIVE" "$DEBIAN_OLD_ARCHIVE" ;;
		local)  printf '%s\n' "$REPO" ;;
	esac
}
# Print the base URL (or the path) from which an archive serves a release.
# Usage: archive_url ARCHIVE SUITE
declare -A BASE=()
archive_url() { printf '%s\n' "${BASE[$1/$2]:-$(archive_bases "$1" | first_line)}"; }

# Fetch and verify the signed Release file of a release, once. Debian moves a
# release to archive.debian.org at the end of its life, so that server is
# tried next. Fails if no server has the release. The local repository has no
# Release file.
# Usage: release_load ARCHIVE SUITE
release_load() {
	local aid=$1 suite=$2 d="$WORKDIR/index/$1/$2" base
	[[ $aid != local && ! -f $d/Release ]] || return 0
	[[ -z ${IDX_FAILED[$aid/$suite]:-} ]] || return 1
	mkdir -p "$d"
	[[ $aid != rpi ]] || setup_keyring
	for base in $(archive_bases "$aid"); do
		fetch "$base/dists/$suite/InRelease" "$d/InRelease" 2>/dev/null || continue
		# Release is trusted when present, so it is written only once verified
		verify_inrelease "$aid" "$d/InRelease" "$d/Release.new"
		release_ok "$d/Release.new" "$suite" "$base" || die "the signed index at $base/dists/$suite is not a current $suite index"
		mv -f -- "$d/Release.new" "$d/Release"
		BASE[$aid/$suite]=$base
		return 0
	done
	IDX_FAILED[$aid/$suite]=1
	return 1
}

# Print the package names of an index, loading it first.
# Usage: index_names ARCHIVE SUITE ARCH
index_names() {
	index_load "$@" || return 0
	sed -n 's/^Package: //p' "$WORKDIR/index/$1/$2/Packages-$3" | sort -u
}

# Unpack a Raspberry Pi OS package that is read but never installed (for its
# settings or artwork) into a directory under $WORKDIR/pi, once, and print
# that directory.
# Usage: pi_unpack PACKAGE SUITE ARCH
pi_unpack() {
	local pkg=$1 suite=$2 arch=$3 aid line v a f sha z d x=$WORKDIR/pi/$1-$2-$3
	[[ ! -d $x ]] || { printf '%s\n' "$x"; return 0; }
	aid=$(rpi_aid)
	index_load "$aid" "$suite" "$arch" || return 1
	line=$(index_candidates "$aid" "$suite" "$arch" "$pkg" | first_line)
	[[ -n $line ]] || return 1
	IFS=$'\t' read -r v a f sha z d <<<"$line"
	PKG_VER[$pkg]=$v PKG_FILE[$pkg]=$f PKG_SHA[$pkg]=$sha PKG_SIZE[$pkg]=${z:-0} PKG_SUITE[$pkg]=$suite PKG_AID[$pkg]=$aid
	f=$(download_pkg "$pkg") || return 1
	mkdir -p "$x"
	dpkg-deb -x "$f" "$x" || { rm -rf -- "$x"; return 1; }
	printf '%s\n' "$x"
}

# Download a file from an official archive, or copy a local path. Only HTTPS
# URLs of the Raspberry Pi and Debian archives are accepted and redirects are
# refused, so nothing can come from another host.
# Usage: fetch URL|PATH OUTPUT [SHOW-PROGRESS]
fetch() {
	local url=$1 out=$2 progress=${3:-0}
	if [[ $url == /* ]]; then cp -- "$url" "$out"; return; fi
	[[ $url == "$RPI_ARCHIVE"/* || $url == "$DEBIAN_ARCHIVE"/* || $url == "$DEBIAN_OLD_ARCHIVE"/* ]] \
		|| die "refusing to download from an unofficial source: $url"
	debug "GET $url"
	if command -v curl >/dev/null; then
		local -a a=(-f -L --proto '=https' --max-redirs 0 --retry 3 --retry-delay 2 --connect-timeout 20 -o "$out")
		if (( progress )) && [[ -t 2 ]]; then a+=(--progress-bar); else a+=(-sS); fi
		curl "${a[@]}" "$url"
	elif command -v wget >/dev/null; then
		local -a a=(--https-only --max-redirect=0 --tries=3 --timeout=20 -O "$out")
		if (( progress )) && [[ -t 2 ]]; then a+=(-q --show-progress); else a+=(-q); fi
		wget "${a[@]}" "$url"
	else
		die "curl or wget is required"
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
# signature by a trusted key suffices and a bad one fails. Raspberry Pi indexes
# must be signed by the pinned key; Debian indexes by debian-archive-keyring.
# Usage: verify_inrelease ARCHIVE IN OUT
verify_inrelease() {
	local aid=$1 in=$2 out=$3 status fpr
	local -a keys=(--keyring "$KEYRING")
	if [[ $aid != rpi ]]; then
		# Archived releases are signed with keys that Debian has since retired
		keys=(--keyring "$DEBIAN_KEYRING")
		[[ -r $DEBIAN_OLD_KEYRING ]] && keys+=(--keyring "$DEBIAN_OLD_KEYRING")
	fi
	rm -f -- "$out"
	status=$(gpgv --status-fd 1 "${keys[@]}" --output "$out" "$in" 2>/dev/null) || true
	if grep -qE '^\[GNUPG:\] (BADSIG|REVKEYSIG)' <<<"$status" || ! grep -q '^\[GNUPG:\] GOODSIG' <<<"$status"; then
		die "signature verification failed for $in"
	fi
	if [[ $aid == rpi ]]; then
		fpr=$(awk '$2 == "VALIDSIG" { print $NF }' <<<"$status")
		grep -qxi "$RPI_KEY_FPR" <<<"$fpr" || die "$in is not signed by the Raspberry Pi archive key"
	fi
	[[ -s $out ]] || die "no signed content in $in"
}

# Succeed if a verified Release file belongs to the given release and has not
# expired. Releases on archive.debian.org no longer change, so their expiry
# date is not checked.
# Usage: release_ok FILE SUITE BASE-URL
release_ok() {
	local codename until t
	codename=$(sed -n 's/^Codename:[[:space:]]*//p' "$1" | first_line)
	[[ -z $codename || $codename == "$2" ]] || return 1
	[[ $3 != "$DEBIAN_OLD_ARCHIVE" ]] || return 0
	until=$(sed -n 's/^Valid-Until:[[:space:]]*//p' "$1" | first_line)
	[[ -n $until ]] || return 0
	t=$(date -u -d "$until" +%s 2>/dev/null) || return 0
	(( t > $(date -u +%s) ))
}

# Load the package index of an archive, release and architecture into
# $WORKDIR/index, once, and check it against the signed Release file. The local
# repository's index is copied as it is (packages/ is checked by SHA256SUMS).
# Usage: index_load ARCHIVE SUITE ARCH
index_load() {
	local aid=$1 suite=$2 arch=$3 key="$1/$2/$3" d="$WORKDIR/index/$1/$2" base comp="" sha="" c
	[[ -n ${IDX_LOADED[$key]:-} ]] && return 0
	[[ -z ${IDX_FAILED[$key]:-} ]] || return 1
	if [[ -f $d/Packages-$arch ]]; then IDX_LOADED[$key]=1; return 0; fi
	release_load "$aid" "$suite" || { IDX_FAILED[$key]=1; return 1; }
	mkdir -p "$d"
	base=$(archive_url "$aid" "$suite")
	debug "loading $key index"
	if [[ $aid == local ]]; then
		if [[ ! -f $base/dists/$suite/main/binary-$arch/Packages ]]; then IDX_FAILED[$key]=1; return 1; fi
		cp -- "$base/dists/$suite/main/binary-$arch/Packages" "$d/Packages-$arch"
		IDX_LOADED[$key]=1
		return 0
	fi
	for c in xz gz; do
		[[ $c == xz ]] && ! command -v xz >/dev/null && continue
		sha=$(awk -v f="main/binary-$arch/Packages.$c" '
			/^SHA256:/ { s = 1; next } /^[^ ]/ { s = 0 } s && $3 == f { print $1; exit }' "$d/Release")
		if [[ -n $sha ]]; then comp=$c; break; fi
	done
	if [[ -z $comp ]]; then debug "no $arch index in $aid/$suite"; IDX_FAILED[$key]=1; return 1; fi
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
# Usage: index_candidates ARCHIVE SUITE ARCH PACKAGE
index_candidates() {
	local aid=$1 suite=$2 arch=$3 pkg=$4 line v i
	local -a lines=()
	while IFS= read -r line; do
		v=${line%%$'\t'*}
		for (( i = ${#lines[@]}; i > 0; i-- )); do
			dpkg --compare-versions "$v" gt "${lines[i-1]%%$'\t'*}" || break
			lines[i]=${lines[i-1]}
		done
		lines[i]=$line
	done < <(awk -v p="$pkg" 'BEGIN { RS = ""; FS = "\n" }
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
		}' "$WORKDIR/index/$aid/$suite/Packages-$arch")
	if (( ${#lines[@]} )); then printf '%s\n' "${lines[@]}"; fi
}

# Compare two Debian versions with a Depends operator (<<, <=, =, >=, >>).
_vcmp() {
	local op
	case $2 in '<<') op=lt ;; '<='|'<') op=le ;; '=') op=eq ;; '>='|'>') op=ge ;; '>>') op=gt ;; *) return 1 ;; esac
	dpkg --compare-versions "$1" "$op" "$3"
}

# Set AV to the space-separated versions of a package available on the target:
# its resolved version if it is in the install set; otherwise, when building
# packages/, those in the Debian index, else the installed version and the APT
# candidate. "*" stands for any version (a virtual or unresolved package).
declare -A AVAIL=()
_avail() {
	local n=$1
	# Not cached: the version is known only once the package is resolved
	if [[ -n ${IN_SET[$n]:-} ]]; then AV=${PKG_VER[$n]:-*}; return 0; fi
	if [[ -z ${AVAIL[$n]+set} ]]; then
		if [[ -n $DEP_INDEX ]]; then
			AVAIL[$n]=$(awk -v n="$n" '$1 == n { print ($2 == "" ? "*" : $2) }' "$DEP_INDEX" | paste -sd' ' -)
		else
			AVAIL[$n]=$(printf '%s %s' "$(installed_version "$n")" \
				"$(LC_ALL=C apt-cache policy "$n" 2>/dev/null | awk '/Candidate:/ && $2 != "(none)" { print $2 }')" | xargs)
			if [[ -z ${AVAIL[$n]} ]] && apt_has "$n"; then AVAIL[$n]="*"; fi
		fi
	fi
	AV=${AVAIL[$n]}
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
					if [[ -z $op || $v == "*" ]] || _vcmp "$v" "$op" "$ver"; then ok=1; break 3; fi
				done
			done
		done
		(( ok )) || return 1
	done
}

# Find the newest compatible version of a package and record it in PKG_*.
# A version is compatible when all its dependencies, with their versions, are
# available on this Debian release; a version that needs a Raspberry Pi
# rebuild of a Debian package is passed over for an older one that does not.
# The indexes searched, in order:
#  * The target release: any architecture (its binaries match this system).
#  * Newer Raspberry Pi OS releases: architecture-independent packages (icons,
#    fonts, wallpapers) and, built for this architecture, the theme packages
#    without compiled code (DATA_PKGS).
#  * Only if neither has the package: older releases, with the same
#    restriction.
# Offline, the local repository is the only source and is used as built.
# Usage: resolve_pkg PACKAGE [ARCHIVE]
resolve_pkg() {
	local pkg=$1 aid=${2:-rpi} s x line best="" best_v="" skipped="" v a f sha z d arch=$H_ARCH data=0
	[[ -n $REPO && $O_MODE != download ]] && aid=local
	[[ " ${DATA_PKGS[*]} " == *" $pkg "* ]] && data=1
	local -a newer=() older=()
	if [[ $aid == rpi ]]; then
		for s in $(releases); do
			if (( $(suite_rank "$s") > $(suite_rank "$H_SUITE") )); then newer+=("$s/$arch")
			elif (( $(suite_rank "$s") < $(suite_rank "$H_SUITE") )); then older+=("$s/$arch"); fi
		done
	fi
	for x in "$H_SUITE/$arch" "${newer[@]}" "${older[@]}"; do
		[[ -n $best && " ${older[*]} " == *" $x "* ]] && break   # older releases are only a fallback
		index_load "$aid" "${x%/*}" "${x#*/}" || continue
		while IFS= read -r line; do
			IFS=$'\t' read -r v a f sha z d <<<"$line"
			# shellcheck disable=SC2086  # a list of names
			[[ -z ${DEP_DROPS[$pkg]:-} ]] || d=$(drop_deps "$d" ${DEP_DROPS[$pkg]})
			# packages/ holds both Debian's and Raspberry Pi's builds of the panel and
			# file manager; Raspberry Pi's serve only when they replace Debian's
			# (USE_STACK). lxpanel-pi and pcmanfm-pi are separate programs.
			if [[ $aid == local && $v == *+rpt* && $pkg =~ ^(lxpanel|pcmanfm|libfm) && $pkg != *-pi ]] && (( ! USE_STACK )); then continue; fi
			# The same for its build of Openbox (USE_WM)
			if [[ $aid == local && $v == *+rpt* && " ${PI_WM[*]} " == *" $pkg "* ]] && (( ! USE_WM )); then continue; fi
			# The same for its build of libnma, which serves only its network plugin
			if [[ $aid == local && $v == *+rpt* && $pkg == libnma* ]] && (( ! USE_NETMAN )); then continue; fi
			# Raspberry Pi's builds of these, with their plugins and data, and
			# the magnifier of its plugin, come from the target release only,
			# since they must match each other
			if [[ $x != "$H_SUITE/$arch" && $pkg =~ ^(lxpanel|pcmanfm|libfm|lxplug-|libnma|mage) && $pkg != *-pi ]]; then continue; fi
			[[ $x == "$H_SUITE/$arch" || $a == all ]] || { [[ $a == "$arch" ]] && (( data )); } || continue
			if [[ $aid != local ]] && ! _deps_satisfiable "$d"; then
				[[ -n $skipped ]] || skipped=$v
				continue
			fi
			# The release goes first: tab is an IFS whitespace character, so a
			# final empty Depends field would otherwise shift it when read back
			if [[ -z $best_v ]] || dpkg --compare-versions "$v" gt "$best_v"; then best="${x%/*}"$'\t'"$line" best_v=$v; fi
			break
		done < <(index_candidates "$aid" "${x%/*}" "${x#*/}" "$pkg")
	done
	if [[ -z $best ]]; then
		[[ -n $skipped ]] && warn "$pkg $skipped needs packages that Debian does not provide; no compatible version found"
		return 1
	fi
	IFS=$'\t' read -r s v a f sha z d <<<"$best"
	if [[ -n $skipped ]] && dpkg --compare-versions "$skipped" gt "$v"; then
		warn "$pkg $skipped needs packages that Debian does not provide; using $v"
	fi
	PKG_VER[$pkg]=$v PKG_FILE[$pkg]=$f PKG_SHA[$pkg]=$sha PKG_SIZE[$pkg]=${z:-0}
	PKG_SUITE[$pkg]=$s PKG_AID[$pkg]=$aid
}

# Print a Depends field without the given packages. Usage: drop_deps DEPENDS NAME...
drop_deps() {
	local re
	re=$(printf '%s|' "${@:2}" | sed 's/[.+]/\\&/g')
	tr ',' '\n' <<<"$1" | grep -vE "^[[:space:]]*(${re%|})([[:space:](]|\$)" \
		| sed 's/^[[:space:]]*//' | paste -sd, - | sed 's/,/, /g'
}

# Remove the dependencies that only a Raspberry Pi needs (DEP_DROPS) from a
# package. Prints the path of the package to install.
deps_drop() {
	local deb=$1 drop
	drop=${DEP_DROPS[$(dpkg-deb -f "$deb" Package)]:-}
	[[ -n $drop ]] || { printf '%s\n' "$deb"; return 0; }
	deb_unpack "$deb" debian
	# shellcheck disable=SC2086  # a list of names
	control_set Depends "$(drop_deps "$(dpkg-deb -f "$deb" Depends)" $drop)"
	deb_pack
}

# Download a resolved package, verify it and print its local path. When
# packages/ is refreshed, a file there with the expected checksum is reused.
download_pkg() {
	local pkg=$1 out big=0 base
	out="$WORKDIR/debs/$(basename "${PKG_FILE[$pkg]}")"
	base=$(archive_url "${PKG_AID[$pkg]}" "${PKG_SUITE[$pkg]}")
	mkdir -p "$WORKDIR/debs"
	if [[ ! -f $out && $O_MODE == download && -d $REPO/pool ]]; then
		local old
		old=$(find "$REPO/pool" -type f -name "$(basename "$out")" -print -quit)
		if [[ -n $old ]]; then cp -- "$old" "$out"; fi
	fi
	if [[ -f $out ]] && [[ $(sha256sum "$out" | cut -d' ' -f1) == "${PKG_SHA[$pkg]}" ]]; then
		printf '%s\n' "$out"; return 0
	fi
	(( ${PKG_SIZE[$pkg]:-0} > 5000000 )) && big=1
	if [[ ${PKG_AID[$pkg]} != local ]]; then
		info "Downloading $pkg ${PKG_VER[$pkg]} ($(human_size "${PKG_SIZE[$pkg]}"))"
	fi
	fetch "$base/${PKG_FILE[$pkg]}" "$out" "$big" || die "cannot download $pkg from $base"
	sha256_check "$out" "${PKG_SHA[$pkg]}"
	chmod 0644 "$out"
	printf '%s\n' "$out"
}

# Print the dependency closure of the roots within a Packages index: every
# package reachable through Depends and Pre-Depends, taking the first available
# alternative and resolving virtual packages through Provides. Settings, in the
# environment:
#   BASE=priority  also start from the Debian base system (priority required,
#                  important and standard)
#   INSTALLED=1    skip dependencies that installed packages already satisfy
#   HAVE=FILE      skip dependencies satisfied by the names in FILE
# Usage: _closure INDEX [ROOT]...
_closure() {
	local idx=$1 inst=${HAVE:-/dev/null}; shift
	if [[ ${INSTALLED:-} == 1 ]]; then
		inst=$WORKDIR/installed-names
		dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Provides}\n' 2>/dev/null \
			| awk '$1 ~ /^.i/ { $1 = ""; gsub(/\([^)]*\)|,/, " "); n = split($0, a, " "); for (i = 1; i <= n; i++) print a[i] }' \
			| sort -u >"$inst"
	fi
	ROOTS="$*" INST=$inst awk '
		function resolve(x) { if (x in real) return x; if (x in prov) return prov[x]; return "" }
		function clean(x) { gsub(/\(.*\)/, "", x); sub(/:[a-z0-9]+/, "", x); gsub(/[ \t]/, "", x); return x }
		BEGIN {
			while ((getline line < ENVIRON["INST"]) > 0) have[line] = 1
			RS = ""; FS = "\n"
		}
		{
			n = d = pr = pri = ""
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^Package: /) n = substr($i, 10)
				else if ($i ~ /^(Pre-)?Depends: /) {
					x = $i; sub(/^[^:]*: /, "", x); d = d (d == "" ? "" : ",") x
				}
				else if ($i ~ /^Provides: /) pr = substr($i, 11)
				else if ($i ~ /^Priority: /) pri = substr($i, 11)
			}
			if (n == "" || n in real) next
			real[n] = 1; deps[n] = d; prio[n] = pri
			m = split(pr, a, ","); for (j = 1; j <= m; j++) { v = clean(a[j]); if (v != "" && !(v in prov)) prov[v] = n }
		}
		END {
			if (ENVIRON["BASE"] == "priority") for (p in prio) if (prio[p] ~ /^(required|important|standard)$/) q[++tail] = p
			nr = split(ENVIRON["ROOTS"], r, " "); for (i = 1; i <= nr; i++) { x = resolve(r[i]); if (x != "") q[++tail] = x }
			head = 1
			while (head <= tail) {
				p = q[head++]; if (p in done) continue; done[p] = 1; print p
				c = split(deps[p], alts, ",")
				for (k = 1; k <= c; k++) {
					na = split(alts[k], o, "|"); sat = 0
					for (j = 1; j <= na; j++) if (clean(o[j]) in have) sat = 1
					if (sat) continue
					for (j = 1; j <= na; j++) { x = resolve(clean(o[j])); if (x != "") { if (!(x in done)) q[++tail] = x; break } }
				}
			}
		}' "$idx" | sort -u
}

# Print the names of the dependencies of .deb files, all alternatives included.
_deb_depnames() {
	local f
	for f; do dpkg-deb -f "$f" Pre-Depends Depends 2>/dev/null | sed 's/^[A-Za-z-]*: //'; done \
		| depnames
}

# Succeed if a dependency can be satisfied on the target: by the install set,
# by the APT sources, or, when building packages/, by the Debian index.
_dep_ok() {
	[[ -n ${IN_SET[$1]:-} ]] && return 0
	if [[ -n $DEP_INDEX ]]; then awk -v n="$1" '$1 == n { f = 1; exit } END { exit !f }' "$DEP_INDEX"; else apt_has "$1"; fi
}

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

# Build a package with every file owned by root. dpkg before 1.19 (Debian 9)
# has no option for that, so fakeroot is used. Usage: build_deb DIR OUT [STAMP]
build_deb() {
	local -a cmd=(dpkg-deb --root-owner-group)
	if ! grep -q -- --root-owner-group <<<"$(dpkg-deb --help 2>/dev/null)"; then
		command -v fakeroot >/dev/null || die "fakeroot is required to build packages with this version of dpkg"
		cmd=(fakeroot dpkg-deb)
	fi
	SOURCE_DATE_EPOCH=${3:-$(date +%s)} "${cmd[@]}" -Zxz -b "$1" "$2" >/dev/null || die "cannot build $(basename "$2")"
	chmod 0644 "$2"
}

# Raspberry Pi's file manager replaces Debian's: it has the same program name
# and data files, and Breaks and Replaces pcmanfm. Repack it to run beside
# Debian's as pcmanfm-pi: rename the program and its data directory (the path
# is rewritten in the program, in place), drop those fields, and leave out the
# files that Debian's package already provides (identical toolbar icons, and
# translations of the same message domain). Debian's file manager is not
# changed. Prints the path of the package to install.
fm_coinstall() {
	local deb=$1 n
	local from=/usr/share/pcmanfm/    # the data directory compiled into the program
	local to=/usr/share/pcmanpi/      # of the same length, so it can replace it in place
	[[ $(dpkg-deb -f "$deb" Package) == pcmanfm-pi ]] || { printf '%s\n' "$deb"; return 0; }
	deb_unpack "$deb" beside
	local dir=$R_DIR
	for n in usr/bin/pcmanfm usr/share/applications/pcmanfm.desktop usr/share/man/man1/pcmanfm.1.gz; do
		[[ -f $dir/$n ]] || die "$(basename "$deb") does not contain /$n"
	done
	[[ -d $dir$from ]] || die "$(basename "$deb") does not contain $from"
	grep -qF "$from" "$dir/usr/bin/pcmanfm" || die "$(basename "$deb") does not hold the path $from"
	FROM=$from TO=$to perl -0777 -pe 'BEGIN { binmode STDIN; binmode STDOUT }
		s/\Q$ENV{FROM}\E/$ENV{TO}/g' <"$dir/usr/bin/pcmanfm" >"$dir/usr/bin/pcmanfm-pi"
	chmod 0755 "$dir/usr/bin/pcmanfm-pi"
	rm -f -- "$dir/usr/bin/pcmanfm"
	mv -- "$dir$from" "$dir$to"
	sed -E 's/^(Exec|TryExec)=pcmanfm/\1=pcmanfm-pi/' "$dir/usr/share/applications/pcmanfm.desktop" \
		>"$dir/usr/share/applications/pcmanfm-pi.desktop"
	rm -f -- "$dir/usr/share/applications/pcmanfm.desktop"
	mv -- "$dir/usr/share/man/man1/pcmanfm.1.gz" "$dir/usr/share/man/man1/pcmanfm-pi.1.gz"
	rm -rf -- "${dir:?}/usr/share/locale" "${dir:?}/usr/share/icons" "${dir:?}/etc"
	# Its conffiles and maintainer script concern the files removed above
	rm -f -- "$dir/DEBIAN/conffiles" "$dir/DEBIAN/postinst"
	for n in Breaks Replaces Conflicts Provides; do control_set "$n" ""; done
	deb_pack
}

# Hide the menu entry of Raspberry Pi's Control Centre (rpcc) and Appearance
# Settings (pipanel) in every desktop; the Raspberry Pi Desktop session shows
# its own copy. Prints the path of the package to install.
rpcc_session() {
	local deb=$1 f p
	p=$(dpkg-deb -f "$deb" Package)
	[[ $p == rpcc || $p == pipanel ]] || { printf '%s\n' "$deb"; return 0; }
	deb_unpack "$deb" session
	f=$R_DIR/usr/share/applications/$p.desktop
	if [[ -f $f ]]; then sed -i '/^OnlyShowIn=/d; /^NoDisplay=/d' "$f"; sed -i '$a NoDisplay=true' "$f"; fi
	deb_pack
}

# Succeed if Debian has a package of that name, in a version that satisfies
# OP VERSION when given: in the Debian index when building packages/, else in
# the APT sources. Usage: _debian_has NAME [OP VERSION]
_debian_has() {
	local v
	while read -r v; do
		[[ -z ${2:-} ]] || { [[ $v != - ]] && dpkg --compare-versions "$v" "$2" "$3"; } && return 0
	done < <(if [[ -n $DEP_INDEX ]]; then awk -v n="$1" '$1 == n { print ($2 == "" ? "-" : $2) }' "$DEP_INDEX"
		else apt_versions "$1"; fi)
	return 1
}

# Check that a Raspberry Pi package leaves Debian's alone. It may not replace,
# break, conflict with or stand in for a Debian package (Raspberry Pi's file
# manager is repacked first, see fm_coinstall), except for the builds of
# Debian's panel, file manager and Openbox (PI_STACK, PI_WM) and of libnma that
# are installed in their place. Its maintainer scripts may not edit a file
# under /etc that the package does not ship. Any other such package is
# refused. Prints the path of the package to install; fails for a refused one.
scripts_coinstall() {
	local deb=$1 dir=$WORKDIR/scripts s f n bad="" paths
	# Raspberry Pi's builds of PI_STACK, PI_WM and libnma replace Debian's on purpose.
	# A versioned relation counts only where a Debian version satisfies it.
	stack_deb "$deb" || [[ $(dpkg-deb -f "$deb" Source) == libnma* ]] || for s in Replaces Breaks Conflicts Provides; do
		while read -r n op v; do
			[[ -n $n ]] || continue
			[[ $s != Provides ]] || op="" v=""
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
	return 1
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

# Show the Debian logo wherever the theme shows the Raspberry Pi logo
# (LOGO_ICONS), such as on the menu button: LOGO_BADGE where there is one. The images come from Debian's
# desktop-base, else from the hicolor theme, else from
# /usr/share/pixmaps/debian-logo.png, as in _logo_path. Files are looked for
# under SYS_ROOT; the links point to their paths on the installed system.
# VARIANT -white takes Debian's white logo, for dark themes, and fails if
# Debian has none. Usage: _logo_aliases OUT-DIR [VARIANT]
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
# Debian's white logo, hidden from the appearance settings. Fails without
# the white logo. Usage: gen_logo_overlay NAME LIGHT-SET OUTPUT-DIR
gen_logo_overlay() {
	local name=$1 light=$2 out=$3 d dirs=""
	_logo_aliases "$out" -white || return 1
	for d in "$out"/*/places; do dirs+="${dirs:+,}${d#"$out"/}"; done
	{
		printf '[Icon Theme]\nName=%s\nComment=%s with the white Debian logo\nInherits=%s\nHidden=true\nDirectories=%s\n' \
			"$name" "$light" "$light" "$dirs"
		for d in ${dirs//,/ }; do
			if [[ $d == scalable/* ]]; then printf '\n[%s]\nSize=64\nMinSize=8\nMaxSize=512\nContext=Places\nType=Scalable\n' "$d"
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
	tmp=$(mktemp)
	cat >"$tmp"
	mkdir -p "$(dirname "$1")"
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

# Replace the first <TAG>…</TAG> element of an Openbox or labwc rc.xml with
# CONTENT, or add CONTENT before the closing root tag if there is none.
# Usage: _xml_block FILE TAG CONTENT
_xml_block() {
	T=$2 C=$3 awk '
		BEGIN { t = ENVIRON["T"] }
		!done && $0 ~ "<" t "[ >]" { skip = 1 }
		skip { if ($0 ~ "</" t ">") { print ENVIRON["C"]; skip = 0; done = 1 }; next }
		!done && /<\/(openbox|labwc)_config>/ { print ENVIRON["C"]; done = 1 }
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

# Apply the Raspberry Pi OS Openbox settings (lxde-pi-rc.xml / rpd-rc.xml):
# the <theme> section with the theme's corners and invisible handles, one
# desktop and the focus and placement settings. Usage: _openbox_rc FILE
_openbox_rc() {
	local file=$1 fonts
	fonts=$(_xml_fonts ActiveWindow InactiveWindow MenuHeader MenuItem ActiveOnScreenDisplay InactiveOnScreenDisplay)
	_xml_block "$file" theme "$(printf '  <theme>\n    <name>%s</name>\n    <titleLayout>LIMC</titleLayout>\n    <keepBorder>yes</keepBorder>\n    <roundCorners>%s</roundCorners>\n    <invisibleHandles>yes</invisibleHandles>\n    <animateIconify>yes</animateIconify>\n%s\n  </theme>' "$T_GTK" "$(_ob_round "$T_GTK")" "$fonts")"
	# Use Openbox's own menu when LXDE's is missing
	if [[ ! -f /usr/share/lxde/openbox/menu.xml ]]; then
		sed -i 's#<file>/usr/share/lxde/openbox/menu.xml</file>#<file>menu.xml</file>#' "$file"
	fi
	_xml_child "$file" desktops number 1
	_xml_child "$file" focus focusDesktop yes
	_xml_child "$file" placement monitor Any
	# Windows redraw while being resized; Raspberry Pi OS leaves them blank and
	# unshaped until the mouse is released
	_xml_child "$file" resize drawContents yes
}

# Bind the Openbox keys of Raspberry Pi OS (lxde-pi-rc.xml / rpd-rc.xml) whose
# program is installed: the panel's menu and dialogs, the terminal, the task
# manager and the Shutdown dialog; Ctrl+Alt+L and the lock key of keyboards
# and laptops to lock the screen, the wireless key for the wireless radios and
# the power button (see power_build). A key's existing binding is replaced.
# With RASPBERRY-PI-FILE set, the file is Raspberry Pi OS's own and keeps its
# keys; only the session's own are added. Usage: _openbox_keys RC-XML [RASPBERRY-PI-FILE]
_openbox_keys() {
	local file=$1 k c ctl=lxpanelctl
	local -a keys
	if [[ -n ${2:-} ]]; then
		keys=("C-A-L|$SHARE/power lock" "XF86ScreenSaver|$SHARE/power lock" "XF86WLAN|$SHARE/power wireless-radio"
			"XF86PowerOff|$SHARE/power power-key")
	elif (( S_PI_PANEL )); then
		ctl=lxpanelctl-pi
		keys=("Super_L|$ctl command smenu menu" "C-Escape|$ctl command smenu menu" "A-F2|gui-runcmd"
			"C-A-B|$ctl command bluetooth menu")
	elif (( S_PI_STACK )); then
		# The keys of Raspberry Pi OS 10 to 12, for its build of Debian's panel
		keys=("Super_L|$ctl menu" "C-Escape|$ctl menu" "A-F2|$ctl run"
			"C-A-B|$ctl command bluetooth menu")
	else
		keys=("Super_L|$ctl menu" "C-Escape|$ctl menu" "A-F2|$ctl run")
	fi
	[[ -n ${2:-} ]] || keys+=("C-A-S|$ctl move" "C-A-T|x-terminal-emulator" "C-S-Escape|lxtask" "Print|scrot"
		"C-A-End|pishutdown" "C-A-Delete|pishutdown" "C-A-L|$SHARE/power lock" "XF86ScreenSaver|$SHARE/power lock" "XF86WLAN|$SHARE/power wireless-radio"
		"XF86PowerOff|$SHARE/power power-key")
	# The volume keys and the magnifier, through the panel's plugins
	if [[ -z ${2:-} ]] && (( S_PI_PANEL || S_PI_STACK )); then
		keys+=("XF86AudioRaiseVolume|$ctl command volumepulse volu" "XF86AudioLowerVolume|$ctl command volumepulse vold"
			"XF86AudioMute|$ctl command volumepulse mute" "C-A-M|$ctl command magnifier toggle")
	fi
	[[ -n ${2:-} ]] || ! (( USE_NETMAN )) || keys+=("C-A-W|$ctl command netman menu")
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
	# Remove the keys of Raspberry Pi OS whose program is not installed
	SH=$SHARE awk '
		/<keybind[ >]/ && !inb { blk = $0; inb = 1; if ($0 ~ /<\/keybind>/) { inb = 0; flush() }; next }
		inb { blk = blk "\n" $0; if ($0 ~ /<\/keybind>/) { inb = 0; flush() }; next }
		{ print }
		function flush(  c) {
			if (match(blk, /<command>[^< ]+/)) {
				c = substr(blk, RSTART + 9, RLENGTH - 9)
				if (index(c, ENVIRON["SH"] "/") != 1 && system("command -v \"" c "\" >/dev/null 2>&1") != 0) return
			}
			print blk
		}' "$file" | _write "$file"
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

# Print the parts of the Raspberry Pi OS panel (raspberrypi-ui-mods /
# rpd-x-core) that both panel programs share. Usage: _panel_global [KEY=VALUE]...
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
		"$fm" "$(_launcher x-terminal-emulator.desktop lxterminal.desktop lxde-x-terminal-emulator.desktop)"; do
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
# rpd-x-core defines it (see _pi_layout), or the built-in Raspberry Pi OS 13
# layout if that package is unavailable.
_pi_panel_layout() {
	local f
	if f=$(pi_unpack "$PANEL_PKG" "$(config_suite)" "$H_ARCH" 2>/dev/null) && f+=/etc/xdg/lxpanel-pi/panels/panel && [[ -f $f ]]; then
		_pi_layout "$f" lxpanel-pi
	else
		_pi_panel_builtin
	fi
}
# The same before Raspberry Pi OS 13, for Raspberry Pi's build of Debian's
# panel (PI_STACK), from this release's raspberrypi-ui-mods, or the Debian
# panel layout if that package is unavailable.
_pi_stack_layout() {
	local f
	if f=$(_pi_stack_file etc/xdg/lxpanel/LXDE-pi/panels/panel); then _pi_layout "$f" lxpanel/plugins; else _lxpanel_layout; fi
}
# Print the path of a file in this release's raspberrypi-ui-mods (Raspberry
# Pi OS's settings before 13); fail if it is missing. Usage: _pi_stack_file PATH
_pi_stack_file() {
	local x
	x=$(pi_unpack raspberrypi-ui-mods "$H_SUITE" "$H_ARCH" 2>/dev/null) && [[ -f $x/$1 ]] && printf '%s\n' "$x/$1"
}

# Print a Raspberry Pi OS panel layout with its spaces and separators, so that
# later releases' layouts are followed. Removed, keeping their spaces as on
# Raspberry Pi OS: plugins left out (panel_drop), the magnifier (for the user
# to add), plugins not installed and, without a battery, the battery plugin.
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
	T=$(_launcher x-terminal-emulator.desktop lxterminal.desktop lxde-x-terminal-emulator.desktop || true) awk '
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

# Print the Raspberry Pi OS 13 panel (rpd-x-core) for when that package
# cannot be read: the same plugins in the same order.
_pi_panel_builtin() {
	local p
	_panel_global point_at_menu=0
	_panel_plugin smenu
	_panel_plugin separator
	_panel_tasks
	_panel_plugin ejecter
	for p in bluetooth tray volumepulse clock batt; do _panel_plugin space Size=2; _panel_plugin "$p"; done
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

# Print the Raspberry Pi OS package that holds the menu and application
# entries for the session's release, followed by the release to fetch it from.
menu_pkg() { if suite_ge "$H_SUITE" trixie; then echo "$ART_PKG $(config_suite)"; else echo "raspberrypi-ui-mods $H_SUITE"; fi; }

# Write the Raspberry Pi OS application menu from this release's package, so
# that later releases' changes are followed: the menu file, its category
# names and the application entries it renames or moves (raspi-ui-overrides),
# for installed applications only. Debian's settings tools, which Raspberry
# Pi OS hides in favour of its Control Centre, stay shown, as Debian lacks
# that. Without the package, the built-in menu
# is written. Usage: _session_menu XDG-DIR DATA-DIR
_session_menu() {
	local xdg=$1 data=$2 prefix x f
	prefix=$(menu_prefix)
	# shellcheck disable=SC2046  # package and release
	x=$( (pi_unpack $(menu_pkg) "$H_ARCH") 2>/dev/null ) || x=""
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
		# The category's id without the menu prefix: the session's (lxde-pi-,
		# rpd-) or LXDE's (lxde-help.directory in Raspberry Pi OS's own menu)
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
	prefix=$(menu_prefix)
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
_wallpaper_path() {
	local w=/usr/share/rpd-wallpaper/$T_WALL_DEFAULT
	if [[ -f $w ]]; then printf '%s\n' "$w"; else warn "Wallpaper $w not found; the desktop shows its background colour."; fi
}

# Write the session's lxsession profile: Raspberry Pi OS's desktop.conf with
# the chosen theme, and the autostart list. Usage: _session_profile XDG-DIR
_session_profile() {
	local dir=$1/lxsession/$S_PROFILE ctl=lxpanelctl images=1 fm=pcmanfm
	(( S_PI_PANEL )) && ctl=lxpanelctl-pi
	(( S_PI_FM )) && fm=pcmanfm-pi
	# Raspberry Pi OS turns menu images off, and Raspberry Pi's panels show
	# menu icons regardless; Debian's panel shows them only when it is on
	(( S_PI_PANEL || S_PI_STACK )) && images=0
	{
		# LXDE's authentication agent, as in Raspberry Pi OS's X session
		printf '[Session]\nwindow_manager=%s/openbox\ndisable_autostart=no\npolkit/command=lxpolkit\n' "$SHARE"
		printf 'clipboard/command=lxclipboard\nxsettings_manager/command=build-in\nproxy_manager/command=build-in\n'
		printf 'keyring/command=ssh-agent\nquit_manager/command=lxsession-logout\n'
		printf 'quit_manager/image=/usr/share/lxde/images/logout-banner.png\nquit_manager/layout=top\n'
		printf 'lock_manager/command=%s/power lock\nterminal_manager/command=x-terminal-emulator\nlauncher_manager/command=%s\n' "$SHARE" "$ctl"
		# The session's own applications that lxsession starts only on request,
		# for its settings window; those it starts at login are left empty
		printf 'file_manager/command=%s\nwebbrowser/command=x-www-browser\n' "$fm"
		# LXDE's task manager, which Debian's LXDE desktop installs
		if command -v lxtask >/dev/null; then printf 'tasks/command=lxtask\n'; fi
		printf '\n'
		printf '[GTK]\nsNet/ThemeName=%s\nsNet/IconThemeName=%s\nsGtk/FontName=%s\n' "$T_GTK" "$T_ICONS" "$T_FONT"
		printf 'iGtk/ToolbarStyle=3\niGtk/ButtonImages=0\niGtk/MenuImages=%s\niGtk/CursorThemeSize=%s\n' "$images" "$T_CURSOR_SIZE"
		printf 'iXft/Antialias=1\niGtk/AutoMnemonics=1\niGtk/EnableMnemonics=1\nsGtk/ColorScheme=%s\n' "$(color_scheme)"
		printf 'sGtk/CursorThemeName=%s\niGtk/ToolbarIconSize=3\nsGtk/IconSizes=gtk-large-toolbar=%s,%s\n' "$T_ICONS" "$T_TB_ICON" "$T_TB_ICON"
		printf 'sNet/SoundThemeName=%s\niNet/EnableEventSounds=1\niNet/EnableInputFeedbackSounds=1\n' "$T_SOUND_THEME"
		printf 'iXft/Hinting=1\nsXft/HintStyle=hintfull\nsXft/RGBA=rgb\n\n'
		printf '[Mouse]\nAccFactor=20\nAccThreshold=10\nLeftHanded=0\n\n[Keyboard]\nDelay=500\nInterval=30\nBeep=1\n\n'
		printf '[State]\nguess_default=true\n\n[Dbus]\nlxde=true\n\n[Environment]\nmenu_prefix=%s\n' "$(menu_prefix)"
	} | _write "$dir/desktop.conf"
	{
		# The session's power helper in place of Raspberry Pi OS's xscreensaver
		printf '@%s/panel\n@%s/desktop\n@%s/power\n@%s/popup-keeper\n' "$SHARE" "$SHARE" "$SHARE" "$SHARE"
	} | _write "$dir/autostart"
}

# Write Raspberry Pi OS's desktop and file manager settings (pcmanfm.conf,
# desktop-items, libfm.conf): for Debian's file manager under the session's
# profile, and for Raspberry Pi's, which reads the 'default' profile.
# Usage: _session_files XDG-DIR
_session_files() {
	local xdg=$1 d i f src
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
		if (( S_PI_STACK )) && [[ $d != */default ]] && src=$(_pi_stack_file etc/xdg/pcmanfm/LXDE-pi/pcmanfm.conf); then
			# Raspberry Pi OS's own settings for its build, without gksu,
			# which Debian lacks, and its Appearance Settings where missing
			if command -v pipanel >/dev/null; then grep -v '^su_cmd=' "$src"; else grep -vE '^(su_cmd|prefs_app)=' "$src"; fi \
				| _write "$f"
		else
			_ini_set "$f" config bm_open_method 0
			_ini_set "$f" volume mount_on_startup 0 mount_removable 0 autorun 0
			_ini_set "$f" ui always_show_tabs 0 max_tab_chars 32 win_width 640 win_height 480 splitter_pos 150 \
				view_mode icon show_hidden 0 sort "name;ascending;" columns "name;size;mtime;" \
				toolbar "newtab;navigation;home;" show_statusbar 1 pathbar_mode_buttons 0
			[[ $d == */default ]] || _ini_set "$f" ui side_pane_mode places
		fi
		_ini_set "$f" desktop desktop_bg "$T_DESK_BG" desktop_fg "$T_DESK_FG" desktop_shadow "$T_DESK_SHADOW" \
			show_wm_menu 0 wallpaper_mode crop wallpaper "$S_WALL"
		if [[ $d == */default ]]; then
			# Raspberry Pi's file manager keeps here what Debian's keeps in
			# libfm.conf: menus, side pane and icon sizes
			_fm_shared_conf "$f"
			_ini_set "$f" config terminal "x-terminal-emulator %s"
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
# Raspberry Pi OS keeps them in raspi-ui-overrides: Debian Reference in the
# Help menu, Raspberry Pi's file manager as "File Manager" for folders and
# Desktop Preferences, the appearance settings with the session's themes, and
# hidden Blueman windows and tray applets that Raspberry Pi OS does not show.
# Usage: _session_entries XDG-DIR DATA-DIR
_session_entries() {
	local xdg=$1 apps=$2/applications f id
	f=/usr/share/applications/debian-reference-common.desktop
	if [[ -f $f && ! -f $apps/${f##*/} ]]; then
		awk '/^Categories=/ { print "Categories=Help;"; found = 1; next } { print }
			END { if (!found) print "Categories=Help;" }' "$f" | _write "$apps/${f##*/}"
	fi
	if (( S_PI_FM )); then
		# Raspberry Pi's file manager entry, run as pcmanfm-pi on Debian;
		# Debian's entry is hidden in the session
		f=$apps/pcmanfm.desktop
		[[ -f $f ]] || f=/usr/share/applications/pcmanfm-pi.desktop
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
	# Appearance settings: the Control Centre on Wayland, as in Raspberry Pi
	# OS 13; on X, Raspberry Pi's Appearance Settings (pipanel) where it is
	# installed (Raspberry Pi OS 10 to 12), else Customize Look and Feel
	f=/usr/share/applications/rpcc.desktop
	[[ ! -f $f ]] || { sed '/^NoDisplay=/d; /^OnlyShowIn=/d' "$f"; echo 'OnlyShowIn=labwc;'; } | _write "$apps/rpcc.desktop"
	f=/usr/share/applications/pipanel.desktop
	if [[ -f $f ]]; then
		{ sed '/^NoDisplay=/d; /^OnlyShowIn=/d' "$f"; echo 'OnlyShowIn=LXDE;'; } | _write "$apps/pipanel.desktop"
		f=/usr/share/applications/lxappearance.desktop
		[[ ! -f $f ]] || { sed '/^NoDisplay=/d' "$f"; echo 'NoDisplay=true'; } | _write "$apps/lxappearance.desktop"
		f=""
	else
		f=$apps/lxappearance.desktop
		[[ -f $f ]] || f=/usr/share/applications/lxappearance.desktop
	fi
	if [[ -n $f && -f $f ]]; then
		sed -E "s|^Exec=.*|Exec=$SHARE/appearance|; /^TryExec=/d; /^NoDisplay=/d; /^OnlyShowIn=/d" "$f" \
			| { cat; echo 'OnlyShowIn=LXDE;'; } | _write "$apps/lxappearance.desktop"
	fi
	# Hide Blueman's windows where Raspberry Pi's panel has its Bluetooth plugin:
	# opening one would start a second Bluetooth icon and pairing agent
	if (( S_PI_PANEL || S_PI_STACK )); then
		for f in /usr/share/applications/blueman-manager.desktop /usr/share/applications/blueman-adapters.desktop; do
			[[ ! -f $f ]] || { sed '/^NoDisplay=/d' "$f"; echo 'NoDisplay=true'; } | _write "$apps/${f##*/}"
		done
	fi
	# Hide clipboard managers and other volume applets, which Raspberry Pi OS
	# lacks; screen lockers, screensavers and power managers, as the sessions
	# run their own power helper (power_build); the Bluetooth applet where
	# Raspberry Pi's panel has its own plugin; nm-applet where its network
	# plugin is used; and the authentication agents, as the sessions start
	# their own (polkit_agent). A user can enable them again in Desktop
	# Session Settings.
	local -a pats=(volumeicon pasystray pnmixer diodon clipit parcellite
		light-locker xscreensaver xss-lock xautolock gnome-screensaver mate-screensaver
		xfce4-power-manager mate-power-manager lxqt-powermanagement
		polkit-gnome-authentication-agent polkit-mate xfce-polkit lxpolkit)
	(( S_PI_PANEL || S_PI_STACK )) && pats+=(blueman)
	(( USE_NETMAN )) && pats+=(nm-applet)
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
	local data=$1 t src f n
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
			# square, as Raspberry Pi OS's X11 session does from Bullseye on.
			# On Wayland, and with GTK 3.24.5 (Debian 10, as on Buster), they
			# are "csd" and stay rounded.
			printf 'tooltip:not(.csd), .tooltip:not(.csd) { border-radius: 0px; }\n'
		} | _write "$data/themes/$t/gtk-3.0/gtk.css"
		# Openbox reads the hover image of a toggled title bar button from
		# "<button>_toggled_hover.xbm", but the official themes name it
		# "<button>_hover_toggled.xbm"; without a link, the maximise button
		# of a maximised window would not change on hover.
		[[ -f $src/openbox-3/themerc ]] || continue
		mkdir -p "$data/themes/$t/openbox-3"
		for f in "$src"/openbox-3/*; do
			n=${f##*/}
			ln -sfn "/usr/share/themes/$t/openbox-3/$n" "$data/themes/$t/openbox-3/$n"
			[[ $n != *_hover_toggled* ]] || ln -sfn "/usr/share/themes/$t/openbox-3/$n" "$data/themes/$t/openbox-3/${n/_hover_toggled/_toggled_hover}"
		done
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

# Write the sessions' programs: the shared session-env and the X start
# script, modelled on Raspberry Pi OS's startx-rpd and Debian's startlxde;
# panel and desktop wrappers that run Raspberry Pi's program where installed
# and wanted, else Debian's, so a session keeps working when one is removed;
# and the appearance settings wrapper, which lists the session's themes.
# Usage: _session_programs ROOT
_session_programs() {
	local root=$1 pcm="" f img
	# Raspberry Pi's file manager runs as "pcmanfm" in the session, as on
	# Raspberry Pi OS, whose Appearance Settings call it by that name
	if (( S_PI_FM )); then
		# shellcheck disable=SC2016  # written as is, for session-env
		pcm='export PATH="$share/bin:$PATH"'
		printf '#!/bin/sh\nif command -v pcmanfm-pi >/dev/null; then exec pcmanfm-pi "$@"; fi\nexec /usr/bin/pcmanfm "$@"\n' | _write "$root$SHARE/bin/pcmanfm"
		chmod 0755 "$root$SHARE/bin/pcmanfm"
	fi
	cat <<EOF | _write "$root$SHARE/session-env"
# The environment and helpers of both Raspberry Pi Desktop sessions, written
# by $APP_NAME. Only these sessions put $SHARE first in the XDG paths.
profile=$S_PROFILE
# Raspberry Pi OS's names for Openbox's settings file and the file manager profile
obfile=$(ob_file)
fmprofile=$S_FM_PROFILE
share=$SHARE
config=\${XDG_CONFIG_HOME:-\$HOME/.config}
# The user's own data for these sessions: marker files and saved originals
own=\${XDG_DATA_HOME:-\$HOME/.local/share}/$APP_NAME
# The application entries the session tidies at login (menu_tidy)
menu=\${XDG_RUNTIME_DIR:-\$HOME/.cache}/$APP_NAME-menu
export XDG_CONFIG_DIRS="\$share/xdg:\${XDG_CONFIG_DIRS:-/etc/xdg}"
export XDG_DATA_DIRS="\$share/data:\$menu:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XDG_MENU_PREFIX=$(menu_prefix)
export FONTCONFIG_FILE=\$share/fonts.conf
[ ! -f "\$share/dconf/profile" ] || export DCONF_PROFILE=\$share/dconf/profile
export SAL_USE_VCLPLUGIN=gtk3
export QT_QPA_PLATFORMTHEME=gtk3
$pcm

# Create the Desktop folder if it is missing
if [ -e "\$config/user-dirs.dirs" ]; then . "\$config/user-dirs.dirs"; fi
mkdir -p "\${XDG_DESKTOP_DIR:-\$HOME/Desktop}"
EOF
	cat <<'EOF' >>"$root$SHARE/session-env"

# Show each installed application once in the menu. The menu shows an
# application in each of its categories (Settings is Preferences, System is
# System Tools, Utility is Accessories, ...); one whose entry names several
# of them keeps the first in this order, as Raspberry Pi OS tidies the
# applications it ships (raspi-ui-overrides). The tidied copies go to the
# session's runtime folder, which the menu reads before Debian's entries;
# Debian's files are not changed, and the session's own entries are kept.
menu_tidy() {
	rm -rf "$menu"
	mkdir -p "$menu/applications" || return 0
	set -- /usr/share/applications/*.desktop
	[ -e "$1" ] || return 0
	awk -v out="$menu/applications" -v own="$share/data/applications" '
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
# Keep the user's own FILE under $config (or a mark that there was none)
# before the session first changes it, so that --uninstall gives it back.
# Usage: keep_orig FILE
keep_orig() {
	k=$own/orig/${1#"$config"/}
	[ -e "$k" ] || [ -e "$k.none" ] || {
		mkdir -p "${k%/*}"
		if [ -f "$1" ]; then cp -p "$1" "$k"; else : >"$k.none"; fi
	}
}
# Create the user's xsettingsd.conf (XSETTINGS for X applications on
# Wayland), the file Appearance Settings writes, if it is missing.
xsettings_file() {
	xs=$config/xsettingsd/xsettingsd.conf
	keep_orig "$xs"
	[ ! -f "$xs" ] || return 0
	mkdir -p "${xs%/*}"
	cp "$share/xsettingsd.conf" "$xs"
}

# Apply the user's look (rpios-look-set) to the Wayland session: labwc's
# theme, title font and cursor, XSETTINGS and GSettings, written as
# Appearance Settings writes them.
wayland_look() {
	lxs=$config/lxsession/$profile/desktop.conf
	[ -f "$lxs" ] || return 0
	v() { sed -n "s|^$1=||p" "$lxs" | head -n1; }
	theme=$(v sNet/ThemeName) icons=$(v sNet/IconThemeName) font=$(v sGtk/FontName)
	cursor=$(v sGtk/CursorThemeName) csize=$(v iGtk/CursorThemeSize) scheme=$(v sGtk/ColorScheme)
	case $theme in PiXnoir|PiXonyx) cs=prefer-dark ;; *) cs=default ;; esac
	# Window frames and title font, taken from the X session's Openbox file
	ob=$config/openbox/$obfile
	[ -f "$ob" ] || ob=$share/openbox-rc.xml
	win=$(sed -n '/<theme>/,/<\/theme>/{/<font /,/<\/font>/b;s|.*<name>\([^<]*\)</name>.*|\1|p}' "$ob" | head -n1)
	tfont=$(sed -n '/<theme>/,/<\/theme>/{/<font /,/<\/font>/{s|.*<name>\([^<]*\)</name>.*|\1|p}}' "$ob" | head -n1)
	tsize=$(sed -n '/<theme>/,/<\/theme>/{/<font /,/<\/font>/{s|.*<size>\([^<]*\)</size>.*|\1|p}}' "$ob" | head -n1)
	tweight=$(sed -n '/<theme>/,/<\/theme>/{/<font /,/<\/font>/{s|.*<weight>\([^<]*\)</weight>.*|\1|p}}' "$ob" | head -n1)
	# Set the theme name and fonts in the user's labwc rc.xml, keeping other settings
	lrc=$config/labwc/rc.xml
	keep_orig "$lrc"
	if [ ! -f "$lrc" ]; then
		mkdir -p "${lrc%/*}"
		printf '<?xml version="1.0"?>\n<labwc_config>\n  <theme>\n  </theme>\n</labwc_config>\n' >"$lrc"
	fi
	grep -q '<theme>' "$lrc" || sed -i 's|</labwc_config>|  <theme>\n  </theme>\n</labwc_config>|' "$lrc"
	fonts=$(for p in ActiveWindow InactiveWindow OnScreenDisplay MenuItem; do
		printf '    <font place="%s">\n      <name>%s</name>\n      <size>%s</size>\n      <weight>%s</weight>\n    </font>\n' \
			"$p" "${tfont:-Piboto}" "${tsize:-12}" "${tweight:-Normal}"
	done)
	N=${win:-$theme} F=$fonts awk '
		/<theme>/ { t = 1; print; print "    <name>" ENVIRON["N"] "</name>"; next }
		t && /<font[ >]/ { f = 1 }
		t && f { if (/<\/font>/) f = 0; next }
		t && /<name>/ { next }
		t && /<\/theme>/ { print ENVIRON["F"]; t = 0 }
		{ print }' "$lrc" >"$lrc.new" && mv -f "$lrc.new" "$lrc"
	# labwc's own cursor comes from its environment file; the user's file
	# starts as a copy of the session's
	lenv=$config/labwc/environment
	keep_orig "$lenv"
	if [ -n "$cursor" ]; then
		[ -f "$lenv" ] || cp "$share/xdg/labwc/environment" "$lenv" 2>/dev/null || : >"$lenv"
		T=$cursor S=${csize:-24} awk '
			/^XCURSOR_THEME=/ { if (!t) print "XCURSOR_THEME=" ENVIRON["T"]; t = 1; next }
			/^XCURSOR_SIZE=/ { if (!s) print "XCURSOR_SIZE=" ENVIRON["S"]; s = 1; next }
			{ print }
			END { if (!t) print "XCURSOR_THEME=" ENVIRON["T"]; if (!s) print "XCURSOR_SIZE=" ENVIRON["S"] }' "$lenv" >"$lenv.new" \
			&& mv -f "$lenv.new" "$lenv"
	fi
	# X applications (Xwayland); values are escaped for sed
	xsettings_file
	e() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }
	sed -i -e "s|^Net/ThemeName .*|Net/ThemeName \"$(e "$theme")\"|" -e "s|^Net/IconThemeName .*|Net/IconThemeName \"$(e "$icons")\"|" \
		-e "s|^Gtk/CursorThemeName .*|Gtk/CursorThemeName \"$(e "$cursor")\"|" -e "s|^Gtk/CursorThemeSize .*|Gtk/CursorThemeSize ${csize:-24}|" \
		-e "s|^Gtk/FontName .*|Gtk/FontName \"$(e "$font")\"|" -e "s|^Gtk/ColorScheme .*|Gtk/ColorScheme \"$(e "$scheme")\"|" "$xs"
	# GTK's animations: the user's choice (rpios-look-set --animations), else GTK's own
	anim=$(v iGtk/EnableAnimations)
	sed -i '/^Gtk\/EnableAnimations /d' "$xs"
	[ -z "$anim" ] || echo "Gtk/EnableAnimations $anim" >>"$xs"
	# Wayland applications (GSettings, in the session's own database)
	if command -v dconf >/dev/null; then
		for kv in "gtk-theme='$theme'" "icon-theme='$icons'" "cursor-theme='$cursor'" "cursor-size=${csize:-24}" \
			"font-name='$font'" "document-font-name='$font'" "color-scheme='$cs'"; do
			dconf write "/org/gnome/desktop/interface/${kv%%=*}" "${kv#*=}" 2>/dev/null || true
		done
		case $anim in
			0) dconf write /org/gnome/desktop/interface/enable-animations false ;;
			1) dconf write /org/gnome/desktop/interface/enable-animations true ;;
			*) dconf reset /org/gnome/desktop/interface/enable-animations ;;
		esac 2>/dev/null || true
	fi
}
EOF
	cat <<'EOF' | _write "$root$SHARE/start"
#!/bin/sh
# The Raspberry Pi Desktop session on X.
. /usr/share/rpios-look/session-env
menu_tidy
export XDG_CURRENT_DESKTOP=LXDE
# Raspberry Pi OS's session name (LXDE-pi, rpd-x), where its own tools, such
# as Appearance Settings, read the session's settings
export DESKTOP_SESSION=$profile

# Openbox reads only the user's own file. It receives the session's defaults,
# also after they change, until the user edits it.
rc=$config/openbox/$obfile seen=$config/openbox/.$obfile.rpios-look
if [ ! -e "$rc" ] || cmp -s "$rc" "$seen" 2>/dev/null; then
	mkdir -p "$config/openbox" && cp "$share/openbox-rc.xml" "$rc" && cp "$share/openbox-rc.xml" "$seen"
elif ! cmp -s "$share/openbox-rc.xml" "$seen" 2>/dev/null; then
	# The user's copy has their own changes, and the session's settings
	# changed since (an update): take the session's key bindings, keep the rest
	awk 'FNR == NR { if (/<keyboard>/) k = 1; if (k) kb = kb $0 "\n"; if (/<\/keyboard>/) k = 0; next }
		/<keyboard>/ { if (kb != "") { printf "%s", kb; skip = 1; next } }
		skip { if (/<\/keyboard>/) skip = 0; next }
		{ print }' "$share/openbox-rc.xml" "$rc" >"$rc.new" && cat "$rc.new" >"$rc"
	rm -f "$rc.new"
	cp "$share/openbox-rc.xml" "$seen"
fi

# lxsession reads the user's copy of the start list once there is one: an
# empty copy would start nothing (no panel, no desktop), so it is removed.
if [ -f "$config/lxsession/$profile/autostart" ] && [ ! -s "$config/lxsession/$profile/autostart" ]; then
	rm -f "$config/lxsession/$profile/autostart"
fi
lxs=$config/lxsession/$profile/desktop.conf

# Window frames and corners follow the theme. Use Openbox's own menu when
# LXDE's is missing.
theme=$(sed -n 's/^sNet\/ThemeName=//p' "$lxs" "$share/xdg/lxsession/$profile/desktop.conf" 2>/dev/null | head -n1)
same=0; cmp -s "$rc" "$seen" 2>/dev/null && same=1
case $theme in
	PiX|PiXflat|PiXnoir|PiXtrix|PiXonyx)
		# Rounded corners unless the theme's border.radius is 0
		r=yes
		case $(sed -n 's/^border\.radius:[[:space:]]*//p' "/usr/share/themes/$theme/openbox-3/themerc" 2>/dev/null | head -n1) in ''|0) r=no ;; esac
		grep -q "<name>$theme</name>" "$rc" && grep -q "<roundCorners>$r</roundCorners>" "$rc" \
			|| sed -i --follow-symlinks -e "/<theme>/,/<\/theme>/ s|<name>PiX[a-z]*</name>|<name>$theme</name>|" \
			-e "/<theme>/,/<\/theme>/ s|<roundCorners>[^<]*</roundCorners>|<roundCorners>$r</roundCorners>|" "$rc" ;;
esac
if [ ! -f /usr/share/lxde/openbox/menu.xml ] && grep -q '<file>/usr/share/lxde/openbox/menu.xml</file>' "$rc"; then
	sed -i --follow-symlinks 's#<file>/usr/share/lxde/openbox/menu.xml</file>#<file>menu.xml</file>#' "$rc"
fi
[ "$same" = 0 ] || cp "$rc" "$seen"

# Clean up after GDM, which sets the number of desktops to one
xprop -root -remove _NET_NUMBER_OF_DESKTOPS -remove _NET_DESKTOP_NAMES -remove _NET_CURRENT_DESKTOP 2>/dev/null

# Start D-Bus if needed
if command -v dbus-launch >/dev/null && [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
	if [ -z "$XDG_RUNTIME_DIR" ] || [ ! -S "$XDG_RUNTIME_DIR/bus" ] || [ ! -O "$XDG_RUNTIME_DIR/bus" ]; then
		eval "$(dbus-launch --sh-syntax --exit-with-session)"
	fi
fi

# Remove the variables an earlier Wayland login left for programs started by D-Bus
if command -v systemctl >/dev/null; then
	systemctl --user unset-environment WAYLAND_DISPLAY 2>/dev/null
	systemctl --user set-environment XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=LXDE 2>/dev/null
fi

/usr/bin/lxsession -s "$profile" -e LXDE
# lxsession's SSH agent outlives the logout and keeps the login session open
# (the login screen would show the user as logged in): end this session's one
s=$(cat /proc/self/sessionid 2>/dev/null)
for p in $(pgrep -u "$(id -u)" -x ssh-agent); do
	[ -n "$s" ] && [ "$p" != "$PPID" ] && [ "$(cat "/proc/$p/sessionid" 2>/dev/null)" = "$s" ] && kill "$p" 2>/dev/null
done
exit 0
EOF
	printf '#!/bin/sh\nexec openbox --config-file "${XDG_CONFIG_HOME:-$HOME/.config}/openbox/%s" "$@"\n' "$(ob_file)" \
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
		(( S_PI_FM )) && printf 'if command -v pcmanfm-pi >/dev/null; then exec pcmanfm-pi --desktop --profile %s; fi\n' "$S_FM_PROFILE"
		# Debian's file manager draws no desktop on Wayland: swaybg draws the
		# wallpaper, or the colour alone without one
		img=""
		[[ -z $S_WALL ]] || img=" -i \"$S_WALL\""
		printf 'if [ -n "$WAYLAND_DISPLAY" ]; then exec swaybg -m fill -c "%s"%s; fi\n' "#${T_DESK_BG:1:2}${T_DESK_BG:5:2}${T_DESK_BG:9:2}" "$img"
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
	exec env XDG_DATA_DIRS=$run/rpios-look-appearance/share GTK_DATA_PREFIX=$run/rpios-look-appearance lxappearance "$@"
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

# Write the sessions' GSettings defaults, which GTK reads on Wayland and GTK 4
# reads for its light or dark style, as a separate dconf database
# (DCONF_PROFILE): the user's settings still win, and other sessions never
# read it.
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
document-font-name='$T_FONT'
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
EOF
	if ! command -v dconf >/dev/null || ! dconf compile "$root$SHARE/dconf/settings" "$dir"; then
		warn "dconf is missing: the sessions start without their GSettings defaults (install dconf-cli and run this again)."
		return 0
	fi
	# A separate user database keeps other desktops' settings apart (named
	# without "-", which D-Bus does not allow)
	printf 'user-db:%s\nfile-db:%s/dconf/settings\n' "${APP_NAME//-/}" "$SHARE" | _write "$root$SHARE/dconf/profile"
}

# Write the Raspberry Pi Desktop session on Wayland, as in Raspberry Pi OS 13
# (rpd-wayland-core): labwc with Raspberry Pi OS's window settings and keys,
# wf-panel-pi in its layout, the desktop, display settings (kanshi) and
# XSETTINGS for X applications (xsettingsd). The keyboard layout is the
# system's; keys and panel plugins that need Raspberry Pi tools are left out.
# Usage: _session_wayland ROOT
_session_wayland() {
	local root=$1 xdg=$1$SHARE/xdg x rc browser term fm=pcmanfm
	x=$( (pi_unpack "$WAYLAND_PKG" "$(config_suite)" "$H_ARCH") 2>/dev/null ) || x=""
	(( S_PI_FM )) && fm=pcmanfm-pi
	browser=$(_browser || true)
	term=$(_launcher x-terminal-emulator.desktop lxterminal.desktop || true)
	rc=$xdg/labwc/rc.xml
	if [[ -f $x/etc/xdg/labwc/rc.xml ]]; then _write "$rc" <"$x/etc/xdg/labwc/rc.xml"
	else printf '<?xml version="1.0"?>\n<labwc_config>\n  <keyboard>\n  </keyboard>\n</labwc_config>\n' | _write "$rc"; fi
	_labwc_rc "$rc"
	# Ctrl+Alt+L and the lock key lock the screen; the wireless key switches
	# the wireless radios; the power button runs the session's helper in place
	# of Raspberry Pi OS's pwrkey, on release as there (see power_build), and
	# the terminal key Debian's terminal, as Debian's labwc lacks Raspberry Pi's
	# lab-sensible-terminal
	P="$SHARE/power" awk '
		{ pk += gsub(/command="pwrkey"/, "command=\"" ENVIRON["P"] " power-key\"")
		  gsub(/command="lab-sensible-terminal"/, "command=\"x-terminal-emulator\"") }
		!done && /<\/keyboard>/ {
			n = split("C-A-l=lock XF86ScreenSaver=lock XF86WLAN=wireless-radio", k, " ")
			for (i = 1; i <= n; i++) {
				split(k[i], b, "=")
				print "    <keybind key=\"" b[1] "\">\n      <action name=\"Execute\" command=\"" ENVIRON["P"] " " b[2] "\" />\n    </keybind>"
			}
			if (!pk) print "    <keybind key=\"XF86PowerOff\" onRelease=\"yes\">\n      <action name=\"Execute\" command=\"" ENVIRON["P"] " power-key\" />\n    </keybind>"
			done = 1
		}
		{ print }' "$rc" | _write "$rc"
	# Remove key bindings whose program is not installed; the session's own
	# helpers are installed with it
	SH=$SHARE awk '
		/<keybind[ >]/ { blk = $0; inb = 1; if ($0 ~ /<\/keybind>/) { inb = 0; flush() }; next }
		inb { blk = blk "\n" $0; if ($0 ~ /<\/keybind>/) { inb = 0; flush() }; next }
		{ print }
		function flush(  c) {
			if (match(blk, /command="[^" ]+/)) {
				c = substr(blk, RSTART + 9, RLENGTH - 9)
				if (index(c, ENVIRON["SH"] "/") != 1 && system("command -v \"" c "\" >/dev/null 2>&1") != 0) return
			}
			print blk
		}' "$rc" | _write "$rc"
	printf 'QT_WAYLAND_DISABLE_WINDOWDECORATION=1\nXCURSOR_THEME=%s\nXCURSOR_SIZE=%s\nLABWC_FALLBACK_OUTPUT=NOOP-1\n' \
		"$T_ICONS" "$T_CURSOR_SIZE" | _write "$xdg/labwc/environment"
	{
		printf '%s/respawn %s/desktop &\n' "$SHARE" "$SHARE"
		printf '%s/respawn wf-panel-pi &\n' "$SHARE"
		command -v kanshi >/dev/null && printf 'kanshi &\n'
		# shellcheck disable=SC2016  # written as is, for the autostart file
		command -v xsettingsd >/dev/null \
			&& printf 'xsettingsd -c "${XDG_CONFIG_HOME:-$HOME/.config}/xsettingsd/xsettingsd.conf" &\n'
		printf '%s &\n' "$(polkit_agent)"
		printf '%s/respawn %s/power &\n' "$SHARE" "$SHARE"
		printf 'lxsession-xdg-autostart\n'
	} | _write "$xdg/labwc/autostart"
	{
		printf '<openbox_menu>\n  <menu id="root-menu">\n'
		printf '    <item label="Desktop Preferences...">\n      <action name="Execute" command="%s --desktop-pref" />\n    </item>\n' "$fm"
		printf '  </menu>\n</openbox_menu>\n'
	} | _write "$xdg/labwc/menu.xml"
	# The panel: Raspberry Pi OS's layout without the plugins that need its
	# tools or the magnifier (see _pi_layout), with the launchers installed
	# here. wf-panel-pi reads only this path, and no other program reads it.
	if [[ -f $x/etc/xdg/wf-panel-pi/wf-panel-pi.ini ]]; then
		DROP="$(wf_drop)|magnifier" B=${browser%.desktop} T=${term%.desktop} FM=$fm awk '
			/^widgets_(left|right)=/ {
				n = split(substr($0, index($0, "=") + 1), w, " "); m = 0; out = ""
				for (i = 1; i <= n; i++) {
					if (w[i] ~ "^(" ENVIRON["DROP"] ")$") continue
					o[++m] = w[i]
				}
				for (i = 1; i <= m; i++) out = out (i > 1 ? " " : "") o[i]
				print substr($0, 1, index($0, "=")) out; next
			}
			/^launchers=/ {
				n = split(substr($0, 11), w, " "); out = ""
				for (i = 1; i <= n; i++) {
					v = w[i]
					if (v == "x-www-browser") v = ENVIRON["B"]; else if (v == "x-terminal-emulator") v = ENVIRON["T"]; else if (v == "pcmanfm") v = ENVIRON["FM"]
					if (v != "") out = out (out == "" ? "" : " ") v
				}
				print "launchers=" out; next
			}
			{ print }' "$x/etc/xdg/wf-panel-pi/wf-panel-pi.ini" | _write "$root/etc/xdg/wf-panel-pi/wf-panel-pi.ini"
		# Other size presets than Raspberry Pi OS's default (medium): the icon
		# size, as Appearance Settings sets it (the panel's icon size minus 4)
		if [[ ${O_SIZE:-medium} != medium ]]; then
			_ini_set "$root/etc/xdg/wf-panel-pi/wf-panel-pi.ini" panel icon_size $(( T_PANEL_ICON - 4 ))
		fi
	fi
	{
		printf 'Net/ThemeName "%s"\nNet/IconThemeName "%s"\nGtk/CursorThemeName "%s"\nGtk/CursorThemeSize %s\n' \
			"$T_GTK" "$T_ICONS" "$T_ICONS" "$T_CURSOR_SIZE"
		printf 'Gtk/FontName "%s"\nGtk/ColorScheme "%s"\nNet/SoundThemeName "%s"\n' "$T_FONT" "$(color_scheme)" "$T_SOUND_THEME"
		printf 'Net/EnableEventSounds 1\nNet/EnableInputFeedbackSounds 1\nGtk/ToolbarStyle 3\nGtk/ButtonImages 0\nGtk/MenuImages 0\n'
		printf 'Gtk/AutoMnemonics 1\nGtk/EnableMnemonics 1\nGtk/ToolbarIconSize 3\nGtk/IconSizes "gtk-large-toolbar=%s,%s"\n' "$T_TB_ICON" "$T_TB_ICON"
		printf 'Xft/Antialias 1\nXft/Hinting 1\nXft/HintStyle "hintfull"\nXft/RGBA "rgb"\n'
	} | _write "$root$SHARE/xsettingsd.conf"
	cat <<'EOF' | _write "$root$SHARE/start-wayland"
#!/bin/sh
# The Raspberry Pi Desktop session on Wayland.
. /usr/share/rpios-look/session-env
menu_tidy

# The system's keyboard layout, which Debian keeps in /etc/default/keyboard
if [ -r /etc/default/keyboard ]; then
	. /etc/default/keyboard
	export XKB_DEFAULT_MODEL="$XKBMODEL" XKB_DEFAULT_LAYOUT="$XKBLAYOUT" \
		XKB_DEFAULT_VARIANT="$XKBVARIANT" XKB_DEFAULT_OPTIONS="$XKBOPTIONS"
fi
# Render in software without 3D acceleration (virtual machines, old hardware)
export WLR_RENDERER_ALLOW_SOFTWARE=1
if [ -z "$(ls /dev/dri/renderD* 2>/dev/null)" ]; then export WLR_RENDERER=pixman; fi
# NVIDIA's driver draws hardware cursors incorrectly with wlroots
if [ -d /sys/module/nvidia_drm ]; then export WLR_NO_HARDWARE_CURSORS=1; fi
# Display settings start empty, as in Raspberry Pi OS
if command -v kanshi >/dev/null && [ ! -e "$config/kanshi/config" ]; then
	mkdir -p "$config/kanshi" && : >"$config/kanshi/config"
fi

xsettings_file
# Apply a look that rpios-look-set saved while this session was not running
[ ! -e "$own/.wayland-look" ] || { wayland_look; rm -f "$own/.wayland-look"; }
/usr/bin/labwc -m
EOF
	cat <<'EOF' | _write "$root$SHARE/respawn"
#!/bin/sh
# Run a program of the session again whenever it exits, while labwc runs.
while kill -0 "${LABWC_PID:-$PPID}" 2>/dev/null; do
	"$@"
	sleep 1
done
EOF
	chmod 0755 "$root$SHARE/start-wayland" "$root$SHARE/respawn"
	printf '[Desktop Entry]\nType=Application\nName=Raspberry Pi Desktop on Wayland\nComment=The Raspberry Pi OS desktop on Wayland, on Debian\nExec=%s/start-wayland\nTryExec=/usr/bin/labwc\nDesktopNames=labwc;wlroots\n' \
		"$SHARE" | _write "$root/usr/share/wayland-sessions/$SESSION_ID-wayland.desktop"
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
		printf 'APP=%s PROFILE=%s SHARE=%s OBFILE=%s FMPROFILE=%s\n' "$APP_NAME" "$S_PROFILE" "$SHARE" "$(ob_file)" "$S_FM_PROFILE"
		printf 'FONT_SIZE=%s\n' "$T_FONT_SIZE"
		printf 'CURSOR_SIZE=%s DESK_BG=%q DESK_FG=%q DESK_SHADOW=%q\n' "$T_CURSOR_SIZE" "$T_DESK_BG" "$T_DESK_FG" "$T_DESK_SHADOW"
		printf 'COLOR_SCHEME=%q\n' "$T_COLOR_SCHEME"
		# Each theme's look, as set_theme defines it for this Debian release
		printf '# The look of a theme, as Raspberry Pi OS gives it. Usage: theme_look NAME\n'
		printf 'theme_look() {\n\tcase ${1,,} in\n'
		for t in pixflat pixnoir pixtrix pixonyx pix; do
			set_theme "$t"
			printf '\t\t%s) gtk=%s icons=%s font=%q ob_font=%q ob_weight=%s wall=%s ;;\n' \
				"$t" "$T_GTK" "$T_ICONS" "$T_FONT" "$T_FONT_FAMILY" "$T_FONT_WEIGHT" "$T_WALL_DEFAULT"
		done
		printf '\t\t*) return 1 ;;\n\tesac\n}\n'
		cat <<'EOF'
set -u
config=${XDG_CONFIG_HOME:-$HOME/.config}
own=${XDG_DATA_HOME:-$HOME/.local/share}/$APP
lxs=$config/lxsession/$PROFILE/desktop.conf lxs_sys=$SHARE/xdg/lxsession/$PROFILE/desktop.conf
fm=$config/pcmanfm/$FMPROFILE fm_sys=$SHARE/xdg/pcmanfm/$FMPROFILE
obrc=$config/openbox/$OBFILE
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
  --reset              back to the session's look, as installed
  -h, --help           this text

Examples: rpios-look-set --theme pixonyx
          rpios-look-set --animations off
          rpios-look-set --reset
USAGE
}
die() { printf 'rpios-look-set: %s\n' "$*" >&2; exit 1; }

# INI files. Usage: ini_get FILE SECTION KEY; ini_set FILE SECTION KEY VALUE
ini_get() {
	S="[$2]" K=$3 awk '$0 == ENVIRON["S"] { f = 1; next } /^\[/ { f = 0 }
		f && index($0, ENVIRON["K"] "=") == 1 { print substr($0, length(ENVIRON["K"]) + 2); exit }' "$1" 2>/dev/null
}
ini_set() {
	local tmp
	tmp=$(S="[$2]" K=$3 V=$4 awk '
		function put() { if (!done) { print ENVIRON["K"] "=" ENVIRON["V"]; done = 1 } }
		$0 == ENVIRON["S"] { print; ins = 1; seen = 1; next }
		/^\[/ { if (ins) put(); ins = 0 }
		ins && index($0, ENVIRON["K"] "=") == 1 { put(); next }
		{ print }
		END { if (ins) put(); if (!seen) { print ""; print ENVIRON["S"]; put() } }' "$1") && printf '%s\n' "$tmp" >"$1"
}
ini_del() {
	local tmp
	tmp=$(S="[$2]" K=$3 awk '$0 == ENVIRON["S"] { f = 1; print; next } /^\[/ { f = 0 }
		f && index($0, ENVIRON["K"] "=") == 1 { next } { print }' "$1") && printf '%s\n' "$tmp" >"$1"
}
# Print a value from the user's file, else from the session's
get() { local v; v=$(ini_get "$1" "$3" "$4"); [ -n "$v" ] || v=$(ini_get "$2" "$3" "$4"); printf '%s' "$v"; }
# Create the user's copy of a session file before its first change
seed() { [ -f "$1" ] || { mkdir -p "${1%/*}" && cp "$2" "$1"; } || die "cannot write $1"; }

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
	seed "$obrc" "$SHARE/openbox-rc.xml"
	sed -i -e "/<theme>/,/<\/theme>/ { /<font /,/<\/font>/ {
		s|<name>[^<]*</name>|<name>$1</name>|; s|<weight>[^<]*</weight>|<weight>$2</weight>|
		s|<slant>[^<]*</slant>|<slant>Normal</slant>|; s|<size>[^<]*</size>|<size>$FONT_SIZE</size>| } }" "$obrc"
}

list() {
	local t
	printf 'Themes (--theme): '
	for t in $PI_THEMES; do theme_look "$t" && gtk_theme "$gtk" && printf '%s ' "$t"; done
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
# The labwc of this user's Raspberry Pi Desktop session on Wayland, if one
# runs: the one whose XDG_CONFIG_DIRS starts with the session's (session-env)
wayland_pid() {
	local p line
	for p in $(pgrep -u "$(id -u)" -x labwc); do
		while IFS= read -r -d '' line; do
			case $line in "XDG_CONFIG_DIRS=$SHARE/xdg"|"XDG_CONFIG_DIRS=$SHARE/xdg:"*) printf '%s\n' "$p"; return 0 ;; esac
		done 2>/dev/null </proc/"$p"/environ
	done
	return 1
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
	w=$(sed -n '/<theme>/,/<\/theme>/ s|.*<name>\([^<]*\)</name>.*|\1|p' "$obrc" 2>/dev/null | head -n1)
	printf 'Windows        %s\n' "${w:-$(sed -n '/<theme>/,/<\/theme>/ s|.*<name>\([^<]*\)</name>.*|\1|p' "$SHARE/openbox-rc.xml" | head -n1)}"
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

# Set Openbox's theme in the user's Openbox file, with the theme's corners:
# rounded unless its border.radius is 0 (see _ob_round in rpios-look)
set_openbox_theme() {
	local r
	seed "$obrc" "$SHARE/openbox-rc.xml"
	r=$(sed -n 's/^border\.radius:[[:space:]]*//p' "/usr/share/themes/$1/openbox-3/themerc" 2>/dev/null | head -n 1)
	if [[ ${r:-0} == 0 ]]; then r=no; else r=yes; fi
	# The theme name only, not the font names inside <font>
	sed -i "/<theme>/,/<\/theme>/ { /<font /,/<\/font>/b; s|<name>[^<]*</name>|<name>$1</name>|; s|<roundCorners>[^<]*</roundCorners>|<roundCorners>$r</roundCorners>| }" "$obrc"
}

# Set the desktop settings per monitor, as Desktop Preferences keeps them:
# the session's (reset_desktop) or the theme's (write_desktop)
reset_desktop() {
	local i k
	for i in 0 1; do
		[[ -f $fm_sys/desktop-items-$i.conf ]] || continue
		for k in wallpaper wallpaper_mode desktop_bg desktop_fg desktop_shadow desktop_font; do
			ini_set "$fm/desktop-items-$i.conf" '*' "$k" "$(ini_get "$fm_sys/desktop-items-$i.conf" '*' "$k")"
		done
	done
}
write_desktop() {
	local i f
	for i in 0 1; do
		f=$fm/desktop-items-$i.conf
		[[ -f $f ]] || continue
		[[ -z $wall ]] || ini_set "$f" '*' wallpaper "$wall"
		ini_set "$f" '*' wallpaper_mode crop
		ini_set "$f" '*' desktop_bg "$DESK_BG"
		ini_set "$f" '*' desktop_fg "$DESK_FG"
		ini_set "$f" '*' desktop_shadow "$DESK_SHADOW"
		ini_set "$f" '*' desktop_font "$font"
	done
}

theme="" reset=0 anim=""
(( $# )) || { usage; exit 2; }
while (( $# )); do
	o=$1
	case $o in --*=*) set -- "${o%%=*}" "${o#*=}" "${@:2}"; o=$1 ;; esac
	case $o in
		--show) show; exit 0 ;;
		--list) list; exit 0 ;;
		-h|--help) usage; exit 0 ;;
		--reset) reset=1 ;;
		--theme) (( $# >= 2 )) || die "$o needs a value"; theme=$2; shift ;;
		--animations) (( $# >= 2 )) || die "$o needs a value"; anim=$2; shift
			[[ $anim =~ ^(on|off|default)$ ]] || die "--animations takes on, off or default" ;;
		*) die "unknown option '$o' (see --help)" ;;
	esac
	shift
done
[[ -z $theme ]] || (( ! reset )) || die "give --theme or --reset, not both"
[[ -z $anim ]] || (( ! reset )) || die "give --animations or --reset, not both"

[[ -f $lxs_sys ]] || die "the Raspberry Pi Desktop session is not installed"
gtk="" icons="" font="" ob_font="" ob_weight="" wall=""
if [[ -n $theme ]]; then
	theme_look "$theme" || die "unknown theme '$theme': pixflat, pixnoir, pixtrix, pixonyx or pix"
	gtk_theme "$gtk" || die "the $gtk theme is not installed (see --list)"
	icon_theme "$icons" || die "the $icons icons are not installed"
	wall=/usr/share/rpd-wallpaper/$wall
	[[ -f $wall ]] || { printf 'rpios-look-set: the wallpaper %s is not installed; the desktop keeps its own\n' "$wall" >&2; wall=""; }
fi


# The user's own copies of the files to change
seed "$lxs" "$lxs_sys"
for i in 0 1; do [[ ! -f $fm_sys/desktop-items-$i.conf ]] || seed "$fm/desktop-items-$i.conf" "$fm_sys/desktop-items-$i.conf"; done
old_theme=$(ini_get "$lxs" GTK sNet/ThemeName) old_icons=$(ini_get "$lxs" GTK sNet/IconThemeName)
old_cursor=$(ini_get "$lxs" GTK sGtk/CursorThemeName)/$(ini_get "$lxs" GTK iGtk/CursorThemeSize)
old_anim=$(ini_get "$lxs" GTK iGtk/EnableAnimations)
if (( reset )); then
	for k in sNet/ThemeName sNet/IconThemeName sGtk/CursorThemeName iGtk/CursorThemeSize sGtk/FontName sGtk/ColorScheme; do
		ini_set "$lxs" GTK "$k" "$(ini_get "$lxs_sys" GTK "$k")"
	done
	ini_del "$lxs" GTK iGtk/EnableAnimations
	reset_desktop
	# Openbox follows the session's look again
	mkdir -p "${obrc%/*}" && cp "$SHARE/openbox-rc.xml" "$obrc" && cp "$SHARE/openbox-rc.xml" "${obrc%/*}/.$OBFILE.$APP"
elif [[ -n $theme ]]; then
	ini_set "$lxs" GTK sNet/ThemeName "$gtk"
	ini_set "$lxs" GTK sNet/IconThemeName "$icons"
	ini_set "$lxs" GTK sGtk/CursorThemeName "$icons"
	ini_set "$lxs" GTK iGtk/CursorThemeSize "$CURSOR_SIZE"
	ini_set "$lxs" GTK sGtk/FontName "$font"
	# The theme's own colours (a dark panel for a dark theme), else Raspberry Pi OS's
	ini_set "$lxs" GTK sGtk/ColorScheme "$(theme_scheme "$gtk" || printf '%s\n' "$COLOR_SCHEME")"
	set_openbox_theme "$gtk"
	set_openbox_font "$ob_font" "$ob_weight"
	write_desktop
fi
# Animations: GTK's, which lxsession passes on, and Openbox's outline when a
# window is minimized or restored (labwc has none)
if [[ -n $anim ]]; then
	case $anim in
		off) ini_set "$lxs" GTK iGtk/EnableAnimations 0; ob=no ;;
		on) ini_set "$lxs" GTK iGtk/EnableAnimations 1; ob=yes ;;
		default) ini_del "$lxs" GTK iGtk/EnableAnimations
			ob=$(sed -n 's|.*<animateIconify>\([^<]*\)</animateIconify>.*|\1|p' "$SHARE/openbox-rc.xml" | head -n1) ;;
	esac
	seed "$obrc" "$SHARE/openbox-rc.xml"
	sed -i "s|<animateIconify>[^<]*</animateIconify>|<animateIconify>${ob:-yes}</animateIconify>|" "$obrc"
fi
new_theme=$(ini_get "$lxs" GTK sNet/ThemeName)

# A running Wayland session: its settings are made from the same files
wl=$(wayland_pid)
if [[ -n $wl ]]; then
	rm -f "$own/.wayland-look"
	(
		while IFS= read -r -d '' line; do
			case $line in WAYLAND_DISPLAY=*|XDG_RUNTIME_DIR=*|DBUS_SESSION_BUS_ADDRESS=*|DISPLAY=*) export "${line?}" ;; esac
		done </proc/"$wl"/environ
		. "$SHARE/session-env"
		wayland_look
		# The menu takes the new icons when its entries are rebuilt
		menu_tidy
		kill -HUP "$wl"
		# X applications: xsettingsd reads its file again
		pkill -HUP -u "$(id -u)" -x xsettingsd
		# The desktop: labwc sets WAYLAND_DISPLAY for its clients only, so
		# it is taken from the file manager's environment
		fm=$(pgrep -u "$(id -u)" -x pcmanfm-pi | head -n1)
		if [[ -n $fm ]]; then
			while IFS= read -r -d '' line; do
				case $line in WAYLAND_DISPLAY=*) export "${line?}" ;; esac
			done </proc/"$fm"/environ
			pcmanfm-pi --profile "$FMPROFILE" --reconfigure
		fi
	) >/dev/null 2>&1 || true
else
	# Not running: start-wayland applies the look at the next login
	mkdir -p "$own" && : >"$own/.wayland-look"
fi
# A running X session: lxsession passes the theme, icons, cursor, font and
# GTK 2 colours on by itself when its file changes
p=$(session_pid)
if [[ -z $p ]]; then
	if [[ -n $wl ]]; then echo "Applied to the Raspberry Pi Desktop session on Wayland."
	else echo "Saved; the Raspberry Pi Desktop session uses it from your next login."; fi
	show
	exit 0
fi
attach "$p"
if [[ -n $old_anim && -z $(ini_get "$lxs" GTK iGtk/EnableAnimations) ]]; then
	# lxsession keeps a setting the file no longer has: pass GTK's own on
	# first, for 100 ms
	ini_set "$lxs" GTK iGtk/EnableAnimations 1; sleep 0.1
	ini_del "$lxs" GTK iGtk/EnableAnimations
fi
if [[ -z $theme ]] && (( ! reset )); then
	# Animations only: Openbox reloads its settings
	if running openbox; then openbox --reconfigure >/dev/null 2>&1 || true; fi
	show
	exit 0
fi
if [[ $new_theme == "$old_theme" ]]; then
	# GTK 3 reloads colours only on a theme change: switch to another theme
	# for 100 ms, as Raspberry Pi OS's Appearance Settings does
	tmp=Adwaita; [[ -d /usr/share/themes/t$new_theme ]] && tmp=t$new_theme
	ini_set "$lxs" GTK sNet/ThemeName "$tmp"; sleep 0.1
	ini_set "$lxs" GTK sNet/ThemeName "$new_theme"
fi
# Openbox restarts in place rather than reloading its settings: a reload
# leaves open windows without the theme's rounded corners (roundCorners)
if running openbox; then openbox --restart >/dev/null 2>&1 || true; fi
# The panel reloads its icons, as Raspberry Pi OS's Appearance Settings has
# it, and the menu its own when its entries are rebuilt
if running lxpanel-pi; then lxpanelctl-pi refresh >/dev/null 2>&1 || true
elif running lxpanel; then lxpanelctl refresh >/dev/null 2>&1 || true; fi
sh -c ". $SHARE/session-env && menu_tidy" >/dev/null 2>&1 || true
# The desktop rereads its settings: wallpaper, colours and font
for p in pcmanfm-pi pcmanfm; do
	if running "$p"; then "$p" --profile "$FMPROFILE" --reconfigure >/dev/null 2>&1 || true; break; fi
done
if [[ $(ini_get "$lxs" GTK sNet/IconThemeName) != "$old_icons" ]]; then
	echo "The menu button's logo and the cursor on window borders follow from your next login."
elif [[ $(ini_get "$lxs" GTK sGtk/CursorThemeName)/$(ini_get "$lxs" GTK iGtk/CursorThemeSize) != "$old_cursor" ]]; then
	echo "Window borders keep the old cursor until your next login."
fi
show
EOF
	} | _write "$root/usr/bin/$APP_NAME-set"
	chmod 0755 "$root/usr/bin/$APP_NAME-set"
}

# Set the session's values (S_*): its profile, the wallpaper, and whether
# Raspberry Pi's panel and file manager are used. Run in the main shell
# before the package is built.
session_vars() {
	S_PROFILE=$(session_profile)
	S_WALL=$(_wallpaper_path)
	S_PI_PANEL=0 S_PI_FM=0 S_PI_STACK=0
	if [[ -x /usr/bin/lxpanel-pi ]]; then S_PI_PANEL=1; fi
	if [[ -x /usr/bin/pcmanfm-pi ]]; then S_PI_FM=1; fi
	# Raspberry Pi's builds replacing Debian's, before Debian 13
	if (( ! S_PI_PANEL )) && _stack_installed; then S_PI_STACK=1; fi
	# Raspberry Pi's file manager uses its 'default' profile, as on Raspberry Pi OS
	S_FM_PROFILE=$S_PROFILE
	if (( S_PI_FM )); then S_FM_PROFILE=default; fi
}

# Keep the panel's pop-up windows inside the screen, on X. The panel places a
# pop-up (such as the calendar) before it knows its size, and Openbox leaves it
# there, so it can open partly off screen. popup-keeper (Python, through Xlib)
# moves each lxpanel or lxpanel-pi dropdown that reaches past its monitor back
# inside as soon as Openbox lists it, before it is drawn. GTK keeps menus and
# tooltips inside by itself; on Wayland the compositor does so for all pop-ups.
# Usage: popup_keeper_build ROOT
popup_keeper_build() {
	cat <<'EOF' | _write "$1$SHARE/popup-keeper"
#!/usr/bin/python3
# Keep the panel's pop-up windows inside their monitor (see rpios-look).
# It talks to the X server through Xlib, so that it moves a pop-up as soon
# as the window manager lists it, before the pop-up is drawn.
import ctypes
import ctypes.util
import sys

X = ctypes.CDLL(ctypes.util.find_library("X11") or "libX11.so.6")
try:
    XR = ctypes.CDLL(ctypes.util.find_library("Xrandr") or "libXrandr.so.2")
except OSError:
    XR = None

ulong, vp = ctypes.c_ulong, ctypes.c_void_p


class Prop(ctypes.Structure):       # XPropertyEvent; ConfigureNotify shares the head
    _fields_ = [("type", ctypes.c_int), ("serial", ulong), ("send_event", ctypes.c_int),
                ("display", vp), ("window", ulong), ("atom", ulong)]


class Event(ctypes.Union):
    _fields_ = [("type", ctypes.c_int), ("prop", Prop), ("pad", ctypes.c_long * 24)]


class Attrs(ctypes.Structure):      # the head of XWindowAttributes
    _fields_ = [("x", ctypes.c_int), ("y", ctypes.c_int), ("width", ctypes.c_int),
                ("height", ctypes.c_int), ("pad", ctypes.c_long * 32)]


class ClassHint(ctypes.Structure):
    _fields_ = [("name", vp), ("cls", vp)]


class Monitor(ctypes.Structure):    # XRRMonitorInfo
    _fields_ = [("name", ulong), ("primary", ctypes.c_int), ("automatic", ctypes.c_int),
                ("noutput", ctypes.c_int), ("x", ctypes.c_int), ("y", ctypes.c_int),
                ("width", ctypes.c_int), ("height", ctypes.c_int),
                ("mwidth", ctypes.c_int), ("mheight", ctypes.c_int), ("outputs", vp)]


class Message(ctypes.Structure):    # XClientMessageEvent
    _fields_ = [("type", ctypes.c_int), ("serial", ulong), ("send_event", ctypes.c_int),
                ("display", vp), ("window", ulong), ("message_type", ulong),
                ("format", ctypes.c_int), ("data", ctypes.c_long * 5)]


X.XOpenDisplay.restype = vp
X.XOpenDisplay.argtypes = [ctypes.c_char_p]
X.XDefaultRootWindow.restype = ulong
X.XDefaultRootWindow.argtypes = [vp]
X.XInternAtom.restype = ulong
X.XInternAtom.argtypes = [vp, ctypes.c_char_p, ctypes.c_int]
X.XSelectInput.argtypes = [vp, ulong, ctypes.c_long]
X.XNextEvent.argtypes = [vp, ctypes.POINTER(Event)]
X.XGetWindowProperty.argtypes = [vp, ulong, ulong, ctypes.c_long, ctypes.c_long, ctypes.c_int, ulong,
                                 ctypes.POINTER(ulong), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ulong),
                                 ctypes.POINTER(ulong), ctypes.POINTER(vp)]
X.XFree.argtypes = [vp]
X.XGetClassHint.argtypes = [vp, ulong, ctypes.POINTER(ClassHint)]
X.XGetWindowAttributes.argtypes = [vp, ulong, ctypes.POINTER(Attrs)]
X.XTranslateCoordinates.argtypes = [vp, ulong, ulong, ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_int),
                                    ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ulong)]
X.XSendEvent.argtypes = [vp, ulong, ctypes.c_int, ctypes.c_long, ctypes.POINTER(Message)]
X.XFlush.argtypes = [vp]
X.XDisplayWidth.argtypes = X.XDisplayHeight.argtypes = [vp, ctypes.c_int]
if XR:
    XR.XRRGetMonitors.restype = ctypes.POINTER(Monitor)
    XR.XRRGetMonitors.argtypes = [vp, ulong, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
    XR.XRRFreeMonitors.argtypes = [ctypes.POINTER(Monitor)]

# A window can close while it is looked at: ignore the X errors that causes
ERRORS = ctypes.CFUNCTYPE(ctypes.c_int, vp, vp)(lambda d, e: 0)
X.XSetErrorHandler(ERRORS)

dpy = X.XOpenDisplay(None)
if not dpy:
    sys.exit(0)
root = X.XDefaultRootWindow(dpy)
atom = lambda name: X.XInternAtom(dpy, name.encode(), 0)
CLIENTS, TYPE = atom("_NET_CLIENT_LIST"), atom("_NET_WM_WINDOW_TYPE")
DROPDOWN, MOVE = atom("_NET_WM_WINDOW_TYPE_DROPDOWN_MENU"), atom("_NET_MOVERESIZE_WINDOW")
PANELS = {b"Lxpanel", b"lxpanel-pi", b"Lxpanel-pi"}
PROPERTY_NOTIFY, CONFIGURE_NOTIFY = 28, 22


def windows(w, prop):
    """The window list or atom list in property PROP of window W."""
    t, f, n, left, data = ulong(), ctypes.c_int(), ulong(), ulong(), vp()
    if X.XGetWindowProperty(dpy, w, prop, 0, 4096, 0, 0, ctypes.byref(t), ctypes.byref(f),
                            ctypes.byref(n), ctypes.byref(left), ctypes.byref(data)) != 0 or not data:
        return []
    out = list(ctypes.cast(data, ctypes.POINTER(ulong))[:n.value]) if f.value == 32 else []
    X.XFree(data)
    return out


def popup(w):
    """Whether W is a pop-up of the panel."""
    hint = ClassHint()
    if not X.XGetClassHint(dpy, w, ctypes.byref(hint)):
        return False
    cls = ctypes.string_at(hint.cls) if hint.cls else b""
    for p in (hint.name, hint.cls):
        if p:
            X.XFree(p)
    return cls in PANELS and DROPDOWN in windows(w, TYPE)


def monitors():
    """The monitors, as (x, y, width, height); the whole screen without RandR."""
    out = []
    if XR:
        n = ctypes.c_int()
        mons = XR.XRRGetMonitors(dpy, root, 1, ctypes.byref(n))
        if mons:
            out = [(m.x, m.y, m.width, m.height) for m in mons[:n.value]]
            XR.XRRFreeMonitors(mons)
    return out or [(0, 0, X.XDisplayWidth(dpy, 0), X.XDisplayHeight(dpy, 0))]


def keep(w):
    """Move pop-up W inside the monitor its top left corner is on."""
    a, x, y, child = Attrs(), ctypes.c_int(), ctypes.c_int(), ulong()
    if not X.XGetWindowAttributes(dpy, w, ctypes.byref(a)) or \
            not X.XTranslateCoordinates(dpy, w, root, 0, 0, ctypes.byref(x), ctypes.byref(y), ctypes.byref(child)):
        return
    x, y, mons = x.value, y.value, monitors()
    mx, my, mw, mh = next((m for m in mons if m[0] <= x < m[0] + m[2] and m[1] <= y < m[1] + m[3]), mons[0])
    nx = max(mx, min(x, mx + mw - a.width))
    ny = max(my, min(y, my + mh - a.height))
    if (nx, ny) != (x, y):
        # _NET_MOVERESIZE_WINDOW: move only (x and y flags), from a pager
        m = Message(type=33, send_event=1, window=w, message_type=MOVE, format=32)
        m.data[:] = [(1 << 8) | (1 << 9) | (2 << 12), nx, ny, 0, 0]
        X.XSendEvent(dpy, root, 0, (1 << 19) | (1 << 20), ctypes.byref(m))
        X.XFlush(dpy)


X.XSelectInput(dpy, root, 1 << 22)                   # PropertyChangeMask
seen, ev = set(windows(root, CLIENTS)), Event()
while True:
    X.XNextEvent(dpy, ctypes.byref(ev))
    if ev.type == PROPERTY_NOTIFY and ev.prop.window == root and ev.prop.atom == CLIENTS:
        now = set(windows(root, CLIENTS))
        for w in now - seen:
            if popup(w):
                X.XSelectInput(dpy, w, 1 << 17)      # StructureNotifyMask: it can grow
                keep(w)
        seen = now
    elif ev.type == CONFIGURE_NOTIFY and ev.prop.window in seen:
        keep(ev.prop.window)
EOF
	chmod 0755 "$1$SHARE/popup-keeper"
}

# Write the power settings of both sessions: the defaults (power.conf), the
# helper the sessions run (power) and rpios-look-power, with which each user
# sets their own. The helper blanks the screen, switches the monitor off,
# locks the screen and puts the computer to sleep after the times set, and
# acts on the lid: on X through the X server's blanking and power saving,
# light-locker and a systemd-logind inhibitor; on Wayland through swayidle
# and swaylock. Only these sessions run it. Usage: power_build ROOT
power_build() {
	local root=$1
	{
		printf '# The power settings of the Raspberry Pi Desktop session, written by %s.\n' "$APP_NAME"
		printf '# Minutes without use (0 is never); each user sets their own with %s-power.\n' "$APP_NAME"
		printf '%s\n' lock=on lock_after=10 blank=10 monitor_off=10 sleep_battery=30 sleep_ac=0 lid=sleep
	} | _write "$root$SHARE/power.conf"
	cat <<'EOF' | _write "$root$SHARE/power"
#!/usr/bin/python3
# The power helper of the Raspberry Pi Desktop session (see rpios-look-power):
# blanking, monitor off, screen lock, sleep without use and the lid. Commands:
# "lock" locks now; "suspend battery|ac" sleeps when on that power source;
# "wireless-radio" is the wireless key (radios off and on together);
# "power-key" is the power button, as Raspberry Pi OS's pwrkey.
import ctypes
import ctypes.util
import os
import shutil
import signal
import struct
import subprocess
import sys
import time

SELF = os.path.realpath(__file__)
SHARE = os.path.dirname(SELF)
STATE = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                     os.path.basename(SHARE), "power")
WAYLAND = bool(os.environ.get("WAYLAND_DISPLAY"))
LOCK = ["swaylock", "-f", "-c", "000000"] if WAYLAND else ["light-locker-command", "-l"]
QUIET = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
LIBC = ctypes.CDLL(None)


def settings():
    """The session's settings, with the user's own over them."""
    s = {}
    for f in (os.path.join(SHARE, "power.conf"), STATE):
        try:
            with open(f) as fh:
                for line in fh:
                    k, _, v = line.strip().partition("=")
                    if v and not k.startswith("#"):
                        s[k] = v
        except OSError:
            pass
    return s


def seconds(s, key):
    """A time of the settings in seconds; 0 is never."""
    v = s.get(key, "0")
    return int(v) * 60 if v.isdigit() else 0


def read(path):
    try:
        with open(path) as fh:
            return fh.read().strip()
    except OSError:
        return ""


def on_ac():
    """Whether the computer runs on mains power; one without a battery does."""
    base, battery = "/sys/class/power_supply", False
    for d in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        kind = read(os.path.join(base, d, "type"))
        if kind == "Mains" and read(os.path.join(base, d, "online")) == "1":
            return True
        if kind == "Battery" and read(os.path.join(base, d, "scope")) != "Device":
            battery = True
    return not battery


def lid_closed():
    base = "/proc/acpi/button/lid"
    return any("closed" in read(os.path.join(base, d, "state"))
               for d in (os.listdir(base) if os.path.isdir(base) else []))


def radios():
    """The Wi-Fi and Bluetooth radios, as {index: (type, off)}."""
    base, out = "/sys/class/rfkill", {}
    for d in os.listdir(base) if os.path.isdir(base) else []:
        kind = read(os.path.join(base, d, "type"))
        if kind in ("wlan", "bluetooth") and d[6:].isdigit():
            out[int(d[6:])] = (kind, "1" in (read(os.path.join(base, d, "soft")),
                                             read(os.path.join(base, d, "hard"))))
    return out


def wifi_off(r):
    return [off for kind, off in r.values() if kind == "wlan"]


def wireless_radio(before, changed=False):
    """The wireless key: where the computer switched Wi-Fi itself, Bluetooth
    follows it; elsewhere all radios go off, or on when all are off. BEFORE is
    the Wi-Fi state seen before the key; CHANGED, that Wi-Fi changed just
    before it. Returns the Wi-Fi state after it."""
    now = radios()
    if wifi_off(now) and (changed or wifi_off(now) != before):
        off, kinds = all(wifi_off(now)), ("bluetooth",)
    else:
        off, kinds = not all(o for _, o in now.values()), ("wlan", "bluetooth")
    try:
        with open("/dev/rfkill", "wb", buffering=0) as f:
            for i, (kind, _) in now.items():
                if kind in kinds:
                    f.write(struct.pack("IBBBB", i, 0, 2, int(off), 0))    # RFKILL_OP_CHANGE
    except OSError:
        return wifi_off(now)
    if now:
        notify("Wireless Radios are disconnected" if off else "Wireless Radios are connected")
    return wifi_off(radios())


def notify(text):
    """Show TEXT in the panel's notifications, as Raspberry Pi's own items do."""
    if WAYLAND:
        cmd = ["wfpanelctl", "notify", text]
    elif subprocess.call(["pgrep", "-u", str(os.getuid()), "-x", "lxpanel-pi"], **QUIET) == 0:
        cmd = ["lxpanelctl-pi", "notify", text]
    else:
        cmd = ["lxpanelctl", "notify", text]
    if shutil.which(cmd[0]):
        subprocess.call(cmd, **QUIET)


def child(cmd):
    """Start a program that ends with this one."""
    return subprocess.Popen(cmd, preexec_fn=lambda: LIBC.prctl(1, signal.SIGTERM), **QUIET)


def lock():
    """Lock the screen now; return the locking program, or None without one."""
    return subprocess.Popen(LOCK, **QUIET) if shutil.which(LOCK[0]) else None


def suspend():
    subprocess.call(["systemctl", "suspend"], **QUIET)


class Idle:
    """The time without use on X, from the X server's screen saver extension."""
    class Info(ctypes.Structure):
        _fields_ = [("window", ctypes.c_ulong), ("state", ctypes.c_int), ("kind", ctypes.c_int),
                    ("til_or_since", ctypes.c_ulong), ("idle", ctypes.c_ulong), ("mask", ctypes.c_ulong)]

    def __init__(self):
        x11 = ctypes.CDLL(ctypes.util.find_library("X11") or "libX11.so.6")
        self.xss = ctypes.CDLL(ctypes.util.find_library("Xss") or "libXss.so.1")
        x11.XOpenDisplay.restype = ctypes.c_void_p
        x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x11.XDefaultRootWindow.restype = ctypes.c_ulong
        x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        self.xss.XScreenSaverAllocInfo.restype = ctypes.POINTER(self.Info)
        self.xss.XScreenSaverQueryInfo.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(self.Info)]
        self.dpy = x11.XOpenDisplay(None)
        if not self.dpy:
            sys.exit(0)
        self.root = x11.XDefaultRootWindow(self.dpy)
        self.info = self.xss.XScreenSaverAllocInfo()

    def seconds(self):
        self.xss.XScreenSaverQueryInfo(self.dpy, self.root, self.info)
        return self.info.contents.idle // 1000


def session(s):
    """Start what the settings ask for; return the programs started."""
    kids, lock_on = [], s.get("lock") == "on"
    # The desktop acts on the power button while it runs, as on Raspberry Pi OS,
    # and on the lid unless it sleeps, which logind does
    what = "handle-power-key" + (":handle-lid-switch" if s.get("lid", "sleep") != "sleep" else "")
    kids.append(child(["systemd-inhibit", "--what=" + what, "--who=Raspberry Pi Desktop",
                       "--why=The power button and lid of the Raspberry Pi Desktop", "--mode=block", "sleep", "infinity"]))
    if WAYLAND:
        args, off = ["swayidle", "-w"], [t for t in (seconds(s, "blank"), seconds(s, "monitor_off")) if t]
        if off and shutil.which("wlopm"):
            args += ["timeout", str(min(off)), "wlopm --off '*'", "resume", "wlopm --on '*'"]
        if lock_on and seconds(s, "lock_after"):
            args += ["timeout", str(seconds(s, "lock_after")), " ".join(LOCK)]
        if lock_on:
            args += ["before-sleep", " ".join(LOCK)]
        for source in ("battery", "ac"):
            if seconds(s, "sleep_" + source):
                args += ["timeout", str(seconds(s, "sleep_" + source)), "%s suspend %s" % (SELF, source)]
        kids.append(child(args))
        return kids
    blank, monitor = seconds(s, "blank"), seconds(s, "monitor_off")
    for a in (["s", "blank", "s", str(blank), str(blank)] if blank else ["s", "off"],
              ["+dpms", "dpms", "0", "0", str(monitor)] if monitor else ["-dpms"]):
        subprocess.call(["xset"] + a, **QUIET)
    if (lock_on or s.get("lid") == "lock") and shutil.which("light-locker"):
        # light-locker does the locking; locking after a time is this helper's,
        # locking on sleep light-locker's when the screen lock is on
        kids.append(child(["light-locker", "--lock-after-screensaver=2147483", "--no-late-locking",
                           "--lock-on-suspend" if lock_on else "--no-lock-on-suspend", "--no-lock-on-lid"]))
    return kids


def main():
    reload, key = [True], [0]
    signal.signal(signal.SIGHUP, lambda *_: reload.__setitem__(0, True))
    signal.signal(signal.SIGUSR1, lambda *_: key.__setitem__(0, time.time()))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    idle = None if WAYLAND else Idle()
    kids, runs, done, last, closed, s = [], [], set(), 0, lid_closed(), {}
    wifi, changed = wifi_off(radios()), 0
    # The time spent asleep: the boot clock runs on during sleep, the
    # monotonic clock does not
    asleep, woke = time.clock_gettime(time.CLOCK_BOOTTIME) - time.monotonic(), None
    while True:
        # The wireless key acts on the next round, once a computer that
        # switches Wi-Fi itself has done so
        if key[0] and time.time() - key[0] >= 1:
            key[0] = 0
            wifi, changed = wireless_radio(wifi, time.time() - changed < 3), 0
        w = wifi_off(radios())
        if w != wifi:
            wifi, changed = w, time.time()
        if reload[0]:
            reload[0] = False
            for k in kids:
                k.terminate()
                k.wait()
            if s:
                # Run again, as this file may be newer, with the new settings
                os.execv(sys.executable, [sys.executable, SELF])
            s = settings()
            kids, done = session(s), set()
        runs = [r for r in runs if r and r.poll() is None]
        for k in kids:
            k.poll()
        if idle:
            # Waking from sleep is use: the screen lock (light-locker) takes
            # the keys on the login screen, so the session's time without use
            # runs on, and the computer would not sleep again
            a = time.clock_gettime(time.CLOCK_BOOTTIME) - time.monotonic()
            if a - asleep > 1:
                woke = time.monotonic()
            asleep = a
            t = idle.seconds()
            if woke is not None:
                t = min(t, int(time.monotonic() - woke))
            if t < last:
                done.clear()
            last = t
            after = seconds(s, "lock_after")
            if s.get("lock") == "on" and after and t >= after and "lock" not in done:
                done.add("lock")
                runs.append(lock())
            # The power source is read only once sleeping is due on one of them
            due = [a for a in (seconds(s, "sleep_ac"), seconds(s, "sleep_battery")) if a]
            if due and t >= min(due) and "sleep" not in done:
                after = seconds(s, "sleep_ac" if on_ac() else "sleep_battery")
                if after and t >= after:
                    done.add("sleep")
                    suspend()
                    # Counted again from now, should sleep fail or end at once
                    woke = time.monotonic()
        if s.get("lid") == "lock":
            now = lid_closed()
            if now and not closed:
                runs.append(lock())
            closed = now
        # On X the display's end stops the helper; on Wayland the compositor's socket
        if WAYLAND and not os.path.exists(os.path.join(os.environ.get("XDG_RUNTIME_DIR", ""),
                                                       os.environ["WAYLAND_DISPLAY"])):
            sys.exit(0)
        time.sleep(1)


if sys.argv[1:] == ["lock"]:
    p = lock() if settings().get("lock") == "on" else None
    if p:
        p.wait()
elif sys.argv[1:2] == ["suspend"]:
    if sys.argv[2:] == (["ac"] if on_ac() else ["battery"]):
        suspend()
elif sys.argv[1:] == ["wireless-radio"]:
    # The running helper knows the Wi-Fi state from before the key
    if subprocess.call(["pkill", "-USR1", "-u", str(os.getuid()), "-f", "^/usr/bin/python3 %s$" % SELF]):
        wireless_radio(wifi_off(radios()))
elif sys.argv[1:] == ["power-key"]:
    # The Shutdown dialog; pressed again while it is open, shut down. A key
    # event repeated at once (some systems deliver the power key twice) finds
    # the dialog just opened and is not a second press.
    # The dialog is lxde-pi-shutdown-helper in Raspberry Pi OS 10, pishutdown later
    dialog = next((d for d in ("pishutdown", "lxde-pi-shutdown-helper") if shutil.which(d)), "pishutdown")
    pids = subprocess.run(["pgrep", "-d", ",", "-u", str(os.getuid()), "-f", "(^|/)%s( |$)" % dialog],
                          capture_output=True, text=True).stdout.strip()
    ages = subprocess.run(["ps", "-o", "etimes=", "-p", pids], capture_output=True,
                          text=True).stdout.split() if pids else []
    if shutil.which(dialog) and not ages:
        subprocess.Popen([dialog], start_new_session=True, **QUIET)
    elif not ages or min(int(a) for a in ages) >= 1:
        subprocess.call(["systemctl", "poweroff"], **QUIET)
else:
    main()
EOF
	chmod 0755 "$root$SHARE/power"
	{
		printf '#!/bin/bash\n# Your power settings of the Raspberry Pi Desktop session, written by %s %s.\n' "$APP_NAME" "$APP_VERSION"
		printf 'APP=%s SHARE=%s\n' "$APP_NAME" "$SHARE"
		cat <<'EOF'
state=${XDG_DATA_HOME:-$HOME/.local/share}/$APP file=$state/power
usage() {
	cat <<EOT
Usage: $APP-power [OPTION]...
Set when the screen of your Raspberry Pi Desktop session blanks and locks and
when the computer sleeps: for you only, at once and for later logins. MIN is
minutes without use, such as 30, 30m or 30min; 0 or never is never. Any
option set to default goes back to the session's setting, in brackets.

  --lock on|off              lock the screen: after --lock-after, on waking
                             from sleep and with Ctrl+Alt+L [$(def lock)]
  --lock-after MIN           lock the screen after MIN minutes [$(def lock_after)]
  --blank MIN                blank the screen after MIN minutes [$(def blank)]
  --monitor-off MIN          switch the monitor off after MIN minutes [$(def monitor_off)]
  --sleep-battery MIN        sleep after MIN minutes, on battery [$(def sleep_battery)]
  --sleep-ac MIN             sleep after MIN minutes, on mains power [$(def sleep_ac)]
  --lid sleep|lock|nothing   what closing the lid does while you are logged in [$(def lid)]
  --show                     show your settings
  --reset                    all back to the session's settings
  -h, --help                 show this help

Example: $APP-power --lock-after 5 --sleep-ac 30
EOT
}
die() { printf '%s-power: %s\n' "$APP" "$*" >&2; exit 1; }
# A setting of the session (power.conf) or yours (FILE).
conf() { sed -n "s/^$1=//p" "$2" 2>/dev/null | tail -n1; }
# A value as shown: minutes, never, or as it is.
val() { case $1 in lock|lid) echo "${2:-none}" ;; *) [[ -z $2 || $2 == 0 ]] && echo never || echo "$2 min" ;; esac; }
def() { val "$1" "$(conf "$1" "$SHARE/power.conf")"; }
label() {
	case $1 in lock) echo Lock ;; lock_after) echo "Lock after" ;; blank) echo Blank ;;
		monitor_off) echo "Monitor off" ;; sleep_battery) echo "Sleep on battery" ;;
		sleep_ac) echo "Sleep on mains" ;; lid) echo "Lid closed" ;; esac
}
put() {
	mkdir -p "$state" || die "cannot write $file"
	{ grep -v "^$1=" "$file" 2>/dev/null; printf '%s=%s\n' "$1" "$2"; } >"$file.new" && mv -f "$file.new" "$file"
	printf '%s set to %s by you (default %s)\n' "$(label "$1")" "$(val "$1" "$2")" "$(def "$1")"
	changed=1
}
# Drop your own value of a setting: the session's applies again.
drop() {
	if [[ -f $file ]]; then
		grep -v "^$1=" "$file" >"$file.new"
		if [[ -s $file.new ]]; then mv -f "$file.new" "$file"; else rm -f "$file.new" "$file"; fi
	fi
	printf '%s back to the default, %s\n' "$(label "$1")" "$(def "$1")"
	changed=1
}
# Each setting: yours, with the default beside it, else the default.
show() {
	local k u
	echo
	for k in lock lock_after blank monitor_off sleep_battery sleep_ac lid; do
		u=$(conf "$k" "$file")
		if [[ -n $u ]]; then
			printf '%-20s %-10s set by you (default %s)\n' "$(label "$k")" "$(val "$k" "$u")" "$(def "$k")"
		else
			printf '%-20s %-10s default\n' "$(label "$k")" "$(def "$k")"
		fi
	done
}
(( $# )) || { usage; exit 1; }
changed=
while (( $# )); do
	case $1 in
		--lock|--lid) k=${1#--}; [[ ${2:-} == default ]] && { drop "$k"; shift 2; continue; }
			[[ $k == lid || ${2:-} =~ ^(on|off)$ ]] || die "--lock takes on, off or default"
			[[ $k == lock || ${2:-} =~ ^(sleep|lock|nothing)$ ]] || die "--lid takes sleep, lock, nothing or default"
			put "$k" "$2"; shift ;;
		--lock-after|--blank|--monitor-off|--sleep-battery|--sleep-ac)
			k=${1#--} v=${2:-}; k=${k//-/_}
			[[ $v == default ]] && { drop "$k"; shift 2; continue; }
			[[ $v == never ]] && v=0; v=${v%min}; v=${v%m}
			[[ $v =~ ^[0-9]+$ ]] || die "$1 takes minutes, such as $1 30 (0 or never is never; default is the session's)"
			put "$k" "$((10#$v))"; shift ;;
		--reset) rm -f "$file"; echo "All settings back to the defaults"; changed=1 ;;
		--show) ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown option: $1 (see --help)" ;;
	esac
	shift
done
# A running session takes the settings at once
[[ -z $changed ]] || pkill -HUP -u "$(id -u)" -f "^/usr/bin/python3 $SHARE/power\$" 2>/dev/null || true
show
EOF
	} | _write "$root/usr/bin/$APP_NAME-power"
	chmod 0755 "$root/usr/bin/$APP_NAME-power"
	# light-locker locks by switching to the login screen, which leaves the
	# session inactive, and Debian lets only an active session sleep without
	# a password. polkit cannot tell a locked session from one switched away
	# from, so any local session that is not in front may also put the computer
	# to sleep, in the rule format of this release's polkit: JavaScript from
	# Debian 12, .pkla before. Remote sessions still need a password.
	if suite_ge "$H_SUITE" bookworm; then
		cat <<EOF | _write "$root/usr/share/polkit-1/rules.d/60-$APP_NAME.rules"
// Written by $APP_NAME: a local session that is not in front, such as one
// whose screen is locked, may put the computer to sleep.
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.suspend" && subject.local && !subject.active) {
        return polkit.Result.YES;
    }
});
EOF
	else
		printf '[%s: sleep while the screen is locked]\nIdentity=unix-user:*\nAction=org.freedesktop.login1.suspend\nResultInactive=yes\n' \
			"$APP_NAME" | _write "$root/var/lib/polkit-1/localauthority/10-vendor.d/$APP_NAME.pkla"
	fi
}

# Raspberry Pi's archive in APT, pinned to the packages installed unchanged
# (PIN_PKGS), so that "apt full-upgrade" updates the look; a hook stops APT if
# one would replace, break or conflict with a Debian package. Not offline nor
# for --prepare-upgrade. Usage: apt_files ROOT
apt_files() {
	local root=$1 k="" d=$WORKDIR/apt-keyring
	[[ -z $REPO ]] && (( ! NO_APT_SOURCE && ${#PIN_PKGS[@]} )) || return 0
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
	printf '// Written by %s and removed with %s (see %s/apt-check)\nDPkg::Pre-Install-Pkgs { "%s/apt-check"; };\n' \
		"$APP_NAME" "$APP_PKG" "$SHARE" "$SHARE" | _write "$root$APT_HOOK"
	cat <<'EOF' | _write "$root$SHARE/apt-check"
#!/bin/sh
# Run by APT before it installs packages, with the .deb files on stdin: stop
# if a Raspberry Pi package that APT updates (the list in the pins below)
# would replace, break or conflict with an installed Debian package.
allow=" $(sed -n 's/^Package: //p' /etc/apt/preferences.d/rpios-look | head -n1) "
[ "$allow" != "  " ] || exit 0
bad=$(while read -r deb; do
	case $deb in *.deb) ;; *) continue ;; esac
	# APT names its files PACKAGE_VERSION_ARCH.deb
	p=${deb##*/}; p=${p%%_*}
	case $allow in *" $p "*) ;; *) continue ;; esac
	dpkg-deb -f "$deb" Replaces Breaks Conflicts | sed 's/^[A-Za-z-]*: //' | tr ',|' '\n' \
		| sed -E 's/^( *[^ :(]+):[^ (]*/\1/; s/\( *([<>=]+) */ \1 /; s/\)//' | while read -r n op v; do
		[ -n "$n" ] || continue
		case $allow in *" $n "*) continue ;; esac
		iv=$(dpkg-query -W -f='${db:Status-Abbrev}${Version}' "$n" 2>/dev/null) || continue
		case $iv in "ii "*) iv=${iv#ii } ;; *) continue ;; esac
		if [ -z "$op" ] || dpkg --compare-versions "$iv" "$op" "$v"; then echo "$p ($n)"; fi
	done
done)
[ -z "$bad" ] && exit 0
echo "rpios-look: a Raspberry Pi package would change Debian's packages: $(echo $bad); nothing was installed." >&2
echo "rpios-look: update the look with: bash rpios-look.sh --refresh" >&2
exit 1
EOF
	chmod 0755 "$root$SHARE/apt-check"
}
# Print the host name of a URL. Usage: _host URL
_host() { local u=${1#*://}; echo "${u%%/*}"; }

# Debian's LXDE session with Raspberry Pi's panel build (Debian 11 and 12):
# that build has no pager or background image and names its menu plugin
# smenu. The package carries Debian's layout adapted to it, which an
# Xsession.d hook puts first in XDG_CONFIG_DIRS for Debian's LXDE session only,
# while that build is installed. Debian's files and the user's are unchanged.
# Usage: lxde_panel_build ROOT
lxde_panel_build() {
	local root=$1 src=$SYS_ROOT/etc/xdg/lxpanel/LXDE/panels/panel
	(( USE_STACK )) && suite_ge "$H_SUITE" bullseye && ! suite_ge "$H_SUITE" trixie && [[ -f $src ]] || return 0
	awk '
		/^Plugin[ \t]*\{/ { buf = $0; inb = 1; next }
		inb { buf = buf "\n" $0; if ($0 ~ /^\}/) { if (buf !~ /type[ \t]*=[ \t]*pager/) print buf; inb = 0 }; next }
		{ print }' "$src" \
		| sed -e 's/^\([ \t]*\)background=1[ \t]*$/\1background=0/' \
			-e 's/^\([ \t]*type[ \t]*=[ \t]*\)menu[ \t]*$/\1smenu/' \
			-e 's#^\([ \t]*\)image=/usr/share/lxde/images/lxde-icon.png[ \t]*$#\1padding=4\n\1image=start-here#' \
		| _write "$root$SHARE/lxde-xdg/lxpanel/LXDE/panels/panel"
	cat <<EOF | _write "$root/etc/X11/Xsession.d/90${APP_NAME}-lxde"
# Written by $APP_NAME and removed with $APP_PKG. Debian's LXDE session uses
# a panel layout adapted to Raspberry Pi's build of the panel, while that
# build (with its smenu plugin) is installed.
if [ "\${DESKTOP_SESSION:-}" = LXDE ] && [ -f $SHARE/lxde-xdg/lxpanel/LXDE/panels/panel ]; then
	for f in /usr/lib/*/lxpanel/plugins/smenu.so; do
		[ -e "\$f" ] && export XDG_CONFIG_DIRS="$SHARE/lxde-xdg:\${XDG_CONFIG_DIRS:-/etc/xdg}"
		break
	done
fi
EOF
}

# Write the whole session into the package root: profile, Openbox, panels,
# menu, file manager, entries, icons, themes, programs and GSettings defaults.
# Usage: session_build ROOT
session_build() {
	local root=$1 xdg=$1$SHARE/xdg data=$1$SHARE/data rc pi="" f
	_session_profile "$xdg"
	rc=$root$SHARE/openbox-rc.xml
	# Raspberry Pi OS's own Openbox settings for this release, else Debian's
	if suite_ge "$H_SUITE" trixie; then
		pi=$( (pi_unpack "$PANEL_PKG" "$(config_suite)" "$H_ARCH") 2>/dev/null ) && pi+=/etc/xdg/openbox/rpd-rc.xml || pi=""
	else
		pi=$(_pi_stack_file etc/xdg/openbox/lxde-pi-rc.xml) || pi=""
	fi
	_seed "$rc" ${pi:+"$pi"} "$SYS_ROOT"/etc/xdg/openbox/LXDE/rc.xml "$SYS_ROOT"/etc/xdg/openbox/rc.xml \
		|| die "Openbox's rc.xml is missing (install openbox)"
	_openbox_rc "$rc"
	_openbox_keys "$rc" "$pi"
	if (( S_PI_STACK )); then _pi_stack_layout; else _lxpanel_layout; fi | _panel_size | _write "$xdg/lxpanel/$S_PROFILE/panels/panel"
	# The panel's logout opens Raspberry Pi's Shutdown dialog (lxde-pi-shutdown-helper in Raspberry Pi OS 10)
	for f in pishutdown lxde-pi-shutdown-helper; do
		if command -v "$f" >/dev/null; then printf '[Command]\nLogout=%s\n' "$f" | _write "$xdg/lxpanel/$S_PROFILE/config"; break; fi
	done
	(( S_PI_PANEL )) && _pi_panel_layout | _panel_size | _write "$xdg/lxpanel-pi/panels/panel"
	# The terminal's font for the size preset; medium is lxterminal's own
	if [[ ${O_SIZE:-medium} != medium ]]; then
		printf '[general]\nfontname=%s\n' "$T_TERM_FONT" | _write "$xdg/lxterminal/lxterminal.conf"
	fi
	_session_files "$xdg"
	_session_menu "$xdg" "$data"
	_session_entries "$xdg" "$data"
	_session_icons "$data"
	_session_themes "$data"
	_session_programs "$root"
	_session_command "$root"
	_session_dconf "$root"
	if [[ $H_DISPLAY == wayland && -x /usr/bin/labwc && -x /usr/bin/wf-panel-pi ]]; then _session_wayland "$root"; fi
}

# Copy a panel layout from stdin with the size preset's icon size, panel
# height and taskbar button width, as Appearance Settings sets them.
_panel_size() {
	sed -E -e "s/^([[:space:]]*)(iconsize|height)=[0-9]+[[:space:]]*\$/\1\2=$T_PANEL_ICON/" \
		-e "s/^([[:space:]]*MaxTaskWidth)=[0-9]+[[:space:]]*\$/\1=$T_TASK_WIDTH/"
}

# Print the login screen's background picture: Debian's login artwork, which
# follows Debian's active theme, else the session's wallpaper (a derivative
# may have no Debian artwork), else nothing.
login_background() {
	local f=/usr/share/desktop-base/active-theme/login/background.svg
	if [[ -e $f ]]; then printf '%s\n' "$f"; return 0; fi
	if [[ -n ${S_WALL:-} && -f $S_WALL ]]; then printf '%s\n' "$S_WALL"; fi
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
# and GDM read, else in ~/.dmrc and LightDM's copy of it, which its greeter
# reads (it cannot read a private home folder). This is done on the first
# install, and later only where AccountsService has no session for the user
# yet (it was installed later); a session the user picks is kept.
choose_session() {
	local user cur m v first=0 want=$SESSION_ID wl=/usr/share/wayland-sessions/$SESSION_ID-wayland.desktop
	[[ $H_DISPLAY == wayland && -f $wl ]] && want=$SESSION_ID-wayland
	_once session-chosen && first=1
	user=/org/freedesktop/Accounts/User$(id -u)
	if command -v busctl >/dev/null \
		&& cur=$(busctl get-property org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User XSession 2>/dev/null); then
		# Set on first install, or if the Wayland session is gone
		(( first )) || [[ $cur == 's ""' ]] \
			|| { [[ $cur == "s \"$SESSION_ID-wayland\"" && ! -f $wl ]]; } || return 0
		# A file this creates is removed on uninstall; a session chosen before
		# is put back
		sudo test -e "/var/lib/AccountsService/users/$(id -un)" || id -un | record_add "$SYS_DIR/accounts-created"
		for m in XSession Session; do
			v=$(busctl get-property org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User "$m" 2>/dev/null | sed -n 's/^s "\(.*\)"$/\1/p' || true)
			[[ -z $v || $v == "$SESSION_ID"* ]] || printf '%s\t%s\t%s\n' "$(id -un)" "$m" "$v" | record_add "$SYS_DIR/session-before"
		done
		as_root busctl call org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User SetXSession s "$want" >/dev/null 2>&1 || true
		as_root busctl call org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User SetSession s "$want" >/dev/null 2>&1 || true
	else
		(( first )) || return 0
		_ini_set "$HOME/.dmrc" Desktop Session "$want"
		chmod 0644 "$HOME/.dmrc"
		if [[ -d /var/cache/lightdm ]]; then sys_write "/var/cache/lightdm/dmrc/$(id -un).dmrc" <"$HOME/.dmrc"; fi
	fi
	ok "Your next login uses the Raspberry Pi Desktop session on $(display_name); the login screen offers the others too"
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
	if [[ $O_MODE != offline ]] && ! command -v curl >/dev/null && ! command -v wget >/dev/null; then missing+=(curl); fi
	(( ${#missing[@]} == 0 )) || die "missing tools: ${missing[*]} (install them with apt)"
}

# Stop unless every file of the offline repository matches SHA256SUMS.
verify_repo() {
	[[ -f $REPO/SHA256SUMS ]] || die "no offline repository in $REPO: run $(self_cmd) --download on a machine with internet access"
	step "Verifying the offline repository"
	(cd -- "$REPO" && sha256sum --quiet --strict -c SHA256SUMS) || die "packages/ is damaged (SHA256SUMS mismatch); run --download again"
	ok "Every file in packages/ matches SHA256SUMS"
}

# Decide whether Raspberry Pi OS's network plugin (netman) is used, as on
# Raspberry Pi OS 12 and 13: where NetworkManager runs the network (installed,
# or installed now for Wi-Fi), on Debian 12 with Raspberry Pi's panel build
# and on Debian 13. It needs Raspberry Pi's build of Debian's libnma, which
# is used only where its version is Debian's with Raspberry Pi's patch; where
# Debian's libnma is newer, nm-applet stays. Sets USE_NETMAN and NET_NAMES: libnma0,
# libnma-common and the other installed packages of the libnma source.
netman_decide() {
	local rv dv
	USE_NETMAN=0 NET_NAMES=()
	[[ $H_SUITE == trixie || ( $H_SUITE == bookworm && USE_STACK -eq 1 ) ]] || return 0
	[[ -n $(installed_version network-manager) ]] \
		|| { has_wifi && [[ -z $(installed_version connman)$(installed_version wicd) ]]; } || return 0
	rv=$(index_candidates "$(rpi_aid)" "$H_SUITE" "$H_ARCH" libnma0 2>/dev/null | first_line | cut -f1)
	[[ $rv == *+rpt* ]] || return 0
	dv=$(installed_version libnma0)
	[[ -n $dv ]] || dv=$(apt_versions libnma0 | first_line)
	# Offline, Debian's own build in packages/
	[[ -n $dv || -z $REPO ]] || dv=$(index_candidates local "$H_SUITE" "$H_ARCH" libnma0 2>/dev/null | cut -f1 | { grep -v '+rpt' || true; } | first_line)
	[[ -n $rv && -n $dv && ${rv%+rpt*} == "${dv%+rpt*}" ]] || return 0
	USE_NETMAN=1
	mapfile -t NET_NAMES < <({ printf '%s\n' libnma0 libnma-common
		dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${source:Package}\n' 2>/dev/null \
			| awk '$1 ~ /^.i/ && $3 == "libnma" { print $2 }'; } | awk '!seen[$0]++')
}

# Decide what to install. FETCH_PKGS holds the Raspberry Pi OS packages,
# installed from verified .deb files: every theme with its icons, fonts and
# wallpapers and, where they fit, Raspberry Pi's panel and file manager.
# APT_PKGS holds the Debian packages the session and the themes need,
# installed by name from Debian's own sources.
resolve_all() {
	local p q tray
	local -a wanted=() asked=() helpers=() kept=()
	if [[ -n $REPO ]]; then
		step "Resolving packages from packages/ ($H_SUITE, $H_ARCH)"
		index_load local "$H_SUITE" "$H_ARCH" || die "packages/ has no $H_SUITE/$H_ARCH index"
	else
		step "Resolving the latest official packages ($H_SUITE, $H_ARCH)"
		index_load rpi "$H_SUITE" "$H_ARCH" || die "cannot download the $H_SUITE package index from $RPI_ARCHIVE"
		ok "Package index signature verified (Raspberry Pi Archive Signing Key)"
	fi
	# Before Debian 13, Raspberry Pi's builds of the panel and file manager
	# replace Debian's.
	USE_STACK=0 STACK_NAMES=()
	if ! suite_ge "$H_SUITE" trixie; then
		USE_STACK=1
		mapfile -t STACK_NAMES < <(printf '%s\n' "${PI_STACK[@]}"; stack_extras "$PI_STACK_SRC" "${PI_STACK[@]}")
	fi
	# On every release, Raspberry Pi's build of Openbox replaces Debian's
	USE_WM=1
	mapfile -t WM_NAMES < <(printf '%s\n' "${PI_WM[@]}"; stack_extras "$PI_WM_SRC" "${PI_WM[@]}")
	netman_decide
	while read -r p; do
		case $p in
			lxplug-*) (( USE_STACK )) || continue ;;
			wf-panel-pi|wfplug-*|rpcc|sudopwd|gui-screenshot) [[ $H_DISPLAY == wayland ]] && apt_has labwc || continue ;;
			# Appearance Settings: on X with Raspberry Pi's panel build (before 13), and on Wayland
			pipanel) (( USE_STACK )) || { [[ $H_DISPLAY == wayland ]] && apt_has labwc; } || continue ;;
		esac
		if _stack_member "$p" && (( ! USE_STACK )); then continue; fi
		wanted+=("$p")
	done < <(rpi_pkgs "$H_SUITE" "$H_ARCH")
	# The plugin's Edit Connections opens Raspberry Pi's connection editor,
	# which its package for Debian 12 does not depend on
	(( USE_NETMAN )) && wanted+=("${NET_NAMES[@]}" lp-connection-editor)
	p=$(magnifier_pkg "$H_SUITE" "$H_ARCH") && [[ -n $p ]] && wanted+=("$p")
	# What is asked for; the Raspberry Pi packages they need are dependencies
	asked=("${wanted[@]}")
	[[ -n $REPO ]] || mapfile -t wanted < <(with_rpi_deps "$H_SUITE" "$H_ARCH" "${wanted[@]}")
	FETCH_PKGS=()
	for p in "${wanted[@]}"; do IN_SET[$p]=1; done
	for p in "${wanted[@]}"; do
		if resolve_pkg "$p"; then FETCH_PKGS+=("$p")
		# A package with no usable build for this release is skipped.
		else warn "$p is not available for $H_SUITE/$H_ARCH; skipping it"; fi
	done
	[[ " ${FETCH_PKGS[*]} " == *-theme\ * ]] || die "no theme packages are available for $H_SUITE/$H_ARCH"
	# Install all of Raspberry Pi's builds or none: a Debian package of the
	# same sources does not work with them.
	if (( USE_STACK )); then
		for p in "${STACK_NAMES[@]}"; do
			[[ " ${FETCH_PKGS[*]} " == *" $p "* ]] && continue
			note "Debian's panel and file manager are used: Raspberry Pi OS has no build of $p for $H_SUITE/$H_ARCH."
			USE_STACK=0 STACK_NAMES=()
			for q in "${FETCH_PKGS[@]}"; do _stack_member "$q" || kept+=("$q"); done
			FETCH_PKGS=("${kept[@]}")
			break
		done
	fi
	for p in "${WM_NAMES[@]}"; do
		[[ " ${FETCH_PKGS[*]} " == *" $p "* ]] && continue
		note "Debian's Openbox is used: Raspberry Pi OS has no build of $p for $H_SUITE/$H_ARCH."
		kept=()
		for q in "${FETCH_PKGS[@]}"; do [[ " ${WM_NAMES[*]} " == *" $q "* ]] || kept+=("$q"); done
		FETCH_PKGS=("${kept[@]}") USE_WM=0 WM_NAMES=()
		break
	done
	if [[ $H_DISPLAY == wayland &&" ${FETCH_PKGS[*]} " != *" wf-panel-pi "* ]]; then
		H_DISPLAY=x11 H_DISPLAY_WHY="Raspberry Pi's Wayland panel or labwc is not available for $H_SUITE/$H_ARCH"
		note "The session runs on X: $H_DISPLAY_WHY."
		# Leave out the packages only the Wayland session uses.
		mapfile -t FETCH_PKGS < <(printf '%s\n' "${FETCH_PKGS[@]}" | grep -vxE 'wfplug-.*|pipanel|rpcc|sudopwd')
	fi
	# The network plugin, and every one of Raspberry Pi's libnma builds it needs
	if (( USE_NETMAN )); then
		q=$(printf '%s\n' "${FETCH_PKGS[@]}" | grep -xE '(lx|lp)plug-netman' | first_line || true)
		for p in "${q:-the network plugin}" "${NET_NAMES[@]}"; do
			[[ " ${FETCH_PKGS[*]} " == *" $p "* ]] && continue
			note "Debian's network icon (nm-applet) is used: Raspberry Pi OS has no build of $p for $H_SUITE/$H_ARCH."
			USE_NETMAN=0 NET_NAMES=() kept=()
			for q in "${FETCH_PKGS[@]}"; do [[ $q =~ netman|^libnma|^lp-connection-editor$ ]] || kept+=("$q"); done
			FETCH_PKGS=("${kept[@]}")
			break
		done
	fi
	_refuse_debian_names "${FETCH_PKGS[@]}"

	tray=$(tray_debs "$H_SUITE")
	mapfile -t helpers < <(session_debs; theme_debs "$H_SUITE"; { grep -E '^debian-reference' <<<"$tray" || true; }
		if [[ $H_DISPLAY == wayland ]]; then wayland_debs; fi)
	mapfile -t -O "${#helpers[@]}" helpers < <(qt_debs)
	# LightDM's greeter reads each user's session choice from AccountsService;
	# it cannot read it from a private home folder.
	! with_lightdm || helpers+=(accountsservice)
	if [[ -n $H_DM && $H_DM != lightdm ]]; then
		note "The Raspberry Pi OS login screen needs LightDM; this computer uses $H_DM. To switch: sudo apt install lightdm lightdm-gtk-greeter && sudo dpkg-reconfigure lightdm, then run this again."
	fi
	# Hardware support: the X server, network and Bluetooth tools, sound and
	# the login screen.
	mapfile -t HW_PKGS < <(x11_debs; { grep -vE '^debian-reference' <<<"$tray" || true; }; audio_debs "$H_SUITE"; login_debs)
	helpers+=("${HW_PKGS[@]}")
	grep -q -- --root-owner-group <<<"$(dpkg-deb --help 2>/dev/null)" || helpers+=(fakeroot)
	ROOT_PKGS=("${helpers[@]}")
	for p in "${FETCH_PKGS[@]}"; do [[ " ${asked[*]} " != *" $p "* ]] || ROOT_PKGS+=("$p"); done
	APT_PKGS=()
	for p in "${helpers[@]}"; do
		[[ " ${APT_PKGS[*]} " == *" $p "* || " ${FETCH_PKGS[*]} " == *" $p "* || -n $(installed_version "$p") ]] && continue
		if [[ -n $REPO ]] || apt_has "$p"; then APT_PKGS+=("$p"); fi
	done

	if [[ -n $REPO ]]; then
		# Offline: install every package of the selection's dependency closure
		# that the repository has and the system lacks.
		local -a roots=("${FETCH_PKGS[@]}" "${APT_PKGS[@]}") needed=("${FETCH_PKGS[@]}")
		APT_PKGS=()
		while read -r p; do
			[[ -n ${PKG_VER[$p]:-} || -n $(installed_version "$p") ]] && continue
			if resolve_pkg "$p"; then FETCH_PKGS+=("$p"); fi
		done < <(INSTALLED=1 _closure "$WORKDIR/index/local/$H_SUITE/Packages-$H_ARCH" "${roots[@]}")
		# A helper that this Debian release lacks was left out of the download,
		# as an online install leaves it out
		for p in "${roots[@]}"; do
			[[ -n ${PKG_VER[$p]:-} || -n $(installed_version "$p") ]] && continue
			if [[ " ${needed[*]} " == *" $p "* ]]; then warn "$p is not in packages/; skipping it"
			else debug "$p is not in packages/ for Debian $H_SUITE/$H_ARCH; left out"; fi
		done
	fi
	for p in "${FETCH_PKGS[@]}" "${APT_PKGS[@]}"; do IN_SET[$p]=1; done
}

# Succeed if a package is one of Raspberry Pi's builds of Debian's panel and
# file manager, or a plugin for them; its own programs (*-pi) are not.
_stack_member() { [[ $1 =~ ^(lxplug-|lxpanel|pcmanfm|libfm) && $1 != *-pi ]]; }

# A Raspberry Pi package must never replace a package from the APT sources,
# except its builds of Debian's panel, file manager and Openbox (STACK_NAMES,
# WM_NAMES) and of libnma (NET_NAMES), which are installed in their place.
# Usage: _refuse_debian_names PACKAGE...
_refuse_debian_names() {
	local p
	for p; do
		[[ " ${STACK_NAMES[*]} ${WM_NAMES[*]} ${NET_NAMES[*]} " != *" $p "* ]] || continue
		if [[ -n $(apt_versions "$p") ]]; then
			die "refusing to install $p from Raspberry Pi OS: your APT sources provide a package with that name"
		fi
	done
}

# Print the state of a resolved package on this system: new, an update or up
# to date. A newer installed version is kept, never downgraded.
_pkg_status() {
	local cur from=""
	cur=$(installed_version "$1")
	[[ ${PKG_SUITE[$1]:-$H_SUITE} == "$H_SUITE" || ${PKG_AID[$1]:-} == local ]] || from=" (from ${PKG_SUITE[$1]})"
	if [[ -z $cur ]]; then echo "new$from"
	elif dpkg --compare-versions "$cur" lt "${PKG_VER[$1]}"; then echo "update from $cur$from"
	elif dpkg --compare-versions "$cur" eq "${PKG_VER[$1]}"; then echo "up to date"
	else echo "installed $cur is newer; kept"; fi
}

# Print one package line of a status table.
_pkg_line() { printf '    %-12s %-28s %-18s %s\n' "$(pkg_category "$1")" "$1" "$2" "$3" >&2; }

# Print the component type of a package, which is also its folder in
# packages/pool.
pkg_category() {
	case $1 in
		sound-theme-*)               echo sounds ;;
		pipewire*|pulseaudio|wireplumber) echo sound ;;
		lightdm*|desktop-base)       echo greeter ;;
		pcmanfm-pi|pcmanfm|libfm*)   echo files ;;
		lxpanel*|lpplug-*|pplug-*|lxplug-*|wf-panel-pi|wfplug-*|rpcc|pipanel|sudopwd|pishutdown|gui-runcmd|gui-screenshot|debian-reference-*) echo panel ;;
		network-manager*|nm-connection-editor|wpasupplicant|iw|wireless-regdb|rfkill|bluez*|blueman|libspa-0.2-bluetooth|pulseaudio-module-bluetooth|libnma*|lp-connection-editor) echo network ;;
		lxsession*|lxpolkit|mate-polkit*|openbox|lxappearance|accountsservice|gvfs*|lxde-*|lxmenu-data|labwc|swaybg|kanshi|xsettingsd|wlr-randr|xwayland|swaylock|swayidle|wlopm|python3|dconf-cli|libglib2.0-bin) echo session ;;
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
# verified files, or the Debian archive and its security updates (on a
# derivative, its own archive). This keeps third-party and Raspberry Pi
# rebuilds of Debian packages out, even when such a source is configured.
# APT names a verified file after the archive that has the same version, so
# the files are matched by name and version.
# Usage: _check_origins APT-SIMULATION-OUTPUT [DEB]...
_check_origins() {
	local line pkg ver f origins own=Debian
	local -A verified=()
	[[ -n $H_ID && $H_ID != debian ]] && own=${H_ID^}
	for f in "${@:2}"; do verified[$(dpkg-deb -f "$f" Package)=$(dpkg-deb -f "$f" Version)]=1; done
	while IFS= read -r line; do
		pkg=$(awk '{ print $2 }' <<<"$line") pkg=${pkg%%:*}
		ver=$(sed -E 's/^Inst [^ ]+ (\[[^]]*\] )?\(([^ ]+) .*/\2/' <<<"$line")
		[[ -z ${verified[$pkg=$ver]:-} ]] || continue
		# The archive name before the release: "Debian" in "Debian:13/stable"
		origins=$(sed -E 's/^Inst [^ ]+ (\[[^]]*\] )?\([^ ]+ ([^[]*)\[.*/\2/' <<<"$line")
		origins=${origins%%:*}; origins=${origins%% }
		if [[ ! $origins =~ ^(local-deb|Debian|Debian-Security|$own|$own-Security)$ ]]; then
			die "refusing to install $pkg from '${origins% }': Debian packages must come from Debian"
		fi
	done < <(grep '^Inst ' <<<"$1")
}

# Offline: copy the verified files into a private APT archive cache under the
# names APT uses. APT then takes them, instead of trying to download the same
# version listed in the APT sources.
_prime_apt_cache() {
	local f
	mkdir -p "$WORKDIR/archives/partial"
	for f; do
		cp -- "$f" "$WORKDIR/archives/$(dpkg-deb -f "$f" Package)_$(dpkg-deb -f "$f" Version | sed 's/:/%3a/')_$(dpkg-deb -f "$f" Architecture).deb"
	done
}

# Print the Raspberry Pi OS release whose configuration packages this system
# uses: its own release from Debian 13, else Raspberry Pi OS 13. Offline, the
# release's own, which packages/ holds.
config_suite() {
	if suite_ge "$H_SUITE" trixie || [[ -n $REPO && $O_MODE != download ]]; then echo "$H_SUITE"; else echo trixie; fi
}

# Print the given packages and the Raspberry Pi packages they need that Debian
# does not have (such as a plugin's data), which are installed from Raspberry
# Pi too. Usage: with_rpi_deps SUITE ARCH PACKAGE...
with_rpi_deps() {
	local suite=$1 arch=$2 names p n i
	local -a list=("${@:3}")
	local -A seen=()
	names=$(index_names rpi "$suite" "$arch")
	for (( i = 0; i < ${#list[@]}; i++ )); do
		p=${list[i]}
		[[ -z ${seen[$p]:-} ]] || continue
		seen[$p]=1
		echo "$p"
		for n in $(index_candidates rpi "$suite" "$arch" "$p" | first_line | cut -f6 | depnames); do
			[[ " ${DEP_DROPS[$p]:-} " != *" $n "* ]] || continue
			[[ -z ${seen[$n]:-} ]] && grep -qxF "$n" <<<"$names" && ! _dep_ok "$n" && list+=("$n")
		done
	done
	return 0
}

# Adapt a Raspberry Pi package for Debian and print its path; fail if it is
# refused. Usage: adapt_deb FILE
adapt_deb() {
	local f
	f=$(deps_drop "$1") && f=$(compat_fix "$f") && f=$(fm_coinstall "$f") && f=$(rpcc_session "$f") && f=$(bt_pin_entry "$f") \
		&& scripts_coinstall "$f"
}

# Raspberry Pi's Bluetooth plugins: the PIN field of their pairing dialog
# cannot take the keyboard focus (can-focus False), so the PIN that legacy
# pairing (Bluetooth 2.0) asks for cannot be typed. The field is made
# focusable; nothing else changes. Prints the path of the package to install.
bt_pin_entry() {
	local deb=$1 f
	[[ $(dpkg-deb -f "$deb" Package) =~ ^(lx|lp|wf)plug-bluetooth$ ]] || { printf '%s\n' "$deb"; return 0; }
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
# field (installed before bt_pin_entry). Usage: _pin_unfixed PACKAGE
_pin_unfixed() {
	local f
	[[ $1 =~ ^(lx|lp|wf)plug-bluetooth$ ]] || return 1
	while read -r f; do
		[[ -f $f ]] && ! cmp -s "$f" <(_pin_focus <"$f") && return 0
	done < <(dpkg -L "$1" 2>/dev/null | grep '/ui/lxplug-bluetooth\.ui$')
	return 1
}

# Download, verify and install the packages. APT never removes packages
# (--no-remove) and, offline, never downloads (--no-download). Every package
# installed is recorded for --uninstall.
install_all() {
	local p f q v cur sim had accts
	local -a files=() opts=("${APT_OPTS[@]}") new=() left=() kept=() deb=()
	if [[ -n $REPO ]]; then step "Preparing packages"; else step "Downloading and verifying packages"; fi
	if [[ -z $REPO ]]; then
		info "Refreshing APT package lists"
		as_root apt-get update -q >/dev/null || die "apt-get update failed"
		for p in "${APT_PKGS[@]}"; do apt_has "$p" || die "the Debian package '$p' is not available from your APT sources"; done
	fi
	# The packages installed as Raspberry Pi ships them, from earlier runs
	local -A plain=()
	if [[ -f $SYS_DIR/apt-packages ]]; then while read -r p; do [[ -z $p ]] || plain[$p]=1; done <"$SYS_DIR/apt-packages"; fi
	for p in "${FETCH_PKGS[@]}"; do
		cur=$(installed_version "$p")
		if [[ -n $cur ]] && dpkg --compare-versions "$cur" ge "${PKG_VER[$p]}" && ! _pin_unfixed "$p"; then
			debug "$p $cur is installed and up to date"
			continue
		fi
		f=$(download_pkg "$p") q=$f
		# A package fixed at its installed version (_pin_unfixed): APT takes
		# the same version with other contents for a downgrade
		if [[ -n $cur ]] && dpkg --compare-versions "$cur" eq "${PKG_VER[$p]}" && [[ " ${opts[*]} " != *" --reinstall "* ]]; then
			opts+=(--reinstall --allow-downgrades)
		fi
		# The files in packages/ are adapted already
		if [[ -z $REPO ]]; then f=$(adapt_deb "$f") || { left+=("$p"); continue; }; fi
		# APT updates only packages used unchanged from this release's suite,
		# the one in its sources; not Raspberry Pi's builds of Debian's
		# packages (PI_STACK, PI_WM, libnma), nor offline
		if [[ -z $REPO && $f == "$q" && ${PKG_SUITE[$p]:-} == "$H_SUITE" ]] && ! stack_deb "$f" \
			&& [[ $(dpkg-deb -f "$f" Source) != libnma* ]]; then
			plain[$p]=1
		else unset 'plain[$p]'; fi
		files+=("$f")
	done
	# A package left out was warned about; it is not checked for after APT
	if (( ${#left[@]} )); then
		for p in "${FETCH_PKGS[@]}"; do [[ " ${left[*]} " == *" $p "* ]] || kept+=("$p"); done
		FETCH_PKGS=("${kept[@]}") kept=()
	fi
	# The network plugin needs all of its packages: without one, nm-applet
	if (( USE_NETMAN )) && [[ " ${left[*]} " =~ \ (libnma[^\ ]*|[^\ ]*netman[^\ ]*|lp-connection-editor)\  ]]; then
		note "Debian's network icon (nm-applet) is used: a package of Raspberry Pi's network plugin was left out."
		USE_NETMAN=0 NET_NAMES=()
		for f in "${files[@]}"; do [[ $(dpkg-deb -f "$f" Package) =~ netman|^libnma|^lp-connection-editor$ ]] || kept+=("$f"); done
		files=("${kept[@]}") kept=()
		for p in "${FETCH_PKGS[@]}"; do [[ $p =~ netman|^libnma|^lp-connection-editor$ ]] || kept+=("$p"); done
		FETCH_PKGS=("${kept[@]}")
		q=$(nm_applet_pkg "$H_SUITE")
		if [[ -z $(installed_version "$q") ]] && apt_has "$q"; then APT_PKGS+=("$q"); fi
	fi
	# Raspberry Pi's Openbox needs all of its packages: without one, Debian's
	for p in "${left[@]}"; do
		[[ " ${WM_NAMES[*]} " == *" $p "* ]] || continue
		note "Debian's Openbox is used: Raspberry Pi's build of $p was left out."
		for f in "${files[@]}"; do [[ " ${WM_NAMES[*]} " == *" $(dpkg-deb -f "$f" Package) "* ]] || kept+=("$f"); done
		files=("${kept[@]}") kept=()
		for q in "${FETCH_PKGS[@]}"; do [[ " ${WM_NAMES[*]} " == *" $q "* ]] || kept+=("$q"); done
		FETCH_PKGS=("${kept[@]}") kept=() USE_WM=0 WM_NAMES=()
		break
	done
	PIN_PKGS=()
	for p in "${FETCH_PKGS[@]}"; do [[ -z ${plain[$p]:-} ]] || PIN_PKGS+=("$p"); done
	printf '%s\n' "${PIN_PKGS[@]}" | sys_write "$SYS_DIR/apt-packages"
	if [[ -n $REPO ]]; then
		# Offline, APT must not download anything; it would otherwise fetch
		# recommended packages that packages/ lacks from the APT sources.
		opts+=(--no-download -o "Dir::Cache::archives=$WORKDIR/archives/")
		_prime_apt_cache "${files[@]}"
	fi

	step "Installing packages"
	if (( ${#files[@]} + ${#APT_PKGS[@]} == 0 )); then ok "Every package is installed and up to date"; return 0; fi
	had=$(installed_names) accts=$(_accounts)
	# APT's "automatically installed" marks of Debian's panel, file manager,
	# Openbox and libnma, before Raspberry Pi's builds replace them (see
	# restore_debian_stack)
	deb=()
	for p in "${STACK_NAMES[@]}" "${WM_NAMES[@]}" "${NET_NAMES[@]}"; do
		v=$(installed_version "$p")
		[[ -z $v || $v == *+rpt* ]] || deb+=("$p")
	done
	if (( ${#deb[@]} )); then
		{ grep -vxF -f <(printf '%s\n' "${deb[@]}") "$SYS_DIR/stack-auto" 2>/dev/null || true
			apt-mark showauto "${deb[@]}" 2>/dev/null || true; } | sort -u | sys_write "$SYS_DIR/stack-auto"
	fi
	if ! sim=$(LC_ALL=C apt-get install --simulate "${opts[@]}" "${files[@]}" "${APT_PKGS[@]}" 2>&1); then
		tail -n 15 <<<"$sim" >&2
		[[ -n $REPO ]] && warn "an offline install can only use packages that are installed or in packages/"
		die "APT cannot install the packages on this system (see above); nothing was changed"
	fi
	_check_origins "$sim" "${files[@]}"
	if ! as_root env DEBIAN_FRONTEND=noninteractive apt-get install "${opts[@]}" "${files[@]}" "${APT_PKGS[@]}" 2>&1 \
		| tee "$WORKDIR/apt.out"; then
		# APT downloads everything before it installs anything, so a 404 means
		# that nothing was installed.
		if grep -q ' 404 ' "$WORKDIR/apt.out"; then
			die "your APT sources point to files Debian has moved (404 Not Found), so nothing was installed. When a Debian release reaches its end, its packages and security updates move to archive.debian.org: change /etc/apt/sources.list to match (see https://www.debian.org/distrib/archive), run 'sudo apt update', then run this again"
		fi
		die "APT could not install the packages (see above)"
	fi
	_verify_installed
	mapfile -t new < <(LC_ALL=C comm -13 <(printf '%s\n' "$had") <(installed_names))
	_record_installed "${new[@]}"
	# The system users and groups the packages created, which a purge keeps
	LC_ALL=C comm -13 <(printf '%s\n' "$accts") <(_accounts) | record_add "$SYS_DIR/accounts-new"
	start_sound "${new[@]}"
	RELOGIN=1
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
		cur=$(installed_version "$p")
		if [[ -z $cur ]]; then
			note "$p is not installed"; bad=1
		elif [[ -n ${PKG_VER[$p]:-} ]] && dpkg --compare-versions "$cur" lt "${PKG_VER[$p]}"; then
			note "$p $cur is installed, older than ${PKG_VER[$p]}"; bad=1
		fi
	done
	(( bad )) || ok "Installed versions verified"
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
	if (( ${#autos[@]} )); then as_root apt-mark auto "${autos[@]}" >/dev/null; fi
	# Hardware support is recorded apart, so that the uninstall can name it.
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

# Build the generated package from the installed official themes: icon sets
# with the Debian logo and the names Debian's programs use, the session and
# the login screen. Sets PKG_DEB to the package's path. It runs in the main
# shell, so that any failure stops the build.
# shellcheck disable=SC2016  # maintainer scripts contain a literal $1
build_pkg() {
	local stage=$WORKDIR/pkg b f ver icons=() depends="lxsession, openbox, lxpanel | lxpanel-pi, pcmanfm"
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
	lxde_panel_build "$stage"
	popup_keeper_build "$stage"
	power_build "$stage"
	apt_files "$stage"
	if [[ -n $(installed_version lightdm) ]]; then login_build "$stage"; fi

	ver="${APP_VERSION}+$(date -u +%Y%m%d%H%M%S)"
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
		# Version 3.11 diverted Debian's rfkill and linked Debian's applets into
		# Raspberry Pi's panel: give rfkill back and remove the links
		printf 'if [ "$1" = configure ]; then\n'
		printf '\tif dpkg-divert --listpackage /usr/sbin/rfkill | grep -qx %s; then\n' "$APP_PKG"
		printf '\t\trm -f /usr/sbin/rfkill\n\t\tdpkg-divert --package %s --remove --rename --divert /usr/sbin/rfkill.distrib /usr/sbin/rfkill >/dev/null\n\tfi\n' "$APP_PKG"
		printf '\tfor l in /usr/lib/*/lxpanel-pi/*.so; do\n\t\tcase $(readlink "$l" || true) in /usr/lib/*/lxpanel/plugins/*) rm -f "$l" ;; esac\n\tdone\nfi\n'
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
	[[ ${XDG_SESSION_DESKTOP:-} == "$SESSION_ID" && -n ${DISPLAY:-} ]] || return 0
	local p
	_running openbox && openbox --restart >/dev/null 2>&1 || true
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
	# The power helper, which a session started before this version lacks;
	# a running one starts again as this version, with the new settings
	pkill -HUP -u "$(id -u)" -f "^/usr/bin/python3 $SHARE/power\$" \
		|| setsid -f sh -c ". $SHARE/session-env; exec $SHARE/power" >/dev/null 2>&1 9<&- || true
	ok "The running session shows the new look; log out and back in for the theme of open applications"
}

###############################################################################
# 8. User state: backups for --uninstall
#
# The session itself changes nothing in the user's own files. A user file
# that the script does change (the session choice in ~/.dmrc) is backed up in
# the user's state directory, so that --uninstall can restore it.
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
		if grep -qxF "$rel" "$st/created" 2>/dev/null; then
			rm -f -- "$dst" || { warn "could not remove $rel"; fail=1; }
		elif [[ -e $st/files/$rel || -L $st/files/$rel ]]; then
			{ mkdir -p -- "$(dirname "$dst")" && cp -a -- "$st/files/$rel" "$dst"; } || { warn "could not restore $rel"; fail=1; }
		fi
	done <"$st/keys"
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

# Apply the Raspberry Pi OS labwc look (from rpd-wayland-core's rc.xml): the
# <theme> section, window snapping and the window switcher.
# Usage: _labwc_rc FILE
_labwc_rc() {
	local file=$1 fonts
	fonts=$(_xml_fonts ActiveWindow InactiveWindow OnScreenDisplay MenuItem)
	_xml_block "$file" theme "$(printf '  <theme>\n    <name>%s</name>\n    <cornerRadius>0</cornerRadius>\n    <keepBorder>yes</keepBorder>\n%s\n    <dropShadows>yes</dropShadows>\n    <titlebar>\n      <layout>:iconify,max,close</layout>\n    </titlebar>\n  </theme>' "$T_GTK" "$fonts")"
	_xml_block "$file" snapping '  <snapping>
    <range>0</range>
    <topMaximize>no</topMaximize>
  </snapping>'
	_xml_block "$file" windowSwitcher '  <windowSwitcher show="yes" preview="yes" outlines="yes" allWorkspaces="no">
    <fields>
      <field content="icon" width="5%" />
      <field content="title" width="95%" />
    </fields>
  </windowSwitcher>'
}

# Run gsettings on the user's own dconf database. Inside the Raspberry Pi
# Desktop session, DCONF_PROFILE points at the session's private database.
# Usage: _gs ARGUMENT...
_gs() { env -u DCONF_PROFILE gsettings "$@"; }
# Succeed if a GSettings key exists.
_gs_ok() { _gs writable "$1" "$2" >/dev/null 2>&1; }
# Succeed if the user runs a process of that name.
_running() { pgrep -u "$(id -u)" -x "$1" >/dev/null 2>&1; }


###############################################################################
# 9. Offline: --download, --offline
###############################################################################

# Print the Packages index entry of a .deb file.
# Usage: _stanza DEB FILENAME-IN-REPOSITORY
_stanza() {
	local deb=$1 rel=$2 f v
	for f in Package Version Architecture Pre-Depends Depends Recommends Suggests Conflicts Breaks \
		Replaces Provides Enhances Installed-Size Maintainer Section Priority Multi-Arch Source; do
		v=$(dpkg-deb -f "$deb" "$f" 2>/dev/null)
		if [[ -n $v ]]; then printf '%s: %s\n' "$f" "$v"; fi
	done
	printf 'Filename: %s\nSize: %s\nSHA256: %s\n' "$rel" "$(stat -c %s "$deb")" "$(sha256sum "$deb" | cut -d' ' -f1)"
	printf 'Description: %s\n\n' "$(dpkg-deb -f "$deb" Description | first_line)"
}

# Write VERSIONS.md: the build date, and the version, releases and origin of
# every package in the repository. A package counts as Raspberry Pi OS's by
# name and version, since Debian's builds of some names are bundled as well.
# shellcheck disable=SC2016  # Markdown backticks
_write_versions() {
	local dir=$1 rpi
	rpi="${!RPI_NAMES[*]}"
	{
		printf '# Package versions\n\n'
		printf 'Built by `rpios-look.sh --download` (%s %s) on %s from\n' "$APP_NAME" "$APP_VERSION" "$(date -u '+%Y-%m-%d %H:%M UTC')"
		printf '%s and %s. Every file is listed in `SHA256SUMS`.\n\n' "$RPI_ARCHIVE" "$DEBIAN_ARCHIVE"
		printf '| Package | Version | Releases | Source |\n|---|---|---|---|\n'
		RPI=" $rpi " awk 'BEGIN { RS = ""; FS = "\n" }
			{
				p = v = ""
				for (i = 1; i <= NF; i++) {
					if ($i ~ /^Package: /) p = substr($i, 10)
					else if ($i ~ /^Version: /) v = substr($i, 10)
				}
				o = index(ENVIRON["RPI"], " " p "=" v " ") ? "Raspberry Pi OS" : "Debian"
				split(FILENAME, s, "/"); print p "\t" v "\t" s[length(s) - 3] "\t" o
			}' "$dir"/dists/*/main/binary-*/Packages \
			| sort -u | awk -F'\t' '
				{ k = $1 "\t" $2; if (!(k in r)) { ord[++n] = k; r[k] = $3; src[k] = $4 } else if (index(r[k], $3) == 0) r[k] = r[k] ", " $3 }
				END { for (i = 1; i <= n; i++) { split(ord[i], a, "\t"); printf "| %s | %s | %s | %s |\n", a[1], a[2], r[ord[i]], src[ord[i]] } }'
	} >"$dir/VERSIONS.md"
}

# Write SHA256SUMS for every file of the repository.
# shellcheck disable=SC2094  # SHA256SUMS is excluded from its own listing
_write_checksums() {
	(cd -- "$1" && find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | xargs -r -d '\n' sha256sum >SHA256SUMS)
}

# Print "name version" for every package of a Packages index, and "name" or
# "name version" for every virtual package it provides, sorted.
_index_names() {
	awk 'BEGIN { RS = ""; FS = "\n" }
		{
			n = v = pr = ""
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^Package: /) n = substr($i, 10)
				else if ($i ~ /^Version: /) v = substr($i, 10)
				else if ($i ~ /^Provides: /) pr = substr($i, 11)
			}
			print n " " v
			m = split(pr, a, ",")
			for (j = 1; j <= m; j++) {
				x = a[j]; pv = ""
				if (match(x, /\(= *[^)]+\)/)) { pv = substr(x, RSTART + 1, RLENGTH - 2); sub(/^= */, "", pv) }
				sub(/^[ \t]+/, "", x); sub(/[ \t(].*/, "", x)
				print x (pv == "" ? "" : " " pv)
			}
		}' "$1" | sort -u
}

# Add a .deb file to the staging repository and its index.
# Usage: _stage_pkg STAGE INDEX-DIR PACKAGE FILE
_stage_pkg() {
	local rel
	rel=pool/$(pkg_category "$3")/$(basename "$4")
	[[ -f $1/$rel ]] || install -D -m 0644 "$4" "$1/$rel"
	_stanza "$1/$rel" "$rel" >>"$2/Packages"
}

# Print, sorted, the packages that every Debian desktop installation of an
# edition (lxde, xfce, gnome, kde, cinnamon, mate, lxqt) has: the base system
# and the dependencies of the desktop task, without recommended packages.
# Usage: _desktop_base INDEX EDITION
_desktop_base() {
	BASE=priority _closure "$1" task-desktop "task-$2-desktop" | LC_ALL=C sort -u
}

# Print the Debian packages that the given Debian packages and .deb files need
# and a baseline lacks. A name that the baseline has or provides satisfies any
# alternative. Fails if a step fails.
# Usage: _bundle_closure INDEX BASELINE [PACKAGE]... -- [DEB]...
_bundle_closure() {
	local idx=$1 base=$2 have=$2.have
	local -a pkgs=() roots=()
	shift 2
	while (( $# )) && [[ $1 != -- ]]; do pkgs+=("$1"); shift; done
	(( $# )) && shift
	awk 'NR == FNR { b[$1] = 1; next }
		/^Package: / { p = $2 } /^Provides: / && (p in b) {
			sub(/^Provides: /, ""); n = split($0, a, ",")
			for (i = 1; i <= n; i++) { x = a[i]; sub(/^[ \t]+/, "", x); sub(/[ \t(].*/, "", x); print x }
		}' "$base" "$idx" | cat - "$base" | sort -u >"$have" || return 1
	if (( $# )); then
		_deb_depnames "$@" >"$have.roots" || return 1
		mapfile -t roots <"$have.roots"
	fi
	HAVE=$have _closure "$idx" "${pkgs[@]}" "${roots[@]}" >"$have.all" || return 1
	# grep exits with 1 when every name is in the baseline
	grep -vxF -f "$base" "$have.all" || (( $? == 1 ))
}

# Print the release/architecture pairs that --download builds: every pair from
# Debian $OFFLINE_OLDEST on that Raspberry Pi publishes packages for.
bundle_pairs() {
	local s a
	for s in $(releases); do
		(( $(suite_rank "$s") >= OFFLINE_OLDEST )) || continue
		for a in $(rpi_arches "$s"); do
			# Debian 13 and later do not run on 32-bit PCs
			[[ $a == i386 ]] && suite_ge "$s" trixie && continue
			rpi_populated "$s" "$a" && echo "$s/$a"
		done
	done
}

# --download: build packages/ for every release and architecture. It holds the
# Raspberry Pi OS packages, and the Debian packages that they and the session
# need and that some Debian desktop installation lacks. Each .deb is filed in
# a folder of its kind (pool/themes, pool/icons, ...). The new packages/
# replaces the old one only when complete.
download_mode() {
	local dest=$REPO stage pair suite arch p f idx deb line s v sha z e old=0 n=0 net
	local -a pairs rpis debs got
	declare -gA RPI_NAMES=()   # "name=version" of each Raspberry Pi OS package, for VERSIONS.md
	preflight_tools
	[[ -r $DEBIAN_KEYRING ]] || die "$DEBIAN_KEYRING is missing (install debian-archive-keyring)"
	mapfile -t pairs < <(bundle_pairs)
	(( ${#pairs[@]} )) || die "Raspberry Pi publishes nothing for any release; releases: $(releases | xargs)"
	step "Building packages/ from the official archives"
	log "  Raspberry Pi OS  $RPI_ARCHIVE"
	log "  Debian           $DEBIAN_ARCHIVE, $DEBIAN_OLD_ARCHIVE"
	log "  For              ${pairs[*]}"
	log "  Destination      $dest"
	ask "Proceed" y || die "aborted"
	setup_keyring
	stage=$(mktemp -d "$(dirname -- "$dest")/.packages.XXXXXX")
	BUILD_STAGE=$stage   # cleanup() removes it if the build stops
	mkdir -p "$stage/pool"
	for pair in "${pairs[@]}"; do
		suite=${pair%/*} arch=${pair#*/}
		step "Packages for $suite / $arch ($(( n + 1 )) of ${#pairs[@]})"
		H_SUITE=$suite H_ARCH=$arch
		PKG_VER=() PKG_FILE=() PKG_SHA=() PKG_SIZE=() PKG_SUITE=() PKG_AID=() IN_SET=() AVAIL=()
		index_load debian "$suite" "$arch" || die "cannot load the Debian $suite/$arch index"
		deb=$WORKDIR/index/debian/$suite/Packages-$arch
		DEP_INDEX=$deb.names
		_index_names "$deb" >"$DEP_INDEX"
		rpi_pkgs "$suite" "$arch" >"$deb.rpi" || die "cannot list the Raspberry Pi OS packages for $suite/$arch"
		mapfile -t rpis <"$deb.rpi"
		p=$(magnifier_pkg "$suite" "$arch") && [[ -n $p ]] && rpis+=("$p")
		# Raspberry Pi's network plugin needs its build of libnma and its
		# connection editor; Debian's libnma is bundled beside them, for a
		# system where the plugin is not used (see netman_decide)
		net=0
		if printf '%s\n' "${rpis[@]}" | grep -qE '^(lx|lp|wf)plug-netman$'; then
			net=1 rpis+=(libnma0 libnma-common lp-connection-editor)
		fi
		mapfile -t rpis < <(with_rpi_deps "$suite" "$arch" "${rpis[@]}")
		mapfile -t debs < <({ x11_debs; session_debs 1; theme_debs "$suite"; qt_debs; tray_debs "$suite" 1; audio_debs "$suite" 1; login_debs 1; echo accountsservice
			if suite_ge "$suite" trixie; then wayland_debs 1; fi
			if (( net )); then printf '%s\n' libnma0 libnma-common; fi; } | awk '!seen[$0]++')
		for p in "${rpis[@]}" "${debs[@]}"; do IN_SET[$p]=1; done
		idx=$stage/dists/$suite/main/binary-$arch
		mkdir -p "$idx"
		: >"$idx/Packages"
		got=()
		for p in "${rpis[@]}"; do
			if ! resolve_pkg "$p" rpi; then warn "$p is not available for $suite/$arch; left out"; continue; fi
			# A failed download stops the build; a refused package is left out
			f=$(download_pkg "$p")
			f=$(adapt_deb "$f") || continue
			got+=("$f")
			_stage_pkg "$stage" "$idx" "$p" "$f"
			RPI_NAMES[$p=${PKG_VER[$p]}]=1
			ok "$p ${PKG_VER[$p]} (Raspberry Pi OS ${PKG_SUITE[$p]})"
		done
		# The configuration packages are never installed, so their
		# dependencies are not bundled
		for p in "$PANEL_PKG $(config_suite)" "$WAYLAND_PKG $(config_suite)" "$(menu_pkg)"; do
			s=${p#* } p=${p%% *}
			[[ -z ${PKG_VER[$p]:-} ]] || continue
			line=$(index_candidates rpi "$s" "$arch" "$p" | first_line)
			[[ -n $line ]] || continue
			IFS=$'\t' read -r v _ f sha z _ <<<"$line"
			PKG_VER[$p]=$v PKG_FILE[$p]=$f PKG_SHA[$p]=$sha PKG_SIZE[$p]=${z:-0} PKG_SUITE[$p]=$s PKG_AID[$p]=rpi
			f=$(download_pkg "$p")
			_stage_pkg "$stage" "$idx" "$p" "$f"
			RPI_NAMES[$p=$v]=1
			ok "$p $v (Raspberry Pi OS $s; settings and artwork, never installed)"
		done
		# The Debian packages: the dependency closure of everything bundled,
		# minus what every Debian desktop installation has (the base system and
		# the dependencies of each desktop task)
		_desktop_base "$deb" lxde >"$deb.base"
		for e in xfce gnome kde cinnamon mate lxqt; do
			_desktop_base "$deb" "$e" | LC_ALL=C comm -12 "$deb.base" - >"$deb.tmp"
			mv -- "$deb.tmp" "$deb.base"
		done
		# The packages the script asks for are always bundled, since a minimal
		# installation may lack what a desktop task brings. Debian's panel and
		# file manager (and libnma) are bundled beside Raspberry Pi's builds of
		# them, for a system where those builds cannot be used.
		_bundle_closure "$deb" "$deb.base" "${debs[@]}" -- "${got[@]}" >"$deb.closure" \
			|| die "cannot work out the Debian packages for $suite/$arch"
		mapfile -t debs < <(printf '%s\n' "${debs[@]}" | cat - "$deb.closure" \
			| LC_ALL=C sort -u | while read -r p; do
				[[ " ${rpis[*]} " != *" $p "* || ( $p =~ ^(lxpanel|pcmanfm|libfm|libnma) && $p != *-pi ) ]] && echo "$p"
			done)
		# Debian's builds of those packages depend on Debian's versions
		for p in "${!IN_SET[@]}"; do
			if [[ $p =~ ^(lxpanel|pcmanfm|libfm|libnma) && $p != *-pi ]]; then unset 'IN_SET[$p]'; fi
		done
		for p in "${debs[@]}"; do
			# A release may lack a package (PipeWire before Debian 11); the
			# install leaves it out silently too
			if ! resolve_pkg "$p" debian; then debug "$p is not available in Debian $suite/$arch; left out"; continue; fi
			f=$(download_pkg "$p")
			_stage_pkg "$stage" "$idx" "$p" "$f"
			ok "$p ${PKG_VER[$p]} (Debian $suite)"
		done
		n=$(( n + 1 ))
	done
	DEP_INDEX=""
	step "Writing the indexes and checksums"
	_write_versions "$stage"
	_write_checksums "$stage"
	chmod -R u=rwX,go=rX "$stage"
	[[ -f $dest/.gitignore ]] && cp -- "$dest/.gitignore" "$stage/.gitignore"
	if [[ -e $dest ]]; then rm -rf -- "$dest.old"; mv -- "$dest" "$dest.old"; old=1; fi
	if ! mv -- "$stage" "$dest"; then
		(( ! old )) || mv -- "$dest.old" "$dest"
		die "cannot move the new packages/ into place"
	fi
	BUILD_STAGE=""
	rm -rf -- "$dest.old"
	ok "packages/ is ready: $(du -sh -- "$dest" | cut -f1), $(find "$dest/pool" -name '*.deb' | wc -l) packages, $n indexes"
	info "Copy $(self_cmd | cut -d' ' -f2) and packages/ to the offline computer and run: $(self_cmd) --offline"
}

###############################################################################
# 10. Refresh: --refresh, --prepare-upgrade
###############################################################################

# Print the system and version that a run resolves against.
state_lines() {
	printf 'debian %s\nrelease %s\narch %s\nversion %s\n' "${H_CODENAME:-?}" "$H_SUITE" "$H_ARCH" "$APP_VERSION"
}

# Save the state that later runs and --refresh compare against.
save_state() { state_lines | cmp -s - "$SYS_DIR/state" 2>/dev/null || state_lines | sys_write "$SYS_DIR/state"; }

# --refresh: list what an update would change, then ask. Exit when there is
# nothing to do or the answer is no; return to apply the update. Nothing is
# changed before the answer.
refresh_check() {
	local p st n=0 line key saved
	step "Updates for the Raspberry Pi OS look"
	while read -r line; do
		key=${line#?}
		case $line in
			">debian "*)  log "  + Debian release is now ${key#debian }" ;;
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
	[[ -n $(installed_version "$APP_PKG") ]] || { log "  + The session package $APP_PKG is missing"; n=$(( n + 1 )); }
	log ""
	if (( n == 0 )); then ok "The Raspberry Pi OS look is up to date; nothing to apply."; exit 0; fi
	ask "$n update(s) found. Apply them now" n || { info "Nothing changed."; exit 0; }
}

# --prepare-upgrade: before a Debian release upgrade, remove the Raspberry Pi
# OS packages with compiled code that this script installed. They are built
# for this release and could hold the upgrade back. Until the script runs
# again after the upgrade, the session uses Debian's panel, file manager and
# login screen.
prepare_upgrade() {
	local p
	local -a remove=()
	[[ -f $SYS_DIR/installed-packages ]] || die "the Raspberry Pi OS look is not installed"
	# release_bound_pkgs lists only packages that this script installed
	for p in $(release_bound_pkgs); do
		[[ -n $(installed_version "$p") ]] && remove+=("$p")
	done
	step "Preparing for a Debian release upgrade"
	if (( ${#remove[@]} == 0 )) && ! _stack_installed; then ok "Nothing to remove: no package of the look is tied to this Debian release"; return 0; fi
	log "  Removes, until the look is installed again after the upgrade:"
	(( ${#remove[@]} == 0 )) || log "    ${remove[*]}"
	_stack_installed && log "    Raspberry Pi's builds of the panel and file manager (Debian's are installed again)"
	log "  The themes, icons, fonts and wallpapers stay; the session uses Debian's"
	log "  panel, file manager and login screen meanwhile."
	ask "Continue" n || die "aborted"
	prepare_root
	take_run_lock
	require_dpkg_ready
	# What APT can remove without taking other packages, decided before any change
	if (( ${#remove[@]} )); then
		local -a safe=() kept=()
		mapfile -t safe < <(_safe_purge_set "${remove[@]}" || true)
		(( ${#safe[@]} )) || die "APT would remove other packages with them; nothing was changed"
		for p in "${remove[@]}"; do [[ " ${safe[*]} " == *" $p "* ]] || kept+=("$p"); done
		(( ${#kept[@]} == 0 )) || warn "other packages need ${kept[*]}, so they stay and may hold the upgrade back"
		remove=("${safe[@]}")
	fi
	# The Debian upgrade sees only Debian's archives; the next run adds it again
	NO_APT_SOURCE=1
	if [[ -f $APT_SRC ]]; then as_root rm -f -- "$APT_SRC" "$APT_PIN" "$APT_HOOK"; apt_source_gone; fi
	if (( ${#remove[@]} )); then
		step "Removing the packages built for Debian $H_CODENAME"
		as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${remove[@]}"
	fi
	restore_debian_stack
	set_theme "$(default_theme)"
	install_pkg
	ok "Ready. Upgrade Debian and reboot, then run: $(self_cmd)"
}

# Succeed if Raspberry Pi's build of Debian's panel is installed (PI_STACK).
_stack_installed() { [[ $(installed_version lxpanel) == *+rpt* ]]; }

# Give every wallpaper setting of the running user that names a Raspberry Pi
# OS wallpaper Debian's default: the desktop-base alternative, which points
# to the artwork of this Debian release; without desktop-base, a plain colour.
# Covers PCManFM (any profile), Xfce, MATE and GNOME-based desktops.
reset_wallpapers() {
	local def=/etc/alternatives/desktop-background f p k
	local rpd='/usr/share/rpd-wallpaper/'
	[[ -e $def ]] || def=""
	for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/pcmanfm/*/desktop-items-*.conf "${XDG_CONFIG_HOME:-$HOME/.config}"/pcmanfm/*/pcmanfm.conf; do
		grep -q "^wallpaper=$rpd" "$f" 2>/dev/null || continue
		if [[ -n $def ]]; then sed -i --follow-symlinks "s#^wallpaper=$rpd.*#wallpaper=$def#" "$f"
		else sed -i --follow-symlinks "\#^wallpaper=$rpd#d; s/^wallpaper_mode=.*/wallpaper_mode=color/" "$f"; fi
	done
	# Only with Xfce desktop settings: querying starts xfconfd, which creates its folders
	if [[ -f ${XDG_CONFIG_HOME:-$HOME/.config}/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml ]] \
		&& command -v xfconf-query >/dev/null && xfconf-query -c xfce4-desktop -l >/dev/null 2>&1; then
		while read -r p; do
			[[ $(xfconf-query -c xfce4-desktop -p "$p" 2>/dev/null) == "$rpd"* ]] || continue
			if [[ -n $def ]]; then xfconf-query -c xfce4-desktop -p "$p" -s "$def" || true
			else xfconf-query -c xfce4-desktop -p "$p" -r || true; fi
		done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/last-image$' || true)
	fi
	if command -v gsettings >/dev/null; then
		for k in org.mate.background:picture-filename org.gnome.desktop.background:picture-uri \
			org.gnome.desktop.background:picture-uri-dark org.gnome.desktop.screensaver:picture-uri \
			org.cinnamon.desktop.background:picture-uri; do
			_gs_ok "${k%%:*}" "${k#*:}" || continue
			[[ $(_gs get "${k%%:*}" "${k#*:}" 2>/dev/null) == *"$rpd"* ]] && _gs reset "${k%%:*}" "${k#*:}" || true
		done
	fi
}

# Purge packages without stopping their running services (the display
# manager, NetworkManager, the sound server): a running desktop or network
# connection stays until the next restart. A policy-rc.d file that denies
# service actions is in place during the purge, unless the system has one.
# Usage: _purge [-q] PACKAGE...
_purge() {
	local pol=/usr/sbin/policy-rc.d rc=0
	if [[ ! -e $pol ]]; then
		printf '#!/bin/sh\n# Written by %s during an uninstall\nexit 101\n' "$APP_NAME" | sys_write "$pol" && as_root chmod 0755 "$pol" && POLICY_RC=$pol
	fi
	as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@" || rc=$?
	if [[ -n $POLICY_RC ]]; then as_root rm -f -- "$POLICY_RC"; POLICY_RC=""; fi
	return "$rc"
}

# Refresh APT's lists once Raspberry Pi's archive is no longer one of its
# sources, so that APT offers only Debian's packages again.
apt_source_gone() {
	[[ ! -f $APT_SRC ]] || return 0
	compgen -G "/var/lib/apt/lists/*raspberrypi.org*" >/dev/null || return 0
	as_root apt-get update -q >/dev/null 2>&1 || true
}

# Print the files of PACKAGE=VERSION pairs in packages/ beside this script,
# for this computer's architecture, each checked against its SHA256SUMS.
# Return 1 if one is missing or differs. Usage: _local_debs PACKAGE=VERSION...
_local_debs() {
	local repo pv f arch
	repo=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-./x}")" && pwd)/packages
	arch=$(dpkg --print-architecture)
	[[ -f $repo/SHA256SUMS ]] && compgen -G "$repo/dists/*/main/binary-$arch/Packages" >/dev/null || return 1
	for pv; do
		f=$(P=${pv%%=*} V=${pv#*=} awk -v RS= -F'\n' '{
			p = v = f = ""
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^Package: /) p = substr($i, 10)
				else if ($i ~ /^Version: /) v = substr($i, 10)
				else if ($i ~ /^Filename: /) f = substr($i, 11)
			}
			if (p == ENVIRON["P"] && v == ENVIRON["V"]) { print f; exit }
		}' "$repo"/dists/*/main/binary-"$arch"/Packages | first_line)
		[[ -n $f ]] || return 1
		(cd -- "$repo" && F=$f awk '$2 == ENVIRON["F"]' SHA256SUMS | sha256sum --quiet --strict -c -) >/dev/null 2>&1 || return 1
		printf '%s\n' "$repo/$f"
	done
}

# Install Debian's builds of the panel, file manager, Openbox and libnma again
# in place of Raspberry Pi's, from the APT sources, removing Raspberry Pi's
# panel plugins first. Warn about builds without a Debian version.
restore_debian_stack() {
	local p v src
	local -a args=() kept=() plugins=() autos=() debs=()
	while read -r p v src; do
		[[ $v == *+rpt* && ${src:-$p} =~ ^($PI_STACK_SRC|$PI_WM_SRC|libnma)$ ]] || continue
		v=$(apt_versions "$p" | first_line)
		if [[ -n $v ]]; then args+=("$p=$v"); else kept+=("$p"); fi
	done < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version} ${source:Package}\n' 2>/dev/null | awk '$1 ~ /^.i/ { $1 = ""; print }')
	(( ${#args[@]} + ${#kept[@]} )) || return 0
	if (( ${#args[@]} )); then
		step "Putting Debian's builds back"
		# Raspberry Pi's plugins for its panel build, and the network plugins
		# and connection editor, which need its libnma build
		mapfile -t plugins < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'lxplug-*' '*-netman' lp-connection-editor 2>/dev/null \
			| awk '$1 ~ /^.i/ { print $2 }')
		if (( ${#plugins[@]} )); then as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y -q "${plugins[@]}" >/dev/null || true; fi
		if [[ -f $SYS_DIR/stack-auto ]]; then
			mapfile -t autos < <(printf '%s\n' "${args[@]%%=*}" | grep -xF -f "$SYS_DIR/stack-auto" || true)
		else
			mapfile -t autos < <(apt-mark showauto "${args[@]%%=*}" 2>/dev/null || true)
		fi
		# Debian's builds from packages/ beside this script when it has them
		# all, so that an offline computer gets them back too
		mapfile -t debs < <(_local_debs "${args[@]}" || true)
		(( ${#debs[@]} == ${#args[@]} )) || debs=("${args[@]}")
		if as_root env DEBIAN_FRONTEND=noninteractive apt-get install "${APT_OPTS[@]}" --allow-downgrades "${debs[@]}"; then
			# Installing by name marks them manual; they were dependencies of a desktop
			if (( ${#autos[@]} )); then as_root apt-mark auto "${autos[@]}" >/dev/null || true; fi
			ok "Debian's ${args[*]%%=*} are installed again"
		else
			warn "APT could not put Debian's builds back; install them with: sudo apt install --allow-downgrades ${args[*]}"
		fi
	fi
	(( ${#kept[@]} == 0 )) || warn "your APT sources have no Debian version of ${kept[*]}; Raspberry Pi's build stays"
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
# 11. Uninstall: --uninstall
###############################################################################

# --uninstall: undo what the script did. For everyone: the session, the login
# screen, the generated package and the packages it installed. For the user
# running it: the settings it changed. Packages that were installed before, or
# that other software now needs, stay.
uninstall() {
	local p f u m d v prev why
	local -a pkgs=() remove=() keep=()
	if [[ -f $SYS_DIR/installed-packages ]]; then mapfile -t pkgs <"$SYS_DIR/installed-packages"; fi
	if [[ -f $SYS_DIR/hardware-packages ]]; then mapfile -t -O "${#pkgs[@]}" pkgs <"$SYS_DIR/hardware-packages"; fi
	for p in "${pkgs[@]}"; do
		[[ -n $(installed_version "$p") ]] || continue
		grep -qxF "$p" "$SYS_DIR/packages-before" 2>/dev/null && continue
		keep+=("$p")
	done
	pkgs=("${keep[@]}") keep=()
	step "What the uninstall removes"
	log "  For everyone: the Raspberry Pi Desktop session, the login screen style and $APP_PKG"
	(( ${#pkgs[@]} )) && log "  Packages this script installed, hardware support included: ${pkgs[*]}"
	_stack_installed && log "  Raspberry Pi's panel and file manager: Debian's are installed again in their place"
	log "  For $(id -un): the settings it changed and your Raspberry Pi Desktop settings; other users keep theirs."
	log "  Packages you had before, or that software you installed later needs, stay."
	log "  Running services (login screen, network, sound) stop at the next restart."
	ask "Continue" n || die "aborted"
	prepare_root
	take_run_lock
	require_dpkg_ready

	step "Restoring the login screen and the users' session choice"
	# Users who chose the session get the login screen's default session
	for f in $(sudo sh -c "grep -lE '^X?Session=$SESSION_ID(-wayland)?\$' /var/lib/AccountsService/users/*" 2>/dev/null); do
		u=$(id -u "${f##*/}" 2>/dev/null) || continue
		prev=""
		for m in XSession Session; do
			# The session chosen before the install, else the login screen's default
			v=$(awk -F'\t' -v u="${f##*/}" -v m="$m" '$1 == u && $2 == m { print $3; exit }' "$SYS_DIR/session-before" 2>/dev/null || true)
			sudo grep -qE "^$m=$SESSION_ID(-wayland)?\$" "$f" && as_root busctl call org.freedesktop.Accounts \
				"/org/freedesktop/Accounts/User$u" org.freedesktop.Accounts.User "Set$m" s "$v" >/dev/null 2>&1 || true
			[[ -z $v ]] || prev=$v
		done
		if [[ -n $prev ]]; then ok "${f##*/} logs in to $prev again"; else ok "${f##*/} logs in to the login screen's default session again"; fi
	done
	# LightDM's own record of the users' session choice, used without AccountsService
	for f in $(sudo sh -c "grep -lE '^Session=$SESSION_ID(-wayland)?\$' /var/cache/lightdm/dmrc/*.dmrc" 2>/dev/null); do
		as_root rm -f -- "$f"
		ok "$(basename "$f" .dmrc) logs in to the login screen's default session again"
	done

	# This user's files: those this script backed up, and the files the
	# session wrote that are unchanged
	step "Restoring the settings of $(id -un)"
	restore_user
	# The settings of the Raspberry Pi Desktop session, which no other session
	# reads, so that a new install starts from the defaults
	f=${XDG_CONFIG_HOME:-$HOME/.config}
	d=${XDG_DATA_HOME:-$HOME/.local/share}
	for p in rpd-rc.xml lxde-pi-rc.xml; do
		rm -f -- "$f/openbox/$p" "$f/openbox/.$p.$APP_NAME"
	done
	rm -rf -- "$f/lxsession/rpd-x" "$f/lxsession/LXDE-pi" "$f/lxpanel/rpd-x" "$f/lxpanel/LXDE-pi" "$f/lxpanel-pi" \
		"$f/pcmanfm/rpd-x" "$f/pcmanfm/LXDE-pi" "$f/wf-panel-pi" "$f/wf-panel-pi.ini"
	# Debian's file manager reads its default profile in other sessions too:
	# only the desktop files with a Raspberry Pi OS wallpaper are the session's
	for p in "$f/pcmanfm/default"/desktop-items-*.conf; do
		if grep -q '^wallpaper=/usr/share/rpd-wallpaper/' "$p" 2>/dev/null; then rm -f -- "$p"; fi
	done
	# The user's own files that the session changed (keep_orig): given back,
	# or removed where the session made them
	if [[ -d $d/$APP_NAME/orig ]]; then
		while IFS= read -r -d '' p; do
			k=${p#"$d/$APP_NAME/orig/"}
			if [[ $k == *.none ]]; then rm -f -- "$f/${k%.none}"; else mkdir -p "$(dirname "$f/$k")" && cp -p -- "$p" "$f/$k"; fi
		done < <(find "$d/$APP_NAME/orig" -type f -print0)
	fi
	# The session's own user data (markers, saved originals), which only it reads
	rm -rf -- "${d:?}/$APP_NAME"
	# The session's own GSettings database
	rm -f -- "$f/dconf/${APP_NAME//-/}"
	# Folders the sessions left empty; rmdir keeps folders with content
	rmdir -- "$f/pcmanfm/default" "$f/pcmanfm" "$f/xsettingsd" "$f/dconf" "$f/labwc" "$f/lxpanel" \
		"$f/lxsession" "$f/openbox" "$d/desktop-directories" "$d/flatpak/db" "$d/flatpak" 2>/dev/null || true

	step "Removing packages"
	if [[ -n $(installed_version "$APP_PKG") ]]; then
		as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y -q "$APP_PKG" >/dev/null
		ok "Removed the Raspberry Pi Desktop session ($APP_PKG)"
	fi
	apt_source_gone
	restore_debian_stack
	# Putting Debian's panel back removes Raspberry Pi's plugins for it
	mapfile -t pkgs < <(for p in "${pkgs[@]}"; do [[ -z $(installed_version "$p") ]] || echo "$p"; done)
	if (( ${#pkgs[@]} )) && ask "Also remove the ${#pkgs[@]} packages this script installed" y; then
		why="other installed software needs them"
		if _safe_purge_set "${pkgs[@]}" >"$WORKDIR/purge-set"; then
			mapfile -t remove <"$WORKDIR/purge-set"
		else
			case $? in
				1) why="APT would also remove other packages with them" ;;
				*) why="APT could not work out what removing them would remove" ;;
			esac
			remove=()
		fi
		for p in "${pkgs[@]}"; do [[ " ${remove[*]} " == *" $p "* ]] || keep+=("$p"); done
		if (( ${#remove[@]} )); then _purge "${remove[@]}"; fi
		# The packages that stay are marked as automatically installed, so
		# that 'apt autoremove' removes them once nothing needs them
		if (( ${#keep[@]} )); then
			as_root apt-mark auto "${keep[@]}" >/dev/null
			info "Kept, because $why: ${keep[*]}"
			[[ $why == other* ]] || info "None of them was removed; later, 'sudo apt autoremove' removes those that nothing needs"
		fi
		pkgs=()
	fi
	# Icon caches left in icon set folders that no package owns any more
	for f in /usr/share/icons/PiXflat /usr/share/icons/PiXtrix /usr/share/icons/PiX; do
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
	# The AccountsService files the install created for its user
	while IFS= read -r u; do
		[[ $u =~ ^[a-z_][a-z0-9_.-]*$ ]] && as_root rm -f -- "/var/lib/AccountsService/users/$u"
	done < <(cat "$SYS_DIR/accounts-created" 2>/dev/null || true)
	if [[ -z $(installed_version accountsservice) ]]; then
		as_root rmdir /var/lib/AccountsService/users /var/lib/AccountsService 2>/dev/null || true
	fi
	if (( ${#pkgs[@]} == 0 )); then as_root rm -rf -- "$SYS_DIR"; fi
	ok "Uninstalled. Restart the computer to finish."
}

###############################################################################
# 12. Main: modes, run log, summary
###############################################################################

# Print the help: the header comment from "Usage" to the next "# ====" line.
usage() {
	local f=${BASH_SOURCE[0]:-}
	if [[ -f $f ]]; then sed -n '/^# Usage/,/^# ====/{/^# ====/q;s/^# \{0,1\}//;p}' "$f"
	else echo "Usage: bash $APP_NAME.sh [--refresh | --uninstall | --prepare-upgrade | --download | --offline | --help]"; fi
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
			--refresh|--uninstall|--prepare-upgrade|--download|--offline)
				[[ -z $mode || $mode == "${opt#--}" ]] || die "give only one of --refresh, --uninstall, --prepare-upgrade, --download and --offline"
				mode=${opt#--} ;;
			--size)           (( $# >= 2 )) || die "$opt needs a value"
				size_ok "${2,,}" || die "unknown size '$2' (small, medium, large or larger)"
				O_SIZE=${2,,} O_SIZE_GIVEN=1; shift; eq=0 ;;
			-v|--verbose)     O_VERBOSE=1 ;;
			-h|--help)        usage; exit 0 ;;
			-V|--version)     echo "$APP_NAME $APP_VERSION"; exit 0 ;;
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
	ls -1t "$HOME/$APP_NAME-$O_MODE"-*.log 2>/dev/null | tail -n +11 | xargs -r rm -f --
	{
		printf '===== %s %s, %s =====\n' "$APP_NAME" "$APP_VERSION" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
		printf 'Command:  %s %s\n' "$0" "$(_q "${ARGV[@]}")"
		printf 'System:   %s (%s), %s\n' "${H_PRETTY:-unknown}" "${H_CODENAME:-?}" "$H_ARCH"
		printf 'User:     %s (uid %s)\n' "$(id -un)" "$(id -u)"
		printf 'Session:  %s (XDG_CURRENT_DESKTOP=%s, display %s)\n' "${DESKTOP_SESSION:-none}" \
			"${XDG_CURRENT_DESKTOP:-}" "${DISPLAY:-${WAYLAND_DISPLAY:-none}}"
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
	if [[ -n $BUILD_STAGE && -d $BUILD_STAGE ]]; then rm -rf -- "$BUILD_STAGE"; fi
}

# Summarise what an install will do.
print_plan() {
	local p st total=0 src="$RPI_ARCHIVE"
	local -A status=()
	for p in "${FETCH_PKGS[@]}"; do
		st=$(_pkg_status "$p") status[$p]=$st
		[[ $st == "up to date" || $st == installed* ]] || total=$(( total + ${PKG_SIZE[$p]:-0} ))
	done
	[[ -n $REPO ]] && src="packages/"
	step "Plan"
	log "  Looks        every theme; the session uses ${T_DESC%% —*} (change it with: $APP_NAME-set --theme NAME)"
	log "  Session      Raspberry Pi Desktop on $(display_name), on the login screen for every user"
	[[ $H_DISPLAY == wayland ]] && log "               and on X (Openbox), for when Wayland does not suit"
	log "  Packages     from $src ($H_SUITE, $H_ARCH)$([[ -n $REPO ]] || echo ", up to $(human_size "$total") to download")"
	for p in "${FETCH_PKGS[@]}"; do _pkg_line "$p" "${PKG_VER[$p]}" "${status[$p]}"; done
	for p in "${APT_PKGS[@]}"; do _pkg_line "$p" "(APT)" "new, from your Debian sources"; done
	if (( USE_STACK || USE_WM )); then
		if (( USE_STACK && USE_WM )); then
			log "  Replaces     Debian's panel, file manager and Openbox with Raspberry Pi OS's"
			log "               builds of them (lxpanel, pcmanfm, libfm, openbox above),"
		elif (( USE_STACK )); then
			log "  Replaces     Debian's panel and file manager with Raspberry Pi OS's builds of"
			log "               them (lxpanel, pcmanfm, libfm above),"
		else
			log "  Replaces     Debian's Openbox with Raspberry Pi OS's build of it (openbox above),"
		fi
		log "               which Debian's own sessions then use too. --uninstall puts"
		log "               Debian's back."
		log "  Your settings in Debian's own sessions are not changed."
	else
		log "  Debian's own sessions and your settings in them are not changed."
	fi
}

# Print the closing summary.
summary() {
	local n
	log ""
	if (( ${#NOTES[@]} )); then
		warn "Not done or worth knowing:"
		for n in "${NOTES[@]}"; do log "   - $n"; done
	fi
	ok "${C_B}Done.${C_0} $T_DESC is the look of the Raspberry Pi Desktop session."
	if (( RELOGIN )) && [[ ${XDG_SESSION_DESKTOP:-} != "$SESSION_ID" ]]; then
		info "Log out and choose ${C_B}Raspberry Pi Desktop${C_0} on the login screen (it is chosen for you); other sessions stay as they were."
	fi
	info "Updates: $(self_cmd) --refresh    Undo: $(self_cmd) --uninstall"
	if [[ -n $LOG_FILE ]]; then info "Log of this run: $LOG_FILE"; fi
}

# Install, update or refresh the look, online or offline.
install_mode() {
	if [[ $O_MODE == refresh ]]; then
		[[ -f $SYS_DIR/installed-packages || -n $(installed_version "$APP_PKG") ]] \
			|| die "the Raspberry Pi OS look is not installed; install it with: $(self_cmd)"
	fi
	preflight_tools
	[[ -z $REPO ]] || verify_repo
	pick_display
	print_machine
	set_theme "$(default_theme)"
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
	install_all
	install_pkg
	apt_source_gone
	step "Setting up the login screen and the session for $(id -un)"
	_state_init
	choose_session
	reload_session
	save_size
	save_state
	summary
}

# Parse the command line, set up the run and start the chosen mode.
main() {
	ARGV=("$@")
	init_colors
	parse_args "$@"
	load_releases
	(( EUID != 0 )) || die "do not run this as root: run it as your normal user, which needs sudo rights"
	[[ $O_MODE == download || $O_MODE == offline ]] && REPO=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-./x}")" && pwd)/packages
	WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/$APP_NAME.XXXXXX")
	chmod 0755 "$WORKDIR"
	trap cleanup EXIT
	trap 'die "interrupted"' INT TERM
	detect_host
	adopt_session
	start_log
	log ""
	log "${C_B}  $APP_NAME $APP_VERSION${C_0} — the Raspberry Pi OS desktop look for Debian"
	case $O_MODE in
		download)  download_mode; return 0 ;;
		uninstall) uninstall; return 0 ;;
	esac
	pick_suite
	load_size
	case $O_MODE in
		prepare-upgrade) prepare_upgrade ;;
		*)               install_mode ;;
	esac
}

# Run main unless this file is sourced (the tests source it).
if [[ ${BASH_SOURCE[0]:-} == "$0" || -z ${BASH_SOURCE[0]:-} ]]; then
	main "$@"
fi
