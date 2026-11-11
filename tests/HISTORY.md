# Test history

Each run of the test suite: what was tested, the result, and what it found.
Newest first. Every section is a test of 1.0.0 while it was being written;
the earlier ones tested builds on the way to it.

## Test machines

Virtual machines (KVM/libvirt, 2 vCPUs, 3 GB memory, virtio graphics
without 3D acceleration, 1280×800). Each Debian VM was installed with
Debian's LXDE (`task-lxde-desktop`, LightDM, X) and is reverted to that
fresh snapshot before each install.

| VM | System | Architecture | Role |
|----|--------|--------------|------|
| deb9-i386, deb9-amd64 | Debian 9 (stretch) | i386, amd64 | Test |
| deb10-i386, deb10-amd64 | Debian 10 (buster) | i386, amd64 | Test |
| deb11-i386, deb11-lxde | Debian 11 (bullseye) | i386, amd64 | Test |
| deb12-i386, deb12-amd64 | Debian 12 (bookworm) | i386, amd64 | Test |
| deb13-lxde | Debian 13 (trixie) | amd64 | Test |
| debsid-lxde | Debian unstable (sid) | amd64 | Test |
| raspios-ref | Raspberry Pi OS desktop on Debian 13, X (Openbox), UEFI | amd64 | Reference: look, behaviour, packages, speed |
| rpios11 | Raspberry Pi Desktop (Debian 11) | amd64 | Reference: speed |

Physical machines:

| Machine | System | Used for |
|---------|--------|----------|
| Desktop PC: Intel Core i5-3550, 32 GB, NVIDIA GeForce GT 1030 (NVIDIA's driver), SATA SSD | Debian 13 with rpios-look, X | VM host; daily use of the session; NVIDIA window dragging (picom), theme switching, lock |
| Laptop: Intel Core i7-1355U, 32 GB, Intel Iris Xe | Debian 13 | `--download` (packages/ for the offline tests) |

## 1.0.0, LXTerminal maximized and restored (2026-11-12)

A report from the real desktop: LXTerminal, maximized and then restored, does
not get its first size back. Tried on deb13-lxde with LXTerminal 0.4.1-1,
through the window manager's maximize state.

| Session | First | Maximized | Restored |
|---------|-------|-----------|----------|
| Debian's LXDE, before the install | 656 x 436 | 1280 x 752 | 1280 x 742 |
| Raspberry Pi Desktop (X), PiXtrix, the session's `lxterminal` | 655 x 442 | 1280 x 736 | 1279 x 731 |
| the same, `/usr/bin/lxterminal` started directly | 655 x 442 | 1280 x 736 | 1279 x 731 |
| the same, PiXflat | 655 x 441 | 1280 x 736 | 1279 x 730 |
| Debian's LXDE, after the install | 656 x 436 | 1280 x 752 | 1280 x 742 |

The same in every session, also in Debian's LXDE before the look is
installed: Debian 13's LXTerminal keeps the maximized size as its own. Not
caused by the look; nothing changed.

## 1.0.0, clean install on a real Debian 13 desktop (2026-11-11)

The desktop PC above (NVIDIA's driver), in daily use, from a fresh clone of
GitHub at the v1.0.0 tag (the same file as tested in AUD4).

- `--uninstall` of the build installed before, with the script that
  installed it: rc 0; the 71 packages it had installed removed; no rpios-look
  or Raspberry Pi package, session, APT source, polkit rule or icon folder
  left; the user's login choice back to Debian's default session.
- Old run logs and the old clone deleted by hand. Then a restart: LightDM up,
  no failed unit.
- Fresh install, default options: rc 0, no note; both sessions installed (X
  and Wayland); PiXtrix; no power helper, no polkit rule, `swayidle` and
  `wlopm` not installed; no `C-A-l` key in the X session,
  `lock_manager/command=lxlock`, the power button bound to the session's own
  program.
- After a restart: LightDM's login screen up, no failed system unit.
- `--refresh` twice: rc 0, "up to date; nothing to apply" both times, and no
  notice of a newer script.
- After the user logged in (X session, NVIDIA's driver): `lxsession` under
  `systemd-inhibit` (`handle-power-key`), `openbox-pi`, `lxpanel-pi`,
  `pcmanfm-pi`, the settings keeper, the compositor starter with `picom`
  (GLX, direct rendering on the NVIDIA card); PiXtrix with its icons, cursor,
  font and wallpaper; the X server's blanking 600/600/600; no failed system
  or user unit. The session log has the panel's and file manager's known GTK
  messages and lxsession's one warning of a first login (it cannot save into
  the session's system file and then writes the user's own).
- Not checked: the Wayland session on NVIDIA's driver, the power button, the
  lid and the sleep keys.

## 1.0.0: fourth audit, shape and logic (2026-11-11)

Working tree, both scripts, on every release, architecture and theme. Both
scripts are version 1.0.0; no update from an earlier install is supported
(uninstall with the script that installed it, then install).

**Shape.** The power helper is gone from both scripts: no `rpios-look-power`,
no helper process, no polkit rule, no lid polling, and four fewer Debian
packages (`x11-xserver-utils`, `libxss1`, `swayidle`, `wlopm`). The session
does what Raspberry Pi OS's does, checked against its own packages
(`rpd-common`, `rpd-x-core`, `rpd-wayland-core`, `raspberrypi-ui-mods`): the X
server's own blanking, no automatic lock or sleep, the lid as Debian has it;
Ctrl+Alt+L locks through LightDM (13 and later); the power button runs a
small program like Raspberry Pi OS's `pwrkey`, and the session starts under
`systemd-inhibit`, so the key is the session's exactly while it runs. The
main script no longer carries copies of release 13's panel, labwc and
Wayland panel settings: a release's desktop is known only when its own
packages hold them. Its repack helper names only what Debian 13 repacks.
Main: 6,878 to 6,412 lines; legacy: 7,044 to 6,695.

**Logic, found and fixed.**

- A login-settings file the install had created (AccountsService) stayed
  after `--uninstall` on Debian 13 and sid (seen in the baseline run).
- "printf: write error: Broken pipe" when the size was first saved, where
  the script's parent ignores SIGPIPE (seen in the baseline run).
- The session's file manager and desktop never fell back to Debian's file
  manager when Raspberry Pi's was removed (main).
- One package with an alternative dependency made `--uninstall` keep every
  recorded package.
- An APT 404 left the install's plan recorded, so that packages installed
  by hand later counted as the script's.
- A terminal font chosen by the user was overwritten at the medium size.
- The purge lock could stay with a program that APT started.
- A PiX window theme in the user's own labwc file counted as the session's.
- A second `--uninstall`, with only kept packages left, showed the whole
  plan and the restart countdown again.
- The offline bundle's `VERSIONS.md` named the wrong script (legacy).
- Leftover names and comments of packages no longer installed; a duplicate
  origin check; the labwc theme helpers defined twice.

| Run | VM | Script | Result |
|-----|----|--------|--------|
| AUD0 | all 10 VMs | both, before the changes | baseline: install rc 0, every theme of the release applied, a later release's theme refused, `--refresh` up to date, three sizes, uninstall rc 0. Found: the AccountsService file left on 13 and sid, the "Broken pipe" message |
| AUD2 | deb13-lxde, debsid-lxde | main | install rc 0, no message; X: lxsession under `systemd-inhibit` (`handle-power-key`), `openbox-pi`, `lxpanel-pi`, `pcmanfm-pi`, settings-keeper, nothing else of the look; the X server's blanking 600/600/600; Ctrl+Alt+L `dm-tool lock`; the power button program opens the Shutdown dialog; the look's processes used 1 to 3 clock ticks in 60 idle seconds; PiXtrix, PiXonyx, PiXflat, PiXnoir, PiX each applied (GTK, icons, cursor, font, Openbox, wallpaper, GSettings light or dark). Wayland: labwc under `systemd-inhibit`, panel, desktop, kanshi, xsettingsd, no idle helper, `swayidle` and `wlopm` not installed; four themes applied, PiX refused; `--reset` clean. Debian's LXDE session unchanged, no Debian package with a Raspberry Pi version. `--refresh` up to date; Large (20-pixel borders, `PiXtrix_l`, terminal font 15), Small (8), Medium (10). Uninstall rc 0: nothing left, the AccountsService file gone; state before and after equal but for the test's own files |
| AUD2 | deb12-amd64, deb12-i386 | legacy | as above for X: the power key held for the session (as Raspberry Pi OS 12), PiXflat, PiXnoir, PiX; PiXtrix refused; Large with `PiXflat_l`; uninstall clean |
| AUD2 | deb11-lxde, deb11-i386, deb10-amd64, deb10-i386 | legacy | install rc 0; Raspberry Pi's panel, file manager and Openbox beside Debian's; no power-key inhibitor (as Raspberry Pi OS 10 and 11); three themes; three sizes; uninstall clean |
| AUD2 | deb9-amd64, deb9-i386 | legacy | install rc 0 (`lxplug-ejecter` left out: its dependencies are not in Debian 9); Stretch's own panel, file manager and Openbox; PiX only; three sizes; uninstall clean |
| OFF1 | deb12-amd64, deb10-amd64 | legacy | `--download` on Debian 12 rc 0: 746 MB, 1532 packages, 8 indexes (9 to 12, both architectures), `VERSIONS.md` names the legacy script; `--offline` on Debian 10 with no route out rc 0: no APT source added, Raspberry Pi's panel, file manager and Openbox beside Debian's, three themes, uninstall rc 0, nothing left |
| POW1 | deb13-lxde | main | the README's recipes for your own lock and blank times, in the session: light-locker from the user's own start entry (`--lock-after-screensaver=30`) locked 30 seconds after the screen blanked (LightDM's login screen shown, the session marked idle); `xset` from a start entry set 300 seconds; Wayland: `swayidle` with `wlopm` from the user's labwc autostart ran beside the session's panel and desktop |
| POW2 | deb12-amd64, deb9-amd64 | legacy | the same lock and blank recipes work (light-locker 1.8.0 and 1.7.0, both installed by Debian's LXDE) |
| IDLE | deb13-lxde, deb12-amd64, deb10-amd64, deb9-amd64 | both | systemd-logind's `IdleAction` did not fire within 5 minutes while light-locker's lock was shown: the login screen's session is never idle. |
| SLP1 | deb13-lxde, deb12-amd64, deb9-amd64 | both | sleep after a time with Debian's tools and no polkit rule (the VMs given suspend-to-RAM for the run). `xautolock` is not in Debian 13. On 12 and 9: with the lock set before the sleep time the computer did not sleep (a locked session may not suspend); with the lock only at sleep it slept after 65 seconds and woke locked |
| SLP2 | deb13-lxde, deb12-amd64, deb9-amd64 | both | `xss-lock --ignore-sleep -- systemctl suspend` from the user's start entry: slept and woke locked on all three; on 13 the monitor power timer (DPMS) also started it, after 25 seconds instead of 60. Lock time through `xset s` and `light-locker --lock-after-screensaver=1`: locked on all three. Wayland on 13: `swayidle` with `wlopm`, `swaylock -f` and `systemctl suspend` (20, 30, 60 seconds): asleep after 66 seconds, `swaylock-pi` running after waking |
| SLP3 | deb13-lxde, deb12-amd64, deb9-amd64 | both | the README's lock recipe (`xset s 20 20; xset dpms 20 20 20`, `--lock-after-screensaver=20`): unlocked after 30 seconds, locked after 55 on all three. Sleep a time after the screen went off (`xset s 20 40`, `xss-lock -n true`): 66 and 70 seconds on 12 and 9; 25 on 13, again from the DPMS timer |
| SLP4 | deb13-lxde, deb12-amd64, deb9-amd64 | both | the README's sleep recipe (`xset s 20 40; xset dpms 0 0 0; exec xss-lock -n true --ignore-sleep -- systemctl suspend`, `light-locker --lock-after-screensaver=0 --lock-on-suspend --lock-on-lid`): not locked after 35 seconds, asleep after 66, 66 and 71 seconds, LightDM's login screen shown after waking |
| REV | - | both | independent review of the whole change: eight findings, all fixed. Main: a failed download of Raspberry Pi's desktop package stops the run (it was read as a desktop the script does not know); Raspberry Pi's panel is used only on a desktop the script knows. Both: a 404 is matched as `404 Not Found` and what APT installed all the same stays recorded; a later `--uninstall` that removes kept packages ends with the restart offer; the power button opens the Shutdown dialog through the session's own starter; a dead variable removed; the X session's lock key and LightDM lock command removed (LOCK1) |
| LOCK1 | deb10-i386 | - | `dm-tool lock` with no locker running in the session: LightDM's login screen is shown, but switching back to the session's console shows the desktop without a password. So the X session has no lock key (as Raspberry Pi OS's has none) and `lock_manager/command` is `lxlock`, as there |
| LOCK2 | deb10-i386 | - | with light-locker running (the README's lock recipe), `light-locker-command -l` locks: switching back to the session's console shows "This session is locked" and returns to the login screen |
| AUD3 | all 10 VMs | both, before the review's fixes | every step rc 0, as AUD2 |
| AUD4 | all 10 VMs | both, final | install, `--refresh`, three sizes and uninstall rc 0 on all ten; every theme of each release applied (13 and sid: five in X, four on Wayland, PiX refused there; 12, 11, 10: three; 9: PiX), a later release's theme refused on 9 to 12; no `C-A-l` key in the X session, `lock_manager/command=lxlock`; the power-key inhibitor on 13, sid and 12, none on 9 to 11; the Shutdown dialog opens from the power button program; no power leftovers; helpers 0 to 3 jiffies in 60 s, 98 to 99 % idle; no Debian package with a Raspberry Pi version; after uninstall only the test's own files, CUPS's and the session programs' own files differ. Notes as before: `qt5-style-plugins` left out on sid, `lxplug-ejecter` on 9 |
| DLG | deb13-lxde | main | the Shutdown dialog from the power button program: in the X session Shutdown, Reboot, Logout and no lock key; in the Wayland session the same with "Press 'Ctrl-Alt-l' to lock screen" (through the session's own starter) |

- bats: 183/183. shellcheck: main 15 (was 16), legacy 15. After the review's fixes: bats 183/183, shellcheck 15 and 15.
- New unit test file `rpios-look-both.bats` (2 tests): of the 259 functions both scripts define, 176 have the same text and 83 are listed as different on purpose; a function outside the list that differs fails the test, and so does a listed one that no longer differs. Tried with a change in one script only and with a stale list entry: both fail and name the function. bats now 185/185.
- Not tested in this round: the power button and the lid on real hardware
  (the virtual machines have neither); NVIDIA's driver.

## Fixes of the third audit (2026-11-11)

Working tree, both scripts. The fixes of the third audit (installing record,
uninstall order, refresh gate, AccountsService lines, terminal font, purge
lock, labwc undo, `beside_tidy`, `dnsmasq-base`, toolbar icon size, Wayland
panel spacers, Debian 9 thumbnails and places), Debian's `libobt2v5` instead
of a repack, and code for packages no longer used removed.

| Run | VM | Script | Result |
|-----|----|--------|--------|
| VALL2 | all 8 VMs | both | install `--size large` rc 0 (20-pixel borders; `_l` window theme on 12 and 13+; terminal font 15), X session with `openbox-pi` on Debian's `libobt2v5`, panel, file manager and power helper; `rpios-look-set --theme pixnoir` dark on every release (sid included: the earlier PiXtrix result is gone); `--refresh` "up to date"; `--refresh --size small` terminal font 8; uninstall rc 0. Found: on 13 and sid `/var/lib/rpios-look` stayed (below); the Wayland panel had no launchers (below) |
| V13K | deb13-lxde | main | `libldacbt-abr2` reported kept "because other installed software needs them": only `libspa-0.2-bluetooth` needed it, which the network step removed after. Fixed: the packages agreed on and the network tools go in one APT run |
| V13L, V13M | deb13-lxde | main | wf-panel-pi reads only `/etc/xdg/wf-panel-pi` and `~/.config` (strings of the binary; the same names in the user's file show the launchers), never `XDG_CONFIG_DIRS`: the panel ran on its built-in layout, so no launchers and no Large/Larger panel size. Fixed: the panel file is in the session package at `/etc/xdg/wf-panel-pi/wf-panel-pi.ini`, as on Raspberry Pi OS |
| VFIX | deb13-lxde, debsid-lxde | main | Wayland: browser, file manager and terminal launchers at Medium; `--refresh --size large` gives the 48-pixel panel with launchers; uninstall: nothing kept, no `/var/lib/rpios-look`, `/etc/xdg/wf-panel-pi` or `/usr/share/rpios-look` left |

- bats: 177/177. shellcheck: main 16, legacy 15 (unchanged).

## Fixes of the second audit (2026-11-10)

Working tree, both scripts. `--uninstall` no longer leaves the install's
state behind when packages are kept (that blocked the upgrade path from
Debian 12 to 13), removes the network and Bluetooth tools the install added,
and undoes only what it set in labwc's and LXTerminal's files; packages from
an APT run that did not finish are recorded; a `policy-rc.d` left by a
stopped purge is removed; a purge never takes Debian's LXDE with it. Large
on Debian 9 to 11 as Raspberry Pi OS 9 to 11 (20-pixel borders, 18-pixel
scrollbars); the terminal font follows `--refresh --size`; Raspberry Pi's
file manager reads the session's settings after Debian's (no automatic
mounting); the Wayland panel's window buttons, GTK's toolbar icon size,
second-monitor desktop icons on 10 and 11 and the sound packages of 9 to
11 as on Raspberry Pi OS; a `--refresh` in the Wayland session restarts the
power helper.

| Run | VM | Script | Result |
|-----|----|--------|--------|
| VR13 | deb13-lxde | main | a `policy-rc.d` left behind is removed; install `--size large` rc 0: `[window-list] max_width=300`, toolbar icon size 6, the file manager wrapper; terminal font 15, `--refresh --size small` 8; X: `pcmanfm-pi` runs with the session's folder last; `rpios-look-set --theme` in Wayland, then a keybind added: `--uninstall` keeps the keybind, puts back the user's own theme block and cursor, and only the terminal font (a line added since stays); nothing of the install left |
| VR11 | deb11-lxde | legacy | install `--size large` rc 0: 20-pixel borders, PiXflat (no large title bar), GTK 2 scrollbars 18, GTK 3 button and slider 12, toolbar icon size 6, second monitor with wastebasket and drives; uninstall keeping the packages: only `packages-before`, `installed-packages`, `installed-auto` left, no state; a new install rc 0, a full uninstall leaves nothing |
| VR13B | deb13-lxde | main | libfm test (open question C): Raspberry Pi's unmodified `lxpanel-pi` 1.11 links Debian's `libfm` 1.4.0 and runs; its panel looks the same as the repacked one |
| VR13C, VR13D | deb13-lxde | main | the repacked panel logs the same GTK warning as the unmodified one (not caused by Debian's libfm); an update `--refresh` (state of the build before) inside the Wayland session recognises the session and restarts the power helper (new process). Found and fixed: the restarted helper kept the terminal as its input; it now reads /dev/null |
| VC, VC2, VM | deb13-lxde, debsid-lxde | main | Raspberry Pi's panel as shipped with Debian's libfm (open question C): fresh install rc 0, `lxpanel-pi` 1.11 from Raspberry Pi's archive (pinned), linked to Debian's libfm 1.4.0 (sid: 1.4.1); its menu (click and Super) the same as 1.1.2's repacked panel's, Panel Preferences, volume and network popups, window list and the file manager work; uninstall leaves nothing |

- Then: the libfm repacks are gone from main (13 and later); legacy no
  longer installs pipanel; code for packages no longer used is removed, and
  so is legacy's `old_looks` (offering to remove looks left by an in-place
  Debian upgrade, which the supported path never leaves).
- bats: 178/178. shellcheck: main 16 (the new note is a deliberate
  single-quoted `${XDG_CONFIG_DIRS}` in a generated script), legacy 15.

## Fixes of the full audit (2026-11-10)

Working tree, both scripts. Updates as in ubuntu-look: APT updates the
Raspberry Pi packages used unchanged (archive pinned), `--refresh` the
repacked ones; no check before APT installs, no hook after `apt update`, no
local repository; a check after dpkg names a look package APT removed. Also:
Wayland power button, Ctrl+Alt+T and power settings (swayidle);
`rpios-look-set` records the user's labwc files; no GPU plugin, no battery
plugin without a battery; each `--uninstall` removes the other script's
install; 10-pixel resize borders at Small and Medium; legacy offers Small,
Medium and Large only; Appearance Settings' monospace font and toolbar size
and GTK 2 scrollbars (the session's own file).

| Run | VM | Script | Result |
|-----|----|--------|--------|
| AU | deb13-lxde | main | install `--size large` rc 0; APT: Raspberry Pi's source pinned, only `DPkg::Post-Invoke`, no local repository; no GPU or battery plugin; GTK 2 scrollbars 17 in the session's own file; `apt-get remove lpplug-clock`: the check names it; `--refresh` puts it back; Wayland: Ctrl+Alt+T runs the terminal, the power button the session's handler, `wl-power` runs swayidle (screen off at 10 min) with the power-button inhibitor; `rpios-look-set --theme` records the user's labwc files, `--reset` brings back the user's theme and cursor; legacy `--uninstall` rc 0 removes it all (Wayland settings, dconf databases, the PiX labwc theme), the user's cursor line back, no rpios-look package left |
| AL-12 | deb12-amd64 | legacy | `--size larger` refused; install `--size large` rc 0: PiXflat_l, 20-pixel borders, GTK 2 file; the check after dpkg names a removed look package; `--refresh` puts it back, a second finds nothing; session runs Raspberry Pi's Openbox, panel and file manager; uninstall rc 0, nothing left |
| AL-11 | deb11-lxde | legacy | `--size larger` refused; install medium rc 0: PiXflat, 10-pixel borders, no GTK 2 file; the rest as AL-12 |

| VF | deb12-amd64, deb13-lxde | main | Debian 12: refused at once, no release table saved, nothing in `/var/lib/rpios-look`; Debian 13: the release table saved after the check |
| VF5 | deb13-lxde | main | install killed (SIGKILL) right after its first record: `/var/lib/rpios-look` holds `packages-before` and `state` with `edition main`; the same install run again finishes, rc 0 |

- Found and fixed: legacy's message after dpkg named the main script.
- Then: main refuses a system known to be wrong before Debian's release
  table is downloaded; both scripts write their state (the edition) right
  after the first record, so the other script never installs over an
  install that stopped halfway (VF, VF5).
- Not changed: the power button while the screen is locked or another
  user's session is in front. Raspberry Pi OS blocks systemd-logind's power
  key for the whole session as well.
- bats: 170/170. shellcheck: main 15, legacy 15.

## rpios-look-set --theme on every release and theme (2026-11-10)

Each VM: fresh install, login, then for each theme `rpios-look-set --theme`
live in the session, then a new login into that theme; compared: the
session's files (GTK theme and icons, Openbox theme, wallpaper), the running
session's theme and icons, and the panel and desktop icons on screen (live
against the fresh login).

| VM | Script | Themes | Result |
|----|--------|--------|--------|
| deb13-lxde | main | PiXtrix, PiXonyx, PiXflat, PiXnoir, PiX | files and running session right for each; screen the same as after a login (differences only in a network notification and the clock) |
| deb12-amd64 | legacy | PiXflat, PiXnoir, PiX | the same; screen differences only in one clock digit |
| deb11-lxde | legacy | PiXflat, PiXnoir, PiX | the same |
| deb10-amd64 | legacy | PiXflat, PiXnoir, PiX | the same |

- Not reproduced: on the real Debian 13 desktop, a first theme change right
  after a fresh install twice left the GTK theme and icons unchanged (window
  theme and wallpaper changed); later changes there, and every change on the
  VMs, were complete. Left open.
- The VMs were prepared with the rebuilt harness (prep.sh).

## Fixes found after the Wayland session was added (2026-11-10)

Both scripts: a plain run also resets the session's X
settings database, its own lxpanel profile and its menu file; `--uninstall`
drops the `Session=` line LightDM writes into `~/.dmrc`; `--size small|large|larger`
sets the terminal's font in the user's LXTerminal settings, as Raspberry Pi
OS's Appearance Settings does (the session's copy was never read), recorded
for `--uninstall`; a Wayland test no longer reads the computer's own themes.

| Run | VM | Script | Result |
|-----|----|--------|--------|
| TF | deb13-lxde | main | install `--size large` rc 0: `~/.config/lxterminal/lxterminal.conf` made from LXTerminal's defaults with `fontname=Monospace 15`, kept after login; plain install rc 0: `fontname=Monospace 10` (the terminal's own) again; `--uninstall` rc 0: the file the script made is gone, and so is its state. LightDM kept the session choice in AccountsService, so `~/.dmrc` stayed empty (the `~/.dmrc` fix is unit-tested) |

- bats: 164/164 (6 new). shellcheck: main 15, legacy 15.

## Clean install on a real Debian 13 desktop, with the Wayland session (2026-11-09)

The desktop PC above (NVIDIA's driver), in daily use.

- `--uninstall` of the build installed before: rc 0; no rpios-look file or
  Raspberry Pi package left; the user's login choice back to Debian's
  default session. Then a restart.
- Leftovers of earlier builds deleted by hand before the install: old
  logs and settings backups, and user files of earlier builds (GTK settings
  naming PiXflat-Debian, Control Centre and qt5ct/qt6ct files). Debian's
  LXDE settings kept.
- Fresh install, default options: rc 0; both sessions installed (X and
  Wayland, with Debian's labwc 0.8.3, wf-panel-pi 1.43 and
  rpios-look-swaylock); PiXtrix; the next login uses the X session.
- After a restart: LightDM's login screen up, no failed system units.
- `--refresh` twice: rc 0, "nothing to apply" both times.
- Not checked: a login (no auto-login on that computer), the Wayland
  session on NVIDIA's driver.

## The Wayland session on Debian 13 and later (2026-11-09)

Design: README, "Wayland session". Decisions (user, 2026-11-09):
- Wayland on 13+ only; legacy (9–12) stays X only.
- Debian's labwc 0.8.3.
- Both sessions on the login screen, no GPU check, X the default.
- Wayland runs as on Raspberry Pi OS (software rendering without 3D
  acceleration).
- squeekboard only with a touch screen; wayvnc left out.
- No unnecessary package changes.

Research before building (subagents):
- Debian 12 has no labwc, and Raspberry Pi's needs newer libwayland and
  libdrm than Debian 12 has.
- Raspberry Pi OS 13's labwc 0.20 needs newer libwayland, libxkbcommon and
  libdrm than Debian 13 has.
- Debian 13's labwc 0.8.3 runs Raspberry Pi OS 13's rc.xml, with two gaps:
  Light font weight is shown as Regular, and the switcher has no icons.
- Reference files and screenshots of Raspberry Pi OS 13's Wayland session
  (raspios-ref), kept on the VM host.

Experiment (W0, deb13-lxde, reverted):
- Debian's labwc 0.8.3 with Raspberry Pi's wf-panel-pi 1.43 and Raspberry
  Pi OS 13's labwc files: the session runs with the PiXtrix frame.
- Raspberry Pi's swaylock renamed (PAM service "swaylock" without its file)
  authenticates through Debian's PAM "other" service (common-auth): the
  right password is accepted, a wrong one refused.

Unit tests:
- tests/rpios-look-wayland.bats, 29 tests written by a subagent. Its
  mutation checks found 4 script bugs, all fixed:
  - rpios-look-set on Wayland failed on every --theme (unset variables
    under set -u);
  - the fallback panel layout was not Raspberry Pi OS's;
  - an empty kanshi file was left after uninstall;
  - choose_session skipped any previous session named rpios-look*.
- All tests: 158/158.

Code review (code-review skill, medium): 10 candidates.
- Fixed:
  - swaylock kept when Wayland was dropped;
  - rpios-look-set read the X session's font on Wayland;
  - no `_l` fallback on Wayland;
  - one-line `<theme>` sections not removed correctly;
  - empty Raspberry Pi package directory read the host's /etc/xdg;
  - --refresh closed file manager windows;
  - the panel's left-out plugins listed twice.
- Not changed: Debian release changes left out of --refresh (the user's
  decision: uninstall first). An older dependency check (outside this work)
  was left as is.

VM runs:

| Run | VM | What | Result |
|---|---|---|---|
| W1 run1 | deb13-lxde | install | stopped before any change: swaylock's zsh completion is also Debian's; twins now drop shell completions |
| W1 run2 | deb13-lxde | install, X, Wayland | session runs (labwc, wf-panel-pi, desktop, kanshi, Xwayland + xsettingsd); rpios-look-set --theme failed (bug 1 above) |
| W1 run3 | deb13-lxde | full | themes on Wayland, PiX refused (exit 2), --list without pix, --session x/wayland; uninstall left two empty labwc files (fixed); apt-listchanges timer link gone (not reproduced since: dbg1/dbg2 show it kept through install, reboot and Wayland login) |
| W1 run4 | deb13-lxde | full | all phases RC 0; refresh ×2 "nothing to apply"; uninstall: no difference but a Debian update and test files; duplicate title bar buttons after a theme change (fixed: no `<titlebar>` in the user's labwc file); no lock line in the Shutdown dialog (fixed: Raspberry Pi's rc.xml kept as shipped, `swaylock -p` through the session's own swaylock launcher) |
| W2 | debsid-lxde | full | all phases RC 0; lock and unlock; refresh ×2 "nothing to apply"; uninstall: no difference but a Debian update and test files |
| W1 run5 | deb13-lxde | full | Shutdown dialog shows "Press 'Ctrl-Alt-l' to lock screen"; single title bar buttons; all phases RC 0; clean uninstall |
| LK | deb13-lxde | unlock after Ctrl+Alt+L | four ways (typed at once; after Ctrl and Alt; after a click; started directly): all unlock, swaylock receives the password each time. Earlier failures came from the test's open Shutdown dialog |
| XR13 | deb13-lxde | X session regression: install, login, idle, themes (PiXtrix, PiXonyx, PiXflat, PiX), refresh ×2, uninstall | all RC 0; Openbox themes as set; idle as R9 (blank and monitor off 10 min, no lock); refresh ×2 "nothing to apply"; uninstall: no difference but a Debian update and test files |

Look (screenshots, files first): PiXtrix wallpaper, Raspberry Pi's panel
and menu, PiXtrix window frame; PiXflat after rpios-look-set; GTK 2 (xsane)
under Xwayland; the Pi mode lock screen. Gaps as expected: titles in Regular
instead of Light, no switcher icons (labwc 0.8.3).

## 1.0.0 and 1.0.0 (legacy), the Large and Larger sizes as on Raspberry Pi OS 12 and 13 (2026-11-09)

Found while reading Raspberry Pi OS's Wayland files: its Appearance
Settings (pipanel 1.3x on Raspberry Pi OS 12 since 2024-03, 2.x on 13;
`src/defaults.c`, `src/system.c`) give the Large and Larger presets the
theme's large window theme (`PiXflat_l`, `PiXnoir_l`, `PiXtrix_l`,
`PiXonyx_l`: 14-pixel title bar buttons instead of 8), 17-pixel scrollbars
and 20-pixel invisible resize borders, in Openbox and labwc alike.
Raspberry Pi OS 9 to 11 never did; PiX has no large window theme. Both
scripts set none of this for `--size large|larger`.

Change: both scripts, on Debian 12 (legacy) and 13+ (main), for Large and
Larger: the session's Openbox `<theme>` names `<theme>_l` (the theme itself
when the package has no `_l`), `invHandleWidth` 20, and each session theme
layer adds the scrollbar rules (button 17, slider 11), as pipanel writes
them; the `_l` themes get the session's Openbox button links;
`rpios-look-set --theme` keeps the size's window theme. Debian 9 to 11 and
Small/Medium unchanged. Not done: GTK 2 scrollbars (pipanel writes each
user's `~/.gtkrc-2.0`; the session has no shared GTK 2 file).

bats: 129/129 (3 new; both mutated scripts fail them). shellcheck: no new
warnings.

| Run | VM | Script | Install `--size large` | Session Openbox | Running Openbox (`_OB_THEME`) | Scrollbars | `rpios-look-set` | Uninstall | Time |
|---|---|---|---|---|---|---|---|---|---|
| LG13 | deb13-lxde | main | RC 0 | `PiXtrix_l`, handles 20 | `PiXtrix_l` | 17/11 in all 5 layers | PiXonyx → `PiXonyx_l`, PiXflat → `PiXflat_l`, PiX → `PiX`; reset → `PiXtrix_l` | RC 0, no difference but a Debian update (libpcre2) and test files | 11 min |
| LG12 | deb12-amd64 | legacy | RC 0 | `PiXflat_l`, handles 20 | `PiXflat_l` | 17/11 in all 3 layers | PiXnoir → `PiXnoir_l`, PiX → `PiX`; reset → `PiXflat_l` | RC 0, no difference but test files | 9 min |
| LG12i | deb12-i386 | legacy | RC 0 | `PiXflat_l`, handles 20 | `PiXflat_l` | 17/11 in all 3 layers | PiXflat → `PiXflat_l`; reset → `PiXflat_l` | RC 0, no difference but test files | 9 min |

Screenshots (pixels to confirm): the large title bar buttons and the wider
scrollbar on PiXtrix, PiXonyx, PiXflat and PiXnoir; PiX unchanged.

## 1.0.0 and 1.0.0 (legacy), idle behaviour as on Raspberry Pi OS (2026-11-07)

Reference, measured on Raspberry Pi OS for PC: 9 (2019-04-11), 10
(2021-01-11) and 11 (2022-07-01) as live VMs, 13 (2026-10-13) installed, in
its X and Wayland sessions; 12 from its desktop packages (no PC image).

- Every X session (9, 10, 11, 13): blanking after 600 s, DPMS standby,
  suspend and off at 600 s, no screen locker installed or running, no power
  manager, no compositor; systemd-logind IdleAction `ignore`, lid `suspend`.
- 13's Wayland session: no automatic lock or blanking; Ctrl+Alt+L runs
  `swaylock -p`. 12 installs swaylock and swayidle for Wayland, nothing for X.
- Tooltips: opaque in every X session; see-through and rounded only in the
  Wayland session (labwc composites).

Changed: screen lock off by default, sleep on battery `never`, DPMS standby
and suspend at the monitor-off time; the power helper waits for a signal
only when nothing can come due.

Fresh install on Debian 13 (main) and 12 (legacy), VMs: rc 0; defaults
lock off, sleep never, lid sleep; `xset`: blanking 600 s, DPMS 600/600/600
(13; the 12 VM has no DPMS); the helper woke 0 times in 120 s (4 before);
`rpios-look-power --lock on` starts light-locker, `--lock off` stops it.
bats 112/112.

## 1.0.0 and 1.0.0 (legacy), upgrades and --refresh after R9 (2026-11-08)

Changed in both scripts: `--prepare-upgrade` removed with its functions and
records; a Debian release upgrade is Debian's own (uninstall first, then a
clean install; the scripts never check for a new release). `--refresh`
updates the installed Raspberry Pi OS release only. The state records the
edition; each script stops before any change when the other one installed
the rpios-look script.

Found and fixed: the removal left one line that read the dropped variable,
so every install stopped at its last step (`base: unbound variable`); bats
cannot reach that step, the first U3 run did. shellcheck finds no other
unset variable.

- U3 (deb12-amd64): legacy install with PiXnoir, size large; Debian 12 → 13
  with the rpios-look script installed: rc 0 (`ofono` held back: Debian's
  own, on the VM before). On 13: main install and `--refresh` stop ("installed
  by rpios-look-legacy.sh … uninstall it first"), legacy `--refresh` stops
  (Debian 13), nothing changed (checksums). `rpios-look.sh --uninstall` rc 0;
  clean main install, refresh ×2 ("nothing to apply"), uninstall: rc 0.
- U4 (deb13-lxde), a future release: main install with PiXonyx, size large;
  Debian 13 → testing (forky) with the rpios-look script installed: rc 0.
  `--refresh` there keeps Raspberry Pi OS 13 (state `release trixie`) and
  takes Debian's GTK 3 Qt themes, as on sid; uninstall, clean install,
  refresh ×2 ("nothing to apply"), uninstall: rc 0.
- Upgraded without uninstalling (U3, U4): Debian's upgrade marks two Qt
  style plugins as installed by name, so the uninstall keeps them (on
  testing with the Qt 5 libraries they need). Not on the recommended path.
- L1r (deb12-amd64, legacy) and M1r (deb13-lxde, main): install, session,
  refresh ×2 ("nothing to apply"), uninstall rc 0; after uninstall only
  CUPS runtime files, files the harness opened in Debian's LXDE and (13)
  Debian's libpcre2 point update differ.
- bats 126/126.

Harness: a run now stops when its install fails; an image compaction
started while the queue waited raced with M1r, which ran again.

## 1.0.0 and 1.0.0 (legacy), round R9: every release, architecture and theme (2026-11-08)

VMs as listed above, plus deb9-i386 and deb9-amd64 (Debian 9, LXDE). The
rules are checked from the files first (Raspberry Pi's panel files,
desktop.conf, Openbox and theme files); screenshots only confirm.

Online, install → idle → themes → Debian's LXDE → refresh ×2 → uninstall
(D9, D9a, L4, L7, L8, L1, L2, L9 legacy; M1, M3, M4, M5 main): every step
rc 0.
- Idle: lock off, blanking and monitor off at 10 min, no light-locker.
- Rules: debian-reference only in legacy (9–12); no xscreensaver or xfce4-*
  installed; PipeWire only without a sound server (sid: installed; with
  PulseAudio: not); the magnifier installed, not on the panel; on 9–12 no
  later look installed.
- Panel files, setting by setting against Raspberry Pi's (stretch, buster,
  bullseye, bookworm, trixie): same global settings and plugin order. Left
  out by design: updater and power, the battery without a battery, the
  network plugin on 9–11 (dhcpcd), the ejecter on 9 (Raspberry Pi's stretch
  build needs a newer fontconfig than Debian 9 has).
- Shutdown dialog: on 13 with the lock line ("Press 'Ctrl-Alt-l' to lock
  screen") on all 5 themes, Ctrl+Alt+L locks and unlocks; on 9–12 as
  Raspberry Pi OS shows it (no lock line).
- Uninstall: no difference except the harness's own files and Debian's
  own runtime files (CUPS subscriptions, font cache).

Offline, from a bundle on a read-only disk (OF9a–OF12b, 32 and 64 bit):
a damaged package is refused (SHA256SUMS mismatch, nothing changed); the
install rc 0 with no network; all themes, the shutdown dialog and Debian's
LXDE as online; uninstall rc 0, no difference; on Debian 12 the online
`--refresh` twice afterwards rc 0.

`--download` (DL9a–DL12b): on 9 and 10 it stops at once (their archive keys
cannot check newer releases) and changes nothing; on 11 and 12 it builds
the same packages/ as the reference bundle (1736 packages, every file the
same) and changes nothing outside its folder.

Found and fixed:
- `--download` on deb11-lxde stopped ("fakeroot: command not found"): the
  repack helper read `dpkg-deb --help` through a pipe to decide whether
  fakeroot is needed, and that failed now and then under load (5 of 3000 on
  that VM). Both scripts now decide by dpkg's version.
- After a Debian release upgrade (12 → 13): the upgrade marked two Qt
  style plugins as installed by name, and the uninstall kept them as the
  user's. `--prepare-upgrade` now records the marks, and the next run puts
  the script's dependencies back to automatic. A dependency updated from
  its .deb file is also put back to automatic.
- After the same upgrade, the main script used Debian's GTK 3 Qt themes
  instead of Raspberry Pi's GTK 2 styles: the plugins left from Debian 12
  counted as installed. A dependency the script installed, which no APT
  source has any more, is now taken again from Raspberry Pi.

12 → 13 upgrade (U1), with all three fixes: legacy install,
`--prepare-upgrade`, upgrade, main install (Raspberry Pi's GTK 2 Qt styles,
the plugins from Debian 12 updated to Raspberry Pi's builds), refresh
("nothing to apply"), uninstall (every Qt style plugin purged): rc 0
throughout. M1 (13) and L1 (12) again with the fixes: install, refresh ×2
("nothing to apply"), uninstall rc 0, no difference after uninstall but
Debian's own updates. `--download` on both Debian 11 VMs again: rc 0, the
same packages/ as the reference.
bats 124/124.

Harness faults found and fixed during the round (no script change): the
offline bundle disk could not be attached from the home folder, the
damaged-package test could not change the read-only link tree, the shutdown
shot used pishutdown where 9–11 have lxde-pi-shutdown-helper.

## 1.0.0, clean reinstall on a real Debian 13 desktop (2026-11-07)

A real computer (Debian 13, amd64) in daily use, with Debian's LXDE.

- `--uninstall` of the installed 1.0.0: rc 0; no rpios-look package and no
  records left.
- Fresh install, no settings put back: rc 0; after a restart the session
  runs Raspberry Pi's Openbox, panel and file manager, with PiXtrix and the
  Trixie wallpaper; no user Openbox file; color-scheme `default` (light);
  no failed system or user units; no errors in `~/.xsession-errors`; the
  user's desktop shortcuts kept.
- picom and light-locker, installed earlier by the user and by Debian's
  LXDE, are used by the session's compositor and power helpers, not
  installed by the script.
- `--refresh` twice: rc 0, "nothing to apply" both times.
- bats on that computer: 112/112.

## 1.0.0 and 1.0.0 (legacy), the user's own keys (2026-11-07)

Debian 13 (main) and 12 (legacy), fresh install, keys pressed through the
VM's keyboard: Super+E, Ctrl+Alt+T, Ctrl+Shift+Esc.

- Without a user file: Super opens the menu; Ctrl+Alt+T opens the terminal,
  Ctrl+Shift+Esc the task manager.
- A user file holding only a `<keyboard>` section with Super+E and
  Ctrl+Alt+T: both run the user's commands, and the session's other keys
  (Ctrl+Shift+Esc, Super) stop working. Openbox's `parse_keyboard` drops the
  earlier keys first, so the README's "Your own keys" starts from a copy of
  the session's section.
- `rpios-look-set --theme` keeps the user's keys (two keybinds still in the
  file, both work), also after a new login; `--reset` removes the file and
  the session's keys work again.
- The README's copy command, run on a missing file and on a theme-only file:
  valid XML, all 35 session keys, the theme kept, and nothing added on a
  second run.

Seen once: on Debian 13, after the harness restarted LightDM under a running
session, a polkit dialog said "An authentication agent already exists for
the given subject". Not seen at the other nine logins on both systems or in
round R8.

## 1.0.0 and 1.0.0 (legacy), round R8 (2026-11-07)

First round of the 1.0.0 scripts (earlier installs are no longer handled).
bats 112/112, shellcheck at baseline. Fresh installs from the fresh snapshot.

| Run | VM | Script | Phases | Result |
|-----|----|--------|--------|--------|
| M1 | deb13-lxde | main | install, session, keys, login time, refresh twice, uninstall | PASS |
| L1 | deb12-amd64 | legacy | install, session, keys, login time, refresh twice, uninstall | PASS |
| X13 | deb13-lxde | main | install and first login, SSH agents of both sessions | PASS |

- Install, `--refresh` (both "nothing to apply") and `--uninstall` RC 0 on
  both; after the uninstall only the test tools, Debian updates and CUPS's
  own files differ from before the install.
- Openbox: the session's settings come from the system file (`rpd-rc.xml` on
  13, `lxde-pi-rc.xml` on 12, with `rc.xml` beside it); no Openbox file in
  the home folder after the first login; a theme change writes a file with
  the theme only (no keys), and the keys still work (Ctrl+Alt+T opens the
  terminal); the file stays byte for byte the same over two logouts and
  logins; `rpios-look-set --reset` removes it. Debian's LXDE file is never
  touched.
- Dark mode: 13 `prefer-light`/`prefer-dark` with the theme, `default` after
  `--reset`; 12 `default` with every theme, as Raspberry Pi OS 12.
- SSH: the session's profile has no `keyring/command`; lxsession's built-in
  default still starts `ssh-agent -s` once, exactly as in Debian's own LXDE
  session (seen in both), beside the X session's agent.
- accountsservice not installed by the script (Debian's LXDE desktop on 13
  brings its own).
- Login to panel and desktop, Debian's LXDE before → after the install: 12
  1.82–1.95 s → 1.91–1.93 s; 13 1.90–2.02 s → 1.97–2.12 s. Raspberry Pi
  Desktop: 12 1.45–1.75 s (one 3.30 s outlier), 13 1.63–1.69 s.
- Not run this round: L2 (12 i386), U1 (12 → 13 upgrade with
  `--prepare-upgrade`), offline (`--download`/`--offline`), the GUI tools
  (obconf, Appearance Settings) by hand.

## Known harness limits

- QEMU key input: X may drop the first key after the lock screen; the
  harness sends a key first.
- Raspberry Pi OS for ARM cannot be compared for speed (emulated);
  the references are its x86 builds.
