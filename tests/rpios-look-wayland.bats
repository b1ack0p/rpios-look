#!/usr/bin/env bats
# Unit tests of rpios-look.sh's Wayland (labwc) session.
# They source the script, which then defines its functions
# without running anything, and need no root, network or desktop.
# Run: bats tests/

bats_require_minimum_version 1.5.0

setup() {
	# RPIOS_LOOK_SH: another copy of the script, for mutation checks
	SCRIPT=${RPIOS_LOOK_SH:-$BATS_TEST_DIRNAME/../rpios-look.sh}
	# shellcheck source=../rpios-look.sh
	source "$SCRIPT"
	XDG_CACHE_HOME=$BATS_TEST_TMPDIR/cache
	load_releases
}

# Raspberry Pi OS 13's Wayland desktop package (rpd-wayland-core), unpacked:
# the parts of its labwc and panel settings that the session reads. Sets
# PI_DIR and has pi_unpack print it.
pi_fixture() {
	PI_DIR=$BATS_TEST_TMPDIR/pi
	mkdir -p "$PI_DIR/etc/xdg/labwc" "$PI_DIR/etc/xdg/wf-panel-pi"
	{
		printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<openbox_config xmlns="http://openbox.org/3.4/rc">' '' \
			'  <theme>' '    <name>PiXtrix</name>' '    <cornerRadius>0</cornerRadius>' '    <keepBorder>yes</keepBorder>'
		for p in ActiveWindow InactiveWindow OnScreenDisplay MenuItem; do
			printf '    <font place="%s">\n      <name>Nunito Sans</name>\n      <size>12</size>\n      <weight>Light</weight>\n      <slant>Normal</slant>\n    </font>\n' "$p"
		done
		printf '%s\n' '    <dropShadows>yes</dropShadows>' '    <titlebar>' '      <layout>:iconify,max,close</layout>' '    </titlebar>' '  </theme>' '' \
			'  <keyboard>' '    <numlock>off</numlock>' '    <default />' \
			'    <keybind key="C-Print">' '      <action name="Execute" command="gui-screenshot -a" />' '    </keybind>' \
			'    <keybind key="C-A-l">' '      <action name="Execute" command="swaylock -p" />' '    </keybind>' \
			'    <keybind key="A-F2">' '      <action name="Execute" command="gui-runcmd" />' '    </keybind>' \
			'    <keybind key="C-A-t">' '      <action name="Execute" command="lab-sensible-terminal" />' '    </keybind>' \
			'    <keybind key="XF86PowerOff" onRelease="yes">' '      <action name="Execute" command="pwrkey" />' '    </keybind>' \
			'  </keyboard>' '' '</openbox_config>'
	} >"$PI_DIR/etc/xdg/labwc/rc.xml"
	printf '%s\n' '<openbox_menu>' '  <menu id="root-menu">' '    <item label="Desktop Preferences...">' \
		'      <action name="Execute" command="rpcc desktop" />' '    </item>' '  </menu>' '</openbox_menu>' >"$PI_DIR/etc/xdg/labwc/menu.xml"
	printf '%s\n' '[panel]' 'widgets_left=smenu spacing0 spacing4 launchers spacing8 window-list' \
		'widgets_right=tray power ejecter updater spacing2 connect spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock spacing2 batt spacing2 squeek' \
		'launchers=x-www-browser pcmanfm x-terminal-emulator' >"$PI_DIR/etc/xdg/wf-panel-pi/wf-panel-pi.ini"
	pi_unpack() { [ -n "${PI_DIR:-}" ] && printf '%s\n' "$PI_DIR"; }
}

# The window themes installed (under SYS_ROOT). Usage: mk_themes NAME...
mk_themes() {
	local t
	for t; do mkdir -p "$SYS_ROOT/usr/share/themes/$t/openbox-3"; echo 'border.radius: 0' >"$SYS_ROOT/usr/share/themes/$t/openbox-3/themerc"; done
}

# The computer's battery and on-screen keyboard: BATTERY=1 and SQUEEK=1
# fake them; neither is read from this computer
fake_hw() {
	has_battery() { [ "${BATTERY:-0}" = 1 ]; }
	command() { if [ "$1" = -v ] && [ "$2" = squeekboard ]; then [ "${SQUEEK:-0}" = 1 ]; else builtin command "$@"; fi; }
}

# The Wayland session's files for a theme and size in a fresh test root.
# Usage: wl_build THEME [SIZE]; sets r, xdg
wl_build() {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR WAYLAND=1 H_SUITE=trixie H_ARCH=amd64
	O_SIZE=${2:-medium} set_theme "$1"
	r=$BATS_TEST_TMPDIR/root-$1-${2:-medium} xdg=$BATS_TEST_TMPDIR/root-$1-${2:-medium}$SHARE/xdg
	rm -rf -- "$r"
	_wayland_session "$r"
}

# The window theme named in an rc.xml (not a font name)
rc_theme() { sed -n '/<theme>/,/<\/theme>/ { /<font /,/<\/font>/!s|.*<name>\([^<]*\)</name>.*|\1|p }' "$1"; }

@test "wayland_known: Raspberry Pi's desktop package runs labwc and wf-panel-pi, and Debian has labwc" {
	index_load() { [ "${IDX:-1}" = 1 ]; }
	index_candidates() { [ "$3" = rpd-wayland-core ] && printf '1.35\tamd64\tf.deb\tsha\t1\t%s\n' "$DEPS"; }
	apt_has() { [ "$1" = labwc ] && [ "${APT_LABWC:-1}" = 1 ]; }
	# The release's own package holds labwc's settings and the panel's
	WLPI=$BATS_TEST_TMPDIR/pi; pi_unpack() { echo "$WLPI"; }
	mkdir -p "$WLPI/etc/xdg/labwc" "$WLPI/etc/xdg/wf-panel-pi"; : >"$WLPI/etc/xdg/labwc/rc.xml"; : >"$WLPI/etc/xdg/wf-panel-pi/wf-panel-pi.ini"
	DEPS="labwc (>= 0.8), wf-panel-pi, kanshi | wlr-randr"
	wayland_known trixie amd64
	# Without them, the desktop is not known: no copy of an earlier one stands in
	rm "$WLPI/etc/xdg/wf-panel-pi/wf-panel-pi.ini"; run ! wayland_known trixie amd64
	: >"$WLPI/etc/xdg/wf-panel-pi/wf-panel-pi.ini"
	run ! declare -F _wl_rc_default
	DEPS="labwc, wfplug-clock"
	run ! wayland_known trixie amd64
	DEPS="labwc-pi, wf-panel-pi"
	run ! wayland_known trixie amd64
	DEPS="labwc, wf-panel-pi" APT_LABWC=0
	run ! wayland_known trixie amd64
	APT_LABWC=1 IDX=0
	run ! wayland_known trixie amd64
}

@test "wl_apps: the programs and the plugins, less updater, power, connect; netman only with USE_NETMAN, batt only with a battery" {
	fake_hw
	index_candidates() { [ "$3" = rpd-wayland-core ] && printf '1.35\tamd64\tf.deb\tsha\t1\t%s\n' \
		"labwc, wf-panel-pi, autotouch, wfplug-batt, wfplug-bluetooth, wfplug-connect, wfplug-netman, wfplug-power, wfplug-updater, wfplug-volumepulse"; }
	USE_NETMAN=0 BATTERY=0
	diff <(wl_apps trixie amd64) - <<<$'wf-panel-pi\ngui-screenshot\nswaylock\nwfplug-bluetooth\nwfplug-volumepulse'
	USE_NETMAN=1 BATTERY=1
	diff <(wl_apps trixie amd64) - <<<$'wf-panel-pi\ngui-screenshot\nswaylock\nwfplug-batt\nwfplug-bluetooth\nwfplug-netman\nwfplug-volumepulse'
	# rpi_pkgs adds them only for the Wayland session
	grep -q '^	if (( WAYLAND )); then wl_apps "$1" "$2"; fi$' <(sed -n '/^rpi_pkgs() {$/,/^}$/p' "$SCRIPT")
}

