# Test history

Each run of the test suite: what was tested, the result, and what it found.
Newest first.

## Test machines

Virtual machines (KVM/libvirt, 2 vCPUs, 3 GB memory, virtio graphics
without 3D acceleration, 1280×800). Each Debian VM was installed with
Debian's LXDE (`task-lxde-desktop`, LightDM, X) and is reverted to that
fresh snapshot before each install.

| VM | System | Architecture | Role |
|----|--------|--------------|------|
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

Suite phases (queue.sh): 1 online install, uninstall, fix checks,
`rpios-look-set` and `rpios-look-power`; 2 offline install and uninstall
(packages/ from `--download`); 3 look, behaviour (21 checks per theme),
package health, Don't Break Debian; 4 speed and resources against Debian's
own LXDE; 5 A/B of Raspberry Pi's packages against Debian's; 6 report.

## 3.17.1 (2026-11-03)

Five notes from daily use on the desktop PC, tested on all 8 VMs (fresh
install, every theme), raspios-ref and the desktop PC.

- **Slow theme change, fixed.** `rpios-look-set --theme` took up to 4 s:
  after `openbox --restart` it waited for Openbox's check window to change,
  but Openbox restarts on a new X connection that can get the old client
  slot, so the window kept its ID and the wait ran its full 3 s. It now
  removes `_OB_VERSION` from the root window and waits for Openbox to set it
  again. Result: 0.6–1.1 s on every release and theme (Debian 13, first
  change: 3.96 s before).
- Network during the panel restart: a ping every 0.1 s lost no packets and
  NetworkManager stayed connected on every release and theme.
- Launch bar after a quick logout and login (the user saw a "+" once): the
  browser, file manager and terminal launchers were there after all 28
  logins through the login screen (4 per VM, 1 s and 15 s after the
  logout). Not reproduced; the desktop PC's session log of that login shows
  no error.
- Desktop icon tooltips: shown 3 of 3 times on every release and theme
  where the icon was visible. Harness: on the 1024×768 VMs a window left
  open by the resize check covered the Trash after the first theme.
- Microphone mute after logout: lost on Debian 13 and sid, kept on Debian
  10 to 12. The login screen starts PipeWire and WirePlumber as the
  `lightdm` user; they reset the sound card and the user's WirePlumber
  (0.5.8) saves the route as unmuted. raspios-ref does the same (same
  WirePlumber). A restart of LightDM without the login screen keeps the
  mute. Left as Debian and Raspberry Pi OS have it; README notes it.
- Window resize: on the VMs (no compositor) the contents redraw cleanly
  while a window grows or shrinks. On the desktop PC (NVIDIA's driver,
  picom) the right side and title bar break up during fast resizing; frames
  grabbed with `import` do not show it. picom with `--xrender-sync-fence`
  is being tried there.
- Harness: the login screen hides the user list until a user has logged in
  once, and the VMs' remembered session was Debian's LXDE; the relogin
  check now types the user name, waits out the failed-login delay, then
  the password, and sets the session through AccountsService.
- Desktop PC: a capture script closed its test window with `xkill`, which
  ended the desktop (`pcmanfm-pi --desktop`); it was started again. Test
  windows are now closed with WM_DELETE_WINDOW.

## 3.17.0 (2026-11-01 to 11-03)

Support narrowed to Debian's LXDE on X: the Wayland session, the code for
other desktops and for Debian-based distributions are removed; the script
stops before changing anything where Debian's LXDE is not installed or the
system is not Debian. The offline bundle leaves out what Debian's LXDE
already has. The full suite runs again on this version, every phase, every
VM and theme.

- Refusals: on Debian 12 without LXDE the script stops with "LXDE only"
  before adding an APT source or a package.
- `--download` (on the VM host): packages/ 861 MB, 1808 packages,
  7 indexes, SHA256SUMS verified (3.16.2: 1.1 GB, 2292 packages).
- Phase 1, online: all 8 VMs install and uninstall with rc 0; fix checks
  32/32 on each; every theme applies, bad values refused. After uninstall
  Debian 10 and 11 and Debian 12 i386 show no difference. The other VMs show
  only Debian's own updates (libpcre2 on 13 and sid) and LXDE's
  `desktop.conf`. LXDE's lxsession writes that file over its first two
  logins, without the script too, and the baseline was taken between them.
  The harness now logs in once more before the baseline.
