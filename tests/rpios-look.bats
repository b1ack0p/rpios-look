#!/usr/bin/env bats
# Unit tests of rpios-look.sh's decision helpers. They source the script,
# which then defines its functions without running anything, and need no
# root, network or desktop. Run: bats tests/

bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=../rpios-look.sh
	source "$BATS_TEST_DIRNAME/../rpios-look.sh"
	XDG_CACHE_HOME=$BATS_TEST_TMPDIR/cache
	load_releases
}

# Build a small package for the repacking tests and print its path. Usage:
# mkdeb NAME VERSION FIELDS PATH=CONTENT...; FIELDS are control lines, each
# ending with a newline; a CONTENT "ELF:a|b" is an ELF file holding the
# strings a and b, as a program names its libraries and folders; "LINK:x"
# is a link to x.
mkdeb() {
	local name=$1 ver=$2 fields=$3 d=$BATS_TEST_TMPDIR/src/$1 spec path content
	shift 3
	rm -rf -- "$d"; mkdir -p "$d/DEBIAN"
	printf 'Package: %s\nVersion: %s\nArchitecture: amd64\nMaintainer: test <test@localhost>\n%sDescription: test\n test package\n' \
		"$name" "$ver" "$fields" >"$d/DEBIAN/control"
	for spec; do
		path=${spec%%=*} content=${spec#*=}
		mkdir -p "$d/${path%/*}"
		case $content in
			ELF:*) { printf '\177ELF\0'; printf '%s' "${content#ELF:}" | tr '|' '\0'; printf '\0'; } >"$d/$path"; chmod 0755 "$d/$path" ;;
			LINK:*) ln -s "${content#LINK:}" "$d/$path" ;;
			*) printf '%s\n' "$content" >"$d/$path" ;;
		esac
	done
	dpkg-deb --root-owner-group -b "$d" "$BATS_TEST_TMPDIR/$name.deb" >/dev/null
	printf '%s\n' "$BATS_TEST_TMPDIR/$name.deb"
}
# Succeed if a file holds the string, as its own string (between NUL bytes).
# Usage: has_string FILE STRING
has_string() { S=$2 perl -0777 -ne 'exit !/(?<=\0)\Q$ENV{S}\E(?=\0)/' "$1"; }

@test "release order: suite_ge and releases" {
	suite_ge trixie bookworm
	suite_ge bookworm bookworm
	run ! suite_ge bullseye bookworm
	[ "${REL_VER[buster]}" = 10 ] && [ "${REL_VER[trixie]}" = 13 ]
	[ "$(releases | tail -n 1)" = stretch ]
}

@test "unknown or empty release names fail without errors" {
	run ! suite_ge "" bookworm
	run ! suite_ge nosuch bookworm
	suite_ge trixie ""
}

@test "Debian's release table: valid rows only, as data" {
	f=$BATS_TEST_TMPDIR/debian.csv
	cat >"$f" <<'CSV'
version,codename,series,created,release,eol,eol-lts,eol-elts
13,Trixie,trixie,2023-06-10,2025-08-09,2028-08-09,2030-06-30,2035-06-30
14,Forky,forky,2025-08-09
16,Next,next,2027-01-01,2029-06-01,soon,$(touch pwned)
x,Bad,bad,2020-01-01,2021-01-01,,
17,Upper,UPPER,2020-01-01,2021-01-01,,
,Sid,sid,1993-08-16
CSV
	_release_csv "$f"
	[ "${REL_VER[forky]}" = 14 ] && [ "${REL_VER[next]}" = 16 ]
	[ -z "${REL_VER[bad]:-}" ] && [ -z "${REL_VER[UPPER]:-}" ] && [ -z "${REL_VER[sid]:-}" ]
	[ "${REL_DATES[13]}" = "2025-08-09 2028-08-09 2030-06-30" ]
	[ "${REL_DATES[16]}" = "2029-06-01 - -" ]
	[ ! -e pwned ]
	_release_table_ok "$f"
	printf 'version,codename\n13,Trixie,trixie,x' >"$f"
	run ! _release_table_ok "$f"
}

@test "release dates: a row without end dates keeps the dates known before" {
	f=$BATS_TEST_TMPDIR/debian.csv
	printf '%s\n' version,codename,series,created,release,eol,eol-lts 13,Trixie,trixie,2023-06-10,2025-08-09 \
		12,Bookworm,bookworm,2021-08-14,2023-06-10,,soon >"$f"
	_release_csv "$f"
	[ "${REL_DATES[13]}" = "2025-08-09 2028-08-09 2030-06-30" ]
	[ "${REL_DATES[12]}" = "2023-06-10 2026-07-11 2028-06-30" ]
	# A later table still corrects a date
	printf '%s\n' version,codename,series,created,release,eol,eol-lts 13,Trixie,trixie,2023-06-10,2025-08-09,2028-08-10 >"$f"
	_release_csv "$f"
	[ "${REL_DATES[13]}" = "2025-08-09 2028-08-10 2030-06-30" ]
}

@test "the saved release table adds releases named later" {
	mkdir -p "$XDG_CACHE_HOME/rpios-look"
	printf '%s\n' version,codename,series,created,release,eol,eol-lts 16,Later,later,2027-01-01 >"$XDG_CACHE_HOME/rpios-look/debian.csv"
	REL_VER=() REL_DATES=()
	load_releases
	[ "${REL_VER[later]}" = 16 ] && [ "${REL_VER[trixie]}" = 13 ]
	[ "$(releases | head -n 1)" = later ]
}

@test "published versions of the script: parsed as data, compared as numbers" {
	[ "$(printf '#!/bin/bash\nreadonly APP_VERSION="4.10.2"\n' | script_version)" = 4.10.2 ]
	[ -z "$(printf 'readonly APP_VERSION="$(rm -rf /)"\n' | script_version)" ]
	version_newer 4.10.0 4.9.9
	version_newer 4.0.1 4.0.0
	version_newer 5 4.9
	run ! version_newer 4.0.0 4.0.0
	run ! version_newer 3.22.0 4.0.0
	run ! version_newer "" 4.0.0
	run ! version_newer 4.1-rc1 4.0.0
}

@test "only the allowed extra URLs are fetched" {
	curl() { echo "CURL $*"; }
	wget() { echo "WGET $*"; }
	run ! fetch_extra https://example.org/debian.csv 100
	[ -z "$output" ]
	run fetch_extra "$RELEASES_URL" 100
	[[ $output == *"--proto =https"* && $output == *"--max-redirs 0"* && $output == *"--range 0-99"* ]]
}

@test "size presets" {
	for s in small medium large larger; do size_ok "$s"; done
	run ! size_ok huge
	run ! size_ok ""
}

@test "the size and the state are saved once, without a message when there is no record yet" {
	sys=$BATS_TEST_TMPDIR/sys; mkdir -p "$sys"
	eval "$(declare -f save_size save_state | sed "s|\$SYS_DIR|$sys|g")"
	sys_write() { cat >"$1"; echo written >>"$BATS_TEST_TMPDIR/writes"; }
	O_SIZE=large H_CODENAME=x H_SUITE=y H_ARCH=z
	# No record yet: written, with nothing on stderr also where SIGPIPE is ignored
	[ -z "$( (trap '' PIPE; save_size; save_state) 2>&1 )" ]
	[ "$(cat "$sys/options")" = size=large ] && grep -qx "version $APP_VERSION" "$sys/state"
	# Unchanged: not written again
	save_size; save_state
	[ "$(wc -l <"$BATS_TEST_TMPDIR/writes")" = 2 ]
}

@test "shell quoting for messages" {
	[ "$(_q a 'b c' "d'e")" = "a b\\ c d\\'e" ]
}

@test "NetworkManager counts only when it runs the network" {
	installed_version() { case $1 in network-manager) echo 1.0 ;; wicd) echo "${WICD:-}" ;; *) ;; esac; }
	systemctl() { return "${NM_ENABLED:-1}"; }
	nm_runs
	WICD=1.7 NM_ENABLED=1; run ! nm_runs
	WICD=1.7 NM_ENABLED=0; nm_runs
	installed_version() { :; }
	run ! nm_runs
}

@test "the terminal is LXTerminal unless the user chose another" {
	command() { [ "$2" = lxterminal ] && [ -n "${LXT:-}" ]; }
	update-alternatives() { echo "Status: ${MODE:-auto}"; }
	LXT=1; [ "$(_term_cmd)" = lxterminal ]
	LXT=1 MODE=manual; [ "$(_term_cmd)" = x-terminal-emulator ]
	LXT="" MODE=auto; [ "$(_term_cmd)" = x-terminal-emulator ]
}

@test "only Debian's LXDE is accepted" {
	H_LXDE=1; require_lxde
	# shellcheck disable=SC2034  # read by require_lxde
	H_LXDE=0; run ! require_lxde
	[[ $output == *"LXDE only"* ]]
}

@test "--refresh asks for a restart only for services that outlive a logout" {
	b=$'lightdm 1.0\nfonts-piboto 1.0\npixflat-theme 0.24\nxserver-xorg-core 2'
	[ -z "$(reboot_reason "$b" "$b")" ]
	[ -z "$(reboot_reason "$b" "${b/0.24/0.25}")" ]
	[ "$(reboot_reason "$b" "${b/lightdm 1.0/lightdm 1.1}")" = "updated: the login screen" ]
	[ "$(reboot_reason "$b" "$b"$'\npipewire 1\nbluez 5')" = "updated: the sound server, network and Bluetooth services" ]
	[ "$(reboot_reason "$b" "${b/xserver-xorg-core 2/}")" = "updated: the display server" ]
}

@test "no restart without a terminal or with --no-reboot" {
	init_colors
	as_root() { echo "RAN $*"; }
	O_INTERACTIVE=0 run offer_reboot auto test
	[[ $output != *RAN* ]] && [[ $output == *"restart is needed"* ]]
	O_INTERACTIVE=1 O_NO_REBOOT=1 run offer_reboot auto test
	[[ $output != *RAN* ]]
}

@test "--no-reboot is accepted; --download and --offline are not" {
	parse_args --uninstall --no-reboot
	[ "$O_NO_REBOOT" = 1 ] && [ "$O_MODE" = uninstall ]
	run ! parse_args --download
	run ! parse_args --offline
}

@test "Debian 13 and later on amd64 only; 9 to 12 and 32-bit point to the legacy script" {
	host_rank() { echo "$RANK"; }
	RANK=13 H_ARCH=amd64; require_host
	RANK=14 H_ARCH=amd64; require_host
	RANK=12 H_ARCH=amd64 H_PRETTY="Debian GNU/Linux 12 (bookworm)"; run ! require_host
	[[ $output == *rpios-look-legacy.sh* && $output == *"Debian 9 to 12"* && $output == *bookworm* ]]
	RANK=13 H_ARCH=i386; run ! require_host
	[[ $output == *"Debian 13 and later support only 64-bit PCs"* && $output == *i386* && $output == *"rpios-look-legacy.sh"*"up to Debian 12"* ]]
	host_rank() { return 1; }
	run ! require_host
}

@test "a system known to be wrong stops before Debian's release table is downloaded" {
	host_rank() { echo "$RANK"; }
	RANK=12 H_ARCH=amd64; run ! require_host_early
	RANK=13 H_ARCH=i386; run ! require_host_early
	RANK=13 H_ARCH=amd64; require_host_early
	# a release named after the built-in tables passes, for require_host
	host_rank() { return 1; }; H_ARCH=amd64; require_host_early
	# main: no download before the early check
	detect_host() { H_ARCH=amd64 H_PRETTY="Debian GNU/Linux 12 (bookworm)"; }
	host_rank() { echo 12; }
	update_release_table() { echo DOWNLOADED; }
	run main
	[ "$status" -ne 0 ] && [[ $output != *DOWNLOADED* ]]
}

@test "--uninstall runs on any release and architecture; an install stops first" {
	detect_host() { H_ARCH=i386 H_PRETTY="Debian GNU/Linux 10 (buster)"; }
	host_rank() { echo 10; }
	adopt_session() { :; }; start_log() { echo LOGGED; }; risk_warning() { :; }
	update_release_table() { :; }
	uninstall() { echo UNINSTALLED; }
	preflight_tools() { echo CHANGED; }
	look_installed() { :; }
	run main --uninstall
	[ "$status" -eq 0 ] && [[ $output == *UNINSTALLED* ]]
	run main
	[ "$status" -ne 0 ] && [[ $output == *rpios-look-legacy.sh* && $output != *CHANGED* && $output != *LOGGED* ]]
	# Where the look is not installed: nothing changes, no log, no restart
	look_installed() { return 1; }
	run main --uninstall
	[ "$status" -eq 0 ] && [[ $output == *"not installed on this computer: nothing to uninstall"* && $output != *LOGGED* && $output != *UNINSTALLED* ]]
	# Installed: a record in SYS_DIR, or the generated package
	unset -f look_installed; source <(sed -n '/^look_installed()/p' "$BATS_TEST_DIRNAME/../rpios-look.sh")
	ls() { :; }; installed_version() { :; }
	run ! look_installed
	ls() { echo installed-packages; }
	look_installed
	ls() { :; }; installed_version() { [[ $1 != rpios-look-debian ]] || echo 4.0.0; }
	look_installed
}

@test "the Raspberry Pi OS release: the newest with the look, from 13 up to the host's" {
	rpi_populated() { [[ " $PUB " == *" $1 "* ]]; }
	rpi_arches() { echo amd64; }
	H_ARCH=amd64
	host_rank() { echo 13; }
	PUB="bookworm trixie forky"; pick_suite; [ "$H_SUITE" = trixie ]
	host_rank() { echo 14; }
	pick_suite; [ "$H_SUITE" = forky ]
	PUB="bookworm trixie"; pick_suite; [ "$H_SUITE" = trixie ]
	PUB="bookworm"; run ! pick_suite
}