@test "wayland_debs: Debian's labwc and helpers, only with the Wayland session, no Raspberry Pi names" {
	WAYLAND=0
	[ -z "$(wayland_debs)" ]
	WAYLAND=1
	out=$(wayland_debs)
	for p in labwc kanshi wlr-randr xsettingsd squeekboard; do grep -qx "$p" <<<"$out"; done
	# No idle helper: Raspberry Pi OS's Wayland session starts none
	run ! grep -qxE 'swayidle|wlopm' <<<"$out"
	run ! grep -qE '^(wf-panel-pi|wfplug-.*|swaylock|gui-screenshot|labwc-pi)$' <<<"$out"
}

@test "desktop_unknown: Raspberry Pi's Wayland package is checked only with the Wayland session; its known and skipped packages are not noted" {
	index_names() { printf '%s\n' wf-panel-pi gui-screenshot swaylock autotouch wfplug-clock newtool labwc pcmanfm-pi; }
	index_candidates() {
		case $3 in
			rpd-wayland-core) printf '1\tamd64\tf\ts\t1\t%s\n' "labwc, wf-panel-pi, gui-screenshot, swaylock, autotouch, wfplug-clock, newtool" ;;
			*) printf '1\tamd64\tf\ts\t1\t%s\n' "pcmanfm-pi" ;;
		esac
	}
	_debian_has() { [ "$1" = labwc ]; }
	WAYLAND=1
	[ "$(desktop_unknown trixie amd64)" = newtool ]
	WAYLAND=0
	[ -z "$(desktop_unknown trixie amd64)" ]
}

@test "TWIN_RE: swaylock is a twin, repacked beside Debian's; its neighbours are not" {
	[[ swaylock =~ ^($TWIN_RE)$ ]]
	run ! eval '[[ swaylock-pi =~ ^($TWIN_RE)$ ]]'
	run ! eval '[[ swayidle =~ ^($TWIN_RE)$ ]]'
	run ! eval '[[ wf-panel-pi =~ ^($TWIN_RE)$ ]]'
	# The repacking keeps the exact Raspberry Pi version only between twins
	[ "$(twin_deps swaylock 'libc6 (>= 2.34), libpam0g (= 1.5+rpt1)')" = "libc6 (>= 2.34), libpam0g" ]
}

@test "_wl_panel_ini: Raspberry Pi OS 13's layout without updater, power and connect; netman, batt and squeek only when present" {
	_browser() { echo firefox-esr.desktop; }; _terminal() { echo lxterminal.desktop; }; S_PI_FM=1
	fake_hw
	pi_fixture
	local L='widgets_left=smenu spacing0 spacing4 launchers spacing8 window-list'
	# Nothing extra: no network plugin, no battery, no on-screen keyboard
	USE_NETMAN=0 BATTERY=0 SQUEEK=0 APT_PKGS=() O_SIZE=medium; set_theme pixtrix
	out=$(_wl_panel_ini "$PI_DIR")
	grep -qx "$L" <<<"$out"
	grep -qx 'widgets_right=tray ejecter spacing2 bluetooth spacing2 volumepulse spacing2 clock' <<<"$out"
	# Launchers by the session's .desktop names (Raspberry Pi's come from its
	# rpd-common, which Debian lacks)
	grep -qx 'launchers=firefox-esr pcmanfm-pi lxterminal' <<<"$(_wl_panel_ini "$PI_DIR")"
	S_PI_FM=0; grep -qx 'launchers=firefox-esr pcmanfm lxterminal' <<<"$(_wl_panel_ini "$PI_DIR")"; S_PI_FM=1
	# Medium: the panel's own icon size, as Raspberry Pi OS leaves it
	run ! grep -q '^icon_size=' <<<"$out"
	# Without the package's layout the build stops: no built-in copy
	H_SUITE=trixie; run _wl_panel_ini "$BATS_TEST_TMPDIR/none"
	[ "$status" = 1 ] && [[ $output == *"cannot read Raspberry Pi OS trixie's panel settings"* ]]
	# Everything
	USE_NETMAN=1 BATTERY=1 SQUEEK=1
	out=$(_wl_panel_ini "$PI_DIR")
	grep -qx "$L" <<<"$out"
	grep -qx 'widgets_right=tray ejecter spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock spacing2 batt spacing2 squeek' <<<"$out"
	# A battery only: the spacer of the left-out keyboard goes too
	USE_NETMAN=0 BATTERY=1 SQUEEK=0
	grep -qx 'widgets_right=tray ejecter spacing2 bluetooth spacing2 volumepulse spacing2 clock spacing2 batt' <<<"$(_wl_panel_ini "$PI_DIR")"
	# squeekboard about to be installed (APT_PKGS) counts as installed
	BATTERY=0 APT_PKGS=(labwc squeekboard)
	grep -qx 'widgets_right=tray ejecter spacing2 bluetooth spacing2 volumepulse spacing2 clock spacing2 squeek' <<<"$(_wl_panel_ini "$PI_DIR")"
	# The network plugin only
	USE_NETMAN=1 APT_PKGS=()
	grep -qx 'widgets_right=tray ejecter spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock' <<<"$(_wl_panel_ini "$PI_DIR")"
	# Another size: as Appearance Settings writes it, the panel's height
	# (the preset's T_PANEL_ICON) less 4, once
	for s in small large larger; do
		O_SIZE=$s; set_theme pixtrix
		out=$(_wl_panel_ini "$PI_DIR")
		grep -qx "icon_size=$((T_PANEL_ICON - 4))" <<<"$out"
		[ "$(grep -c '^icon_size=' <<<"$out")" = 1 ]
		# and the window buttons' width, in their own section, once
		grep -A1 -x '\[window-list\]' <<<"$out" | grep -qx "max_width=$T_TASK_WIDTH"
		[ "$(grep -c '^max_width=' <<<"$out")" = 1 ]
	done
	[ "$T_PANEL_ICON" = 68 ]
	grep -qx icon_size=64 <<<"$out"
	# Raspberry Pi's newest layout is followed: a plugin it adds stays
	sed -i 's/ clock / clock spacing2 cpu /' "$PI_DIR/etc/xdg/wf-panel-pi/wf-panel-pi.ini"
	grep -qx 'widgets_right=tray ejecter spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock spacing2 cpu' <<<"$(_wl_panel_ini "$PI_DIR")"
	# Medium: the panel's own window button width
	O_SIZE=medium; set_theme pixtrix
	run ! grep -q '^max_width=' <<<"$(_wl_panel_ini "$PI_DIR")"
}

@test "_wl_environment: the system's keyboard layout (never a British default), the look's cursor, Xwayland through the session" {
	SYS_ROOT=$BATS_TEST_TMPDIR/root
	O_SIZE=medium; set_theme pixtrix
	out=$(_wl_environment)
	run ! grep -q '^XKB_' <<<"$out"
	run ! grep -q 'gb' <<<"$out"
	run ! grep -q LIFTOFF <<<"$out"
	run ! grep -q XAUTHORITY <<<"$out"
	grep -qx "XCURSOR_THEME=$T_ICONS" <<<"$out"
	grep -qx 'XCURSOR_SIZE=24' <<<"$out"
	grep -qx "WLR_XWAYLAND=$SHARE/xwayland" <<<"$out"
	grep -qx 'DESKTOP_SESSION=rpd-labwc' <<<"$out"
	grep -qx 'QT_WAYLAND_DISABLE_WINDOWDECORATION=1' <<<"$out"
	# Debian's keyboard settings
	mkdir -p "$SYS_ROOT/etc/default"
	printf '%s\n' 'XKBMODEL="pc105"' 'XKBLAYOUT="de"' 'XKBVARIANT=""' 'XKBOPTIONS="ctrl:nocaps"' 'BACKSPACE="guess"' >"$SYS_ROOT/etc/default/keyboard"
	out=$(_wl_environment)
	grep -qx 'XKB_DEFAULT_LAYOUT=de' <<<"$out"
	grep -qx 'XKB_DEFAULT_MODEL=pc105' <<<"$out"
	grep -qx 'XKB_DEFAULT_OPTIONS=ctrl:nocaps' <<<"$out"
	run ! grep -q '^XKB_DEFAULT_VARIANT' <<<"$out"
	run ! grep -q 'gb' <<<"$out"
	sed -i 's/"de"/"gb"/' "$SYS_ROOT/etc/default/keyboard"
	grep -qx 'XKB_DEFAULT_LAYOUT=gb' <<<"$(_wl_environment)"
	# The size's cursor
	O_SIZE=large; set_theme pixonyx
	out=$(_wl_environment)
	grep -qx 'XCURSOR_SIZE=36' <<<"$out"
	grep -qx "XCURSOR_THEME=$T_ICONS" <<<"$out"
}

