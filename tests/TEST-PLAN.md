# Test plan: rpios-look.sh and rpios-look-legacy.sh 1.0.0

The release tests of both scripts. Results are recorded in
[HISTORY.md](HISTORY.md).

## Setup

- **Machines:** virtual machines (libvirt/KVM), one per Debian release and
  architecture, each installed with Debian's LXDE desktop and kept as a clean
  snapshot (`fresh`). Every run starts from that snapshot. A reference virtual
  machine with Raspberry Pi OS 13 (amd64) is used to compare the look.
- **Order:** at most two virtual machines at a time; the Debian 9 machines
  one at a time. Free disk space is checked before each run.
- **Scripts:** copied from the repository at the tested commit.
- **Test-only setup inside the virtual machines:** passwordless sudo and
  automatic login, to drive the runs. Never on a real computer.
- **Stop rule:** at the first failure that breaks Debian, stop, fix, re-run.

## Checks in every install run

1. **The run:** exit status 0; the log has no errors; the plan lists the
   expected packages; the risk warning and, where expected, the old-release
   warning are shown.
2. **Debian's health:** `dpkg --audit`, `apt-get check`, no held or broken
   packages, `systemctl --failed` empty, `apt-get -s dist-upgrade` clean.
3. **Session:** automatic login into Raspberry Pi Desktop; panel, desktop and
   menu up.
4. **Defaults:** theme, dark variant, icons, cursor (24 px), font, monospace
   font and wallpaper as in the README's
   [Looks per release](../README.md#looks-per-release). No power helper
   runs, no screen locker starts and no polkit rule is installed; the X
   server's own blanking (10 minutes) applies; on 13 and later, Raspberry Pi Desktop (X) is the first login's session
   and both sessions are on the login screen.
5. **Every theme of the release:** switch to each with
   `rpios-look-set --theme`, and for each:
   - screenshots of the desktop with the menu open, a GTK 3 window and a
     GTK 2 window;
   - the settings file, icon and cursor theme, font and wallpaper applied;
   - compared with Raspberry Pi OS (the reference machine for PiXtrix and
     PiXonyx; the release's own defaults and Raspberry Pi's theme files for
     the older looks).

   `rpios-look-set --list` shows exactly the release's themes (no later
   ones); `rpios-look-set --reset` returns to the default.

   | Debian | Themes |
   |---|---|
   | 9 | PiX |
   | 10, 11, 12 | PiX, PiXflat, PiXnoir |
   | 13, sid | PiX, PiXflat, PiXnoir, PiXtrix, PiXonyx |
6. **Keys and settings:**
   - Ctrl+Alt+M toggles the magnifier (not on the panel; it can be added);
   - the display key opens LXRandR;
   - the IBus tray icon is hidden;
   - the Qt setting is in this session only, not in Debian's LXDE session.
7. **Not buggy**, in the Raspberry Pi Desktop session:
   - popups, menus, tooltips and notifications show and are drawn correctly;
   - moving and resizing windows leaves no corrupted corners or redraw
     artifacts; panel and desktop layout stay correct;
   - preferences work: Default Applications, Desktop Preferences, Openbox
     Configuration, Customize Look and Feel, keyboard, mouse and display.
8. **Not bloaty, not slow:** compared with Debian's LXDE session on the
   same machine: time from login to a ready desktop, memory used after
   login, idle CPU over a minute (no polling or wakeups), the list of
   session processes (only those the look needs), and how fast menus,
   the file manager and theme switches open.
