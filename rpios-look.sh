#!/usr/bin/env bash
# =============================================================================
# Title       : rpios-look.sh
# Description : Makes Debian look like Raspberry Pi OS, without breaking
#               Debian: the official PiXflat, PiXnoir, PiXtrix, PiXonyx and
#               PiX themes with their icons, cursors, fonts, wallpapers,
#               panel, file manager and login screen, as a "Raspberry Pi
#               Desktop" session on the login screen. Other desktops (Xfce,
#               GNOME, MATE, ...) can be given the same look on request.
#
# Usage       : bash rpios-look.sh                   install or update
#               bash rpios-look.sh --refresh         list available updates, then
#                                                      ask to apply them
#               bash rpios-look.sh --uninstall       undo it
#               bash rpios-look.sh --prepare-upgrade before a Debian release upgrade
#               bash rpios-look.sh --download        build or refresh packages/ for
#                                                      an offline install (needs internet)
#               bash rpios-look.sh --offline         install from packages/, no network
#               bash rpios-look.sh --help            this text
#               Safe to re-run.
#
# Options     : -t, --theme NAME     pixflat, pixnoir, pixtrix, pixonyx, pix or auto
#                                    (auto: pixtrix on Debian 13 and later, else pixflat);
#                                    without it, every theme is installed and the
#                                    install asks at the end which one to use
#                   --icons NAME     pixflat, pixtrix, pix or auto (the theme's own)
#                   --wallpaper W    a file in /usr/share/rpd-wallpaper (e.g. aurora),
#                                    a path, or auto (the theme's own)
#                   --4k | --no-4k   the 4K wallpapers (about 196 MB) or the standard ones
#                   --pi-apps | --no-pi-apps
#                                    Raspberry Pi's own panel and file manager: beside
#                                    Debian's on Debian 13 and later, in place of
#                                    Debian's on Debian 10 to 12; or Debian's
#                   --login-screen | --no-login-screen
#                                    the Raspberry Pi OS login screen style (LightDM, installed
#                                    where no other login manager is used), or none
#                   --pi-greeter | --no-pi-greeter
#                                    Raspberry Pi's own login box, which has no session
#                                    chooser, or Debian's greeter in its style (default)
#                   --login-background B
#                                    the picture behind the login box: debian (Debian's
#                                    own login artwork, default), raspios or a full path
#                   --wayland | --no-wayland | --auto
#                                    the session on Wayland (labwc), as Raspberry Pi OS
#                                    13 has it (Debian 13 and later), or on X (Openbox)
#                                    only. Default (auto): Wayland where this computer
#                                    suits it, X on older computers and older Debian.
#                                    X is always installed: the login screen runs on it
#                   --qt | --no-qt   Qt applications follow the theme in the session
#               An install run saves the options above; later runs reuse them
#               unless given again, e.g. --theme auto.
#               -d, --desktop LIST   also give these desktops the look, for you only:
#                                    xfce, gnome, budgie, cinnamon, mate, lxqt,
#                                    openbox, labwc, kde, all or none (this run only)
#                   --bundle LIST    with --download: only these release/architecture
#                                    pairs, e.g. bookworm/i386,trixie/amd64
#                   --no-log         no run log
#               -y, --yes            answer yes to every question
#               -v, --verbose        print every command
#
# Offline     : Run --download on any machine with internet access; it builds
#               packages/ for Debian 10 to 13 on amd64, arm64, armhf and i386.
#               Copy this script and packages/ to the target; run --offline there.
#
# Refresh     : --refresh lists what an update would change: newer official
#               packages, missing ones, a Debian change, changed options. It
#               asks before applying anything.
#
# Undo        : bash rpios-look.sh --uninstall removes the session, the
#               packages it installed and the login screen style, and restores
#               the settings of the user running it.
#
# Requires    : Debian 10 or later, or a derivative; a normal user (not root)
#               with sudo rights; internet access, except for --offline.
# =============================================================================

# Contents
#   1. Settings     constants, options, state
#   2. Helpers      messages, questions, records, run lock
#   3. Packages     themes, package sets, host and release
#   4. Archives     signed indexes, resolution, download, repacking
#   5. Artwork      Xfwm4 themes, icon sets with the Debian logo
#   6. Session      the Raspberry Pi Desktop session and login screen
#   7. Install      packages, the generated package, records
#   8. Desktops     the look for other desktops, per user
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
readonly APP_VERSION="3.8.1"
# The package this script generates; it carries the session, the login
# screen style and the adapted icon sets, so dpkg tracks and removes them.
readonly APP_PKG="rpios-look-debian"
# What it installed, the saved options and the files it replaced.
readonly SYS_DIR="/var/lib/rpios-look"
# The session's own configuration and data, inside the generated package.
readonly SHARE="/usr/share/rpios-look"
readonly SESSION_ID="rpios-look"
# Earlier versions, named pixflat-theme (2) and raspios-look (3.0.0); their
# install is taken over.
readonly OLD_NAME="pixflat-theme" OLD_PKG="pixflat-theme-debian" OLD_SYS_DIR="/var/lib/pixflat-theme"
readonly PREV_NAME="raspios-look" PREV_PKG="raspios-look-debian" PREV_SYS_DIR="/var/lib/raspios-look"
# APT never removes a package to satisfy this script, never asks, and waits
# for another package manager to finish. Recommended packages are not
# installed: what the look needs is named, and a recommendation (Raspberry
# Pi's plugins recommend PulseAudio) must not replace what is installed.
readonly APT_OPTS=(-y --no-remove --no-install-recommends -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=300)
readonly RPI_ARCHIVE="https://archive.raspberrypi.org/debian"
readonly RPI_KEY_URL="${RPI_ARCHIVE}/raspberrypi.gpg.key"
readonly RPI_KEY_FPR="CF8A1AF502A2AA2D763BAE7E82B129927FA3303E"
# Raspberry Pi OS configuration packages, downloaded and verified like the
# others but never installed: rpd-common gives the login screen wallpaper and
# its licence, rpd-x-core the panel layout and rpd-wayland-core the Wayland
# session's settings (Raspberry Pi OS 13 and later).
readonly ART_PKG="rpd-common" PANEL_PKG="rpd-x-core" WAYLAND_PKG="rpd-wayland-core"
readonly DEBIAN_ARCHIVE="https://deb.debian.org/debian"
# Debian's server for the releases that have reached their end.
readonly DEBIAN_OLD_ARCHIVE="https://archive.debian.org/debian"
readonly DEBIAN_KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
# The keys Debian has retired, which signed the releases now archived.
readonly DEBIAN_OLD_KEYRING="/usr/share/keyrings/debian-archive-removed-keys.gpg"
# Debian releases by major version. Debian's distro-info-data, where
# installed, adds the releases named after this script was written.
readonly KNOWN_RELEASES=(9:stretch 10:buster 11:bullseye 12:bookworm 13:trixie 14:forky 15:duke)
readonly OLDEST=9 OFFLINE_OLDEST=10   # the oldest releases supported, and bundled
# Raspberry Pi OS theme packages built per architecture but holding no compiled
# code: any Raspberry Pi OS release's build for this architecture can be used.
readonly DATA_PKGS=(pixflat-theme pixtrix-theme pix-theme)
readonly DE_OTHER=(xfce gnome budgie cinnamon mate lxqt openbox labwc kde)

# Dependency names that some Debian releases do not have, mapped to the
# package that carries them there; the first available candidate wins. A newer
# release has the renamed successor (libgdk-pixbuf-2.0-0), an older one the
# package a set was later split from (adwaita-icon-theme).
declare -rA DEP_RENAMES=(
	[adwaita-icon-theme-legacy]="adwaita-icon-theme"
	[libgdk-pixbuf2.0-0]="libgdk-pixbuf-2.0-0"
	[libglib2.0-0]="libglib2.0-0t64"
	[libgtk2.0-0]="libgtk2.0-0t64"
	[libatk1.0-0]="libatk1.0-0t64"
	[libpng12-0]="libpng16-16t64 libpng16-16"
	[gtk-update-icon-cache]="libgtk-3-bin"
)
# Dependencies of Raspberry Pi packages that only a Raspberry Pi needs; they
# are left out. The battery plugin of Raspberry Pi OS 10 and 11 asks
# raspi-config only whether it runs on a pi-top, and without it reads the
# computer's own battery.
declare -rA DEP_DROPS=(
	[lxplug-ptbatt]="raspi-config"
)

# Cursor names that toolkits request, mapped to equivalents that may exist in
# the official cursor themes. Missing names become symlinks to official files.
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
	# Hashed names used by Qt and older X11 toolkits
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

# Icon names Debian's programs request, mapped to the Raspberry Pi OS icons:
# the notification area (sound, network, Bluetooth), and the folder, drive and
# network names file managers and dialogs use. Missing names become symlinks
# to official images; a leading "!" also overrides the name
# where the theme maps it to something Raspberry Pi OS's panel does not show.
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
# Icon names the Raspberry Pi OS icon sets draw as the Raspberry Pi logo, for
# the menu button; each shows the Debian logo instead. The other one, "rpi",
# is the window icon of Raspberry Pi's Shutdown dialog before Raspberry Pi
# OS 13, and shows the Shutdown icon instead, as it does from 13 (see
# ICON_ALIASES and _session_icons).
readonly LOGO_ICONS=(start-here distributor-logo gnome-main-menu launch rpi-logo)

# Options (O_*). The remembered ones are saved by an install run in
# $SYS_DIR/options and reused by later runs unless given again.
O_MODE="install"        # install | refresh | uninstall | prepare-upgrade | download | offline
O_THEME="auto"
O_ICONS="auto"
O_WALLPAPER="auto"
O_4K=0
O_PI_APPS=1             # Raspberry Pi's own panel and file manager, where they fit
O_LOGIN=1               # the Raspberry Pi OS login screen, where LightDM is used
O_PI_GREETER=0          # Raspberry Pi's own greeter, which has no session chooser
O_LOGIN_BG="debian"     # the login screen's background: debian, raspios or a path
O_QT=0
O_WAYLAND=auto          # the Wayland session: auto (where the computer suits it), 1 or 0
O_DESKTOPS="none"       # other desktops to give the look, for the running user
O_BUNDLE=""             # --download: release/architecture pairs, empty = all
O_LOG=1
O_YES=0
O_VERBOSE=0
O_INTERACTIVE=0
readonly SAVED_KEYS=(theme icons wallpaper 4k pi-apps login-screen pi-greeter login-background qt wayland)
declare -A GIVEN=()     # remembered options given on this command line

# Theme (T_*), host (H_*) and run state.
H_ARCH="" H_ID="" H_LIKE="" H_CODENAME="" H_PRETTY="" H_SUITE="" H_RPI_ARCH=""
# The computer (see detect_machine) and the display system chosen for it
H_MODEL="" H_CPU="" H_MEM_MB=0 H_OLD_CPU=0 H_GPU="" H_GPU_DRV="" H_GPU_DRVS="" H_RENDER=0 H_KMS=0
H_VIRT="" H_KERNEL="" H_EDITION="" H_DM="" H_DISPLAY="x11" H_DISPLAY_WHY=""
FETCH_PKGS=()           # installed from verified .deb files
DEP_PKGS=()             # of those, offline, the ones installed only as dependencies
HW_PKGS=()              # hardware support (X server, network, Bluetooth, sound, firmware), kept on uninstall
ROOT_PKGS=()            # what is installed for its own sake, not as a dependency
APT_PKGS=()             # installed by name from the APT sources
USE_STACK=0             # 1 when Raspberry Pi's builds replace Debian's panel and file manager (PI_STACK)
STACK_NAMES=()          # those packages, with the other installed ones of their sources
declare -A PKG_VER=() PKG_FILE=() PKG_SHA=() PKG_SIZE=() PKG_SUITE=() PKG_AID=()
declare -A IDX_LOADED=() IDX_FAILED=() IN_SET=()
WORKDIR="" KEYRING="" DEP_INDEX="" BUILD_STAGE="" LOG_FILE="" REPO=""
ARGV=()
NOTES=()                # lines for the summary at the end
STEP=0                  # the number of the step being shown
RELOGIN=0               # 1 when the user has to log in again to see the change
SYS_ROOT=""             # filesystem root the package builder reads themes from (tests)

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
# section heading and verbose-only detail.
log()   { printf '%s\n' "$*" >&2; }
info()  { printf '%s::%s %s\n' "$C_C" "$C_0" "$*" >&2; }
ok()    { printf '%s✔%s %s\n' "$C_G" "$C_0" "$*" >&2; }
warn()  { printf '%s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()   { printf '%s✘ error:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
step()  { STEP=$(( STEP + 1 )); printf '\n%s==> %d. %s%s\n' "$C_C" "$STEP" "$*" "$C_0" >&2; }
debug() { if (( O_VERBOSE )); then printf '%s   %s%s\n' "$C_D" "$*" "$C_0" >&2; fi; }
# A line for the summary at the end, and a warning now.
note()  { warn "$*"; NOTES+=("$*"); }

# Print the first line of stdin. It reads all of it, so the command writing it
# never fails on a closed pipe (set -o pipefail).
first_line() { awk 'NR == 1'; }

# Quote arguments for display.
_q() { local a out=""; for a; do out+="${out:+ }$(printf '%q' "$a")"; done; printf '%s' "$out"; }

# Run a command as root; with --verbose, print it first.
as_root() { debug "sudo $(_q "$@")"; sudo -- "$@"; }

# Ask a yes/no question at the terminal, also when the script comes through a
# pipe. Without a terminal, or with --yes, the default answer is taken.
# Usage: ask QUESTION y|n
ask() {
	local q=$1 def=$2 ans hint="[y/N]"
	[[ $def == y ]] && hint="[Y/n]"
	if (( O_YES )); then return 0; fi
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

# Print the installed version of a package, or nothing.
installed_version() {
	{ dpkg-query -W -f='${db:Status-Abbrev} ${Version}\n' "$1" 2>/dev/null || true; } | awk '$1 ~ /^.i/ { print $2 }'
}

# Print the names of all installed packages, sorted.
installed_names() {
	dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1 ~ /^.i/ { print $2 }' | LC_ALL=C sort
}

# Succeed if APT knows a package, or a package providing it.
apt_has() {
	local out
	out=$(LC_ALL=C apt-cache showpkg "$1" 2>/dev/null) || return 1
	awk '
		/^Versions:/          { s = "v";  next }
		/^Reverse Provides:/  { s = "rp"; next }
		/^[A-Z][A-Za-z ]*:/   { s = "";   next }
		(s == "v" || s == "rp") && NF { found = 1 }
		END { exit !found }' <<<"$out"
}

# Write stdin to a root-owned system file, readable by all, through a temporary
# file and a rename, so an interrupted write keeps the old file whole.
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

# Read the saved options into the O_* variables not given on the command line.
# The file is parsed, never sourced; an invalid value is ignored.
load_options() {
	local key val
	[[ -f $SYS_DIR/options ]] || return 0
	# Only an update reuses them: a fresh install decides for this computer
	[[ -n $(installed_version "$APP_PKG")$(installed_version "$PREV_PKG")$(installed_version "$OLD_PKG") ]] || return 0
	while IFS='=' read -r key val; do
		[[ " ${SAVED_KEYS[*]} " == *" $key "* && -z ${GIVEN[$key]:-} ]] || continue
		set_option "$key" "$val" 2>/dev/null || debug "ignoring saved option $key=$val"
	done <"$SYS_DIR/options"
}

# Set one remembered option; fail on an invalid value.
# Usage: set_option KEY VALUE
set_option() {
	case $1:$2 in
		theme:auto|theme:pixflat|theme:pixnoir|theme:pixtrix|theme:pixonyx|theme:pix) O_THEME=$2 ;;
		icons:auto|icons:pixflat|icons:pixtrix|icons:pix) O_ICONS=$2 ;;
		wallpaper:?*)
			[[ $2 =~ ^[A-Za-z0-9._/+-]+$ && $2 != *..* ]] || return 1
			O_WALLPAPER=$2 ;;
		4k:[01]) O_4K=$2 ;;
		pi-apps:[01]) O_PI_APPS=$2 ;;
		login-screen:[01]) O_LOGIN=$2 ;;
		pi-greeter:[01]) O_PI_GREETER=$2 ;;
		login-background:raspios|login-background:debian) O_LOGIN_BG=$2 ;;
		login-background:/?*)
			[[ $2 =~ ^[A-Za-z0-9._/+-]+$ && $2 != *..* ]] || return 1
			O_LOGIN_BG=$2 ;;
		qt:[01]) O_QT=$2 ;;
		wayland:auto|wayland:on) O_WAYLAND=${2/on/1} ;;
		wayland:off|wayland:0) O_WAYLAND=0 ;;
		# Saved by 3.2.0 and earlier, where the Wayland session was the default
		wayland:1) O_WAYLAND=auto ;;
		*) return 1 ;;
	esac
}

# Print the remembered options as the options file holds them.
option_lines() {
	printf 'theme=%s\nicons=%s\nwallpaper=%s\n4k=%s\npi-apps=%s\nlogin-screen=%s\npi-greeter=%s\nlogin-background=%s\nqt=%s\nwayland=%s\n' \
		"$O_THEME" "$O_ICONS" "$O_WALLPAPER" "$O_4K" "$O_PI_APPS" "$O_LOGIN" "$O_PI_GREETER" "$O_LOGIN_BG" "$O_QT" "$(case $O_WAYLAND in 1) echo on ;; 0) echo off ;; *) echo auto ;; esac)"
}

# Save the options of this install run for later runs.
save_options() {
	if ! option_lines | cmp -s - "$SYS_DIR/options" 2>/dev/null; then
		option_lines | sys_write "$SYS_DIR/options" || note "The options could not be saved; give them again next time."
	fi
}

# Take the run lock, waiting while another run holds it, so two runs never
# change the system at once.
take_run_lock() {
	local lock=/run/lock/$APP_NAME.lock
	{ [[ -e $lock ]] || ( umask 022; : >"$lock" ); } 2>/dev/null
	{ exec 9<"$lock"; } 2>/dev/null || die "cannot open the run lock $lock"
	if ! flock -n 9; then
		info "Another $APP_NAME run is in progress; waiting for it to finish"
		flock 9
	fi
}

# Stop when an interrupted dpkg run must be repaired first: APT would refuse
# every change, and its refusals would read as this script's.
require_dpkg_ready() {
	[[ -z $(ls -A /var/lib/dpkg/updates 2>/dev/null) ]] \
		&& ! grep -qvxE 'installed|config-files|not-installed' <<<"$(dpkg-query -W -f='${db:Status-Status}\n' 2>/dev/null)" \
		&& return 0
	die "dpkg was interrupted earlier: run 'sudo dpkg --configure -a' and 'sudo apt-get -f install', then run this again"
}

# Obtain root rights through sudo, once, before changing the system.
prepare_root() {
	command -v sudo >/dev/null || die "sudo is needed: install it and add $(id -un) to the sudo group"
	sudo true || die "$(id -un) cannot use sudo"
}

# Use the user's own session bus and display when the script runs outside the
# desktop (SSH, a text console), so the desktop can be reloaded and the
# settings of other desktops reach the running session.
adopt_session() {
	local uid pid p line
	uid=$(id -u)
	[[ -S /run/user/$uid/bus ]] && export XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
	[[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && return 0
	for p in lxsession xfce4-session lxqt-session gnome-shell budgie-panel cinnamon mate-session plasmashell labwc openbox; do
		pid=$(pgrep -u "$uid" -n -x "$p" 2>/dev/null) && break
	done
	[[ -n ${pid:-} ]] || return 0
	while IFS= read -r -d '' line; do
		case $line in
			DISPLAY=*|WAYLAND_DISPLAY=*|XAUTHORITY=*|XDG_CURRENT_DESKTOP=*|DESKTOP_SESSION=*|LABWC_PID=*) export "${line?}" ;;
		esac
	done < <(cat -- "/proc/$pid/environ" 2>/dev/null || true)
}

###############################################################################
# 3. Packages: themes, package sets, host and release
###############################################################################

# Set the T_* variables for a theme. The icon option may choose another set.
set_theme() {
	# T_GTK names the GTK theme and the Openbox, labwc and Xfwm4 themes alike
	case $1 in
		pixflat) T_GTK=PiXflat T_ICON_BASE=PiXflat T_ERA=bookworm T_DARK=0
		         T_DESC="PiXflat — light, Raspberry Pi OS Bookworm" ;;
		pixnoir) T_GTK=PiXnoir T_ICON_BASE=PiXflat T_ERA=bookworm T_DARK=1
		         T_DESC="PiXnoir — dark, Raspberry Pi OS Bookworm" ;;
		pixtrix) T_GTK=PiXtrix T_ICON_BASE=PiXtrix T_ERA=trixie T_DARK=0
		         T_DESC="PiXtrix — light, Raspberry Pi OS Trixie" ;;
		pixonyx) T_GTK=PiXonyx T_ICON_BASE=PiXtrix T_ERA=trixie T_DARK=1
		         T_DESC="PiXonyx — dark, Raspberry Pi OS Trixie" ;;
		pix)     T_GTK=PiX T_ICON_BASE=PiX T_ERA=legacy T_DARK=0
		         T_DESC="PiX — legacy Raspberry Pi OS Buster/Bullseye" ;;
		*) die "unknown theme '$1'" ;;
	esac
	if [[ $T_ERA == trixie ]]; then
		T_FONT_FAMILY="Nunito Sans" T_FONT_WEIGHT=Light T_FONT="Nunito Sans Light 12" T_WALL_DEFAULT=sunrise.jpg
	else
		T_FONT_FAMILY=PibotoLt T_FONT_WEIGHT=Normal T_FONT="PibotoLt 12" T_WALL_DEFAULT=fisherman.jpg
	fi
	case $O_ICONS in pixflat) T_ICON_BASE=PiXflat ;; pixtrix) T_ICON_BASE=PiXtrix ;; pix) T_ICON_BASE=PiX ;; esac
	# The adapted icon set, with the Debian logo and the names Debian's
	# programs use (see gen_icon_overlay)
	T_ICONS=$T_ICON_BASE-Debian
	# Values used by Raspberry Pi OS itself (raspberrypi-ui-mods / rpd-x-core)
	T_COLOR_SCHEME='selected_bg_color:#878791919b9b\nselected_fg_color:#f0f0f0f0f0f0\nbar_bg_color:#ededececebeb\nbar_fg_color:#000000000000\n'
	T_DESK_BG="#d6d6d3d3dede" T_DESK_FG="#e8e8e8e8e8e8" T_DESK_SHADOW="#d6d6d3d3dede"
	T_CURSOR_SIZE=24
	T_SOUND_THEME=freedesktop   # Raspberry Pi OS enables event sounds with the default theme
}

# Print the Raspberry Pi OS package that provides a theme or an icon set.
theme_pkg() {
	case $1 in
		pixflat|pixnoir) echo pixflat-theme ;;
		pixtrix|pixonyx) echo pixtrix-theme ;;
		pix)             echo pix-theme ;;
	esac
}
icons_pkg() { case $1 in pixflat) echo pixflat-icons ;; pixtrix) echo pixtrix-icons ;; pix) echo rpd-icons ;; esac; }

# Raspberry Pi OS packages for a release: every theme with its icons, fonts,
# GTK 2 engines, wallpapers (every set the release publishes) and login screen,
# and its own panel and file manager: from Raspberry Pi OS 13 its programs,
# before that its builds of Debian's (see pi_stack).
# Usage: rpi_pkgs SUITE ARCH [4K]
rpi_pkgs() {
	printf '%s\n' pixflat-theme pixtrix-theme pix-theme pixflat-icons pixtrix-icons rpd-icons \
		gtk2-engines-pixflat gtk2-engines-clearlookspix fonts-piboto fonts-nunito-sans pi-greeter
	# The wallpaper sets of this and every later release: they hold no code
	local s
	for s in $(releases); do
		suite_ge "$s" "$1" || continue
		if (( ${3:-0} )); then index_names "$(rpi_aid)" "$s" "$2" | grep -E '^rpd-wallpaper.*-4k$' || true
		else index_names "$(rpi_aid)" "$s" "$2" | grep -E '^rpd-wallpaper' | grep -v -- '-4k$' || true; fi
	done | awk '!seen[$0]++'
	if suite_ge "$1" trixie; then pi_apps "$1" "$2"; wayland_pkgs "$1" "$2"; else pi_stack "$1" "$2"; fi
}

# Raspberry Pi's Wayland panel with every plugin Raspberry Pi OS installs (its
# rpd-wayland-core) that works on Debian. Usage: wayland_pkgs SUITE ARCH
wayland_pkgs() {
	# pipanel (Appearance Settings) runs in rpcc (Control Centre), with sudopwd
	printf '%s\n' wf-panel-pi pipanel rpcc sudopwd
	index_candidates "$(rpi_aid)" "$1" "$2" "$WAYLAND_PKG" 2>/dev/null | first_line | cut -f6 | depnames \
		| grep '^wfplug-' | grep -vxE "wfplug-($WF_DROP)" || true
}
# Debian packages of the Wayland session: the compositor, wallpaper, display
# settings, XSETTINGS for X applications, and Xwayland.
wayland_debs() { printf '%s\n' labwc swaybg kanshi xsettingsd wlr-randr xwayland; }
# Debian packages of the X server, which the login screen always needs, with
# Mesa's 3D drivers. Kept on uninstall.
x11_debs() { printf '%s\n' xserver-xorg x11-utils libgl1-mesa-dri; }
# Debian packages of the login screen: LightDM with Debian's greeter, which
# takes the Raspberry Pi OS style, where no other display manager is in use,
# and Debian's login artwork (desktop-base) behind it. Kept on uninstall, so
# the computer keeps its login screen. ALL gives every one, for offline
# repositories. Usage: login_debs [ALL]
login_debs() {
	(( O_LOGIN )) || [[ ${1:-0} == 1 ]] || return 0
	if [[ ${1:-0} == 1 || -z $H_DM || $H_DM == lightdm ]]; then printf '%s\n' lightdm lightdm-gtk-greeter; fi
	[[ $O_LOGIN_BG != debian && ${1:-0} != 1 ]] || echo desktop-base
}
# Succeed if LightDM is installed, or is about to be.
with_lightdm() { [[ -n $(installed_version lightdm) ]] || login_debs | grep -qx lightdm; }

# Raspberry Pi's own programs: its file manager, which draws the desktop and
# opens folders, installed beside Debian's (see fm_coinstall); its Shutdown and
# Run dialogs; its panel, with every plugin Raspberry Pi OS installs (its
# rpd-x-core) that works on Debian, so any of them can be added to the panel,
# and those its panel layout uses (see _pi_panel_layout). Debian's own panel
# and its plugins stay installed beside it. Usage: pi_apps SUITE ARCH
pi_apps() {
	local t
	printf '%s\n' pcmanfm-pi pishutdown gui-runcmd lxpanel-pi
	{
		for t in $(panel_plugins "$1" "$2"); do printf 'lpplug-%s\n' "${t/#smenu/menu}"; done
		index_candidates "$(rpi_aid)" "$1" "$2" "$PANEL_PKG" 2>/dev/null | first_line | cut -f6 | depnames \
			| grep '^lpplug-' | grep -vxE "lpplug-($PANEL_DROP)" || true
	} | awk '!seen[$0]++'
}

# Print the plugin types of Raspberry Pi OS's panel layout for a release that
# work on Debian; the built-in ones of the panel program are left out.
# Usage: panel_plugins SUITE ARCH
panel_plugins() {
	local f
	f=$(pi_unpack "$PANEL_PKG" "$1" "$2" 2>/dev/null) && f+=/etc/xdg/lxpanel-pi/panels/panel && [[ -f $f ]] \
		|| { printf '%s\n' smenu ejecter bluetooth volumepulse clock batt magnifier | _no_battery; return 0; }
	sed -n 's/^[[:space:]]*type=//p' "$f" | grep -vxE "$PANEL_DROP|space|separator|launchbar|taskbar|tray" | awk '!seen[$0]++' | _no_battery
}

# The same for the panel of a Raspberry Pi OS release before 13, from its
# raspberrypi-ui-mods. Usage: lx_panel_plugins SUITE ARCH
lx_panel_plugins() {
	local f
	f=$(pi_unpack raspberrypi-ui-mods "$1" "$2" 2>/dev/null) && f+=/etc/xdg/lxpanel/LXDE-pi/panels/panel && [[ -f $f ]] \
		|| { printf '%s\n' smenu ejecter bluetooth volumepulse batt magnifier | _no_battery; return 0; }
	sed -n 's/^[[:space:]]*type=//p' "$f" | grep -vxE "$PANEL_DROP|space|separator|launchbar|taskbar|tray|menu|dclock" \
		| awk '!seen[$0]++' | _no_battery
}

# Pass plugin types on, without the battery's where this computer has none
# (except when building packages/, for any computer).
_no_battery() { if [[ $O_MODE == download ]] || has_battery; then cat; else grep -vxE 'batt|ptbatt' || true; fi; }