@test "_wayland_session: labwc's settings from Raspberry Pi's package, with the look's window theme, fonts and lock key" {
	fake_hw
	pi_fixture
	SYS_ROOT=$BATS_TEST_TMPDIR/sys
	mk_themes PiXtrix PiXonyx PiXtrix_l PiXflat
	wl_build pixtrix
	rc=$xdg/labwc/rc.xml
	[ "$(rc_theme "$rc")" = PiXtrix ]
	[ "$(grep -c '<name>Nunito Sans</name>' "$rc")" = 4 ]
	[ "$(grep -c '<size>12</size>' "$rc")" = 4 ]
	[ "$(grep -c '<weight>Light</weight>' "$rc")" = 4 ]
	# Ctrl+Alt+L exactly as Raspberry Pi OS binds it (the Shutdown dialog
	# reads it); the session's swaylock starts the repacked lock
	grep -q 'command="swaylock -p"' "$rc"
	run ! grep -q 'swaylock-pi' "$rc"
	# The rest of Raspberry Pi's settings stay
	grep -q 'command="gui-screenshot -a"' "$rc"
	grep -q '<layout>:iconify,max,close</layout>' "$rc"
	# The menu opens pcmanfm's own Desktop Preferences
	grep -q 'command="pcmanfm --desktop-pref"' "$xdg/labwc/menu.xml"
	run ! grep -q rpcc "$xdg/labwc/menu.xml"
	# Large: the large window theme and the size's font
	wl_build pixtrix large
	[ "$(rc_theme "$xdg/labwc/rc.xml")" = PiXtrix_l ]
	[ "$(grep -c '<size>16</size>' "$xdg/labwc/rc.xml")" = 4 ]
	# Larger, a theme without its _l installed: the theme itself
	wl_build pixonyx larger
	[ "$(rc_theme "$xdg/labwc/rc.xml")" = PiXonyx ]
	[ "$(grep -c '<size>24</size>' "$xdg/labwc/rc.xml")" = 4 ]
	# PiX has no labwc look: PiXtrix
	wl_build pix
	[ "$(rc_theme "$xdg/labwc/rc.xml")" = PiXtrix ]
	# PiXflat: its own font and weight
	wl_build pixflat
	[ "$(rc_theme "$xdg/labwc/rc.xml")" = PiXflat ]
	[ "$(grep -c '<name>PibotoLt</name>' "$xdg/labwc/rc.xml")" = 4 ]
	[ "$(grep -c '<weight>Normal</weight>' "$xdg/labwc/rc.xml")" = 4 ]
}

@test "_wayland_session: without Raspberry Pi's package the build stops; no copy of an earlier release's settings stands in" {
	fake_hw
	pi_unpack() { return 1; }
	SYS_ROOT=$BATS_TEST_TMPDIR/sys
	mk_themes PiXtrix PiXtrix_l
	run wl_build pixtrix large
	[ "$status" = 1 ] && [[ $output == *"cannot read Raspberry Pi OS trixie's labwc settings"* ]]
}

@test "_wayland_session: autostart, environment, panel and the login screen's entry" {
	fake_hw
	pi_fixture
	SYS_ROOT=$BATS_TEST_TMPDIR/sys USE_NETMAN=0 BATTERY=0 SQUEEK=0 APT_PKGS=()
	mk_themes PiXtrix
	wl_build pixtrix
	a=$xdg/labwc/autostart
	grep -qx "$SHARE/lwrespawn wf-panel-pi &" "$a"
	grep -qx "$SHARE/lwrespawn $SHARE/desktop &" "$a"
	grep -qx 'kanshi &' "$a"
	grep -qx "$SHARE/squeek &" "$a"
	grep -qx 'lxsession-xdg-autostart' "$a"
	# No direct path to Raspberry Pi's file manager, no Raspberry Pi-only tools
	run ! grep -q /usr/bin/pcmanfm-pi "$a"
	run ! grep -qE 'raspi-config|rpcc|rpinters|wayvnc|pi-greeter|squeekboard ' "$a"
	diff "$xdg/labwc/environment" <(_wl_environment)
	# The panel reads its settings from /etc/xdg (not XDG_CONFIG_DIRS), as on Raspberry Pi OS
	diff "$r/etc/xdg/wf-panel-pi/wf-panel-pi.ini" <(_wl_panel_ini "$PI_DIR")
	[ ! -e "$xdg/wf-panel-pi" ]
	e=$r/usr/share/wayland-sessions/rpios-look-wayland.desktop
	grep -qx 'Name=Raspberry Pi Desktop (Wayland)' "$e"
	grep -qx "Exec=$SHARE/start-wayland" "$e"
	grep -qx 'TryExec=/usr/bin/labwc' "$e"
	grep -qx 'Type=Application' "$e"
	# Only the Wayland session's entry; the X one is not written here
	[ "$(ls "$r/usr/share/wayland-sessions")" = rpios-look-wayland.desktop ]
	[ ! -e "$r/usr/share/xsessions" ]
	# build_pkg writes it only for the Wayland session
	grep -q '(( ! WAYLAND )) || _wayland_session "$root"' "$SCRIPT"
}