9. **Debian's own LXDE session** still logs in and looks as before, with
   Debian's own packages untouched: `dpkg -l lxpanel pcmanfm 'libfm*'
   openbox 'libob*' libnma0 obconf lxappearance-obconf` shows Debian's
   versions only (no `+rpt`, `+rpi`); Debian's `obconf` and LXDE's
   Appearance (Window Border tab) open and work, on 32-bit too.
10. **Beside Debian's:** Raspberry Pi's builds are installed as
   `rpios-look-*` packages; `ps` in the Raspberry Pi Desktop session shows
   `openbox-pi`, the panel (`lxpanel-pi`) and the desktop (`pcmanfm-pi`);
   `grep -E 'libobrender\.so|libnma\.so' /proc/$(pgrep -x
   openbox-pi)/maps` (and the same for the panel) lists only the `...pi.so`
   libraries; in Debian's LXDE session, only Debian's. The panel
   (`lxpanel-pi`, as Raspberry Pi ships it) uses Debian's libfm.
   APT: Raspberry Pi's archive is in the sources and pinned (`apt-cache
   policy` shows 500 only for the packages used unchanged); `50rpios-look`
   holds only the `DPkg::Post-Invoke` check; there is no local repository.
11. **`--refresh`** right after the install: nothing to update, or only real
   updates.
12. **`--uninstall`:** the computer is back to its state before the install;
   no `rpios-look-*` package, `/var/lib/rpios-look`, APT source or check
   is left; the user's own programs and settings are untouched; Qt libraries
   stay while a Qt program needs them.

## Runs

| # | Debian | Arch | Script | Run | Extra checks |
|---|---|---|---|---|---|
| M1 | 13 | amd64 | main | install, refresh, uninstall | all five themes; Qt style plugins; online release table; update notice |
| M2 | 13 | amd64 | main | theme kept after other setting changes | change the theme, then settings through LXSession and lxappearance; watch the settings file; confirm the theme stays |
| M3 | 13 | amd64 | main | with a Qt program installed first | Qt programs follow the GTK theme; still work after uninstall |
| M4 | sid | amd64 | main | install, uninstall | best effort |
| M5 | 12 | amd64 | main | refusal | stops before any change, writes no log, names the legacy script |
| L1 | 12 | amd64 | legacy | install, refresh, uninstall | network item with NetworkManager; Debian's panel and file manager untouched throughout |
| L2 | 12 | i386 | legacy | install, uninstall | 32-bit |
| L3 | 11 → 12 | amd64 | legacy | install on 11 (Qt `gtk3` setting), `--uninstall`, upgrade to 12, clean install | Debian 11's setup back after the uninstall; Qt `gtk2` setting on 12 |
| L4 | 10 | i386 | legacy | install, uninstall | no Wi-Fi: firmware and wicd steps stay silent |
| L5 | 10 | amd64 | legacy | `--download`, then `--offline` without network | the same result as online; SHA256SUMS checked |
| L6 | 13 | amd64 | legacy | refusal | stops, names the main script; `--uninstall` still allowed |
| L7 | 11 | i386 | legacy | install, uninstall | 32-bit |
| D9 | 9 | i386 | legacy | install, refresh, uninstall | Stretch's own packages; PiX only; Stretch's panel or Debian's with a note |
| D9a | 9 | amd64 | legacy | install, refresh, uninstall | as D9 |
| U1 | 12 → 13 | amd64 | both | legacy install, legacy `--uninstall`, upgrade to 13, main install | no leftovers (optional) |
| A1 | 13, 12 | amd64 | both | updates | install an older build of a Raspberry Pi package used unchanged: `sudo apt upgrade` updates it; an older repacked build: only `--refresh` updates it; remove a look package with `apt-get remove`: APT's check names it and `--refresh` brings it back |
| W1 | 13 | amd64 | main | Wayland session: install, login, themes, lock, refresh ×2, uninstall | both sessions on the login screen, X the default, no graphics check; Raspberry Pi OS 13's panel, menu and keys (Ctrl+Alt+T, the power button opens the Shutdown dialog, held for the session while labwc runs); no idle helper; `rpios-look-set` records and restores your labwc files |
| W2 | sid | amd64 | main | as W1 | best effort |
| X1 | 13, 12 | amd64 | main, legacy | the other edition's install | each script refuses the other's install before any change; each `--uninstall` removes the other's (with its Wayland session) |

## Order

The Debian 9 machines are built while M1 runs. Then: M1, M2, L1, L3, M3, L2,
L4, L7, D9, D9a, M5, L6, M4, L5, and U1 if time allows.
