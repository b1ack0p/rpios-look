#!/usr/bin/env bats
# Unit tests of rpios-look-legacy.sh's decision helpers. They source the
# script, which then defines its functions without running anything, and need
# no root, network or desktop. Run: bats tests/

bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=../rpios-look-legacy.sh
	source "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh"
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

@test "edition and version" {
	[ "$APP_NAME" = rpios-look ] && [ "$APP_EDITION" = legacy ] && [ "$APP_VERSION" = 1.0.0 ]
	[ "$APP_PKG" = rpios-look-debian ] && [ "$SESSION_ID" = rpios-look ] && [ "$SYS_DIR" = /var/lib/rpios-look ]
	run parse_args --version
	[ "$output" = "rpios-look 1.0.0 (legacy)" ]
}

@test "Debian 9 to 12 are served, 13 and later are not" {
	for r in 9 10 11 12; do release_supported "$r"; done
	for r in 8 13 14 ""; do run ! release_supported "$r"; done
}

@test "Debian 13, testing and unstable stop with a pointer to rpios-look.sh" {
	init_colors
	H_PRETTY="Debian GNU/Linux 13 (trixie)" H_CODENAME=trixie
	run require_release
	[ "$status" -ne 0 ]
	[[ $output == *rpios-look.sh* && $output == *github.com/b1ack0p/rpios-look* && $output == *"nothing was changed"* ]]
	# testing names no release in os-release; debian_version names the next one
	H_CODENAME="" ; cat() { echo "forky/sid"; }
	run require_release
	[ "$status" -ne 0 ] && [[ $output == *rpios-look.sh* ]]
	H_CODENAME=sid
	run require_release
	[ "$status" -ne 0 ] && [[ $output == *rpios-look.sh* ]]
	unset -f cat
	H_CODENAME=bookworm
	[ "$(require_release)" = 12 ]
	H_CODENAME=stretch
	[ "$(require_release)" = 9 ]
}

@test "release dates: a row without end dates keeps the built-in ones" {
	# Debian 9's distro-info-data 0.36 has no end dates for Debian 9
	f=$BATS_TEST_TMPDIR/debian.csv
	printf '%s\n' version,codename,series,created,release,eol,eol-lts 9,Stretch,stretch,2015-04-25,2017-06-17 \
		10,Buster,buster,2017-06-17,2019-07-06,,x 16,Next,next,2027-01-01,2029-06-01 >"$f"
	_release_csv "$f"
	[ "${REL_DATES[9]}" = "2017-06-17 2020-07-18 2022-06-30" ]
	[ "${REL_DATES[10]}" = "2019-07-06 2022-09-10 2024-06-30" ]
	[ "${REL_DATES[16]}" = "2029-06-01 - -" ]
	[ "${REL_VER[next]}" = 16 ]
	init_colors; H_PRETTY="Debian GNU/Linux 9 (stretch)"
	host_rank() { echo 9; }
	run old_release_warning
	[[ $output == *"LTS included, ended on 2022-06-30"* && $output != *"may have ended"* ]]
}

@test "--uninstall and --download skip the release check" {
	grep -q 'case $O_MODE in uninstall|download) ;; \*) require_release' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh"
	# uninstall runs before pick_suite, which calls require_release
	run ! grep -nE '^[[:space:]]*(pick_suite|require_release)' <(sed -n '/^uninstall()/,/^}/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh")
}

@test "--download bundles Debian 9 to 12, both architectures" {
	[ "$OFFLINE_OLDEST" = 9 ] && [ "$OLDEST" = 9 ] && [ "$NEWEST" = 12 ]
	# Raspberry Pi has the look of each release for both architectures
	# (Stretch's in its "ui" component)
	rpi_suite() { case $1 in 9) echo stretch ;; 10) echo buster ;; 11) echo bullseye ;; 12) echo bookworm ;; esac; }
	run bundle_pairs
	[ "$output" = "$(printf '%s\n' bookworm/amd64/bookworm bookworm/i386/bookworm bullseye/amd64/bullseye \
		bullseye/i386/bullseye buster/amd64/buster buster/i386/buster stretch/amd64/stretch stretch/i386/stretch)" ]
}

@test "Debian indexes: Release with Release.gpg where InRelease is missing; missing keys named" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR
	# archive.debian.org serves Debian 9 without InRelease (404 is curl's 22)
	fetch() { case $1 in "$DEBIAN_OLD_ARCHIVE"/dists/stretch/Release) printf 'Codename: stretch\n' >"$2" ;;
		"$DEBIAN_OLD_ARCHIVE"/dists/stretch/Release.gpg) echo sig >"$2" ;; *) return 22 ;; esac; }
	gpgv() { echo "gpgv $*" >>"$WORKDIR/log"; echo '[GNUPG:] GOODSIG 1 Debian'; }
	release_load debian stretch
	grep -q "gpgv .*$WORKDIR/index/debian/stretch/Release.gpg $WORKDIR/index/debian/stretch/Release.signed$" "$WORKDIR/log"
	[ "$(cat "$WORKDIR/index/debian/stretch/Release")" = "Codename: stretch" ]
	[ "$(archive_url debian stretch)" = "$DEBIAN_OLD_ARCHIVE" ]
	# A bad signature stops the run, as with InRelease
	gpgv() { echo '[GNUPG:] BADSIG 1 Debian'; }
	rm -rf "$WORKDIR/index"
	run release_load debian stretch
	[ "$status" -ne 0 ] && [[ $output == *"signature verification failed"* ]]
	# No key on this computer for a later release's index: status 2, nothing kept
	fetch() { [[ $1 == "$DEBIAN_ARCHIVE"/dists/bookworm/InRelease ]] && printf 'Codename: bookworm\n' >"$2"; }
	gpgv() { echo '[GNUPG:] NO_PUBKEY 1'; echo '[GNUPG:] ERRSIG 1'; }
	run release_load debian bookworm
	[ "$status" = 2 ] && [ ! -e "$WORKDIR/index/debian/bookworm/Release" ]
	# Raspberry Pi's index without its key stops the run
	run verify_release rpi "$WORKDIR/x" "$WORKDIR/y"
	[ "$status" = 1 ] && [[ $output == *"signature verification failed"* ]]
	# --download names every release this computer cannot check, before building
	preflight_tools() { :; }; ask() { :; }; setup_keyring() { :; }; mktemp() { echo "$WORKDIR/stage"; }
	[[ -r $DEBIAN_KEYRING ]] || skip "debian-archive-keyring is not installed"
	REPO=$WORKDIR/packages
	bundle_pairs() { printf '%s\n' stretch/amd64/stretch buster/amd64/buster bullseye/amd64/bullseye bookworm/amd64/bookworm bookworm/i386/bookworm; }
	release_load() { [[ $2 =~ ^(stretch|buster)$ ]] || return 2; }
	run download_mode
	[ "$status" -ne 0 ] && [[ $output == *"cannot check the Debian bullseye bookworm indexes"*"nothing was built"*"Debian 12 or later"* ]]
	[ ! -e "$WORKDIR/stage" ]
}

@test "the Raspberry Pi OS release: the newest up to Debian's, else the oldest after it" {
	rpi_aid() { echo rpi; }
	rpi_populated() { [[ $1 =~ ^(stretch|buster|bullseye|bookworm|trixie)$ ]]; }
	[ "$(rpi_suite 12)" = bookworm ]
	[ "$(rpi_suite 10)" = buster ]
	[ "$(rpi_suite 9)" = stretch ]
	rpi_populated() { [[ $1 =~ ^(buster|bullseye|bookworm|trixie)$ ]]; }
	[ "$(rpi_suite 9)" = buster ]
	# never Raspberry Pi OS 13 or later
	rpi_populated() { [[ $1 == trixie ]]; }
	run ! rpi_suite 12
}

@test "looks: this and earlier releases, never Raspberry Pi OS 13's" {
	O_MODE=install
	rpi_new_looks() { :; }
	pi_stack() { :; }
	index_load() { [[ $2 =~ ^(buster|bookworm|trixie)$ ]]; }
	index_names() { case $2 in buster) echo rpd-wallpaper ;; bookworm) printf '%s\n' rpd-wallpaper rpd-wallpaper-4k ;; trixie) echo rpd-wallpaper-trixie ;; esac; }
	index_transitional() { return 1; }
	H_RANK=11
	out=$(rpi_pkgs bullseye amd64)
	for p in pix-theme pixflat-theme pixflat-icons rpd-icons fonts-piboto rpd-wallpaper; do grep -qx "$p" <<<"$out"; done
	for p in pixtrix-theme pixtrix-icons fonts-nunito-sans rpd-wallpaper-trixie rpd-wallpaper-4k; do run ! grep -qx "$p" <<<"$out"; done
	out=$(rpi_pkgs bookworm amd64)
	grep -qx rpd-wallpaper-4k <<<"$out"
	run ! grep -qx rpd-wallpaper-trixie <<<"$out"
}

@test "a release with no look packages still gives the whole set; a set cut short stops the run" {
	init_colors
	O_MODE=install WORKDIR=$BATS_TEST_TMPDIR H_RANK=12
	rpi_aid() { echo rpi; }
	index_load() { [[ -f $WORKDIR/index/$1/$2/Packages-$3 ]]; }
	index_names() { sed -n 's/^Package: //p' "$WORKDIR/index/$1/$2/Packages-$3"; }
	_debian_has() { return 1; }
	pi_stack() { printf '%s\n' lxpanel pcmanfm; }
	mkdir -p "$WORKDIR"/index/rpi/{stretch,bookworm}
	printf 'Package: rpd-wallpaper\nArchitecture: all\nDescription: x\n\n' >"$WORKDIR/index/rpi/stretch/Packages-amd64"
	printf 'Package: rpd-wallpaper-4k\nArchitecture: all\nDescription: x\n\n' >"$WORKDIR/index/rpi/bookworm/Packages-amd64"
	mapfile -t out < <(rpi_pkgs bookworm amd64)
	for p in pixflat-theme rpd-wallpaper rpd-wallpaper-4k lxpanel pcmanfm; do [[ " ${out[*]} " == *" $p "* ]]; done
	out=()
	read_lines out rpi_pkgs bookworm amd64
	[ "${out[-1]}" = pcmanfm ]
	# A producer that stops (die, or a failed command under the script's set
	# -e) before its end. It exits: run ignores set -e in what it calls, even
	# where a function sets it again, so a failed command would not stop it
	half() { echo a; exit 1; }
	run read_lines out half
	[ "$status" -ne 0 ]
	[[ $output == *"half stopped early"* ]]
}

@test "Debian 9 gets PiX only, as Raspbian Stretch" {
	O_MODE=install
	pi_stack() { :; }
	index_load() { return 1; }
	H_RANK=9
	out=$(rpi_pkgs stretch amd64)
	for p in pix-theme rpd-icons fonts-piboto gtk2-engines-clearlookspix; do grep -qx "$p" <<<"$out"; done
	run ! grep -qE '^(pixflat-|gtk2-engines-pixflat$)' <<<"$out"
	H_RANK=10
	grep -qx pixflat-theme <<<"$(rpi_pkgs buster amd64)"
}