@test "start-wayland: labwc as Raspberry Pi OS starts it, software rendering only without a render node, the user's files left alone" {
	r=$BATS_TEST_TMPDIR/root WORKDIR=$BATS_TEST_TMPDIR
	O_SIZE=medium; set_theme pixtrix
	_wl_programs "$r"
	s=$r$SHARE/start-wayland
	for f in start-wayland lwrespawn xwayland xsettings squeek; do
		[ -x "$r$SHARE/$f" ]
		sh -n "$r$SHARE/$f"
	done
	grep -qx 'set -- /usr/bin/labwc -m "$@"' "$s" && [ "$(tail -n 1 "$s")" = 'exec "$@"' ]
	run ! grep -q gtk.css "$s"
	run ! grep -q 'Xauthority\|xauth ' "$s"
	run ! grep -q 'Xauthority\|xauth ' "$r$SHARE/xwayland"
	run ! grep -q 'refuse\|exit 1' "$s"
	grep -q 'DCONF_PROFILE=$share/dconf/profile-wayland' "$s"
	# The session's name is set once, in labwc's environment file, as on Raspberry Pi OS
	run ! grep -q 'DESKTOP_SESSION' "$s"
	# The renderer line, run against a test /dev/dri
	line=$(grep WLR_RENDERER "$s")
	[ "$(grep -c WLR_RENDERER "$s")" = 1 ]
	line=${line//\/dev\/dri/$BATS_TEST_TMPDIR/dri}
	mkdir -p "$BATS_TEST_TMPDIR/dri"
	[ "$(env -u WLR_RENDERER sh -c "$line"'; echo "${WLR_RENDERER:-}"')" = pixman ]
	: >"$BATS_TEST_TMPDIR/dri/card0"
	[ "$(env -u WLR_RENDERER sh -c "$line"'; echo "${WLR_RENDERER:-}"')" = pixman ]
	: >"$BATS_TEST_TMPDIR/dri/renderD128"
	[ -z "$(env -u WLR_RENDERER sh -c "$line"'; echo "${WLR_RENDERER:-}"')" ]
	# Xwayland with xsettingsd for its display
	[ "$(tail -n 1 "$r$SHARE/xwayland")" = 'exec /usr/bin/Xwayland "$@"' ]
	grep -q 'xsettingsd -c' "$r$SHARE/xwayland"
}

@test "kanshi's file: start-wayland creates it empty only where there is none" {
	r=$BATS_TEST_TMPDIR/root WORKDIR=$BATS_TEST_TMPDIR
	set_theme pixtrix
	_wl_programs "$r"
	line=$(sed -n '/^if \[ ! -e "\$config\/kanshi\/config" \]; then$/,/^fi$/p' "$r$SHARE/start-wayland")
	c=$BATS_TEST_TMPDIR/config s=$BATS_TEST_TMPDIR/state
	config=$c XDG_STATE_HOME=$s sh -c "$line"
	[ -f "$c/kanshi/config" ]
	[ ! -s "$c/kanshi/config" ]
	# With its mark, so that only a file of the session's making is removed later
	[ -e "$s/rpios-look/kanshi-created" ]
	echo 'profile { output * enable }' >"$c/kanshi/config"; rm "$s/rpios-look/kanshi-created"
	config=$c XDG_STATE_HOME=$s sh -c "$line"
	grep -q profile "$c/kanshi/config" && [ ! -e "$s/rpios-look/kanshi-created" ]
}

@test "squeek: the on-screen keyboard starts only with squeekboard and a touch screen" {
	r=$BATS_TEST_TMPDIR/root WORKDIR=$BATS_TEST_TMPDIR
	set_theme pixtrix
	_wl_programs "$r"
	q=$r$SHARE/squeek
	grep -q "/run/udev/data/c13:\*" "$q"
	grep -qx 'exec squeekboard' "$q"
	# Run against a test udev folder
	u=$BATS_TEST_TMPDIR/udev b=$BATS_TEST_TMPDIR/bin
	mkdir -p "$u" "$b"
	sed "s|/run/udev/data|$u|" "$q" >"$BATS_TEST_TMPDIR/squeek"
	for t in sh grep; do ln -s "$(command -v "$t")" "$b/$t"; done
	# Without squeekboard
	echo 'E:ID_INPUT_TOUCHSCREEN=1' >"$u/c13:70"
	run env PATH="$b" sh "$BATS_TEST_TMPDIR/squeek"
	[ "$status" = 0 ]
	[ -z "$output" ]
	# With squeekboard, without a touch screen
	printf '#!/bin/sh\necho started\n' >"$b/squeekboard"; chmod +x "$b/squeekboard"
	printf 'E:ID_INPUT_MOUSE=1\nE:ID_INPUT_TOUCHPAD=1\n' >"$u/c13:70"
	run env PATH="$b" sh "$BATS_TEST_TMPDIR/squeek"
	[ "$status" = 0 ]
	[ -z "$output" ]
	# Both
	echo 'E:ID_INPUT_TOUCHSCREEN=1' >"$u/c13:71"
	run env PATH="$b" sh "$BATS_TEST_TMPDIR/squeek"
	[ "$status" = 0 ]
	[ "$output" = started ]
}

@test "xsettings: the GTK settings for X programs come from the session's GSettings; lwrespawn stops with labwc" {
	r=$BATS_TEST_TMPDIR/root WORKDIR=$BATS_TEST_TMPDIR b=$BATS_TEST_TMPDIR/bin
	O_SIZE=large; set_theme pixonyx
	_wl_programs "$r"
	mkdir -p "$b" "$BATS_TEST_TMPDIR/run"
	printf '#!/bin/sh\ncase $3 in gtk-theme) echo "'"'"'PiXonyx'"'"'" ;; icon-theme|cursor-theme) echo "'"'"'%s'"'"'" ;; font-name) echo "'"'"'%s'"'"'" ;; cursor-size) echo 36 ;; esac\n' "$T_ICONS" "$T_FONT" >"$b/gsettings"
	printf '#!/bin/sh\necho "pkill $*" >>"%s"\n' "$BATS_TEST_TMPDIR/log" >"$b/pkill"
	chmod +x "$b"/*
	PATH="$b:$PATH" XDG_RUNTIME_DIR=$BATS_TEST_TMPDIR/run sh "$r$SHARE/xsettings"
	f=$BATS_TEST_TMPDIR/run/rpios-look-xsettingsd.conf
	grep -qx 'Net/ThemeName "PiXonyx"' "$f"
	grep -qx "Net/IconThemeName \"$T_ICONS\"" "$f"
	grep -qx "Gtk/CursorThemeName \"$T_ICONS\"" "$f"
	grep -qx 'Gtk/CursorThemeSize 36' "$f"
	grep -qx "Gtk/FontName \"$T_FONT\"" "$f"
	grep -qx "Gtk/IconSizes \"gtk-large-toolbar=$T_TB_ICON,$T_TB_ICON\"" "$f"
	grep -q -- '-HUP .*-x xsettingsd' "$BATS_TEST_TMPDIR/log"
	# lwrespawn: nothing to do when the program runs already, or without labwc
	printf '#!/bin/sh\n[ "$4" = "${RUNS:-}" ]\n' >"$b/pgrep"; chmod +x "$b/pgrep"
	RUNS=prog PATH="$b:$PATH" timeout 5 sh "$r$SHARE/lwrespawn" "$b/notrun"
	RUNS="" PATH="$b:$PATH" timeout 5 sh "$r$SHARE/lwrespawn" "$b/notrun"
}

@test "_session_dconf: the Wayland session's own dconf profile and defaults (grey, slight hinting), only with the Wayland session" {
	command -v dconf >/dev/null || skip "dconf is not installed"
	WORKDIR=$BATS_TEST_TMPDIR
	set_theme pixtrix
	WAYLAND=0 r=$BATS_TEST_TMPDIR/x
	_session_dconf "$r"
	[ -f "$r$SHARE/dconf/profile" ]
	[ ! -e "$r$SHARE/dconf/profile-wayland" ]
	WAYLAND=1 r=$BATS_TEST_TMPDIR/wl
	_session_dconf "$r"
	diff "$r$SHARE/dconf/profile" - <<<"user-db:rpioslook"$'\n'"file-db:$SHARE/dconf/settings"
	diff "$r$SHARE/dconf/profile-wayland" - <<<"user-db:rpioslookwayland"$'\n'"file-db:$SHARE/dconf/settings-wayland"
	[ -s "$r$SHARE/dconf/settings-wayland" ]
	# Its defaults differ from the X session's in text smoothing only
	k=$WORKDIR/dconf-keys
	grep -qx "font-antialiasing='grayscale'" "$k-wayland/00-rpios-look"
	grep -qx "font-hinting='slight'" "$k-wayland/00-rpios-look"
	grep -qx "font-antialiasing='rgba'" "$k/00-rpios-look"
	[ "$(diff "$k/00-rpios-look" "$k-wayland/00-rpios-look" | grep -c '^>')" = 2 ]
}

# The generated rpios-look-set, with the session's files in a test folder,
# as make_set in rpios-look.bats, and the Wayland session's labwc settings;
# dconf and busctl calls are logged. RUN runs it in the Wayland session.
make_wl_set() {
	init_colors
	fake_hw
	pi_fixture
	WORKDIR=$BATS_TEST_TMPDIR S_PROFILE=rpd-x S_FM_PROFILE=rpd-x WAYLAND=1 H_SUITE=trixie H_ARCH=amd64
	SYS_ROOT=$BATS_TEST_TMPDIR/sys
	mk_themes PiXtrix PiXonyx PiXtrix_l PiXonyx_l
	r=$BATS_TEST_TMPDIR/root
	O_SIZE=${1:-medium}
	set_theme pixtrix
	_session_command "$r"
	_wayland_session "$r"
	share=$r$SHARE bin=$BATS_TEST_TMPDIR/bin
	# Themes only from the test's folders, never the computer's own
	sed -e "s|^APP=\(.*\) SHARE=$SHARE |APP=\1 SHARE=$share |" -e "s|/usr/share/wayland-sessions/|$r/usr/share/wayland-sessions/|" \
		-e "s| /usr/local/share/\"\\\$1\" /usr/share/\"\\\$1\"; }| \"$BATS_TEST_TMPDIR/sysshare/\\\$1\"; }|" \
		"$r/usr/bin/rpios-look-set" >"$BATS_TEST_TMPDIR/set"
	grep -q "SHARE=$share " "$BATS_TEST_TMPDIR/set"
	grep -q "^theme_dirs() .*sysshare" "$BATS_TEST_TMPDIR/set"
	mkdir -p "$share/xdg/lxsession/rpd-x" "$share/xdg/pcmanfm/rpd-x" "$share/dconf" "$bin"
	printf '[GTK]\nsNet/ThemeName=PiXtrix\n' >"$share/xdg/lxsession/rpd-x/desktop.conf"
	printf '[*]\nwallpaper=/w.jpg\n' >"$share/xdg/pcmanfm/rpd-x/desktop-items-0.conf"
	: >"$share/dconf/profile"; : >"$share/dconf/profile-wayland"
	mkdir -p "$share/xdg/openbox"
	printf '%s\n' '<openbox_config xmlns="http://openbox.org/3.4/rc">' '  <theme>' '    <name>PiXtrix</name>' '    <roundCorners>no</roundCorners>' \
		'    <font place="ActiveWindow">' '      <name>Nunito Sans</name>' '    </font>' '  </theme>' '</openbox_config>' >"$share/xdg/openbox/$OB_FILE"
	export HOME=$BATS_TEST_TMPDIR/home XDG_DATA_HOME=$BATS_TEST_TMPDIR/home/data XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/config
	mkdir -p "$HOME"
	for t in PiXtrix PiXonyx PiX PiXflat PiXnoir; do mkdir -p "$XDG_DATA_HOME/themes/$t/gtk-3.0" "$XDG_DATA_HOME/icons/$t-Debian"
		: >"$XDG_DATA_HOME/themes/$t/gtk-3.0/gtk.css"; : >"$XDG_DATA_HOME/icons/$t-Debian/index.theme"; done
	printf '#!/bin/sh\necho "$DCONF_PROFILE $*" >>"%s"\n[ "$1" != load ] || cat >>"%s"\n' "$BATS_TEST_TMPDIR/dconf.log" "$BATS_TEST_TMPDIR/dconf.log" >"$bin/dconf"
	printf '#!/bin/sh\nshift; exec "$@"\n' >"$bin/dbus-run-session"
	printf '#!/bin/sh\nexit 1\n' >"$bin/pgrep"
	printf '#!/bin/sh\necho x\n' >"$bin/gsettings"
	printf '#!/bin/sh\necho "busctl $*" >>"%s"\nexit "${BUSCTL_RC:-0}"\n' "$BATS_TEST_TMPDIR/busctl.log" >"$bin/busctl"
	chmod +x "$bin"/*
	: >"$BATS_TEST_TMPDIR/dconf.log"
	RUN() { PATH="$bin:$PATH" XDG_SESSION_DESKTOP=rpios-look-wayland DBUS_SESSION_BUS_ADDRESS=unix:path=/x bash "$BATS_TEST_TMPDIR/set" "$@"; }
}

@test "rpios-look-set knows the Wayland session by its name, or by labwc's session variables" {
	make_wl_set
	out=$(RUN --show)
	grep -qx 'Session        Raspberry Pi Desktop on Wayland' <<<"$out"
	grep -qx 'Windows        PiXtrix' <<<"$out"
	out=$(PATH="$bin:$PATH" XDG_SESSION_DESKTOP="" WAYLAND_DISPLAY=wayland-0 DESKTOP_SESSION=rpd-labwc bash "$BATS_TEST_TMPDIR/set" --show)
	grep -qx 'Session        Raspberry Pi Desktop on Wayland' <<<"$out"
	# The X session
	out=$(PATH="$bin:$PATH" XDG_SESSION_DESKTOP=rpios-look WAYLAND_DISPLAY="" bash "$BATS_TEST_TMPDIR/set" --show)
	run ! grep -q Wayland <<<"$out"
}

@test "rpios-look-set in the Wayland session: --theme pix refuses, exit 2, nothing written" {
	make_wl_set
	run RUN --theme pix
	[ "$status" = 2 ]
	[ "$output" = "rpios-look-set: PiX is an X theme (Raspbian Stretch); log in to Raspberry Pi Desktop (X) to use it" ]
	[ ! -e "$XDG_CONFIG_HOME" ]
	[ ! -s "$BATS_TEST_TMPDIR/dconf.log" ]
}

@test "rpios-look-set in the Wayland session: --theme writes labwc's theme block, the cursor and the session's own GSettings, and the X session's look with it" {
	make_wl_set
	c=$XDG_CONFIG_HOME
	# Your own labwc settings
	mkdir -p "$c/labwc"
	printf '%s\n' '<?xml version="1.0"?>' '<openbox_config xmlns="http://openbox.org/3.4/rc">' '  <keyboard>' '    <keybind key="W-t"><action name="Execute" command="foot" /></keybind>' \
		'  </keyboard>' '</openbox_config>' >"$c/labwc/rc.xml"
	echo 'XKB_DEFAULT_LAYOUT=fr' >"$c/labwc/environment"
	run RUN --theme pixonyx
	[ "$status" = 0 ]
	set_theme pixonyx
	[ "$(rc_theme "$c/labwc/rc.xml")" = PiXonyx ]
	[ "$(grep -c '<name>Nunito Sans</name>' "$c/labwc/rc.xml")" = 4 ]
	[ "$(grep -c '<weight>Light</weight>' "$c/labwc/rc.xml")" = 4 ]
	[ "$(grep -c '<theme>' "$c/labwc/rc.xml")" = 1 ]
	grep -q 'command="foot"' "$c/labwc/rc.xml"
	[ "$(tail -n 1 "$c/labwc/rc.xml")" = '</openbox_config>' ]
	grep -qx 'XKB_DEFAULT_LAYOUT=fr' "$c/labwc/environment"
	grep -qx "XCURSOR_THEME=$T_ICONS" "$c/labwc/environment"
	grep -q "^$share/dconf/profile-wayland load /org/gnome/desktop/interface/" "$BATS_TEST_TMPDIR/dconf.log"
	grep -qx "gtk-theme='PiXonyx'" "$BATS_TEST_TMPDIR/dconf.log"
	grep -qx "color-scheme='prefer-dark'" "$BATS_TEST_TMPDIR/dconf.log"
	# One look for both sessions: the X session's files and GSettings too
	grep -q "^$share/dconf/profile load /org/gnome/desktop/interface/" "$BATS_TEST_TMPDIR/dconf.log"
	grep -qx 'sNet/ThemeName=PiXonyx' "$c/lxsession/rpd-x/desktop.conf"
	[ "$(rc_theme "$c/openbox/$OB_FILE")" = PiXonyx ]
	grep -qx 'wallpaper=.*' "$c/pcmanfm/rpd-x/desktop-items-0.conf"
	# Again: one theme block, one cursor line
	RUN --theme pixtrix >/dev/null
	[ "$(grep -c '<theme>' "$c/labwc/rc.xml")" = 1 ]
	# Not the title bar's buttons: labwc would add them to the session's
	run ! grep -q '<titlebar>' "$c/labwc/rc.xml"
	[ "$(rc_theme "$c/labwc/rc.xml")" = PiXtrix ]
	[ "$(grep -c '^XCURSOR_THEME=' "$c/labwc/environment")" = 1 ]
	# --reset: the theme block and cursor go, your settings stay
	RUN --reset >/dev/null
	run ! grep -q '<theme>' "$c/labwc/rc.xml"
	grep -q 'command="foot"' "$c/labwc/rc.xml"
	run ! grep -q XCURSOR_THEME "$c/labwc/environment"
	grep -qx 'XKB_DEFAULT_LAYOUT=fr' "$c/labwc/environment"
	grep -q "^$share/dconf/profile-wayland reset /org/gnome/desktop/interface/gtk-theme" "$BATS_TEST_TMPDIR/dconf.log"
	grep -q "^$share/dconf/profile reset /org/gnome/desktop/interface/gtk-theme" "$BATS_TEST_TMPDIR/dconf.log"
	grep -qx 'sNet/ThemeName=PiXtrix' "$c/lxsession/rpd-x/desktop.conf"
	[ ! -e "$c/openbox/$OB_FILE" ]
	# --animations is the X session's: said, and stored for it
	run RUN --animations off
	[ "$status" = 0 ] && [[ $output == *"applies to the X session"* ]]
	grep -qx 'iGtk/EnableAnimations=0' "$c/lxsession/rpd-x/desktop.conf"
}

@test "rpios-look-set in the X session: --theme and --reset write the Wayland session's look too; PiX leaves it its theme" {
	make_wl_set
	c=$XDG_CONFIG_HOME
	XRUN() { PATH="$bin:$PATH" XDG_SESSION_DESKTOP=rpios-look WAYLAND_DISPLAY="" DBUS_SESSION_BUS_ADDRESS=unix:path=/x bash "$BATS_TEST_TMPDIR/set" "$@"; }
	run XRUN --theme pixonyx
	[ "$status" = 0 ]
	grep -qx 'sNet/ThemeName=PiXonyx' "$c/lxsession/rpd-x/desktop.conf"
	[ "$(rc_theme "$c/labwc/rc.xml")" = PiXonyx ]
	set_theme pixonyx
	grep -qx "XCURSOR_THEME=$T_ICONS" "$c/labwc/environment"
	grep -q "^$share/dconf/profile-wayland load /org/gnome/desktop/interface/" "$BATS_TEST_TMPDIR/dconf.log"
	grep -q "^$share/dconf/profile load /org/gnome/desktop/interface/" "$BATS_TEST_TMPDIR/dconf.log"
	# PiX: the X session's only
	: >"$BATS_TEST_TMPDIR/dconf.log"
	run XRUN --theme pix
	[ "$status" = 0 ]
	[[ $output == *"PiX is an X theme (Raspbian Stretch): the Wayland session keeps its theme."* ]]
	grep -qx 'sNet/ThemeName=PiX' "$c/lxsession/rpd-x/desktop.conf"
	[ "$(rc_theme "$c/labwc/rc.xml")" = PiXonyx ]
	run ! grep -q "^$share/dconf/profile-wayland " "$BATS_TEST_TMPDIR/dconf.log"
	# --reset: both
	run XRUN --reset
	[ "$status" = 0 ]
	[ ! -e "$c/labwc/rc.xml" ]
	grep -q "^$share/dconf/profile-wayland reset /org/gnome/desktop/interface/gtk-theme" "$BATS_TEST_TMPDIR/dconf.log"
	# --animations alone: the Wayland session's files stay as they are
	: >"$BATS_TEST_TMPDIR/dconf.log"
	run XRUN --animations off
	[ "$status" = 0 ]
	[ ! -e "$c/labwc" ] || [ ! -e "$c/labwc/rc.xml" ]
	[ ! -s "$BATS_TEST_TMPDIR/dconf.log" ]
}

@test "rpios-look-set in the Wayland session: Large and Larger write the large window theme" {
	make_wl_set large
	# Without the large window theme installed: the theme itself
	run RUN --theme pixonyx
	[ "$status" = 0 ]
	[ "$(rc_theme "$XDG_CONFIG_HOME/labwc/rc.xml")" = PiXonyx ]
	# With it: the large one
	mkdir -p "$XDG_DATA_HOME/themes/PiXonyx_l/openbox-3"
	: >"$XDG_DATA_HOME/themes/PiXonyx_l/openbox-3/themerc"
	run RUN --theme pixonyx
	[ "$status" = 0 ]
	[ "$(rc_theme "$XDG_CONFIG_HOME/labwc/rc.xml")" = PiXonyx_l ]
	grep -q 'pixonyx) gtk=PiXonyx wm_theme=PiXonyx_l ' "$BATS_TEST_TMPDIR/set"
}

@test "rpios-look-set --list: no PiX in the Wayland session; PiX in the X session" {
	make_wl_set
	run RUN --list
	[[ $output == "Themes (--theme): "* ]]
	[[ " $output " == *" pixonyx "* ]]
	[[ " $output " != *" pix "* ]]
	out=$(PATH="$bin:$PATH" XDG_SESSION_DESKTOP=rpios-look WAYLAND_DISPLAY="" bash "$BATS_TEST_TMPDIR/set" --list)
	[[ " $out " == *" pix "* ]]
}

@test "rpios-look-set --session x|wayland: the next login's session, through AccountsService, else ~/.dmrc" {
	make_wl_set
	l=$BATS_TEST_TMPDIR/busctl.log
	run RUN --session x
	[ "$status" = 0 ]
	[ "$output" = "Your next login starts Raspberry Pi Desktop (X)." ]
	grep -q "SetXSession s rpios-look$" "$l"
	grep -q "SetSession s rpios-look$" "$l"
	# Nothing else changes
	[ ! -e "$XDG_CONFIG_HOME" ]
	[ ! -s "$BATS_TEST_TMPDIR/dconf.log" ]
	: >"$l"
	run RUN --session wayland
	[ "$status" = 0 ]
	[ "$output" = "Your next login starts Raspberry Pi Desktop (Wayland)." ]
	grep -q "SetXSession s rpios-look-wayland$" "$l"
	grep -q "SetSession s rpios-look-wayland$" "$l"
	# Without AccountsService: ~/.dmrc
	BUSCTL_RC=1 RUN --session wayland >/dev/null
	grep -qx 'Session=rpios-look-wayland' "$HOME/.dmrc"
	BUSCTL_RC=1 RUN --session x >/dev/null
	grep -qx 'Session=rpios-look' "$HOME/.dmrc"
	[ "$(grep -c '^Session=' "$HOME/.dmrc")" = 1 ]
	# The Wayland session not installed; an unknown session
	rm "$r/usr/share/wayland-sessions/rpios-look-wayland.desktop"
	run RUN --session wayland
	[ "$status" = 1 ]
	[[ $output == *"not installed"* ]]
	run RUN --session gnome
	[ "$status" = 1 ]
}

# The user's files of the session, in a test home folder
wl_home() {
	export HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/config XDG_DATA_HOME=$BATS_TEST_TMPDIR/home/data \
		XDG_STATE_HOME=$BATS_TEST_TMPDIR/home/state
	c=$XDG_CONFIG_HOME
	mkdir -p "$c/labwc" "$c/kanshi" "$XDG_STATE_HOME/rpios-look"
	# rpios-look-set's record of the labwc files, made before its first change
	printf 'file:config/labwc/rc.xml\nfile:config/labwc/environment\n' >"$XDG_STATE_HOME/rpios-look/keys"
}
# A user's labwc file: THEME's block and, with KEYS, the user's own key
# Usage: user_rc THEME [KEYS]
user_rc() {
	mkdir -p "$c/labwc"
	{
		printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<openbox_config xmlns="http://openbox.org/3.4/rc">'
		printf '  <theme>\n    <name>%s</name>\n    <font place="ActiveWindow">\n      <name>Nunito Sans</name>\n    </font>\n  </theme>\n' "$1"
		[ -z "${2:-}" ] || printf '%s\n' '  <keyboard>' '    <keybind key="W-t"><action name="Execute" command="foot" /></keybind>' '  </keyboard>'
		printf '</openbox_config>\n'
	} >"$c/labwc/rc.xml"
}

@test "has_session_settings: the Wayland session's files count; the user's own labwc theme does not" {
	wl_home
	run ! has_session_settings
	user_rc Adwaita keys
	run ! has_session_settings
	user_rc PiXonyx_l keys
	has_session_settings
	rm "$c/labwc/rc.xml"
	mkdir "$c/wf-panel-pi"
	has_session_settings
	rmdir "$c/wf-panel-pi"
	mkdir -p "$c/dconf"; : >"$c/dconf/rpioslookwayland"
	has_session_settings
}

@test "reset_session_settings: labwc's theme block goes only when it names a PiX theme; the user's other labwc settings stay" {
	wl_home
	# A PiX theme and your own key: the theme block goes, your key stays
	user_rc PiXtrix keys
	printf 'XKB_DEFAULT_LAYOUT=fr\nXCURSOR_THEME=PiXtrix-Debian\n' >"$c/labwc/environment"
	reset_session_settings
	run ! grep -q '<theme>' "$c/labwc/rc.xml"
	run ! grep -q PiXtrix "$c/labwc/rc.xml"
	grep -q 'command="foot"' "$c/labwc/rc.xml"
	grep -q '^<openbox_config' "$c/labwc/rc.xml"
	[ "$(tail -n 1 "$c/labwc/rc.xml")" = '</openbox_config>' ]
	diff "$c/labwc/environment" - <<<'XKB_DEFAULT_LAYOUT=fr'
	# Undone: its record goes, and the next change records the files again
	run ! grep -q labwc "$XDG_STATE_HOME/rpios-look/keys"
	# A theme block of the look only: the file goes
	wl_home
	user_rc PiXonyx_l
	echo 'XCURSOR_THEME=PiXonyx-Debian' >"$c/labwc/environment"
	reset_session_settings
	[ ! -e "$c/labwc/rc.xml" ]
	[ ! -e "$c/labwc/environment" ]
	# Your own theme and cursor stay, even when other settings of the session go
	user_rc Adwaita keys
	echo 'XCURSOR_THEME=Adwaita' >"$c/labwc/environment"
	cp "$c/labwc/rc.xml" "$BATS_TEST_TMPDIR/rc.before"
	mkdir -p "$c/wf-panel-pi"; echo '[panel]' >"$c/wf-panel-pi/wf-panel-pi.ini"
	reset_session_settings
	[ ! -e "$c/wf-panel-pi" ]
	diff "$c/labwc/rc.xml" "$BATS_TEST_TMPDIR/rc.before"
	grep -qx 'XCURSOR_THEME=Adwaita' "$c/labwc/environment"
}

@test "reset_session_settings: kanshi's empty file goes, yours stays; the Wayland dconf database and the panel's folder go" {
	wl_home
	: >"$c/kanshi/config"; : >"$XDG_STATE_HOME/rpios-look/kanshi-created"
	mkdir -p "$c/dconf" "$c/wf-panel-pi"
	: >"$c/dconf/rpioslookwayland"; : >"$c/dconf/user"
	echo '[panel]' >"$c/wf-panel-pi/wf-panel-pi.ini"
	reset_session_settings
	[ ! -e "$c/kanshi/config" ]
	[ ! -e "$c/dconf/rpioslookwayland" ]
	[ -e "$c/dconf/user" ]
	[ ! -e "$c/wf-panel-pi" ]
	# Your kanshi settings
	mkdir -p "$c/kanshi" "$c/wf-panel-pi"
	echo 'profile { output * enable }' >"$c/kanshi/config"
	reset_session_settings
	grep -q profile "$c/kanshi/config"
}

@test "reset_session_settings: the empty kanshi file of a Wayland login is removed even without other settings" {
	wl_home
	# start-wayland created it at the first Wayland login, with its mark; nothing else
	: >"$c/kanshi/config"; : >"$XDG_STATE_HOME/rpios-look/kanshi-created"
	reset_session_settings
	[ ! -e "$c/kanshi/config" ] && [ ! -e "$XDG_STATE_HOME/rpios-look/kanshi-created" ]
	# An empty file of your own (no mark) is not the session's
	mkdir -p "$c/kanshi"; : >"$c/kanshi/config"; rm -f "$XDG_STATE_HOME/rpios-look/keys"
	run ! has_session_settings
	reset_session_settings; [ -e "$c/kanshi/config" ]
}

@test "uninstall: the session-ID regexes accept rpios-look and rpios-look-wayland, not rpios-lookalike" {
	body=$(sed -n '/^uninstall() {$/,/^}$/p' "$SCRIPT")
	# The AccountsService list, its per-key check, the lines removed from a file the install made, and LightDM's dmrc records
	[ "$(grep -c "(\$SESSION_ID|\$WL_SESSION_ID)\\\\\\$" <<<"$body")" = 4 ]
	grep -q "grep -lE '^X?Session=(\$SESSION_ID|\$WL_SESSION_ID)\\\\\$' /var/lib/AccountsService/users/" <<<"$body"
	grep -q "grep -qE \"^\$m=(\$SESSION_ID|\$WL_SESSION_ID)\\\\\$\"" <<<"$body"
	grep -q "grep -lE '^Session=(\$SESSION_ID|\$WL_SESSION_ID)\\\\\$' /var/cache/lightdm/dmrc/" <<<"$body"
	# The patterns, as the shell expands them
	as=$(eval "printf '%s' \"^X?Session=(\$SESSION_ID|\$WL_SESSION_ID)\\\$\"")
	dm=$(eval "printf '%s' \"^Session=(\$SESSION_ID|\$WL_SESSION_ID)\\\$\"")
	m=XSession key=$(eval "printf '%s' \"^\$m=(\$SESSION_ID|\$WL_SESSION_ID)\\\$\"")
	[ "$as" = '^X?Session=(rpios-look|rpios-look-wayland)$' ]
	for re in "$as" "$dm"; do
		grep -qE "$re" <<<'Session=rpios-look'
		grep -qE "$re" <<<'Session=rpios-look-wayland'
		run ! grep -qE "$re" <<<'Session=rpios-lookalike'
		run ! grep -qE "$re" <<<'Session=rpios-look-waylandx'
		run ! grep -qE "$re" <<<'Session=lightdm-xsession'
	done
	grep -qE "$as" <<<'XSession=rpios-look-wayland'
	grep -qE "$key" <<<'XSession=rpios-look-wayland'
	run ! grep -qE "$key" <<<'XSession=rpios-lookalike'
	run ! grep -qE "$key" <<<'Session=rpios-look'
}

@test "choose_session records a previous session that is not ours, also one whose name starts like ours" {
	WORKDIR=$BATS_TEST_TMPDIR log=$BATS_TEST_TMPDIR/log
	_once() { return 0; }
	ok() { :; }
	as_root() { [ "$1" = test ] && return 0; "$@"; }
	busctl() { case $1 in get-property) echo "s \"$PREV\"" ;; *) echo "busctl $*" >>"$log" ;; esac; }
	record_add() { echo "record ${1##*/} $(cat)" >>"$log"; }
	for PREV in rpios-look rpios-look-wayland; do
		: >"$log"; choose_session
		run ! grep -q session-before "$log"
	done
	: >"$log"; PREV=lightdm-xsession; choose_session
	grep -q "record session-before .*XSession	lightdm-xsession" "$log"
	: >"$log"; PREV=rpios-lookalike; choose_session
	grep -q "record session-before .*XSession	rpios-lookalike" "$log"
}