@test "the wallpapers and looks of this and every earlier release, not later ones" {
	WORKDIR=$BATS_TEST_TMPDIR
	index_load() { [[ -f $WORKDIR/index/$1/Packages-$2 ]]; }
	index_names() { sed -n 's/^Package: //p' "$WORKDIR/index/$1/Packages-$2"; }
	_debian_has() { [ "$1" = fonts-debian ]; }
	DESKTOP_KNOWN=0
	mkdir -p "$WORKDIR"/index/{buster,bookworm,trixie,forky}
	printf 'Package: %s\nArchitecture: all\nDescription: x\n\n' rpd-wallpaper cantab-wallpaper >"$WORKDIR/index/buster/Packages-amd64"
	printf 'Package: pixel-wallpaper\nArchitecture: all\nDescription: transitional package\n\n' >>"$WORKDIR/index/buster/Packages-amd64"
	printf 'Package: old-cursors\nArchitecture: all\nDescription: x\n\nPackage: gtk2-engines-pixold\nArchitecture: amd64\nDescription: x\n\n' >>"$WORKDIR/index/buster/Packages-amd64"
	printf 'Package: rpd-wallpaper-4k\nArchitecture: all\nDescription: x\n\nPackage: fonts-debian\nArchitecture: all\nDescription: x\n\n' >"$WORKDIR/index/bookworm/Packages-amd64"
	printf 'Package: rpd-wallpaper-trixie\nArchitecture: all\nDescription: x\n\nPackage: gtk2-engines-pixnew\nArchitecture: amd64\nDescription: x\n\n' >"$WORKDIR/index/trixie/Packages-amd64"
	printf 'Package: rpd-wallpaper-forky\nArchitecture: all\nDescription: x\n\nPackage: forky-cursors\nArchitecture: all\nDescription: x\n\n' >"$WORKDIR/index/forky/Packages-amd64"
	out=$(rpi_pkgs trixie amd64)
	for p in rpd-wallpaper cantab-wallpaper rpd-wallpaper-4k rpd-wallpaper-trixie old-cursors gtk2-engines-pixnew; do grep -qx "$p" <<<"$out"; done
	for p in rpd-wallpaper-forky forky-cursors pixel-wallpaper gtk2-engines-pixold fonts-debian lxpanel-pi; do run ! grep -qx "$p" <<<"$out"; done
}

@test "a release with no look packages still gives the whole set; a set cut short stops the run" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR
	index_load() { [[ -f $WORKDIR/index/$1/Packages-$2 ]]; }
	index_names() { sed -n 's/^Package: //p' "$WORKDIR/index/$1/Packages-$2"; }
	_debian_has() { return 1; }
	pi_apps() { printf '%s\n' lxpanel-pi lpplug-netman; }
	DESKTOP_KNOWN=1
	mkdir -p "$WORKDIR"/index/{stretch,trixie}
	printf 'Package: rpd-wallpaper\nArchitecture: all\nDescription: x\n\n' >"$WORKDIR/index/stretch/Packages-amd64"
	printf 'Package: rpd-wallpaper-trixie\nArchitecture: all\nDescription: x\n\n' >"$WORKDIR/index/trixie/Packages-amd64"
	mapfile -t out < <(rpi_pkgs trixie amd64)
	for p in pixtrix-theme rpd-wallpaper rpd-wallpaper-trixie lxpanel-pi lpplug-netman; do [[ " ${out[*]} " == *" $p "* ]]; done
	out=()
	read_lines out rpi_pkgs trixie amd64
	[ "${out[-1]}" = lpplug-netman ]
	# A producer that stops (die, or a failed command under the script's set
	# -e) before its end. It exits: run ignores set -e in what it calls, even
	# where a function sets it again, so a failed command would not stop it
	half() { echo a; exit 1; }
	run read_lines out half
	[ "$status" -ne 0 ]
	[[ $output == *"half stopped early"* ]]
	none() { :; }
	read_lines out none
	[ "${#out[@]}" = 0 ]
}

@test "a Raspberry Pi OS desktop of a new design is not guessed at" {
	WORKDIR=$BATS_TEST_TMPDIR
	index_load() { :; }
	index_names() { printf '%s\n' $NAMES; }
	index_candidates() { printf '1\tamd64\tf\ts\t1\t%s\n' "$DEPS"; }
	# The release's own package holds the panel's layout
	pi_unpack() { echo "$BATS_TEST_TMPDIR/pi"; }
	mkdir -p "$BATS_TEST_TMPDIR/pi/${PANEL_LAYOUT%/*}"; : >"$BATS_TEST_TMPDIR/pi/$PANEL_LAYOUT"
	NAMES="rpd-x-core lxpanel-pi pcmanfm-pi" DEPS="rpd-common, openbox, lxpanel-pi, lpplug-menu"
	desktop_known trixie amd64
	# Without the layout there, the desktop is not known: no copy of an earlier one stands in
	rm "$BATS_TEST_TMPDIR/pi/$PANEL_LAYOUT"; run ! desktop_known trixie amd64
	: >"$BATS_TEST_TMPDIR/pi/$PANEL_LAYOUT"
	run ! declare -F _pi_panel_builtin
	DEPS="rpd-common, newpanel"; run ! desktop_known forky amd64
	NAMES="rpd-x-core lxpanel-pi" DEPS="lxpanel-pi"; run ! desktop_known forky amd64
}

@test "a Raspberry Pi OS release counts once its look and its desktop are published" {
	rpi_arches() { echo amd64; }; index_names() { printf '%s\n' $NAMES; }; H_ARCH=amd64
	NAMES="pixtrix-icons pixtrix-theme"; run ! rpi_populated forky
	NAMES="pixtrix-icons rpd-x-core"; rpi_populated forky
	NAMES="rpd-x-core"; run ! rpi_populated forky
}

@test "the display key opens LXRandR, as in Debian's LXDE session, where it is installed" {
	SYS_ROOT=$BATS_TEST_TMPDIR/root WORKDIR=$BATS_TEST_TMPDIR S_PI_PANEL=1 USE_NETMAN=0
	mkdir -p "$SYS_ROOT/usr/bin"
	command() { if [ "$2" = lxrandr ]; then [ -x "$SYS_ROOT/usr/bin/lxrandr" ]; else builtin command "$@"; fi; }
	PATH=$SYS_ROOT/usr/bin:$PATH
	rc=$BATS_TEST_TMPDIR/rc.xml
	printf '<openbox_config>\n  <keyboard>\n  </keyboard>\n</openbox_config>\n' >"$rc"
	_openbox_keys "$rc" "$rc"
	run ! grep -q XF86Display "$rc"
	printf '#!/bin/sh\n' >"$SYS_ROOT/usr/bin/lxrandr"; chmod +x "$SYS_ROOT/usr/bin/lxrandr"
	_openbox_keys "$rc" "$rc"
	grep -A2 'key="XF86Display"' "$rc" | grep -q '<command>lxrandr</command>'
	[ "$(grep -c 'key="XF86Display"' "$rc")" = 1 ]
}