@test "--refresh names the release's own themes" {
	init_colors
	FETCH_PKGS=() APT_PKGS=() FW_PKGS=() WICD_IFACE="" O_SIZE_GIVEN=0
	state_lines() { :; }; wifi_plan() { :; }; installed_version() { echo 1; }
	H_RANK=9 H_SUITE=stretch
	run refresh_check
	[[ $output == *"every theme"*"(PiX) with"* && $output != *PiXflat* && $output != *PiXnoir* ]]
	H_RANK=10 H_SUITE=buster
	run refresh_check
	[[ $output == *"(PiXflat, PiXnoir, PiX) with"* ]]
}

@test "Debian 9: fakeroot and apt-transport-https come first, from Debian; without the latter, no APT source" {
	init_colors
	REPO="" NO_APT_SOURCE=0 NOTES=()
	deb_root_owner() { return 1; }; apt_https() { return 1; }; apt_has() { :; }
	tool_pkgs
	[ "${TOOL_PKGS[*]}" = "fakeroot apt-transport-https" ]
	[ "$NO_APT_SOURCE" = 0 ]
	# Not in the APT sources: Raspberry Pi's archive is not added, with a note
	apt_has() { return 1; }
	tool_pkgs
	[ "${TOOL_PKGS[*]}" = fakeroot ]
	[ "$NO_APT_SOURCE" = 1 ]
	[[ ${NOTES[*]} == *apt-transport-https*--refresh* ]]
	# Debian 10 and later need neither; offline needs no APT source
	deb_root_owner() { :; }; apt_https() { :; }; NO_APT_SOURCE=0
	tool_pkgs
	[ "${#TOOL_PKGS[@]}" = 0 ]
	[ "$NO_APT_SOURCE" = 0 ]
	REPO=/x
	apt_https() { return 1; }
	tool_pkgs
	[ "${#TOOL_PKGS[@]}" = 0 ]
	[ "$NO_APT_SOURCE" = 0 ]
	# They are installed and recorded before any package is repacked
	REPO="" WORKDIR=$BATS_TEST_TMPDIR FETCH_PKGS=(gui-runcmd) APT_PKGS=(fakeroot) TOOL_PKGS=(fakeroot) PKG_VER[gui-runcmd]=1
	log=$WORKDIR/log
	apt_has() { :; }; installed_version() { :; }; sys_write() { cat >/dev/null; }
	as_root() { [[ " $* " != *" install "* ]] || echo "install ${*: -1}" >>"$log"; }
	installed_names() { if [[ -s $log ]]; then printf '%s\n' a fakeroot; else echo a; fi; }
	_record_installed() { echo "record $*" >>"$log"; }
	download_pkg() { echo "$WORKDIR/$1.deb"; }
	adapt_deb() { echo "adapt $1" >>"$log"; }
	run install_all
	[ "$(head -n 3 "$log")" = "$(printf '%s\n' "install fakeroot" "record fakeroot" "adapt $WORKDIR/gui-runcmd.deb")" ]
}

@test "the tools installed first are recorded, and taken back when the run stops before the look" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR/w ROOT_PKGS=(apt-transport-https) HW_PKGS=() EARLY_PKGS=()
	mkdir -p "$WORKDIR"
	log=$BATS_TEST_TMPDIR/log
	installed_version() { :; }
	installed_names() { if [[ -s $log ]]; then printf '%s\n' a apt-transport-https libcurl3-gnutls; else echo a; fi; }
	as_root() { echo "$*" >>"$log"; }
	record_add() { sed "s#^#$(basename "$1"): #" >>"$log"; }
	install_now apt-transport-https 2>/dev/null
	[ "${EARLY_PKGS[*]}" = "apt-transport-https libcurl3-gnutls" ]
	grep -qx 'installed-packages: apt-transport-https' "$log" && grep -qx 'installed-packages: libcurl3-gnutls' "$log"
	grep -qx 'installed-auto: libcurl3-gnutls' "$log"
	# A run that stops: they are removed, and a first install leaves no records
	: >"$log"
	_safe_purge_set() { printf '%s\n' "$@"; }
	sys_write() { cat >/dev/null; }
	stopped() { false || cleanup; }
	run stopped
	grep -q "purge .*apt-transport-https libcurl3-gnutls" "$log"
	# (only where this computer has no records of its own in SYS_DIR)
	if [[ ! -s $SYS_DIR/installed-packages && ! -e $SYS_DIR/hardware-packages ]]; then
		grep -qx "rm -rf -- $SYS_DIR" "$log"
	fi
	[[ $output == *"Removed apt-transport-https libcurl3-gnutls"* ]]
	# One that APT cannot remove alone stays recorded, for --uninstall
	: >"$log"
	_safe_purge_set() { echo libcurl3-gnutls; }
	run stopped
	[[ $output == *"apt-transport-https stay installed"*--uninstall* ]]
	grep -q "purge .*libcurl3-gnutls" "$log"
	run ! grep -q "rm -rf" "$log"
	# A run that ends well, or reaches the look's packages, keeps them
	: >"$log"
	mkdir -p "$WORKDIR"
	ended() { :; cleanup; }
	run ended
	[ ! -s "$log" ]
	grep -q '^	EARLY_PKGS=()$' <(sed -n '/^install_all()/,/^}/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh")
}