# Raspberry Pi OS's panel and file manager before Raspberry Pi OS 13: its
# builds of Debian's (PI_STACK), those of any other package of the same
# sources installed here, and the plugins its panel layout uses that
# Raspberry Pi publishes (lxplug-*, the menu's as lxplug-menu).
# Usage: pi_stack SUITE ARCH
pi_stack() {
	local t names
	printf '%s\n' "${PI_STACK[@]}"
	[[ $O_MODE == download ]] || stack_extras
	names=$(index_names "$(rpi_aid)" "$1" "$2")
	for t in $(lx_panel_plugins "$1" "$2"); do
		t=lxplug-${t/#smenu/menu}
		if grep -qxF "$t" <<<"$names"; then echo "$t"; fi
	done
}
# Print the other installed packages of the sources of PI_STACK.
stack_extras() {
	dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${source:Package}\n' 2>/dev/null \
		| awk -v re="^($PI_STACK_SRC)\$" '$1 ~ /^.i/ && $3 ~ re { print $2 }' \
		| grep -vxF -f <(printf '%s\n' "${PI_STACK[@]}") || true
}
# Succeed if a .deb file is one of Raspberry Pi's builds of Debian's panel and
# file manager (of PI_STACK's sources).
stack_deb() {
	local src
	src=$(dpkg-deb -f "$1" Source)
	src=${src%% *}
	[[ ${src:-$(dpkg-deb -f "$1" Package)} =~ ^($PI_STACK_SRC)$ ]]
}
# Succeed if this computer has a battery of its own (not a mouse's or a
# keyboard's).
has_battery() {
	local d
	for d in /sys/class/power_supply/*; do
		[[ $(cat "$d/type" 2>/dev/null) == Battery && $(cat "$d/scope" 2>/dev/null) != Device ]] && return 0
	done
	return 1
}
# Plugins of Raspberry Pi OS's panel that do not work on Debian: the updater
# and power plugins need Raspberry Pi system tools or hardware; the network
# plugins need a Raspberry Pi rebuild of a Debian library or Raspberry Pi's
# network settings (nm-applet shows the same icons in the tray).
readonly PANEL_DROP="updater|power|netman|dhcpcdui"
# The network plugins of Raspberry Pi OS's panels, whose place the tray takes.
readonly PANEL_NET="netman|dhcpcdui"
# Before Raspberry Pi OS 13, Raspberry Pi's panel and file manager are its own
# builds of Debian's packages, under Debian's names; from Raspberry Pi OS 11
# they use GTK 3, while Debian 11 and 12 build theirs, and their plugins, for
# GTK 2, so the two cannot be mixed. With --pi-apps on Debian 10 to 12 these
# replace Debian's, with any other package of their sources installed here;
# --uninstall and --prepare-upgrade put Debian's back.
readonly PI_STACK=(lxpanel lxpanel-data pcmanfm libfm4 libfm-gtk4 libfm-modules libfm-data libfm-gtk-data libfm-extra4)
readonly PI_STACK_SRC="lxpanel|libfm|pcmanfm"
# Debian panel applets that work in Raspberry Pi's panel.
readonly DEBIAN_APPLETS="xkb weather volume thermal monitors deskno cpufreq"
# The same for the Wayland panel, and the Raspberry Pi Connect and on-screen
# keyboard buttons, which need Raspberry Pi's own services.
readonly WF_DROP="updater|power|netman|connect|squeek"

# Print the Raspberry Pi OS programs this script installed: built against one
# Debian release's libraries, --prepare-upgrade removes them first. The themes
# and their GTK 2 engines, which need only GTK 2, stay.
release_bound_pkgs() {
	local p
	while read -r p; do
		[[ $(dpkg-query -W -f='${Architecture}' "$p" 2>/dev/null) != all ]] || continue
		[[ " ${DATA_PKGS[*]} " != *" $p "* && $p != gtk2-engines-* ]] || continue
		if [[ -z $(apt-cache madison "$p" 2>/dev/null) ]]; then echo "$p"; fi   # not from the APT sources
	done < <(cat "$SYS_DIR/installed-packages" 2>/dev/null)
}

# Debian packages the session runs on: the LXDE session manager, window
# manager, panel and file manager (also the fallback for Raspberry Pi's), gvfs
# for the file managers' Trash and drives, the appearance settings, and dconf
# for the sessions' own settings. (Raspberry Pi OS also starts xcompmgr with
# an option Debian's xcompmgr does not have, so no compositor runs there
# either.)
session_debs() { printf '%s\n' lxsession openbox lxpanel pcmanfm gvfs-backends gvfs-fuse lxappearance dconf-cli libglib2.0-bin; }

# Debian packages the themes need: the GTK 2 pixmap engine and runtime, the
# icon sets the Raspberry Pi sets inherit, the sound theme and the monospace
# font. Usage: theme_debs SUITE
theme_debs() {
	printf '%s\n' gtk2-engines-pixbuf libgtk2.0-bin gnome-icon-theme sound-theme-freedesktop "$(mono_font_pkg "$1")"
	if suite_ge "$1" trixie; then printf '%s\n' adwaita-icon-theme-legacy; fi
}
# Succeed if this computer has a Wi-Fi or a Bluetooth adapter.
has_wifi() { compgen -G '/sys/class/ieee80211/*' >/dev/null; }
has_bluetooth() { compgen -G '/sys/class/bluetooth/hci*' >/dev/null; }

# Debian packages of the panel's network and Bluetooth icons, as Raspberry Pi
# OS has them, and of its Help menu. With a Wi-Fi adapter: NetworkManager and
# the Wi-Fi tools, unless another network manager is installed; its tray icon
# (nm-applet) also where NetworkManager is installed already. With a Bluetooth
# adapter: BlueZ and Bluetooth audio for the sound server in use, and blueman
# where Debian's panel, which has no Bluetooth plugin, is used. ALL gives every
# one, for offline repositories. Usage: tray_debs SUITE [ALL]
tray_debs() {
	local all=${2:-0} nm=0
	[[ -n $(installed_version network-manager) ]] && nm=1
	if (( all )) || { (( ! nm )) && has_wifi && [[ -z $(installed_version connman)$(installed_version wicd) ]]; }; then
		nm=1
		printf '%s\n' network-manager wpasupplicant iw wireless-regdb rfkill
	fi
	(( nm )) && nm_applet_pkg "$1"
	if (( all )) || has_bluetooth; then
		printf '%s\n' bluez rfkill
		if (( all )) || [[ -n $(installed_version pipewire) ]]; then echo libspa-0.2-bluetooth; fi
		if [[ -n $(installed_version pulseaudio) ]]; then echo pulseaudio-module-bluetooth; fi
		# Raspberry Pi's panel has its own Bluetooth plugin
		suite_ge "$1" trixie || (( USE_STACK )) || echo blueman
	fi
	printf '%s\n' debian-reference-common debian-reference-en
}
# Debian packages for sound, where a sound card exists and no sound server is
# installed: PipeWire from Debian 12, PulseAudio before. Raspberry Pi OS's
# volume plugin needs the PulseAudio interface, which both give.
# Usage: audio_debs SUITE
audio_debs() {
	compgen -G '/sys/class/sound/card*' >/dev/null || return 0
	[[ -z $(installed_version pipewire-pulse)$(installed_version pulseaudio) ]] || return 0
	if suite_ge "$1" bookworm; then echo pipewire-audio; else echo pulseaudio; fi
}

# Print the firmware files the kernel could not load during this boot, as
# Debian's kernel logs them: a Wi-Fi, Bluetooth or sound device, among others,
# then has its driver but cannot work.
missing_firmware() {
	{ as_root journalctl -k -b -q -o cat 2>/dev/null || as_root dmesg 2>/dev/null || true; } \
		| sed -nE 's/.*firmware: failed to load ([^ ]+).*/\1/p; s/.*Direct firmware load for ([^ ]+) failed.*/\1/p' | sort -u
}

# Print the Debian packages holding the firmware files the kernel missed, from
# the signed Contents index of Debian's firmware component of this release
# (non-free-firmware, non-free before Debian 12). Debian only: derivatives
# ship firmware their own way.
firmware_debs() {
	local names comp=non-free-firmware suite=$H_CODENAME d sha
	[[ $H_ID == debian && -n $suite && -z $REPO ]] || return 0
	names=$(missing_firmware)
	[[ -n $names ]] || return 0
	[[ $suite == sid ]] || suite_ge "$suite" bookworm || comp=non-free
	release_load debian "$suite" || return 0
	d=$WORKDIR/index/debian/$suite
	sha=$(awk -v f="$comp/Contents-all.gz" '/^SHA256:/ { s = 1; next } /^[^ ]/ { s = 0 } s && $3 == f { print $1; exit }' "$d/Release")
	[[ -n $sha ]] && fetch "$(archive_url debian "$suite")/dists/$suite/$comp/Contents-all.gz" "$d/firmware.gz" 2>/dev/null || return 0
	sha256_check "$d/firmware.gz" "$sha"
	gzip -dc "$d/firmware.gz" | NAMES=$names awk '
		BEGIN { n = split(ENVIRON["NAMES"], a, "\n"); for (i = 1; i <= n; i++) want["lib/firmware/" a[i]] = 1 }
		{ f = $1; sub(/^usr\//, "", f); if (f in want) { p = $NF; sub(/.*\//, "", p); print p } }' | sort -u
}

# Debian package providing nm-applet (network-manager-gnome is transitional
# from Debian 13).
nm_applet_pkg() { if suite_ge "$1" trixie; then echo network-manager-applet; else echo network-manager-gnome; fi; }
# Debian package providing Liberation Mono, the Raspberry Pi OS monospace font.
mono_font_pkg() { if suite_ge "$1" trixie; then echo fonts-liberation; else echo fonts-liberation2; fi; }

# Load the Debian release numbers: the built-in list, then Debian's own
# distro-info-data, which names the releases to come.
declare -A REL_VER=()
load_releases() {
	local e v c
	for e in "${KNOWN_RELEASES[@]}"; do REL_VER[${e#*:}]=${e%%:*}; done
	[[ -r /usr/share/distro-info/debian.csv ]] || return 0
	while IFS=, read -r v _ c _; do
		if [[ $v =~ ^[0-9]+ && $c =~ ^[a-z]+$ ]]; then REL_VER[$c]=${v%%.*}; fi
	done </usr/share/distro-info/debian.csv
}
# Print the archive the Raspberry Pi OS packages come from: packages/ for
# an offline install, else Raspberry Pi's.
rpi_aid() { if [[ -n $REPO && $O_MODE != download ]]; then echo local; else echo rpi; fi; }

# Print the Debian releases from Debian 9, newest first.
releases() {
	local c
	for c in "${!REL_VER[@]}"; do if (( REL_VER[$c] >= OLDEST )); then echo "${REL_VER[$c]} $c"; fi; done | sort -rn | cut -d' ' -f2
}
# Print the major version of a release; fail if unknown.
suite_rank() { [[ -n ${REL_VER[$1]:-} ]] && echo "${REL_VER[$1]}" || { echo 0; return 1; }; }
# Succeed if the first release is the second one or newer.
# Usage: suite_ge SUITE OTHER-SUITE
suite_ge() { (( $(suite_rank "$1") >= $(suite_rank "$2") )); }

# Print the lxsession profile of the session, as Raspberry Pi OS names it in
# that release: rpd-x from Raspberry Pi OS 13, LXDE-pi before.
session_profile() { if suite_ge "$H_SUITE" trixie; then echo rpd-x; else echo LXDE-pi; fi; }
# Print its application menu prefix.
menu_prefix() { if suite_ge "$H_SUITE" trixie; then echo rpd-; else echo lxde-pi-; fi; }
# The Openbox settings file, as Raspberry Pi OS names it.
ob_file() { if suite_ge "$H_SUITE" trixie; then echo rpd-rc.xml; else echo lxde-pi-rc.xml; fi; }

# Print a field of /etc/os-release.
os_release() { sed -n "s/^$1=//p" /etc/os-release | first_line | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"; }

# Detect the architecture and the distribution.
detect_host() {
	command -v dpkg >/dev/null && command -v apt-get >/dev/null || die "Debian or a derivative is needed (dpkg and apt not found)"
	H_ARCH=$(dpkg --print-architecture)
	if [[ -r /etc/os-release ]]; then
		H_ID=$(os_release ID) H_LIKE=$(os_release ID_LIKE)
		H_CODENAME=$(os_release VERSION_CODENAME) H_PRETTY=$(os_release PRETTY_NAME)
	fi
	if [[ $H_ID != debian && " $H_LIKE " != *" debian "* && " $H_LIKE " != *" ubuntu "* ]]; then
		warn "untested distribution '${H_PRETTY:-unknown}', continuing anyway"
	fi
	detect_machine
}

# Detect the computer: model, processor, memory, graphics, kernel, desktop.
detect_machine() {
	local d drv slot name t
	H_KERNEL=$(uname -r)
	H_MODEL=$( { tr -d '\0' </proc/device-tree/model; } 2>/dev/null || true)
	if [[ -z $H_MODEL && -r /sys/class/dmi/id/product_name ]]; then
		H_MODEL=$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_version /sys/class/dmi/id/product_name 2>/dev/null \
			| grep -viE '^(to be filled|system (product|manufacturer|version)|default string|not specified|none)?[[:space:]]*$' | awk '!seen[$0]++' | paste -sd' ' -)
	fi
	H_CPU=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | first_line)
	[[ -n $H_CPU ]] || H_CPU=$(uname -m)
	H_CPU="$(tr -s ' ' <<<"$H_CPU") ($(nproc 2>/dev/null || echo 1) cores)"
	H_MEM_MB=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
	# PC processors without SSE4.2 predate 2009
	H_OLD_CPU=0
	if [[ $H_ARCH == amd64 || $H_ARCH == i386 ]] && ! grep -qw sse4_2 /proc/cpuinfo; then H_OLD_CPU=1; fi
	H_VIRT=$(systemd-detect-virt 2>/dev/null || true)
	[[ -n $H_VIRT ]] || H_VIRT=none
	# The first real graphics driver (not the boot framebuffer)
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
	# NVIDIA's driver may not register a DRM card
	if [[ -z $H_GPU_DRV && -d /sys/module/nvidia ]]; then H_GPU_DRV=nvidia H_GPU="NVIDIA"; fi
	[[ -n $H_GPU_DRV ]] || H_GPU_DRV=$(awk '{ print $1 }' <<<"$H_GPU_DRVS")
	H_RENDER=0; if compgen -G '/dev/dri/renderD*' >/dev/null; then H_RENDER=1; fi
	# Display outputs exist only with kernel modesetting, which Wayland needs
	H_KMS=0; if compgen -G '/sys/class/drm/card[0-9]*-*' >/dev/null; then H_KMS=1; fi
	H_EDITION=""
	for t in gnome kde xfce cinnamon mate lxqt lxde gnome-flashback; do
		[[ -n $(installed_version "task-$t-desktop") ]] || continue
		case $t in gnome) name=GNOME ;; kde) name="KDE Plasma" ;; xfce) name=Xfce ;; lxqt) name=LXQt ;; lxde) name=LXDE ;;
			gnome-flashback) name="GNOME Flashback" ;; *) name=${t^} ;; esac
		H_EDITION+="${H_EDITION:+, }$name"
	done
	if [[ -z $H_EDITION ]]; then
		H_EDITION=$(grep -hs '^Name=' /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop \
			| grep -v 'Raspberry Pi Desktop' | sed 's/^Name=//' | sort -u | paste -sd, - | sed 's/,/, /g')
	fi
	H_DM=$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service 2>/dev/null)
	[[ -n $H_DM && $H_DM != display-manager ]] || H_DM=$(basename "$(cat /etc/X11/default-display-manager 2>/dev/null)" 2>/dev/null)
}

# Choose Wayland or X for the session: Wayland on every Raspberry Pi, as
# Raspberry Pi OS does, and on capable PCs with Debian 13+; X otherwise.
pick_display() {
	local why=""
	if ! suite_ge "$H_SUITE" trixie; then why="the Wayland session needs Debian 13 or later"
	elif [[ $O_WAYLAND == 0 ]]; then why="--no-wayland"
	elif (( ! H_KMS )) && [[ $H_GPU_DRV == nvidia ]]; then
		why="NVIDIA's driver has kernel modesetting off, which Wayland needs"
		[[ $O_WAYLAND != 1 ]] || note "Wayland cannot start: NVIDIA's driver has kernel modesetting off. See 'X or Wayland' in the README to enable it."
	elif (( ! H_KMS )); then
		why="the graphics have no kernel modesetting, which Wayland needs"
		[[ $O_WAYLAND != 1 ]] || note "Wayland cannot start here: $why."
	elif [[ $O_WAYLAND == 1 ]]; then H_DISPLAY=wayland H_DISPLAY_WHY="--wayland"; return 0
	elif [[ $H_MODEL == "Raspberry Pi"* ]]; then
		H_DISPLAY=wayland H_DISPLAY_WHY="Raspberry Pi OS uses Wayland on every Raspberry Pi"; return 0
	elif (( H_MEM_MB < 2000 )); then why="less than 2 GB of memory"
	elif [[ $H_ARCH == i386 || $H_ARCH == armhf || $H_ARCH == armel ]]; then why="a 32-bit system"
	elif (( H_OLD_CPU )); then why="an older processor (without SSE4.2)"
	elif [[ $H_GPU_DRV == nvidia ]]; then why="NVIDIA's own driver works best with X"
	elif [[ $H_GPU_DRV == nouveau ]]; then why="the open NVIDIA driver (nouveau) is more reliable with X"
	elif [[ -z $H_GPU_DRV ]]; then why="the graphics have no kernel driver"
	elif (( ! H_RENDER )); then why="the graphics ($H_GPU_DRV) have no 3D acceleration"
	else
		case $H_GPU_DRV in
			radeon) why="older AMD graphics (radeon driver)" ;;
			i915|xe|amdgpu|virtio_gpu|vmwgfx|vc4|v3d|msm|panfrost|panthor|lima|etnaviv|rockchip|rockchip-drm|mediatek-drm|meson|sun4i-drm|imx-drm)
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

# Print the major Debian version this system is or follows: from os-release,
# else, for testing, unstable and derivatives (Ubuntu, Mint, ...), from
# /etc/debian_version, which names the release they follow ("forky/sid",
# "13.1"); fail if unknown.
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
# newest release Raspberry Pi publishes the themes for, up to this Debian
# release. So a Debian release Raspberry Pi OS has not reached yet uses the
# newest Raspberry Pi OS, and moves on by itself once Raspberry Pi publishes
# its own. On an architecture Raspberry Pi does not publish, the packages
# without compiled code are taken from another one's indexes.
pick_suite() {
	local rank s
	rank=$(host_rank) && (( rank >= OLDEST )) || die "Debian $OLDEST or later is needed (found ${H_PRETTY:-an unknown release})"
	# The newest release up to this one; for an older Debian, the oldest one,
	# whose packages with compiled code are then left out by their dependencies
	H_SUITE=""
	for s in $(releases); do
		if [[ $(rpi_aid) == local ]]; then [[ -d $REPO/dists/$s ]] || continue
		else rpi_populated "$s" || continue; fi
		H_SUITE=$s
		(( $(suite_rank "$s") > rank )) || break
	done
	[[ -n $H_SUITE ]] || die "Raspberry Pi publishes nothing of the look${REPO:+ in packages/}"
	H_RPI_ARCH=$H_ARCH
	if ! grep -qxF "$H_ARCH" <<<"$(rpi_arches "$H_SUITE")"; then
		H_RPI_ARCH=""
		note "Raspberry Pi publishes no builds for $H_ARCH: the themes, icons, fonts and wallpapers are installed, but not its panel, file manager, login screen and GTK 2 engines."
	fi
	debug "Debian $rank on $H_ARCH: Raspberry Pi OS $H_SUITE, ${H_RPI_ARCH:-architecture-independent packages only}"
}

# Print the architectures Raspberry Pi publishes for a release, as its signed
# Release file (or packages/) lists them.
rpi_arches() {
	local d
	if [[ $(rpi_aid) == local ]]; then
		for d in "$REPO/dists/$1"/main/binary-*; do [[ -d $d ]] && echo "${d##*binary-}"; done
	else
		release_load rpi "$1" || return 0
		sed -n 's/^Architectures:[[:space:]]*//p' "$WORKDIR/index/rpi/$1/Release" | tr ' ' '\n' | grep -v '^$'
	fi
}
# Print the architecture whose Raspberry Pi indexes serve this system.
rpi_arch() { printf '%s\n' "${H_RPI_ARCH:-$(rpi_arches "$H_SUITE" | first_line)}"; }

# Succeed if Raspberry Pi publishes the look for a release: its themes, icons
# or GTK 2 engines (a new release starts empty), for this or another
# architecture. Usage: rpi_populated SUITE [ARCH]
rpi_populated() {
	local a=${2:-}
	if [[ -z $a ]]; then
		a=$(rpi_arches "$1")
		a=$(grep -xF "$H_ARCH" <<<"$a" || first_line <<<"$a")
	fi
	[[ -n $a ]] && grep -qxE 'pix(flat|trix)?-(theme|icons)|rpd-icons|gtk2-engines-pixflat' <<<"$(index_names rpi "$1" "$a")"
}

# Print the theme matching this Debian release: the Raspberry Pi OS Trixie look
# (PiXtrix) on Debian 13 and newer, the Bookworm look (PiXflat) otherwise.
default_theme() { if suite_ge "$H_SUITE" trixie; then echo pixtrix; else echo pixflat; fi; }

# Print the theme the options choose.
chosen_theme() { if [[ $O_THEME == auto ]]; then default_theme; else echo "$O_THEME"; fi; }

###############################################################################
# 4. Archives: signed indexes, resolution, download, repacking
#   rpi     archive.raspberrypi.org, checked against the pinned key
#   debian  deb.debian.org (archive.debian.org for archived releases),
#           checked against debian-archive-keyring
#   local   the offline repository in packages/, checked by SHA256SUMS
###############################################################################

# Print the base URLs or path of an archive, in the order they are tried.
archive_bases() {
	case $1 in
		rpi)    printf '%s\n' "$RPI_ARCHIVE" ;;
		debian) printf '%s\n' "$DEBIAN_ARCHIVE" "$DEBIAN_OLD_ARCHIVE" ;;
		local)  printf '%s\n' "$REPO" ;;
	esac
}
# Print the base URL or path an archive serves a release from.
# Usage: archive_url ARCHIVE SUITE
declare -A BASE=()
archive_url() { printf '%s\n' "${BASE[$1/$2]:-$(archive_bases "$1" | first_line)}"; }

# Fetch and verify the signed Release file of a release, once. Debian moves
# a release to its archive server when it reaches its end; it is looked for
# there next. Fails if no server has the release.
# Usage: release_load ARCHIVE SUITE
release_load() {
	local aid=$1 suite=$2 d="$WORKDIR/index/$1/$2" base
	[[ $aid != local && ! -f $d/Release ]] || return 0
	[[ -z ${IDX_FAILED[$aid/$suite]:-} ]] || return 1
	mkdir -p "$d"
	[[ $aid != rpi ]] || setup_keyring
	for base in $(archive_bases "$aid"); do
		fetch "$base/dists/$suite/InRelease" "$d/InRelease" 2>/dev/null || continue
		verify_inrelease "$aid" "$d/InRelease" "$d/Release"
		release_ok "$d/Release" "$suite" "$base" || die "the signed index at $base/dists/$suite is not a current $suite index"
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

# Unpack a Raspberry Pi OS package that is never installed (for its settings
# or artwork) into a directory of $WORKDIR/pi, once, and print it.
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

# Download from an official archive (or copy a local path). Only HTTPS URLs of
# the Raspberry Pi and Debian archives are accepted, and redirects are refused,
# so nothing can come from another host.
# Usage: fetch URL|PATH OUTPUT [SHOW-PROGRESS]
fetch() {
	local url=$1 out=$2 progress=${3:-0}
	if [[ $url == /* ]]; then cp -- "$url" "$out"; return; fi
	[[ $url == "$RPI_ARCHIVE"/* || $url == "$DEBIAN_ARCHIVE"/* || $url == "$DEBIAN_OLD_ARCHIVE"/* ]] \
		|| die "refusing to download from an unofficial source: $url"
	debug "GET $url"
	if command -v curl >/dev/null; then
		local -a a=(-f --proto '=https' --max-redirs 0 --retry 3 --retry-delay 2 --connect-timeout 20 -o "$out")
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

# Fetch the Raspberry Pi archive key and convert it to a gpgv keyring.
setup_keyring() {
	[[ -n $KEYRING ]] && return 0
	fetch "$RPI_KEY_URL" "$WORKDIR/rpi.asc" || die "cannot download the Raspberry Pi archive key from $RPI_KEY_URL"
	# Dearmor without gpg: decode the base64 body of the armored key.
	awk '/^-----BEGIN PGP PUBLIC KEY BLOCK-----/ { b = 1; next }
		/^-----END PGP PUBLIC KEY BLOCK-----/ { b = 0 }
		b { sub(/\r$/, "") } b && NF && !/^[A-Za-z-]+: / && !/^=/' "$WORKDIR/rpi.asc" \
		| base64 -d >"$WORKDIR/rpi.gpg" 2>/dev/null || die "could not decode the Raspberry Pi archive key"
	[[ -s $WORKDIR/rpi.gpg ]] || die "the Raspberry Pi archive key is empty"
	KEYRING=$WORKDIR/rpi.gpg
}

# Verify an InRelease file and write its signed content. Raspberry Pi indexes
# must be signed by the pinned key, Debian indexes by debian-archive-keyring.
# Usage: verify_inrelease ARCHIVE IN OUT
verify_inrelease() {
	local aid=$1 in=$2 out=$3 status fpr
	local -a keys=(--keyring "$KEYRING")
	if [[ $aid != rpi ]]; then
		# Archived releases are signed with keys Debian has since retired
		keys=(--keyring "$DEBIAN_KEYRING")
		[[ -r $DEBIAN_OLD_KEYRING ]] && keys+=(--keyring "$DEBIAN_OLD_KEYRING")
	fi
	rm -f -- "$out"
	status=$(gpgv --status-fd 1 "${keys[@]}" --output "$out" "$in" 2>/dev/null) || true
	if grep -qE '^\[GNUPG:\] (BADSIG|EXPSIG|EXPKEYSIG|REVKEYSIG|ERRSIG)' <<<"$status" \
		|| ! grep -q '^\[GNUPG:\] VALIDSIG' <<<"$status"; then
		die "signature verification failed for $in"
	fi
	if [[ $aid == rpi ]]; then
		fpr=$(awk '$2 == "VALIDSIG" { print $NF }' <<<"$status")
		grep -qxi "$RPI_KEY_FPR" <<<"$fpr" || die "$in is not signed by the Raspberry Pi archive key"
	fi
	[[ -s $out ]] || die "no signed content in $in"
}

# Succeed if a verified Release file is the one for this release and has not
# expired. Debian's archive server keeps releases that no longer change, so
# their dates are not checked. Usage: release_ok FILE SUITE BASE-URL
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

# Load and verify the package index of an archive, release and architecture.
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
	if [[ $comp == xz ]]; then xz -dc "$d/Packages-$arch.$comp"; else gzip -dc "$d/Packages-$arch.$comp"; fi >"$d/Packages-$arch"
	rm -f -- "$d/Packages-$arch.$comp"
	IDX_LOADED[$key]=1
}

# Print "version<TAB>arch<TAB>filename<TAB>sha256<TAB>size<TAB>depends" for every
# version of a package in one index, newest first.
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

# Set AV to the versions of a package available on the target: the install
# set, the installed version and APT candidate, or, when building packages/,
# the Debian index. "*" stands for a virtual package of unknown version.
declare -A AVAIL=()
_avail() {
	local n=$1
	if [[ -z ${AVAIL[$n]+set} ]]; then
		if [[ -n ${IN_SET[$n]:-} ]]; then
			AVAIL[$n]=${PKG_VER[$n]:-*}
		elif [[ -n $DEP_INDEX ]]; then
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
# constraint, can be satisfied on the target. A dependency Debian renamed
# (DEP_RENAMES) counts as satisfied by its successor.
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
				read -ra avs <<<"$AV"   # no glob expansion of "*"
				for v in "${avs[@]}"; do
					if [[ -z $op || $v == "*" ]] || _vcmp "$v" "$op" "$ver"; then ok=1; break 3; fi
				done
			done
		done
		(( ok )) || return 1
	done
}

# Find the newest compatible version of a package and record it in PKG_*.
# A version is compatible when all its dependencies, including versions, are
# available on this Debian release, so a package that needs a Raspberry Pi
# rebuild of a Debian package is skipped for an older version that does not.
#  * From the target release: any architecture (binaries match this system).
#  * From newer Raspberry Pi OS releases: architecture-independent packages
#    (icons, fonts, wallpapers), and the theme packages without compiled code
#    (DATA_PKGS) built for this architecture.
#  * Only if neither has it: older releases, then the armhf index, which lists
#    every Raspberry Pi package. These carry the same restriction, so they can
#    supply an architecture-independent package but never another arch's binary.
#  * On an architecture Raspberry Pi does not publish, its amd64 indexes, for
#    the architecture-independent packages and the theme packages, which are
#    repacked without the GTK 2 engines (see data_coinstall).
# Offline, the local repository is the only source and is used as built.
# Usage: resolve_pkg PACKAGE [ARCHIVE]
resolve_pkg() {
	local pkg=$1 aid=${2:-rpi} s x line best="" best_v="" skipped="" v a f sha z d arch=$H_ARCH data=0
	[[ -n $REPO && $O_MODE != download ]] && aid=local
	[[ " ${DATA_PKGS[*]} " == *" $pkg "* ]] && data=1
	local -a newer=() older=()
	if [[ $aid == rpi ]]; then
		arch=${H_RPI_ARCH:-amd64}
		for s in $(releases); do
			if (( $(suite_rank "$s") > $(suite_rank "$H_SUITE") )); then newer+=("$s/$arch")
			elif (( $(suite_rank "$s") < $(suite_rank "$H_SUITE") )); then older+=("$s/$arch"); fi
		done
		if [[ $arch != armhf ]]; then
			for s in $(releases); do
				if (( $(suite_rank "$s") <= $(suite_rank "$H_SUITE") )); then older+=("$s/armhf"); fi
			done
		fi
	fi
	for x in "$H_SUITE/$arch" "${newer[@]}" "${older[@]}"; do
		[[ -n $best && " ${older[*]} " == *" $x "* ]] && break   # older releases are only a fallback
		index_load "$aid" "${x%/*}" "${x#*/}" || continue
		while IFS= read -r line; do
			IFS=$'\t' read -r v a f sha z d <<<"$line"
			# shellcheck disable=SC2086  # a list of names
			[[ -z ${DEP_DROPS[$pkg]:-} ]] || d=$(drop_deps "$d" ${DEP_DROPS[$pkg]})
			# packages/ has Debian's panel and file manager beside Raspberry Pi's builds
			if [[ $aid == local && $v == *+rpt* && $pkg =~ ^(lxpanel|pcmanfm|libfm) ]] && (( ! USE_STACK )); then continue; fi
			# Raspberry Pi's builds of them, with their plugins and data, come
			# from this release only: they belong together
			if [[ $x != "$H_SUITE/$arch" && $pkg =~ ^(lxpanel|pcmanfm|libfm|lxplug-) && $pkg != *-pi ]]; then continue; fi
			if [[ $aid == rpi && -z $H_RPI_ARCH ]]; then
				# Another architecture's build: only what holds no compiled code
				[[ $a == all ]] || (( data )) || continue
				(( data )) && d=$(no_engines "$d")
			else
				[[ $x == "$H_SUITE/$arch" || $a == all ]] || { [[ $a == "$arch" ]] && (( data )); } || continue
			fi
			if [[ $aid != local ]] && ! _deps_satisfiable "$d"; then
				[[ -n $skipped ]] || skipped=$v
				continue
			fi
			# The release is read back first, so an empty trailing field (no
			# dependencies) cannot shift the others
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

# Print a Depends field without the Raspberry Pi GTK 2 engines, which hold
# compiled code. Usage: no_engines DEPENDS
no_engines() { drop_deps "$1" gtk2-engines-pixflat gtk2-engines-clearlookspix; }

# Print a Depends field without the given packages. Usage: drop_deps DEPENDS NAME...
drop_deps() {
	local re
	re=$(printf '%s|' "${@:2}" | sed 's/[.+]/\\&/g')
	tr ',' '\n' <<<"$1" | grep -vE "^[[:space:]]*(${re%|})([[:space:](]|\$)" \
		| sed 's/^[[:space:]]*//' | paste -sd, - | sed 's/,/, /g'
}

# Leave out the dependencies only a Raspberry Pi needs (DEP_DROPS). Prints the
# path of the package to install.
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
# refreshing packages/, an unchanged file there is reused.
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
# alternative and resolving virtual packages through Provides.
#   BASE=priority  also start from the Debian base system (priority required,
#                  important and standard)
#   RECOMMENDS=1   also follow Recommends, as APT does by default
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
	ROOTS="$*" INST=$inst RECOMMENDS=${RECOMMENDS:-} awk '
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
				else if ($i ~ /^(Pre-)?Depends: / || (ENVIRON["RECOMMENDS"] == "1" && $i ~ /^Recommends: /)) {
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

# Print the dependency names of .deb files (all alternatives).
_deb_depnames() {
	local f
	for f; do dpkg-deb -f "$f" Pre-Depends Depends 2>/dev/null | sed 's/^[A-Za-z-]*: //'; done \
		| depnames
}

# Print the packages providing the GTK 2 engines that the gtkrc files in the
# given .deb files use.
_engine_pkgs() {
	local f e
	for f; do
		dpkg-deb --fsys-tarfile "$f" 2>/dev/null | tar -xO --wildcards '*/gtk-2.0/gtkrc' 2>/dev/null \
			| sed -n 's/^[[:space:]]*engine[[:space:]]*"\([^"]*\)".*/\1/p' || true
	done | sort -u | while read -r e; do
		case $e in
			pixmap)        echo gtk2-engines-pixbuf ;;
			pixflat)       echo gtk2-engines-pixflat ;;
			clearlookspix) echo gtk2-engines-clearlookspix ;;
			murrine)       echo gtk2-engines-murrine ;;
			adwaita)       echo gnome-themes-extra ;;
			xfce)          echo gtk2-engines-xfce ;;
			oxygen-gtk)    echo gtk2-engines-oxygen ;;
			clearlooks|crux|glide|hcengine|industrial|mist|redmond95|thinice) echo gtk2-engines ;;
			*) warn "unknown GTK 2 engine '$e' in a theme; GTK 2 applications may look wrong" ;;
		esac
	done | sort -u
}
# Succeed for GTK 2 engines published only by Raspberry Pi OS.
_is_rpi_engine() { [[ $1 == gtk2-engines-pixflat || $1 == gtk2-engines-clearlookspix ]]; }

# Succeed if a dependency can be satisfied on the target: by the install set,
# by the APT sources, or, when building packages/, by the Debian index.
_dep_ok() {
	[[ -n ${IN_SET[$1]:-} ]] && return 0
	if [[ -n $DEP_INDEX ]]; then awk -v n="$1" '$1 == n { f = 1; exit } END { exit !f }' "$DEP_INDEX"; else apt_has "$1"; fi
}