- Phase 2, offline: install rc 0 on Debian 10 to 13 and gives the same
  packages as online; sid refuses offline mode by design. **Regression:**
  offline uninstall left Raspberry Pi's builds of lxpanel, pcmanfm, libfm,
  Openbox and libnma installed ("APT could not put Debian's builds back").
  The smaller bundle subtracted what Debian's LXDE has, Debian's builds of
  those packages included. Fixed: they are always bundled. Run again:
  `--download` 866 MB, 1844 packages; offline install rc 0 on Debian 10 to
  13, and uninstall leaves no difference on all 8 VMs.
- Phase 3, behaviour (8 VMs × 5 themes, raspios-ref): panel, desktop and
  Openbox stay up in every run; menus, run dialog, terminal, full screen,
  maximise, task manager, shutdown dialog, screenshot, volume, right-click
  menus and lock/unlock work. Found:
  - **Bug:** Debian 13, PiXnoir: the launch bar came up empty after the
    theme change. Each theme change rebuilt the session's menu folder
    (deleted, then written again) and restarted the panel at the same moment.
    The panel then read the menu while menu-cache was still rebuilding it.
    Fixed: the folder is replaced only when its entries change, so a theme
    change leaves it alone.
  - Harness: on Debian 10, Firefox ESR answered the harness's close with
    "Close tabs and quit?" and covered the desktop (right-click, Trash).
    Started from the panel's launcher it runs as `x-www-browser`, a name
    the harness's kill first missed. With that name added, both Debian 10
    VMs pass all 21 checks with every theme.
  - Harness: the clock's calendar on lxpanel-pi (Debian 13, sid and
    Raspberry Pi OS itself) is a managed window of the panel, which the
    harness skipped. The screenshots show it open; it is now counted.
  - Harness: a second lxpanel process for a moment right after
    `rpios-look-set --reset` (Debian 10 i386); the check now counts again
    after 3 seconds.
  - Phase 3 and the `rpios-look-set` checks run again with these fixes, with
    a second pass on Debian 13 and sid.
  - Debian 13: the panel hung once after a theme change, and could not be
    reproduced in 26 more. Openbox and the panel restarted at the same
    moment; `rpios-look-set` now restarts the panel only after Openbox is
    back (it names a new check window). Debian 13 and sid, fresh install,
    each theme twice: 20/20 PASS (21 checks each).
  - Harness: sid, PiXflat once reported "panel not restarted for new
    icons". lxpanel-pi restarts in place on a new X connection; the X server
    can give it the old client slot, so its new windows get the old IDs.
    Recorded with `xev`, the panel created both windows again on every
    theme change, those runs included. The harness now counts the panel's
    new windows; 8/8 theme changes on sid show the restart, and a change
    to the same theme shows none. (A retry in `rpios-look-set` built on the
    ID check was tried and dropped: it would only restart the panel again.)