@test "--uninstall where the look is not installed changes nothing and does not restart" {
	init_colors
	detect_host() { H_ARCH=i386 H_PRETTY="Debian GNU/Linux 10 (buster)"; }
	adopt_session() { :; }; start_log() { echo LOGGED; }; risk_warning() { :; }
	uninstall() { echo UNINSTALLED; }
	look_installed() { return 1; }
	run main --uninstall
	[ "$status" -eq 0 ] && [[ $output == *"not installed on this computer: nothing to uninstall"* && $output != *LOGGED* && $output != *UNINSTALLED* ]]
	look_installed() { :; }
	run main --uninstall
	[ "$status" -eq 0 ] && [[ $output == *LOGGED*UNINSTALLED* ]]
	# Installed: a record in SYS_DIR, or the generated package
	unset -f look_installed; source <(sed -n '/^look_installed()/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh")
	ls() { :; }; installed_version() { :; }
	run ! look_installed
	ls() { echo installed-packages; }
	look_installed
	ls() { :; }; installed_version() { [[ $1 != rpios-look-debian ]] || echo 3.22.0; }
	look_installed
}

@test "every purge goes through _purge, which keeps running services until the restart" {
	# The only apt-get purge is _purge's own; APT's simulations do not count
	f=$BATS_TEST_DIRNAME/../rpios-look-legacy.sh
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
	WORKDIR=$BATS_TEST_TMPDIR REPO="" FETCH_PKGS=(gui-runcmd) APT_PKGS=() NOTES=()
	PKG_VER[gui-runcmd]=1
	as_root() { :; }; installed_version() { :; }; sys_write() { cat >/dev/null; }
	download_pkg() { echo "$WORKDIR/$1.deb"; }
	_debian_has() { [[ $1 == bash ]]; }
	for f in deps_drop wall_own_dir; do eval "$f() { printf '%s\\n' \"\$1\"; }"; done
	mkdir -p "$WORKDIR/x/DEBIAN"
	printf 'Package: gui-runcmd\nVersion: 1\nArchitecture: all\nMaintainer: x <x@x>\nConflicts: bash\nDescription: x\n' >"$WORKDIR/x/DEBIAN/control"
	dpkg-deb -b "$WORKDIR/x" "$WORKDIR/gui-runcmd.deb" >/dev/null 2>&1
	# A repack that fails (Debian 9 without fakeroot) stops before APT
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

@test "packages that need an unresolved package are left out, in turn" {
	init_colors
	H_SUITE=stretch H_ARCH=i386
	PKG_DEPS=([lxplug-a]="lxpanel (>= 0.9), libc6" [lxpanel]="gtk2-engines-clearlookspix" [theme]="x | gtk2-engines-pixbuf" [b]="libc6")
	IN_SET=([lxplug-a]=1 [lxpanel]=1 [theme]=1 [b]=1 [gtk2-engines-clearlookspix]=1)
	list=(lxplug-a lxpanel theme b)
	run drop_broken list gtk2-engines-clearlookspix
	[[ $output == *"lxpanel is left out: it needs gtk2-engines-clearlookspix"* && $output == *"lxplug-a is left out: it needs lxpanel"* ]]
	drop_broken list gtk2-engines-clearlookspix x 2>/dev/null
	[ "${list[*]}" = "theme b" ]
	[ -z "${IN_SET[lxpanel]:-}" ] && [ -n "${IN_SET[b]}" ]
}

@test "nothing of the look needs AccountsService: never asked for, nor bundled" {
	run ! grep -q 'accountsservice' <(sed -n '/^resolve_all() {$/,/^}$/p; /^download_mode() {$/,/^}$/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh")
}

@test "the magnifier: plugin and the program it starts, per release, off the panel" {
	O_MODE=install USE_NETMAN=0 WORKDIR=$BATS_TEST_TMPDIR
	pi_unpack() { return 1; }
	has_battery() { :; }
	rpi_aid() { echo aid; }
	_debian_has() { [[ " $DEBIAN " == *" $1 "* ]]; }
	index_names() { printf '%s\n' lxplug-menu lxplug-cputemp lxplug-ejecter lxplug-updater $NAMES; }
	mkdir -p "$WORKDIR/index/aid/bookworm"
	printf 'Package: raspberrypi-ui-mods\nRecommends: lxplug-cputemp, lxplug-magnifier, lxplug-updater\n' >"$WORKDIR/index/aid/bookworm/Packages-amd64"
	# Debian 12: mage-rpi (its mage is a transitional package for it)
	DEBIAN="" NAMES="lxplug-magnifier mage mage-rpi"
	out=$(pi_stack bookworm amd64)
	grep -qx lxplug-magnifier <<<"$out" && grep -qx mage-rpi <<<"$out" && grep -qx lxplug-cputemp <<<"$out"
	run ! grep -qxE 'mage|lxplug-updater' <<<"$out"
	# Debian 10 and 11: mage
	NAMES="lxplug-magnifier mage"
	out=$(pi_stack bookworm amd64)
	grep -qx lxplug-magnifier <<<"$out" && grep -qx mage <<<"$out"
	# Neither without a program, nor where Debian has a package named mage
	for NAMES in "lxplug-magnifier" "mage-rpi" "mage"; do
		out=$(pi_stack bookworm amd64)
		grep -qx lxplug-cputemp <<<"$out"
		run ! grep -qxE 'lxplug-magnifier|mage(-rpi)?' <<<"$out"
	done
	DEBIAN=mage NAMES="lxplug-magnifier mage"
	run ! grep -qxE 'lxplug-magnifier|mage' <<<"$(pi_stack bookworm amd64)"
	# The program goes with Raspberry Pi's panel build
	_stack_member mage && _stack_member mage-rpi && _stack_member lxplug-magnifier
	run ! _stack_member pishutdown
	# Not in the panel layout, as Raspberry Pi OS shows it only with its program
	SYS_ROOT=$BATS_TEST_TMPDIR/root
	mkdir -p "$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanel/plugins"
	for t in magnifier cputemp; do : >"$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanel/plugins/$t.so"; done
	f=$BATS_TEST_TMPDIR/panel
	printf 'Global {\n}\nPlugin {\n  type=cputemp\n}\nPlugin {\n  type=magnifier\n  Config {\n  }\n}\n' >"$f"
	out=$(_pi_layout "$f" lxpanel/plugins)
	grep -qx '  type=cputemp' <<<"$out"
	run ! grep -q magnifier <<<"$out"
}

@test "Ctrl+Alt+M stays, as in Raspberry Pi OS's keys, where the magnifier plugin is installed" {
	init_colors
	SYS_ROOT=$BATS_TEST_TMPDIR/root WORKDIR=$BATS_TEST_TMPDIR S_PI_PANEL=0 S_PI_STACK=1 USE_NETMAN=0
	mkdir -p "$SYS_ROOT/usr/bin" "$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanpi/plugins"
	printf '#!/bin/sh\n' >"$SYS_ROOT/usr/bin/lxpanelctl"; chmod +x "$SYS_ROOT/usr/bin/lxpanelctl"
	PATH=$SYS_ROOT/usr/bin:$PATH
	pi=$BATS_TEST_TMPDIR/lxde-pi-rc.xml rc=$BATS_TEST_TMPDIR/rc.xml
	printf '%s\n' '<openbox_config>' '  <keyboard>' '    <keybind key="C-A-M">' '      <action name="Execute">' \
		'         <command>lxpanelctl command magnifier toggle</command>' '      </action>' '    </keybind>' \
		'    <keybind key="C-A-S">' '      <action name="Execute">' '         <command>lxpanelctl move</command>' \
		'      </action>' '    </keybind>' '  </keyboard>' '</openbox_config>' >"$pi"
	: >"$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanpi/plugins/magnifier.so"
	cp "$pi" "$rc"
	_openbox_keys "$rc" "$pi"
	grep -A2 'key="C-A-M"' "$rc" | grep -q 'command magnifier toggle'
	grep -A2 'key="C-A-S"' "$rc" | grep -q 'lxpanelctl move'
	# Raspberry Pi OS 9's keys have none, and none is added
	printf '<openbox_config>\n  <keyboard>\n  </keyboard>\n</openbox_config>\n' >"$pi"
	cp "$pi" "$rc"
	_openbox_keys "$rc" "$pi"
	run ! grep -q magnifier "$rc"
	# Without the plugin it goes
	rm "$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanpi/plugins/magnifier.so"
	printf '<openbox_config>\n  <keyboard>\n  </keyboard>\n</openbox_config>\n' >"$rc"
	_openbox_keys "$rc"
	run ! grep -q magnifier "$rc"
}

@test "Debian 9 takes Stretch's own panel build, only where Debian 9 meets its dependencies" {
	init_colors
	H_SUITE=stretch H_ARCH=amd64 O_MODE=install REPO=""
	index_load() { :; }
	index_candidates() {
		case $2 in
			stretch) printf '0.9.3-1+rpi7\tamd64\tpool/ui/l/lxpanel.deb\taa\t1\tlibgtk2.0-0 (>= 2.24.0)\n' ;;
			buster) printf '0.10.0-2+rpt1\tamd64\tpool/main/l/lxpanel.deb\tbb\t1\tlibc6 (>= 2.28)\n' ;;
		esac
	}
	_deps_satisfiable() { [[ -z ${DEPFAIL:-} ]]; }
	resolve_pkg lxpanel
	[ "${PKG_SUITE[lxpanel]}" = stretch ] && [ "${PKG_VER[lxpanel]}" = 0.9.3-1+rpi7 ]
	DEPFAIL=1
	run ! resolve_pkg lxpanel
}

@test "Qt follows Raspberry Pi OS's style per release, through Debian's packages" {
	for s in stretch buster bookworm; do
		[ "$(qt_theme "$s")" = gtk2 ] && [ "$(qt_debs "$s")" = qt5-style-plugins ]
	done
	[ "$(qt_theme bullseye)" = gtk3 ] && [ "$(qt_debs bullseye)" = qt5-gtk-platformtheme ]
}

@test "Raspberry Pi's components: main, and ui where the index lists it" {
	WORKDIR=$BATS_TEST_TMPDIR
	release_load() { :; }
	mkdir -p "$WORKDIR/index/rpi/stretch" "$WORKDIR/index/rpi/bookworm"
	printf '%s\n' 'SHA256:' ' aa 1 main/binary-i386/Packages.gz' ' bb 1 ui/binary-i386/Packages.gz' \
		' cc 1 untested/binary-i386/Packages.gz' >"$WORKDIR/index/rpi/stretch/Release"
	printf '%s\n' 'SHA256:' ' aa 1 main/binary-i386/Packages.xz' >"$WORKDIR/index/rpi/bookworm/Release"
	[ "$(rpi_components stretch i386 | xargs)" = "main ui" ]
	[ "$(rpi_components bookworm i386 | xargs)" = main ]
	[ -z "$(rpi_components stretch amd64)" ]
}

@test "Debian 9 defaults to PiX, the others to PiXflat" {
	H_RANK=9; [ "$(default_theme)" = pix ]
	H_RANK=10; [ "$(default_theme)" = pixflat ]
	H_RANK=12; [ "$(default_theme)" = pixflat ]
}

@test "release order: suite_ge and suite_rank" {
	suite_ge bookworm bullseye
	suite_ge bookworm bookworm
	run ! suite_ge bullseye bookworm
	[ "$(suite_rank stretch)" = 9 ]
	[ "$(suite_rank buster)" = 10 ]
}

@test "Debian 9 to 12 package names" {
	# Debian's tray icons start in every session: never installed
	[[ ! $(USE_NETMAN=0 tray_debs bookworm 1) =~ network-manager-gnome|blueman ]]
	[[ $(theme_debs) == *fonts-liberation2* ]]
	[ "$SESSION_PROFILE" = LXDE-pi ] && [ "$OB_FILE" = lxde-pi-rc.xml ] && [ "$MENU_PREFIX" = lxde-pi- ]
}

@test "Wi-Fi firmware files map to Debian's packages" {
	[ "$(firmware_pkg ipw2200-bss.fw)" = firmware-ipw2x00 ]
	[ "$(firmware_pkg ipw2100-1.3.fw)" = firmware-ipw2x00 ]
	[ "$(firmware_pkg iwlwifi-6000-4.ucode)" = firmware-iwlwifi ]
	[ "$(firmware_pkg rtlwifi/rtl8192cfw.bin)" = firmware-realtek ]
	[ "$(firmware_pkg rtl8192eu_nic.bin)" = firmware-realtek ]
	[ "$(firmware_pkg rtw88/rtw8822c_fw.bin)" = firmware-realtek ]
	[ "$(firmware_pkg rtw89/rtw8852a_fw.bin)" = firmware-realtek ]
	[ "$(firmware_pkg htc_9271.fw)" = firmware-atheros ]
	[ "$(firmware_pkg mediatek/mt7961_patch_mcu_1_2_hdr.bin)" = firmware-misc-nonfree ]
	[ "$(firmware_pkg mt7601u.bin)" = firmware-misc-nonfree ]
	# Ethernet and Bluetooth firmware
	for f in rtl_nic/rtl8168g-2.fw rtl_bt/rtl8761b_fw.bin ar3k/AthrBT_0x01020001.dfu ath3k-1.fw \
		qca/rampatch_00130302.bin brcm/BCM20702A1-0a5c-21e8.hcd mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin; do
		run ! firmware_pkg "$f"
	done
	[ "$(firmware_pkg ath10k/QCA6174/hw3.0/firmware-6.bin)" = firmware-atheros ]
	[ "$(firmware_pkg ar9271.fw)" = firmware-atheros ]
	[ "$(firmware_pkg brcm/brcmfmac43430-sdio.bin)" = firmware-brcm80211 ]
	[ "$(firmware_pkg rt2870.bin)" = firmware-misc-nonfree ]
	[ "$(firmware_pkg rt73.bin)" = firmware-misc-nonfree ]
	[ "$(firmware_pkg libertas/usb8388.bin)" = firmware-libertas ]
	[ "$(firmware_pkg zd1211/zd1211_ub)" = firmware-zd1211 ]
	[ "$(firmware_pkg ti-connectivity/wl1271-nvs.bin)" = firmware-ti-connectivity ]
	run ! firmware_pkg i915/kbl_dmc_ver1_04.bin
	run ! firmware_pkg amdgpu/polaris10_mc.bin
}

@test "the kernel log gives the driver and the missing firmware file" {
	log=$'Nov 05 10:00:01 pc kernel: ipw2200 0000:02:02.0: firmware: failed to load ipw2200-bss.fw (-2)\n'
	log+=$'[    5.120000] ipw2200 0000:02:02.0: firmware: failed to load ipw2200-bss.fw (-2)\n'
	log+=$'[    6.000000] iwlwifi 0000:03:00.0: Direct firmware load for iwlwifi-6000-6.ucode failed with error -2\n'
	log+=$'[    6.100000] e1000e 0000:00:19.0 eth0: NIC Link is Up\n'
	[ "$(firmware_failures <<<"$log")" = $'ipw2200 ipw2200-bss.fw\niwlwifi iwlwifi-6000-6.ucode' ]
}

@test "firmware is installed only for Wi-Fi drivers, reloaded only while down" {
	SYS_ROOT=$BATS_TEST_TMPDIR/root
	n=$SYS_ROOT/sys/class/net
	mkdir -p "$SYS_ROOT/drivers/r8169" "$SYS_ROOT/drivers/iwlwifi" "$n/eth0/device" "$n/wlan0/device" "$n/wlan0/wireless"
	ln -s "$SYS_ROOT/drivers/r8169" "$n/eth0/device/driver"
	ln -s "$SYS_ROOT/drivers/iwlwifi" "$n/wlan0/device/driver"
	echo 0x1003 >"$n/eth0/flags"
	echo 0x1002 >"$n/wlan0/flags"
	run ! wifi_driver r8169
	wifi_driver iwlwifi
	# a card without an interface yet (it could not start without firmware)
	wifi_driver ipw2200
	driver_up r8169
	run ! driver_up iwlwifi
	run ! driver_up ipw2200
}

@test "wicd counts as unset only with exactly 'wireless_interface = None'" {
	f=$BATS_TEST_TMPDIR/manager-settings.conf
	printf '[Settings]\nwireless_interface = None\nwired_interface = eth0\n' >"$f"
	wicd_unset "$f"
	printf '[Settings]\nwireless_interface = wlan0\n' >"$f"
	run ! wicd_unset "$f"
	printf '[Settings]\nwireless_interface = None # set\n' >"$f"
	run ! wicd_unset "$f"
	run ! wicd_unset "$BATS_TEST_TMPDIR/missing"
}

@test "the Wi-Fi interface is one with wireless or phy80211" {
	SYS_ROOT=$BATS_TEST_TMPDIR/root
	mkdir -p "$SYS_ROOT/sys/class/net/eth0" "$SYS_ROOT/sys/class/net/lo"
	run ! wifi_iface
	mkdir -p "$SYS_ROOT/sys/class/net/wlan0/wireless"
	[ "$(wifi_iface)" = wlan0 ]
	rm -r "$SYS_ROOT/sys/class/net/wlan0"
	mkdir -p "$SYS_ROOT/sys/class/net/wlp2s0"
	touch "$SYS_ROOT/sys/class/net/wlp2s0/phy80211"
	[ "$(wifi_iface)" = wlp2s0 ]
}

@test "the licence is the text of the package's own question" {
	t=$BATS_TEST_TMPDIR/templates
	printf '%s\n' 'Template: firmware-x/license/accepted' 'Type: boolean' 'Default: false' \
		'Description: Do you agree to the "X License"?' ' You must agree.' ' .' ' TERMS' \
		'Description-de.UTF-8: Stimmen Sie zu?' ' Nein.' '' 'Template: firmware-x/license/error' 'Type: error' \
		'Description: Declined' ' Not installed.' >"$t"
	[ "$(licence_text firmware-x "$t")" = $'Do you agree to the "X License"?\nYou must agree.\n\nTERMS' ]
	[ -z "$(licence_text firmware-y "$t")" ]
	[[ firmware-ipw2x00 =~ ^($FW_LICENSED)$ ]]
	[[ ! firmware-iwlwifi =~ ^($FW_LICENSED)$ ]]
}

@test "Fn+F7 opens lxrandr, only where it is installed" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR S_PI_PANEL=0 S_PI_STACK=0 USE_NETMAN=0
	bin=$BATS_TEST_TMPDIR/bin rc=$BATS_TEST_TMPDIR/rc.xml
	mkdir -p "$bin" "$BATS_TEST_TMPDIR/tools"
	# The system's programs, without the display tools the test adds itself
	for f in /usr/bin/*; do
		case ${f##*/} in lxrandr|arandr) ;; *) ln -s "$f" "$BATS_TEST_TMPDIR/tools/" ;; esac
	done
	PATH=$bin:$BATS_TEST_TMPDIR/tools
	printf '<openbox_config>\n  <keyboard>\n  </keyboard>\n</openbox_config>\n' >"$rc"
	_openbox_keys "$rc"
	run ! grep -q XF86Display "$rc"
	printf '#!/bin/sh\n' >"$bin/arandr"
	chmod +x "$bin/arandr"
	_openbox_keys "$rc"
	run ! grep -q XF86Display "$rc"
	cp "$bin/arandr" "$bin/lxrandr"
	_openbox_keys "$rc"
	_openbox_keys "$rc"
	grep -A2 'key="XF86Display"' "$rc" | grep -q '<command>lxrandr</command>'
	[ "$(grep -c 'key="XF86Display"' "$rc")" = 1 ]
}