# Rewrite dependency names that Debian has since renamed (see DEP_RENAMES).
# Only the Depends field changes. Prints the path of the package to install.
compat_fix() {
	local deb=$1 deps names n c repl changed=0 re field
	local -A value=()
	for field in Depends Pre-Depends; do
		deps=$(dpkg-deb -f "$deb" "$field")
		[[ -n $deps ]] || continue
		names=$(depnames <<<"$deps")
		for n in $names; do
			_dep_ok "$n" && continue
			repl=""
			for c in ${DEP_RENAMES[$n]:-}; do
				if _dep_ok "$c"; then repl=$c; break; fi
			done
			[[ -n $repl ]] || die "$(basename "$deb") depends on '$n', which is not available for $H_SUITE/$H_ARCH"
			re=${n//./\\.}
			re=${re//+/\\+}
			deps=$(sed -E "s/(^|[ ,|])${re}([ ,(|:]|\$)/\\1${repl}\\2/g" <<<"$deps")
			info "Compatibility: $(dpkg-deb -f "$deb" Package) $field $n -> $repl"
			changed=1
		done
		value[$field]=$deps
	done
	if (( ! changed )); then printf '%s\n' "$deb"; return 0; fi
	deb_unpack "$deb" "debcompat-$H_SUITE"
	control_set Depends "${value[Depends]:-}"
	control_set Pre-Depends "${value[Pre-Depends]:-}"
	deb_pack
}

# Unpack a .deb for repacking into R_DIR; R_OUT is the repacked file, named
# with a suffix, and R_STAMP the original time, so that the same input always
# gives an identical file. Usage: deb_unpack DEB SUFFIX
deb_unpack() {
	R_DIR="$WORKDIR/repack/$(basename "$1" .deb)"
	R_OUT="$WORKDIR/debs/$(basename "$1" .deb)+$2.deb"
	rm -rf -- "$R_DIR"; mkdir -p "$(dirname "$R_DIR")" "$WORKDIR/debs"
	dpkg-deb -R "$1" "$R_DIR"
	R_STAMP=$(stat -c %Y "$R_DIR/DEBIAN/control")
}

# Set a field of the unpacked control file, or drop it when the value is
# empty. Usage: control_set FIELD VALUE
control_set() {
	F=$1 V=$2 awk '
		index($0, ENVIRON["F"] ":") == 1 { if (ENVIRON["V"] != "") print ENVIRON["F"] ": " ENVIRON["V"]; folded = 1; next }
		folded && /^[ \t]/ { next }                      # continuation lines of the old field
		{ folded = 0; print }' "$R_DIR/DEBIAN/control" >"$R_DIR/DEBIAN/control.new"
	mv -- "$R_DIR/DEBIAN/control.new" "$R_DIR/DEBIAN/control"
}

# Build the repacked package with the original timestamps and print its path.
deb_pack() {
	( cd "$R_DIR" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z \
		| xargs -0r md5sum >DEBIAN/md5sums )
	chmod 0644 "$R_DIR/DEBIAN/md5sums"
	find "$R_DIR" -exec touch -d "@$R_STAMP" {} +
	build_deb "$R_DIR" "$R_OUT" "$R_STAMP"
	printf '%s\n' "$R_OUT"
}

# Build a package with every file owned by root. dpkg before 1.19 (Debian 9)
# has no option for that and uses fakeroot. Usage: build_deb DIR OUT [STAMP]
build_deb() {
	local -a cmd=(dpkg-deb --root-owner-group)
	grep -q -- --root-owner-group <<<"$(dpkg-deb --help 2>/dev/null)" || cmd=(fakeroot dpkg-deb)
	SOURCE_DATE_EPOCH=${3:-$(date +%s)} "${cmd[@]}" -Zxz -b "$1" "$2" >/dev/null
	chmod 0644 "$2"
}

# Raspberry Pi's file manager replaces Debian's: same program name, same data
# files, Breaks/Replaces on pcmanfm. Repack it to run beside Debian's as
# pcmanfm-pi: rename the program and its data directory (the path is rewritten
# in the program, in place), drop those fields, and leave out the files
# Debian's package already provides (identical toolbar icons; translations of
# the same message domain). Debian's file manager stays untouched.
# Prints the path of the package to install.
fm_coinstall() {
	local deb=$1 n
	local from=/usr/share/pcmanfm/    # the data directory compiled into it
	local to=/usr/share/pcmanpi/      # same length, so it replaces it in place
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
	# Its conffile and maintainer script belong to the files left out above
	rm -f -- "$dir/DEBIAN/conffiles" "$dir/DEBIAN/postinst"
	for n in Breaks Replaces Conflicts Provides; do control_set "$n" ""; done
	deb_pack
}

# Raspberry Pi's Control Centre sets up the Raspberry Pi Desktop session: its
# menu entry is hidden, and the session shows its own copy.
rpcc_session() {
	local deb=$1 f
	[[ $(dpkg-deb -f "$deb" Package) == rpcc ]] || { printf '%s\n' "$deb"; return 0; }
	deb_unpack "$deb" session
	f=$R_DIR/usr/share/applications/rpcc.desktop
	if [[ -f $f ]]; then sed -i '/^OnlyShowIn=/d; /^NoDisplay=/d' "$f"; echo 'NoDisplay=true' >>"$f"; fi
	deb_pack
}

# Succeed if Debian has a package of that name: in the Debian index when
# building packages/, else in your APT sources.
_debian_has() {
	if [[ -n $DEP_INDEX ]]; then awk -v n="$1" '$1 == n { f = 1; exit } END { exit !f }' "$DEP_INDEX"
	else [[ -n $(apt-cache madison "$1" 2>/dev/null) ]]; fi
}

# Raspberry Pi's packages must leave Debian's alone: none may replace, break,
# conflict with or stand in for a Debian package (Raspberry Pi's file manager
# is repacked first, see fm_coinstall), except its builds of Debian's panel and
# file manager that --pi-apps installs in their place (PI_STACK), and none may
# change a file of Debian's. A maintainer script that edits a file under /etc the package does
# not ship is left out where the package works without it: pi-greeter's only
# lists the users in Debian's lightdm.conf, which this script's own LightDM
# settings do. Any other such package is refused. Prints the path of the
# package to install; fails for a refused one.
scripts_coinstall() {
	local deb=$1 dir=$WORKDIR/scripts s f n bad=""
	# Raspberry Pi's builds of Debian's panel and file manager replace Debian's
	# on purpose (see PI_STACK); their relations are Debian's own
	stack_deb "$deb" || for s in Replaces Breaks Conflicts Provides; do
		for n in $(dpkg-deb -f "$deb" "$s" | depnames); do
			if _debian_has "$n"; then bad+="$s:$n "; fi
		done
	done
	rm -rf -- "$dir"; mkdir -p "$dir"
	dpkg-deb -e "$deb" "$dir"
	for s in preinst postinst prerm postrm config; do
		[[ -f $dir/$s ]] || continue
		while read -r f; do
			grep -qxF ".$f" <<<"$(dpkg-deb -c "$deb" | awk '{ print $NF }')" || bad+="$s:$f "
		done < <(grep -oE '/etc/[A-Za-z0-9._/+-]*[A-Za-z0-9_]' "$dir/$s" | sort -u)
	done
	if [[ -z $bad ]]; then printf '%s\n' "$deb"; return 0; fi
	if [[ $(dpkg-deb -f "$deb" Package) == pi-greeter && $bad == "postinst:/etc/lightdm/lightdm.conf " ]]; then
		deb_unpack "$deb" own
		rm -f -- "$R_DIR/DEBIAN/postinst"
		deb_pack
		return 0
	fi
	warn "$(dpkg-deb -f "$deb" Package) is left out: it would change Debian's packages or files (${bad% })"
	return 1
}

# On an architecture Raspberry Pi does not publish, a theme package built for
# another one serves as well: it holds the same files, none of them compiled.
# Repack it as architecture-independent, without the Raspberry Pi GTK 2
# engines it names, which are compiled; GTK 2 applications then keep their
# default look. Prints the path of the package to install.
data_coinstall() {
	local deb=$1 f
	[[ -z $H_RPI_ARCH && " ${DATA_PKGS[*]} " == *" $(dpkg-deb -f "$deb" Package) "* \
		&& $(dpkg-deb -f "$deb" Architecture) != all ]] || { printf '%s\n' "$deb"; return 0; }
	deb_unpack "$deb" all
	while IFS= read -r -d '' f; do
		[[ $(head -c4 -- "$f") != $'\x7fELF' ]] || die "$(basename "$deb") holds compiled code (${f#"$R_DIR"})"
	done < <(find "$R_DIR" -path "$R_DIR/DEBIAN" -prune -o -type f -print0)
	control_set Architecture all
	control_set Depends "$(no_engines "$(dpkg-deb -f "$deb" Depends)")"
	deb_pack
}

# Print the package names of a Depends-style field on stdin, one per line,
# without versions, alternatives markers or architecture qualifiers.
depnames() { tr ',|' '\n' | sed 's/(.*//; s/:.*//; s/[[:space:]]//g' | awk 'NF' | sort -u; }

# List the releases and architectures in the offline repository.
repo_contents() {
	local d out=""
	for d in "$REPO"/dists/*/main/binary-*; do
		[[ -d $d ]] || continue
		d=${d#"$REPO"/dists/}
		out+="${out:+, }${d%%/*}/${d##*binary-}"
	done
	printf '%s\n' "${out:-nothing}"
}

###############################################################################
# 5. Artwork: Xfwm4 themes, icon sets with the Debian logo
###############################################################################

# Print an Openbox theme colour as #rrggbb, or the default.
# Usage: _ob_color THEMERC KEY DEFAULT
_ob_color() {
	local v
	v=$(awk -v k="$2" '{ key = $0; sub(/:.*/, "", key) }
		tolower(key) == tolower(k) { v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t\r]+$/, "", v) }
		END { print v }' "$1")
	if [[ $v =~ ^#[0-9A-Fa-f]{6}$ ]]; then printf '%s\n' "${v,,}"
	elif [[ $v =~ ^#([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])$ ]]; then
		printf '#%s%s%s%s%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" \
			"${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[3]}" | tr 'A-F' 'a-f'
	else printf '%s\n' "$3"; fi
}

# Blend two colours. Usage: _mix #rrggbb #rrggbb PERCENT-OF-SECOND
_mix() {
	local a=${1#\#} b=${2#\#} p=$3 out="#" i
	for i in 0 2 4; do
		printf -v out '%s%02x' "$out" $(( (16#${a:i:2} * (100 - p) + 16#${b:i:2} * p) / 100 ))
	done
	printf '%s\n' "$out"
}

# Repeat a character. Usage: _rep CHAR COUNT
_rep() { local s; (( $2 > 0 )) || return 0; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }

# Write an XPM image. Usage: _xpm FILE CHAR=COLOUR... -- ROW...
_xpm() {
	local file=$1 p i; shift
	local -a pal=()
	while [[ $1 != -- ]]; do pal+=("$1"); shift; done; shift
	{
		printf '/* XPM */\nstatic char * xpm[] = {\n"%d %d %d 1",\n' "${#1}" "$#" "${#pal[@]}"
		for p in "${pal[@]}"; do printf '"%s c %s",\n' "${p%%=*}" "${p#*=}"; done
		for (( i = 1; i <= $#; i++ )); do
			if (( i < $# )); then printf '"%s",\n' "${!i}"; else printf '"%s"};\n' "${!i}"; fi
		done
	} >"$file"
}

# Write an XPM image of identical rows.
# Usage: _xpm_tile FILE HEIGHT ROW CHAR=COLOUR...
_xpm_tile() {
	local file=$1 h=$2 row=$3 i; shift 3
	local -a rows=()
	for (( i = 0; i < h; i++ )); do rows+=("$row"); done
	_xpm "$file" "$@" -- "${rows[@]}"
}

# Print an XBM bitmap as rows of '#' (set) and '.' (clear).
_xbm_rows() {
	local f=$1 w h x y b bpr row
	w=$(sed -n 's/^#define[[:space:]]\{1,\}[^[:space:]]*_width[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p' "$f")
	h=$(sed -n 's/^#define[[:space:]]\{1,\}[^[:space:]]*_height[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p' "$f")
	[[ -n $w && -n $h ]] || return 1
	local -a bytes
	mapfile -t bytes < <(sed '/^#define/d' "$f" | grep -oiE '0x[0-9a-f]{1,2}')
	bpr=$(( (w + 7) / 8 ))
	(( ${#bytes[@]} >= bpr * h )) || return 1
	for (( y = 0; y < h; y++ )); do
		row=""
		for (( x = 0; x < w; x++ )); do
			b=$(( bytes[y * bpr + x / 8] ))
			if (( (b >> (x % 8)) & 1 )); then row+="#"; else row+="."; fi
		done
		printf '%s\n' "$row"
	done
}

# Print a button glyph from an Openbox bitmap, or a built-in one.
# Usage: _glyph OPENBOX-DIR XBM-NAME|builtin:NAME
_glyph() {
	local dir=$1 name=$2
	if [[ $name != builtin:* && -f $dir/$name.xbm ]] && _xbm_rows "$dir/$name.xbm"; then return 0; fi
	case ${name#builtin:} in
		shade*_toggled*) printf '%s\n' "########" "########" "........" "..####.." "..####.." "...##..." "...##..." "........" ;;
		shade*)          printf '%s\n' "########" "########" "........" "........" "........" "........" "........" "........" ;;
		stick*_toggled*) printf '%s\n' "........" "..####.." ".######." ".######." ".######." ".######." "..####.." "........" ;;
		stick*)          printf '%s\n' "........" "..####.." ".##..##." ".#....#." ".#....#." ".##..##." "..####.." "........" ;;
		menu*)           printf '%s\n' "........" "........" "########" "########" ".######." "..####.." "...##..." "........" ;;
		*)               printf '%s\n' "........" ;;
	esac
}

# Write a button image with the glyph from stdin centred on it.
# Usage: _xpm_button FILE WIDTH HEIGHT BG FG
_xpm_button() {
	local file=$1 w=$2 h=$3 bg=$4 fg=$5 gw gh ox oy y line
	local -a g=() rows=()
	mapfile -t g
	gh=${#g[@]} gw=${#g[0]}
	ox=$(( (w - gw) / 2 )) oy=$(( (h - gh) / 2 ))
	for (( y = 0; y < h; y++ )); do
		if (( y >= oy && y < oy + gh )); then
			line="$(_rep . "$ox")${g[y - oy]}$(_rep . $(( w - gw - ox )))"
			rows+=("${line//#/+}")
		else
			rows+=("$(_rep . "$w")")
		fi
	done
	_xpm "$file" ".=$bg" "+=$fg" -- "${rows[@]}"
}

# Generate an Xfwm4 theme from the colours and bitmaps of an Openbox theme.
# Usage: gen_xfwm4 OPENBOX-DIR OUTPUT-DIR THEME-NAME
gen_xfwm4() {
	local src=$1 out=$2 name=$3 rc=$1/themerc
	[[ -f $rc ]] || return 1
	local a_bg a_fg a_btn i_bg i_fg i_btn a_bd i_bd a_cl i_cl
	a_bg=$(_ob_color "$rc" window.active.title.bg.color '#87919b')
	a_fg=$(_ob_color "$rc" window.active.label.text.color '#f0f0f0')
	a_btn=$(_ob_color "$rc" window.active.button.unpressed.image.color "$a_fg")
	i_bg=$(_ob_color "$rc" window.inactive.title.bg.color '#eeefee')
	i_fg=$(_ob_color "$rc" window.inactive.label.text.color '#70747d')
	i_btn=$(_ob_color "$rc" window.inactive.button.unpressed.image.color "$i_fg")
	a_bd=$(_ob_color "$rc" window.active.border.color '#d0d0d0')
	i_bd=$(_ob_color "$rc" window.inactive.border.color "$a_bd")
	a_cl=$(_ob_color "$rc" window.active.client.color "$i_bg")
	i_cl=$(_ob_color "$rc" window.inactive.client.color "$a_cl")

	local H=26 W=26 n st bg bd cl
	mkdir -p "$out"
	for st in active inactive; do
		if [[ $st == active ]]; then bg=$a_bg bd=$a_bd cl=$a_cl; else bg=$i_bg bd=$i_bd cl=$i_cl; fi
		for n in 1 2 3 4 5; do _xpm_tile "$out/title-$n-$st.xpm" "$H" "bb" "b=$bg"; done
		_xpm_tile "$out/top-left-$st.xpm"  "$H" "dbb" "d=$bd" "b=$bg"
		_xpm_tile "$out/top-right-$st.xpm" "$H" "bbd" "d=$bd" "b=$bg"
		_xpm_tile "$out/left-$st.xpm"      2 "dcc" "d=$bd" "c=$cl"
		_xpm_tile "$out/right-$st.xpm"     2 "ccd" "d=$bd" "c=$cl"
		_xpm "$out/bottom-$st.xpm"       "d=$bd" "c=$cl" -- "cc" "cc" "dd"
		_xpm "$out/bottom-left-$st.xpm"  "d=$bd" "c=$cl" -- "dcc" "dcc" "ddd"
		_xpm "$out/bottom-right-$st.xpm" "d=$bd" "c=$cl" -- "ccd" "ccd" "ddd"
	done

	# Xfwm4 button name -> Openbox bitmap
	local -A ob=([close]=close [hide]=iconify [maximize]=max [maximize-toggled]=max_toggled
		[menu]=menu [shade]=builtin:shade [shade-toggled]=builtin:shade_toggled
		[stick]=builtin:stick [stick-toggled]=builtin:stick_toggled)
	local b glyph hover
	for b in "${!ob[@]}"; do
		glyph=${ob[$b]} hover="${ob[$b]}_hover"
		[[ $glyph != builtin:* && ! -f $src/$hover.xbm ]] && hover=$glyph
		_glyph "$src" "$glyph" | _xpm_button "$out/$b-active.xpm"   "$W" "$H" "$a_bg" "$a_btn"
		_glyph "$src" "$glyph" | _xpm_button "$out/$b-inactive.xpm" "$W" "$H" "$i_bg" "$i_btn"
		_glyph "$src" "$hover" | _xpm_button "$out/$b-prelight.xpm" "$W" "$H" "$(_mix "$a_bg" "$a_btn" 18)" "$a_btn"
		_glyph "$src" "$hover" | _xpm_button "$out/$b-pressed.xpm"  "$W" "$H" "$(_mix "$a_bg" "$a_btn" 32)" "$a_btn"
	done

	cat >"$out/themerc" <<EOF
# Xfwm4 theme generated from the official Raspberry Pi OS "$name" Openbox theme
# by $APP_NAME $APP_VERSION. It is regenerated on every install; do not edit.
active_text_color=$a_fg
inactive_text_color=$i_fg
title_alignment=center
full_width_title=true
title_shadow_active=false
title_shadow_inactive=false
title_horizontal_offset=0
title_vertical_offset_active=0
title_vertical_offset_inactive=0
button_offset=0
button_spacing=0
maximized_offset=0
EOF
}

# Print the other Raspberry Pi OS icon sets an icon set borrows from: only the
# legacy PiX does, from PiXflat, the set closest to it in style. The others
# keep the fallback the official theme itself names (GNOME, Adwaita), so no set
# is mixed with icons from another era.
_icon_fallbacks() {
	case $1 in PiX) echo PiXflat ;; esac
}

# Link each missing cursor name to an equivalent official cursor. Repeated
# passes let aliases build on each other.
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

# Link the icon names Debian's applets request to the official images, at
# every size the base theme has. Names the base theme already has are kept,
# unless marked with "!".
# Usage: _icon_aliases BASE-DIR OUT-DIR BASE-NAME
_icon_aliases() {
	local bdir=$1 out=$2 base=$3 entry name target rel f n i force
	local -a pairs=("${ICON_ALIASES[@]}")
	local -A have=() imgs=()
	# nm-applet's connecting animation frames and VPN frames
	for n in 01 02 03; do for i in $(seq -w 1 11); do pairs+=("nm-stage$n-connecting$i:network-idle"); done; done
	for i in $(seq -w 1 14); do pairs+=("nm-vpn-connecting$i:nm-vpn-active-lock"); done
	# Generic file names: the official sets carry the old GNOME names
	# (gnome-mime-application-pdf), while today's programs ask for the current
	# ones (application-pdf), which are linked to those images.
	pairs+=("application-octet-stream:unknown"    "application-x-generic:unknown"
		"text-plain:text-x-generic"              "application-x-zerosize:empty"
		"inode-x-empty:empty"
		"application-x-sharedlib:application-x-executable"
		"application-x-firmware:unknown"         "application-certificate:unknown"
		# Office documents, which file managers ask for by their long names
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
		have[$f]=1
		imgs[$f]+="$rel "
	done < <(cd "$bdir" && find . -mindepth 3 \( -name '*.png' -o -name '*.svg' \) -printf '%P\n')
	for f in "${!imgs[@]}"; do
		[[ $f == gnome-mime-* ]] && pairs+=("${f#gnome-mime-}:$f")
	done
	for entry in "${pairs[@]}"; do
		name=${entry%%:*} target=${entry#*:} force=0
		if [[ $name == '!'* ]]; then name=${name#!} force=1; fi
		[[ -n ${imgs[$target]:-} ]] || continue
		if [[ -n ${have[$name]:-} ]] && (( ! force )); then continue; fi
		for rel in ${imgs[$target]}; do
			mkdir -p "$out/${rel%/*}"
			ln -sfn "../../../$base/$rel" "$out/${rel%/*}/$name.${rel##*.}"
		done
	done
}

# Show the Debian logo wherever the theme shows the Raspberry Pi logo
# (LOGO_ICONS), e.g. on the menu button.
# The images come from Debian's desktop-base, else from debconf.
# Usage: _logo_aliases OUT-DIR
_logo_aliases() {
	local out=$1 f dir size ext n found=0
	for f in /usr/share/icons/desktop-base/*/emblems/emblem-debian.png \
		/usr/share/icons/desktop-base/scalable/emblems/emblem-debian.svg; do
		[[ -f $f ]] || continue
		size=${f#/usr/share/icons/desktop-base/}; size=${size%%/*}
		dir=$out/$size/places ext=${f##*.}
		mkdir -p "$dir"
		for n in "${LOGO_ICONS[@]}"; do ln -sfn "$f" "$dir/$n.$ext"; done
		found=1
	done
	if (( ! found )) && [[ -f /usr/share/pixmaps/debian-logo.png ]]; then
		mkdir -p "$out/48x48/places"
		for n in "${LOGO_ICONS[@]}"; do ln -sfn /usr/share/pixmaps/debian-logo.png "$out/48x48/places/$n.png"; done
	fi
}

# Create the "<Base>-Debian" icon theme: the official set, plus the Debian
# logo and the cursor and icon names Debian's programs ask for.
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
	# An icon a set lacks comes from the other Raspberry Pi OS sets first, so
	# that it still looks like Raspberry Pi OS instead of GNOME's fallback
	local pi=""
	for d in $(_icon_fallbacks "$base"); do
		[[ -f $SYS_ROOT/usr/share/icons/$d/index.theme ]] && pi+="$d,"
	done
	inh=$(tr ',' '\n' <<<"$base,$pi$inh,Adwaita,hicolor" | awk 'NF && !seen[$0]++' | paste -sd, -)
	{
		printf '[Icon Theme]\nName=%s (Debian)\n' "$base"
		printf 'Comment=Raspberry Pi OS %s icons and cursors with Debian compatibility names\n' "$base"
		printf 'Inherits=%s\nExample=folder\nDirectories=%s\n' "$inh" "$(IFS=,; echo "${dirs[*]}")"
		for d in "${dirs[@]}"; do   # each directory's section: the official theme's, or a new one
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
# Raspberry Pi OS is an LXDE session profile: its login screen entry starts
# lxsession with its own profile, menu prefix and data directories. The
# session here is built the same way. Its configuration lives in the generated
# package under $SHARE/xdg and $SHARE/data, which the session alone puts first
# in XDG_CONFIG_DIRS and XDG_DATA_DIRS: Debian's own LXDE session, and every
# other one, stay as they are. Settings a user makes in the session are kept
# in that user's own files for the profile, and win over these defaults.
###############################################################################

# File editors, for the generated package and, through _track_file, for the
# user's own files (section 8).

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
					# the first line with this key carries the new value; later ones go
					if (kk == k) { if (!done) { print k "=" v; done = 1 }; next }
				}
				{ print }
				END { if (!done) { if (!ins) { if (NR) print ""; print s } print k "=" v } }' \
			| _write "$file"
		shift 2
	done
}

# Set a key in a "key=value" file without sections.
# Usage: _kv_set FILE KEY VALUE [QUOTE-CHAR]
_kv_set() {
	local file=$1 key=$2 val=$3 quote=${4:-}
	_track_file "$file"
	{ [[ -f $file ]] && cat -- "$file"; true; } \
		| K=$key V="$quote$val$quote" awk '
			BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"] }
			index($0, "=") {
				kk = substr($0, 1, index($0, "=") - 1); gsub(/^[ \t]+|[ \t]+$/, "", kk)
				if (kk == k) { if (!done) print k "=" v; done = 1; next }
			}
			{ print }
			END { if (!done) print k "=" v }' \
		| _write "$file"
}

# Replace or append a block between marker comments.
# Usage: _block_set FILE TAG CONTENT
_block_set() {
	local file=$1 tag=$2 content=$3 b e
	case $file in *.css) b="/* >>> $tag >>> */" e="/* <<< $tag <<< */" ;; *) b="# >>> $tag >>>" e="# <<< $tag <<<" ;; esac
	_track_file "$file"
	{ [[ -f $file ]] && cat -- "$file"; true; } \
		| B=$b E=$e C=$content awk '
			$0 == ENVIRON["B"] { skip = 1; next }
			$0 == ENVIRON["E"] { skip = 0; next }
			!skip { print }
			END { print ENVIRON["B"]; print ENVIRON["C"]; print ENVIRON["E"] }' \
		| _write "$file"
}

# Copy the first existing system default into place, if the file is missing.
# Usage: _seed FILE DEFAULT...
_seed() {
	local dst=$1 src
	shift
	[[ -e $dst ]] && return 0
	for src; do
		if [[ -f $src ]]; then
			_track_file "$dst"
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

# Print <font> elements for the given places, as Raspberry Pi OS sets them
# (theme font, size 12). Usage: _xml_fonts PLACE...
_xml_fonts() {
	local p
	for p; do
		printf '    <font place="%s">\n      <name>%s</name>\n      <size>12</size>\n      <weight>%s</weight>\n      <slant>Normal</slant>\n    </font>\n' \
			"$p" "$T_FONT_FAMILY" "$T_FONT_WEIGHT"
	done
}

# Apply the Raspberry Pi OS Openbox settings (lxde-pi-rc.xml / rpd-rc.xml):
# the <theme> section with round corners and invisible handles, and, unless
# THEME-ONLY is set, one desktop and the focus and placement settings.
# Usage: _openbox_rc FILE [THEME-ONLY]
_openbox_rc() {
	local file=$1 theme_only=${2:-0} fonts
	_track_file "$file"
	fonts=$(_xml_fonts ActiveWindow InactiveWindow MenuHeader MenuItem ActiveOnScreenDisplay InactiveOnScreenDisplay)
	_xml_block "$file" theme "$(printf '  <theme>\n    <name>%s</name>\n    <titleLayout>LIMC</titleLayout>\n    <keepBorder>yes</keepBorder>\n    <roundCorners>yes</roundCorners>\n    <invisibleHandles>yes</invisibleHandles>\n    <animateIconify>yes</animateIconify>\n%s\n  </theme>' "$T_GTK" "$fonts")"
	(( theme_only )) && return 0
	# Use Openbox's own menu when LXDE's is missing
	if [[ ! -f /usr/share/lxde/openbox/menu.xml ]]; then
		sed -i 's#<file>/usr/share/lxde/openbox/menu.xml</file>#<file>menu.xml</file>#' "$file"
	fi
	_xml_child "$file" desktops number 1
	_xml_child "$file" focus focusDesktop yes
	_xml_child "$file" placement monitor Any
}

# Bind the Openbox keys of Raspberry Pi OS (lxde-pi-rc.xml / rpd-rc.xml) whose
# program is installed: the panel's menu and dialogs, the terminal, the task
# manager and the Shutdown dialog. A key's existing binding is replaced.
# Usage: _openbox_keys RC-XML
_openbox_keys() {
	local file=$1 k c ctl=lxpanelctl
	local -a keys
	if (( S_PI_PANEL )); then
		ctl=lxpanelctl-pi
		keys=("Super_L|$ctl command smenu menu" "C-Escape|$ctl command smenu menu" "A-F2|gui-runcmd"
			"C-A-B|$ctl command bluetooth menu" "C-A-M|$ctl command magnifier toggle"
			"XF86AudioRaiseVolume|$ctl command volumepulse volu" "XF86AudioLowerVolume|$ctl command volumepulse vold"
			"XF86AudioMute|$ctl command volumepulse mute")
	elif (( S_PI_STACK )); then
		# Raspberry Pi OS 10 to 12's keys, for its build of Debian's panel
		keys=("Super_L|$ctl menu" "C-Escape|$ctl menu" "A-F2|$ctl run"
			"C-A-B|$ctl command bluetooth menu" "C-A-M|$ctl command magnifier toggle"
			"XF86AudioRaiseVolume|$ctl command volumepulse volu" "XF86AudioLowerVolume|$ctl command volumepulse vold"
			"XF86AudioMute|$ctl command volumepulse mute")
	else
		keys=("Super_L|$ctl menu" "C-Escape|$ctl menu" "A-F2|$ctl run")
	fi
	keys+=("C-A-S|$ctl move" "C-A-T|x-terminal-emulator" "C-S-Escape|lxtask" "Print|scrot"
		"C-A-End|pishutdown" "C-A-Delete|pishutdown")
	for k in "${keys[@]}"; do
		c=${k#*|} k=${k%%|*}
		command -v "${c%% *}" >/dev/null || [[ -x $SYS_ROOT/usr/bin/${c%% *} ]] || continue
		K=$k C=$c awk '
			BEGIN {
				k = "<keybind key=\"" ENVIRON["K"] "\""
				nb = "    <keybind key=\"" ENVIRON["K"] "\">\n      <action name=\"Execute\">\n        <command>" ENVIRON["C"] "</command>\n      </action>\n    </keybind>"
			}
			!done && index($0, k) { inb = 1; if ($0 ~ /<\/keybind>/) { inb = 0; print nb; done = 1 }; next }
			inb { if ($0 ~ /<\/keybind>/) { inb = 0; print nb; done = 1 }; next }
			!done && /<\/keyboard>/ { print nb; done = 1 }
			{ print }' "$file" | _write "$file"
	done
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
_browser() {
	if [[ -x /usr/bin/x-www-browser ]]; then echo x-www-browser.desktop
	else _launcher firefox-esr.desktop chromium.desktop lxde-x-www-browser.desktop; fi
}
# The same, as a path for the X panels, which look up ids in the menu only.
_browser_lx() {
	local id
	id=$(_browser) || return 1
	if [[ $id == x-www-browser.desktop ]]; then echo "$SHARE/data/applications/$id"; else echo "$id"; fi
}

# Print the parts of the Raspberry Pi OS panel (raspberrypi-ui-mods /
# rpd-x-core) that both panel programs share. Usage: _panel_global [KEY=VALUE]...
_panel_global() {
	printf '# lxpanel <profile> config file. Manually editing is not recommended.\n'
	printf '# Use preference dialog in lxpanel to adjust config when you can.\n\n'
	printf 'Global {\n'
	printf '  %s\n' edge=top align=left margin=0 widthtype=percent width=100 height=36 transparent=0 \
		tintcolor=#000000 alpha=0 autohide=0 heightwhenhidden=2 setdocktype=1 setpartialstrut=1 \
		usefontcolor=0 fontsize=12 fontcolor=#ffffff usefontsize=0 background=0 \
		backgroundfile=/usr/share/lxpanel/images/background.png iconsize=36 monitor=0 "$@"
	printf '}\n'
}
# Usage: _panel_plugin TYPE [CONFIG-LINE]...
_panel_plugin() {
	local t=$1; shift
	printf 'Plugin {\n  type=%s\n' "$t"
	[[ $t == taskbar ]] && printf '  expand=1\n'
	printf '  Config {\n'
	if (( $# )); then printf '    %s\n' "$@"; fi
	printf '  }\n}\n'
}
# The launchers for web browser, file manager and terminal, then the taskbar.
_panel_tasks() {
	local id fm=pcmanfm.desktop
	local -a buttons=()
	(( S_PI_FM )) && fm=pcmanfm-pi.desktop
	for id in "$(_browser_lx)" \
		"$fm" "$(_launcher x-terminal-emulator.desktop lxterminal.desktop lxde-x-terminal-emulator.desktop)"; do
		if [[ -n $id ]]; then buttons+=("Button {" "  id=$id" "}"); fi
	done
	_panel_plugin space Size=4
	_panel_plugin launchbar "${buttons[@]}"
	_panel_plugin space Size=8
	_panel_plugin taskbar tooltips=1 IconsOnly=0 ShowAllDesks=0 UseMouseWheel=1 UseUrgencyHint=1 FlatButton=0 \
		MaxTaskWidth=200 spacing=1 GroupedTasks=0
	_panel_plugin space Size=2
}

# The Raspberry Pi OS panel for Debian's lxpanel: menu with the Debian logo,
# launchers, taskbar, tray, volume, keyboard layout, clock and, with a
# battery, the battery, with Raspberry Pi OS's spaces. Pi-only plugins have no
# Debian counterpart; network and Bluetooth appear in the tray through
# Debian's applets.
_lxpanel_layout() {
	local plugins="$SYS_ROOT/usr/lib/*/lxpanel/plugins"
	_panel_global point_at_menu=0
	_panel_plugin menu padding=4 "image=${S_LOGO:-start-here}" "system {" "}" "separator {" "}" \
		"item {" "  image=system-run" "  command=run" "}" "separator {" "}" \
		"item {" "  image=system-shutdown" "  command=logout" "}"
	[[ $T_ERA == trixie ]] && _panel_plugin separator
	_panel_tasks
	_panel_plugin tray
	if compgen -G "$plugins/volume.so" >/dev/null; then _panel_plugin space Size=2; _panel_plugin volume; fi
	if compgen -G "$plugins/xkb.so" >/dev/null; then _panel_plugin space Size=2; _xkb_plugin; fi
	_panel_plugin space Size=2
	_panel_plugin dclock ClockFmt=%R 'TooltipFmt=%A %x' BoldFont=0 IconOnly=0 CenterText=1
	if compgen -G "$plugins/batt.so" >/dev/null && has_battery; then _panel_plugin space Size=2; _panel_plugin batt HideIfNoBattery=1; fi
}

# Raspberry Pi OS's panel for Raspberry Pi's own panel program, as its
# rpd-x-core of this release has it (see _pi_layout). Without that package,
# the Raspberry Pi OS 13 layout is written.
_pi_panel_layout() {
	local f
	f=$(pi_unpack "$PANEL_PKG" "$(config_suite)" "$(rpi_arch)" 2>/dev/null)/etc/xdg/lxpanel-pi/panels/panel
	if [[ -f $f ]]; then _pi_layout "$f" lxpanel-pi; else _pi_panel_builtin; fi
}
# The same before Raspberry Pi OS 13, for Raspberry Pi's build of Debian's
# panel (PI_STACK), as its raspberrypi-ui-mods of this release has it.
# Without that package, the panel of Debian's is written.
_pi_stack_layout() {
	local f
	if f=$(_pi_stack_file etc/xdg/lxpanel/LXDE-pi/panels/panel); then _pi_layout "$f" lxpanel/plugins; else _lxpanel_layout; fi
}
# Print a file of this release's raspberrypi-ui-mods, Raspberry Pi OS's
# settings before 13; fail if it is not there. Usage: _pi_stack_file PATH
_pi_stack_file() {
	local x
	x=$(pi_unpack raspberrypi-ui-mods "$H_SUITE" "$(rpi_arch)" 2>/dev/null) && [[ -f $x/$1 ]] && printf '%s\n' "$x/$1"
}

# Print a Raspberry Pi OS panel layout as it comes, with its spaces and
# separators, so a new layout of a later release is taken as it is. Left out
# are the plugins that do not work on Debian (PANEL_DROP), those not installed
# and, without a battery, the battery's; a space they leave doubled goes too.
# The tray takes the network plugin's place, as nm-applet shows the network
# icon there. The keyboard layout applet comes before the clock (Raspberry Pi
# OS has none). The launchers name the browser, file manager and terminal
# installed here. Usage: _pi_layout FILE PLUGIN-DIR (under /usr/lib/*/)
_pi_layout() {
	local f=$1 dir=$2 t keep="" fm=pcmanfm.desktop xkb="" nobatt=0
	(( S_PI_FM )) && fm=pcmanfm-pi.desktop
	while read -r t; do
		if compgen -G "$SYS_ROOT/usr/lib/*/$dir/$t.so" >/dev/null; then keep+="$t|"; fi
	done < <(sed -n 's/^[[:space:]]*type=//p' "$f" | sort -u)
	# Debian's applet, which the generated package links into Raspberry Pi's panel
	if compgen -G "$SYS_ROOT/usr/lib/*/$dir/xkb.so" >/dev/null || compgen -G "$SYS_ROOT/usr/lib/*/lxpanel/plugins/xkb.so" >/dev/null; then
		xkb=$(_xkb_plugin)
	fi
	has_battery || nobatt=1
	KEEP="${keep}space|separator|launchbar|taskbar|tray|menu|dclock" DROP=$PANEL_DROP NET=$PANEL_NET FM=$fm \
	XKB=$xkb SPACE=$(_panel_plugin space Size=2) NOBATT=$nobatt B=$(_browser_lx || true) \
	T=$(_launcher x-terminal-emulator.desktop lxterminal.desktop lxde-x-terminal-emulator.desktop || true) awk '
		function put(i) {
			if (typ[i] == "space" && last == "space") return
			out[++m] = blk[i]; last = typ[i]
		}
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
			keep = "^(" ENVIRON["KEEP"] ")$"; drop = "^(" ENVIRON["DROP"] ")$"; netre = "^(" ENVIRON["NET"] ")$"
			for (i = 1; i <= n; i++) { if (typ[i] == "tray") tray = i; if (typ[i] ~ netre && !net) net = i }
			n++; typ[n] = "xkb"; blk[n] = ENVIRON["XKB"]; xkb = n
			n++; typ[n] = "space"; blk[n] = ENVIRON["SPACE"]; sp = n
			printf "%s", head
			for (i = 1; i < xkb; i++) {
				if (i == net && tray) { put(tray); continue }
				if (i == tray && net) continue
				if (typ[i] != "" && (typ[i] ~ drop || typ[i] !~ keep)) continue
				if (ENVIRON["NOBATT"] == 1 && typ[i] ~ /^(batt|ptbatt)$/) continue
				if (typ[i] ~ /^(dclock|clock)$/ && blk[xkb] != "") { put(sp); put(xkb); put(sp) }
				put(i)
			}
			if (last == "space") m--   # no space at the end
			for (i = 1; i <= m; i++) printf "%s", out[i]
		}' "$f"
}

# The keyboard layout applet: the layouts of the system, each shown by its
# short name (FR, US, ...), in the smallest size the applet has.
_xkb_plugin() { _panel_plugin xkb DisplayType=1 FlagSize=1 PerWinLayout=0 NoResetOpt=0 KeepSysLayouts=1; }

# The Raspberry Pi OS 13 panel (rpd-x-core), for when its package cannot be
# read: the same plugins, in the same order.
_pi_panel_builtin() {
	local p
	_panel_global point_at_menu=0
	_panel_plugin smenu
	_panel_plugin separator
	_panel_tasks
	_panel_plugin ejecter
	for p in bluetooth tray volumepulse clock batt magnifier; do _panel_plugin space Size=2; _panel_plugin "$p"; done
}

# Print the panel button rules of Raspberry Pi OS: flat buttons with its
# spacing, so that 36 px icons fit the 36 px panel.
_panel_button_css() {
	printf '%s\n' \
		'#PanelToplevel button { padding: 2px 3px; margin: 0px; border: 0px; background-image: none; }' \
		'#PanelToplevel button image { -gtk-icon-shadow: none; -gtk-icon-effect: none; }' \
		'#launchbar button { padding: 0px; }'
}

# The categories of the Raspberry Pi OS menu, in its order: id, name, icon,
# freedesktop category, and Debian's directory file (lxmenu-data) of the
# same name, whose translations are kept.
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
# entries of the session's release, and the release to take it from.
menu_pkg() { if suite_ge "$H_SUITE" trixie; then echo "$ART_PKG $(config_suite)"; else echo "raspberrypi-ui-mods $H_SUITE"; fi; }

# The application menu of Raspberry Pi OS as its own package of this release
# has it: the menu file, its category names and the application entries it
# renames or files elsewhere (raspi-ui-overrides), those of applications
# installed here only. A later release's changes are so taken as they come.
# Raspberry Pi OS also hides Debian's settings tools (appearance, monitors,
# keys, session, Openbox, desktop), which its own Control Centre replaces;
# that is not on Debian, so they stay in the menu: an entry that only hides
# a program is not taken. Without that package, the built-in menu is written.
# Usage: _session_menu XDG-DIR DATA-DIR
_session_menu() {
	local xdg=$1 data=$2 prefix x f
	prefix=$(menu_prefix)
	# shellcheck disable=SC2046  # package and release
	x=$( (pi_unpack $(menu_pkg) "$(rpi_arch)") 2>/dev/null ) || x=""
	if [[ ! -f $x/etc/xdg/menus/${prefix}applications.menu ]]; then _menu_write "$xdg" "$data"; return 0; fi
	_write "$xdg/menus/${prefix}applications.menu" <"$x/etc/xdg/menus/${prefix}applications.menu"
	for f in "$x"/usr/share/desktop-directories/*.directory; do
		[[ -f $f ]] && _write "$data/desktop-directories/${f##*/}" <"$f"
	done
	for f in "$x"/usr/share/raspi-ui-overrides/applications/*.desktop; do
		[[ -f $f && -f /usr/share/applications/${f##*/} ]] && grep -q '^Exec=' "$f" || continue
		grep -vE '^(NoDisplay|Hidden)=true' "$f" | _write "$data/applications/${f##*/}"
	done
	[[ ! -f $x/usr/share/raspi-ui-overrides/applications/mimeapps.list ]] \
		|| _write "$xdg/mimeapps.list" <"$x/usr/share/raspi-ui-overrides/applications/mimeapps.list"
	# A category file the menu names that neither package nor Debian has
	# here (an older Debian may lack one): its name and icon from the table
	local d e id name icon
	while read -r d; do
		[[ -f $data/desktop-directories/$d || -f /usr/share/desktop-directories/$d ]] && continue
		id=${d%.directory} id=${id#*-} name=${id^} icon=applications-other
		for e in "${MENU_CATS[@]}"; do
			if [[ ${e%%|*} == "$id" ]]; then IFS='|' read -r _ name icon _ _ <<<"$e"; fi
		done
		printf '[Desktop Entry]\nType=Directory\nName=%s\nIcon=%s\n' "$name" "$icon" | _write "$data/desktop-directories/$d"
	done < <(sed -n 's/.*<Directory>\([^<]*\)<\/Directory>.*/\1/p' "$xdg/menus/${prefix}applications.menu" | sort -u)
}

# The built-in Raspberry Pi OS application menu: its category order, names and icons,
# with separators before Help and Preferences, and the entries outside the
# categories (Logout) at the end. Category names that match Debian's
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

# Print the Debian logo for the menu button, from packages every Debian desktop
# has: desktop-base (emblem-debian), else debconf (debian-logo).
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

# Print the wallpaper file to use, or nothing. The theme's default wallpaper
# comes in the requested resolution if installed, else in the other one.
_wallpaper_path() {
	local w=$O_WALLPAPER std uhd
	if [[ $w == auto ]]; then
		std=/usr/share/rpd-wallpaper/$T_WALL_DEFAULT uhd=${std%.jpg}_4k.jpg
		if (( O_4K )); then w=$uhd; [[ -f $w || ! -f $std ]] || w=$std
		else w=$std; [[ -f $w || ! -f $uhd ]] || w=$uhd; fi
	elif [[ $w != */* ]]; then
		[[ $w == *.* ]] || w+=".jpg"
		w=/usr/share/rpd-wallpaper/$w
	fi
	if [[ -f $w ]]; then printf '%s\n' "$w"; else warn "Wallpaper $w not found; the desktop shows its background colour."; fi
}

# The session's lxsession profile: Raspberry Pi OS's desktop.conf, with the
# chosen theme, and its autostart list. Usage: _session_profile XDG-DIR
_session_profile() {
	local dir=$1/lxsession/$S_PROFILE ctl=lxpanelctl images=1
	(( S_PI_PANEL )) && ctl=lxpanelctl-pi
	# Raspberry Pi's panels show icons in their menu whatever this says, and
	# Raspberry Pi OS has menu images off; Debian's panel shows them only with
	# it on
	(( S_PI_PANEL || S_PI_STACK )) && images=0
	{
		printf '[Session]\nwindow_manager=%s/openbox\ndisable_autostart=no\npolkit/command=lxpolkit\n' "$SHARE"
		printf 'clipboard/command=lxclipboard\nxsettings_manager/command=build-in\nproxy_manager/command=build-in\n'
		printf 'keyring/command=ssh-agent\nquit_manager/command=lxsession-logout\n'
		printf 'quit_manager/image=/usr/share/lxde/images/logout-banner.png\nquit_manager/layout=top\n'
		printf 'lock_manager/command=lxlock\nterminal_manager/command=x-terminal-emulator\nlauncher_manager/command=%s\n\n' "$ctl"
		printf '[GTK]\nsNet/ThemeName=%s\nsNet/IconThemeName=%s\nsGtk/FontName=%s\n' "$T_GTK" "$T_ICONS" "$T_FONT"
		printf 'iGtk/ToolbarStyle=3\niGtk/ButtonImages=0\niGtk/MenuImages=%s\niGtk/CursorThemeSize=%s\n' "$images" "$T_CURSOR_SIZE"
		printf 'iXft/Antialias=1\niGtk/AutoMnemonics=1\niGtk/EnableMnemonics=1\nsGtk/ColorScheme=%s\n' "$(color_scheme)"
		printf 'sGtk/CursorThemeName=%s\niGtk/ToolbarIconSize=3\nsGtk/IconSizes=gtk-large-toolbar=24,24\n' "$T_ICONS"
		printf 'sNet/SoundThemeName=%s\niNet/EnableEventSounds=1\niNet/EnableInputFeedbackSounds=1\n' "$T_SOUND_THEME"
		printf 'iXft/Hinting=1\nsXft/HintStyle=hintfull\nsXft/RGBA=rgb\n\n'
		printf '[Mouse]\nAccFactor=20\nAccThreshold=10\nLeftHanded=0\n\n[Keyboard]\nDelay=500\nInterval=30\nBeep=1\n\n'
		printf '[State]\nguess_default=true\n\n[Dbus]\nlxde=true\n\n[Environment]\nmenu_prefix=%s\n' "$(menu_prefix)"
	} | _write "$dir/desktop.conf"
	{
		printf '@%s/panel\n@%s/desktop\n' "$SHARE" "$SHARE"
		command -v xscreensaver >/dev/null && printf '@xscreensaver -no-splash\n'
	} | _write "$dir/autostart"
}

# The desktop and file manager settings of Raspberry Pi OS (pcmanfm.conf,
# desktop-items, libfm.conf), for Debian's file manager under the session's
# profile and for Raspberry Pi's, which reads the 'default' profile.
# Usage: _session_files XDG-DIR
_session_files() {
	local xdg=$1 d i f src
	for d in "$xdg/pcmanfm/$S_PROFILE" "$xdg/pcmanfm/default"; do
		for i in 0 1; do
			{
				printf '[*]\nwallpaper_mode=crop\nwallpaper_common=1\nwallpaper=%s\n' "$S_WALL"
				printf 'desktop_bg=%s\ndesktop_fg=%s\ndesktop_shadow=%s\ndesktop_font=%s\n' "$T_DESK_BG" "$T_DESK_FG" "$T_DESK_SHADOW" "$T_FONT"
				# trash and drive icons on the first monitor only
				printf 'show_wm_menu=0\nsort=mtime;ascending;\nshow_documents=0\nshow_trash=%s\nshow_mounts=%s\n' $(( !i )) $(( !i ))
			} | _write "$d/desktop-items-$i.conf"
		done
		f=$d/pcmanfm.conf
		if (( S_PI_STACK )) && [[ $d != */default ]] && src=$(_pi_stack_file etc/xdg/pcmanfm/LXDE-pi/pcmanfm.conf); then
			# Raspberry Pi OS's own settings for its build, without its
			# commands that Debian does not have (gksu, its appearance settings)
			grep -vE '^(su_cmd|prefs_app)=' "$src" | _write "$f"
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
			# Raspberry Pi's file manager keeps in this file what Debian's keeps
			# in libfm.conf: its own menus, side pane and icon sizes
			_fm_shared_conf "$f"
			_ini_set "$f" config terminal "x-terminal-emulator %s"
		fi
	done
	# Debian's libfm.conf, with Raspberry Pi OS's values
	_seed "$xdg/libfm/libfm.conf" "$SYS_ROOT"/etc/xdg/libfm/libfm.conf || true
	_fm_shared_conf "$xdg/libfm/libfm.conf"
}

# The settings both file managers read the same way: menus, thumbnails, icon
# sizes and the places in the side pane. Usage: _fm_shared_conf FILE
_fm_shared_conf() {
	_ini_set "$1" config cutdown_menus 1 real_expanders 1 single_click 0 use_trash 1 confirm_del 1 \
		thumbnail_local 1 thumbnail_max 2048
	_ini_set "$1" ui big_icon_size 48 small_icon_size 24 thumbnail_size 80 pane_icon_size 24 show_thumbnail 1
	_ini_set "$1" places places_home 1 places_desktop 0 places_root 1 places_computer 0 places_trash 0 \
		places_applications 0 places_network 0 places_unmounted 1 places_volmounts 1
}

# Application entries and autostart overrides of the session, as Raspberry Pi
# OS keeps them in raspi-ui-overrides: Debian Reference in the Help menu,
# Raspberry Pi's file manager as "File Manager" for folders and Desktop
# Preferences, the appearance settings reloading the panel, and the tray
# applets Raspberry Pi OS does not show. Usage: _session_entries XDG-DIR DATA-DIR
_session_entries() {
	local xdg=$1 apps=$2/applications f id
	f=/usr/share/applications/debian-reference-common.desktop
	if [[ -f $f && ! -f $apps/${f##*/} ]]; then
		awk '/^Categories=/ { print "Categories=Help;"; found = 1; next } { print }
			END { if (!found) print "Categories=Help;" }' "$f" | _write "$apps/${f##*/}"
	fi
	if (( S_PI_FM )); then
		# Raspberry Pi's entry for its file manager, which on Debian runs as
		# pcmanfm-pi; Debian's is hidden in the session
		f=$apps/pcmanfm.desktop
		[[ -f $f ]] || f=/usr/share/applications/pcmanfm-pi.desktop
		sed -E 's/^Name=.*/Name=File Manager/; s/^(Exec|TryExec)=pcmanfm( |$)/\1=pcmanfm-pi\2/' "$f" | _write "$apps/pcmanfm-pi.desktop"
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
	# Appearance: the Control Centre on Wayland, as in Raspberry Pi OS 13;
	# Customize Look and Feel on X (Openbox)
	f=/usr/share/applications/rpcc.desktop
	[[ ! -f $f ]] || { sed '/^NoDisplay=/d; /^OnlyShowIn=/d' "$f"; echo 'OnlyShowIn=labwc;'; } | _write "$apps/rpcc.desktop"
	f=$apps/lxappearance.desktop
	[[ -f $f ]] || f=/usr/share/applications/lxappearance.desktop
	if [[ -f $f ]]; then
		sed -E "s|^Exec=.*|Exec=$SHARE/appearance|; /^TryExec=/d; /^NoDisplay=/d; /^OnlyShowIn=/d" "$f" \
			| { cat; echo 'OnlyShowIn=LXDE;'; } | _write "$apps/lxappearance.desktop"
	fi
	# Clipboard managers and other volume applets, which Raspberry Pi OS does
	# not have; Bluetooth's, where Raspberry Pi's panel has its own plugin; and
	# a second authentication agent, which the session refuses (it runs
	# lxpolkit). A user can turn one on again in Desktop Session Settings.
	local -a pats=(volumeicon pasystray pnmixer diodon clipit parcellite
		polkit-gnome-authentication-agent polkit-mate xfce-polkit)
	(( S_PI_PANEL || S_PI_STACK )) && pats+=(blueman)
	for id in "${pats[@]}"; do
		for f in /etc/xdg/autostart/"$id"*.desktop; do
			[[ -f $f ]] || continue
			printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "${f##*/}" | _write "$xdg/autostart/${f##*/}"
		done
	done
}

# Icon sets: only the adapted sets are offered in the appearance settings. A
# copy of each official index.theme, hidden and inheriting the adapted set,
# keeps the official sets working, with the Debian logo even when chosen by
# name. Usage: _session_icons DATA-DIR
_session_icons() {
	local data=$1 b o inh f n rel size t logo out
	logo=/usr/share/icons/desktop-base/scalable/emblems/emblem-debian.svg
	[[ -f $logo ]] || logo=$(_logo_path) || logo=""
	for b in PiXflat PiXtrix PiX; do
		[[ -f $SYS_ROOT/usr/share/icons/$b/index.theme ]] || continue
		inh="$b-Debian,"
		for o in $(_icon_fallbacks "$b"); do [[ -d $SYS_ROOT/usr/share/icons/$o ]] && inh+="$o,"; done
		# Hidden and Inherits belong to the [Icon Theme] section, the first one
		f=$SYS_ROOT/usr/share/icons/$b/index.theme
		I=$inh H=$(grep -c '^Inherits[[:space:]]*=' "$f") awk '/^Hidden=/ { next }
			/^Inherits[[:space:]]*=/ { sub(/^Inherits[[:space:]]*=[[:space:]]*/, ""); print "Inherits=" ENVIRON["I"] $0; next }
			{ print }
			/^\[Icon Theme\]/ { print "Hidden=true"; if (!ENVIRON["H"]) print "Inherits=" ENVIRON["I"] "gnome,Adwaita,hicolor" }' "$f" \
			| _write "$data/icons/$b/index.theme"
		# The Shutdown dialog's window icon, as in the adapted set
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

# The themes as the session shows them: each official GTK 3 theme, plus the
# panel style of Raspberry Pi OS (and, for the legacy PiX, the panel colours
# the newer themes have), and the Openbox theme with the button names Openbox
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
			fi
			_panel_button_css
			# Raspberry Pi's tray does not clear an icon before redrawing it at a
			# new size; an opaque background in the panel colour hides the old
			# one. Tray icons are windows of their applets, not of the panel.
			printf '#tray, #tray * { padding: 0px; margin: 0px; border: 0px; }\n'
			printf 'window > image { background-color: @bar_bg_color; }\n'
			# Rounded tooltips need a compositor, which marks them "csd"; without
			# one (Openbox) their corners are black, so they are square, as
			# Raspberry Pi OS's X11 session makes them (startx-rpd, startlxde-pi)
			printf 'tooltip:not(.csd), .tooltip:not(.csd) { border-radius: 0px; }\n'
		} | _write "$data/themes/$t/gtk-3.0/gtk.css"
		# Openbox reads the hover image of a toggled title bar button as
		# "<button>_toggled_hover.xbm"; the official themes name it
		# "<button>_hover_toggled.xbm", so the middle button of a maximised
		# window would keep its small image on hover while the others grow.
		[[ -f $src/openbox-3/themerc ]] || continue
		mkdir -p "$data/themes/$t/openbox-3"
		for f in "$src"/openbox-3/*; do
			n=${f##*/}
			ln -sfn "/usr/share/themes/$t/openbox-3/$n" "$data/themes/$t/openbox-3/$n"
			[[ $n != *_hover_toggled* ]] || ln -sfn "/usr/share/themes/$t/openbox-3/$n" "$data/themes/$t/openbox-3/${n/_hover_toggled/_toggled_hover}"
		done
	done
}

# Print the session's GTK 2 colour scheme for the theme: its highlight and
# panel colours, as Raspberry Pi OS sets them, from the theme's own scheme
# (dark themes have a dark panel); Raspberry Pi OS's light values otherwise.
color_scheme() {
	local f=$SYS_ROOT/usr/share/themes/$T_GTK/gtk-2.0/gtkrc k v out=""
	for k in selected_bg_color selected_fg_color bar_bg_color bar_fg_color; do
		v=$(sed -n 's/^[[:space:]]*gtk-color-scheme[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$f" 2>/dev/null | first_line \
			| tr -s '\\' '\n' | sed -n "s/^n\{0,1\}$k:\(#[0-9A-Fa-f]\{6\}\)\$/\1/p" | first_line)
		[[ -n $v ]] || { printf '%s\n' "$T_COLOR_SCHEME"; return 0; }
		out+="$k:${v,,}\\n"
	done
	printf '%s\n' "$out"
}

# Print a literal colour that a theme's GTK 3 stylesheets define.
# Usage: _theme_color THEME NAME
_theme_color() {
	local f v
	for f in gtk-colours.css gtk-contained.css gtk.css; do
		f=$SYS_ROOT/usr/share/themes/$1/gtk-3.0/$f
		[[ -f $f ]] || continue
		v=$(sed -n "s/^[[:space:]]*@define-color[[:space:]]\{1,\}$2[[:space:]]\{1,\}\([^;]*\);.*/\1/p" "$f" | first_line)
		if [[ $v =~ ^(#[0-9A-Fa-f]{3,8}|rgba?\([0-9.,[:space:]%]+\)|[a-z]+)$ ]]; then printf '%s\n' "$v"; return 0; fi
	done
	return 1
}

# Print the GTK 4 colour layer of a theme. No official theme ships gtk-4.0,
# and libadwaita ignores themes, but both read named colours from the user's
# gtk-4.0/gtk.css. The theme's GTK 3 palette is mapped onto them, as
# @define-color names and, for GTK 4.16 and newer, as CSS variables.
# Usage: gtk4_colors THEME
gtk4_colors() {
	local -a map=(
		accent_color:theme_selected_bg_color accent_bg_color:theme_selected_bg_color
		accent_fg_color:theme_selected_fg_color
		window_bg_color:theme_bg_color       window_fg_color:theme_fg_color
		view_bg_color:theme_base_color       view_fg_color:theme_text_color
		headerbar_bg_color:theme_bg_color    headerbar_fg_color:theme_fg_color
		sidebar_bg_color:theme_bg_color      sidebar_fg_color:theme_fg_color
		card_bg_color:theme_base_color       card_fg_color:theme_text_color
		dialog_bg_color:theme_bg_color       dialog_fg_color:theme_fg_color
		popover_bg_color:theme_base_color    popover_fg_color:theme_text_color
		theme_bg_color:theme_bg_color        theme_fg_color:theme_fg_color
		theme_base_color:theme_base_color    theme_text_color:theme_text_color
		theme_selected_bg_color:theme_selected_bg_color
		theme_selected_fg_color:theme_selected_fg_color
	)
	local m c defs="" vars="" gtk4
	for m in "${map[@]}"; do
		c=$(_theme_color "$1" "${m#*:}") || continue
		defs+="@define-color ${m%%:*} $c;"$'\n'
		[[ ${m%%:*} == theme_* ]] || vars+="  --${m%%:*}: $c;"$'\n'
	done
	[[ -n $defs ]] || return 1
	printf '/* Raspberry Pi OS %s colours for GTK 4 and libadwaita applications,\n   generated from the official theme'"'"'s GTK 3 palette */\n%s' "$1" "$defs"
	gtk4=$(installed_version libgtk-4-1)
	if [[ -n $gtk4 ]] && dpkg --compare-versions "$gtk4" ge 4.16; then printf ':root {\n%s}\n' "${vars//_/-}"; fi
}

# The programs of the sessions: their start scripts, modelled on Raspberry
# Pi OS's startx-rpd and labwc-pi and Debian's startlxde; the panel and
# desktop, each Raspberry Pi's own where installed and wanted, else Debian's,
# so a session keeps working when one is removed; and the appearance
# settings, which reload the panel on an icon theme change, as the panel does
# not follow one by itself. Usage: _session_programs ROOT
_session_programs() {
	local root=$1 qt="" pcm="" f
	(( O_QT )) && qt="export QT_QPA_PLATFORMTHEME=gtk3"
	# Raspberry Pi's file manager is "pcmanfm" in the session, as on Raspberry
	# Pi OS, where Appearance Settings call it by that name
	if (( S_PI_FM )); then
		# shellcheck disable=SC2016  # written as is, for session-env
		pcm='export PATH="$share/bin:$PATH"'
		printf '#!/bin/sh\nif command -v pcmanfm-pi >/dev/null; then exec pcmanfm-pi "$@"; fi\nexec /usr/bin/pcmanfm "$@"\n' | _write "$root$SHARE/bin/pcmanfm"
		chmod 0755 "$root$SHARE/bin/pcmanfm"
	fi
	cat <<EOF | _write "$root$SHARE/session-env"
# The settings both Raspberry Pi Desktop sessions start with, written by
# $APP_NAME. They come first from $SHARE, in these sessions only.
profile=$S_PROFILE
# Raspberry Pi OS's names: Openbox's settings file, the file manager profile
obfile=$(ob_file)
fmprofile=$S_FM_PROFILE
share=$SHARE
config=\${XDG_CONFIG_HOME:-\$HOME/.config}
# The user's own colours (rpios-look-set --accent), in these sessions only
own=\${XDG_DATA_HOME:-\$HOME/.local/share}/$APP_NAME
export XDG_CONFIG_DIRS="\$share/xdg:\${XDG_CONFIG_DIRS:-/etc/xdg}"
export XDG_DATA_DIRS="\$own:\$share/data:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XDG_MENU_PREFIX=$(menu_prefix)
export FONTCONFIG_FILE=\$share/fonts.conf
[ ! -f "\$share/dconf/profile" ] || export DCONF_PROFILE=\$share/dconf/profile
export SAL_USE_VCLPLUGIN=gtk3
$qt
$pcm

# GTK 4 and libadwaita read colours only from the user's gtk-4.0/gtk.css:
# the theme's colours are added there while the session runs.
css=\$config/gtk-4.0/gtk.css
gtk4_off() {
	[ -f "\$css" ] || return 0
	sed -i --follow-symlinks -e '/^\/\* >>> $APP_NAME >>> \*\/\$/,/^\/\* <<< $APP_NAME <<< \*\/\$/d' \\
		-e '/^\/\* >>> $PREV_NAME >>> \*\/\$/,/^\/\* <<< $PREV_NAME <<< \*\/\$/d' "\$css"
	[ -s "\$css" ] || rm -f "\$css"
}
gtk4_on() {
	gtk4_off
	theme=\$(sed -n 's/^sNet\/ThemeName=//p' "\$config/lxsession/\$profile/desktop.conf" \\
		"\$share/xdg/lxsession/\$profile/desktop.conf" 2>/dev/null | head -n1)
	f=\$own/gtk4/\$theme.css
	[ -f "\$f" ] || f=\$share/gtk4/\$theme.css
	[ -f "\$f" ] || return 0
	mkdir -p "\${css%/*}"
	{ echo '/* >>> $APP_NAME >>> */'; cat "\$f"; echo '/* <<< $APP_NAME <<< */'; } >>"\$css"
}

# Ensure the existence of the Desktop folder
if [ -e "\$config/user-dirs.dirs" ]; then . "\$config/user-dirs.dirs"; fi
mkdir -p "\${XDG_DESKTOP_DIR:-\$HOME/Desktop}"
EOF
	cat <<'EOF' >>"$root$SHARE/session-env"

# Panels saved by earlier versions name a browser: use the generic
# "Web Browser" launcher instead, once.
web_browser() {
	web=$share/data/applications/x-www-browser.desktop
	[ -f "$web" ] && [ ! -e "$own/.web-browser" ] || return 0
	b='firefox-esr|firefox|chromium|chromium-browser|lxde-x-www-browser'
	for f in "$config/lxpanel-pi/panels/panel" "$config/lxpanel/$profile/panels/panel"; do
		[ -f "$f" ] && sed -i --follow-symlinks -E "s#^([[:space:]]*id=)($b)\.desktop\$#\1$web#" "$f"
	done
	for f in "$config/wf-panel-pi.ini" "$config/wf-panel-pi/wf-panel-pi.ini"; do
		[ -f "$f" ] && sed -i --follow-symlinks -E "/^launchers=/ s/(=| )($b)( |\$)/\1x-www-browser\3/" "$f"
	done
	mkdir -p "$own" && : >"$own/.web-browser"
}

# Desktop settings saved under the session's profile move to the file
# manager's, once.
fm_profile() {
	[ "$fmprofile" != "$profile" ] && [ ! -e "$own/.fm-profile" ] || return 0
	for f in "$config/pcmanfm/$profile"/desktop-items-*.conf; do
		[ -f "$f" ] || continue
		mkdir -p "$config/pcmanfm/$fmprofile"
		[ -e "$config/pcmanfm/$fmprofile/${f##*/}" ] || cp "$f" "$config/pcmanfm/$fmprofile/"
	done
	mkdir -p "$own" && : >"$own/.fm-profile"
}

# XSETTINGS for X applications on Wayland, in the file Appearance Settings
# writes.
xsettings_file() {
	xs=$config/xsettingsd/xsettingsd.conf
	[ ! -f "$xs" ] || return 0
	mkdir -p "${xs%/*}"
	if [ -f "$own/xsettingsd.conf" ]; then mv -f "$own/xsettingsd.conf" "$xs"
	else cp "$share/xsettingsd.conf" "$xs"; fi
}

# The user's look (rpios-look-set) for the Wayland session: labwc's theme and
# title font, XSETTINGS and GSettings, written as Appearance Settings does.
wayland_look() {
	lxs=$config/lxsession/$profile/desktop.conf
	[ -f "$lxs" ] || return 0
	v() { sed -n "s|^$1=||p" "$lxs" | head -n1; }
	theme=$(v sNet/ThemeName) icons=$(v sNet/IconThemeName) font=$(v sGtk/FontName)
	cursor=$(v sGtk/CursorThemeName) csize=$(v iGtk/CursorThemeSize) scheme=$(v sGtk/ColorScheme)
	case $theme in PiXnoir|PiXonyx) cs=prefer-dark ;; *) cs=default ;; esac
	# Window frames and title font, as in the X session
	ob=$config/openbox/$obfile
	[ -f "$ob" ] || ob=$share/openbox-rc.xml
	win=$(sed -n '/<theme>/,/<\/theme>/{/<font /,/<\/font>/b;s|.*<name>\([^<]*\)</name>.*|\1|p}' "$ob" | head -n1)
	tfont=$(sed -n '/<theme>/,/<\/theme>/{/<font /,/<\/font>/{s|.*<name>\([^<]*\)</name>.*|\1|p}}' "$ob" | head -n1)
	tsize=$(sed -n '/<theme>/,/<\/theme>/{/<font /,/<\/font>/{s|.*<size>\([^<]*\)</size>.*|\1|p}}' "$ob" | head -n1)
	tweight=$(sed -n '/<theme>/,/<\/theme>/{/<font /,/<\/font>/{s|.*<weight>\([^<]*\)</weight>.*|\1|p}}' "$ob" | head -n1)
	# labwc: the theme's name and fonts in the user's rc.xml, other settings kept
	lrc=$config/labwc/rc.xml
	if [ ! -f "$lrc" ]; then
		mkdir -p "${lrc%/*}"
		printf '<?xml version="1.0"?>\n<labwc_config>\n  <theme>\n  </theme>\n</labwc_config>\n' >"$lrc"
	fi
	grep -q '<theme>' "$lrc" || sed -i 's|</labwc_config>|  <theme>\n  </theme>\n</labwc_config>|' "$lrc"
	fonts=""
	for p in ActiveWindow InactiveWindow OnScreenDisplay MenuItem; do
		fonts="$fonts    <font place=\"$p\">\n      <name>${tfont:-Piboto}</name>\n      <size>${tsize:-12}</size>\n      <weight>${tweight:-Normal}</weight>\n    </font>\n"
	done
	N=${win:-$theme} F=$(printf "$fonts") awk '
		/<theme>/ { t = 1; print; print "    <name>" ENVIRON["N"] "</name>"; next }
		t && /<font[ >]/ { f = 1 }
		t && f { if (/<\/font>/) f = 0; next }
		t && /<name>/ { next }
		t && /<\/theme>/ { print ENVIRON["F"]; t = 0 }
		{ print }' "$lrc" >"$lrc.new" && mv -f "$lrc.new" "$lrc"
	# X applications (Xwayland); values escaped for sed
	xsettings_file
	e() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }
	sed -i -e "s|^Net/ThemeName .*|Net/ThemeName \"$(e "$theme")\"|" -e "s|^Net/IconThemeName .*|Net/IconThemeName \"$(e "$icons")\"|" \
		-e "s|^Gtk/CursorThemeName .*|Gtk/CursorThemeName \"$(e "$cursor")\"|" -e "s|^Gtk/CursorThemeSize .*|Gtk/CursorThemeSize ${csize:-24}|" \
		-e "s|^Gtk/FontName .*|Gtk/FontName \"$(e "$font")\"|" -e "s|^Gtk/ColorScheme .*|Gtk/ColorScheme \"$(e "$scheme")\"|" "$xs"
	# Wayland applications (GSettings, in the session's own database)
	if command -v dconf >/dev/null; then
		for kv in "gtk-theme='$theme'" "icon-theme='$icons'" "cursor-theme='$cursor'" "cursor-size=${csize:-24}" \
			"font-name='$font'" "document-font-name='$font'" "color-scheme='$cs'"; do
			dconf write "/org/gnome/desktop/interface/${kv%%=*}" "${kv#*=}" 2>/dev/null || true
		done
	fi
}
EOF
	cat <<'EOF' | _write "$root$SHARE/start"
#!/bin/sh
# The Raspberry Pi Desktop session on X.
. /usr/share/rpios-look/session-env
export XDG_CURRENT_DESKTOP=LXDE

# Openbox reads the user's own file only. It gets the session's defaults,
# also after the look changes, until the user changes it.
rc=$config/openbox/$obfile seen=$config/openbox/.$obfile.rpios-look
# Settings saved under earlier names
o=$config/openbox/$profile-rc.xml
if [ -f "$o" ] && [ ! -L "$o" ] && [ ! -e "$rc" ]; then
	mv -f "$o" "$rc" && ln -s "$obfile" "$o"
	for m in rpios-look raspios-look; do [ ! -e "$config/openbox/.${o##*/}.$m" ] || mv -f "$config/openbox/.${o##*/}.$m" "$seen"; done
fi
if [ ! -e "$rc" ] || cmp -s "$rc" "$seen" 2>/dev/null; then
	mkdir -p "$config/openbox" && cp "$share/openbox-rc.xml" "$rc" && cp "$share/openbox-rc.xml" "$seen"
fi

# Repair settings saved under the previous name, so the window manager starts.
lxs=$config/lxsession/$profile/desktop.conf
for f in "$lxs" "$config/lxsession/$profile/autostart"; do
	if [ -f "$f" ] && grep -q '/usr/share/raspios-look/' "$f"; then
		sed -i --follow-symlinks 's#/usr/share/raspios-look/#/usr/share/rpios-look/#g' "$f"
	fi
done
wm=$(sed -n 's/^window_manager=//p' "$lxs" 2>/dev/null | head -n1)
if [ -n "$wm" ] && ! command -v "${wm%% *}" >/dev/null 2>&1; then
	sed -i --follow-symlinks "s#^window_manager=.*#window_manager=$share/openbox#" "$lxs"
fi

# Window frames follow the theme unless chosen with rpios-look-set --window.
# Use Openbox's own menu when LXDE's is missing.
theme=$(sed -n 's/^sNet\/ThemeName=//p' "$lxs" "$share/xdg/lxsession/$profile/desktop.conf" 2>/dev/null | head -n1)
[ ! -f "$own/window" ] || theme=""
same=0; cmp -s "$rc" "$seen" 2>/dev/null && same=1
case $theme in
	PiX|PiXflat|PiXnoir|PiXtrix|PiXonyx)
		sed -i --follow-symlinks "/<theme>/,/<\/theme>/ s|<name>PiX[a-z]*</name>|<name>$theme</name>|" "$rc" ;;
esac
if [ ! -f /usr/share/lxde/openbox/menu.xml ]; then
	sed -i --follow-symlinks 's#<file>/usr/share/lxde/openbox/menu.xml</file>#<file>menu.xml</file>#' "$rc"
fi
[ "$same" = 0 ] || cp "$rc" "$seen"

# Clean up after GDM (GDM sets the number of desktops to one)
xprop -root -remove _NET_NUMBER_OF_DESKTOPS -remove _NET_DESKTOP_NAMES -remove _NET_CURRENT_DESKTOP 2>/dev/null

# Launch D-Bus if needed
if command -v dbus-launch >/dev/null && [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
	if [ -z "$XDG_RUNTIME_DIR" ] || [ ! -S "$XDG_RUNTIME_DIR/bus" ] || [ ! -O "$XDG_RUNTIME_DIR/bus" ]; then
		eval "$(dbus-launch --sh-syntax --exit-with-session)"
	fi
fi

# A Wayland login before leaves its variables to programs started by D-Bus
if command -v systemctl >/dev/null; then
	systemctl --user unset-environment WAYLAND_DISPLAY 2>/dev/null
	systemctl --user set-environment XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=LXDE 2>/dev/null
fi

web_browser
fm_profile
gtk4_on
/usr/bin/lxsession -s "$profile" -e LXDE
gtk4_off
EOF
	printf '#!/bin/sh\nexec openbox --config-file "${XDG_CONFIG_HOME:-$HOME/.config}/openbox/%s" "$@"\n' "$(ob_file)" \
		| _write "$root$SHARE/openbox"
	{
		printf '#!/bin/sh\n'
		(( S_PI_PANEL )) && printf 'if command -v lxpanel-pi >/dev/null; then exec lxpanel-pi; fi\n'
		printf 'exec lxpanel --profile %s\n' "$S_PROFILE"
	} | _write "$root$SHARE/panel"
	{
		printf '#!/bin/sh\n# The desktop: wallpaper and icons.\n'
		(( S_PI_FM )) && printf 'if command -v pcmanfm-pi >/dev/null; then exec pcmanfm-pi --desktop --profile %s; fi\n' "$S_FM_PROFILE"
		# Debian's file manager draws no desktop on Wayland
		printf 'if [ -n "$WAYLAND_DISPLAY" ]; then exec swaybg -m fill -c "%s" -i "%s"; fi\n' "#${T_DESK_BG:1:2}${T_DESK_BG:5:2}${T_DESK_BG:9:2}" "$S_WALL"
		printf 'exec pcmanfm --desktop --profile %s\n' "$S_PROFILE"
	} | _write "$root$SHARE/desktop"
	cat <<'EOF' | _write "$root$SHARE/appearance"
#!/bin/sh
# Run the appearance settings, reloading the panel on every icon theme change.
#
# The settings list the themes they find in the data directories. They are
# shown a sorted view of them: each Raspberry Pi OS icon set once, by its own
# name (the Debian-adapted set, which inherits the official one), cursor-only
# themes such as Adwaita by name, and none of Raspberry Pi's tPiX* helper
# themes. The names they save are the real ones.
icon_theme() { sed -n 's/^sNet\/IconThemeName=//p' "${XDG_CONFIG_HOME:-$HOME/.config}"/lxsession/*/desktop.conf 2>/dev/null; }
reload_panel() {
	# The panel builds its menu once: restart it after lxsession has passed
	# the new theme on, which takes it a moment
	sleep 2
	if pgrep -u "$(id -u)" -x lxpanel-pi >/dev/null; then lxpanelctl-pi restart
	elif pgrep -u "$(id -u)" -x lxpanel >/dev/null; then lxpanelctl restart; fi
}
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
		# a theme's parts, each from the first directory that has it (the
		# session's GTK 3 layer, the official GTK 2 theme, ...)
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
				# the official set, from beside its adapted one: still there
				# for the adapted set to inherit, not listed
				[ -f "$i" ] && [ -d "$d/icons/$n-Debian" ] || continue
				mkdir "$o" && ln -s "$t"/* "$o"/ && rm -f "$o/index.theme" "$o/cursors"
				awk '/^Hidden=/ { next } { print } /^\[Icon Theme\]/ { print "Hidden=true" }' "$i" >"$o/index.theme"
				continue ;;
			esac
			if [ -f "$i" ] && [ "${n%-Debian}" != "$n" ] && [ -d "$d/icons/${n%-Debian}" ]; then
				# the adapted set, listed by the official name
				mkdir "$o" && ln -s "$t"/* "$o"/ && rm -f "$o/index.theme"
				sed "s/^Name=\(.*\) (Debian)\$/Name=\1/" "$i" >"$o/index.theme"
			elif [ -f "$i" ] && [ -d "$t/cursors" ] && [ "$(key Hidden "$i")" = true ]; then
				# a hidden icon set with cursors (Adwaita), which the settings
				# would list without a name: listed by its name
				mkdir "$o" && ln -s "$t"/* "$o"/ && rm -f "$o/index.theme"
				grep -v '^Hidden=' "$i" >"$o/index.theme"
			else
				ln -s "$t" "$o"
			fi
		done
		IFS=:
	done
	IFS=' '
	# read-only, as the system's themes are: nothing to remove there
	chmod a-w "$v/icons" "$v/themes"
}
run=${XDG_RUNTIME_DIR:-}
if [ -n "$run" ] && [ -d "$run" ] && view "$run/rpios-look-appearance"; then
	XDG_DATA_DIRS=$run/rpios-look-appearance/share GTK_DATA_PREFIX=$run/rpios-look-appearance lxappearance "$@" &
else
	lxappearance "$@" &
fi
tool=$!
was=$(icon_theme)
while kill -0 "$tool" 2>/dev/null; do
	sleep 1
	now=$(icon_theme)
	if [ "$now" != "$was" ]; then was=$now; reload_panel; fi
done
wait "$tool"
EOF
	for f in start openbox panel desktop appearance; do chmod 0755 "$root$SHARE/$f"; done
	printf '[Desktop Entry]\nType=Application\nName=Raspberry Pi Desktop\nComment=The Raspberry Pi OS desktop on X, on Debian\nExec=%s/start\nTryExec=/usr/bin/lxsession\nDesktopNames=LXDE\n' \
		"$SHARE" | _write "$root/usr/share/xsessions/$SESSION_ID.desktop"
	# Monospace is Liberation Mono, as in Raspberry Pi OS, in the sessions only
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

# The sessions' GSettings defaults, which GTK reads on Wayland and GTK 4 for
# its light or dark style: a dconf database of their own (DCONF_PROFILE), so
# that the user's own settings still win and other sessions never read it.
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
	# A user database of its own, so other desktops' settings stay apart
	# (named without "-", which D-Bus does not allow)
	printf 'user-db:%s\nfile-db:%s/dconf/settings\n' "${APP_NAME//-/}" "$SHARE" | _write "$root$SHARE/dconf/profile"
}

# The Raspberry Pi Desktop session on Wayland, as Raspberry Pi OS 13 has it
# (rpd-wayland-core): the labwc compositor with Raspberry Pi OS's window
# settings and keys, Raspberry Pi's wf-panel-pi in its layout, the desktop,
# display settings (kanshi) and XSETTINGS for X applications (xsettingsd).
# The keyboard layout is the system's; keys and panel plugins that need
# Raspberry Pi tools are left out. Usage: _session_wayland ROOT
_session_wayland() {
	local root=$1 xdg=$1$SHARE/xdg x rc browser term fm=pcmanfm
	x=$( (pi_unpack "$WAYLAND_PKG" "$(config_suite)" "$(rpi_arch)") 2>/dev/null ) || x=""
	(( S_PI_FM )) && fm=pcmanfm-pi
	browser=$(_browser || true)
	term=$(_launcher x-terminal-emulator.desktop lxterminal.desktop || true)
	rc=$xdg/labwc/rc.xml
	if [[ -f $x/etc/xdg/labwc/rc.xml ]]; then _write "$rc" <"$x/etc/xdg/labwc/rc.xml"
	else printf '<?xml version="1.0"?>\n<labwc_config>\n</labwc_config>\n' | _write "$rc"; fi
	_labwc_rc "$rc"
	# Key bindings whose program is not installed go
	awk '
		/<keybind[ >]/ { blk = $0; inb = 1; if ($0 ~ /<\/keybind>/) { inb = 0; flush() }; next }
		inb { blk = blk "\n" $0; if ($0 ~ /<\/keybind>/) { inb = 0; flush() }; next }
		{ print }
		function flush(  c) {
			if (match(blk, /command="[^" ]+/)) {
				c = substr(blk, RSTART + 9, RLENGTH - 9)
				if (system("command -v \"" c "\" >/dev/null 2>&1") != 0) return
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
		printf 'lxsession-xdg-autostart\n'
	} | _write "$xdg/labwc/autostart"
	{
		printf '<openbox_menu>\n  <menu id="root-menu">\n'
		printf '    <item label="Desktop Preferences...">\n      <action name="Execute" command="%s --desktop-pref" />\n    </item>\n' "$fm"
		printf '  </menu>\n</openbox_menu>\n'
	} | _write "$xdg/labwc/menu.xml"
	# The panel: Raspberry Pi OS's layout, without the plugins that need its
	# tools (and the spacing before them), and with the launchers installed
	# here. wf-panel-pi reads this one path only; no other program does.
	if [[ -f $x/etc/xdg/wf-panel-pi/wf-panel-pi.ini ]]; then
		DROP=$WF_DROP B=${browser%.desktop} T=${term%.desktop} FM=$fm awk '
			/^widgets_(left|right)=/ {
				n = split(substr($0, index($0, "=") + 1), w, " "); m = 0; out = ""
				for (i = 1; i <= n; i++) {
					if (w[i] ~ "^(" ENVIRON["DROP"] ")$") { if (m && o[m] ~ /^spacing/) m--; continue }
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
	fi
	{
		printf 'Net/ThemeName "%s"\nNet/IconThemeName "%s"\nGtk/CursorThemeName "%s"\nGtk/CursorThemeSize %s\n' \
			"$T_GTK" "$T_ICONS" "$T_ICONS" "$T_CURSOR_SIZE"
		printf 'Gtk/FontName "%s"\nGtk/ColorScheme "%s"\nNet/SoundThemeName "%s"\n' "$T_FONT" "$(color_scheme)" "$T_SOUND_THEME"
		printf 'Net/EnableEventSounds 1\nNet/EnableInputFeedbackSounds 1\nGtk/ToolbarStyle 3\nGtk/ButtonImages 0\nGtk/MenuImages 0\n'
		printf 'Gtk/AutoMnemonics 1\nGtk/EnableMnemonics 1\nGtk/ToolbarIconSize 3\nGtk/IconSizes "gtk-large-toolbar=24,24"\n'
		printf 'Xft/Antialias 1\nXft/Hinting 1\nXft/HintStyle "hintfull"\nXft/RGBA "rgb"\n'
	} | _write "$root$SHARE/xsettingsd.conf"
	cat <<'EOF' | _write "$root$SHARE/start-wayland"
#!/bin/sh
# The Raspberry Pi Desktop session on Wayland.
. /usr/share/rpios-look/session-env

# The keyboard layout of the system, which Debian keeps in /etc/default/keyboard
if [ -r /etc/default/keyboard ]; then
	. /etc/default/keyboard
	export XKB_DEFAULT_MODEL="$XKBMODEL" XKB_DEFAULT_LAYOUT="$XKBLAYOUT" \
		XKB_DEFAULT_VARIANT="$XKBVARIANT" XKB_DEFAULT_OPTIONS="$XKBOPTIONS"
fi
# Graphics without 3D acceleration (virtual machines, old hardware) are
# drawn in software
export WLR_RENDERER_ALLOW_SOFTWARE=1
if [ -z "$(ls /dev/dri/renderD* 2>/dev/null)" ]; then export WLR_RENDERER=pixman; fi
# NVIDIA's driver draws hardware cursors wrongly with wlroots
if [ -d /sys/module/nvidia_drm ]; then export WLR_NO_HARDWARE_CURSORS=1; fi
# Display settings start empty, as in Raspberry Pi OS
if command -v kanshi >/dev/null && [ ! -e "$config/kanshi/config" ]; then
	mkdir -p "$config/kanshi" && : >"$config/kanshi/config"
fi

web_browser
fm_profile
xsettings_file
gtk4_on
/usr/bin/labwc -m
gtk4_off
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

# rpios-look-set: a user's own theme, icons, cursor, highlight colour, font
# and desktop in the Raspberry Pi Desktop session on X, from the command line.
# It writes the files the appearance and desktop settings write, which only
# this session reads, and applies them in the running session.
# Usage: _session_command ROOT
_session_command() {
	local root=$1
	{
		printf '#!/bin/bash\n# The look of the Raspberry Pi Desktop session for you, written by %s %s.\n' "$APP_NAME" "$APP_VERSION"
		printf 'APP=%s PROFILE=%s SHARE=%s OBFILE=%s FMPROFILE=%s\n' "$APP_NAME" "$S_PROFILE" "$SHARE" "$(ob_file)" "$S_FM_PROFILE"
		cat <<'EOF'
set -u
config=${XDG_CONFIG_HOME:-$HOME/.config}
own=${XDG_DATA_HOME:-$HOME/.local/share}/$APP
lxs=$config/lxsession/$PROFILE/desktop.conf lxs_sys=$SHARE/xdg/lxsession/$PROFILE/desktop.conf
fm=$config/pcmanfm/$FMPROFILE fm_sys=$SHARE/xdg/pcmanfm/$FMPROFILE
obrc=$config/openbox/$OBFILE
PI_THEMES="PiXflat PiXnoir PiXtrix PiXonyx PiX"

usage() {
	cat <<'USAGE'
Usage: rpios-look-set [OPTION]...
The look of the Raspberry Pi Desktop session, for you only. It changes the
running session at once and is kept for your next logins; other sessions
and other users are not changed.

  --theme NAME         pixflat, pixnoir, pixtrix, pixonyx or pix, with its own
                       icons, cursor, window frames and font; or any
                       installed GTK theme
  --light, --dark      the light or dark version of the current theme
                       (PiXflat and PiXnoir, PiXtrix and PiXonyx)
  --icons NAME         pixflat, pixtrix, pix or any installed icon theme
                       (also --icon)
  --window NAME        the window frames: pixflat, pixnoir, pixtrix, pixonyx,
                       pix or any installed Openbox theme; "theme" makes them
                       follow the theme again
  --cursor NAME        pixflat, pixtrix, pix or any installed cursor theme
  --cursor-size N      cursor size in pixels (e.g. 24, 32, 48)
  --font NAME          the font of applications, the desktop and the window
                       titles: nunito (Nunito Sans, Raspberry Pi OS Trixie),
                       piboto (Raspberry Pi OS Bookworm), piboto-condensed,
                       sans, serif, mono (Debian's DejaVu fonts), or any
                       installed font family; its style and size are set
                       to suit the theme
  --list               the themes, icons, window frames and fonts installed
  --accent COLOUR      highlight colour, e.g. '#d6363c', or default
  --accent-text COLOUR text on the highlight colour (default: black or white,
                       whichever reads better)
  --desktop-color COLOUR
                       the desktop's background colour
  --desktop-text COLOUR
                       the colour of the desktop icons' names
  --wallpaper W        a picture of /usr/share/rpd-wallpaper (e.g. aurora),
                       a path, or none
  --wallpaper-mode M   crop, fit, stretch, center, tile or color
  --show               print the current look
  --reset              back to the session's look, as installed
  -h, --help           this text

Examples: rpios-look-set --theme pixonyx --accent '#2e7d32' --cursor-size 32
          rpios-look-set --theme pixtrix --icons pixflat --window pixnoir
          rpios-look-set --font piboto
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
# A value from the user's file, else the session's
get() { local v; v=$(ini_get "$1" "$3" "$4"); [ -n "$v" ] || v=$(ini_get "$2" "$3" "$4"); printf '%s' "$v"; }
# The user's copy of a file of the session, made on first change
seed() { [ -f "$1" ] || { mkdir -p "${1%/*}" && cp "$2" "$1"; } || die "cannot write $1"; }

colour() { # print a colour as #rrggbb, or fail
	local c=${1,,}
	[[ $c =~ ^#([0-9a-f]{3}|[0-9a-f]{6})$ ]] || return 1
	if (( ${#c} == 4 )); then c="#${c:1:1}${c:1:1}${c:2:1}${c:2:1}${c:3:1}${c:3:1}"; fi
	printf '%s\n' "$c"
}
readable() { # black or white text on a colour
	local c=$1 r g b
	r=$((16#${c:1:2})) g=$((16#${c:3:2})) b=$((16#${c:5:2}))
	if (( r * 299 + g * 587 + b * 114 > 150000 )); then echo '#000000'; else echo '#f0f0f0'; fi
}
theme_dirs() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/$1" "$HOME/.$1" /usr/local/share/"$1" /usr/share/"$1"; }
icon_theme() { # print the theme name for NAME, or fail. Usage: icon_theme NAME [cursors]
	local n=$1 d
	case ${n,,} in pixflat) n=PiXflat ;; pixtrix) n=PiXtrix ;; pix) n=PiX ;; esac
	if [[ $n == PiX* && -d /usr/share/icons/$n-Debian ]]; then n=$n-Debian; fi
	for d in $(theme_dirs icons); do
		if [[ -f $d/$n/index.theme || ( -n ${2:-} && -d $d/$n/cursors ) ]]; then
			[[ -z ${2:-} || -d $d/$n/cursors ]] || continue
			printf '%s\n' "$n"; return 0
		fi
	done
	return 1
}
gtk_theme() {
	local d
	for d in $(theme_dirs themes); do [[ -f $d/$1/gtk-3.0/gtk.css ]] && return 0; done
	return 1
}
pi_name() { # PiX theme names by their short name
	case ${1,,} in pixflat) echo PiXflat ;; pixnoir) echo PiXnoir ;; pixtrix) echo PiXtrix ;;
		pixonyx) echo PiXonyx ;; pix) echo PiX ;; *) echo "$1" ;; esac
}
ob_theme() { # succeed if an Openbox theme is installed
	local d
	for d in $(theme_dirs themes); do [[ -f $d/$1/openbox-3/themerc ]] && return 0; done
	return 1
}

# Fonts: short names and default styles.
font_family() { # print the installed family for NAME, or fail
	local f
	case ${1,,} in
		nunito|nunito-sans|"nunito sans") f="Nunito Sans" ;;
		piboto|pibotolt|piboto-light) f="Piboto" ;;
		piboto-condensed|"piboto condensed") f="Piboto Condensed" ;;
		sans|sans-serif) f="DejaVu Sans" ;;
		serif) f="DejaVu Serif" ;;
		mono|monospace) f="DejaVu Sans Mono" ;;
		*) f=$(fc-list : family | tr ',' '\n' | awk -v n="${1,,}" 'tolower($0) == n { print; exit }') ;;
	esac
	[[ -n $f ]] && fc-list "$f" family | grep -q . || return 1
	printf '%s\n' "$f"
}
font_default_style() { case $1 in "Nunito Sans"|Piboto) echo light ;; *) echo regular ;; esac; }
font_styles() { # the styles a family has, as this command names them
	fc-list --format '%{style}\n' "$1" | tr ',' '\n' | tr 'A-Z' 'a-z' | sed 's/^12pt //; s/ *$//' | grep . | sort -u
}
# Convert a style to Pango words.
pango_style() {
	local w out="" s=${1,,}
	for w in $s; do
		case $w in
			regular|normal|book) ;;
			thin) out+=" Thin" ;; extralight|ultralight) out+=" Ultra-Light" ;; light) out+=" Light" ;;
			medium) out+=" Medium" ;; semibold|demibold) out+=" Semi-Bold" ;; bold) out+=" Bold" ;;
			extrabold|ultrabold) out+=" Ultra-Bold" ;; black|heavy) out+=" Heavy" ;; italic) out+=" Italic" ;;
			*) return 1 ;;
		esac
	done
	printf '%s\n' "${out# }"
}
# Openbox title font weight.
ob_weight() { case ${1,,} in *bold*|*black*|*heavy*) echo Bold ;; *light*|*thin*) echo Light ;; *) echo Normal ;; esac; }
# Set the window title font.
set_openbox_font() {
	local fam=$1 wt=$2 size=$4 slant=Normal
	[[ ${3,,} == *italic* ]] && slant=Italic
	seed "$obrc" "$SHARE/openbox-rc.xml"
	sed -i -e "/<theme>/,/<\/theme>/ { /<font /,/<\/font>/ {
		s|<name>[^<]*</name>|<name>$fam</name>|; s|<weight>[^<]*</weight>|<weight>$wt</weight>|
		s|<slant>[^<]*</slant>|<slant>$slant</slant>|; s|<size>[^<]*</size>|<size>${size%.*}</size>| } }" "$obrc"
}

list() {
	local t d f
	printf 'Themes (--theme):   '
	for t in $PI_THEMES; do gtk_theme "$t" && printf '%s ' "${t,,}"; done
	printf '(or any GTK theme installed)\nIcons (--icons):    '
	for t in pixflat pixtrix pix; do icon_theme "$t" >/dev/null && printf '%s ' "$t"; done
	printf '\nWindows (--window): '
	for t in $PI_THEMES; do ob_theme "$t" && printf '%s ' "${t,,}"; done
	printf '\nFonts (--font):     '
	for t in nunito piboto piboto-condensed sans serif mono; do font_family "$t" >/dev/null && printf '%s ' "$t"; done
	printf '(or any family: fc-list : family)\n'
	for t in nunito piboto; do
		f=$(font_family "$t") || continue
		printf '  %-18s %s\n' "$t styles:" "$(font_styles "$f" | paste -sd, - | sed 's/,/, /g')"
	done
}

# The running session, if this user has one: its display, for the commands
# that reach it
session_pid() { pgrep -u "$(id -u)" -f "^/usr/bin/lxsession -s $PROFILE( |\$)" | head -n1; }
attach() {
	local p=$1 line
	[[ -n ${DISPLAY:-} ]] && return 0
	while IFS= read -r -d '' line; do
		case $line in DISPLAY=*|XAUTHORITY=*|DBUS_SESSION_BUS_ADDRESS=*) export "${line?}" ;; esac
	done </proc/"$p"/environ
}
running() { pgrep -u "$(id -u)" -x "$1" >/dev/null; }
# A colour as #rrggbb (GTK 2 writes #rrrrggggbbbb)
short() { local c=$1; (( ${#c} != 13 )) || c="#${c:1:2}${c:5:2}${c:9:2}"; printf '%s\n' "$c"; }
# A theme's own GTK 2 colour scheme: highlight and panel colours
theme_scheme() {
	local f k v out=""
	for f in $(theme_dirs themes); do [[ -f $f/$1/gtk-2.0/gtkrc ]] && break; done
	f=$f/$1/gtk-2.0/gtkrc
	for k in selected_bg_color selected_fg_color bar_bg_color bar_fg_color; do
		v=$(sed -n 's/^[[:space:]]*gtk-color-scheme[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$f" 2>/dev/null | head -n1 \
			| tr -s '\\' '\n' | sed -n "s/^n\{0,1\}$k:\(#[0-9A-Fa-f]\{6\}\)\$/\1/p" | head -n1)
		[[ -n $v ]] || return 1
		out+="$k:${v,,}\\n"
	done
	printf '%s\n' "$out"
}
# The highlight colour now
accent_now() { colour "$(short "$(get "$lxs" "$lxs_sys" GTK sGtk/ColorScheme | sed -n 's/.*selected_bg_color:\(#[0-9A-Fa-f]*\).*/\1/p')")"; }

show() {
	local w
	printf 'Theme          %s\n' "$(get "$lxs" "$lxs_sys" GTK sNet/ThemeName)"
	printf 'Icons          %s\n' "$(get "$lxs" "$lxs_sys" GTK sNet/IconThemeName)"
	w=$(sed -n '/<theme>/,/<\/theme>/ s|.*<name>\([^<]*\)</name>.*|\1|p' "$obrc" 2>/dev/null | head -n1)
	printf 'Windows        %s%s\n' "${w:-$(sed -n '/<theme>/,/<\/theme>/ s|.*<name>\([^<]*\)</name>.*|\1|p' "$SHARE/openbox-rc.xml" | head -n1)}" \
		"$( [[ -f $own/window ]] && echo ' (chosen)' || echo ' (the theme'"'"'s)')"
	printf 'Cursor         %s, %s pixels\n' "$(get "$lxs" "$lxs_sys" GTK sGtk/CursorThemeName)" "$(get "$lxs" "$lxs_sys" GTK iGtk/CursorThemeSize)"
	printf 'Font           %s\n' "$(get "$lxs" "$lxs_sys" GTK sGtk/FontName)"
	printf 'Accent         %s%s\n' "$(accent_now)" "$( [[ -d $own/themes ]] || echo ' (the theme'"'"'s)')"
	w=$(get "$fm/desktop-items-0.conf" "$fm_sys/desktop-items-0.conf" '*' wallpaper)
	printf 'Wallpaper      %s (%s)\n' "${w:-none}" "$(get "$fm/desktop-items-0.conf" "$fm_sys/desktop-items-0.conf" '*' wallpaper_mode)"
	printf 'Desktop        %s, text %s\n' "$(short "$(get "$fm/desktop-items-0.conf" "$fm_sys/desktop-items-0.conf" '*' desktop_bg)")" \
		"$(short "$(get "$fm/desktop-items-0.conf" "$fm_sys/desktop-items-0.conf" '*' desktop_fg)")"
}

# The highlight colour: in GTK 2's colour scheme, and in a copy of each
# Raspberry Pi OS theme for GTK 3, GTK 4 and Openbox, which the session reads
# before the installed theme (as Raspberry Pi OS keeps them in ~/.local/share/themes)
set_accent() {
	local bg=$1 fg=$2 t d f scheme
	rm -rf "$own/themes" "$own/gtk4"
	if [[ $bg == default ]]; then
		ini_set "$lxs" GTK sGtk/ColorScheme "$(theme_scheme "$(get "$lxs" "$lxs_sys" GTK sNet/ThemeName)" \
			|| ini_get "$lxs_sys" GTK sGtk/ColorScheme)"
		return 0
	fi
	for t in $PI_THEMES; do
		# on top of the session's own layer of the theme, where it has one
		f=/usr/share/themes/$t b=$SHARE/data/themes/$t
		[[ -f $f/gtk-3.0/gtk.css ]] || continue
		[[ -f $b/gtk-3.0/gtk.css ]] || b=$f
		d=$own/themes/$t
		mkdir -p "$d/gtk-3.0"
		printf '@import url("file://%s/gtk-3.0/gtk.css");\n@define-color theme_selected_bg_color %s;\n@define-color theme_selected_fg_color %s;\n' \
			"$b" "$bg" "$fg" >"$d/gtk-3.0/gtk.css"
		if [[ -f $f/openbox-3/themerc ]]; then
			[[ -d $SHARE/data/themes/$t/openbox-3 ]] && b=$SHARE/data/themes/$t || b=$f
			mkdir -p "$d/openbox-3" && ln -s "$b"/openbox-3/* "$d/openbox-3/" && rm -f "$d/openbox-3/themerc"
			sed -E -e "s/^(window\.active\.title\.bg\.color|menu\.items\.active\.bg\.color):.*/\1: $bg/" \
				-e "s/^(window\.active\.label\.text\.color|menu\.items\.active\.text\.color):.*/\1: $fg/" \
				"$f/openbox-3/themerc" >"$d/openbox-3/themerc"
		fi
		if [[ -f $SHARE/gtk4/$t.css ]]; then
			mkdir -p "$own/gtk4"
			sed -E -e "s/^@define-color (accent_color|accent_bg_color|theme_selected_bg_color) .*/@define-color \1 $bg;/" \
				-e "s/^@define-color (accent_fg_color|theme_selected_fg_color) .*/@define-color \1 $fg;/" \
				-e "s/^( *--accent-(bg-)?color:).*/\1 $bg;/" -e "s/^( *--accent-fg-color:).*/\1 $fg;/" \
				"$SHARE/gtk4/$t.css" >"$own/gtk4/$t.css"
		fi
	done
	scheme=$(get "$lxs" "$lxs_sys" GTK sGtk/ColorScheme)
	scheme=$(sed -e "s/selected_bg_color:#[0-9A-Fa-f]*/selected_bg_color:$bg/" -e "s/selected_fg_color:#[0-9A-Fa-f]*/selected_fg_color:$fg/" <<<"$scheme")
	ini_set "$lxs" GTK sGtk/ColorScheme "$scheme"
}

# Openbox's theme, in the user's file of the session
set_openbox_theme() {
	local t=$1 d
	for d in $(theme_dirs themes); do
		[[ -f $d/$t/openbox-3/themerc ]] || continue
		seed "$obrc" "$SHARE/openbox-rc.xml"
		# the theme's own name, not the font names inside <font>
		sed -i "/<theme>/,/<\/theme>/ { /<font /,/<\/font>/b; s|<name>[^<]*</name>|<name>$t</name>| }" "$obrc"
		return 0
	done
}

# The desktop's settings, as Desktop Preferences keeps them, per monitor
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
		[[ -z $font ]] || ini_set "$f" '*' desktop_font "$font"
		[[ -z $dbg ]] || ini_set "$f" '*' desktop_bg "$dbg"
		[[ -z $dbg ]] || ini_set "$f" '*' desktop_shadow "$dbg"
		[[ -z $dfg ]] || ini_set "$f" '*' desktop_fg "$dfg"
		if [[ $wall == none ]]; then ini_set "$f" '*' wallpaper_mode color
		elif [[ -n $wall ]]; then ini_set "$f" '*' wallpaper "$wall"; [[ -n $mode ]] || [[ $(ini_get "$f" '*' wallpaper_mode) != color ]] || ini_set "$f" '*' wallpaper_mode crop
		fi
		[[ -z $mode ]] || ini_set "$f" '*' wallpaper_mode "$mode"
	done
}

theme="" style="" icons="" window="" cursor="" size="" font="" font_name="" font_style="" font_size="" accent="" accent_fg="" dbg="" dfg="" wall="" mode="" reset=0
(( $# )) || { usage; exit 2; }
while (( $# )); do
	o=$1
	case $o in --*=*) set -- "${o%%=*}" "${o#*=}" "${@:2}"; o=$1 ;; esac
	case $o in
		--show) show; exit 0 ;;
		--list) list; exit 0 ;;
		--light|--dark) style=${o#--} ;;
		--mode) (( $# >= 2 )) || die "$o needs a value"; style=${2,,}; shift
			[[ $style == light || $style == dark ]] || die "the mode is light or dark" ;;
		-h|--help) usage; exit 0 ;;
		--reset) reset=1 ;;
		--theme|--icons|--icon|--window|--cursor|--cursor-size|--font|--font-style|--font-size|--accent|--accent-text|--desktop-color|--desktop-text|--wallpaper|--wallpaper-mode)
			(( $# >= 2 )) || die "$o needs a value"
			case $o in
				--theme) theme=$2 ;; --icons|--icon) icons=$2 ;; --window) window=$2 ;; --cursor) cursor=$2 ;; --cursor-size) size=$2 ;;
				--font) font_name=$2 ;; --font-style) font_style=$2 ;; --font-size) font_size=$2 ;;
				--accent) accent=$2 ;; --accent-text) accent_fg=$2 ;;
				--desktop-color) dbg=$2 ;; --desktop-text) dfg=$2 ;; --wallpaper) wall=$2 ;; --wallpaper-mode) mode=$2 ;;
			esac
			shift ;;
		*) die "unknown option '$o' (see --help)" ;;
	esac
	shift