@test "keys: Raspberry Pi OS's own, with the session's power button program; no lock key in the X session, as there; none other that neither it nor Debian's LXDE binds" {
	SYS_ROOT=$BATS_TEST_TMPDIR/root WORKDIR=$BATS_TEST_TMPDIR S_PI_PANEL=1 USE_NETMAN=1
	mkdir -p "$SYS_ROOT/usr/bin"
	for p in lxpanelctl-pi gui-runcmd lxtask scrot pishutdown lxterminal dm-tool lxrandr; do printf '#!/bin/sh\n' >"$SYS_ROOT/usr/bin/$p"; done
	chmod +x "$SYS_ROOT/usr/bin"/*
	PATH=$SYS_ROOT/usr/bin:/usr/bin:/bin
	pi=$BATS_TEST_TMPDIR/rpd-rc.xml rc=$BATS_TEST_TMPDIR/rc.xml
	# Raspberry Pi OS 13's file binds the power button to pwrkey, which is not installed
	printf '%s\n' '<openbox_config>' '  <keyboard>' '    <keybind key="XF86PowerOff">' '      <action name="Execute">' \
		'        <command>pwrkey</command>' '      </action>' '    </keybind>' '    <keybind key="C-A-T">' \
		'      <action name="Execute">' '        <command>x-terminal-emulator</command>' '      </action>' '    </keybind>' \
		'  </keyboard>' '</openbox_config>' >"$pi"
	cp "$pi" "$rc"
	_openbox_keys "$rc" "$pi"
	grep -A2 'key="XF86PowerOff"' "$rc" | grep -q "<command>$SHARE/pwrkey</command>"
	grep -A2 'key="C-A-T"' "$rc" | grep -q '<command>lxterminal</command>'
	# LightDM's lock alone is no lock (the session's console can be switched back to)
	run ! grep -qE 'key="C-A-l"|dm-tool' "$rc"
	run ! grep -q "<command>pwrkey</command>" "$rc"
	# Without Raspberry Pi OS's file: its keys over Debian's
	printf '<openbox_config>\n  <keyboard>\n  </keyboard>\n</openbox_config>\n' >"$rc"
	_openbox_keys "$rc"
	for k in Super_L C-Escape A-F2 C-A-B C-A-S C-A-T C-S-Escape Print C-A-End C-A-Delete C-A-W XF86PowerOff; do
		grep -q "key=\"$k\"" "$rc"
	done
	for f in "$rc" "$BATS_TEST_TMPDIR/rpd-rc.xml"; do
		run ! grep -qE 'key="(XF86ScreenSaver|XF86WLAN)"' "$f"
		run ! grep -q wireless-radio "$f"
	done
}

@test "the power button, as Raspberry Pi OS's pwrkey: the Shutdown dialog, shut down on a second press, not on a repeated key event" {
	pwrkey_build "$BATS_TEST_TMPDIR/out"
	bin=$BATS_TEST_TMPDIR/bin log=$BATS_TEST_TMPDIR/log; mkdir -p "$bin"
	w=$BATS_TEST_TMPDIR/pwrkey
	sed "s|/usr/bin/pishutdown|$bin/pishutdown|g" "$BATS_TEST_TMPDIR/out$SHARE/pwrkey" >"$w"; sh -n "$w"
	for p in pishutdown systemctl; do printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$p" "$log" >"$bin/$p"; done
	printf '#!/bin/sh\n[ -z "$DIALOG" ] || echo 4242\n' >"$bin/pgrep"
	printf '#!/bin/sh\necho " $AGE"\n' >"$bin/ps"
	chmod +x "$bin"/*
	# No dialog open: it opens
	DIALOG='' PATH=$bin:$PATH sh "$w"; [ "$(cat "$log")" = "pishutdown " ]
	# Open for a while: a second press shuts down
	: >"$log"; DIALOG=1 AGE=7 PATH=$bin:$PATH sh "$w"; [ "$(cat "$log")" = "systemctl poweroff" ]
	# Just opened (the same press, delivered twice): nothing
	: >"$log"; DIALOG=1 AGE=0 PATH=$bin:$PATH sh "$w"; [ ! -s "$log" ]
	# Without the dialog installed: shut down, as systemd-logind would
	rm "$bin/pishutdown"; : >"$log"; DIALOG='' PATH=$bin:$PATH sh "$w"; [ "$(cat "$log")" = "systemctl poweroff" ]
}

@test "Qt: Raspberry Pi's GTK 2 styles where they fit this Qt, else Debian's GTK 3 platform themes" {
	init_colors
	_debian_has() { return 1; }
	FETCH_PKGS=(pix-theme qt5-style-plugins qt5-gtk2-platformtheme qt6gtk2)
	qt_choose
	[ "$QT_THEME" = gtk2 ] && [ "${FETCH_PKGS[*]}" = "pix-theme qt5-style-plugins qt5-gtk2-platformtheme qt6gtk2" ]
	[ -z "$(qt_debs)" ]
	# A newer Qt (testing): no qt6gtk2 build, so neither GTK 2 style is fetched
	FETCH_PKGS=(pix-theme qt5-style-plugins qt5-gtk2-platformtheme qt5-style-plugin-motif)
	qt_choose >/dev/null
	[ "$QT_THEME" = gtk3 ] && [ "${FETCH_PKGS[*]}" = pix-theme ]
	[ "$(qt_debs | xargs)" = "qt5-gtk-platformtheme qt6-gtk-platformtheme" ]
}

@test "GTK 3 text in the desktop font's weight, as Raspberry Pi's GTK draws it" {
	# The function as session-env has it, run with a session's files
	eval "$(sed -n '/^gtk_weight() {$/,/^}$/p' "$BATS_TEST_DIRNAME/../rpios-look.sh")"
	config=$BATS_TEST_TMPDIR/config share=$BATS_TEST_TMPDIR/share gtkw=$BATS_TEST_TMPDIR/run profile=p
	mkdir -p "$share/data/themes/PiXtrix/gtk-3.0" "$share/data/themes/PiX/gtk-3.0" "$share/xdg/lxsession/p" "$config/lxsession/p"
	touch "$share/data/themes/PiXtrix/gtk-3.0/gtk.css" "$share/data/themes/PiX/gtk-3.0/gtk.css"
	printf '[GTK]\nsGtk/FontName=Nunito Sans Light 12\n' >"$share/xdg/lxsession/p/desktop.conf"
	printf '[GTK]\nsNet/ThemeName=PiX\n' >"$config/lxsession/p/desktop.conf"
	gtk_weight
	css=$gtkw/themes/PiXtrix/gtk-3.0/gtk.css
	grep -qx "@import url(\"$share/data/themes/PiXtrix/gtk-3.0/gtk.css\");" "$css"
	grep -q 'font-weight: 300; font-style: normal;' "$css"
	grep -q 'font-weight: 300;' "$gtkw/themes/PiX/gtk-3.0/gtk.css"
	# The user's own font wins; a light font family without a weight word is normal
	printf '[GTK]\nsGtk/FontName=PibotoLt 12\n' >"$config/lxsession/p/desktop.conf"
	gtk_weight
	grep -q 'font-weight: 400; font-style: normal;' "$css"
	printf '[GTK]\nsGtk/FontName=DejaVu Sans Bold Italic 11\n' >"$config/lxsession/p/desktop.conf"
	gtk_weight
	grep -q 'font-weight: 700; font-style: italic;' "$css"
}

@test "a recorded dependency updated from its file stays automatic; one marked by name before stays manual" {
	log=$BATS_TEST_TMPDIR/log
	# The record of the dependencies the script installed (installed-auto)
	cat() { printf '%s\n' qt5-style-plugin-cleanlooks qt5-style-plugin-motif libfoo; }
	# After the install APT lists both updated plugins and libfoo as manual;
	# libfoo was already marked by name before the run
	apt-mark() { case $1 in showmanual) printf '%s\n' qt5-style-plugin-cleanlooks qt5-style-plugin-motif libfoo pcmanfm ;;
		*) echo "mark $*" >>"$log" ;; esac; }
	as_root() { "$@"; }
	_keep_auto "$(printf '%s\n' libfoo pcmanfm)"
	[ "$(command cat "$log")" = "mark auto qt5-style-plugin-cleanlooks qt5-style-plugin-motif" ]
	# Nothing to change: no call
	rm "$log"
	_keep_auto "$(printf '%s\n' qt5-style-plugin-cleanlooks qt5-style-plugin-motif libfoo pcmanfm)"
	[ ! -e "$log" ]
}

@test "idle and lock as Raspberry Pi OS: no helper, no automatic lock or sleep, nothing outside the session; the power key is the session's only while it runs" {
	WORKDIR=$BATS_TEST_TMPDIR S_PROFILE=$SESSION_PROFILE S_FM_PROFILE=default S_PI_PANEL=1 S_PI_FM=1; _term_cmd() { echo lxterminal; }
	O_SIZE=medium set_theme "pixtrix"
	r=$BATS_TEST_TMPDIR/root
	_session_profile "$r$SHARE/xdg"; _session_programs "$r" 2>/dev/null || true; pwrkey_build "$r"
	# What the session starts: the panel, the desktop and the compositor's starter
	[ "$(xargs <"$r$SHARE/xdg/lxsession/$SESSION_PROFILE/autostart")" = "@$SHARE/panel @$SHARE/desktop @$SHARE/compositor" ]
	grep -qx 'lock_manager/command=lxlock' "$r$SHARE/xdg/lxsession/$SESSION_PROFILE/desktop.conf"
	# No power helper, no settings command, no polkit rule
	[ ! -e "$r$SHARE/power" ] && [ ! -e "$r$SHARE/power.conf" ] && [ ! -e "$r/usr/bin/rpios-look-power" ]
	[ ! -e "$r/usr/share/polkit-1" ] && [ ! -e "$r/var/lib/polkit-1" ]
	run ! grep -qxE 'x11-xserver-utils|libxss1|light-locker' <<<"$(session_debs)"
	# The start script keeps systemd-logind off the power key only where the
	# session's keys bind it, and only where systemd-logind allows it
	grep -qF 'grep -qs "<command>$share/pwrkey</command>"' "$r$SHARE/start"
	grep -qF 'systemd-inhibit --what=handle-power-key --mode=block true' "$r$SHARE/start"
}

@test "the session hides only IBus's tray icon in its own dconf defaults, which IBus reads" {
	WORKDIR=$BATS_TEST_TMPDIR T_DARK=0 T_GTK=PiXtrix T_ICONS=PiXtrix-Debian T_CURSOR_SIZE=24 T_FONT=x T_SOUND_THEME=freedesktop
	dconf() { :; }
	_session_dconf "$BATS_TEST_TMPDIR/root"
	grep -A1 -x '\[desktop/ibus/panel\]' "$WORKDIR/dconf-keys/00-rpios-look" | grep -qx 'show-icon-on-systray=false'
	# IBus starts before the session's start script (70im-config_launch): the
	# session's profile is set before it, for this session only
	x=$BATS_TEST_TMPDIR/root/etc/X11/Xsession.d/60rpios-look_dconf
	[ "$(env -i XDG_SESSION_DESKTOP=rpios-look sh -c ". $x; echo \$DCONF_PROFILE")" = /usr/share/rpios-look/dconf/profile ]
	[ "$(env -i GDMSESSION=rpios-look sh -c ". $x; echo \$DCONF_PROFILE")" = /usr/share/rpios-look/dconf/profile ]
	[ -z "$(env -i XDG_SESSION_DESKTOP=LXDE GDMSESSION=rpios-look sh -c "set -eu; . $x; echo \${DCONF_PROFILE:-}")" ]
	[ -z "$(env -i sh -c "set -eu; . $x; echo \${DCONF_PROFILE:-}")" ]
}

@test "a plain run resets the session's X settings database, its own panel profile or its menu, also when nothing else is there" {
	HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config XDG_DATA_HOME=$BATS_TEST_TMPDIR/home/.local/share
	f=$XDG_CONFIG_HOME
	for p in "dconf/${APP_NAME//-/}" lxpanel/rpd-x/panels "menus/rpd-applications.menu"; do
		rm -rf "$f"; mkdir -p "$(dirname "$f/$p")"; touch "$f/$p"
		has_session_settings
		reset_session_settings
		[ ! -e "$f/$p" ] && ! has_session_settings
	done
}

@test "uninstall: the session choice LightDM wrote into ~/.dmrc goes; its other lines and other sessions stay" {
	HOME=$BATS_TEST_TMPDIR/home; mkdir -p "$HOME"; ok() { :; }
	for id in rpios-look rpios-look-wayland; do
		printf '[Desktop]\nSession=%s\nLanguage=en_US.utf8\n' "$id" >"$HOME/.dmrc"
		forget_dmrc
		[ "$(cat "$HOME/.dmrc")" = "$(printf '[Desktop]\nLanguage=en_US.utf8')" ]
	done
	for id in LXDE rpios-lookalike; do
		printf '[Desktop]\nSession=%s\n' "$id" >"$HOME/.dmrc"
		forget_dmrc
		grep -qx "Session=$id" "$HOME/.dmrc"
	done
	rm "$HOME/.dmrc"; forget_dmrc; [ ! -e "$HOME/.dmrc" ]
}

@test "an install puts the file manager and the desktop back to the session's: the 'default' profile's preferences, desktop files, the bookmarks and the desktop's shortcuts go, your files stay, --uninstall gives back what was there and keeps what you added since" {
	HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config XDG_STATE_HOME=$BATS_TEST_TMPDIR/home/.local/state
	d=$XDG_CONFIG_HOME/pcmanfm/default; mkdir -p "$d" "$HOME/Desktop" "$XDG_CONFIG_HOME/libfm" "$XDG_CONFIG_HOME/pcmanfm/LXDE"
	warn() { :; }; ok() { :; }
	S_PI_FM=1 S_PROFILE=rpd-x S_FM_PROFILE=default
	# Your own from before the look: preferences, a desktop with your wallpaper, a file on the desktop
	printf '[ui]\nwin_width=1200\nview_mode=list\n' >"$d/pcmanfm.conf"
	printf '[*]\nwallpaper=/home/me/photo.jpg\nshow_trash=0\n[note.txt]\nx=300\ny=200\n' >"$d/desktop-items-0.conf"
	echo mine >"$HOME/Desktop/note.txt"
	printf '[ui]\nbig_icon_size=96\n' >"$XDG_CONFIG_HOME/libfm/libfm.conf"; echo keep >"$XDG_CONFIG_HOME/pcmanfm/LXDE/pcmanfm.conf"
	cp "$d/pcmanfm.conf" "$BATS_TEST_TMPDIR/p"; cp "$d/desktop-items-0.conf" "$BATS_TEST_TMPDIR/d0"
	mkdir -p "$XDG_CONFIG_HOME/gtk-3.0"; echo "file://$HOME/Work Work" >"$XDG_CONFIG_HOME/gtk-3.0/bookmarks"; mkdir "$HOME/Work"
	echo 'gtk-theme-name=Mine' >"$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
	# Shortcuts on the desktop: a launcher and a link; a document and a folder beside them
	xdg-user-dir() { return 1; }
	printf '[Desktop Entry]\nType=Application\nName=Game\nExec=game\n' >"$HOME/Desktop/game.desktop"
	ln -s "$HOME/Work" "$HOME/Desktop/work"; mkdir "$HOME/Desktop/Photos"; echo x >"$HOME/Desktop/Photos/a.jpg"; echo y >"$HOME/Work/inside.txt"
	_state_init; reset_file_manager
	# Raspberry Pi OS's desktop has no shortcut: the launcher and the link go, the rest stays
	[ ! -e "$HOME/Desktop/game.desktop" ] && [ ! -L "$HOME/Desktop/work" ]
	[ -f "$HOME/Desktop/Photos/a.jpg" ] && [ "$(cat "$HOME/Work/inside.txt")" = y ]
	[ ! -e "$d/pcmanfm.conf" ] && [ ! -e "$d/desktop-items-0.conf" ]
	# The side pane's bookmarks go; the folders they named and GTK's other settings stay
	[ ! -e "$XDG_CONFIG_HOME/gtk-3.0/bookmarks" ] && [ -d "$HOME/Work" ] && [ -f "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" ]
	# Files and folders, and what Debian's file manager keeps for its own LXDE session
	[ "$(cat "$HOME/Desktop/note.txt")" = mine ]
	grep -qx 'big_icon_size=96' "$XDG_CONFIG_HOME/libfm/libfm.conf"; [ "$(cat "$XDG_CONFIG_HOME/pcmanfm/LXDE/pcmanfm.conf")" = keep ]
	# The session's file manager writes its own since; a later install resets those too
	printf '[ui]\nwin_width=900\n' >"$d/pcmanfm.conf"; printf '[*]\nshow_trash=1\n' >"$d/desktop-items-1.conf"
	# A bookmark added since goes with that install too, and is kept with the one from before
	echo "file://$HOME/Later" >"$XDG_CONFIG_HOME/gtk-3.0/bookmarks"
	reset_file_manager
	[ ! -e "$d/pcmanfm.conf" ] && [ ! -e "$d/desktop-items-1.conf" ] && [ ! -e "$XDG_CONFIG_HOME/gtk-3.0/bookmarks" ]
	# --uninstall: yours from before are back, and nothing of the session's stays
	printf '[ui]\nwin_width=640\n' >"$d/pcmanfm.conf"; printf '[*]\nshow_trash=1\n' >"$d/desktop-items-1.conf"
	# A bookmark and a launcher of the same name, added since the install, stay
	printf 'file://%s/New' "$HOME" >"$XDG_CONFIG_HOME/gtk-3.0/bookmarks"
	printf '[Desktop Entry]\nName=New\n' >"$HOME/Desktop/game.desktop"
	restore_user
	cmp "$d/pcmanfm.conf" "$BATS_TEST_TMPDIR/p" && cmp "$d/desktop-items-0.conf" "$BATS_TEST_TMPDIR/d0"
	[ "$(cat "$XDG_CONFIG_HOME/gtk-3.0/bookmarks")" = "file://$HOME/New"$'\n'"file://$HOME/Work Work"$'\n'"file://$HOME/Later" ]
	grep -qx 'Name=New' "$HOME/Desktop/game.desktop" && grep -qx 'Name=Game' "$HOME/Desktop/game.desktop.~1~"
	[ "$(readlink "$HOME/Desktop/work")" = "$HOME/Work" ]
	[ ! -e "$XDG_STATE_HOME/rpios-look" ]
	[ ! -e "$d/desktop-items-1.conf" ]
	# Without Raspberry Pi's file manager the 'default' profile is not the session's
	printf '[ui]\nwin_width=1200\n' >"$d/pcmanfm.conf"; rm "$XDG_CONFIG_HOME/libfm/libfm.conf"
	_state_init; S_PI_FM=0 S_FM_PROFILE=rpd-x reset_file_manager
	grep -qx 'win_width=1200' "$d/pcmanfm.conf"
}

@test "an install sets your own power settings for the session aside: the power-times and light-locker start entries and the swayidle lines of labwc's start file; an entry that only hides light-locker and your other entries stay; --uninstall puts them back" {
	HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config XDG_STATE_HOME=$BATS_TEST_TMPDIR/home/.local/state
	a=$XDG_CONFIG_HOME/autostart; mkdir -p "$a" "$XDG_CONFIG_HOME/labwc" "$HOME/Desktop"
	warn() { echo "warn: $*"; }; ok() { :; }; xdg-user-dir() { return 1; }
	printf '[Desktop Entry]\nName=Power times\nExec=xset s 300\n' >"$a/power-times.desktop"
	printf '[Desktop Entry]\nName=Screen Locker\nExec=light-locker --lock-after-screensaver=60\n' >"$a/light-locker.desktop"
	printf '[Desktop Entry]\nName=Mine\nExec=mine\n' >"$a/mine.desktop"
	# A swayidle command that goes on over three lines, between two other commands
	printf 'kanshi &\nswayidle -w \\\n\ttimeout 300 x \\\n\tresume y &\nfoot &\n' >"$XDG_CONFIG_HOME/labwc/autostart"
	cp "$XDG_CONFIG_HOME/labwc/autostart" "$BATS_TEST_TMPDIR/as"
	_state_init; reset_power
	[ ! -e "$a/power-times.desktop" ] && [ ! -e "$a/light-locker.desktop" ] && [ -f "$a/mine.desktop" ]
	# The whole command goes, not only its first line; the other commands stay
	[ "$(cat "$XDG_CONFIG_HOME/labwc/autostart")" = 'kanshi &'$'\n''foot &' ]
	# An entry that only hides light-locker is Debian's LXDE's own: it stays
	printf '[Desktop Entry]\nName=Screen Locker\nHidden=true\n' >"$a/light-locker.desktop"
	# The same command written again, and one with no options: a later install takes both, and keeps the first once
	sed -n 2,4p "$BATS_TEST_TMPDIR/as" >>"$XDG_CONFIG_HOME/labwc/autostart"; echo swayidle >>"$XDG_CONFIG_HOME/labwc/autostart"
	echo swayidle >>"$BATS_TEST_TMPDIR/as"
	reset_power; grep -qx 'Hidden=true' "$a/light-locker.desktop"
	[ "$(cat "$XDG_CONFIG_HOME/labwc/autostart")" = 'kanshi &'$'\n''foot &' ]
	# One of the two commands is written again by hand since
	echo swayidle >>"$XDG_CONFIG_HOME/labwc/autostart"
	# --uninstall: the entries are back, the earlier light-locker entry beside the one there now
	restore_user
	grep -qx 'Exec=xset s 300' "$a/power-times.desktop" && grep -qx 'Hidden=true' "$a/light-locker.desktop"
	grep -q 'lock-after-screensaver=60' "$a/light-locker.desktop.~1~" && [ -f "$a/mine.desktop" ]
	# The other command is back whole, after what is there; the one written again is there once
	[ "$(cat "$XDG_CONFIG_HOME/labwc/autostart")" = 'kanshi &'$'\n''foot &'$'\n''swayidle'$'\n'"$(sed -n 2,4p "$BATS_TEST_TMPDIR/as")" ]
	[ ! -e "$XDG_STATE_HOME/rpios-look" ]
}

@test "the swayidle commands of a start file: each whole and once; one that the other file has already is left out, also one whose last line there ends in a backslash" {
	local d=$BATS_TEST_TMPDIR
	printf 'foot &\nswayidle -w \\\n' >"$d/have"
	printf 'swayidle -w \\\n\ttimeout 3 x &\nswayidle\nswayidle\nidle &\n' >"$d/new"
	[ "$(_swayidle_cmds "$d/have" "$d/new")" = 'swayidle -w \'$'\n\t''timeout 3 x &'$'\n''swayidle' ]
	[ "$(_swayidle_cmds "$d/new" "$d/new")" = "" ] && [ "$(_swayidle_cmds /dev/null "$d/have")" = 'swayidle -w \' ]
	# Two that differ only in the spaces their lines begin with are one
	printf '  swayidle -w \\\n  timeout 3 x &\n\tswayidle\n' >"$d/have"
	[ "$(_swayidle_cmds "$d/have" "$d/new")" = "" ] && [ "$(_swayidle_cmds /dev/null "$d/have" | wc -l)" = 3 ]
	printf 'foot &\nswayidle -w \\\n' >"$d/have"
	# With one file: what is left of it
	[ "$(_swayidle_cmds "$d/new")" = 'idle &' ] && [ "$(_swayidle_cmds "$d/have")" = 'foot &' ]
}

@test "a shortcut on the desktop that cannot be moved gets a warning and stays; the install goes on" {
	HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config XDG_STATE_HOME=$BATS_TEST_TMPDIR/home/.local/state
	mkdir -p "$HOME/Desktop" "$XDG_CONFIG_HOME"
	warn() { echo "warn: $*"; }; ok() { :; }; info() { echo "info: $*"; }; xdg-user-dir() { return 1; }
	S_PI_FM=1 S_PROFILE=rpd-x S_FM_PROFILE=default
	echo a >"$HOME/Desktop/stuck.desktop"; echo b >"$HOME/Desktop/free.desktop"
	mv() { case "$*" in *stuck.desktop*) return 1 ;; esac; command mv "$@"; }
	_state_init; run reset_file_manager
	[ "$status" -eq 0 ]
	[[ $output == *"warn: could not move stuck.desktop"* && $output == *"info: 1 shortcuts"* ]]
	[ -f "$HOME/Desktop/stuck.desktop" ] && [ ! -e "$HOME/Desktop/free.desktop" ]
}

@test "the size's terminal font goes into the user's LXTerminal settings, as Raspberry Pi OS does; medium and --uninstall put the font back" {
	HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config XDG_STATE_HOME=$BATS_TEST_TMPDIR/home/.local/state
	SYS_ROOT=$BATS_TEST_TMPDIR/sys; mkdir -p "$HOME" "$SYS_ROOT/usr/share/lxterminal"
	printf '[general]\nfontname=Monospace 10\nscrollback=1000\n' >"$SYS_ROOT/usr/share/lxterminal/lxterminal.conf"
	f=$XDG_CONFIG_HOME/lxterminal/lxterminal.conf
	warn() { :; }
	# Medium, nothing changed before: the file is left alone
	_state_init; O_SIZE=medium term_font; [ ! -e "$f" ]
	# No settings yet: the terminal's defaults, with the size's font
	O_SIZE=large T_TERM_FONT="Monospace 15" term_font
	grep -qx 'fontname=Monospace 15' "$f" && grep -qx 'scrollback=1000' "$f"
	O_SIZE=medium term_font; grep -qx 'fontname=Monospace 10' "$f"
	restore_user; [ ! -e "$f" ]
	# Your own settings: only the font changes, and comes back
	mkdir -p "${f%/*}"; printf '[general]\nfontname=Hack 11\ncursorblinks=true\n' >"$f"; cp "$f" "$BATS_TEST_TMPDIR/orig"
	_state_init; O_SIZE=larger T_TERM_FONT="Monospace 20" term_font
	grep -qx 'fontname=Monospace 20' "$f" && grep -qx 'cursorblinks=true' "$f"
	O_SIZE=medium term_font; grep -qx 'fontname=Hack 11' "$f"
	O_SIZE=small T_TERM_FONT="Monospace 8" term_font; grep -qx 'fontname=Monospace 8' "$f"
	restore_user; cmp "$f" "$BATS_TEST_TMPDIR/orig"
	# A change of yours after the install stays; only the font goes back
	_state_init; O_SIZE=large T_TERM_FONT="Monospace 15" term_font
	sed -i 's/^cursorblinks=true$/cursorblinks=false/' "$f"
	restore_user; grep -qx 'fontname=Hack 11' "$f" && grep -qx 'cursorblinks=false' "$f"
	# A file the install made, changed since: kept, with the default font
	rm -f "$f"; _state_init; O_SIZE=large T_TERM_FONT="Monospace 15" term_font
	printf 'geometry_columns=100\n' >>"$f"
	restore_user; grep -qx 'fontname=Monospace 10' "$f" && grep -qx 'geometry_columns=100' "$f"
	# An install sets it, and --refresh when --size is given
	grep -qx '	if \[\[ \$O_MODE != refresh \]\] || (( O_SIZE_GIVEN )); then term_font; fi' "$BATS_TEST_DIRNAME/../rpios-look.sh"
}

@test "labwc's files of the user's: a clean install and --uninstall undo only a look's theme block and cursor, giving back the user's own" {
	HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config XDG_STATE_HOME=$BATS_TEST_TMPDIR/home/.local/state
	XDG_DATA_HOME=$HOME/.local/share; ok() { :; }; warn() { :; }
	f=$XDG_CONFIG_HOME/labwc st=$XDG_STATE_HOME/rpios-look rel=.config/labwc
	mkdir -p "$f" "$st/files/$rel"
	# The record (rpios-look-set's wl_track): the user's theme on one line, and
	# a cursor of their own
	printf '<?xml version="1.0"?>\n<openbox_config>\n  <theme><name>Mine</name></theme>\n  <keyboard/>\n</openbox_config>\n' >"$st/files/$rel/rc.xml"
	printf 'XKB_DEFAULT_LAYOUT=de\nXCURSOR_THEME=MyCursor\n' >"$st/files/$rel/environment"
	printf 'file:%s/rc.xml\nfile:%s/environment\n' "$rel" "$rel" >"$st/keys"; : >"$st/created"
	[ "$(_theme_block "$st/files/$rel/rc.xml")" = '<theme><name>Mine</name></theme>' ]
	# Now: a look's theme and cursor, and keybinds the user added since
	printf '<?xml version="1.0"?>\n<openbox_config>\n  <keyboard/>\n  <keybind key="W-x"/>\n  <theme>\n    <name>PiXonyx</name>\n  </theme>\n</openbox_config>\n' >"$f/rc.xml"
	printf 'XKB_DEFAULT_LAYOUT=de\nXCURSOR_THEME=PiXonyx\nMY_VAR=1\n' >"$f/environment"
	_labwc_undo
	grep -q 'keybind key="W-x"' "$f/rc.xml" && grep -q '<theme><name>Mine</name></theme>' "$f/rc.xml"
	run ! grep -q PiXonyx "$f/rc.xml"
	[ "$(grep -c '<theme>' "$f/rc.xml")" = 1 ] && [ "$(grep -c '</openbox_config>' "$f/rc.xml")" = 1 ]
	grep -qx 'XCURSOR_THEME=MyCursor' "$f/environment" && grep -qx 'MY_VAR=1' "$f/environment"
	# Once undone, again changes nothing
	cp "$f/rc.xml" "$BATS_TEST_TMPDIR/rc1"; _labwc_undo; cmp "$f/rc.xml" "$BATS_TEST_TMPDIR/rc1"
	# --uninstall: the same, never the whole file back
	printf '<?xml version="1.0"?>\n<openbox_config>\n  <keybind key="W-y"/>\n  <theme><name>PiXflat</name></theme>\n</openbox_config>\n' >"$f/rc.xml"
	restore_user
	grep -q 'keybind key="W-y"' "$f/rc.xml" && grep -q '<name>Mine</name>' "$f/rc.xml" && [ ! -d "$st" ]
	# Without a record, rpios-look-set never wrote them: nothing changes
	printf '<?xml version="1.0"?>\n<openbox_config>\n  <theme>\n    <name>PiXtrix</name>\n  </theme>\n</openbox_config>\n' >"$f/rc.xml"
	cp "$f/rc.xml" "$BATS_TEST_TMPDIR/rc2"; _labwc_undo; cmp "$f/rc.xml" "$BATS_TEST_TMPDIR/rc2"
	# Recorded as made by rpios-look-set: a file with nothing else goes, and
	# the record with it
	mkdir -p "$st"; printf 'file:%s/rc.xml\n' "$rel" >"$st/keys"; printf '%s/rc.xml\n' "$rel" >"$st/created"
	_labwc_undo; [ ! -e "$f/rc.xml" ] && ! grep -q labwc "$st/keys"
}

@test "an APT run that did not finish: what it installed is found by the next run and by --uninstall" {
	local sys=$BATS_TEST_TMPDIR/sys; mkdir -p "$sys"
	eval "$(declare -f _installing_new _installing_end | sed "s|\$SYS_DIR|$sys|g")"
	SYS_DIR_T=$sys
	installed_names() { printf '%s\n' a b c d; }
	[ -z "$(_installing_new)" ]
	# The plan of the APT run: b, d and e; b and d were installed, and c
	# came from somewhere else
	printf '%s\n' b d e >"$sys/installing"
	[ "$(_installing_new | tr '\n' ' ')" = "b d " ]
	as_root() { "$@"; }; _record_names() { printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/rec"; }
	_installing_end
	[ "$(cat "$BATS_TEST_TMPDIR/rec" | tr '\n' ' ')" = "b d " ] && [ ! -e "$sys/installing" ]
	# --uninstall reads them with the records
	grep -q 'mapfile -t -O "${#pkgs\[@\]}" pkgs < <(_installing_new)' "$BATS_TEST_DIRNAME/../rpios-look.sh"
}

@test "beside_tidy removes nothing when other packages would change with it" {
	TWINS=(openbox) BESIDE=()
	log=$BATS_TEST_TMPDIR/purged
	dpkg-query() { printf '%s\n' 'ii  rpios-look-oldpkg'; }; info() { :; }; _purge() { echo PURGED >"$log"; }
	_safe_purge_set() { return 1; }
	run beside_tidy
	[ "$status" -ne 0 ] && [ ! -e "$log" ] && [[ $output == *"would change other packages"*"--uninstall"* ]]
	# APT cannot work it out: said so, nothing removed
	_safe_purge_set() { return 2; }
	run beside_tidy
	[ "$status" -ne 0 ] && [ ! -e "$log" ] && [[ $output == *"cannot work out"* ]]
	_safe_purge_set() { printf '%s\n' "$@"; }
	run beside_tidy
	[ "$status" -eq 0 ] && [ -s "$log" ]
}

@test "uninstall: the network and Bluetooth tools the install added go without asking; kept packages keep only their record" {
	s=$BATS_TEST_DIRNAME/../rpios-look.sh
	for p in network-manager wpasupplicant iw wireless-regdb rfkill dnsmasq-base bluez libspa-0.2-bluetooth pulseaudio-module-bluetooth; do
		[[ $p =~ ^($NET_PKGS_RE)$ ]]
	done
	run ! eval '[[ network-manager-gnome =~ ^($NET_PKGS_RE)$ ]]'
	run ! eval '[[ firmware-iwlwifi =~ ^($NET_PKGS_RE)$ ]]'
	# Every package that tray_debs can add is covered
	has_wifi() { :; }; has_bluetooth() { :; }; installed_version() { case $1 in pipewire|pulseaudio) echo 1 ;; esac; }
	for p in $(USE_NETMAN=1 tray_debs); do [[ $p =~ ^($NET_PKGS_RE)$ ]]; done
	grep -q '! -name packages-before ! -name installed-packages' "$s"
	# One APT run with the packages agreed on, so what only the tools need goes too
	grep -qF '_remove_recorded "${pkgs[@]}" "${net[@]}"' "$s"
}

@test "GTK's toolbar icon size follows the size, as the Appearance Settings set it" {
	WORKDIR=$BATS_TEST_TMPDIR
	O_SIZE=small set_theme pixtrix; [ "$T_TB_SIZE" = 2 ]
	O_SIZE=medium set_theme pixtrix; [ "$T_TB_SIZE" = 3 ]
	O_SIZE=large set_theme pixtrix; [ "$T_TB_SIZE" = 6 ]
	O_SIZE=larger set_theme pixtrix; [ "$T_TB_SIZE" = 6 ]
}

@test "Raspberry Pi's file manager reads the session's pcmanfm.conf after Debian's" {
	r=$BATS_TEST_TMPDIR/root S_PI_FM=1 S_PI_WM=0; _term_cmd() { echo lxterminal; }
	_session_programs "$r" 2>/dev/null || true
	w=$r$SHARE/bin/pcmanfm-pi; [ -x "$w" ]
	bin=$BATS_TEST_TMPDIR/bin; mkdir -p "$bin"
	sed "s|/usr/bin/pcmanfm-pi|$bin/fm|" "$w" >"$BATS_TEST_TMPDIR/w"; printf '#!/bin/sh\necho "$XDG_CONFIG_DIRS"\n' >"$bin/fm"; chmod +x "$bin/fm"
	[ "$(XDG_CONFIG_DIRS=$SHARE/xdg:/etc/xdg sh "$BATS_TEST_TMPDIR/w")" = "$SHARE/xdg:/etc/xdg:$SHARE/xdg" ]
}

@test "the session's file manager and desktop fall back to Debian's when Raspberry Pi's is gone" {
	r=$BATS_TEST_TMPDIR/root S_PI_FM=1 S_PROFILE=rpd-x S_FM_PROFILE=default; _term_cmd() { echo lxterminal; }
	_session_programs "$r" 2>/dev/null || true
	# Decided by the program itself, not by the session's wrapper of that name
	grep -qx "if \[ -x /usr/bin/pcmanfm-pi \]; then exec $SHARE/bin/pcmanfm-pi \"\$@\"; fi" "$r$SHARE/bin/pcmanfm"
	grep -qx 'exec /usr/bin/pcmanfm "$@"' "$r$SHARE/bin/pcmanfm"
	grep -qx "if \[ -x /usr/bin/pcmanfm-pi \]; then exec $SHARE/bin/pcmanfm-pi --desktop --profile default; fi" "$r$SHARE/desktop"
	run ! grep -rq 'command -v pcmanfm-pi' "$r$SHARE"
}

@test "a purge that would install another alternative keeps the member it stands in for, and removes the rest" {
	# APT's plan: purging pipewire-audio would install pulseaudio (pavucontrol
	# needs one of them); without it, the others go cleanly
	apt-get() {
		if [[ " $* " == *" pipewire-audio "* ]]; then printf 'Inst pulseaudio (1 Debian:13/stable [amd64])\nPurg pipewire-audio [1]\nPurg pix-theme [1]\n'
		else for p in "${@:3}"; do echo "Purg $p [1]"; done; fi
	}
	dpkg-query() { printf '%s\n' ', libc6, pulseaudio | pipewire-audio:any (>= 1)' ', libc6'; }
	[ "$(_safe_purge_set pix-theme pipewire-audio rpd-icons | xargs)" = "pix-theme rpd-icons" ]
	# An alternative of no member: not safe, as before
	dpkg-query() { printf '%s\n' ', libc6'; }
	run _safe_purge_set pix-theme pipewire-audio
	[ "$status" = 1 ] && [ -z "$output" ]
}

@test "APT: the Raspberry Pi archive pinned to the look, no check before installing, a check after dpkg that names missing look packages" {
	WORKDIR=$BATS_TEST_TMPDIR r=$BATS_TEST_TMPDIR/root bin=$BATS_TEST_TMPDIR/bin; mkdir -p "$bin"
	note() { :; }; resolve_pkg() { return 1; }; PIN_PKGS=(pixflat-theme)
	apt_files "$r"
	grep -q 'DPkg::Post-Invoke' "$r$APT_HOOK"
	run ! grep -qE 'Pre-Install|Post-Invoke-Success|file:' "$r$APT_HOOK"
	[ ! -e "$r$APT_SRC" ]   # no key: no source, updates through --refresh
	c=$BATS_TEST_TMPDIR/apt-check
	sed "s|$SYS_DIR|$BATS_TEST_TMPDIR/sys|g" "$r$SHARE/apt-check" >"$c"; chmod +x "$c"
	mkdir -p "$BATS_TEST_TMPDIR/sys"; printf 'pixflat-theme\nlpplug-clock\n' >"$BATS_TEST_TMPDIR/sys/look-packages"
	printf '#!/bin/sh\nexit 1\n' >"$bin/pgrep"
	printf '#!/bin/sh\n[ "$3" = pixflat-theme ] && printf "ii " && exit 0\nexit 1\n' >"$bin/dpkg-query"; chmod +x "$bin"/*
	run env PATH="$bin:$PATH" "$c"
	[ "$status" = 0 ] && [[ $output == *"no longer installed: lpplug-clock."* ]] && [[ $output != *pixflat-theme* ]]
	# Quiet while the script itself runs
	printf '#!/bin/sh\nexit 0\n' >"$bin/pgrep"
	run env PATH="$bin:$PATH" "$c"
	[ "$status" = 0 ] && [ -z "$output" ]
	sh -n "$r$SHARE/apt-check"
}

@test "the panel leaves out the GPU monitor, which reads only a Raspberry Pi's GPU" {
	USE_NETMAN=1; [[ "|$(panel_drop)|" == *"|gpu|"* ]]
	USE_NETMAN=0; [[ "|$(panel_drop)|" == *"|gpu|"* && "|$(panel_drop)|" == *"|netman|"* ]]
}

@test "GSettings and GTK 2 as Raspberry Pi OS's Appearance Settings sets them for the size, in the session only" {
	WORKDIR=$BATS_TEST_TMPDIR; dconf() { :; }
	O_SIZE=large set_theme pixtrix
	_session_dconf "$BATS_TEST_TMPDIR/root"
	k=$WORKDIR/dconf-keys/00-rpios-look
	grep -qx "monospace-font-name='Monospace 15'" "$k" && grep -qx "toolbar-icons-size='large'" "$k"
	run ! grep -q '^document-font-name=' "$k"
	O_SIZE=medium set_theme pixtrix; rm -rf "$WORKDIR/dconf-keys"
	_session_dconf "$BATS_TEST_TMPDIR/root"
	# Medium: large, as the Appearance Settings leave it (their "medium" is
	# no value of the key); Small: small
	grep -qx "monospace-font-name='Monospace 10'" "$k" && grep -qx "toolbar-icons-size='large'" "$k"
	O_SIZE=small set_theme pixtrix; rm -rf "$WORKDIR/dconf-keys"
	_session_dconf "$BATS_TEST_TMPDIR/root"; grep -qx "toolbar-icons-size='small'" "$k"
	# GTK 2's scrollbars for the large sizes: the session's own file, before yours
	S_PI_FM=1 S_PI_PANEL=1 S_PROFILE=rpd-x S_FM_PROFILE=default; _term_cmd() { echo lxterminal; }
	r=$BATS_TEST_TMPDIR/r1; O_SIZE=large set_theme pixtrix; _session_programs "$r"
	grep -q 'GtkRange::slider-width = 17' "$r$SHARE/gtkrc-2.0"
	grep -qF "export GTK2_RC_FILES=\"/etc/gtk-2.0/gtkrc:$SHARE/gtkrc-2.0:\$HOME/.gtkrc-2.0\"" "$r$SHARE/session-env"
	r=$BATS_TEST_TMPDIR/r2; O_SIZE=medium set_theme pixtrix; _session_programs "$r"
	[ ! -e "$r$SHARE/gtkrc-2.0" ] && run ! grep -q GTK2_RC_FILES "$r$SHARE/session-env"
}

@test "settings-keeper: a file read half written is never merged; rpios-look-set writes at once" {
	settings_keeper_build "$BATS_TEST_TMPDIR/root"
	K=$BATS_TEST_TMPDIR/root$SHARE/settings-keeper python3 -I - <<'PY'
import importlib.machinery, importlib.util, os
loader = importlib.machinery.SourceFileLoader("keeper", os.environ["K"])
k = importlib.util.module_from_spec(importlib.util.spec_from_loader("keeper", loader))
loader.exec_module(k)
prev = "[GTK]\nsNet/ThemeName=PiXonyx\n\n[Mouse]\nLeftHanded=0\n\n[Session]\nwindow_manager=openbox\n"
# lxsession's write-back: its login-time look, and a session change
back = "[GTK]\nsNet/ThemeName=PiXtrix\n\n[Mouse]\nLeftHanded=0\n\n[Session]\nwindow_manager=openbox-lxde\n"
assert k.merge(prev, back) == prev.replace("=openbox\n", "=openbox-lxde\n")
# Read half written, in the middle of a line or at a line's end
for cut in ("[GTK]\nsNet/ThemeName=PiXtrix\n\n[Mou", "[GTK]\nsNet/ThemeName=PiXtrix\n", ""):
    assert not k.whole(prev, cut) and k.merge(prev, cut) is None, cut
assert k.whole(prev, back) and k.whole("", back)
# A file with only some settings (Appearance Settings creates one) gets the
# session's others; its own stay, and a complete file is left as it is
part = "[GTK]\nsNet/ThemeName=PiXtrix\n"
done = k.complete(part, prev)
assert done == "[GTK]\nsNet/ThemeName=PiXtrix\n\n[Mouse]\nLeftHanded=0\n\n[Session]\nwindow_manager=openbox\n", done
assert k.complete(done, prev) is None and k.complete(prev, prev) is None
assert k.complete("[GTK]\nsNet/Theme", prev) is None
PY
	# rpios-look-set replaces the file at once (a rename), through a link too
	eval "$(sed -n '/^replace() {/,/^get() {/p' "$BATS_TEST_DIRNAME/../rpios-look.sh")"
	die() { echo "$*"; return 1; }
	d=$BATS_TEST_TMPDIR/cfg; mkdir -p "$d/real"
	printf '[GTK]\nsNet/ThemeName=PiXtrix\n\n[Session]\nx=1\n' >"$d/real/desktop.conf"
	chmod 0640 "$d/real/desktop.conf"
	ln -s real/desktop.conf "$d/desktop.conf"
	ino=$(stat -c %i "$d/real/desktop.conf")
	edit "$d/desktop.conf" /dev/null ini_edit GTK sNet/ThemeName=PiXonyx
	[ -L "$d/desktop.conf" ] && [ "$(stat -c %i "$d/real/desktop.conf")" != "$ino" ] && [ "$(stat -c %a "$d/real/desktop.conf")" = 640 ]
	[ "$(ini_get "$d/desktop.conf" GTK sNet/ThemeName)" = PiXonyx ] && [ "$(ini_get "$d/desktop.conf" Session x)" = 1 ]
	edit "$d/desktop.conf" /dev/null ini_edit Session x
	[ -z "$(ini_get "$d/desktop.conf" Session x)" ] && grep -qx '\[Session\]' "$d/desktop.conf"
	# The first change makes the user's copy from the session's file
	edit "$d/new/desktop.conf" "$d/real/desktop.conf" ini_edit Session x=2
	[ "$(ini_get "$d/new/desktop.conf" Session x)" = 2 ]
	[ "$(ini_get "$d/new/desktop.conf" GTK sNet/ThemeName)" = PiXonyx ]
	[ -z "$(ini_get "$d/real/desktop.conf" Session x)" ]
	[ "$(ls -A "$d/real" "$d/new" | grep -c desktop.conf)" = 2 ] && [ "$(ls -A "$d/real" | wc -l)" = 1 ]
	# Several changes to one section at once: set, add, remove; a new section
	printf '[A]\nk=1\nz=0\n\n[B]\nk=2\n' >"$d/i.conf"
	edit "$d/i.conf" /dev/null ini_edit A k=3 n=a=b z
	edit "$d/i.conf" /dev/null ini_edit C k=4
	diff "$d/i.conf" - <<<$'[A]\nk=3\n\nn=a=b\n[B]\nk=2\n\n[C]\nk=4'
}

# The generated rpios-look-set, with the session's files in a test folder
# and no session running; its dconf calls and file renames are logged
make_set() {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR S_PROFILE=rpd-x S_FM_PROFILE=rpd-x
	r=$BATS_TEST_TMPDIR/root
	set_theme pixtrix
	_session_command "$r"
	share=$r$SHARE bin=$BATS_TEST_TMPDIR/bin
	sed "s|^APP=\(.*\) SHARE=$SHARE |APP=\1 SHARE=$share |" "$r/usr/bin/rpios-look-set" >"$BATS_TEST_TMPDIR/set"
	grep -q "SHARE=$share " "$BATS_TEST_TMPDIR/set"
	mkdir -p "$share/xdg/lxsession/rpd-x" "$share/xdg/pcmanfm/rpd-x" "$share/dconf" "$bin"
	printf '[GTK]\nsNet/ThemeName=PiXtrix\n\n[Mouse]\nLeftHanded=0\n' >"$share/xdg/lxsession/rpd-x/desktop.conf"
	printf '[*]\nwallpaper=/w.jpg\n' >"$share/xdg/pcmanfm/rpd-x/desktop-items-0.conf"
	mkdir -p "$share/xdg/openbox"
	printf '%s\n' '<openbox_config xmlns="http://openbox.org/3.4/rc">' '  <keyboard>' '    <keybind key="C-A-T"/>' '  </keyboard>' \
		'  <theme>' '    <name>PiXtrix</name>' '    <roundCorners>no</roundCorners>' '    <animateIconify>yes</animateIconify>' \
		'    <font place="ActiveWindow">' '      <name>Nunito Sans</name>' '    </font>' '  </theme>' '</openbox_config>' \
		>"$share/xdg/openbox/$OB_FILE"
	: >"$share/dconf/profile"
	export HOME=$BATS_TEST_TMPDIR/home XDG_DATA_HOME=$BATS_TEST_TMPDIR/home/data XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/config
	for t in PiXtrix PiXonyx; do mkdir -p "$XDG_DATA_HOME/themes/$t/gtk-3.0" "$XDG_DATA_HOME/icons/$t-Debian"
		: >"$XDG_DATA_HOME/themes/$t/gtk-3.0/gtk.css"; : >"$XDG_DATA_HOME/icons/$t-Debian/index.theme"; done
	printf '#!/bin/sh\necho "$DCONF_PROFILE $*" >>"%s"\n[ "$1" != load ] || cat >>"%s"\n' "$BATS_TEST_TMPDIR/dconf.log" "$BATS_TEST_TMPDIR/dconf.log" >"$bin/dconf"
	printf '#!/bin/sh\necho private >>"%s"; shift; exec "$@"\n' "$BATS_TEST_TMPDIR/dconf.log" >"$bin/dbus-run-session"
	printf '#!/bin/sh\nexit 1\n' >"$bin/pgrep"
	printf '#!/bin/sh\nfor f; do :; done; echo "${f##*/}" >>"%s"; exec /bin/mv "$@"\n' "$BATS_TEST_TMPDIR/mv.log" >"$bin/mv"
	chmod +x "$bin"/*
}

@test "rpios-look-set: one change writes each file once, at once" {
	make_set
	c=$XDG_CONFIG_HOME
	for o in "--theme pixonyx --animations off" "--theme pixtrix" --reset; do
		: >"$BATS_TEST_TMPDIR/mv.log"
		# shellcheck disable=SC2086  # options and their values
		PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" $o >/dev/null
		ob=$OB_FILE; [ "$o" != --reset ] || ob=""
		LC_ALL=C sort "$BATS_TEST_TMPDIR/mv.log" | diff - <(printf '%s\n' desktop-items-0.conf desktop.conf $ob)
		grep -qx LeftHanded=0 "$c/lxsession/rpd-x/desktop.conf"
	done
	grep -qx sNet/ThemeName=PiXtrix "$c/lxsession/rpd-x/desktop.conf"
	[ "$(grep -c EnableAnimations "$c/lxsession/rpd-x/desktop.conf")" = 0 ]
	# The reset leaves Openbox with the session's settings, without a file of yours
	[ ! -e "$c/openbox/$OB_FILE" ]
}

@test "rpios-look-set: your Openbox file holds the window theme only, over the session's settings; Debian's Openbox gets a copy" {
	make_set
	c=$XDG_CONFIG_HOME/openbox/$OB_FILE pi=$BATS_TEST_TMPDIR/openbox-pi
	sed -i "s|/usr/bin/openbox-pi|$pi|" "$BATS_TEST_TMPDIR/set"
	# Raspberry Pi's Openbox: the theme section only, as Appearance Settings writes
	printf '#!/bin/sh\n' >"$pi"; chmod +x "$pi"
	PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --theme pixonyx --animations off >/dev/null
	run ! grep -q keyboard "$c"
	grep -qx '    <name>PiXonyx</name>' "$c" && grep -qx '      <name>Nunito Sans</name>' "$c"
	grep -qx '    <animateIconify>no</animateIconify>' "$c"
	grep -q '^<openbox_config xmlns="http://openbox.org/3.4/rc">$' "$c" && [ "$(tail -n 1 "$c")" = '</openbox_config>' ]
	out=$(PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --show); grep -qx "Windows        PiXonyx" <<<"$out"
	# Your own file is changed, not replaced by the session's
	sed -i 's|</openbox_config>|  <desktops><number>2</number></desktops>\n&|' "$c"
	PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --theme pixtrix >/dev/null
	grep -q '<number>2</number>' "$c" && grep -qx '    <name>PiXtrix</name>' "$c"
	PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --reset >/dev/null
	[ ! -e "$c" ]
	out=$(PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --show); grep -qx "Windows        PiXtrix" <<<"$out"
	# Debian's Openbox reads one file: all of the session's settings
	rm "$pi"
	PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --theme pixonyx >/dev/null
	grep -q '<keybind key="C-A-T"/>' "$c" && grep -qx '    <name>PiXonyx</name>' "$c"
}

@test "the session's Openbox settings are where Raspberry Pi's Openbox reads them; login never writes your file" {
	WORKDIR=$BATS_TEST_TMPDIR S_PROFILE=rpd-x S_FM_PROFILE=rpd-x S_PI_PANEL=1 S_PI_FM=1
	r=$BATS_TEST_TMPDIR/root
	_session_programs "$r"
	grep -qx "exec $SHARE/bin/openbox --config-file \"\${XDG_CONFIG_HOME:-\$HOME/.config}/openbox/$OB_FILE\" \"\$@\"" "$r$SHARE/openbox"
	# The start script never writes the user's Openbox file
	run ! grep -q 'config/openbox' "$r$SHARE/start"
	run ! grep -q '<keyboard>' "$r$SHARE/start"
}

@test "rpios-look-set: the session's GSettings follow the theme, in its own dconf only" {
	make_set
	# No session runs: dconf writes through a private D-Bus
	env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR=/nonexistent PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --theme pixonyx >/dev/null
	# With D-Bus; light again, back to the session's defaults, and no change
	for o in "--theme pixtrix" --reset "--animations off"; do
		# shellcheck disable=SC2086  # an option and its value
		PATH="$bin:$PATH" DBUS_SESSION_BUS_ADDRESS=unix:path=/x bash "$BATS_TEST_TMPDIR/set" $o >/dev/null
	done
	p=$share/dconf/profile d=/org/gnome/desktop/interface/
	set_theme pixonyx; i=$T_ICONS f=$T_FONT
	set_theme pixtrix
	diff "$BATS_TEST_TMPDIR/dconf.log" - <<LOG
private
$p load $d
[/]
gtk-theme='PiXonyx'
icon-theme='$i'
cursor-theme='$i'
font-name='$f'
color-scheme='prefer-dark'
$p load $d
[/]
gtk-theme='PiXtrix'
icon-theme='PiXtrix-Debian'
cursor-theme='PiXtrix-Debian'
font-name='$T_FONT'
color-scheme='prefer-light'
$p reset ${d}gtk-theme
$p reset ${d}icon-theme
$p reset ${d}cursor-theme
$p reset ${d}font-name
$p reset ${d}color-scheme
LOG
}

@test "rpios-look-set with dconf: the session's own database changes, the user's main one does not" {
	command -v dconf >/dev/null && command -v dbus-run-session >/dev/null || skip "dconf or D-Bus is not installed"
	make_set
	rm "$bin/dconf" "$bin/dbus-run-session"
	# The session's defaults, as the install writes them
	set_theme pixtrix
	_session_dconf "$r"
	printf 'user-db:rpioslook\nfile-db:%s/dconf/settings\n' "$share" >"$share/dconf/profile"
	export XDG_RUNTIME_DIR=$BATS_TEST_TMPDIR/run
	mkdir -m 0700 "$XDG_RUNTIME_DIR"
	q() { DCONF_PROFILE=$share/dconf/profile dconf read "/org/gnome/desktop/interface/$1"; }
	# As on a fresh Raspberry Pi OS 13: the schema's default (no override)
	[ "$(q color-scheme)" = "'default'" ]
	[ "$(q gtk-theme)" = "'PiXtrix'" ]
	env -u DBUS_SESSION_BUS_ADDRESS PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --theme pixonyx >/dev/null 2>&1
	set_theme pixonyx
	[ "$(q gtk-theme)" = "'PiXonyx'" ]
	[ "$(q icon-theme)" = "'$T_ICONS'" ]
	[ "$(q cursor-theme)" = "'$T_ICONS'" ]
	[ "$(q font-name)" = "'$T_FONT'" ]
	[ "$(q color-scheme)" = "'prefer-dark'" ]
	[ -s "$XDG_CONFIG_HOME/dconf/rpioslook" ]
	[ ! -e "$XDG_CONFIG_HOME/dconf/user" ]
	env -u DBUS_SESSION_BUS_ADDRESS PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --reset >/dev/null 2>&1
	[ "$(q gtk-theme)" = "'PiXtrix'" ]
	[ "$(q icon-theme)" = "'PiXtrix-Debian'" ]
	[ "$(q color-scheme)" = "'default'" ]
	[ ! -e "$XDG_CONFIG_HOME/dconf/user" ]
}

@test "uninstall: Qt libraries go only when nothing needs them; one you installed by name stays" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR log=$BATS_TEST_TMPDIR/log
	# The install marked the dependencies automatic; you then installed
	# libqt5gui5t64 by name, and a program of yours needs libqt5core5t64
	cat() { printf '%s\n' libqt5core5t64 libqt5gui5t64 qt5-gtk2-platformtheme; }
	apt-mark() { case $1 in showmanual) shift; for p; do [[ $p =~ ^(libqt5gui5t64|qt5-style-plugins)$ ]] && echo "$p"; done; return 0 ;;
		*) echo "mark $*" >>"$log" ;; esac; }
	_safe_purge_set() { for p; do [ "$p" = libqt5core5t64 ] || echo "$p"; done; }
	_purge() { echo "purge $*" >>"$log"; }
	as_root() { "$@"; }
	record_add() { echo "record ${1##*/} $(paste -sd' ')" >>"$log"; }
	ROOT_PKGS=(qt5-style-plugins) HW_PKGS=()
	_record_installed qt5-style-plugins libqt5core5t64
	diff "$log" - <<LOG