- Phase 4, speed and resources, each VM alone, against Debian's own LXDE on
  the same VM:
  - Idle CPU: the script's session uses less than Debian's LXDE on every
    release (10–20 against 30–90 ms per minute), since it leaves out
    Debian's clipboard manager and the like.
  - Terminal and file manager start within ±15% of Debian's LXDE; the menu
    opens in 30–50 ms (Debian's LXDE: 280–370 ms).
  - Memory (PSS of the session) is equal on Debian 10, 13 and sid. On
    Debian 11 and 12 it is 37–74 MB higher. Raspberry Pi's panel and file
    manager are GTK 3 builds there, while Debian's are GTK 2. GTK 3 loads the
    OpenGL driver at start, which is LLVM (llvmpipe) on a VM without a GPU
    driver: about 23 MB per process. `GDK_GL=disable` would save it, but
    programs started from the session would inherit it and lose OpenGL
    (GtkGLArea, such as Totem's video), so it is not set.
  - Disk: 39–83 packages, 113–178 MB.
  - Harness: login time and lxpanel-pi's menu were not measured at first.
    GTK 2's panel window is named "panel", and lxpanel-pi opens its menu
    with `command smenu menu`. raspios-ref's sudo also used a wrong password
    helper there, which also failed its unlock and Don't Break Debian
    checks. Fixed and measured again: login 1.3–2.5 s (Debian's LXDE
    1.7–2.4 s); faster on Debian 10, 13 and sid, 0.4–0.6 s slower on
    Debian 11 (GTK 3 panel). Menu 25–51 ms on every release. The
    per-theme menu times on Debian 13 and sid in that report are from the
    first, wrong command.
- Phase 5, A/B on all 8 VMs, every theme: with Raspberry Pi's packages
  0 failed checks (10 on Debian 10: the Firefox harness issue), with
  Debian's own 30–40; `--refresh` brings Raspberry Pi's back on every VM.
  Harness: deb12-amd64 got another address from DHCP after the reboot,
  and the first run lost it; the harness now finds the address again.
- The VM host ran out of disk space (VM images): the queue waited for
  space. An unused installer image was removed.
- Unit tests: 10/10.
- **Bug (desktop PC, NVIDIA's driver):** the screen stayed black after
  unlocking. The lock screen's login screen runs on another virtual
  terminal; NVIDIA's driver drops picom's GL images while the session is
  not shown, and picom kept showing them. Reproduced by switching to a text
  console and back. Fixed: the compositor wrapper starts picom again each
  time the session's terminal comes back; two round trips show the desktop.

## 3.16.2 (2026-11-01, stopped after phase 1)

Full suite, every phase, every VM and theme.

- Phase 1, online: all 8 VMs install and uninstall with rc 0; Debian 10 to 12
  leave no difference after uninstall; fix checks 32/32 on each.
- `--download` (on the laptop): packages/ 1.1 GB, 2292 packages,
  7 indexes, SHA256SUMS verified.
- Stopped after phase 1 for the 3.17.0 changes.

Changes tested in this version:
- A new icon theme restarts the panel, so its icons follow at once.
- NVIDIA's own driver: picom composites the session; dragged windows keep
  rounded corners and no longer smear (checked on a PC with an NVIDIA card).

## A/B of the package choice, 3.16.2 (2026-11-01)

Debian 12 and 13 (amd64), PiXflat: behaviour with Raspberry Pi's packages
(A), with Debian's own after `--prepare-upgrade` (B), and back (C).

- Debian's packages lose: menu icons (12) or the menu key (13), the volume
  and mute keys, the shutdown dialog, Alt+F2 (13), Ctrl+Alt+Up (12), and
  rounded corners while windows move. No missing libraries or crashes on
  either side.
- `--prepare-upgrade` and `--refresh` switch both ways; C's package versions
  equal A's.
- Result: Raspberry Pi's packages are the right choice where the script
  uses them.

## 3.16.1 (2026-11-01)

Behaviour on 8 VMs × 5 themes (40 runs) and raspios-ref; package health;
piuparts.

- All 40 runs: panel, desktop and Openbox stay up; menus, run dialog,
  terminal, full screen, maximise, task manager, shutdown dialog, screenshot,
  volume, launchers, right-click menus and lock/unlock work.
- Debian 10: the trash test failed only because Firefox ESR stayed open
  ("Close tabs?") over the desktop; with Firefox closed the trash opens.
  The harness now closes browsers.
- Package health: no missing libraries, no crashes, `dpkg --audit` and
  `apt-get check` clean; an upgrade removes nothing.
- piuparts (Debian 13): install and purge PASS; the only leftover is
  LightDM's own `display-manager.service` link.

Found and fixed in 3.16.1:
- Ctrl+Alt+T opened xterm on Debian (Debian ranks xterm above LXTerminal);
  the session now uses LXTerminal unless the user chose another terminal.

## 3.16.0 (2026-11-01)

Full suite: online, fix checks, themes, offline.

- All 8 VMs: install and uninstall rc 0; no difference after uninstall on
  Debian 10 to 12, two lines on 13 and sid (Debian's own updates).
- Fix checks 32/32 on every VM; every theme applies; bad values refused.
- Offline install and uninstall on Debian 10 to 13: rc 0, no difference
  after uninstall; sid refuses offline mode by design.

Found and fixed in 3.16.1:
- Debian 10: two network icons with wicd or ConnMan; NetworkManager now
  counts only when it runs the network.

## Known harness limits

- QEMU key input: X may drop the first key after the lock screen; the
  harness sends a key first.
- Raspberry Pi OS for ARM cannot be compared for speed (emulated);
  the references are its x86 builds.