done

[[ -f $lxs_sys ]] || die "the Raspberry Pi Desktop session is not installed"
gtk="" theme_icons="" theme_font=""
# Light or dark version of the current theme.
if [[ -n $style ]]; then
	[[ -z $theme ]] || die "give --theme or --$style, not both"
	cur=$(get "$lxs" "$lxs_sys" GTK sNet/ThemeName)
	case $style/$cur in
		dark/PiXflat|dark/PiXnoir) gtk=PiXnoir ;; dark/PiXtrix|dark/PiXonyx) gtk=PiXonyx ;;
		light/PiXflat|light/PiXnoir) gtk=PiXflat ;; light/PiXtrix|light/PiXonyx) gtk=PiXtrix ;;
		*) die "$cur has no $style version; use --theme" ;;
	esac
fi
if [[ -n $theme ]]; then
	case ${theme,,} in
		pixflat) gtk=PiXflat theme_icons=pixflat theme_font=piboto ;;
		pixnoir) gtk=PiXnoir theme_icons=pixflat theme_font=piboto ;;
		pixtrix) gtk=PiXtrix theme_icons=pixtrix theme_font=nunito ;;
		pixonyx) gtk=PiXonyx theme_icons=pixtrix theme_font=nunito ;;
		pix)     gtk=PiX theme_icons=pix theme_font=piboto ;;
		*) gtk=$theme ;;
	esac
	gtk_theme "$gtk" || die "no GTK theme '$theme' is installed (see --list)"
	[[ -n $icons ]] || icons=$theme_icons
	[[ -n $cursor ]] || cursor=$theme_icons
	[[ -n $font_name ]] || font_name=$theme_font