mark auto libqt5core5t64
record installed-auto libqt5core5t64
record installed-packages qt5-style-plugins libqt5core5t64
LOG
	rm "$log"
	_remove_recorded qt5-style-plugins qt5-gtk2-platformtheme libqt5core5t64 libqt5gui5t64 >/dev/null
	diff "$log" - <<LOG
purge qt5-style-plugins qt5-gtk2-platformtheme
mark auto libqt5core5t64
LOG
}

@test "every purge goes through _purge, which keeps running services until the restart" {
	# The only apt-get purge is _purge's own; APT's simulations do not count
	f=$BATS_TEST_DIRNAME/../rpios-look.sh
	[ "$(grep -c 'apt-get purge' "$f")" = 1 ]
	grep -q 'apt-get purge' <(sed -n '/^_purge() {$/,/^}$/p' "$f")
	# It denies service actions while it runs, where the system has no policy of its own
	[ ! -e /usr/sbin/policy-rc.d ] || skip "this system has its own policy-rc.d"
	WORKDIR=$BATS_TEST_TMPDIR log=$BATS_TEST_TMPDIR/log POLICY_RC=""
	as_root() { echo "$*" >>"$log"; }
	sys_write() { cat >"$BATS_TEST_TMPDIR/policy"; echo "write $1" >>"$log"; }
	_purge -q pkg-a pkg-b
	grep -qx 'write /usr/sbin/policy-rc.d' "$log"
	grep -qx 'exit 101' "$BATS_TEST_TMPDIR/policy"
	grep -q 'apt-get purge .* -q pkg-a pkg-b$' "$log"
	[ "$(tail -n 1 "$log")" = "rm -f -- /usr/sbin/policy-rc.d" ] && [ -z "$POLICY_RC" ]
}