@test "keys: the power button only where Raspberry Pi OS binds it (12); none that neither it nor Debian's LXDE binds" {
	init_colors
	SYS_ROOT=$BATS_TEST_TMPDIR/root WORKDIR=$BATS_TEST_TMPDIR S_PI_PANEL=0 S_PI_STACK=1 USE_NETMAN=0
	mkdir -p "$SYS_ROOT/usr/bin"
	for p in lxpanelctl lxtask scrot pishutdown lxterminal; do printf '#!/bin/sh\n' >"$SYS_ROOT/usr/bin/$p"; done
	chmod +x "$SYS_ROOT/usr/bin"/*
	PATH=$SYS_ROOT/usr/bin:/usr/bin:/bin
	pi=$BATS_TEST_TMPDIR/lxde-pi-rc.xml rc=$BATS_TEST_TMPDIR/rc.xml
	# Raspberry Pi OS 12's file binds the power button to pwrkey, which is not installed
	printf '%s\n' '<openbox_config>' '  <keyboard>' '    <keybind key="XF86PowerOff">' '      <action name="Execute">' \
		'        <command>pwrkey</command>' '      </action>' '    </keybind>' '  </keyboard>' '</openbox_config>' >"$pi"
	cp "$pi" "$rc"
	_openbox_keys "$rc" "$pi"
	grep -A2 'key="XF86PowerOff"' "$rc" | grep -q "<command>$SHARE/pwrkey</command>"
	# Raspberry Pi OS 9 to 11 leave it to logind
	printf '<openbox_config>\n  <keyboard>\n  </keyboard>\n</openbox_config>\n' >"$pi"
	cp "$pi" "$rc"
	_openbox_keys "$rc" "$pi"
	run ! grep -q XF86PowerOff "$rc"
	# Without Raspberry Pi OS's file: the release's keys over Debian's
	for s in bullseye bookworm; do
		printf '<openbox_config>\n  <keyboard>\n  </keyboard>\n</openbox_config>\n' >"$rc"
		H_SUITE=$s _openbox_keys "$rc"
		for k in Super_L C-Escape A-F2 C-A-S C-A-T C-S-Escape Print C-A-End C-A-Delete; do grep -q "key=\"$k\"" "$rc"; done
		if [ $s = bookworm ]; then grep -q 'key="XF86PowerOff"' "$rc"; else run ! grep -q XF86PowerOff "$rc"; fi
		run ! grep -qE 'key="(C-A-L|XF86ScreenSaver|XF86WLAN)"' "$rc"
		run ! grep -q wireless-radio "$rc"
	done
}

@test "the compositor's starter: only with NVIDIA's driver; picom runs while the session is shown, starts again when it comes back, and the starter ends with picom; it sleeps, reading nothing at intervals" {
	compositor_build "$BATS_TEST_TMPDIR/out"
	d=$BATS_TEST_TMPDIR; c=$d/compositor; mkdir -p "$d/bin"
	sed -e "s|/sys/module/nvidia|$d/nvidia|" -e "s|/sys/class/tty/tty0/active|$d/active|" "$d/out$SHARE/compositor" >"$c"
	python3 -m py_compile "$c"; ! grep -q 'sleep' "$c"
	printf '#!/bin/sh\necho "$$" >>"%s/started"\nexec sleep 30\n' "$d" >"$d/bin/picom"; chmod +x "$d/bin/picom"
	echo tty7 >"$d/active"
	# Another driver: nothing starts
	PATH=$d/bin:$PATH XDG_VTNR=7 python3 "$c"; [ ! -e "$d/started" ]
	mkdir "$d/nvidia"
	PATH=$d/bin:$PATH XDG_VTNR=7 python3 "$c" 3>&- & s=$!
	n() { wc -l <"$d/started" 2>/dev/null || echo 0; }
	till() { for _ in {1..50}; do [ "$(n)" = "$1" ] && return; sleep 0.1; done; false; }
	till 1
	# Another virtual terminal is shown, then the session's again (the kernel's report: here a signal)
	echo tty3 >"$d/active"; kill -CHLD $s; sleep 0.3; [ "$(n)" = 1 ]
	echo tty7 >"$d/active"; kill -CHLD $s; till 2
	! kill -0 "$(sed -n 1p "$d/started")" 2>/dev/null
	# picom ends: the starter ends with it
	kill "$(sed -n 2p "$d/started")"; wait $s
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

@test "GTK 3 text in the desktop font's weight, as Raspberry Pi's GTK draws it" {
	# The function as session-env has it, run with a session's files
	eval "$(sed -n '/^gtk_weight() {$/,/^}$/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh")"
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
	WORKDIR=$BATS_TEST_TMPDIR S_PROFILE=$SESSION_PROFILE S_FM_PROFILE=default S_PI_STACK=1 H_SUITE=bookworm H_RANK=12; _term_cmd() { echo lxterminal; }
	O_SIZE=medium set_theme "pixflat"
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

@test "the session hides IBus's tray icon in its own dconf defaults, which IBus reads" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR
	set_theme pixflat
	dconf() { return 1; }
	_session_dconf "$BATS_TEST_TMPDIR/root" 2>/dev/null
	grep -A1 -x '\[desktop/ibus/panel\]' "$WORKDIR/dconf-keys/00-rpios-look" | grep -qx 'show-icon-on-systray=false'
	dconf() { :; }
	_session_dconf "$BATS_TEST_TMPDIR/root"
	# IBus starts before the session's start script (70im-config_launch): the
	# session's profile is set before it, for this session only
	x=$BATS_TEST_TMPDIR/root/etc/X11/Xsession.d/60rpios-look_dconf
	[ "$(env -i XDG_SESSION_DESKTOP=rpios-look sh -c ". $x; echo \$DCONF_PROFILE")" = /usr/share/rpios-look/dconf/profile ]
	[ "$(env -i GDMSESSION=rpios-look sh -c ". $x; echo \$DCONF_PROFILE")" = /usr/share/rpios-look/dconf/profile ]
	[ -z "$(env -i XDG_SESSION_DESKTOP=LXDE GDMSESSION=rpios-look sh -c "set -eu; . $x; echo \${DCONF_PROFILE:-}")" ]
	[ -z "$(env -i sh -c "set -eu; . $x; echo \${DCONF_PROFILE:-}")" ]
}

@test "the session's GSettings leave the light or dark style unset, also with a dark theme, as Raspberry Pi OS 9 to 12" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR
	dconf() { :; }
	for t in pixflat pixnoir; do
		set_theme "$t"
		_session_dconf "$BATS_TEST_TMPDIR/root"
		grep -qx "gtk-theme='$T_GTK'" "$WORKDIR/dconf-keys/00-rpios-look"
		run ! grep -q color-scheme "$WORKDIR/dconf-keys/00-rpios-look"
	done
}

@test "a plain run resets the session's X settings database, its own panel profile or its menu, also when nothing else is there" {
	HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config XDG_DATA_HOME=$BATS_TEST_TMPDIR/home/.local/share
	f=$XDG_CONFIG_HOME
	for p in "dconf/${APP_NAME//-/}" lxpanel/rpd-x/panels "menus/lxde-pi-applications.menu"; do
		rm -rf "$f"; mkdir -p "$(dirname "$f/$p")"; touch "$f/$p"
		has_session_settings
		reset_session_settings
		[ ! -e "$f/$p" ] && ! has_session_settings
	done
}

@test "uninstall: the session choice LightDM wrote into ~/.dmrc goes; its other lines and other sessions stay" {
	HOME=$BATS_TEST_TMPDIR/home; mkdir -p "$HOME"; ok() { :; }
	for id in rpios-look; do
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

@test "an install puts the file manager's shared settings back to the session's: in libfm.conf only what the session sets; bookmarks, shortcuts, start entries, your other settings and files stay; --uninstall gives back what was there" {
	HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config XDG_STATE_HOME=$BATS_TEST_TMPDIR/home/.local/state
	f=$XDG_CONFIG_HOME/libfm/libfm.conf; mkdir -p "${f%/*}" "$HOME/Desktop" "$XDG_CONFIG_HOME/pcmanfm/default"
	warn() { :; }; ok() { :; }
	S_PROFILE=LXDE-pi O_SIZE=medium; set_theme pixflat
	echo "file://$HOME/Work" >"$HOME/.gtk-bookmarks"; mkdir "$HOME/Work"
	printf '[Desktop Entry]\nName=Game\n' >"$HOME/Desktop/game.desktop"; ln -s "$HOME/Work" "$HOME/Desktop/work"
	a=$XDG_CONFIG_HOME/autostart; mkdir -p "$a"
	printf '[Desktop Entry]\nName=Power times\nExec=xset s 300\n' >"$a/power-times.desktop"
	printf '[Desktop Entry]\nName=Screen Locker\nExec=light-locker --lock-after-screensaver=60\n' >"$a/light-locker.desktop"
	kept() {
		grep -qx 'Name=Game' "$HOME/Desktop/game.desktop" && [ "$(readlink "$HOME/Desktop/work")" = "$HOME/Work" ] \
			&& [ "$(cat "$HOME/.gtk-bookmarks")" = "file://$HOME/Work" ] \
			&& grep -qx 'Exec=xset s 300' "$a/power-times.desktop" && grep -q 'lock-after-screensaver=60' "$a/light-locker.desktop"
	}
	# No libfm.conf of yours: none is created
	_state_init; reset_file_manager; [ ! -e "$f" ]; kept
	# Yours: icon sizes, single click and places changed, and a setting the session does not set
	printf '[config]\nsingle_click=1\nconfirm_trash=0\n\n[ui]\nbig_icon_size=96\nsmall_icon_size=48\nshadow_hidden=1\n\n[places]\nplaces_trash=1\n' >"$f"
	cp "$f" "$BATS_TEST_TMPDIR/orig"; echo mine >"$HOME/Desktop/note.txt"; echo keep >"$XDG_CONFIG_HOME/pcmanfm/default/pcmanfm.conf"
	reset_file_manager; kept
	grep -qx 'single_click=0' "$f" && grep -qx "big_icon_size=$T_FOLDER_ICON" "$f" && grep -qx "small_icon_size=$T_SMALL_ICON" "$f" && grep -qx 'places_trash=0' "$f"
	grep -qx 'confirm_trash=0' "$f" && grep -qx 'shadow_hidden=1' "$f"
	[ "$(cat "$HOME/Desktop/note.txt")" = mine ] && [ "$(cat "$XDG_CONFIG_HOME/pcmanfm/default/pcmanfm.conf")" = keep ]
	# --uninstall undoes in libfm.conf only the values the install wrote: one you changed since stays
	sed -i 's/^pane_icon_size=.*/pane_icon_size=99/' "$f"
	restore_user
	grep -qx 'pane_icon_size=99' "$f" && grep -v '^pane_icon_size=' "$f" | cmp - "$BATS_TEST_TMPDIR/orig"
	# The desktop, the bookmarks and the start entries are as you left them
	kept; [ "$(ls "$HOME/Desktop" | wc -l)" = 3 ] && [ "$(ls "$a" | wc -l)" = 2 ] && [ ! -e "$XDG_STATE_HOME/rpios-look" ]
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
	_state_init; O_SIZE=large T_TERM_FONT="Monospace 15" term_font
	grep -qx 'fontname=Monospace 15' "$f" && grep -qx 'cursorblinks=true' "$f"
	O_SIZE=medium term_font; grep -qx 'fontname=Hack 11' "$f"
	O_SIZE=small T_TERM_FONT="Monospace 8" term_font; grep -qx 'fontname=Monospace 8' "$f"
	restore_user; cmp "$f" "$BATS_TEST_TMPDIR/orig"
	# An install sets it, and --refresh when --size is given
	grep -qx '	if \[\[ \$O_MODE != refresh \]\] || (( O_SIZE_GIVEN )); then term_font; fi' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh"
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
	[[ $output == *"bash rpios-look-legacy.sh --refresh"* ]]
	# Quiet while the script itself runs
	printf '#!/bin/sh\nexit 0\n' >"$bin/pgrep"
	run env PATH="$bin:$PATH" "$c"
	[ "$status" = 0 ] && [ -z "$output" ]
	sh -n "$r$SHARE/apt-check"
}