fi
# Window frames.
if [[ -n $window ]]; then
	if [[ ${window,,} == theme ]]; then window=theme
	else window=$(pi_name "$window"); ob_theme "$window" || die "no window frames '$window' are installed (see --list)"; fi
fi
# Font: family, style and size; unset parts keep their current value.
if [[ -n $font_name$font_style$font_size ]]; then
	cur=$(get "$lxs" "$lxs_sys" GTK sGtk/FontName)
	if [[ -n $font_name ]]; then
		fam=$(font_family "$font_name") || die "no font '$font_name' is installed (see --list)"
		[[ -n $font_style ]] || font_style=$(font_default_style "$fam")
	else
		# keep the current family and style
		fam=$(sed -E 's/ [0-9.]+$//; s/( (Thin|Ultra-Light|Light|Semi-Bold|Bold|Ultra-Bold|Heavy|Medium|Italic))+$//' <<<"$cur")
		if [[ -z $font_style ]]; then
			font_style=$(sed -E 's/ [0-9.]+$//' <<<"$cur"); font_style=${font_style#"$fam"}
			font_style=$(sed 's/Semi-Bold/semibold/; s/Ultra-Bold/extrabold/; s/Ultra-Light/extralight/; s/Heavy/black/' <<<"${font_style# }")
			[[ -n $font_style ]] || font_style=regular
		fi
		[[ $fam != PibotoLt ]] || { fam=Piboto; [[ $font_style != regular ]] || font_style=light; }
	fi
	# A new font takes the session's size; otherwise the current size is kept
	[[ -n $font_name ]] && src=$(ini_get "$lxs_sys" GTK sGtk/FontName) || src=$cur
	[[ -n $font_size ]] || font_size=$(grep -oE '[0-9]+(\.[0-9]+)?$' <<<"$src")
	[[ -n $font_size ]] || font_size=12
	[[ $font_size =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( ${font_size%.*} >= 6 && ${font_size%.*} <= 48 )) || die "the font size is a number of points, 6 to 48"
	words=$(pango_style "$font_style") || die "unknown font style '$font_style' (see --help)"
	# accept only styles the font has
	w=${font_style,,}; w=${w//italic/}; w=${w// /}; [[ -n $w ]] || w=regular
	if [[ $w != regular ]] && ! font_styles "$fam" | grep -qxE "$w|$w italic"; then
		die "$fam has no '$font_style' style; it has: $(font_styles "$fam" | paste -sd, - | sed 's/,/, /g')"
	fi
	font="$fam${words:+ $words} $font_size"
fi
if [[ -n $icons ]]; then icons=$(icon_theme "$icons") || die "no icon theme '$icons' is installed"; fi
if [[ -n $cursor ]]; then cursor=$(icon_theme "$cursor" cursors) || die "no cursor theme '$cursor' is installed"; fi
if [[ -n $size ]]; then [[ $size =~ ^[0-9]+$ ]] && (( size >= 8 && size <= 256 )) || die "the cursor size is a number of pixels, 8 to 256"; fi
if [[ -n $accent && $accent != default ]]; then accent=$(colour "$accent") || die "a colour is #rgb or #rrggbb"; fi
if [[ -n $accent_fg ]]; then accent_fg=$(colour "$accent_fg") || die "a colour is #rgb or #rrggbb"; fi
if [[ -n $dbg ]]; then dbg=$(colour "$dbg") || die "a colour is #rgb or #rrggbb"; fi
if [[ -n $dfg ]]; then dfg=$(colour "$dfg") || die "a colour is #rgb or #rrggbb"; fi
if [[ -n $wall && $wall != none ]]; then
	if [[ $wall != /* ]]; then
		for f in /usr/share/rpd-wallpaper/"$wall" /usr/share/rpd-wallpaper/"$wall".jpg /usr/share/rpd-wallpaper/"$wall".png; do
			[[ -f $f ]] && { wall=$f; break; }
		done
	fi
	[[ -f $wall ]] || die "no wallpaper '$wall' (see /usr/share/rpd-wallpaper)"
fi
if [[ -n $mode ]]; then [[ $mode =~ ^(crop|fit|stretch|center|tile|color)$ ]] || die "the wallpaper mode is crop, fit, stretch, center, tile or color"; fi
if [[ -n $accent_fg && -z $accent ]]; then accent=$(accent_now) || die "set --accent too"; fi

# Settings saved under earlier names (the session's start does the same)
o=$config/openbox/$PROFILE-rc.xml
if [[ -f $o && ! -L $o && ! -e $obrc ]]; then
	mv -f "$o" "$obrc" && ln -s "$OBFILE" "$o"
	[[ ! -e ${o%/*}/.${o##*/}.$APP ]] || mv -f "${o%/*}/.${o##*/}.$APP" "${obrc%/*}/.$OBFILE.$APP"
fi
(cd / && . "$SHARE/session-env" && fm_profile) >/dev/null 2>&1 || true

# The user's files
seed "$lxs" "$lxs_sys"
for i in 0 1; do [[ ! -f $fm_sys/desktop-items-$i.conf ]] || seed "$fm/desktop-items-$i.conf" "$fm_sys/desktop-items-$i.conf"; done
old_icons=$(ini_get "$lxs" GTK sNet/IconThemeName)
old_cursor=$(ini_get "$lxs" GTK sGtk/CursorThemeName)/$(ini_get "$lxs" GTK iGtk/CursorThemeSize)
old_font=$(ini_get "$lxs" GTK sGtk/FontName)
if (( reset )); then
	for k in sNet/ThemeName sNet/IconThemeName sGtk/CursorThemeName iGtk/CursorThemeSize sGtk/FontName sGtk/ColorScheme; do
		ini_set "$lxs" GTK "$k" "$(ini_get "$lxs_sys" GTK "$k")"
	done
	rm -rf "$own/themes" "$own/gtk4"
	reset_desktop
	# Openbox follows the session's look again
	mkdir -p "${obrc%/*}" && cp "$SHARE/openbox-rc.xml" "$obrc" && cp "$SHARE/openbox-rc.xml" "${obrc%/*}/.$OBFILE.$APP"
fi
# A chosen window frame is remembered; a new theme resets it.
if [[ -n $window || -n $theme ]] || (( reset )); then rm -f "$own/window"; fi
if [[ -n $gtk ]]; then
	ini_set "$lxs" GTK sNet/ThemeName "$gtk"
	[[ -f $own/window ]] || set_openbox_theme "$gtk"
	# the theme's own colours (a dark panel for a dark theme), with your
	# highlight colour, if you chose one
	if s=$(theme_scheme "$gtk"); then
		mine=""; [[ ! -d $own/themes || -n $accent ]] || mine=$(accent_now)
		ini_set "$lxs" GTK sGtk/ColorScheme "$s"
		[[ -z $mine ]] || accent=$mine
	fi
fi
[[ -z $icons ]] || ini_set "$lxs" GTK sNet/IconThemeName "$icons"
[[ -z $cursor ]] || ini_set "$lxs" GTK sGtk/CursorThemeName "$cursor"
[[ -z $size ]] || ini_set "$lxs" GTK iGtk/CursorThemeSize "$size"
[[ -z $font ]] || ini_set "$lxs" GTK sGtk/FontName "$font"
[[ -z $font ]] || set_openbox_font "$fam" "$(ob_weight "$font_style")" "$font_style" "$font_size"
if [[ -n $window ]]; then
	if [[ $window == theme ]]; then set_openbox_theme "$(ini_get "$lxs" GTK sNet/ThemeName)"
	else set_openbox_theme "$window"; mkdir -p "$own" && printf '%s\n' "$window" >"$own/window"; fi
fi
[[ -z $accent ]] || set_accent "$accent" "${accent_fg:-$( [[ $accent == default ]] || readable "$accent")}"
write_desktop

# The running session on Wayland: its settings are made from the same files
wl=$(pgrep -u "$(id -u)" -x labwc | head -n1)
if [[ -n $wl ]]; then
	(
		while IFS= read -r -d '' line; do
			case $line in WAYLAND_DISPLAY=*|XDG_RUNTIME_DIR=*|DBUS_SESSION_BUS_ADDRESS=*|DISPLAY=*) export "${line?}" ;; esac
		done </proc/"$wl"/environ
		. "$SHARE/session-env"
		wayland_look; gtk4_on
		kill -HUP "$wl"
		# X applications: xsettingsd reads its file again
		pkill -HUP -u "$(id -u)" -x xsettingsd
	) >/dev/null 2>&1 || true
fi
# The running session on X: lxsession passes the theme, icons, cursor, font
# and GTK 2 colours on by itself when its file changes
p=$(session_pid)
if [[ -z $p ]]; then
	if [[ -n $wl ]]; then echo "Applied to the Raspberry Pi Desktop session on Wayland."
	else echo "Saved; the Raspberry Pi Desktop session uses it from your next login."; fi
	show
	exit 0
fi
attach "$p"
if [[ -n $accent || $reset == 1 ]] && [[ -z $gtk ]]; then
	# GTK 3 reads the colours again only with a new theme: a moment on
	# another one, as Raspberry Pi OS does
	t=$(ini_get "$lxs" GTK sNet/ThemeName)
	tmp=Adwaita; [[ -d /usr/share/themes/t$t ]] && tmp=t$t
	ini_set "$lxs" GTK sNet/ThemeName "$tmp"; sleep 1
	ini_set "$lxs" GTK sNet/ThemeName "$t"
fi
if running openbox; then openbox --reconfigure >/dev/null 2>&1 || true; fi
if [[ -n $dbg$dfg$wall$mode$font || $reset == 1 ]]; then
	if running pcmanfm-pi; then
		pcmanfm-pi --profile "$FMPROFILE" --reconfigure >/dev/null 2>&1 || true
	elif running pcmanfm; then
		# Debian's file manager reads its settings again only at login; it
		# takes a new wallpaper at once, and then saves all its settings
		if [[ -n $wall$mode || $reset == 1 ]]; then
			f=$fm/desktop-items-0.conf
			pcmanfm --profile "$FMPROFILE" --set-wallpaper "$(ini_get "$f" '*' wallpaper)" \
				--wallpaper-mode "$(ini_get "$f" '*' wallpaper_mode)" >/dev/null 2>&1 || true
			sleep 1
			if (( reset )); then reset_desktop; else write_desktop; fi
		fi
		[[ -z $dbg$dfg ]] && [[ -z $font || $font == "$old_font" ]] || echo "The desktop's colours and font change at your next login."
		[[ -z $gtk$accent && $reset == 0 ]] || echo "Debian's file manager shows the new colours fully from your next login."
	fi
fi
if [[ -n $gtk$icons$accent$font$window || $reset == 1 ]] || [[ $(ini_get "$lxs" GTK sNet/IconThemeName) != "$old_icons" ]]; then
	# The panel builds its menu once: restart it after lxsession has passed
	# the new theme on
	sleep 2
	if running lxpanel-pi; then lxpanelctl-pi restart 2>/dev/null || true
	elif running lxpanel; then lxpanelctl restart 2>/dev/null || true; fi
fi
[[ $(ini_get "$lxs" GTK sGtk/CursorThemeName)/$(ini_get "$lxs" GTK iGtk/CursorThemeSize) == "$old_cursor" ]] \
	|| echo "Window borders keep the old cursor until your next login."
show
EOF
	} | _write "$root/usr/bin/$APP_NAME-set"
	chmod 0755 "$root/usr/bin/$APP_NAME-set"
}