@test "the package's scripts update and remove the caches of its own icon sets only" {
	WORKDIR=$BATS_TEST_TMPDIR SYS_ROOT=$BATS_TEST_TMPDIR/sys
	mkdir -p "$SYS_ROOT/usr/share/icons/PiXflat" && touch "$SYS_ROOT/usr/share/icons/PiXflat/index.theme"
	for f in logo_badge_build session_build settings_keeper_build compositor_build pwrkey_build wallpaper_links apt_files login_build; do eval "$f() { :; }"; done
	gen_icon_overlay() { mkdir -p "$2"; }; gen_logo_overlay() { mkdir -p "$3"; }; installed_version() { :; }
	build_deb() { cp "$1/DEBIAN/postinst" "$1/DEBIAN/postrm" "$WORKDIR/"; }
	build_pkg
	[ "$(grep -o '/usr/share/icons/[A-Za-z-]*' "$WORKDIR/postinst" | sort -u | xargs)" = "/usr/share/icons/PiXflat-Debian /usr/share/icons/PiXnoir-Debian" ]
	[ "$(grep -o '/usr/share/icons/[A-Za-z-]*' "$WORKDIR/postrm" | sort -u | xargs)" = "/usr/share/icons/PiXflat-Debian /usr/share/icons/PiXnoir-Debian" ]
	# Nothing else on the system is changed
	run ! grep -qE 'dpkg-divert|readlink|rm -f /usr/(s?bin|lib)' "$WORKDIR/postinst"
}