@test "uninstall of an rpios-look.sh install: its Wayland session's settings go too; your own labwc settings stay" {
	HOME=$BATS_TEST_TMPDIR/home XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/.config XDG_DATA_HOME=$BATS_TEST_TMPDIR/home/.local/share
	f=$XDG_CONFIG_HOME
	mkdir -p "$f/wf-panel-pi" "$f/labwc" "$f/dconf" "$f/kanshi"
	touch "$f/dconf/rpioslookwayland"; : >"$f/kanshi/config"
	printf '%s\n' '<?xml version="1.0"?>' '<openbox_config>' '  <theme><name>PiXtrix</name></theme>' '  <keyboard><keybind key="W-t"/></keyboard>' '</openbox_config>' >"$f/labwc/rc.xml"
	printf '%s\n' XCURSOR_THEME=PiXtrix-Debian XKB_DEFAULT_LAYOUT=fr >"$f/labwc/environment"
	# rpios-look-set recorded them as made by it
	st=$HOME/.local/state/rpios-look; mkdir -p "$st"
	printf 'file:.config/labwc/rc.xml\nfile:.config/labwc/environment\n' >"$st/keys"
	has_session_settings
	XDG_STATE_HOME=$HOME/.local/state reset_session_settings
	[ ! -e "$f/wf-panel-pi" ] && [ ! -e "$f/dconf/rpioslookwayland" ] && [ ! -e "$f/kanshi/config" ]
	run ! grep -q PiXtrix "$f/labwc/rc.xml"; grep -q 'W-t' "$f/labwc/rc.xml"
	[ "$(cat "$f/labwc/environment")" = XKB_DEFAULT_LAYOUT=fr ]
	# And its login choice
	ok() { :; }; printf '[Desktop]\nSession=rpios-look-wayland\n' >"$HOME/.dmrc"; forget_dmrc
	run ! grep -q Session= "$HOME/.dmrc"
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
	eval "$(sed -n '/^replace() {/,/^get() {/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh")"
	die() { echo "$*"; return 1; }
	d=$BATS_TEST_TMPDIR/cfg; mkdir -p "$d/real"
	printf '[GTK]\nsNet/ThemeName=PiXflat\n\n[Session]\nx=1\n' >"$d/real/desktop.conf"
	chmod 0640 "$d/real/desktop.conf"
	ln -s real/desktop.conf "$d/desktop.conf"
	ino=$(stat -c %i "$d/real/desktop.conf")
	edit "$d/desktop.conf" /dev/null ini_edit GTK sNet/ThemeName=PiXnoir
	[ -L "$d/desktop.conf" ] && [ "$(stat -c %i "$d/real/desktop.conf")" != "$ino" ] && [ "$(stat -c %a "$d/real/desktop.conf")" = 640 ]
	[ "$(ini_get "$d/desktop.conf" GTK sNet/ThemeName)" = PiXnoir ] && [ "$(ini_get "$d/desktop.conf" Session x)" = 1 ]
	edit "$d/desktop.conf" /dev/null ini_edit Session x
	[ -z "$(ini_get "$d/desktop.conf" Session x)" ] && grep -qx '\[Session\]' "$d/desktop.conf"
	# The first change makes the user's copy from the session's file
	edit "$d/new/desktop.conf" "$d/real/desktop.conf" ini_edit Session x=2
	[ "$(ini_get "$d/new/desktop.conf" Session x)" = 2 ]
	[ "$(ini_get "$d/new/desktop.conf" GTK sNet/ThemeName)" = PiXnoir ]
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
	WORKDIR=$BATS_TEST_TMPDIR S_PROFILE=rpd-x
	r=$BATS_TEST_TMPDIR/root
	set_theme pixflat
	_session_command "$r"
	share=$r$SHARE bin=$BATS_TEST_TMPDIR/bin
	sed "s|^APP=\(.*\) SHARE=$SHARE |APP=\1 SHARE=$share |" "$r/usr/bin/rpios-look-set" >"$BATS_TEST_TMPDIR/set"
	grep -q "SHARE=$share " "$BATS_TEST_TMPDIR/set"
	mkdir -p "$share/xdg/lxsession/rpd-x" "$share/xdg/pcmanfm/rpd-x" "$share/dconf" "$bin"
	printf '[GTK]\nsNet/ThemeName=PiXflat\n\n[Mouse]\nLeftHanded=0\n' >"$share/xdg/lxsession/rpd-x/desktop.conf"
	printf '[*]\nwallpaper=/w.jpg\n' >"$share/xdg/pcmanfm/rpd-x/desktop-items-0.conf"
	mkdir -p "$share/xdg/openbox"
	printf '%s\n' '<openbox_config xmlns="http://openbox.org/3.4/rc">' '  <keyboard>' '    <keybind key="C-A-T"/>' '  </keyboard>' \
		'  <theme>' '    <name>PiXflat</name>' '    <roundCorners>yes</roundCorners>' '    <animateIconify>yes</animateIconify>' \
		'    <font place="ActiveWindow">' '      <name>PibotoLt</name>' '    </font>' '  </theme>' '</openbox_config>' \
		>"$share/xdg/openbox/$OB_FILE"
	: >"$share/dconf/profile"
	export HOME=$BATS_TEST_TMPDIR/home XDG_DATA_HOME=$BATS_TEST_TMPDIR/home/data XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/home/config
	for t in PiXflat PiXnoir; do mkdir -p "$XDG_DATA_HOME/themes/$t/gtk-3.0" "$XDG_DATA_HOME/icons/$t-Debian"
		: >"$XDG_DATA_HOME/themes/$t/gtk-3.0/gtk.css"; : >"$XDG_DATA_HOME/icons/$t-Debian/index.theme"; done
	printf '#!/bin/sh\necho "$DCONF_PROFILE $*" >>"%s"\n' "$BATS_TEST_TMPDIR/dconf.log" >"$bin/dconf"
	printf '#!/bin/sh\nexit 1\n' >"$bin/pgrep"
	printf '#!/bin/sh\nfor f; do :; done; echo "${f##*/}" >>"%s"; exec /bin/mv "$@"\n' "$BATS_TEST_TMPDIR/mv.log" >"$bin/mv"
	chmod +x "$bin"/*
}

@test "rpios-look-set: one change writes each file once, at once" {
	make_set
	c=$XDG_CONFIG_HOME
	for o in "--theme pixnoir --animations off" "--theme pixflat" --reset; do
		: >"$BATS_TEST_TMPDIR/mv.log"
		# shellcheck disable=SC2086  # options and their values
		PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" $o >/dev/null
		ob=$OB_FILE; [ "$o" != --reset ] || ob=""
		LC_ALL=C sort "$BATS_TEST_TMPDIR/mv.log" | diff - <(printf '%s\n' desktop-items-0.conf desktop.conf $ob)
		grep -qx LeftHanded=0 "$c/lxsession/rpd-x/desktop.conf"
	done
	grep -qx sNet/ThemeName=PiXflat "$c/lxsession/rpd-x/desktop.conf"
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
	PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --theme pixnoir --animations off >/dev/null
	run ! grep -q keyboard "$c"
	grep -qx '    <name>PiXnoir</name>' "$c"
	grep -qx '    <animateIconify>no</animateIconify>' "$c"
	grep -q '^<openbox_config xmlns="http://openbox.org/3.4/rc">$' "$c" && [ "$(tail -n 1 "$c")" = '</openbox_config>' ]
	out=$(PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --show); grep -qx "Windows        PiXnoir" <<<"$out"
	# Your own file is changed, not replaced by the session's
	sed -i 's|</openbox_config>|  <desktops><number>2</number></desktops>\n&|' "$c"
	PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --theme pixflat >/dev/null
	grep -q '<number>2</number>' "$c" && grep -qx '    <name>PiXflat</name>' "$c"
	PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --reset >/dev/null
	[ ! -e "$c" ]
	out=$(PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --show); grep -qx "Windows        PiXflat" <<<"$out"
	# Debian's Openbox reads one file: all of the session's settings
	rm "$pi"
	PATH="$bin:$PATH" bash "$BATS_TEST_TMPDIR/set" --theme pixnoir >/dev/null
	grep -q '<keybind key="C-A-T"/>' "$c" && grep -qx '    <name>PiXnoir</name>' "$c"
}

@test "the session's Openbox settings are where Raspberry Pi's Openbox reads them; login never writes your file" {
	WORKDIR=$BATS_TEST_TMPDIR S_PI_STACK=1 S_PROFILE=LXDE-pi H_SUITE=bookworm
	r=$BATS_TEST_TMPDIR/root
	_session_programs "$r"
	grep -qx "exec $SHARE/bin/openbox --config-file \"\${XDG_CONFIG_HOME:-\$HOME/.config}/openbox/$OB_FILE\" \"\$@\"" "$r$SHARE/openbox"
	# The start script never writes the user's Openbox file
	run ! grep -q 'config/openbox' "$r$SHARE/start"
	run ! grep -q '<keyboard>' "$r$SHARE/start"
}

@test "rpios-look-set leaves GSettings alone, as Raspberry Pi OS 9 to 12's Appearance Settings does" {
	make_set
	for o in "--theme pixnoir" --reset; do
		# shellcheck disable=SC2086  # an option and its value
		PATH="$bin:$PATH" DBUS_SESSION_BUS_ADDRESS=unix:path=/x bash "$BATS_TEST_TMPDIR/set" $o >/dev/null
	done
	grep -qx sNet/ThemeName=PiXflat "$XDG_CONFIG_HOME/lxsession/rpd-x/desktop.conf"
	[ ! -e "$BATS_TEST_TMPDIR/dconf.log" ]
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

@test "versions compare by number" {
	version_newer 3.22.1 3.22.0
	version_newer 3.23.0 3.22.9
	version_newer 3.22.10 3.22.9
	version_newer 4.0 3.22.0
	version_newer 3.22.0.1 3.22.0
	run ! version_newer 3.22.0 3.22.0
	run ! version_newer 3.21.9 3.22.0
	run ! version_newer 3.22 3.22.0
	run ! version_newer "" 3.22.0
	run ! version_newer '3.22.0"; rm -rf /' 3.22.0
}

@test "only Debian's LXDE is accepted" {
	H_LXDE=0; run ! require_lxde
	[[ $output == *"LXDE only"* ]]
}

@test "APT's lists follow Raspberry Pi's archive in the sources: added, changed, removed" {
	init_colors
	log=$BATS_TEST_TMPDIR/log src=$BATS_TEST_TMPDIR/src have=0
	as_root() { echo "$*" >>"$log"; }
	compgen() { (( have )); }
	cat() { if [[ $2 == "$APT_SRC" ]]; then command cat "$src"; else command cat "$@"; fi; }
	# The functions read the real paths; stand-ins for them
	eval "$(sed -n '/^apt_lists_sync()/,/^}/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh" | sed "s#\[\[ -f \$APT_SRC \]\]#[[ -f $src ]]#")"
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
	f=$(sed -n '/^install_mode()/,/^}/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh")
	(( $(grep -n 'src=$(cat -- "$APT_SRC"' <<<"$f" | cut -d: -f1) < $(grep -nx $'\tinstall_pkg' <<<"$f" | cut -d: -f1) ))
	(( $(grep -nx $'\tinstall_pkg' <<<"$f" | cut -d: -f1) < $(grep -nxF $'\tapt_lists_sync "$src"' <<<"$f" | cut -d: -f1) ))
}

@test "versioned Provides: a dependency on a version needs a provider of that version" {
	init_colors
	IN_SET=() AVAIL=()
	# Building packages/: the Debian index's Provides
	DEP_INDEX=$BATS_TEST_TMPDIR/names
	printf '%s\n' 'libqt5core5a 5.15.8' 'qtbase-abi-5-15-8 5.15.8' 'x-terminal-emulator' >"$DEP_INDEX"
	_deps_satisfiable "qtbase-abi-5-15-8 (= 5.15.8), x-terminal-emulator"
	run ! _deps_satisfiable "qtbase-abi-5-15-8 (= 5.15.2)"
	run ! _deps_satisfiable "x-terminal-emulator (>= 1)"
	# Installing: the APT sources' providers, at their installed or candidate versions
	DEP_INDEX="" AVAIL=()
	apt-cache() {
		case "$1" in
			showpkg) printf '%s\n' 'Reverse Provides: ' 'libqt5core5a 5.15.8+dfsg-11 (= 5.15.8)' 'libqt5core5a 5.15.2+dfsg-9 (= 5.15.2)' ;;
			policy) [[ $2 != libqt5core5a ]] || printf '%s:\n  Installed: (none)\n  Candidate: 5.15.8+dfsg-11\n' "$2" ;;
		esac
	}
	installed_version() { :; }; apt_has() { :; }
	[ "$(_provided qtbase-abi-5-15-8)" = 5.15.8 ]
	_deps_satisfiable "qtbase-abi-5-15-8 (= 5.15.8)"
	run ! _deps_satisfiable "qtbase-abi-5-15-8 (= 5.15.2)"
}

@test "a twin's exact Raspberry Pi version of a Debian package, which repacking drops, is not asked for" {
	d='libnma-common (= 1.10.6-5+rpt1), libc6 (>= 2.34), libfm4 (= 1.3.2-1+rpt1) | libx (= 1+rpi2)'
	[ "$(twin_deps libnma0 "$d")" = 'libnma-common, libc6 (>= 2.34), libfm4 (= 1.3.2-1+rpt1) | libx' ]
	[ "$(twin_deps lxplug-netman "$d")" = "$d" ]
}

@test "repacking beside Debian's: own package, program, folder and library names, written in place" {
	h=$BATS_TEST_TMPDIR/beside WORKDIR=$BATS_TEST_TMPDIR
	beside_build "$h"
	lib=$(mkdeb libfm4 1.3-1+rpt1 $'Depends: libfm-data (= 1.3-1+rpt1), libc6\nBreaks: libfm4 (<< 1)\nProvides: libfm\n' \
		'usr/lib/x86_64-linux-gnu/libfm.so.4.1.3=ELF:libfm.so.4|libc.so.6|/usr/lib/x86_64-linux-gnu/libfm/modules' \
		'usr/lib/x86_64-linux-gnu/libfm.so.4=LINK:libfm.so.4.1.3' 'usr/share/locale/de/LC_MESSAGES/libfm.mo=mo' \
		'usr/share/doc/libfm4/copyright=c')
	panel=$(mkdeb lxpanel 0.10-2+rpt1 $'Depends: libfm4 (>= 1.2), libnma-common (= 1.10-1+rpt1), lxpanel-data\nRecommends: lxpanel-extra\n' \
		'usr/bin/lxpanel=ELF:libfm.so.4|libc.so.6|/usr/share/lxpanel/ui/a.ui|/usr/lib/x86_64-linux-gnu/lxpanel' \
		'usr/bin/lxpanel-tool=tool' 'usr/share/lxpanel/ui/a.ui=ui' 'etc/xdg/lxpanel/default/config=c' \
		'usr/share/applications/lxde-x-www-browser.desktop=d')
	fm=$(mkdeb pcmanfm 1.3-1+rpt2 '' 'usr/bin/pcmanfm=ELF:/usr/share/pcmanfm/ui/x.ui|libfm.so.4' 'usr/share/pcmanfm/ui/x.ui=ui' \
		$'usr/share/applications/pcmanfm.desktop=[Desktop Entry]\nExec=pcmanfm %U\nTryExec=pcmanfm')
	plug=$(mkdeb lxplug-x 1.0 $'Depends: lxpanel (>= 0.10)\n' 'usr/lib/x86_64-linux-gnu/lxpanel/plugins/x.so=ELF:/usr/share/lxpanel/images/x.png')
	mag=$(mkdeb mage-rpi 1.0 $'Depends: lxplug-x | lpplug-x\n' 'usr/bin/mage-rpi=ELF:libc.so.6')
	other=$(mkdeb pishutdown 1.0 $'Depends: libc6\n' 'usr/bin/pishutdown=ELF:libc.so.6|/usr/share/lxpanel-pi/ui/x.ui')
	conf=$BATS_TEST_TMPDIR/conf
	printf 'twins=libfm4 lxpanel pcmanfm\nlibs=%s\nbeside=\n' "$("$h" sonames "$lib" "$panel" | xargs)" >"$conf"
	[ "$(sed -n 's/^libs=//p' "$conf")" = libfm.so.4 ]
	# Which packages need it: the twins, a plugin in their folders, what
	# depends on one repacked; not the others
	"$h" need "$conf" "$panel" && "$h" need "$conf" "$plug"
	run ! "$h" need "$conf" "$mag"
	run ! "$h" need "$conf" "$other"
	sed -i 's/^beside=$/beside=lxplug-x/' "$conf"
	"$h" need "$conf" "$mag"
	[ -z "$("$h" pack "$conf" "$other" "$BATS_TEST_TMPDIR/out")" ]
	r=$BATS_TEST_TMPDIR/root c=()
	for d in "$lib" "$panel" "$fm" "$plug" "$mag"; do
		c+=("$("$h" pack "$conf" "$d" "$BATS_TEST_TMPDIR/out")")
		dpkg-deb -x "${c[-1]}" "$r"
	done
	# Own package names, the same versions, no relations to Debian's packages
	[ "$(dpkg-deb -f "${c[0]}" Package)" = rpios-look-libfm4 ] && [ "$(dpkg-deb -f "${c[0]}" Version)" = 1.3-1+rpt1 ]
	[ "$(dpkg-deb -f "${c[0]}" Depends)" = "libfm-data, libc6" ]
	[ -z "$(dpkg-deb -f "${c[0]}" Breaks)$(dpkg-deb -f "${c[0]}" Provides)$(dpkg-deb -f "${c[1]}" Recommends)" ]
	[ "$(dpkg-deb -f "${c[1]}" Depends)" = "rpios-look-libfm4 (>= 1.2), libnma-common, lxpanel-data" ]
	[ "$(dpkg-deb -f "${c[3]}" Depends)" = "rpios-look-lxpanel (>= 0.10)" ]
	[ "$(dpkg-deb -f "${c[4]}" Depends)" = "rpios-look-lxplug-x | lpplug-x" ]
	# Own files: library, program, folders, documentation; nothing of Debian's
	[ -f "$r/usr/lib/x86_64-linux-gnu/libfmpi.so" ] && [ ! -e "$r/usr/lib/x86_64-linux-gnu/libfm.so.4" ]
	[ -x "$r/usr/bin/lxpanel-pi" ] && [ -x "$r/usr/bin/pcmanfm-pi" ] && [ -x "$r/usr/bin/mage-rpi" ]
	[ ! -e "$r/usr/bin/lxpanel" ] && [ ! -e "$r/usr/bin/lxpanel-tool" ] && [ ! -e "$r/usr/bin/pcmanfm" ]
	[ -f "$r/usr/share/lxpanpi/ui/a.ui" ] && [ -f "$r/usr/lib/x86_64-linux-gnu/lxpanpi/plugins/x.so" ]
	[ ! -e "$r/etc" ] && [ ! -e "$r/usr/share/locale" ] && [ ! -e "$r/usr/share/applications" ] && [ ! -e "$r/usr/share/lxpanel" ]
	[ -f "$r/usr/share/doc/rpios-look-libfm4/copyright" ]
	# The file manager's menu entry, for the session only, in its own folder
	grep -qx 'Exec=pcmanfm-pi %U' "$r/usr/share/pcmanpi/pcmanfm-pi.desktop"
	grep -qx 'TryExec=pcmanfm-pi' "$r/usr/share/pcmanpi/pcmanfm-pi.desktop"
	# The names inside the programs, at the same length
	has_string "$r/usr/bin/lxpanel-pi" libfmpi.so && has_string "$r/usr/bin/lxpanel-pi" /usr/share/lxpanpi/ui/a.ui
	has_string "$r/usr/bin/lxpanel-pi" /usr/lib/x86_64-linux-gnu/lxpanpi && has_string "$r/usr/bin/lxpanel-pi" libc.so.6
	has_string "$r/usr/lib/x86_64-linux-gnu/libfmpi.so" libfmpi.so
	has_string "$r/usr/lib/x86_64-linux-gnu/libfmpi.so" /usr/lib/x86_64-linux-gnu/libpi/modules
	has_string "$r/usr/lib/x86_64-linux-gnu/lxpanpi/plugins/x.so" /usr/share/lxpanpi/images/x.png
	run ! grep -rqaE 'libfm\.so\.4|/usr/share/(lxpanel|pcmanfm)/' "$r/usr/bin" "$r/usr/lib"
	[ "$(stat -c %s "$r/usr/bin/lxpanel-pi")" = "$(dpkg-deb --fsys-tarfile "$panel" | tar -xO ./usr/bin/lxpanel | wc -c)" ]
	# The same input gives the same package
	[ "$(sha256sum <"${c[1]}")" = "$(sha256sum <"$("$h" pack "$conf" "$panel" "$BATS_TEST_TMPDIR/again")")" ]
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

@test "the panel, file manager, libfm, Openbox and libnma: Raspberry Pi's builds go beside Debian's" {
	FETCH_PKGS=(pixflat-theme lxpanel lxpanel-data pcmanfm libfm4 libfm-gtk4 libfm-extra4 openbox libobrender32v5 libnma0 lxplug-netman gui-runcmd)
	mapfile -t TWINS < <(printf '%s\n' "${FETCH_PKGS[@]}" | grep -xE "$TWIN_RE")
	[ "${TWINS[*]}" = "lxpanel lxpanel-data pcmanfm libfm4 libfm-gtk4 libfm-extra4 openbox libobrender32v5 libnma0" ]
	apt_versions() { echo 1; }
	_refuse_debian_names lxpanel libfm4 openbox libnma0
	run _refuse_debian_names lxpanel lxsession
	[ "$status" = 1 ] && [[ $output == *"refusing to install lxsession"* ]]
	BESIDE=(lxplug-netman) BESIDE_DONE=1
	[ "$(inst_name lxpanel)" = rpios-look-lxpanel ] && [ "$(inst_name lxplug-netman)" = rpios-look-lxplug-netman ]
	[ "$(inst_name gui-runcmd)" = gui-runcmd ]
	# Raspberry Pi's Openbox is part of the set on every release
	H_RANK=12
	[ "$(rpi_new_looks() { :; }; index_load() { return 1; }; pi_stack() { :; }; rpi_pkgs bookworm amd64 | grep -E '^(openbox|libob)' | xargs)" \
		= "openbox libobrender32v5" ]
}

@test "the session starts Raspberry Pi's panel, file manager and Openbox, by Debian's names too; Debian's LXDE gets nothing" {
	WORKDIR=$BATS_TEST_TMPDIR S_PI_STACK=1 S_PROFILE=LXDE-pi H_SUITE=bookworm
	_session_programs "$BATS_TEST_TMPDIR/root"
	r=$BATS_TEST_TMPDIR/root$SHARE
	grep -q "^exec $SHARE/bin/openbox --config-file " "$r/openbox"
	grep -qx 'if \[ -x /usr/bin/lxpanel-pi \]; then p=/usr/bin/lxpanel-pi; fi' "$r/panel" && grep -qx 'exec $p --profile LXDE-pi' "$r/panel"
	grep -qx "exec $SHARE/bin/pcmanfm --desktop --profile LXDE-pi" "$r/desktop"
	for p in openbox lxpanelctl pcmanfm; do
		grep -qx "if \[ -x /usr/bin/$p-pi \]; then exec /usr/bin/$p-pi \"\$@\"; fi" "$r/bin/$p"
		grep -qx "exec /usr/bin/$p \"\$@\"" "$r/bin/$p"
	done
	# Debian's panel where Raspberry Pi's is not used
	S_PI_STACK=0; _session_programs "$BATS_TEST_TMPDIR/deb"
	run ! grep -q lxpanel-pi "$BATS_TEST_TMPDIR/deb$SHARE/panel"
	# Nothing for Debian's LXDE session: no hook, no adapted layout
	run ! grep -rqE 'lxde-xdg|lxde-gtkrc' "$BATS_TEST_TMPDIR/root" "$BATS_TEST_TMPDIR/deb"
	run ! grep -q lxde_panel_build "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh"
	# The panel layout keeps the plugins of Raspberry Pi's own plugin folder
	SYS_ROOT=$BATS_TEST_TMPDIR/sys
	mkdir -p "$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanpi/plugins"
	: >"$SYS_ROOT/usr/lib/x86_64-linux-gnu/lxpanpi/plugins/smenu.so"
	printf 'Plugin {\n  type=smenu\n}\nPlugin {\n  type=volumepulse\n}\n' >"$BATS_TEST_TMPDIR/panel"
	_pi_stack_file() { echo "$BATS_TEST_TMPDIR/panel"; }; has_battery() { :; }; panel_drop() { echo updater; }
	_pi_stack_layout | grep -qx '  type=smenu'
	run ! grep -q volumepulse <<<"$(_pi_stack_layout)"
}

@test "before the repacked packages come: the repacked ones this run no longer uses go" {
	init_colors
	log=$BATS_TEST_TMPDIR/log
	_purge() { echo "purge $*" >>"$log"; }
	TWINS=(lxpanel openbox) BESIDE=(lxplug-menu mage-rpi)
	# Those in use and the session package stay; a package under its own name
	# is left alone
	_safe_purge_set() { printf "%s\n" "$@"; }
	installed_version() { echo 1; }
	dpkg-query() { printf '%s\n' 'ii  rpios-look-lxpanel' 'ii  rpios-look-lxplug-cputemp' 'ii  rpios-look-debian'; }
	beside_tidy
	[ "$(cat "$log")" = 'purge -q rpios-look-lxplug-cputemp' ]
	# Nothing to do: nothing is removed
	: >"$log"; dpkg-query() { :; }; installed_version() { :; }
	beside_tidy
	[ ! -s "$log" ]
}

@test "--download keeps Raspberry Pi's builds as Raspberry Pi ships them, for the offline computer to repack" {
	# adapt_deb repacks beside Debian's; what packages/ holds stops before that
	declare -f adapt_deb | grep -q 'beside_pack'
	run ! grep -q beside_pack <<<"$(declare -f adapt_pre)"
	declare -f download_mode | grep -q 'f=$(adapt_pre "$f") && e=$(beside_pack "$f")'
	# Offline, the repacking follows on the computer, from packages/
	declare -f install_all | grep -q 'f=$(beside_pack "$f") && f=$(scripts_coinstall "$f")'
}

@test "SSH: the session has Debian's agent only" {
	WORKDIR=$BATS_TEST_TMPDIR S_PI_STACK=1 S_PROFILE=LXDE-pi T_GTK=PiXflat T_ICONS=PiXflat T_FONT=x T_CURSOR_SIZE=24 T_TB_ICON=24 T_SOUND_THEME=x
	_term_cmd() { echo lxterminal; }; color_scheme() { echo default; }
	_session_profile "$BATS_TEST_TMPDIR/xdg"
	f=$BATS_TEST_TMPDIR/xdg/lxsession/LXDE-pi/desktop.conf
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

@test "the other edition's install stops this one before any change; --refresh keeps the installed Raspberry Pi OS release" {
	st=$BATS_TEST_TMPDIR/state
	eval "$(sed -n '/^require_own_install() {$/,/^}$/p;/^keep_installed_release() {$/,/^}$/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh" \
		| sed "s|\$SYS_DIR/state|$st|")"
	die() { echo "DIE: $*"; return 1; }
	# No state, an install of this edition, or a state without the edition: go on
	rm -f "$st"; require_own_install
	printf 'release bullseye\nedition legacy\n' >"$st"; require_own_install
	printf 'release bullseye\n' >"$st"; require_own_install
	# The other edition's install: stop, naming --uninstall
	printf 'release trixie\nedition main\n' >"$st"
	run require_own_install; [ "$status" -ne 0 ]
	[[ $output == *"installed by rpios-look.sh"* && $output == *"--uninstall"* && $output == *"nothing was changed"* ]]
	# --refresh: the installed release stays, with a note when a newer one fits
	rpi_populated() { :; }; rpi_arches() { echo amd64; }
	note() { echo "NOTE: $*"; }
	H_ARCH=amd64 H_SUITE=bookworm
	printf 'release bullseye\nedition legacy\n' >"$st"
	out=$(keep_installed_release; echo "suite=$H_SUITE")
	[[ $out == *"NOTE: Raspberry Pi OS bookworm is available"* && $out == *"suite=bullseye" ]]
	# Not published for this architecture any more: the choice of pick_suite stays
	rpi_arches() { echo i386; }
	H_SUITE=bookworm; keep_installed_release; [ "$H_SUITE" = bookworm ]
	# A release outside this edition's, or not a release name: ignored
	rpi_arches() { echo amd64; }
	printf 'release trixie\n' >"$st"; H_SUITE=bookworm; keep_installed_release; [ "$H_SUITE" = bookworm ]
	printf 'release $(true)\n' >"$st"; keep_installed_release; [ "$H_SUITE" = bookworm ]
}

@test "NetworkManager and the Wi-Fi tools come only with the network plugin; one installed already stays" {
	init_colors
	has_wifi() { :; }; has_bluetooth() { [ -n "${BT:-}" ]; }
	installed_version() { case $1 in network-manager) echo "${NM:-}" ;; esac; }
	USE_NETMAN=1
	[[ $(tray_debs bookworm | xargs) == "network-manager wpasupplicant iw wireless-regdb rfkill dnsmasq-base debian-reference-common debian-reference-en" ]]
	# The plugin is left out while installing: they go from the install set
	USE_NETMAN=0 APT_PKGS=(lxsession network-manager wpasupplicant iw wireless-regdb rfkill debian-reference-common)
	HW_PKGS=(network-manager wpasupplicant iw wireless-regdb rfkill) ROOT_PKGS=(lxsession network-manager iw rfkill)
	netman_debs_drop >/dev/null
	[ "${APT_PKGS[*]}" = "lxsession debian-reference-common" ] && [ ${#HW_PKGS[@]} = 0 ] && [ "${ROOT_PKGS[*]}" = lxsession ]
	# rfkill stays for Bluetooth
	BT=1 APT_PKGS=(network-manager rfkill bluez) HW_PKGS=(network-manager rfkill bluez) ROOT_PKGS=()
	netman_debs_drop >/dev/null
	[ "${APT_PKGS[*]}" = "rfkill bluez" ] && [ "${HW_PKGS[*]}" = "rfkill bluez" ]
	# Installed already: nothing of it is asked for, nothing changes
	NM=1 BT="" APT_PKGS=(lxsession) HW_PKGS=() ROOT_PKGS=(lxsession)
	netman_debs_drop
	[ "${APT_PKGS[*]}" = lxsession ]
	# install_all calls it where the plugin is left out
	grep -q '^		netman_debs_drop$' <(sed -n '/^install_all() {$/,/^}$/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh")
}

@test "Large: wider scrollbars and resize borders on every release, the large window theme on Debian 12, as on Raspberry Pi OS 12; never on 9 to 11" {
	init_colors
	WORKDIR=$BATS_TEST_TMPDIR SYS_ROOT=$BATS_TEST_TMPDIR/root
	local t d=$BATS_TEST_TMPDIR/data rc=$BATS_TEST_TMPDIR/rc.xml
	for t in PiXflat PiX; do
		mkdir -p "$SYS_ROOT/usr/share/themes/$t/gtk-3.0" "$SYS_ROOT/usr/share/themes/$t/openbox-3"
		echo '/* theme */' >"$SYS_ROOT/usr/share/themes/$t/gtk-3.0/gtk.css"
		echo 'border.radius: 0' >"$SYS_ROOT/usr/share/themes/$t/openbox-3/themerc"
	done
	mkdir -p "$SYS_ROOT/usr/share/themes/PiXflat_l/openbox-3"
	echo 'border.radius: 0' >"$SYS_ROOT/usr/share/themes/PiXflat_l/openbox-3/themerc"
	: >"$SYS_ROOT/usr/share/themes/PiXflat_l/openbox-3/max_hover_toggled.xbm"
	mk_rc() { printf '<?xml version="1.0"?>\n<openbox_config>\n  <theme>\n    <name>x</name>\n  </theme>\n  <mouse>\n    <doubleClickTime>200</doubleClickTime>\n  </mouse>\n</openbox_config>\n' >"$rc"; }
	H_RANK=12
	# Medium: the theme itself, no scrollbar rules, 12-pixel borders
	O_SIZE=medium set_theme pixflat
	[ "$T_OB" = PiXflat ]
	[ "$T_HANDLE" = 10 ]
	[ "$T_SCROLL" = 0 ]
	mk_rc; _openbox_rc "$rc"
	grep -q '<name>PiXflat</name>' "$rc"; grep -q '<invHandleWidth>10<' "$rc"
	[ "$(grep -c '<doubleClickTime>' "$rc")" = 1 ]; grep -q '<doubleClickTime>400</doubleClickTime>' "$rc"
	_session_themes "$d"
	run ! grep -q '^scrollbar' "$d/themes/PiXflat/gtk-3.0/gtk.css"
	# Large: <theme>_l, 20-pixel borders, 17-pixel scrollbars
	for O_SIZE in large; do
		set_theme pixflat
		[ "$T_OB" = PiXflat_l ]
		[ "$T_HANDLE" = 20 ]
		[ "$T_SCROLL" = 17 ]
		mk_rc; _openbox_rc "$rc"
		grep -q '<name>PiXflat_l</name>' "$rc"; grep -q '<invHandleWidth>20<' "$rc"
	done
	rm -rf -- "$d"; _session_themes "$d"
	grep -qx 'scrollbar button { min-width: 17px; min-height: 17px; }' "$d/themes/PiXflat/gtk-3.0/gtk.css"
	grep -qx 'scrollbar slider { min-width: 11px; min-height: 11px; }' "$d/themes/PiXflat/gtk-3.0/gtk.css"
	[ -L "$d/themes/PiXflat_l/openbox-3/max_toggled_hover.xbm" ]
	# Debian 9 to 11: Raspberry Pi OS's Large there has no large window
	# theme, 20-pixel borders and 18-pixel scrollbars, GTK 3's buttons as
	# wide as the slider; legacy offers no Larger size (9 to 12 have three)
	run ! size_ok larger
	for H_RANK in 9 10 11; do
		O_SIZE=large set_theme pixflat
		[ "$T_OB" = PiXflat ]
		[ "$T_HANDLE" = 20 ]
		[ "$T_SCROLL" = 18 ]
	done
	rm -rf -- "$d"; _session_themes "$d"
	grep -qx 'scrollbar button { min-width: 12px; min-height: 12px; }' "$d/themes/PiXflat/gtk-3.0/gtk.css"
	grep -qx 'scrollbar slider { min-width: 12px; min-height: 12px; }' "$d/themes/PiXflat/gtk-3.0/gtk.css"
	O_SIZE=medium set_theme pixflat; [ "$T_HANDLE" = 10 ] && [ "$T_SCROLL" = 0 ]
	H_RANK=12 O_SIZE=large
	# PiX has no large window theme; a missing _l theme falls back to the theme
	set_theme pix; [ "$T_OB" = PiX ]
	rm -r "$SYS_ROOT/usr/share/themes/PiXflat_l"
	set_theme pixflat; mk_rc; _openbox_rc "$rc"; grep -q '<name>PiXflat</name>' "$rc"
}