# Set the session's values (S_*): its profile, the Debian logo, the wallpaper,
# and whether Raspberry Pi's panel and file manager are used. In the main
# shell, before the package is built, so the other desktops get them too.
session_vars() {
	S_PROFILE=$(session_profile)
	S_LOGO=$(_logo_path || true)
	S_WALL=$(_wallpaper_path)
	S_PI_PANEL=0 S_PI_FM=0 S_PI_STACK=0
	if (( O_PI_APPS )); then
		if [[ -x /usr/bin/lxpanel-pi ]]; then S_PI_PANEL=1; fi
		if [[ -x /usr/bin/pcmanfm-pi ]]; then S_PI_FM=1; fi
		# Raspberry Pi's builds in place of Debian's, before Debian 13
		if (( ! S_PI_PANEL )) && _stack_installed; then S_PI_STACK=1; fi
	fi
	# Raspberry Pi's file manager uses its default profile, as on Raspberry Pi OS
	S_FM_PROFILE=$S_PROFILE
	if (( S_PI_FM )); then S_FM_PROFILE=default; fi
}

# Write the whole session into the package root: profile, Openbox, panels,
# menu, file manager, entries, icons, themes, GTK 4 colours and programs.
# Usage: session_build ROOT
session_build() {
	local root=$1 xdg=$1$SHARE/xdg data=$1$SHARE/data rc t css
	_session_profile "$xdg"
	rc=$root$SHARE/openbox-rc.xml
	_seed "$rc" "$SYS_ROOT"/etc/xdg/openbox/LXDE/rc.xml "$SYS_ROOT"/etc/xdg/openbox/rc.xml || die "Openbox's rc.xml is missing (install openbox)"
	_openbox_rc "$rc"
	_openbox_keys "$rc"
	if (( S_PI_STACK )); then _pi_stack_layout; else _lxpanel_layout; fi | _write "$xdg/lxpanel/$S_PROFILE/panels/panel"
	command -v pishutdown >/dev/null && printf '[Command]\nLogout=pishutdown\n' | _write "$xdg/lxpanel/$S_PROFILE/config"
	(( S_PI_PANEL )) && _pi_panel_layout | _write "$xdg/lxpanel-pi/panels/panel"
	_session_files "$xdg"
	_session_menu "$xdg" "$data"
	_session_entries "$xdg" "$data"
	_session_icons "$data"
	_session_themes "$data"
	for t in PiXflat PiXnoir PiXtrix PiXonyx PiX; do
		css=$(gtk4_colors "$t") || continue
		printf '%s\n' "$css" | _write "$root$SHARE/gtk4/$t.css"
	done
	_session_programs "$root"
	_session_command "$root"
	_session_dconf "$root"
	if [[ $H_DISPLAY == wayland && -x /usr/bin/labwc && -x /usr/bin/wf-panel-pi ]]; then _session_wayland "$root"; fi
}

# Succeed if Raspberry Pi's own greeter is installed and can run here.
_pi_greeter_ok() {
	[[ -x /usr/sbin/pi-greeter && -f /usr/share/xgreeters/pi-greeter-x.desktop ]] || return 1
	! grep -q 'not found' <<<"$(ldd /usr/sbin/pi-greeter 2>/dev/null)"
}