@test "a package that cannot be adapted stops the run; a refused one is left out with a note" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR FETCH_PKGS=(gui-runcmd) APT_PKGS=() NOTES=()
	PKG_VER[gui-runcmd]=1
	as_root() { :; }; installed_version() { :; }; sys_write() { cat >/dev/null; }
	download_pkg() { echo "$WORKDIR/$1.deb"; }
	_debian_has() { [[ $1 == bash ]]; }
	for f in compat_fix wall_own_dir; do eval "$f() { printf '%s\\n' \"\$1\"; }"; done
	mkdir -p "$WORKDIR/x/DEBIAN"
	printf 'Package: gui-runcmd\nVersion: 1\nArchitecture: all\nMaintainer: x <x@x>\nConflicts: bash\nDescription: x\n' >"$WORKDIR/x/DEBIAN/control"
	dpkg-deb -b "$WORKDIR/x" "$WORKDIR/gui-runcmd.deb" >/dev/null 2>&1
	# A repack that fails stops before APT
	bt_pin_entry() { die "fakeroot is required to build packages with this version of dpkg"; }
	run install_all
	[ "$status" -ne 0 ]
	[[ $output == *"gui-runcmd could not be prepared"* && $output != *"Installing packages"* ]]
	# A package that would change Debian's is refused: left out, with a note
	bt_pin_entry() { printf '%s\n' "$1"; }
	run adapt_deb "$WORKDIR/gui-runcmd.deb"
	[ "$status" -eq 0 ]
	[[ $output == *"gui-runcmd is left out"*"Conflicts:bash"* && $output != *.deb* ]]
	run install_all
	[ "$status" -eq 0 ] && [[ $output == *"Left out, as they would change Debian's packages or files: gui-runcmd"* ]]
}

@test "a package that needs one that did not resolve is left out, and so on up" {
	init_colors
	H_SUITE=trixie H_ARCH=amd64
	FETCH_PKGS=(a b c) IN_SET=([a]=1 [b]=1 [c]=1 [x]=1)
	PKG_VER=([a]=1 [b]=1 [c]=1) PKG_DEPS=([a]="b" [b]="x (>= 1)" [c]="libc6 (>= 2)")
	AVAIL=([x]="" [libc6]="2.41")
	drop_unmet 2>"$BATS_TEST_TMPDIR/err"
	[ "${FETCH_PKGS[*]}" = c ]
	grep -q '^. a is left out' "$BATS_TEST_TMPDIR/err" && grep -q '^. b is left out' "$BATS_TEST_TMPDIR/err"
}

@test "--refresh finds the recorded packages no longer in the look" {
	cat() { printf '%s\n' theme debian-dep lxplug-old gone rpios-look-lxplug-old rpios-look-debian; }
	installed_version() { [ "$1" != gone ] && echo 1; }
	apt_versions() { [[ $1 == debian-dep ]] && echo 1 || true; }
	FETCH_PKGS=(theme) APT_PKGS=()
	# Raspberry Pi OS's, and the repacked ones; Debian's stay, and so does the session package
	[ "$(stale_pkgs | paste -sd' ')" = "lxplug-old rpios-look-lxplug-old" ]
	# Not one installed before the first install
	grep() { [[ $3 == lxplug-old ]]; }
	[ "$(stale_pkgs | paste -sd' ')" = "rpios-look-lxplug-old" ]
	unset -f grep
	# Nothing of the look needs AccountsService: it is never asked for
	run ! grep -q 'accountsservice)' <(sed -n '/^resolve_all() {$/,/^}$/p' "$BATS_TEST_DIRNAME/../rpios-look.sh")
}

@test "--refresh never offers what the look depends on, installed or not, directly or not" {
	init_colors
	cat() { printf '%s\n' qt5-style-plugins qt5-gtk2-platformtheme qt5-style-plugin-motif libqt5-rpi lxplug-old; }
	installed_version() { echo 1; }
	apt_versions() { :; }
	# qt5-style-plugins (installed) needs qt5-gtk2-platformtheme, which needs libqt5-rpi
	dpkg-query() { printf 'ii \tqt5-style-plugins\t, qt5-gtk2-platformtheme (= 5), x | qt5-style-plugin-motif:amd64\nii \tqt5-gtk2-platformtheme\t, libqt5-rpi (>= 5)\nii \tlxplug-old\t, libc6\n'; }
	FETCH_PKGS=(qt5-style-plugins) APT_PKGS=() PKG_DEPS=()
	[ "$(stale_pkgs | paste -sd' ')" = lxplug-old ]
	# A package of the set not installed yet: its index entry names them
	dpkg-query() { printf 'ii \tqt5-gtk2-platformtheme\t, libqt5-rpi\n'; }
	FETCH_PKGS=(qt5-style-plugins) PKG_DEPS=([qt5-style-plugins]="qt5-gtk2-platformtheme, qt5-style-plugin-motif")
	[ "$(stale_pkgs | paste -sd' ')" = lxplug-old ]
}

@test "the magnifier: plugin and program installed, the plugin off the panel, never offered as stale" {
	pi_unpack() { return 1; }
	has_battery() { :; }
	index_names() { printf '%s\n' $NAMES; }
	index_candidates() { printf '1\tamd64\tf\ts\t1\t%s\n' "lxpanel-pi, lpplug-menu, lpplug-magnifier, lpplug-updater, lpplug-netman, lpplug-cpu"; }
	USE_NETMAN=0 NAMES="lpplug-magnifier mage-rpi mage"
	out=$(pi_apps trixie amd64)
	grep -qx lpplug-magnifier <<<"$out" && grep -qx mage-rpi <<<"$out" && grep -qx lpplug-cpu <<<"$out"
	run ! grep -qxE 'mage|lpplug-(updater|netman)' <<<"$out"
	# Without its program, the plugin is not installed either
	NAMES="lpplug-magnifier"
	out=$(pi_apps trixie amd64)
	grep -qx lpplug-cpu <<<"$out"
	run ! grep -qxE 'lpplug-magnifier|mage-rpi' <<<"$out"
	# Not in the panel layout, as Raspberry Pi OS shows it only with its program
	SYS_ROOT=$BATS_TEST_TMPDIR/root S_PI_FM=0
	mkdir -p "$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanel-pi"
	for t in magnifier cpu; do : >"$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanel-pi/$t.so"; done
	f=$BATS_TEST_TMPDIR/panel
	printf 'Global {\n}\nPlugin {\n  type=cpu\n}\nPlugin {\n  type=magnifier\n  Config {\n  }\n}\n' >"$f"
	out=$(_pi_layout "$f" lxpanel-pi)
	grep -qx '  type=cpu' <<<"$out"
	run ! grep -q magnifier <<<"$out"
	# --refresh does not offer to remove them
	cat() { printf '%s\n' lpplug-cpu lpplug-magnifier mage-rpi; }
	installed_version() { echo 1; }
	apt_versions() { :; }
	FETCH_PKGS=(lpplug-cpu lpplug-magnifier mage-rpi) APT_PKGS=()
	[ -z "$(stale_pkgs)" ]
}