@test "an install records the edition before its first change, so the other script never installs over it" {
	local body
	body=$(sed -n '/^\tas_root install -d -m 0755 "\$SYS_DIR"$/,/^\tinstall_all$/p' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh")
	[[ $body == *record_packages_before*'[[ -f $SYS_DIR/state ]] || save_state'*before=* ]]
}

@test "sound: no sound server on Debian 9, as Raspbian Stretch; PulseAudio with its Bluetooth module on 10 and 11" {
	compgen() { :; }; installed_version() { :; }; has_bluetooth() { :; }; has_wifi() { return 1; }; USE_NETMAN=0
	[ -z "$(audio_debs stretch)" ]
	[ "$(audio_debs buster)" = pulseaudio ] && [ "$(audio_debs bullseye)" = pulseaudio ]
	[ "$(audio_debs bookworm)" = pipewire-audio ]
	grep -qx pulseaudio-module-bluetooth <<<"$(tray_debs buster)"
	run ! grep -qx pulseaudio-module-bluetooth <<<"$(tray_debs stretch)"
	run ! grep -qx pulseaudio-module-bluetooth <<<"$(tray_debs bookworm)"
}

@test "GTK's toolbar icon size per size and release, as the Appearance Settings set it" {
	WORKDIR=$BATS_TEST_TMPDIR
	H_RANK=12; O_SIZE=small set_theme pixflat; [ "$T_TB_SIZE" = 2 ]
	H_RANK=10; O_SIZE=small set_theme pixflat; [ "$T_TB_SIZE" = 1 ]
	O_SIZE=medium set_theme pixflat; [ "$T_TB_SIZE" = 3 ]
	O_SIZE=large set_theme pixflat; [ "$T_TB_SIZE" = 6 ]
}

@test "desktop icons on the second monitor: shown on Raspberry Pi OS 10 and 11, hidden on 9 and 12" {
	WORKDIR=$BATS_TEST_TMPDIR H_RANK=12; O_SIZE=medium set_theme pixflat
	S_WALL=w S_PROFILE=LXDE-pi S_PI_STACK=0 SYS_ROOT=$BATS_TEST_TMPDIR/none; _term_cmd() { echo lxterminal; }
	for H_SUITE in bullseye bookworm; do
		d=$BATS_TEST_TMPDIR/$H_SUITE; _session_files "$d"
		grep -qx 'show_trash=1' "$d/pcmanfm/LXDE-pi/desktop-items-0.conf"
	done
	grep -qx 'show_trash=1' "$BATS_TEST_TMPDIR/bullseye/pcmanfm/LXDE-pi/desktop-items-1.conf"
	grep -qx 'show_mounts=1' "$BATS_TEST_TMPDIR/bullseye/pcmanfm/LXDE-pi/desktop-items-1.conf"
	grep -qx 'show_trash=0' "$BATS_TEST_TMPDIR/bookworm/pcmanfm/LXDE-pi/desktop-items-1.conf"
}

@test "uninstall: the network and Bluetooth tools go without asking; kept packages keep only their record" {
	for p in network-manager wpasupplicant iw wireless-regdb rfkill dnsmasq-base bluez libspa-0.2-bluetooth pulseaudio-module-bluetooth; do
		[[ $p =~ ^($NET_PKGS_RE)$ ]]
	done
	has_wifi() { :; }; has_bluetooth() { :; }; installed_version() { case $1 in pipewire|pulseaudio) echo 1 ;; esac; }
	for p in $(USE_NETMAN=1 tray_debs bookworm | grep -v '^debian-reference'); do [[ $p =~ ^($NET_PKGS_RE)$ ]]; done
	grep -q '! -name packages-before ! -name installed-packages' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh"
	# One APT run with the packages agreed on, so what only the tools need goes too
	grep -qF '_remove_recorded "${pkgs[@]}" "${net[@]}"' "$BATS_TEST_DIRNAME/../rpios-look-legacy.sh"
}