@test "reload_session in the Wayland session: labwc rereads its settings, the panel and the desktop start again" {
	log=$BATS_TEST_TMPDIR/log
	_running() { echo "running $1" >>"$log"; [ "$1" = labwc ]; }
	labwc() { echo "labwc $*" >>"$log"; }
	pkill() { echo "pkill $*" >>"$log"; }
	pcmanfm-pi() { echo "pcmanfm-pi $*" >>"$log"; }
	_running() { echo "running $1" >>"$log"; [ "$1" = labwc ] || [ "$1" = pcmanfm-pi ]; }
	ok() { :; }
	XDG_SESSION_DESKTOP=rpios-look-wayland WAYLAND_DISPLAY=wayland-0 reload_session
	grep -qx 'labwc --reconfigure' "$log"
	grep -q -- '-x wf-panel-pi$' "$log"
	# The desktop rereads its settings; its file manager windows stay open
	grep -qx 'pcmanfm-pi --profile default --reconfigure' "$log"
	run ! grep -q -- '-x pcmanfm-pi$' "$log"
	run ! grep -q openbox "$log"
	# Not in the session (no Wayland display): nothing
	: >"$log"
	XDG_SESSION_DESKTOP=rpios-look-wayland WAYLAND_DISPLAY="" DISPLAY="" reload_session
	[ ! -s "$log" ]
}