@test "Ctrl+Alt+M stays, as in Raspberry Pi OS's keys, where the magnifier plugin is installed" {
	SYS_ROOT=$BATS_TEST_TMPDIR/root WORKDIR=$BATS_TEST_TMPDIR S_PI_PANEL=1 USE_NETMAN=0
	mkdir -p "$SYS_ROOT/usr/bin" "$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanel-pi"
	printf '#!/bin/sh\n' >"$SYS_ROOT/usr/bin/lxpanelctl-pi"; chmod +x "$SYS_ROOT/usr/bin/lxpanelctl-pi"
	PATH=$SYS_ROOT/usr/bin:$PATH
	pi=$BATS_TEST_TMPDIR/rpd-rc.xml rc=$BATS_TEST_TMPDIR/rc.xml
	printf '%s\n' '<openbox_config>' '  <keyboard>' '    <keybind key="C-A-M">' '      <action name="Execute">' \
		'         <command>lxpanelctl-pi command magnifier toggle</command>' '      </action>' '    </keybind>' \
		'    <keybind key="C-A-B">' '      <action name="Execute">' '         <command>lxpanelctl-pi command bluetooth menu</command>' \
		'      </action>' '    </keybind>' '  </keyboard>' '</openbox_config>' >"$pi"
	: >"$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanel-pi/magnifier.so"
	cp "$pi" "$rc"
	_openbox_keys "$rc" "$pi"
	grep -A2 'key="C-A-M"' "$rc" | grep -q 'command magnifier toggle'
	grep -A2 'key="C-A-B"' "$rc" | grep -q 'command bluetooth menu'
	# The session's own keys bind it too; without the plugin it goes
	printf '<openbox_config>\n  <keyboard>\n  </keyboard>\n</openbox_config>\n' >"$rc"
	_openbox_keys "$rc"
	grep -A2 'key="C-A-M"' "$rc" | grep -q 'lxpanelctl-pi command magnifier toggle'
	rm "$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanel-pi/magnifier.so"
	cp "$pi" "$rc"
	_openbox_keys "$rc" "$pi"
	run ! grep -q magnifier "$rc"
}

@test "a new program of Raspberry Pi OS's desktop is noted, not installed unchecked" {
	index_names() { printf '%s\n' rpd-x-core rpd-common lxpanel-pi lpplug-new raspi-config pcmanfm-pi rpd-newtool openbox; }
	index_candidates() { case $3 in rpd-x-core) printf '1\tamd64\tf\ts\t1\t%s\n' "rpd-common, openbox, lxpanel-pi, lpplug-new" ;;
		rpd-common) printf '1\tamd64\tf\ts\t1\t%s\n' "pcmanfm-pi, raspi-config, rpd-newtool, lxsession" ;; esac; }
	_debian_has() { [[ $1 == openbox || $1 == lxsession ]]; }
	[ "$(desktop_unknown trixie amd64)" = rpd-newtool ]
}

@test "Qt programs: Raspberry Pi's GTK 2 styles, named in the session only" {
	_debian_has() { [ "$1" = qt6gtk2 ] && [ -n "${DEB:-}" ]; }
	[ "$(qt_pkgs | paste -sd' ')" = "qt5-style-plugins qt6gtk2" ]
	[ -z "$(qt_debs)" ]
	DEB=1; [ "$(qt_pkgs)" = qt5-style-plugins ] && [ "$(qt_debs)" = qt6gtk2 ]
	WORKDIR=$BATS_TEST_TMPDIR S_PI_FM=0 S_PI_PANEL=0 S_PROFILE=rpd-x S_FM_PROFILE=rpd-x
	_session_programs "$BATS_TEST_TMPDIR/root"
	grep -qx 'export QT_QPA_PLATFORMTHEME=gtk2' "$BATS_TEST_TMPDIR/root$SHARE/session-env"
	run ! grep -q QT_STYLE_OVERRIDE "$BATS_TEST_TMPDIR/root$SHARE/session-env"
}

@test "SSH: the session has Debian's agent only" {
	WORKDIR=$BATS_TEST_TMPDIR S_PI_FM=1 S_PI_PANEL=1 S_PROFILE=rpd-x S_FM_PROFILE=default T_GTK=PiXtrix T_ICONS=PiXtrix T_FONT=x T_CURSOR_SIZE=24 T_TB_ICON=24 T_SOUND_THEME=x
	_term_cmd() { echo lxterminal; }; color_scheme() { echo default; }
	_session_profile "$BATS_TEST_TMPDIR/xdg"
	f=$BATS_TEST_TMPDIR/xdg/lxsession/rpd-x/desktop.conf
	grep -qx 'polkit/command=lxpolkit' "$f" && grep -qx 'quit_manager/command=lxsession-logout' "$f"
	run ! grep -q '^keyring/' "$f"
	_session_programs "$BATS_TEST_TMPDIR/root"
	start=$BATS_TEST_TMPDIR/root$SHARE/start
	# No SSH agent is ended at logout: Debian's ends by itself
	run ! grep -q 'pgrep .*ssh-agent' "$start"
	run ! grep -q 'kill "$p"' "$start"
	# The user's file is not changed: a keyring command set there stays
	run ! grep -q 'keyring' "$start"
}

@test "APT's lists follow Raspberry Pi's archive in the sources: added, changed, removed" {
	init_colors
	log=$BATS_TEST_TMPDIR/log src=$BATS_TEST_TMPDIR/src have=0
	as_root() { echo "$*" >>"$log"; }
	compgen() { (( have )); }
	cat() { if [[ $2 == "$APT_SRC" ]]; then command cat "$src"; else command cat "$@"; fi; }
	# The functions read the real paths; stand-ins for them
	eval "$(sed -n '/^apt_lists_sync()/,/^}/p' "$BATS_TEST_DIRNAME/../rpios-look.sh" | sed "s#\[\[ -f \$APT_SRC \]\]#[[ -f $src ]]#")"
	# Added by the install (no lists yet): APT's lists are refreshed
	echo one >"$src"
	apt_lists_sync ""
	grep -qx 'apt-get update -q' "$log"
	# Unchanged, with lists: nothing; changed: refreshed again
	: >"$log"; have=1
	apt_lists_sync one
	[ ! -s "$log" ]
	apt_lists_sync two
	grep -qx 'apt-get update -q' "$log"
	# Removed (uninstall, offline install): refreshed while lists remain
	: >"$log"; rm "$src"
	apt_lists_sync
	grep -qx 'apt-get update -q' "$log"
	: >"$log"; have=0
	apt_lists_sync
	[ ! -s "$log" ]
	# The install reads the source before the generated package changes it
	f=$(sed -n '/^install_mode()/,/^}/p' "$BATS_TEST_DIRNAME/../rpios-look.sh")
	(( $(grep -n 'src=$(cat -- "$APT_SRC"' <<<"$f" | cut -d: -f1) < $(grep -nx $'\tinstall_pkg' <<<"$f" | cut -d: -f1) ))
	(( $(grep -nx $'\tinstall_pkg' <<<"$f" | cut -d: -f1) < $(grep -nxF $'\tapt_lists_sync "$src"' <<<"$f" | cut -d: -f1) ))
}

@test "versioned Provides: Qt 6's private ABI that sid no longer provides leaves qt6gtk2 out" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR H_SUITE=trixie H_ARCH=amd64 IN_SET=() AVAIL=()
	# sid: Qt 6.11 provides qt6-base-private-abi (= 6.11.0); x-terminal-emulator without a version
	apt-cache() {
		case "$1 $2" in
			"showpkg qt6-base-private-abi") printf '%s\n' 'Package: qt6-base-private-abi' 'Reverse Provides: ' \
				'libqt6core6t64 6.11.0+dfsg-1 (= 6.11.0)' 'libqt6core6t64 6.8.2+dfsg-9 (= 6.8.2)' ;;
			"showpkg x-terminal-emulator") printf '%s\n' 'Reverse Provides: ' 'xterm 397-1 (= )' ;;
			policy*) shift; for p; do
				case $p in xterm) v=397-1 ;; libqt6core6t64) v=6.11.0+dfsg-1 ;; *) v="(none)" ;; esac
				printf '%s:\n  Installed: (none)\n  Candidate: %s\n' "$p" "$v"
			done ;;
		esac
	}
	installed_version() { :; }; apt_has() { :; }
	[ "$(_provided qt6-base-private-abi)" = 6.11.0 ]
	[ "$(_provided x-terminal-emulator)" = - ]
	run ! _deps_satisfiable "libc6, qt6-base-private-abi (= 6.8.2)"
	_deps_satisfiable "qt6-base-private-abi (= 6.11.0)"
	_deps_satisfiable "x-terminal-emulator"
	run ! _deps_satisfiable "x-terminal-emulator (>= 1)"
	# The resolver leaves it out, with the reason
	mkdir -p "$WORKDIR/index/trixie"
	printf 'Package: qt6gtk2\nVersion: 0.5-1+rpt1\nArchitecture: amd64\nDepends: libc6, qt6-base-private-abi (= 6.8.2)\nFilename: q.deb\nSHA256: 1\n\n' >"$WORKDIR/index/trixie/Packages-amd64"
	index_load() { [[ -f $WORKDIR/index/$1/Packages-$2 ]]; }
	run resolve_pkg qt6gtk2
	[ "$status" = 1 ] && [[ $output == *"qt6gtk2 0.5-1+rpt1 needs packages that Debian does not provide"* ]]
	# Trixie's Qt 6.8.2 provides it
	AVAIL=()
	apt-cache() { case "$1" in showpkg) printf '%s\n' 'Reverse Provides: ' 'libqt6core6t64 6.8.2+dfsg-9 (= 6.8.2)' ;; policy) [[ $2 != libqt6core6t64 ]] || printf '%s:\n  Candidate: 6.8.2+dfsg-9\n' "$2" ;; esac; }
	resolve_pkg qt6gtk2
	[ "${PKG_VER[qt6gtk2]}" = 0.5-1+rpt1 ]
}

@test "a twin's exact Raspberry Pi version of a Debian package, which repacking drops, is not asked for" {
	d='libnma-common (= 1.10.6-5+rpt1), libc6 (>= 2.34), libobrender32v5 (= 3.6.1-10+rpt1) | libx (= 1+rpi2)'
	[ "$(twin_deps libnma0 "$d")" = 'libnma-common, libc6 (>= 2.34), libobrender32v5 (= 3.6.1-10+rpt1) | libx' ]
	[ "$(twin_deps lxplug-netman "$d")" = "$d" ]
}

@test "repacking beside Debian's: own package, program, folder and library names, written in place" {
	h=$BATS_TEST_TMPDIR/beside WORKDIR=$BATS_TEST_TMPDIR
	beside_build "$h"
	lib=$(mkdeb libnma0 1.10-1+rpt1 $'Depends: libnma-common (= 1.10-1+rpt1), libc6\nBreaks: libnma0 (<< 1)\nProvides: libnma\n' \
		'usr/lib/x86_64-linux-gnu/libnma.so.0.0.0=ELF:libnma.so.0|libc.so.6' \
		'usr/lib/x86_64-linux-gnu/libnma.so.0=LINK:libnma.so.0.0.0' 'usr/share/locale/de/LC_MESSAGES/nma.mo=mo' \
		'usr/share/doc/libnma0/copyright=c')
	fm=$(mkdeb pcmanfm-pi 1.3-1+rpt2 $'Depends: libfm4 (>= 1.2), libc6\nRecommends: lxpolkit\n' \
		'usr/bin/pcmanfm=ELF:/usr/share/pcmanfm/ui/x.ui|libfm.so.4|libc.so.6|/usr/lib/x86_64-linux-gnu/pcmanfm' \
		'usr/bin/pcmanfm-tool=tool' 'usr/share/pcmanfm/ui/x.ui=ui' 'etc/xdg/pcmanfm/default/pcmanfm.conf=c' \
		$'usr/share/applications/pcmanfm.desktop=[Desktop Entry]\nExec=pcmanfm %U\nTryExec=pcmanfm')
	plug=$(mkdeb lpplug-netman 1.0 $'Depends: libnma0 (>= 1.10), lxpanel-pi\n' \
		'usr/lib/x86_64-linux-gnu/lxpanel-pi/netman.so=ELF:libnma.so.0|/usr/share/lxpanel-pi/ui/x.ui')
	ed=$(mkdeb lp-connection-editor 1.0 $'Depends: lpplug-netman | wfplug-netman\n' 'usr/bin/lp-connection-editor=ELF:libc.so.6')
	other=$(mkdeb pishutdown 1.0 $'Depends: libc6\n' 'usr/bin/pishutdown=ELF:libc.so.6|/usr/share/lxpanel-pi/ui/x.ui')
	conf=$BATS_TEST_TMPDIR/conf
	printf 'twins=libnma0 pcmanfm-pi\nlibs=%s\nbeside=\n' "$("$h" sonames "$lib" "$fm" | xargs)" >"$conf"
	[ "$(sed -n 's/^libs=//p' "$conf")" = libnma.so.0 ]
	# Which packages need it: the twins, what depends on one repacked; not
	# the others
	"$h" need "$conf" "$fm" && "$h" need "$conf" "$plug"
	run ! "$h" need "$conf" "$ed"
	run ! "$h" need "$conf" "$other"
	sed -i 's/^beside=$/beside=lpplug-netman/' "$conf"
	"$h" need "$conf" "$ed"
	[ -z "$("$h" pack "$conf" "$other" "$BATS_TEST_TMPDIR/out")" ]
	r=$BATS_TEST_TMPDIR/root c=()
	for d in "$lib" "$fm" "$plug" "$ed"; do
		c+=("$("$h" pack "$conf" "$d" "$BATS_TEST_TMPDIR/out")")
		dpkg-deb -x "${c[-1]}" "$r"
	done
	# Own package names, the same versions, no relations to Debian's packages
	[ "$(dpkg-deb -f "${c[0]}" Package)" = rpios-look-libnma0 ] && [ "$(dpkg-deb -f "${c[0]}" Version)" = 1.10-1+rpt1 ]
	[ "$(dpkg-deb -f "${c[0]}" Depends)" = "libnma-common, libc6" ]
	[ -z "$(dpkg-deb -f "${c[0]}" Breaks)$(dpkg-deb -f "${c[0]}" Provides)$(dpkg-deb -f "${c[1]}" Recommends)" ]
	[ "$(dpkg-deb -f "${c[1]}" Depends)" = "libfm4 (>= 1.2), libc6" ]
	[ "$(dpkg-deb -f "${c[2]}" Depends)" = "rpios-look-libnma0 (>= 1.10), lxpanel-pi" ]
	[ "$(dpkg-deb -f "${c[3]}" Depends)" = "rpios-look-lpplug-netman | wfplug-netman" ]
	# Own files: library, program, folder, documentation; nothing of Debian's
	[ -f "$r/usr/lib/x86_64-linux-gnu/libnmapi.so" ] && [ ! -e "$r/usr/lib/x86_64-linux-gnu/libnma.so.0" ]
	[ -x "$r/usr/bin/pcmanfm-pi" ] && [ -x "$r/usr/bin/lp-connection-editor" ]
	[ ! -e "$r/usr/bin/pcmanfm" ] && [ ! -e "$r/usr/bin/pcmanfm-tool" ]
	[ -f "$r/usr/share/pcmanpi/ui/x.ui" ] && [ -f "$r/usr/lib/x86_64-linux-gnu/lxpanel-pi/netman.so" ]
	[ ! -e "$r/etc" ] && [ ! -e "$r/usr/share/locale" ] && [ ! -e "$r/usr/share/applications" ] && [ ! -e "$r/usr/share/pcmanfm" ]
	[ -f "$r/usr/share/doc/rpios-look-libnma0/copyright" ]
	# The file manager's menu entry, for the session only, in its own folder
	grep -qx 'Exec=pcmanfm-pi %U' "$r/usr/share/pcmanpi/pcmanfm-pi.desktop"
	grep -qx 'TryExec=pcmanfm-pi' "$r/usr/share/pcmanpi/pcmanfm-pi.desktop"
	# The names inside the programs, at the same length; Debian's libfm and
	# Raspberry Pi's own panel folder stay as they are
	has_string "$r/usr/bin/pcmanfm-pi" /usr/share/pcmanpi/ui/x.ui && has_string "$r/usr/bin/pcmanfm-pi" /usr/lib/x86_64-linux-gnu/pcmanpi
	has_string "$r/usr/bin/pcmanfm-pi" libfm.so.4 && has_string "$r/usr/bin/pcmanfm-pi" libc.so.6
	has_string "$r/usr/lib/x86_64-linux-gnu/libnmapi.so" libnmapi.so
	has_string "$r/usr/lib/x86_64-linux-gnu/lxpanel-pi/netman.so" libnmapi.so
	has_string "$r/usr/lib/x86_64-linux-gnu/lxpanel-pi/netman.so" /usr/share/lxpanel-pi/ui/x.ui
	run ! grep -rqaE 'libnma\.so\.0|/usr/share/pcmanfm/' "$r/usr/bin" "$r/usr/lib"
	[ "$(stat -c %s "$r/usr/bin/pcmanfm-pi")" = "$(dpkg-deb --fsys-tarfile "$fm" | tar -xO ./usr/bin/pcmanfm | wc -c)" ]
	# The same input gives the same package
	[ "$(sha256sum <"${c[1]}")" = "$(sha256sum <"$("$h" pack "$conf" "$fm" "$BATS_TEST_TMPDIR/again")")" ]
}