# Print the login screen's background picture: Debian's own login artwork,
# which follows Debian's active theme, Raspberry Pi OS's (the dark one for
# dark themes), or a picture given; Raspberry Pi OS's where the one asked for
# is missing (a derivative has no Debian artwork). Usage: login_background [ROOT]
login_background() {
	local root=${1:-} img=RPiSystem.png f=$O_LOGIN_BG
	[[ $f != debian ]] || f=/usr/share/desktop-base/active-theme/login/background.svg
	if [[ $f == /* && -e $f ]]; then printf '%s\n' "$f"; return 0; fi
	[[ $O_LOGIN_BG == raspios || $f == /usr/share/desktop-base/* ]] || warn "The login background $f is missing; Raspberry Pi OS's is used."
	(( T_DARK )) && img=RPiSystem_dark.png
	[[ -f $root$SHARE/login/$img ]] || img=RPiSystem.png
	if [[ -f $root$SHARE/login/$img ]]; then printf '%s\n' "$SHARE/login/$img"; fi
}

# The Raspberry Pi OS login screen, for LightDM: Debian's GTK greeter in its
# style, which keeps the session chooser, or with --pi-greeter Raspberry Pi's
# own greeter, which has none. A greeter of the package's own then starts
# Raspberry Pi's where it can run, else Debian's, so the login screen keeps
# working when one is removed. Usage: login_build ROOT
login_build() {
	local root=$1 art=$SHARE/login logo bg
	logo=$(_greeter_logo || true)
	mkdir -p "$root$art"
	# Unpacked now, else kept from the installed package
	cp -- "$WORKDIR"/login/* "$root$art/" 2>/dev/null || cp -- "$art"/* "$root$art/" 2>/dev/null || true
	bg=$(login_background "$root")
	[[ -n $bg ]] || { bg='#d6d3de'; warn "The Raspberry Pi OS login screen wallpaper is unavailable; the login screen shows its colour."; }
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
	# Raspberry Pi OS lists the users to choose from (pi-greeter's postinst)
	{
		printf '# Written by %s: the Raspberry Pi OS login screen\n[Seat:*]\ngreeter-hide-users=false\n' "$APP_NAME"
		(( O_PI_GREETER )) && printf 'greeter-session=%s\n' "$APP_NAME"
	} | _write "$root/usr/share/lightdm/lightdm.conf.d/60_$APP_NAME.conf"
	(( O_PI_GREETER )) || return 0
	printf '[Desktop Entry]\nType=Application\nName=Raspberry Pi OS login screen\nComment=Run by LightDM only\nExec=%s/greeter\n' \
		"$SHARE" | _write "$root/usr/share/xgreeters/$APP_NAME.desktop"
	cat <<'EOF' | _write "$root$SHARE/greeter"
#!/bin/sh
# Raspberry Pi's own greeter where it can run, else Debian's default one.
if [ -x /usr/sbin/pi-greeter ] && ! ldd /usr/sbin/pi-greeter 2>/dev/null | grep -q 'not found'; then
	exec /usr/sbin/pi-greeter
fi
for f in /usr/share/xgreeters/lightdm-greeter.desktop /usr/share/xgreeters/lightdm-gtk-greeter.desktop; do
	cmd=$(sed -n 's/^Exec=//p' "$f" 2>/dev/null | head -n1)
	[ -n "$cmd" ] && exec $cmd
done
exit 1
EOF
	chmod 0755 "$root$SHARE/greeter"
}

# Set up Raspberry Pi's own greeter: it shows the same login box, so only its
# settings (pi-greeter.conf) are adapted: the Debian logo instead of the
# Raspberry Pi one, the login wallpaper and the chosen theme, icons and font.
# The original file is kept, and --uninstall puts it back.
greeter_conf() {
	local conf=/etc/lightdm/pi-greeter.conf logo wall
	_pi_greeter_ok || return 0
	logo=$(_greeter_logo || true)
	wall=$(login_background)
	if [[ ! -f $conf ]]; then
		[[ -f $SYS_DIR/pi-greeter.conf.orig ]] || : | sys_write "$SYS_DIR/pi-greeter.conf.new"   # none: removed again on uninstall
	elif [[ ! -f $SYS_DIR/pi-greeter.conf.orig && ! -f $SYS_DIR/pi-greeter.conf.new ]]; then
		sys_write "$SYS_DIR/pi-greeter.conf.orig" <"$conf"
	fi
	{
		printf '# Written by %s %s: the Raspberry Pi OS login screen with Debian branding.\n' "$APP_NAME" "$APP_VERSION"
		printf '# The original file is in %s.\n[greeter]\n' "$SYS_DIR/pi-greeter.conf.orig"
		if [[ -n $logo ]]; then printf 'default-user-image=%s\n' "$logo"; fi
		printf 'desktop_bg=%s\n' "$T_DESK_BG"
		if [[ -n $wall ]]; then printf 'wallpaper=%s\nwallpaper_mode=crop\n' "$wall"; fi
		printf 'gtk-theme-name=%s\ngtk-icon-theme-name=%s\ngtk-font-name=%s\n' "$T_GTK" "$T_ICONS" "$T_FONT"
	} | sys_write "$conf"
	ok "Login screen: Raspberry Pi's own greeter, with the Debian logo"
}

# Choose the Raspberry Pi Desktop session for this user's next logins, as
# picking it on the login screen does: through AccountsService, which LightDM
# and GDM read, else in ~/.dmrc and LightDM's copy of it, which its greeter
# reads (it cannot read a private home folder). Done on the first install,
# and later where AccountsService has no session for the user yet (it came
# after); a session the user picks on the login screen is kept.
choose_session() {
	local user cur first=0 want=$SESSION_ID wl=/usr/share/wayland-sessions/$SESSION_ID-wayland.desktop
	[[ $H_DISPLAY == wayland && -f $wl ]] && want=$SESSION_ID-wayland
	_once session-chosen && first=1
	user=/org/freedesktop/Accounts/User$(id -u)
	if command -v busctl >/dev/null \
		&& cur=$(busctl get-property org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User XSession 2>/dev/null); then
		# Set on first install, on a Wayland option, or if the Wayland session is gone
		(( first )) || [[ $cur == 's ""' || -n ${GIVEN[wayland]:-} ]] \
			|| { [[ $cur == "s \"$SESSION_ID-wayland\"" && ! -f $wl ]]; } || return 0
		as_root busctl call org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User SetXSession s "$want" >/dev/null 2>&1 || true
		as_root busctl call org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User SetSession s "$want" >/dev/null 2>&1 || true
	else
		(( first )) || [[ -n ${GIVEN[wayland]:-} ]] || return 0
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

# Decide what to install: every theme with its icons, fonts, wallpapers and
# login screen and, where they fit, Raspberry Pi's panel and file manager, as
# FETCH_PKGS from verified .deb files; and the Debian packages the session and
# the themes need, as APT_PKGS by name. Installed packages are never upgraded
# by APT on this script's behalf.
resolve_all() {
	local p
	local -a wanted=() helpers=()
	if [[ -n $REPO ]]; then
		step "Resolving packages from packages/ ($H_SUITE, $H_ARCH)"
	else
		step "Resolving the latest official packages ($H_SUITE, $H_ARCH)"
		index_load rpi "$H_SUITE" "$(rpi_arch)" || die "cannot download the $H_SUITE package index from $RPI_ARCHIVE"
		ok "Package index signature verified (Raspberry Pi Archive Signing Key)"
	fi
	# Before Debian 13, Raspberry Pi's panel and file manager replace Debian's
	USE_STACK=0 STACK_NAMES=()
	if (( O_PI_APPS )) && [[ -n $H_RPI_ARCH ]] && ! suite_ge "$H_SUITE" trixie; then
		USE_STACK=1
		mapfile -t STACK_NAMES < <(printf '%s\n' "${PI_STACK[@]}"; stack_extras)
	fi
	while read -r p; do
		case $p in
			pi-greeter) (( O_LOGIN && O_PI_GREETER )) && with_lightdm || continue ;;
			lxpanel-pi|lpplug-*|pplug-*|pishutdown|gui-runcmd|pcmanfm-pi) (( O_PI_APPS )) || continue ;;
			lxplug-*) (( USE_STACK )) || continue ;;
			wf-panel-pi|wfplug-*|pipanel|rpcc|sudopwd) [[ $H_DISPLAY == wayland ]] && apt_has labwc || continue ;;
		esac
		if [[ $p =~ ^(lxpanel|pcmanfm|libfm) && $p != lxpanel-pi && $p != pcmanfm-pi ]] && (( ! USE_STACK )); then continue; fi
		wanted+=("$p")
	done < <(rpi_pkgs "$H_SUITE" "$(rpi_arch)" "$O_4K")
	[[ -n $REPO ]] || mapfile -t wanted < <(with_rpi_deps "$H_SUITE" "$(rpi_arch)" "${wanted[@]}")
	FETCH_PKGS=()
	for p in "${wanted[@]}"; do IN_SET[$p]=1; done
	for p in "${wanted[@]}"; do
		if resolve_pkg "$p"; then FETCH_PKGS+=("$p")
		# Without Raspberry Pi builds for this architecture, the packages with
		# compiled code are left out, as noted already
		elif [[ -n $H_RPI_ARCH ]]; then warn "$p is not available for $H_SUITE/$H_ARCH; skipping it"; fi
	done
	[[ " ${FETCH_PKGS[*]} " == *-theme\ * ]] || die "no theme packages are available for $H_SUITE/$H_ARCH"
	# All of Raspberry Pi's builds, or none: a Debian package of the same
	# sources that is left would not work with them
	if (( USE_STACK )); then
		for p in "${STACK_NAMES[@]}"; do
			[[ " ${FETCH_PKGS[*]} " == *" $p "* ]] && continue
			note "Debian's panel and file manager are used: Raspberry Pi OS has no build of $p for $H_SUITE/$H_ARCH."
			USE_STACK=0 STACK_NAMES=()
			mapfile -t FETCH_PKGS < <(printf '%s\n' "${FETCH_PKGS[@]}" | grep -vE '^(lxplug-.*|lxpanel|lxpanel-data|pcmanfm|libfm.*)$')
			break
		done
	fi
	if [[ $H_DISPLAY == wayland && " ${FETCH_PKGS[*]} " != *" wf-panel-pi "* ]]; then
		H_DISPLAY=x11 H_DISPLAY_WHY="Raspberry Pi's Wayland panel or labwc is not available for $H_SUITE/$H_ARCH"
		note "The session runs on X: $H_DISPLAY_WHY."
		# without the Wayland session's own packages
		mapfile -t FETCH_PKGS < <(printf '%s\n' "${FETCH_PKGS[@]}" | grep -vxE 'wfplug-.*|pipanel|rpcc|sudopwd')
	fi
	_refuse_debian_names "${FETCH_PKGS[@]}"

	mapfile -t helpers < <(session_debs; theme_debs "$H_SUITE"; tray_debs "$H_SUITE"
		if [[ $H_DISPLAY == wayland ]]; then wayland_debs; fi)
	(( O_QT )) && helpers+=(qt5-gtk-platformtheme qt6-gtk-platformtheme)
	# LightDM keeps each user's session choice in AccountsService; its greeter
	# cannot read it otherwise from a private home folder
	! with_lightdm || helpers+=(accountsservice)
	if (( O_LOGIN )) && [[ -n $H_DM && $H_DM != lightdm ]]; then
		note "The Raspberry Pi OS login screen needs LightDM; this computer uses $H_DM. To switch: sudo apt install lightdm lightdm-gtk-greeter && sudo dpkg-reconfigure lightdm, then run this again."
	fi
	# Hardware support: network and Bluetooth tools, sound, missing firmware,
	# and the login screen
	mapfile -t HW_PKGS < <(x11_debs; tray_debs "$H_SUITE" | grep -vE '^debian-reference'; audio_debs "$H_SUITE"; firmware_debs; login_debs)
	for p in "${HW_PKGS[@]}"; do
		if [[ $(pkg_category "$p") == firmware ]] && ! apt_has "$p"; then
			note "$p holds firmware this computer needs: add 'non-free-firmware' (Debian 12 and later; 'non-free' before) to your APT sources, then run this again."
		fi
	done
	helpers+=("${HW_PKGS[@]}")
	grep -q -- --root-owner-group <<<"$(dpkg-deb --help 2>/dev/null)" || helpers+=(fakeroot)
	ROOT_PKGS=("${FETCH_PKGS[@]}" "${helpers[@]}")
	APT_PKGS=()
	for p in "${helpers[@]}"; do
		[[ " ${APT_PKGS[*]} " == *" $p "* || " ${FETCH_PKGS[*]} " == *" $p "* || -n $(installed_version "$p") ]] && continue
		if [[ -n $REPO ]] || apt_has "$p"; then APT_PKGS+=("$p"); fi
	done

	if [[ -n $REPO ]]; then
		# Offline: install every member of the selection's dependency closure that
		# the repository has and the system lacks; the rest is already installed.
		local -a roots=("${FETCH_PKGS[@]}" "${APT_PKGS[@]}")
		APT_PKGS=()
		while read -r p; do
			[[ -n ${PKG_VER[$p]:-} || -n $(installed_version "$p") ]] && continue
			if resolve_pkg "$p"; then FETCH_PKGS+=("$p") DEP_PKGS+=("$p"); fi
		done < <(INSTALLED=1 _closure "$WORKDIR/index/local/$H_SUITE/Packages-$H_ARCH" "${roots[@]}")
		for p in "${roots[@]}"; do
			[[ -n ${PKG_VER[$p]:-} || -n $(installed_version "$p") ]] || warn "$p is not in packages/; skipping it"
		done
	fi
	for p in "${FETCH_PKGS[@]}" "${APT_PKGS[@]}"; do IN_SET[$p]=1; done
}

# A Raspberry Pi package must never replace a package from the APT sources,
# except its builds of Debian's panel and file manager (STACK_NAMES), which
# --pi-apps installs in their place. Usage: _refuse_debian_names PACKAGE...
_refuse_debian_names() {
	local p
	for p; do
		[[ " ${STACK_NAMES[*]} " != *" $p "* ]] || continue
		if [[ -n $(apt-cache madison "$p" 2>/dev/null) ]]; then
			die "refusing to install $p from Raspberry Pi OS: your APT sources provide a package with that name"
		fi
	done
}

# Print the state of a resolved package on this system: new, an update, or
# current. A newer installed version is never downgraded.
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

# Print the component type of a package, also its folder in packages/pool.
pkg_category() {
	case $1 in
		sound-theme-*)               echo sounds ;;
		firmware-*|*-firmware)       echo firmware ;;
		pipewire*|pulseaudio|wireplumber) echo sound ;;
		pi-greeter|lightdm*|desktop-base) echo greeter ;;
		pcmanfm-pi|pcmanfm|libfm*)   echo files ;;
		lxpanel*|lpplug-*|pplug-*|lxplug-*|wf-panel-pi|wfplug-*|rpcc|pipanel|sudopwd|pishutdown|gui-runcmd|debian-reference-*) echo panel ;;
		network-manager*|nm-connection-editor|wpasupplicant|iw|wireless-regdb|rfkill|bluez*|blueman|libspa-0.2-bluetooth|pulseaudio-module-bluetooth) echo network ;;
		lxsession*|lxpolkit|openbox|lxappearance|accountsservice|gvfs*|lxde-*|lxmenu-data|labwc|swaybg|kanshi|xsettingsd|wlr-randr|xwayland|dconf-cli|libglib2.0-bin) echo session ;;
		xserver-*|x11-*|libgl1-mesa-dri) echo display ;;
		*icon-theme*|*-icons)        echo icons ;;
		*-theme)                     echo themes ;;
		fonts-*)                     echo fonts ;;
		gtk2-engines-*|libgtk2.0-*|libgdk-pixbuf*) echo engines ;;   # GTK 2 engines and runtime
		*wallpaper*|"$ART_PKG")      echo wallpapers ;;
		*)                           echo dependencies ;;
	esac
}

# Stop unless every package in APT's plan comes from an official source: the
# verified files ("local-deb") or the Debian archive and its security updates
# (on a derivative, its own archive). This keeps third-party and Raspberry Pi rebuilds of Debian packages
# out, even if such a source is configured.
# Usage: _check_origins APT-SIMULATION-OUTPUT
_check_origins() {
	local line pkg origins own=Debian
	[[ -n $H_ID && $H_ID != debian ]] && own=${H_ID^}
	while IFS= read -r line; do
		pkg=$(awk '{ print $2 }' <<<"$line")
		# the archive name, up to the release it belongs to: "Debian:13/stable"
		origins=$(sed -E 's/^Inst [^ ]+ (\[[^]]*\] )?\([^ ]+ ([^[]*)\[.*/\2/' <<<"$line")
		origins=${origins%%:*}; origins=${origins%% }
		if [[ ! $origins =~ ^(local-deb|Debian|Debian-Security|$own|$own-Security)$ ]]; then
			die "refusing to install $pkg from '${origins% }': Debian packages must come from Debian"
		fi
	done < <(grep '^Inst ' <<<"$1")
}

# Offline: place the verified files in a private APT archive cache under APT's
# own names. APT then uses them even when the APT sources list the same
# version, instead of trying to download it.
_prime_apt_cache() {
	local f
	mkdir -p "$WORKDIR/archives/partial"
	for f; do
		cp -- "$f" "$WORKDIR/archives/$(dpkg-deb -f "$f" Package)_$(dpkg-deb -f "$f" Version | sed 's/:/%3a/')_$(dpkg-deb -f "$f" Architecture).deb"
	done
}

# The Raspberry Pi OS release whose configuration packages serve this system:
# its own from Raspberry Pi OS 13, else Raspberry Pi OS 13's. Offline, they
# are in packages/ with the release's packages.
config_suite() {
	if suite_ge "$H_SUITE" trixie || [[ -n $REPO && $O_MODE != download ]]; then echo "$H_SUITE"; else echo trixie; fi
}

# Unpack the Raspberry Pi OS login screen wallpapers (light and dark) and their
# licence from $ART_PKG into $WORKDIR/login. A failed download does not stop
# the run; the login screen then shows its colour.
_login_art() {
	local x
	if x=$( (pi_unpack "$ART_PKG" "$(config_suite)" "$(rpi_arch)") 2>/dev/null ) && compgen -G "$x/usr/share/rpd-wallpaper/RPiSystem*.png" >/dev/null; then
		mkdir -p "$WORKDIR/login"
		install -m 0644 "$x"/usr/share/rpd-wallpaper/RPiSystem*.png "$x/usr/share/doc/$ART_PKG/copyright" "$WORKDIR/login/"
		ok "Login screen wallpaper from $ART_PKG (unpacked, not installed)"
	else
		warn "$ART_PKG is not available; the login screen uses its background colour"
	fi
}

# Print the given packages with the Raspberry Pi packages they need that
# Debian does not have (such as a plugin's data), which come from Raspberry Pi
# as well. Usage: with_rpi_deps SUITE ARCH PACKAGE...
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
}

# Download, verify and install the packages. APT never removes packages
# (--no-remove) and, offline, never downloads (--no-download). Every package
# installed this way is recorded for --uninstall.
install_all() {
	local p f cur sim had
	local -a files=() opts=("${APT_OPTS[@]}") new=()
	if [[ -n $REPO ]]; then step "Preparing packages"; else step "Downloading and verifying packages"; fi
	if [[ -z $REPO ]]; then
		info "Refreshing APT package lists"
		as_root apt-get update -q >/dev/null || die "apt-get update failed"
		for p in "${APT_PKGS[@]}"; do apt_has "$p" || die "the Debian package '$p' is not available from your APT sources"; done
	fi
	for p in "${FETCH_PKGS[@]}"; do
		cur=$(installed_version "$p")
		if [[ -n $cur ]] && dpkg --compare-versions "$cur" ge "${PKG_VER[$p]}"; then
			debug "$p $cur is installed and up to date"
			continue
		fi
		f=$(download_pkg "$p")
		if [[ -z $REPO ]]; then          # packages/ is adapted already
			f=$(deps_drop "$f")
			f=$(compat_fix "$f")
			f=$(fm_coinstall "$f")
			f=$(rpcc_session "$f")
			f=$(scripts_coinstall "$f") || continue
		fi
		f=$(data_coinstall "$f")
		files+=("$f")
	done
	(( O_LOGIN )) && _login_art
	if [[ -n $REPO ]]; then
		# Offline: only what is needed, never downloads (recommended packages
		# outside packages/ would otherwise be fetched from the APT sources)
		opts+=(--no-download -o "Dir::Cache::archives=$WORKDIR/archives/")
		_prime_apt_cache "${files[@]}"
	fi

	step "Installing packages"
	if (( ${#files[@]} + ${#APT_PKGS[@]} == 0 )); then ok "Every package is installed and up to date"; return 0; fi
	had=$(installed_names)
	if ! sim=$(LC_ALL=C apt-get install --simulate "${opts[@]}" "${files[@]}" "${APT_PKGS[@]}" 2>&1); then
		tail -n 15 <<<"$sim" >&2
		[[ -n $REPO ]] && warn "an offline install can only use packages that are installed or in packages/"
		die "APT cannot install the packages on this system (see above); nothing was changed"
	fi
	_check_origins "$sim"
	if ! as_root env DEBIAN_FRONTEND=noninteractive apt-get install "${opts[@]}" "${files[@]}" "${APT_PKGS[@]}" 2>&1 \
		| tee "$WORKDIR/apt.out"; then
		# APT downloads everything before it installs anything
		if grep -q ' 404 ' "$WORKDIR/apt.out"; then
			die "your APT sources point to files Debian has moved (404 Not Found), so nothing was installed. When a Debian release reaches its end, its packages and security updates move to archive.debian.org: change /etc/apt/sources.list to match (see https://www.debian.org/distrib/archive), run 'sudo apt update', then run this again"
		fi
		die "APT could not install the packages (see above)"
	fi
	_verify_installed
	mapfile -t new < <(LC_ALL=C comm -13 <(printf '%s\n' "$had") <(installed_names))
	_record_installed "${new[@]}"
	start_sound "${new[@]}"
	RELOGIN=1
}

# Start a sound server installed this run for the running user, whose service
# manager only starts it at the next login otherwise.
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

# Record newly installed packages for --uninstall. Only the dependencies are
# marked automatic, as APT marks the dependencies it installs itself; what
# this script installs for its own sake stays manual, so 'apt autoremove'
# never takes it while the look is installed.
_record_installed() {
	local p
	local -a autos=()
	(( $# )) || return 0
	for p; do [[ " ${ROOT_PKGS[*]} " == *" $p "* ]] || autos+=("$p"); done
	if (( ${#autos[@]} )); then as_root apt-mark auto "${autos[@]}" >/dev/null; fi
	# Hardware support stays when the look is uninstalled
	local -a look=() hw=()
	for p; do if [[ " ${HW_PKGS[*]} " == *" $p "* ]]; then hw+=("$p"); else look+=("$p"); fi; done
	if (( ${#look[@]} )); then printf '%s\n' "${look[@]}" | record_add "$SYS_DIR/installed-packages"; fi
	if (( ${#hw[@]} )); then printf '%s\n' "${hw[@]}" | record_add "$SYS_DIR/hardware-packages"; fi
}

# Record the packages installed before the first install, once, so that the
# uninstall never removes one of them.
record_packages_before() {
	[[ -f $SYS_DIR/packages-before ]] || installed_names | sys_write "$SYS_DIR/packages-before"
}

# Build the generated package from the installed official themes: icon sets
# with the Debian logo and the names Debian's programs use, Xfwm4 themes, the
# session, and the login screen. Prints its path.
# shellcheck disable=SC2016  # maintainer scripts contain a literal $1
build_pkg() {
	local stage=$WORKDIR/pkg t b f ver icons=() depends="lxsession, openbox, lxpanel | lxpanel-pi, pcmanfm"
	rm -rf -- "$stage"; mkdir -p "$stage/DEBIAN"
	for t in PiXflat PiXnoir PiXtrix PiXonyx PiX; do
		[[ -f $SYS_ROOT/usr/share/themes/$t/openbox-3/themerc ]] || continue
		gen_xfwm4 "$SYS_ROOT/usr/share/themes/$t/openbox-3" "$stage/usr/share/themes/$t/xfwm4" "$t"
	done
	for b in PiXflat PiXtrix PiX; do
		[[ -f $SYS_ROOT/usr/share/icons/$b/index.theme ]] || continue
		gen_icon_overlay "$b" "$stage/usr/share/icons/$b-Debian"
		icons+=("$b-Debian")
	done
	session_build "$stage"
	if (( O_LOGIN )) && [[ -n $(installed_version lightdm) ]]; then login_build "$stage"; fi

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
 programs ask for, Xfwm4 themes generated from the official Openbox themes,
 and the Raspberry Pi OS login screen style.
EOF
	{
		printf '#!/bin/sh\nset -e\nif [ "$1" = configure ] && command -v gtk-update-icon-cache >/dev/null; then\n'
		for f in "${icons[@]}"; do printf '\tgtk-update-icon-cache -q -t -f /usr/share/icons/%s || true\n' "$f"; done
		printf '\t:\nfi\n'
		# Link Debian's applets into Raspberry Pi's panel
		printf 'if [ "$1" = configure ]; then\n\tfor d in /usr/lib/*/lxpanel-pi; do\n\t\t[ -d "$d" ] || continue\n'
		printf '\t\tfor p in %s; do\n' "$DEBIAN_APPLETS"
		printf '\t\t\tf=${d%%/lxpanel-pi}/lxpanel/plugins/$p.so\n\t\t\t[ -f "$f" ] && [ ! -e "$d/$p.so" ] && ln -s "$f" "$d/$p.so" || true\n'
		printf '\t\tdone\n\tdone\nfi\n'
		# Raspberry Pi's panel reads the application menu only when it starts:
		# restart running panels when packages add or remove applications.
		cat <<'EOF_TRIG'
if [ "$1" = triggered ] && command -v pgrep >/dev/null; then
	for pid in $(pgrep -x lxpanel-pi || true); do
		u=$(ps -o user= -p "$pid" | tr -d ' ')
		d=$( { tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null | sed -n 's/^DISPLAY=//p')
		x=$( { tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null | sed -n 's/^XAUTHORITY=//p')
		[ -n "$u" ] && [ -n "$d" ] || continue
		runuser -u "$u" -- env DISPLAY="$d" ${x:+XAUTHORITY=$x} lxpanelctl-pi restart >/dev/null 2>&1 || true
	done
fi
EOF_TRIG
	} >"$stage/DEBIAN/postinst"
	printf 'interest-noawait /usr/share/applications\n' >"$stage/DEBIAN/triggers"
	{
		printf '#!/bin/sh\nset -e\nif [ "$1" = remove ] || [ "$1" = purge ]; then\n'
		printf '\tfor l in /usr/lib/*/lxpanel-pi/*.so; do\n\t\tcase $(readlink "$l" || true) in /usr/lib/*/lxpanel/plugins/*) rm -f "$l" ;; esac\n\tdone\n'
		for f in "${icons[@]}"; do
			printf '\trm -f /usr/share/icons/%s/icon-theme.cache\n\trmdir /usr/share/icons/%s 2>/dev/null || true\n' "$f" "$f"
		done
		printf '\t:\nfi\n'
	} >"$stage/DEBIAN/postrm"
	chmod 0755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/postrm"
	build_deb "$stage" "$WORKDIR/${APP_PKG}_${ver}_all.deb"
	printf '%s\n' "$WORKDIR/${APP_PKG}_${ver}_all.deb"
}

# Build and install the generated package for the installed themes and the
# chosen look.
install_pkg() {
	local f
	step "Building the Raspberry Pi Desktop session ($APP_PKG)"
	[[ -d $WORKDIR/login || -d $SHARE/login ]] || ! (( O_LOGIN )) || _login_art
	session_vars
	f=$(build_pkg)
	as_root env DEBIAN_FRONTEND=noninteractive apt-get install "${APT_OPTS[@]}" "$f" >/dev/null
	ok "Installed $(basename "$f")"
}

# Reload the running Raspberry Pi Desktop session, so the new look appears at
# once: Openbox reads its settings again, and the panel and desktop restart.
# Open windows are not affected.
reload_session() {
	[[ ${DESKTOP_SESSION:-} == "$SESSION_ID" && -n ${DISPLAY:-} ]] || return 0
	local p
	pgrep -u "$(id -u)" -x openbox >/dev/null && openbox --reconfigure >/dev/null 2>&1 || true
	for p in lxpanel-pi lxpanel; do
		if pgrep -u "$(id -u)" -x "$p" >/dev/null; then "${p/lxpanel/lxpanelctl}" restart 2>/dev/null || true; fi
	done
	for p in pcmanfm-pi pcmanfm; do
		pgrep -u "$(id -u)" -x "$p" >/dev/null && "$p" --desktop-off 2>/dev/null || true
	done
	# with the session's own settings, not this script's environment, and
	# without its run lock
	setsid -f sh -c ". $SHARE/session-env; exec $SHARE/desktop" >/dev/null 2>&1 9<&- || true
	ok "The running session shows the new look; log out and back in for the theme of open applications"
}

###############################################################################
# 8. Desktops: the look for other desktops, per user
#
# The session needs nothing in the user's own files. Other desktops are given
# the look only on request (--desktop), for the user running the script:
# every file changed is backed up and every setting's old value recorded in
# the state directory, so that --uninstall restores them.
###############################################################################

# Print the state directory of this script, or of an earlier version.
_st() { printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/${1:-$APP_NAME}"; }

# Create the state directory, recording parent folders it creates.
_state_init() {
	A_STATE=$(_st)
	local new
	new=$(_missing_dirs "$(dirname "$A_STATE")")
	mkdir -p "$A_STATE/files"
	touch "$A_STATE/keys" "$A_STATE/created" "$A_STATE/created-dirs" "$A_STATE/restore.sh"
	if [[ -n $new ]]; then printf '%s\n' "$new" >>"$A_STATE/created-dirs"; fi
}

# Print the missing directories of a path below $HOME, deepest first.
_missing_dirs() {
	local d=$1
	while [[ ! -d $d && $d == "$HOME"/* ]]; do printf '%s\n' "${d#"$HOME"/}"; d=$(dirname "$d"); done
}

# Back up a file of the user's, or record it as new, before it is first
# changed. Files outside the home folder (the generated package) are not.
_track_file() {
	[[ -n ${A_STATE:-} && $1 == "$HOME"/* ]] || return 0
	local path=$1 rel=${1#"$HOME"/}
	grep -qxF "file:$rel" "$A_STATE/keys" && return 0
	if [[ -e $path || -L $path ]]; then
		mkdir -p "$(dirname "$A_STATE/files/$rel")"
		# A symlinked file is saved by its content: writing and restoring both
		# go through the link, so the file it points at keeps its own content
		cp -aL -- "$path" "$A_STATE/files/$rel" 2>/dev/null || cp -a -- "$path" "$A_STATE/files/$rel"
	else
		printf '%s\n' "$rel" >>"$A_STATE/created"
		_missing_dirs "$(dirname "$path")" >>"$A_STATE/created-dirs"
	fi
	printf 'file:%s\n' "$rel" >>"$A_STATE/keys"
}

# Succeed only the first time a one-time step runs for this user, so later
# runs keep the user's own changes to what it set up. Usage: _once STEP
_once() {
	grep -qxF "once:$1" "$A_STATE/keys" && return 1
	printf 'once:%s\n' "$1" >>"$A_STATE/keys"
}

# Record, once per setting, the command that restores its original value.
# Usage: _track_cmd KEY COMMAND
_track_cmd() {
	grep -qxF "$1" "$A_STATE/keys" && return 0
	printf '%s\n' "$2" >>"$A_STATE/restore.sh"
	printf '%s\n' "$1" >>"$A_STATE/keys"
}

# Print the desktops to give the look: the requested ones, or with "all",
# every supported desktop with an installed session.
desktop_list() {
	local tok f n
	case $O_DESKTOPS in
		none) return 0 ;;
		all)
			for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
				[[ -e $f ]] || continue
				n=$(sed -n 's/^DesktopNames=//p' "$f" | first_line | cut -d';' -f1)
				n=${n,,}; [[ -n $n ]] || n=$(basename "$f" .desktop)
				case $n in
					x-cinnamon) n=cinnamon ;; xfce*) n=xfce ;; plasma*) n=kde ;; budgie*) n=budgie ;; mate*) n=mate ;;
					gnome*|ubuntu*) n=gnome ;; lxqt*) n=lxqt ;; labwc*) n=labwc ;; openbox*) n=openbox ;;
				esac
				[[ " ${DE_OTHER[*]} " == *" $n "* ]] && echo "$n"
			done | awk '!seen[$0]++' ;;
		*)
			for tok in ${O_DESKTOPS//,/ }; do
				[[ " ${DE_OTHER[*]} " == *" $tok "* ]] || die "unsupported desktop '$tok' (use: ${DE_OTHER[*]}, all or none)"
				echo "$tok"
			done | awk '!seen[$0]++' ;;
	esac
}

# Give the requested desktops the look, for the user running the script.
apply_desktops() {
	local de
	local -a D_LIST
	mapfile -t D_LIST < <(desktop_list)
	(( ${#D_LIST[@]} )) || return 0
	step "Applying $T_DESC to ${D_LIST[*]} for $(id -un)"
	apply_gtk_files
	_block_set "$HOME/.config/gtk-4.0/gtk.css" "$APP_NAME" "$(gtk4_colors "$T_GTK" || true)"
	apply_mono_font
	for de in "${D_LIST[@]}"; do "apply_de_$de"; done
	(( O_QT )) && apply_qt_env
	RELOGIN=1
}

# Restore a user's settings and files from a state directory.
# Usage: restore_user [STATE-DIR]
restore_user() {
	local st=${1:-$(_st)} rel
	[[ -f $st/keys ]] || return 0
	if [[ -s $st/restore.sh ]]; then bash "$st/restore.sh" 2>/dev/null || warn "some settings could not be restored"; fi
	while IFS= read -r rel; do
		[[ $rel == file:* ]] || continue
		rel=${rel#file:}
		if grep -qxF "$rel" "$st/created" 2>/dev/null; then
			rm -f -- "${HOME:?}/$rel" || warn "could not remove $rel"
		elif [[ -e $st/files/$rel || -L $st/files/$rel ]]; then
			cp -a -- "$st/files/$rel" "$HOME/$rel" || warn "could not restore $rel"
		fi
	done <"$st/keys"
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

# Undo the edit pi-greeter's own install script made to Debian's
# /etc/lightdm/lightdm.conf (it lists the users), where undoing it gives back
# the file exactly as Debian ships it; a file changed otherwise is left alone.
lightdm_conf_repair() {
	local f=/etc/lightdm/lightdm.conf orig fixed
	[[ -f $f ]] && grep -qx 'greeter-hide-users=false' "$f" || return 0
	orig=$(dpkg-query -W -f='${Conffiles}\n' lightdm 2>/dev/null | awk -v f="$f" '$1 == f { print $2 }')
	fixed=$(sed 's/^greeter-hide-users=false$/#greeter-hide-users=false/' "$f")
	[[ -n $orig && $(md5sum <<<"$fixed" | cut -d' ' -f1) == "$orig" ]] || return 0
	sys_write "$f" <<<"$fixed"
	ok "Debian's $f is as Debian ships it again"
}

# Print the packages the earlier pixflat-theme installed. Its record can also
# name packages that were there before (it compared lists sorted differently),
# so only those APT's history shows it installing are taken, and those only
# Raspberry Pi can have provided.
old_installed() {
	local p hist
	hist=$(zcat -f /var/log/apt/history.log* 2>/dev/null | awk 'BEGIN { RS = "" }
		/\nCommandline:[^\n]*\/pixflat-theme\./ && match($0, /\nInstall: [^\n]*/) {
			n = split(substr($0, RSTART + 10, RLENGTH - 10), a, /\), /)
			for (i = 1; i <= n; i++) { sub(/[: ].*/, "", a[i]); print a[i] }
		}' | sort -u)
	while read -r p; do
		if grep -qxF "$p" <<<"$hist" || [[ -z $(apt-cache madison "$p" 2>/dev/null) ]]; then echo "$p"; fi
	done <"$OLD_SYS_DIR/installed-packages"
}

# Take over the records of raspios-look, as this script was named before:
# they are this script's own, so they move as they are. Done first, before
# the saved options are read.
adopt_prev_records() {
	[[ -d $PREV_SYS_DIR && ! -e $SYS_DIR ]] || return 0
	info "Administrator rights are needed (sudo) to take over the install of $PREV_NAME"
	prepare_root
	as_root mv -- "$PREV_SYS_DIR" "$SYS_DIR"
}

# Take over an install of raspios-look: remove its session package (this
# script's takes its place, with the same files), undo its settings for this
# user (they are written again under the new name) and move the users who
# chose its session to this one.
migrate_prev() {
	local st f u m v
	st=$(_st "$PREV_NAME")
	[[ -n $(installed_version "$PREV_PKG") || -d $st ]] || return 0
	step "Taking over the install of $PREV_NAME"
	if [[ -d $st ]]; then
		grep -q '^file:' "$st/keys" 2>/dev/null \
			&& note "The look $PREV_NAME gave other desktops (--desktop) was undone; give it back with: $(self_cmd) --desktop LIST"
		restore_user "$st"
	fi
	# The Openbox settings the session wrote, still as written
	f=${XDG_CONFIG_HOME:-$HOME/.config}/openbox
	for u in rpd-x LXDE-pi; do
		[[ -f $f/.$u-rc.xml.$PREV_NAME ]] && mv -- "$f/.$u-rc.xml.$PREV_NAME" "$f/.$u-rc.xml.$APP_NAME"
	done
	for f in $(sudo sh -c "grep -lE '^X?Session=$PREV_NAME(-wayland)?\$' /var/lib/AccountsService/users/*" 2>/dev/null); do
		u=$(id -u "${f##*/}" 2>/dev/null) || continue
		for m in XSession Session; do
			v=$(sudo sed -n "s/^$m=$PREV_NAME//p" "$f" | first_line)
			sudo grep -qE "^$m=$PREV_NAME(-wayland)?\$" "$f" && as_root busctl call org.freedesktop.Accounts \
				"/org/freedesktop/Accounts/User$u" org.freedesktop.Accounts.User "Set$m" s "$SESSION_ID$v" >/dev/null 2>&1
		done
	done
	for f in $(sudo grep -lE "^Session=$PREV_NAME(-wayland)?\$" /var/cache/lightdm/dmrc/*.dmrc 2>/dev/null); do
		sudo sed "s/^Session=$PREV_NAME/Session=$SESSION_ID/" "$f" | sys_write "$f"
	done
	if [[ -n $(installed_version "$PREV_PKG") ]]; then
		as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y -q "$PREV_PKG" >/dev/null
	fi
	ok "$PREV_NAME is now $APP_NAME: its records and session carried over"
}

# Take over an install of the earlier pixflat-theme: give Debian's own LXDE
# session back the settings it wrote there, remove its generated package, and
# keep its records of installed packages and the login screen file.
migrate_old() {
	local st f
	migrate_prev
	st=$(_st "$OLD_NAME")
	[[ -n $(installed_version "$OLD_PKG") || -d $OLD_SYS_DIR || -d $st ]] || return 0
	step "Taking over the install of $OLD_NAME 2"
	if [[ -d $st ]]; then restore_user "$st"; fi
	if [[ -n $(installed_version "$OLD_PKG") ]]; then
		as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y -q "$OLD_PKG" >/dev/null
		ok "Removed $OLD_PKG; $APP_PKG takes its place"
	fi
	if [[ -d $OLD_SYS_DIR ]]; then
		if [[ -f $OLD_SYS_DIR/installed-packages ]]; then
			old_installed | record_add "$SYS_DIR/installed-packages"
			# They are the earlier version's, not the user's own
			grep -vxF -f <(old_installed) "$SYS_DIR/packages-before" | sys_write "$SYS_DIR/packages-before"
		fi
		for f in pi-greeter.conf.orig pi-greeter.conf.new; do
			[[ -f $OLD_SYS_DIR/$f && ! -f $SYS_DIR/$f ]] && as_root cp -a -- "$OLD_SYS_DIR/$f" "$SYS_DIR/$f"
		done
		as_root rm -rf -- "$OLD_SYS_DIR"
	fi
	lightdm_conf_repair
	ok "$OLD_NAME's records carried over; Debian's LXDE session has its own settings again"
}

# Openbox reads the hover image of a toggled title bar button as
# "<button>_toggled_hover.xbm", while the official themes name it
# "<button>_hover_toggled.xbm", so the middle button of a maximised window
# keeps its small image on hover while the others grow. Give the theme the
# names Openbox reads, in the user's theme directory, which it looks in first.
# Every file is a link to the official one, so theme updates still apply.
# Usage: _openbox_buttons THEME
_openbox_buttons() {
	local src=/usr/share/themes/$1/openbox-3 dir=$HOME/.themes/$1/openbox-3 f n
	[[ -f $src/themerc ]] && compgen -G "$src/*_hover_toggled*.xbm" >/dev/null || return 0
	for f in "$src"/*; do
		[[ -f $f ]] || continue
		n=${f##*/}
		_track_file "$dir/$n"   # before the directory exists, so --uninstall removes it too
		mkdir -p "$dir"
		ln -sfn "$f" "$dir/$n"
		if [[ $n == *_hover_toggled* ]]; then
			n=${n/_hover_toggled/_toggled_hover}
			_track_file "$dir/$n"
			ln -sfn "$f" "$dir/$n"
		fi
	done
}
# Apply the Raspberry Pi OS labwc look (rpd-wayland-core rc.xml): the <theme>
# section, window snapping and the window switcher.
_labwc_rc() {
	local file=$1 fonts
	_track_file "$file"
	fonts=$(_xml_fonts ActiveWindow InactiveWindow OnScreenDisplay MenuItem)
	_xml_block "$file" theme "$(printf '  <theme>\n    <name>%s</name>\n    <cornerRadius>0</cornerRadius>\n    <keepBorder>yes</keepBorder>\n%s\n    <dropShadows>yes</dropShadows>\n    <titlebar>\n      <layout>:iconify,max,close</layout>\n    </titlebar>\n  </theme>' "$T_GTK" "$fonts")"
	# Window snapping and the window switcher, as in Raspberry Pi OS
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

# Succeed if a GSettings key exists.
_gs_ok() { gsettings writable "$1" "$2" >/dev/null 2>&1; }
# Set a GSettings key, recording its old value. Usage: gs_set SCHEMA KEY VALUE
gs_set() {
	command -v gsettings >/dev/null || return 0
	_gs_ok "$1" "$2" || { debug "gsettings: no $1 $2"; return 0; }
	local old
	old=$(gsettings get "$1" "$2" 2>/dev/null) || return 0
	_track_cmd "gs:$1:$2" "$(_q gsettings set "$1" "$2" "$old")"
	gsettings set "$1" "$2" "$3" || warn "could not set $1 $2"
}
# Set a GSettings string key. Usage: gs_str SCHEMA KEY STRING
gs_str() { gs_set "$1" "$2" "'${3//\'/\\\'}'"; }

# Set an Xfconf property, recording its old value.
# Usage: xf_set CHANNEL PROPERTY TYPE VALUE
xf_set() {
	local old
	if old=$(xfconf-query -c "$1" -p "$2" 2>/dev/null); then
		_track_cmd "xf:$1:$2" "$(_q xfconf-query -c "$1" -p "$2" -s "$old")"
		xfconf-query -c "$1" -p "$2" -s "$4" || warn "could not set $1 $2"
	else
		_track_cmd "xf:$1:$2" "$(_q xfconf-query -c "$1" -p "$2" -r)"
		xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4" || warn "could not set $1 $2"
	fi
}

# Set a KDE configuration key, recording its old value.
# Usage: kde_set FILE GROUP KEY VALUE
kde_set() {
	local w r old
	w=$(command -v kwriteconfig6 || command -v kwriteconfig5 || true)
	r=$(command -v kreadconfig6 || command -v kreadconfig5 || true)
	[[ -n $w && -n $r ]] || { warn "kwriteconfig not found; skipping KDE $3"; return 0; }
	old=$("$r" --file "$1" --group "$2" --key "$3" 2>/dev/null || true)
	if [[ -n $old ]]; then
		_track_cmd "kde:$1:$2:$3" "$(_q "$w" --file "$1" --group "$2" --key "$3" "$old")"
	else
		_track_cmd "kde:$1:$2:$3" "$(_q "$w" --file "$1" --group "$2" --key "$3" --delete)"
	fi
	"$w" --file "$1" --group "$2" --key "$3" "$4"
}

# Succeed if the user runs a process of that name.
_running() { pgrep -u "$(id -u)" -x "$1" >/dev/null 2>&1; }

# Set the theme, icons, cursor and fonts in a GNOME-style interface schema.
_gs_interface() {
	local s=$1
	gs_str "$s" gtk-theme "$T_GTK"
	gs_str "$s" icon-theme "$T_ICONS"
	gs_str "$s" cursor-theme "$T_ICONS"
	gs_set "$s" cursor-size "$T_CURSOR_SIZE"
	gs_str "$s" font-antialiasing rgba
	gs_str "$s" font-hinting full
	gs_str "$s" font-rgba-order rgb
	gs_str "$s" font-name "$T_FONT"
	gs_str "$s" document-font-name "$T_FONT"
}

# Write the GTK 2, 3 and 4 settings files and the default X11 cursor, with the
# Raspberry Pi OS toolbar, icon size and font rendering settings.
apply_gtk_files() {
	local f=$HOME/.config/gtk-3.0/settings.ini
	_ini_set "$f" Settings gtk-theme-name "$T_GTK" gtk-icon-theme-name "$T_ICONS" \
		gtk-cursor-theme-name "$T_ICONS" gtk-cursor-theme-size "$T_CURSOR_SIZE" gtk-font-name "$T_FONT"
	_ini_set "$f" Settings gtk-sound-theme-name "$T_SOUND_THEME" gtk-enable-event-sounds 1 gtk-enable-input-feedback-sounds 1
	_ini_set "$f" Settings gtk-toolbar-style GTK_TOOLBAR_BOTH_HORIZ gtk-toolbar-icon-size GTK_ICON_SIZE_LARGE_TOOLBAR \
		gtk-icon-sizes gtk-large-toolbar=24,24 gtk-button-images 0 gtk-menu-images 0 \
		gtk-xft-antialias 1 gtk-xft-hinting 1 gtk-xft-hintstyle hintfull gtk-xft-rgba rgb
	f=$HOME/.config/gtk-4.0/settings.ini
	_ini_set "$f" Settings gtk-icon-theme-name "$T_ICONS" gtk-cursor-theme-name "$T_ICONS" \
		gtk-cursor-theme-size "$T_CURSOR_SIZE" \
		gtk-xft-antialias 1 gtk-xft-hinting 1 gtk-xft-hintstyle hintfull gtk-xft-rgba rgb gtk-font-name "$T_FONT"
	f=$HOME/.gtkrc-2.0
	_kv_set "$f" gtk-theme-name "$T_GTK" '"'
	_kv_set "$f" gtk-icon-theme-name "$T_ICONS" '"'
	_kv_set "$f" gtk-cursor-theme-name "$T_ICONS" '"'
	_kv_set "$f" gtk-cursor-theme-size "$T_CURSOR_SIZE"
	_kv_set "$f" gtk-font-name "$T_FONT" '"'
	_kv_set "$f" gtk-toolbar-style GTK_TOOLBAR_BOTH_HORIZ
	_kv_set "$f" gtk-toolbar-icon-size GTK_ICON_SIZE_LARGE_TOOLBAR
	_kv_set "$f" gtk-icon-sizes "gtk-large-toolbar=24,24" '"'
	_kv_set "$f" gtk-button-images 0
	_kv_set "$f" gtk-menu-images 0
	_kv_set "$f" gtk-xft-antialias 1
	_kv_set "$f" gtk-xft-hinting 1
	_kv_set "$f" gtk-xft-hintstyle hintfull '"'
	_kv_set "$f" gtk-xft-rgba rgb '"'
	# Default X11 cursor for applications that do not use XSETTINGS
	_ini_set "$HOME/.icons/default/index.theme" "Icon Theme" Inherits "$T_ICONS"
	ok "GTK 2/3/4 configuration files updated"
}


# Map Monospace to Liberation Mono, as Raspberry Pi OS does.
apply_mono_font() {
	grep -qiF "Liberation Mono" <<<"$(fc-list : family 2>/dev/null)" || return 0
	local f=$HOME/.config/fontconfig/conf.d/31-$APP_NAME-mono.conf
	_track_file "$f"
	cat <<'EOF_FC' | _write "$f"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- pixflat-theme: Monospace is Liberation Mono, as in Raspberry Pi OS -->
<fontconfig>
	<match target="pattern">
		<test name="family"><string>Monospace</string></test>
		<edit name="family" mode="assign" binding="same"><string>Liberation Mono</string></edit>
	</match>
</fontconfig>
EOF_FC
}

# LXQt: icons, cursor, Openbox and PCManFM-Qt wallpaper.
apply_de_lxqt() {
	_ini_set "$HOME/.config/lxqt/lxqt.conf" General icon_theme "$T_ICONS"
	_ini_set "$HOME/.config/lxqt/session.conf" Mouse cursor_theme "$T_ICONS" cursor_size "$T_CURSOR_SIZE"
	local rc=$HOME/.config/openbox/lxqt-rc.xml
	if _seed "$rc" /etc/xdg/openbox/lxqt-rc.xml /usr/share/lxqt/openbox/rc.xml; then
		_openbox_buttons "$T_GTK"
		_openbox_rc "$rc" 1
		if [[ -n ${DISPLAY:-} ]] && _running openbox; then openbox --reconfigure >/dev/null 2>&1 || true; fi
	fi
	if [[ -n $S_WALL ]]; then
		_ini_set "$HOME/.config/pcmanfm-qt/lxqt/settings.conf" Desktop Wallpaper "$S_WALL" WallpaperMode zoom
		if _running pcmanfm-qt; then pcmanfm-qt --set-wallpaper "$S_WALL" --wallpaper-mode zoom || true; fi
	fi
	ok "LXQt configured (icons, cursor, Openbox, wallpaper; GTK applications use the GTK theme)"
	NOTES+=("LXQt: Qt widgets keep the LXQt style; log out and back in to refresh the cursor.")
}

# Xfce: xsettings, Xfwm4, wallpaper, panel and panel CSS.
apply_de_xfce() {
	command -v xfconf-query >/dev/null || { warn "xfconf-query not found; skipping Xfce"; return 0; }
	xfconf-query -c xsettings -l >/dev/null 2>&1 || { warn "cannot reach the Xfce settings daemon; skipping Xfce (rerun with --apply-only inside Xfce)"; return 0; }
	xf_set xsettings /Net/ThemeName string "$T_GTK"
	xf_set xsettings /Net/IconThemeName string "$T_ICONS"
	xf_set xsettings /Gtk/CursorThemeName string "$T_ICONS"
	xf_set xsettings /Gtk/CursorThemeSize int "$T_CURSOR_SIZE"
	xf_set xsettings /Gtk/ToolbarStyle string both-horiz
	xf_set xsettings /Gtk/IconSizes string gtk-large-toolbar=24,24
	xf_set xsettings /Gtk/ButtonImages bool false
	xf_set xsettings /Gtk/MenuImages bool false
	xf_set xsettings /Xft/Antialias int 1
	xf_set xsettings /Xft/Hinting int 1
	xf_set xsettings /Xft/HintStyle string hintfull
	xf_set xsettings /Xft/RGBA string rgb
	xf_set xsettings /Gtk/FontName string "$T_FONT"
	xf_set xsettings /Net/SoundThemeName string "$T_SOUND_THEME"
	xf_set xsettings /Net/EnableEventSounds bool true
	xf_set xsettings /Net/EnableInputFeedbackSounds bool true
	if [[ -f /usr/share/themes/$T_GTK/xfwm4/themerc ]]; then
		xf_set xfwm4 /general/theme string "$T_GTK"
	else
		warn "no Xfwm4 theme for $T_GTK found; window borders unchanged"
	fi
	xf_set xfwm4 /general/title_font string "$T_FONT"
	xf_set xfwm4 /general/title_alignment string center
	xf_set xfwm4 /general/button_layout string "|HMC"   # Raspberry Pi OS: no window-menu button
	if [[ -n $S_WALL ]]; then
		local props p n=0
		props=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '^/backdrop/.*/last-image$' || true)
		for p in $props; do
			xf_set xfce4-desktop "$p" string "$S_WALL"
			xf_set xfce4-desktop "${p%/last-image}/image-style" int 5
			n=$(( n + 1 ))
		done
		(( n )) || warn "no Xfce desktop backdrop found; open Desktop settings once and rerun to set the wallpaper"
	fi
	local css='/* Full-colour icons on the Xfce panel, like the Raspberry Pi OS panel */
.xfce4-panel image { -gtk-icon-style: regular; }'
	if (( ! T_DARK )); then
		css+='
/* PiXflat-style desktop icon labels */
XfdesktopIconView.view .label, .xfdesktop-icon-view.view .label { background: #ededed; color: black; text-shadow: none; }
XfdesktopIconView.view .label:active, .xfdesktop-icon-view.view .label:active { background: #87919b; color: white; }'
	fi
	_block_set "$HOME/.config/gtk-3.0/gtk.css" "$APP_NAME" "$css"
	if xfconf-query -c xfce4-panel -p /panels/panel-1/size >/dev/null 2>&1 && _once xfce-panel; then
		xf_set xfce4-panel /panels/panel-1/position string "p=6;x=0;y=0"   # top, like Raspberry Pi OS
		xf_set xfce4-panel /panels/panel-1/size uint 36
		local plug id
		while read -r plug id; do
			case $id in applicationsmenu|whiskermenu)
				[[ -n $S_LOGO ]] && xf_set xfce4-panel "$plug/button-icon" string "$S_LOGO" ;;
			esac
		done < <(xfconf-query -c xfce4-panel -p /plugins -l -v 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+ ' || true)
	fi
	ok "Xfce configured"
	NOTES+=("Xfce: restart the panel (xfce4-panel -r) or log in again to pick up the panel CSS.")
}

# GNOME and Budgie: interface, fonts, window buttons, sounds and wallpaper.
# Usage: apply_de_gnome [NAME-IN-MESSAGES]
apply_de_gnome() {
	local de=${1:-GNOME}
	_gs_interface org.gnome.desktop.interface
	if (( T_DARK )); then gs_str org.gnome.desktop.interface color-scheme prefer-dark
	else gs_str org.gnome.desktop.interface color-scheme default; fi
	gs_str org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"
	gs_str org.gnome.desktop.sound theme-name "$T_SOUND_THEME"
	gs_set org.gnome.desktop.sound event-sounds true
	gs_set org.gnome.desktop.sound input-feedback-sounds true
	gs_str org.gnome.desktop.wm.preferences titlebar-font "$T_FONT"
	if [[ -n $S_WALL ]]; then
		gs_str org.gnome.desktop.background picture-uri "file://$S_WALL"
		gs_str org.gnome.desktop.background picture-uri-dark "file://$S_WALL"
		gs_str org.gnome.desktop.background picture-options zoom
		gs_str org.gnome.desktop.screensaver picture-uri "file://$S_WALL"
	fi
	ok "$de settings applied"
	NOTES+=("$de: GTK 3 applications and window titlebars use $T_GTK; the shell and GTK 4/libadwaita applications keep the Adwaita style.")
}

# Budgie uses the GNOME settings.
apply_de_budgie() {
	apply_de_gnome Budgie
	NOTES+=("Budgie: the panel keeps its own theme.")
}

# Cinnamon: interface, window buttons and wallpaper.
apply_de_cinnamon() {
	_gs_interface org.cinnamon.desktop.interface
	gs_str org.cinnamon.desktop.wm.preferences button-layout ":minimize,maximize,close"
	gs_str org.cinnamon.desktop.wm.preferences titlebar-font "$T_FONT"
	gs_str org.cinnamon.desktop.sound theme-name "$T_SOUND_THEME"
	gs_set org.cinnamon.desktop.sound event-sounds true
	if [[ -n $S_WALL ]]; then
		gs_str org.cinnamon.desktop.background picture-uri "file://$S_WALL"
		gs_str org.cinnamon.desktop.background picture-options zoom
	fi
	ok "Cinnamon settings applied"
	NOTES+=("Cinnamon: the panel/desktop theme and window borders keep the Cinnamon style.")
}

# MATE: interface, cursor and wallpaper.
apply_de_mate() {
	gs_str org.mate.interface gtk-theme "$T_GTK"
	gs_str org.mate.interface icon-theme "$T_ICONS"
	gs_str org.mate.interface font-name "$T_FONT"
	gs_str org.mate.Marco.general titlebar-font "$T_FONT"
	gs_str org.mate.sound theme-name "$T_SOUND_THEME"
	gs_set org.mate.sound event-sounds true
	gs_set org.mate.sound input-feedback-sounds true
	gs_str org.mate.font-rendering antialiasing rgba
	gs_str org.mate.font-rendering hinting full
	gs_str org.mate.font-rendering rgba-order rgb
	gs_str org.mate.peripherals-mouse cursor-theme "$T_ICONS"
	gs_set org.mate.peripherals-mouse cursor-size "$T_CURSOR_SIZE"
	if [[ -n $S_WALL ]]; then
		gs_str org.mate.background picture-filename "$S_WALL"
		gs_str org.mate.background picture-options zoom
	fi
	ok "MATE settings applied"
	NOTES+=("MATE: Marco window borders keep their theme (Raspberry Pi OS ships no Metacity theme).")
}

# Openbox on its own: window theme and fonts.
apply_de_openbox() {
	local rc=$HOME/.config/openbox/rc.xml
	if _seed "$rc" /etc/xdg/openbox/rc.xml; then
		_openbox_buttons "$T_GTK"
		_openbox_rc "$rc"
		if [[ -n ${DISPLAY:-} ]] && _running openbox; then openbox --reconfigure >/dev/null 2>&1 || true; fi
		ok "Openbox configured"
	else
		warn "no Openbox rc.xml found; skipping Openbox"
	fi
}

# labwc: window theme, fonts, cursor and the GTK settings used on Wayland.
apply_de_labwc() {
	local rc=$HOME/.config/labwc/rc.xml
	if [[ ! -e $rc ]]; then
		_track_file "$rc"
		printf '<?xml version="1.0"?>\n<labwc_config>\n</labwc_config>\n' | _write "$rc"
	fi
	_openbox_buttons "$T_GTK"
	_labwc_rc "$rc"
	_kv_set "$HOME/.config/labwc/environment" XCURSOR_THEME "$T_ICONS"
	_kv_set "$HOME/.config/labwc/environment" XCURSOR_SIZE "$T_CURSOR_SIZE"
	_gs_interface org.gnome.desktop.interface   # GTK reads these on Wayland
	if [[ -n ${LABWC_PID:-} ]]; then labwc --reconfigure || true; fi
	ok "labwc configured"
	NOTES+=("labwc: set the wallpaper in your background tool (e.g. swaybg -m fill -i ${S_WALL:-<file>}).")
}

# KDE Plasma: icons and cursor.
apply_de_kde() {
	kde_set kdeglobals Icons Theme "$T_ICONS"
	kde_set kcminputrc Mouse cursorTheme "$T_ICONS"
	kde_set kcminputrc Mouse cursorSize "$T_CURSOR_SIZE"
	ok "KDE Plasma: icons and cursor set"
	NOTES+=("KDE Plasma: only icons, cursor and GTK applications are themed; Plasma and Qt keep Breeze.")
}

# --qt: let Qt applications use the GTK theme after the next login.
apply_qt_env() {
	if [[ " ${D_LIST[*]} " == *" lxqt "* || " ${D_LIST[*]} " == *" kde "* ]]; then
		warn "--qt skipped: LXQt and KDE manage the Qt platform theme themselves"
		return 0
	fi
	_kv_set "$HOME/.config/environment.d/90-$APP_NAME.conf" QT_QPA_PLATFORMTHEME gtk3
	_block_set "$HOME/.xsessionrc" "$APP_NAME" "export QT_QPA_PLATFORMTHEME=gtk3"
	ok "Qt applications will follow the GTK theme after the next login"
}


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

# Write VERSIONS.md: the build date and the version, releases and origin of
# every package in the repository.
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
				o = index(ENVIRON["RPI"], " " p " ") ? "Raspberry Pi OS" : "Debian"
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

# Write "name version" for every package of a Packages index, and "name" or
# "name version" for every virtual package it provides.
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

# Print, sorted, what every Debian desktop installation of an edition (lxde,
# xfce, gnome, kde, cinnamon, mate, lxqt) has: the base system and what the
# desktop task depends on, also when installed without recommended packages.
# Usage: _desktop_base INDEX EDITION
_desktop_base() {
	BASE=priority _closure "$1" task-desktop "task-$2-desktop" | LC_ALL=C sort -u
}

# Print the Debian packages that the given Debian packages and .deb files need
# and a baseline lacks. Names the baseline has, or provides, satisfy any
# alternative. Usage: _bundle_closure INDEX BASELINE [PACKAGE]... -- [DEB]...
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
		}' "$base" "$idx" | cat - "$base" | sort -u >"$have"
	if (( $# )); then mapfile -t roots < <(_deb_depnames "$@"); fi
	HAVE=$have _closure "$idx" "${pkgs[@]}" "${roots[@]}" | grep -vxF -f "$base" || true
}


# Print the release/architecture pairs --download builds: those given with
# --bundle, else every one Raspberry Pi publishes the themes for, from Debian
# $OFFLINE_OLDEST on.
bundle_pairs() {
	local s a p
	for s in $(releases); do
		(( $(suite_rank "$s") >= OFFLINE_OLDEST )) || continue
		for a in $(rpi_arches "$s"); do
			p=$s/$a
			[[ -z $O_BUNDLE || ,$O_BUNDLE, == *",$p,"* ]] && rpi_populated "$s" "$a" && echo "$p"
		done
	done
}

# --download: build packages/, for every release and architecture (or those
# given with --bundle), with the Raspberry Pi OS packages and the Debian
# packages they and the session need that every Debian desktop installation
# lacks. Each .deb is filed in a folder of its kind (pool/themes, pool/icons,
# ...). Unchanged files are reused, and the result replaces packages/ only
# when complete.
download_mode() {
	local dest=$REPO stage pair suite arch p f idx deb line s v a sha z d e n=0
	local -a pairs rpis debs got
	declare -gA RPI_NAMES=()   # the Raspberry Pi OS packages, for VERSIONS.md
	preflight_tools
	[[ -r $DEBIAN_KEYRING ]] || die "$DEBIAN_KEYRING is missing (install debian-archive-keyring)"
	mapfile -t pairs < <(bundle_pairs)
	(( ${#pairs[@]} )) || die "Raspberry Pi publishes nothing for ${O_BUNDLE:-any release}; releases: $(releases | xargs)"
	step "Building packages/ from the official archives"
	log "  Raspberry Pi OS  $RPI_ARCHIVE"
	log "  Debian           $DEBIAN_ARCHIVE, $DEBIAN_OLD_ARCHIVE"
	log "  For              ${pairs[*]}"
	log "  Destination      $dest"
	ask "Proceed" y || die "aborted"
	setup_keyring
	stage=$(mktemp -d "$(dirname -- "$dest")/.packages.XXXXXX")
	BUILD_STAGE=$stage   # cleanup() removes it if the build fails
	mkdir -p "$stage/pool"
	for pair in "${pairs[@]}"; do
		suite=${pair%/*} arch=${pair#*/}
		step "Packages for $suite / $arch ($(( n + 1 )) of ${#pairs[@]})"
		H_SUITE=$suite H_ARCH=$arch H_RPI_ARCH=$arch
		PKG_VER=() PKG_FILE=() PKG_SHA=() PKG_SIZE=() PKG_SUITE=() PKG_AID=() IN_SET=() AVAIL=()
		index_load debian "$suite" "$arch" || die "cannot load the Debian $suite/$arch index"
		deb=$WORKDIR/index/debian/$suite/Packages-$arch
		DEP_INDEX=$deb.names
		_index_names "$deb" >"$DEP_INDEX"
		mapfile -t rpis < <({ rpi_pkgs "$suite" "$arch" 0; rpi_pkgs "$suite" "$arch" 1; } | awk '!seen[$0]++')
		mapfile -t rpis < <(with_rpi_deps "$suite" "$arch" "${rpis[@]}")
		mapfile -t debs < <({ x11_debs; session_debs; theme_debs "$suite"; tray_debs "$suite" 1; login_debs 1; echo accountsservice
			if suite_ge "$suite" trixie; then wayland_debs; fi; } | awk '!seen[$0]++')
		for p in "${rpis[@]}" "${debs[@]}"; do IN_SET[$p]=1; done
		idx=$stage/dists/$suite/main/binary-$arch
		mkdir -p "$idx"
		: >"$idx/Packages"
		got=()
		for p in "${rpis[@]}"; do
			if ! resolve_pkg "$p" rpi; then warn "$p is not available for $suite/$arch; left out"; continue; fi
			f=$(download_pkg "$p")
			f=$(deps_drop "$f")
			f=$(compat_fix "$f")
			f=$(fm_coinstall "$f")
			f=$(rpcc_session "$f")
			f=$(scripts_coinstall "$f") || continue
			got+=("$f")
			_stage_pkg "$stage" "$idx" "$p" "$f"
			RPI_NAMES[$p]=1
			ok "$p ${PKG_VER[$p]} (Raspberry Pi OS ${PKG_SUITE[$p]})"
		done
		# The configuration packages: never installed, so their dependencies
		# are not bundled
		for p in "$ART_PKG $(config_suite)" "$PANEL_PKG $(config_suite)" "$WAYLAND_PKG $(config_suite)" "$(menu_pkg)"; do
			s=${p#* } p=${p%% *}
			[[ -z ${PKG_VER[$p]:-} ]] || continue
			line=$(index_candidates rpi "$s" "$arch" "$p" | first_line)
			[[ -n $line ]] || continue
			IFS=$'\t' read -r v a f sha z d <<<"$line"
			PKG_VER[$p]=$v PKG_FILE[$p]=$f PKG_SHA[$p]=$sha PKG_SIZE[$p]=${z:-0} PKG_SUITE[$p]=$s PKG_AID[$p]=rpi
			_stage_pkg "$stage" "$idx" "$p" "$(download_pkg "$p")"
			RPI_NAMES[$p]=1
			ok "$p $v (Raspberry Pi OS $s; settings and artwork, never installed)"
		done
		# Debian packages: the dependency closure of everything bundled, minus
		# what every Debian desktop installation already has (the base system
		# and each desktop task with its recommended packages, as the Debian
		# installer sets them up)
		_desktop_base "$deb" lxde >"$deb.base"
		for e in xfce gnome kde cinnamon mate lxqt; do
			_desktop_base "$deb" "$e" | LC_ALL=C comm -12 "$deb.base" - >"$deb.tmp"
			mv -- "$deb.tmp" "$deb.base"
		done
		# The packages the script asks for are always there: a minimal
		# installation may lack what a desktop task brings
		# (Debian's panel and file manager stay beside Raspberry Pi's builds of
		# them, for --no-pi-apps)
		mapfile -t debs < <({ printf '%s\n' "${debs[@]}"; _bundle_closure "$deb" "$deb.base" "${debs[@]}" -- "${got[@]}"; } \
			| LC_ALL=C sort -u | while read -r p; do
				[[ " ${rpis[*]} " != *" $p "* || ( $p =~ ^(lxpanel|pcmanfm|libfm) && $p != *-pi ) ]] && echo "$p"
			done)
		for p in "${debs[@]}"; do
			# a package a release does not have (PipeWire before Debian 11)
			if ! resolve_pkg "$p" debian; then warn "$p is not available in Debian $suite/$arch; left out"; continue; fi
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
	# keep the folder's .gitignore
	[[ -f $dest/.gitignore ]] && cp -- "$dest/.gitignore" "$stage/.gitignore"
	if [[ -e $dest ]]; then rm -rf -- "$dest.old"; mv -- "$dest" "$dest.old"; fi
	mv -- "$stage" "$dest"
	BUILD_STAGE=""
	rm -rf -- "$dest.old"
	ok "packages/ is ready: $(du -sh -- "$dest" | cut -f1), $(find "$dest/pool" -name '*.deb' | wc -l) packages, $n indexes"
	info "Copy $(self_cmd | cut -d' ' -f2) and packages/ to the offline computer and run: $(self_cmd) --offline"
}

###############################################################################
# 10. Refresh: --refresh, --prepare-upgrade
###############################################################################

# Print what a run is resolved against; later runs and --refresh compare it.
state_lines() {
	printf 'debian %s\nrelease %s\narch %s\nversion %s\n' "${H_CODENAME:-?}" "$H_SUITE" "$H_ARCH" "$APP_VERSION"
}

# Save the state that later runs and --refresh compare against.
save_state() { state_lines | cmp -s - "$SYS_DIR/state" 2>/dev/null || state_lines | sys_write "$SYS_DIR/state"; }

# --refresh: list what an update would change, then ask. Exits when there is
# nothing to do or the answer is no; returns to apply the update. Before the
# answer it changes nothing.
refresh_check() {
	local p st n=0 line key
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
	while IFS='=' read -r key line; do
		[[ -n ${GIVEN[$key]:-} ]] || continue
		grep -qxF "$key=$line" "$SYS_DIR/options" 2>/dev/null && continue
		log "  + Option changed: $key=$line"
		n=$(( n + 1 ))
	done < <(option_lines)
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

# Before a Debian release upgrade: remove the Raspberry Pi OS packages with
# compiled code this script installed, which are built for this release and
# could hold the upgrade back. The session keeps working with Debian's panel,
# file manager and login screen until the script runs again after the upgrade.
prepare_upgrade() {
	local p
	local -a remove=()
	[[ -f $SYS_DIR/installed-packages ]] || die "the Raspberry Pi OS look is not installed"
	for p in $(release_bound_pkgs); do
		[[ -n $(installed_version "$p") ]] && grep -qxF "$p" "$SYS_DIR/installed-packages" && remove+=("$p")
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
	if (( ${#remove[@]} )); then
		step "Removing the packages built for Debian $H_CODENAME"
		mapfile -t remove < <(_safe_purge_set "${remove[@]}" || true)
		(( ${#remove[@]} )) || die "APT would remove other packages with them; nothing was changed"
		printf '%s\n' "${remove[@]}" | record_add "$SYS_DIR/removed-for-upgrade"
		as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${remove[@]}"
	fi
	restore_debian_stack
	set_theme "$(chosen_theme)"
	install_pkg
	ok "Ready. Upgrade Debian and reboot, then run: $(self_cmd)"
}

# Succeed if Raspberry Pi's build of Debian's panel is installed (PI_STACK).
_stack_installed() { [[ $(installed_version lxpanel) == *+rpt* ]]; }

# Put Debian's own builds of the panel and file manager back where Raspberry
# Pi's replaced them (see PI_STACK), from the APT sources. Raspberry Pi's
# panel plugins, which need its panel, are removed first.
restore_debian_stack() {
	local p v src
	local -a args=() kept=() plugins=()
	while read -r p v src; do
		[[ $v == *+rpt* && ${src:-$p} =~ ^($PI_STACK_SRC)$ ]] || continue
		v=$(LC_ALL=C apt-cache madison "$p" 2>/dev/null | awk -F' *[|] *' 'NR == 1 { print $2 }')
		if [[ -n $v ]]; then args+=("$p=$v"); else kept+=("$p"); fi
	done < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version} ${source:Package}\n' 2>/dev/null | awk '$1 ~ /^.i/ { $1 = ""; print }')
	(( ${#args[@]} )) || return 0
	step "Putting Debian's panel and file manager back"
	mapfile -t plugins < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'lxplug-*' 2>/dev/null | awk '$1 ~ /^.i/ { print $2 }')
	if (( ${#plugins[@]} )); then as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y -q "${plugins[@]}" >/dev/null || true; fi
	if as_root env DEBIAN_FRONTEND=noninteractive apt-get install "${APT_OPTS[@]}" --allow-downgrades "${args[@]}"; then
		ok "Debian's ${args[*]%%=*} are installed again"
	else
		warn "APT could not put Debian's panel and file manager back; install them with: sudo apt install --allow-downgrades ${args[*]}"
	fi
	(( ${#kept[@]} == 0 )) || warn "your APT sources have no Debian version of ${kept[*]}; Raspberry Pi's build stays"
}

# Print the part of a package set that APT can purge without removing any
# other package. Members that other installed software depends on are left
# out; APT's own simulation decides.
_safe_purge_set() {
	local -a set=("$@") extra=() keep=()
	local sim e
	while (( ${#set[@]} )); do
		sim=$(LC_ALL=C apt-get -s purge "${set[@]}" 2>/dev/null) || return 1
		mapfile -t extra < <(awk '/^(Purg|Remv) / { sub(/:.*/, "", $2); print $2 }' <<<"$sim" \
			| grep -vxF -f <(printf '%s\n' "${set[@]}") || true)
		if (( ${#extra[@]} == 0 )); then printf '%s\n' "${set[@]}"; return 0; fi
		# Keep the members those packages depend on, then try again
		mapfile -t keep < <(for e in "${extra[@]}"; do dpkg-query -W -f='${Pre-Depends}, ${Depends}\n' "$e" 2>/dev/null; done \
			| depnames | grep -xF -f <(printf '%s\n' "${set[@]}") || true)
		(( ${#keep[@]} )) || return 1   # the dependency is indirect; remove nothing
		mapfile -t set < <(printf '%s\n' "${set[@]}" | grep -vxF -f <(printf '%s\n' "${keep[@]}") || true)
	done
}

###############################################################################
# 11. Uninstall: --uninstall
###############################################################################

# Undo what the script did: for everyone, the session and the login screen,
# the generated package and the packages it installed; for the user running
# it, the settings it changed. Packages that were installed before, or that
# other software has come to need, stay.
uninstall() {
	local p f u m rc seen
	local -a pkgs=() remove=() keep=()
	if [[ -f $SYS_DIR/installed-packages ]]; then mapfile -t pkgs <"$SYS_DIR/installed-packages"; fi
	for p in "${pkgs[@]}"; do
		[[ -n $(installed_version "$p") ]] || continue
		grep -qxF "$p" "$SYS_DIR/packages-before" 2>/dev/null && continue
		keep+=("$p")
	done
	pkgs=("${keep[@]}") keep=()
	step "What the uninstall removes"
	log "  For everyone: the Raspberry Pi Desktop session, the login screen style and $APP_PKG"
	(( ${#pkgs[@]} )) && log "  Packages this script installed: ${pkgs[*]}"
	_stack_installed && log "  Raspberry Pi's panel and file manager: Debian's are installed again in their place"
	log "  For $(id -un): the settings it changed and your Raspberry Pi Desktop settings; other users keep theirs."
	log "  Packages you had before or installed later stay."
	ask "Continue" n || die "aborted"
	prepare_root
	take_run_lock
	require_dpkg_ready

	step "Restoring the login screen and the users' session choice"
	# Users who chose the session log in to the login screen's default again
	for f in $(sudo sh -c "grep -lE '^X?Session=($SESSION_ID|$PREV_NAME)(-wayland)?\$' /var/lib/AccountsService/users/*" 2>/dev/null); do
		u=$(id -u "${f##*/}" 2>/dev/null) || continue
		for m in XSession Session; do
			sudo grep -qE "^$m=($SESSION_ID|$PREV_NAME)(-wayland)?\$" "$f" && as_root busctl call org.freedesktop.Accounts \
				"/org/freedesktop/Accounts/User$u" org.freedesktop.Accounts.User "Set$m" s "" >/dev/null 2>&1
		done
		ok "${f##*/} logs in to the login screen's default session again"
	done
	# LightDM's copies of the users' session choice, without AccountsService
	for f in $(sudo grep -lE "^Session=($SESSION_ID|$PREV_NAME)(-wayland)?\$" /var/cache/lightdm/dmrc/*.dmrc 2>/dev/null); do
		as_root rm -f -- "$f"
		ok "$(basename "$f" .dmrc) logs in to the login screen's default session again"
	done
	lightdm_conf_repair
	if [[ -f $SYS_DIR/pi-greeter.conf.new ]]; then
		as_root rm -f -- /etc/lightdm/pi-greeter.conf
	elif [[ -f $SYS_DIR/pi-greeter.conf.orig ]]; then
		as_root cp -a -- "$SYS_DIR/pi-greeter.conf.orig" /etc/lightdm/pi-greeter.conf
		ok "Restored the previous /etc/lightdm/pi-greeter.conf"
	fi

	# This user's own files: other desktops' settings, and what the session
	# left that is still as the session wrote it
	step "Restoring the settings of $(id -un)"
	restore_user
	restore_user "$(_st "$PREV_NAME")"
	restore_user "$(_st "$OLD_NAME")"
	# The settings of the Raspberry Pi Desktop session, which no other session
	# reads, so a new install starts from the defaults for this computer
	f=${XDG_CONFIG_HOME:-$HOME/.config}
	for p in rpd-rc.xml lxde-pi-rc.xml rpd-x-rc.xml LXDE-pi-rc.xml; do
		rm -f -- "$f/openbox/$p" "$f/openbox/.$p.$APP_NAME" "$f/openbox/.$p.$PREV_NAME"
	done
	rm -rf -- "$f/lxsession/rpd-x" "$f/lxsession/LXDE-pi" "$f/lxpanel/rpd-x" "$f/lxpanel/LXDE-pi" "$f/lxpanel-pi" \
		"$f/pcmanfm/rpd-x" "$f/pcmanfm/LXDE-pi" "$f/wf-panel-pi" "$f/wf-panel-pi.ini"
	rm -f -- "$f/pcmanfm/default"/desktop-items-*.conf
	# labwc's file, where it holds a Raspberry Pi theme
	if grep -qE '<name>PiX(flat|noir|trix|onyx)?</name>' "$f/labwc/rc.xml" 2>/dev/null; then
		rm -f -- "$f/labwc/rc.xml" "$f/labwc/themerc-override"
	fi
	# The highlight colours of Appearance Settings, in copies of the themes
	for p in PiXflat PiXnoir PiXtrix PiXonyx PiX; do
		rm -rf -- "${XDG_DATA_HOME:-$HOME/.local/share}/themes/$p" "${XDG_DATA_HOME:-$HOME/.local/share}/themes/t$p"
	done
	for p in "$APP_NAME" "$PREV_NAME"; do
		[[ -f $f/gtk-4.0/gtk.css ]] && sed -i --follow-symlinks "/^\/\* >>> $p >>> \*\/\$/,/^\/\* <<< $p <<< \*\/\$/d" "$f/gtk-4.0/gtk.css"
	done
	# The highlight colour of rpios-look-set, which only the session read
	rm -rf -- "${XDG_DATA_HOME:-$HOME/.local/share}/$APP_NAME"
	# The session's own GSettings database, XSETTINGS and labwc settings
	rm -f -- "${XDG_CONFIG_HOME:-$HOME/.config}/dconf/${APP_NAME//-/}" "${XDG_CONFIG_HOME:-$HOME/.config}/xsettingsd/xsettingsd.conf"
	if grep -qF '<!-- rpios-look -->' "${XDG_CONFIG_HOME:-$HOME/.config}/labwc/rc.xml" 2>/dev/null; then
		rm -f -- "${XDG_CONFIG_HOME:-$HOME/.config}/labwc/rc.xml"
	fi

	step "Removing packages"
	for p in "$APP_PKG" "$PREV_PKG" "$OLD_PKG"; do
		[[ -n $(installed_version "$p") ]] || continue
		as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y -q "$p" >/dev/null
		ok "Removed the Raspberry Pi Desktop session ($p)"
	done
	restore_debian_stack
	if (( ${#pkgs[@]} )) && ask "Also remove the ${#pkgs[@]} packages this script installed" y; then
		mapfile -t remove < <(_safe_purge_set "${pkgs[@]}" || true)
		for p in "${pkgs[@]}"; do [[ " ${remove[*]} " == *" $p "* ]] || keep+=("$p"); done
		if (( ${#remove[@]} )); then as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${remove[@]}"; fi
		# Packages kept for other software are left to APT: marked automatic,
		# they go with 'apt autoremove' once nothing needs them
		if (( ${#keep[@]} )); then
			as_root apt-mark auto "${keep[@]}" >/dev/null
			info "Kept, because other installed software needs them: ${keep[*]}"
		fi
		pkgs=()
	fi
	# The icon caches the removed icon sets leave behind, in a folder no
	# package owns any more,
	for f in /usr/share/icons/PiXflat /usr/share/icons/PiXtrix /usr/share/icons/PiX; do
		[[ -d $f && $(ls -A "$f") == icon-theme.cache ]] && ! dpkg -S "$f" >/dev/null 2>&1 && as_root rm -rf -- "$f"
	done
	# and the font folders, where fontconfig leaves its .uuid file
	for f in /usr/share/fonts/truetype/piboto /usr/share/fonts/truetype/nunito-sans; do
		[[ -d $f && $(ls -A "$f") == .uuid ]] && ! dpkg -S "$f" >/dev/null 2>&1 && as_root rm -rf -- "$f"
	done
	if [[ -s $SYS_DIR/hardware-packages ]]; then
		info "Kept, as hardware support: $(paste -sd' ' "$SYS_DIR/hardware-packages")"
	fi
	if (( ${#pkgs[@]} == 0 )); then as_root rm -rf -- "$SYS_DIR"; fi
	ok "Uninstalled. Log out and back in to finish."
}

###############################################################################
# 12. Main: modes, run log, summary
###############################################################################

# Print the help: the header from Usage to Requires.
usage() {
	local f=${BASH_SOURCE[0]:-}
	if [[ -f $f ]]; then sed -n '/^# Usage/,/^# ====/{/^# ====/q;s/^# \{0,1\}//;p}' "$f"
	else echo "Usage: bash $APP_NAME.sh [--refresh | --uninstall | --prepare-upgrade | --download | --offline | --help]"; fi
}

# Parse the command line into the O_* options. A mode may appear anywhere.
parse_args() {
	local opt val mode=""
	while (( $# )); do
		opt=$1
		if [[ $opt == --*=* ]]; then val=${opt#*=}; opt=${opt%%=*}; set -- "$opt" "$val" "${@:2}"; fi
		case $opt in
			--refresh|--uninstall|--prepare-upgrade|--download|--offline)
				[[ -z $mode || $mode == "${opt#--}" ]] || die "give only one of --refresh, --uninstall, --prepare-upgrade, --download and --offline"
				mode=${opt#--} ;;
			-t|--theme)       (( $# >= 2 )) || die "$opt needs a value"; set_option theme "${2,,}" || die "unknown theme '$2' (see --help)"; GIVEN[theme]=1; shift ;;
			--icons)          (( $# >= 2 )) || die "$opt needs a value"; set_option icons "${2,,}" || die "unknown icon set '$2' (see --help)"; GIVEN[icons]=1; shift ;;
			--wallpaper)      (( $# >= 2 )) || die "$opt needs a value"; set_option wallpaper "$2" || die "invalid wallpaper '$2'"; GIVEN[wallpaper]=1; shift ;;
			--4k|--no-4k)     set_option 4k "$([[ $opt == --4k ]] && echo 1 || echo 0)"; GIVEN[4k]=1 ;;
			--pi-apps|--no-pi-apps) set_option pi-apps "$([[ $opt == --pi-apps ]] && echo 1 || echo 0)"; GIVEN[pi-apps]=1 ;;
			--login-screen|--no-login-screen) set_option login-screen "$([[ $opt == --login-screen ]] && echo 1 || echo 0)"; GIVEN[login-screen]=1 ;;
			--pi-greeter|--no-pi-greeter) set_option pi-greeter "$([[ $opt == --pi-greeter ]] && echo 1 || echo 0)"; GIVEN[pi-greeter]=1 ;;
			--login-background) (( $# >= 2 )) || die "$opt needs a value"
				set_option login-background "$2" || die "invalid login background '$2' (raspios, debian or a full path)"; GIVEN[login-background]=1; shift ;;
			--qt|--no-qt)     set_option qt "$([[ $opt == --qt ]] && echo 1 || echo 0)"; GIVEN[qt]=1 ;;
			--wayland|--no-wayland|--auto|--auto-wayland)   # --auto-wayland: the name before
				case $opt in --wayland) val=on ;; --no-wayland) val=off ;; *) val=auto ;; esac
				set_option wayland "$val"; GIVEN[wayland]=1 ;;
			-d|--desktop)     (( $# >= 2 )) || die "$opt needs a value"; O_DESKTOPS=${2,,}; shift ;;
			--bundle)         (( $# >= 2 )) || die "$opt needs a value"; O_BUNDLE=${2,,}; shift ;;
			--no-log)         O_LOG=0 ;;
			-y|--yes)         O_YES=1 ;;
			-v|--verbose)     O_VERBOSE=1 ;;
			-h|--help)        usage; exit 0 ;;
			-V|--version)     echo "$APP_NAME $APP_VERSION"; exit 0 ;;
			*) die "unknown argument '$opt'; see: $(self_cmd) --help" ;;
		esac
		shift
	done
	O_MODE=${mode:-install}
	if [[ $O_DESKTOPS != none && $O_DESKTOPS != all ]]; then
		for val in ${O_DESKTOPS//,/ }; do
			[[ " ${DE_OTHER[*]} " == *" $val "* ]] || die "unsupported desktop '$val' (use: ${DE_OTHER[*]}, all or none)"
		done
	fi
	[[ -z $O_BUNDLE || $O_MODE == download ]] || die "--bundle goes with --download"
	if (( ! O_YES )) && { : </dev/tty; } 2>/dev/null; then O_INTERACTIVE=1; fi
}

# Copy everything this run prints to a log of its own in the home folder,
# named after its mode (rpios-look-install-DATE-TIME.log), after a header
# describing the system. The newest ten logs of each mode stay.
start_log() {
	local log
	(( O_LOG )) || return 0
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
			lxpanel lxpanel-pi pcmanfm pcmanfm-pi lightdm lightdm-gtk-greeter pi-greeter "$APP_PKG" "$PREV_PKG" "$OLD_PKG" 2>/dev/null \
			| awk '$1 ~ /^.i/ { print $2 }' | paste -sd' ' -)"
	} >>"$log"
	# Every line is written with the date and time, without colours
	exec > >(tee -a >(sed -u 's/\x1b\[[0-9;]*m//g' \
		| while IFS= read -r line; do printf '%(%Y-%m-%d %H:%M:%S)T  %s\n' -1 "$line"; done >>"$log")) 2>&1
	LOG_FILE=$log
}

# Remove temporary files on exit.
cleanup() {
	if [[ -n $WORKDIR && -d $WORKDIR ]]; then rm -rf -- "$WORKDIR"; fi
	if [[ -n $BUILD_STAGE && -d $BUILD_STAGE ]]; then rm -rf -- "$BUILD_STAGE"; fi
}

# Show a numbered menu and set REPLY to the chosen index (from 0).
# Usage: _menu PROMPT DEFAULT-NUMBER ITEM...
_menu() {
	local prompt=$1 def=$2 ans i; shift 2
	for i in $(seq 1 $#); do log "   $i) ${!i}"; done
	while :; do
		read -r -p "  $prompt [$def]: " ans </dev/tty || ans=""
		ans=${ans:-$def}
		if [[ $ans =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= $# )); then REPLY=$(( ans - 1 )); return 0; fi
		warn "please enter a number from the list"
	done
}

# Ask which installed theme to use, unless --theme was given.
LOOK_CHOSEN=0
choose_look() {
	local i def=1 cur dflt
	local -a ids=() items=()
	[[ -z ${GIVEN[theme]:-} ]] && (( O_INTERACTIVE )) || return 0
	cur=$(chosen_theme) dflt=$(default_theme)
	for i in pixflat pixnoir pixtrix pixonyx pix; do
		set_theme "$i"
		[[ -f /usr/share/themes/$T_GTK/gtk-3.0/gtk.css ]] || continue
		ids+=("$i") items+=("$T_DESC")
		[[ $i == "$cur" ]] && def=${#ids[@]}
	done
	(( ${#ids[@]} > 1 )) || { set_theme "$cur"; return 0; }
	step "Select the look"
	log "  Every theme is installed; choose the one the session uses. You can change it"
	log "  later with: $APP_NAME-set --theme NAME (for you), or by running this again."
	_menu "Theme" "$def" "${items[@]}"
	O_THEME=${ids[REPLY]} LOOK_CHOSEN=1
	if [[ $O_THEME == "$dflt" ]]; then O_THEME=auto; fi
	set_theme "$(chosen_theme)"
}

# Apply the chosen theme to the current user's own settings, if they have any.
apply_user_look() {
	local f cur
	(( LOOK_CHOSEN )) || [[ -n ${GIVEN[theme]:-} ]] || return 0
	f=${XDG_CONFIG_HOME:-$HOME/.config}/lxsession/$S_PROFILE/desktop.conf
	[[ -f $f && -x /usr/bin/$APP_NAME-set ]] || return 0
	cur=$(sed -n 's/^sNet\/ThemeName=//p' "$f" | first_line)
	[[ -n $cur && $cur != "$T_GTK" ]] || return 0
	if "/usr/bin/$APP_NAME-set" --theme "$(chosen_theme)" >/dev/null 2>&1; then
		ok "$T_GTK replaces $cur, your own theme in the session"
	else
		warn "Could not set $T_GTK for you; run: $APP_NAME-set --theme $(chosen_theme)"
	fi
}

# Summarise what an install will do.
print_plan() {
	local p total=0 src="$RPI_ARCHIVE"
	for p in "${FETCH_PKGS[@]}"; do [[ $(_pkg_status "$p") == "up to date" ]] || total=$(( total + ${PKG_SIZE[$p]:-0} )); done
	[[ -n $REPO ]] && src="packages/"
	step "Plan"
	log "  Looks        every theme; you choose the one to use at the end (now: ${T_DESC%% —*})"
	log "  Session      Raspberry Pi Desktop on $(display_name), on the login screen for every user"
	[[ $H_DISPLAY == wayland ]] && log "               and on X (Openbox), for when Wayland does not suit"
	log "  Packages     from $src ($H_SUITE, $H_ARCH), up to $(human_size "$total") to download"
	for p in "${FETCH_PKGS[@]}"; do _pkg_line "$p" "${PKG_VER[$p]}" "$(_pkg_status "$p")"; done
	for p in "${APT_PKGS[@]}"; do _pkg_line "$p" "(APT)" "new, from your Debian sources"; done
	[[ $O_DESKTOPS == none ]] || log "  Also         ${O_DESKTOPS//,/, } for $(id -un), with a backup of the settings it changes"
	if (( USE_STACK )); then
		log "  Replaces     Debian's panel and file manager with Raspberry Pi OS's builds of"
		log "               them (lxpanel, pcmanfm, libfm above), which Debian's LXDE session"
		log "               then uses too. --uninstall puts Debian's back; --no-pi-apps keeps them."
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
	if (( RELOGIN )) && [[ ${DESKTOP_SESSION:-} != "$SESSION_ID" ]]; then
		info "Log out and choose ${C_B}Raspberry Pi Desktop${C_0} on the login screen (it is chosen for you); other sessions stay as they were."
	fi
	info "Updates: $(self_cmd) --refresh    Undo: $(self_cmd) --uninstall"
	if [[ -n $LOG_FILE ]]; then info "Log of this run: $LOG_FILE"; fi
}

# Install, update, refresh or install offline.
install_mode() {
	if [[ $O_MODE == refresh ]]; then
		[[ -f $SYS_DIR/installed-packages || -n $(installed_version "$APP_PKG") ]] \
			|| die "the Raspberry Pi OS look is not installed; install it with: $(self_cmd)"
	fi
	preflight_tools
	[[ $O_MODE == offline && -z $H_RPI_ARCH ]] && die "an offline install needs amd64, arm64, armhf or i386; install online instead"
	[[ -z $REPO ]] || verify_repo
	pick_display
	print_machine
	set_theme "$(chosen_theme)"
	# Root rights first: reading the kernel log for missing firmware needs them
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
	migrate_old
	install_all
	[[ $O_MODE == refresh ]] || choose_look
	install_pkg
	step "Setting up the login screen and the session for $(id -un)"
	(( O_LOGIN && O_PI_GREETER )) && greeter_conf
	_state_init
	choose_session
	apply_user_look
	apply_desktops
	reload_session
	save_options
	save_state
	[[ ! -f $SYS_DIR/removed-for-upgrade ]] || as_root rm -f -- "$SYS_DIR/removed-for-upgrade"
	summary
}

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
	[[ $O_MODE == download ]] || adopt_prev_records
	case $O_MODE in
		download)  download_mode; return 0 ;;
		uninstall) uninstall; return 0 ;;
	esac
	pick_suite
	load_options
	case $O_MODE in
		prepare-upgrade) prepare_upgrade ;;
		*)               install_mode ;;
	esac
}

# Run main unless this file is sourced (the tests source it).
if [[ ${BASH_SOURCE[0]:-} == "$0" || -z ${BASH_SOURCE[0]:-} ]]; then
	main "$@"
fi