@test "Wayland screen lock: Raspberry Pi's key and dialog text (swaylock -p) reach swaylock-pi" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR S_PROFILE=rpd-x S_FM_PROFILE=rpd-x WAYLAND=1 S_PI_FM=1 S_PI_PANEL=1
	local r=$BATS_TEST_TMPDIR/root bin=$BATS_TEST_TMPDIR/fakebin out
	set_theme pixtrix
	_wl_programs "$r"
	sh -n "$r$SHARE/bin/swaylock"
	# Raspberry Pi's build where installed, with its Pi mode
	grep -q 'exec /usr/bin/swaylock-pi "\$@"' "$r$SHARE/bin/swaylock"
	# Debian's otherwise, without -p (which it lacks): run with fake paths
	mkdir -p "$bin"
	sed -e "s|/usr/bin/swaylock-pi|$bin/none|; s|/usr/bin/swaylock|$bin/swaylock|" "$r$SHARE/bin/swaylock" >"$BATS_TEST_TMPDIR/sl"
	printf '#!/bin/sh\necho "args: $*"\n' >"$bin/swaylock"; chmod +x "$bin/swaylock"
	out=$(sh "$BATS_TEST_TMPDIR/sl" -p -f)
	[ "$out" = "args: -f" ]
	# The shutdown dialog's shim names the key as Raspberry Pi's dialog expects
	_session_programs "$r"
	grep -q 'command="swaylock -p"' "$r$SHARE/labwc/rc.xml"
}