@test "repacking stops at a file of a Raspberry Pi build that Debian's package may have" {
	h=$BATS_TEST_TMPDIR/beside WORKDIR=$BATS_TEST_TMPDIR
	beside_build "$h"
	d=$(mkdeb openbox 3.6-1+rpt1 '' 'usr/bin/openbox=ELF:libobt.so.2' 'usr/share/openbox/x=x')
	printf 'twins=openbox\nlibs=libobt.so.2\nbeside=\n' >"$BATS_TEST_TMPDIR/conf"
	run "$h" pack "$BATS_TEST_TMPDIR/conf" "$d" "$BATS_TEST_TMPDIR/out"
	[ "$status" = 1 ] && [[ $output == *"openbox has a file that may be Debian's: /usr/share/openbox/x"* ]]
	[ -z "$(ls "$BATS_TEST_TMPDIR/out" 2>/dev/null)" ]
}

@test "Openbox, the file manager and libnma: Raspberry Pi's builds go beside Debian's; its panel uses Debian's libfm" {
	# Raspberry Pi's Openbox is part of the set on every release
	[ "$(qt_pkgs() { :; }; rpi_new_looks() { :; }; index_load() { return 1; }; pi_apps() { :; }; rpi_pkgs trixie amd64 | grep -E '^(openbox|libob)' | xargs)" \
		= "openbox libobrender32v5" ]
	# The twins of a resolved set; Raspberry Pi's own programs are not, and
	# libobt is Debian's (Raspberry Pi's is the same library)
	FETCH_PKGS=(pixtrix-theme openbox libobrender32v5 pcmanfm-pi lxpanel-pi libnma0 lpplug-netman)
	mapfile -t TWINS < <(printf '%s\n' "${FETCH_PKGS[@]}" | grep -xE "$TWIN_RE")
	[ "${TWINS[*]}" = "openbox libobrender32v5 pcmanfm-pi libnma0" ]
	# Their names are allowed, as they are repacked; any other Debian name stops
	apt_versions() { echo 1; }
	_refuse_debian_names openbox libnma0
	run _refuse_debian_names openbox lxsession
	[ "$status" = 1 ] && [[ $output == *"refusing to install lxsession"* ]]
	# A repacked package is known under its own name
	BESIDE=(lpplug-netman) BESIDE_DONE=1
	[ "$(inst_name openbox)" = rpios-look-openbox ] && [ "$(inst_name lpplug-netman)" = rpios-look-lpplug-netman ]
	[ "$(inst_name pixtrix-theme)" = pixtrix-theme ] && [ "$(inst_name lxpanel-pi)" = lxpanel-pi ]
}

@test "the session starts Raspberry Pi's Openbox where it is installed, and Debian's otherwise" {
	WORKDIR=$BATS_TEST_TMPDIR S_PI_FM=1 S_PI_PANEL=1 S_PROFILE=rpd-x S_FM_PROFILE=default
	_session_programs "$BATS_TEST_TMPDIR/root"
	r=$BATS_TEST_TMPDIR/root$SHARE
	grep -q "^exec $SHARE/bin/openbox --config-file " "$r/openbox"
	grep -qx 'if \[ -x /usr/bin/openbox-pi \]; then exec /usr/bin/openbox-pi "$@"; fi' "$r/bin/openbox"
	grep -qx 'exec /usr/bin/openbox "$@"' "$r/bin/openbox"
	# Debian's LXDE session is not given anything
	run ! grep -rq lxde-xdg "$BATS_TEST_TMPDIR/root"
}

@test "before the repacked packages come: the repacked ones this run no longer uses go" {
	init_colors
	log=$BATS_TEST_TMPDIR/log
	_purge() { echo "purge $*" >>"$log"; }
	TWINS=(openbox pcmanfm-pi) BESIDE=(lpplug-netman)
	# Those in use and the session package stay; a package under its own name
	# is left alone
	_safe_purge_set() { printf "%s\n" "$@"; }
	installed_version() { echo 1; }
	dpkg-query() { printf '%s\n' 'ii  rpios-look-openbox' 'ii  rpios-look-lxplug-menu' 'ii  rpios-look-debian'; }
	beside_tidy
	[ "$(cat "$log")" = 'purge -q rpios-look-lxplug-menu' ]
	# Nothing to do: nothing is removed
	: >"$log"; dpkg-query() { :; }; installed_version() { :; }
	beside_tidy
	[ ! -s "$log" ]
}

@test "the other edition's install stops this one before any change; --refresh keeps the installed Raspberry Pi OS release" {
	st=$BATS_TEST_TMPDIR/state
	eval "$(sed -n '/^require_own_install() {$/,/^}$/p;/^keep_installed_release() {$/,/^}$/p' "$BATS_TEST_DIRNAME/../rpios-look.sh" \
		| sed "s|\$SYS_DIR/state|$st|")"
	die() { echo "DIE: $*"; return 1; }
	# No state, an install of this edition, or a state without the edition: go on
	rm -f "$st"; require_own_install
	printf 'release trixie\nedition main\n' >"$st"; require_own_install
	printf 'release trixie\n' >"$st"; require_own_install
	# The other edition's install: stop, naming --uninstall
	printf 'release bookworm\nedition legacy\n' >"$st"
	run require_own_install; [ "$status" -ne 0 ]
	[[ $output == *"installed by rpios-look-legacy.sh"* && $output == *"--uninstall"* && $output == *"nothing was changed"* ]]
	# --refresh: the installed release stays, with a note when a newer one fits
	rpi_populated() { :; }; rpi_arches() { echo amd64; }
	note() { echo "NOTE: $*"; }
	H_ARCH=amd64 H_SUITE=forky
	printf 'release trixie\nedition main\n' >"$st"
	out=$(keep_installed_release; echo "suite=$H_SUITE")
	[[ $out == *"NOTE: Raspberry Pi OS forky is available"* && $out == *"suite=trixie" ]]
	# Not published for this architecture any more: the choice of pick_suite stays
	rpi_arches() { echo i386; }
	H_SUITE=forky; keep_installed_release; [ "$H_SUITE" = forky ]
	# A release outside this edition's, or not a release name: ignored
	rpi_arches() { echo amd64; }
	printf 'release bookworm\n' >"$st"; H_SUITE=forky; keep_installed_release; [ "$H_SUITE" = forky ]
	printf 'release $(true)\n' >"$st"; keep_installed_release; [ "$H_SUITE" = forky ]
}

@test "NetworkManager and the Wi-Fi tools come only with the network plugin; one installed already stays" {
	init_colors
	has_wifi() { :; }; has_bluetooth() { [ -n "${BT:-}" ]; }
	installed_version() { case $1 in network-manager) echo "${NM:-}" ;; esac; }
	USE_NETMAN=1
	[[ $(tray_debs | xargs) == "network-manager wpasupplicant iw wireless-regdb rfkill dnsmasq-base" ]]
	# The plugin is left out while installing: they go from the install set
	USE_NETMAN=0 APT_PKGS=(lxsession network-manager wpasupplicant iw wireless-regdb rfkill lxpanel-pi)
	HW_PKGS=(network-manager wpasupplicant iw wireless-regdb rfkill) ROOT_PKGS=(lxsession network-manager iw rfkill)
	netman_debs_drop >/dev/null
	[ "${APT_PKGS[*]}" = "lxsession lxpanel-pi" ] && [ ${#HW_PKGS[@]} = 0 ] && [ "${ROOT_PKGS[*]}" = lxsession ]
	# rfkill stays for Bluetooth
	BT=1 APT_PKGS=(network-manager rfkill bluez) HW_PKGS=(network-manager rfkill bluez) ROOT_PKGS=()
	netman_debs_drop >/dev/null
	[ "${APT_PKGS[*]}" = "rfkill bluez" ] && [ "${HW_PKGS[*]}" = "rfkill bluez" ]
	# Installed already: nothing of it is asked for, nothing changes
	NM=1 BT="" APT_PKGS=(lxsession) HW_PKGS=() ROOT_PKGS=(lxsession)
	netman_debs_drop
	[ "${APT_PKGS[*]}" = lxsession ]
	# install_all calls it where the plugin is left out
	grep -q '^		netman_debs_drop$' <(sed -n '/^install_all() {$/,/^}$/p' "$BATS_TEST_DIRNAME/../rpios-look.sh")
}

@test "Large and Larger sizes: the large window theme, 17-pixel scrollbars and wider resize borders, as Raspberry Pi OS 12 and 13" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR SYS_ROOT=$BATS_TEST_TMPDIR/root
	local t d=$BATS_TEST_TMPDIR/data rc=$BATS_TEST_TMPDIR/rc.xml
	for t in PiXtrix PiX; do
		mkdir -p "$SYS_ROOT/usr/share/themes/$t/gtk-3.0" "$SYS_ROOT/usr/share/themes/$t/openbox-3"
		echo '/* theme */' >"$SYS_ROOT/usr/share/themes/$t/gtk-3.0/gtk.css"
		echo 'border.radius: 0' >"$SYS_ROOT/usr/share/themes/$t/openbox-3/themerc"
	done
	mkdir -p "$SYS_ROOT/usr/share/themes/PiXtrix_l/openbox-3"
	echo 'border.radius: 0' >"$SYS_ROOT/usr/share/themes/PiXtrix_l/openbox-3/themerc"
	: >"$SYS_ROOT/usr/share/themes/PiXtrix_l/openbox-3/max_hover_toggled.xbm"
	mk_rc() { printf '<?xml version="1.0"?>\n<openbox_config>\n  <theme>\n    <name>x</name>\n  </theme>\n  <mouse>\n    <doubleClickTime>200</doubleClickTime>\n  </mouse>\n</openbox_config>\n' >"$rc"; }
	# Medium: the theme itself, no scrollbar rules, 12-pixel borders
	O_SIZE=medium set_theme pixtrix
	[ "$T_OB" = PiXtrix ]
	[ "$T_HANDLE" = 10 ]
	[ "$T_SCROLL" = 0 ]
	mk_rc; _openbox_rc "$rc"
	grep -q '<name>PiXtrix</name>' "$rc"; grep -q '<invHandleWidth>10<' "$rc"
	[ "$(grep -c '<doubleClickTime>' "$rc")" = 1 ]; grep -q '<doubleClickTime>400</doubleClickTime>' "$rc"
	_session_themes "$d"
	run ! grep -q '^scrollbar' "$d/themes/PiXtrix/gtk-3.0/gtk.css"
	# Large and Larger: <theme>_l, 20-pixel borders, 17-pixel scrollbars
	for O_SIZE in large larger; do
		set_theme pixtrix
		[ "$T_OB" = PiXtrix_l ]
		[ "$T_HANDLE" = 20 ]
		[ "$T_SCROLL" = 17 ]
		mk_rc; _openbox_rc "$rc"
		grep -q '<name>PiXtrix_l</name>' "$rc"; grep -q '<invHandleWidth>20<' "$rc"
	done
	rm -rf -- "$d"; _session_themes "$d"
	grep -qx 'scrollbar button { min-width: 17px; min-height: 17px; }' "$d/themes/PiXtrix/gtk-3.0/gtk.css"
	grep -qx 'scrollbar slider { min-width: 11px; min-height: 11px; }' "$d/themes/PiXtrix/gtk-3.0/gtk.css"
	[ -L "$d/themes/PiXtrix_l/openbox-3/max_toggled_hover.xbm" ]
	# PiX has no large window theme; a missing _l theme falls back to the theme
	set_theme pix; [ "$T_OB" = PiX ]
	rm -r "$SYS_ROOT/usr/share/themes/PiXtrix_l"
	set_theme pixtrix; mk_rc; _openbox_rc "$rc"; grep -q '<name>PiXtrix</name>' "$rc"
}

@test "rpios-look-set keeps the size's window theme: the large one for Large and Larger" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR S_PROFILE=rpd-x S_FM_PROFILE=rpd-x
	local r=$BATS_TEST_TMPDIR/root
	O_SIZE=larger; set_theme pixtrix; _session_command "$r"
	grep -q 'pixonyx) gtk=PiXonyx wm_theme=PiXonyx_l ' "$r/usr/bin/rpios-look-set"
	grep -q 'pix) gtk=PiX wm_theme=PiX ' "$r/usr/bin/rpios-look-set"
	grep -q 'set_openbox_theme "$wm_theme" "$gtk"' "$r/usr/bin/rpios-look-set"
	rm -rf -- "$r"; O_SIZE=medium; set_theme pixtrix; _session_command "$r"
	grep -q 'pixonyx) gtk=PiXonyx wm_theme=PiXonyx ' "$r/usr/bin/rpios-look-set"
}

@test "an install records the edition before its first change, so the other script never installs over it" {
	local body
	body=$(sed -n '/^\tas_root install -d -m 0755 "\$SYS_DIR"$/,/^\tinstall_all$/p' "$BATS_TEST_DIRNAME/../rpios-look.sh")
	[[ $body == *record_packages_before*'[[ -f $SYS_DIR/state ]] || save_state'*before=* ]]
}
