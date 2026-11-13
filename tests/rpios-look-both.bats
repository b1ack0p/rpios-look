#!/usr/bin/env bats
# Both scripts stand alone, so the code they share is written twice. These
# tests keep the two copies together: a function that both define must have
# the same text in both, unless it is listed below as different on purpose.
# Run: bats tests/

MAIN=$BATS_TEST_DIRNAME/../rpios-look.sh
LEGACY=$BATS_TEST_DIRNAME/../rpios-look-legacy.sh

# The functions that differ on purpose: releases, architectures, package
# names, the Wayland session, offline installation, sizes.
DIFFERENT="
	adapt_deb apt_files audio_debs _avail beside_build beside_seen bt_pin_entry build_deb
	build_pkg choose_session cleanup cmd_pack _debian_has _dep_ok _deps_satisfiable download_pkg
	fetch _fm_shared_conf index_candidates index_load index_names install_all install_mode
	keep_installed_release list load_releases login_debs _lxpanel_layout magnifier_pkg main
	netman_debs_drop netman_decide _no_battery _openbox_keys _openbox_rc panel_drop _panel_tasks
	parse_args pick_suite _pi_layout _pin_unfixed pi_unpack pkg_category _pkg_status preflight_tools
	_print_look print_plan qt_debs refresh_check _release_csv release_load release_ok reload_session
	require_own_install reset_file_manager resolve_all resolve_pkg rpi_arches rpi_new_looks rpi_pkgs rpi_populated
	self_cmd session_build _session_command _session_dconf _session_entries _session_files
	_session_icons _session_menu _session_profile _session_programs _session_themes session_vars
	set_theme size_ok start_log summary theme_debs tray_debs uninstall usage version_newer
	wicd_restore with_rpi_deps
"

# Print "NAME same|differs" for every function that both scripts define at
# the start of a line: their own and those of the programs they write. Of a
# name defined more than once in a script, the first definition counts.
compare() {
	awk '
	function flush() {
		if (FILENAME == ARGV[1]) a[n] = b
		else if (n in a) { both[n] = 1; if (a[n] != b) diff[n] = 1 }
		n = ""
	}
	/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ && n == "" {
		n = $1; sub(/\(\).*/, "", n)
		if (seen[FILENAME, n]++) { n = ""; next }
		b = $0
		if ($0 !~ /\{[[:space:]]*$/) flush()
		next
	}
	n != "" { b = b "\n" $0; if ($0 == "}") flush() }
	END { for (k in both) print k, (k in diff ? "differs" : "same") }
	' "$MAIN" "$LEGACY" | LC_ALL=C sort
}

@test "shared functions: the same text in both scripts, unless listed as different on purpose" {
	out=$(compare)
	[ "$(grep -c . <<<"$out")" -ge 200 ]
	listed=$(printf '%s\n' $DIFFERENT | LC_ALL=C sort -u)
	# A fix made in one script only shows here
	new=$(LC_ALL=C comm -23 <(awk '$2 == "differs" { print $1 }' <<<"$out") <(printf '%s\n' "$listed"))
	[ -z "$new" ] || { echo "differ in the two scripts, and are not listed as different on purpose: $new"; false; }
}

@test "shared functions: every function listed as different still is, in both scripts" {
	out=$(compare)
	listed=$(printf '%s\n' $DIFFERENT | LC_ALL=C sort -u)
	old=$(LC_ALL=C comm -13 <(awk '$2 == "differs" { print $1 }' <<<"$out") <(printf '%s\n' "$listed"))
	[ -z "$old" ] || { echo "listed as different, but the same in both scripts or no longer in both (take them off the list): $old"; false; }
}