@test "Wayland: the terminal key and the power button run the session's own programs; no idle helper, as Raspberry Pi OS starts none" {
	make_wl_set
	rc=$r$SHARE/xdg/labwc/rc.xml
	grep -q 'command="lxterminal"' "$rc" && grep -q "command=\"$SHARE/pwrkey\"" "$rc"
	run ! grep -qE 'lab-sensible-terminal|command="pwrkey"' "$rc"
	run ! grep -qE 'wl-power|swayidle|wlopm' "$r$SHARE/xdg/labwc/autostart"
	[ ! -e "$r$SHARE/wl-power" ]
	# labwc runs with systemd-logind kept off the power key, where that is allowed
	sh -n "$r$SHARE/start-wayland"
	grep -qF 'systemd-inhibit --what=handle-power-key --mode=block true' "$r$SHARE/start-wayland"
	grep -qF "grep -qs 'command=\"$SHARE/pwrkey\"'" "$r$SHARE/start-wayland"
	grep -qx 'exec "$@"' "$r$SHARE/start-wayland"
}

@test "rpios-look-set in the Wayland session: your own labwc theme and cursor are recorded first and come back with --reset" {
	make_wl_set
	c=$XDG_CONFIG_HOME; mkdir -p "$c/labwc"
	printf '%s\n' '<?xml version="1.0"?>' '<openbox_config xmlns="http://openbox.org/3.4/rc">' '  <theme>' '    <name>Mine</name>' '  </theme>' \
		'  <keyboard>' '    <keybind key="W-t"><action name="Execute" command="foot" /></keybind>' '  </keyboard>' '</openbox_config>' >"$c/labwc/rc.xml"
	printf '%s\n' XKB_DEFAULT_LAYOUT=fr XCURSOR_THEME=MyCursor >"$c/labwc/environment"
	cp "$c/labwc/rc.xml" "$BATS_TEST_TMPDIR/rc.orig"
	run RUN --theme pixonyx
	[ "$status" = 0 ] && [ "$(rc_theme "$c/labwc/rc.xml")" = PiXonyx ]
	run ! grep -q MyCursor "$c/labwc/environment"
	# The originals, as the install records the files it changes (--uninstall puts them back)
	st=$HOME/.local/state/rpios-look rel=${c#"$HOME"/}/labwc
	grep -qxF "file:$rel/rc.xml" "$st/keys" && cmp "$st/files/$rel/rc.xml" "$BATS_TEST_TMPDIR/rc.orig"
	grep -qx 'XCURSOR_THEME=MyCursor' "$st/files/$rel/environment"
	# A second change keeps the first record
	run RUN --theme pixtrix
	cmp "$st/files/$rel/rc.xml" "$BATS_TEST_TMPDIR/rc.orig"
	# --reset: your own theme and cursor again, your other settings as they are
	run RUN --reset
	[ "$status" = 0 ] && [ "$(rc_theme "$c/labwc/rc.xml")" = Mine ] && [ "$(grep -c '<theme>' "$c/labwc/rc.xml")" = 1 ]
	grep -q 'command="foot"' "$c/labwc/rc.xml"
	grep -qx 'XCURSOR_THEME=MyCursor' "$c/labwc/environment" && grep -qx 'XKB_DEFAULT_LAYOUT=fr' "$c/labwc/environment"
	# The record is forgotten: a theme of your own set since is the one the next --reset gives back
	run ! grep -q "labwc/" "$st/keys"; [ ! -e "$st/files/$rel/rc.xml" ]
	sed -i 's|<name>Mine</name>|<name>Newer</name>|' "$c/labwc/rc.xml"
	run RUN --theme pixtrix; [ "$(rc_theme "$c/labwc/rc.xml")" = PiXtrix ]
	run RUN --reset; [ "$(rc_theme "$c/labwc/rc.xml")" = Newer ]
}

@test "labwc's environment file whose last line lacks its end: the cursor goes on a line of its own, and --reset leaves the file as it was" {
	make_wl_set
	c=$XDG_CONFIG_HOME; mkdir -p "$c/labwc"
	printf 'XKB_DEFAULT_LAYOUT=de' >"$c/labwc/environment"
	run RUN --theme pixonyx
	[ "$status" = 0 ]
	grep -qx 'XKB_DEFAULT_LAYOUT=de' "$c/labwc/environment" && grep -q '^XCURSOR_THEME=PiX' "$c/labwc/environment"
	run RUN --reset
	[ "$(cat "$c/labwc/environment")" = 'XKB_DEFAULT_LAYOUT=de' ]
	# A root element written as one empty element is opened, not left beside a second one
	printf '<?xml version="1.0"?>\n<labwc_config/>\n' >"$c/labwc/rc.xml"
	run RUN --theme pixtrix
	[ "$(rc_theme "$c/labwc/rc.xml")" = PiXtrix ] && python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$c/labwc/rc.xml"
	run ! grep -q 'openbox_config' "$c/labwc/rc.xml"
}

@test "labwc's own root element (labwc_config) stays: the theme block goes before its end, and the file is still one document" {
	make_wl_set
	c=$XDG_CONFIG_HOME; mkdir -p "$c/labwc"
	printf '%s\n' '<?xml version="1.0"?>' '<labwc_config>' '  <keyboard>' '    <keybind key="W-t"><action name="Execute" command="foot" /></keybind>' '  </keyboard>' '</labwc_config>' >"$c/labwc/rc.xml"
	run RUN --theme pixonyx
	[ "$status" = 0 ] && [ "$(rc_theme "$c/labwc/rc.xml")" = PiXonyx ]
	run ! grep -q 'openbox_config' "$c/labwc/rc.xml"
	[ "$(grep -c '</labwc_config>' "$c/labwc/rc.xml")" = 1 ] && [ "$(tail -n 1 "$c/labwc/rc.xml")" = '</labwc_config>' ]
	python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$c/labwc/rc.xml"
	# --reset: as it was, less nothing of yours
	run RUN --reset
	[ "$status" = 0 ] && grep -q 'command="foot"' "$c/labwc/rc.xml"
	run ! grep -q '<theme>' "$c/labwc/rc.xml"
	python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$c/labwc/rc.xml"
	# The install's own undo too, and a file with nothing but the root goes
	_labwc_put "$c/labwc/rc.xml" '<theme><name>PiXflat</name></theme>'
	[ "$(grep -c '</labwc_config>' "$c/labwc/rc.xml")" = 1 ] && ! _labwc_bare "$c/labwc/rc.xml"
	printf '<?xml version="1.0"?>\n<labwc_config>\n</labwc_config>\n' >"$c/labwc/bare.xml"; _labwc_bare "$c/labwc/bare.xml"
}
