#!/usr/bin/env bats
# Unit tests of rpios-look.sh's decision helpers. They source the script,
# which then defines its functions without running anything, and need no
# root, network or desktop. Run: bats tests/

bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=../rpios-look.sh
	source "$BATS_TEST_DIRNAME/../rpios-look.sh"
	load_releases
}

@test "release order: suite_ge and suite_rank" {
	suite_ge trixie bookworm
	suite_ge bookworm bookworm
	run ! suite_ge bullseye bookworm
	[ "$(suite_rank buster)" = 10 ]
	[ "$(suite_rank trixie)" = 13 ]
}

@test "unknown or empty release names fail without errors" {
	run suite_rank ""
	[ "$status" -ne 0 ] && [ "$output" = 0 ]
	run suite_rank nosuch
	[ "$status" -ne 0 ]
	run ! suite_ge "" bookworm
	suite_ge trixie ""
}

@test "package names per release" {
	[ "$(nm_applet_pkg bookworm)" = network-manager-gnome ]
	[ "$(nm_applet_pkg trixie)" = network-manager-applet ]
	[ "$(mono_font_pkg bullseye)" = fonts-liberation2 ]
	[ "$(mono_font_pkg trixie)" = fonts-liberation ]
}

@test "size presets" {
	for s in small medium large larger; do size_ok "$s"; done
	run ! size_ok huge
	run ! size_ok ""
}

@test "Debian's builds bundled beside Raspberry Pi's" {
	for p in lxpanel pcmanfm libfm4 libfm-gtk3-4 libnma0 openbox libobrender32v5 libobt2v5; do _debian_twin "$p"; done
	for p in lxpanel-pi pcmanfm-pi labwc lxterminal; do run ! _debian_twin "$p"; done
}

@test "drop_deps removes whole entries only" {
	[ "$(drop_deps 'a, raspi-config, b (>= 1), rpi-x' raspi-config rpi-x)" = 'a, b (>= 1)' ]
	[ "$(drop_deps 'libfoo1, libfoo1-dev' libfoo1)" = 'libfoo1-dev' ]
	[ "$(drop_deps 'gtk+3.0 (>= 3), x' gtk+3.0)" = 'x' ]
}

@test "shell quoting for messages" {
	[ "$(_q a 'b c' "d'e")" = "a b\\ c d\\'e" ]
}

# pick_display with a described machine: SUITE DRIVER KMS MEM RENDER ARCH OLD_CPU
display() {
	H_SUITE=$1 H_GPU_DRV=$2 H_KMS=$3 H_MEM_MB=$4 H_RENDER=$5 H_ARCH=$6 H_OLD_CPU=$7
	pick_display
	echo "$H_DISPLAY"
}

@test "Wayland only on capable PCs with Debian 13 and later" {
	[ "$(display trixie i915 1 8000 1 amd64 0)" = wayland ]
	[ "$(display trixie amdgpu 1 4000 1 amd64 0)" = wayland ]
	[ "$(display forky xe 1 4000 1 amd64 0)" = wayland ]
	[ "$(display bookworm i915 1 8000 1 amd64 0)" = x11 ]
	[ "$(display trixie nvidia 1 8000 1 amd64 0)" = x11 ]
	[ "$(display trixie nouveau 1 8000 1 amd64 0)" = x11 ]
	[ "$(display trixie i915 0 8000 1 amd64 0)" = x11 ]
	[ "$(display trixie i915 1 1700 1 amd64 0)" = x11 ]
	[ "$(display trixie i915 1 1900 1 amd64 0)" = wayland ]
	[ "$(display trixie i915 1 8000 0 amd64 0)" = x11 ]
	[ "$(display trixie i915 1 8000 1 i386 0)" = x11 ]
	[ "$(display trixie i915 1 8000 1 amd64 1)" = x11 ]
	[ "$(display trixie radeon 1 8000 1 amd64 0)" = x11 ]
	[ "$(display trixie "" 1 8000 1 amd64 0)" = x11 ]
}

@test "every X choice gives a reason" {
	# shellcheck disable=SC2034  # read by pick_display
	H_SUITE=trixie H_GPU_DRV=nvidia H_KMS=1 H_MEM_MB=8000 H_RENDER=1 H_ARCH=amd64 H_OLD_CPU=0
	pick_display
	[ -n "$H_DISPLAY_WHY" ]
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
