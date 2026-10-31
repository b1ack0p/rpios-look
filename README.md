# rpios-look

rpios-look installs the official Raspberry Pi OS desktop on Debian for 32-bit
(`i386`) and 64-bit (`amd64`) PCs: Raspberry Pi's themes, icons, cursors,
fonts, wallpapers, panel, file manager and login screen style. It adds a
separate session, **Raspberry Pi Desktop**. Debian and your other sessions
are not changed.

![PiXtrix, the Raspberry Pi OS 13 look, on Debian 13 with the menu open](screenshot/pixtrix.png)
![PiXflat, the Raspberry Pi OS 10 to 12 look](screenshot/pixflat.png)
![PiX, the legacy Raspbian look](screenshot/pix.png)
![The login screen](screenshot/login.png)

## Contents

1. [Quick start](#quick-start)
2. [Modes and options](#modes-and-options)
3. [Changing the look: rpios-look-set](#changing-the-look-rpios-look-set)
4. [Screen lock and power: rpios-look-power](#screen-lock-and-power-rpios-look-power)
5. [Offline installation](#offline-installation)
6. [Updating, upgrading and uninstalling](#updating-upgrading-and-uninstalling)
7. [Supported systems](#supported-systems)
8. [Troubleshooting](#troubleshooting)
9. [How it works](#how-it-works)
10. [Credits and licence](#credits-and-licence)

## Quick start

**Requirements:** Debian 10 or later, or a derivative; bash 4.4 or later; a
normal user account with sudo rights (do not run the script as root);
internet access, except for an [offline installation](#offline-installation).

1. Download `rpios-look.sh`, or clone this repository.
2. In a terminal, in the script's folder, run `bash rpios-look.sh`.
3. Enter your password, review the plan (every package with its version and
   origin) and answer `y`.
4. Log out. **Raspberry Pi Desktop** is preselected on the login screen; log in.

The script is safe to run again. Run from a terminal inside the session, it
also refreshes the running desktop.

## Modes and options

```bash
bash rpios-look.sh [MODE] [OPTION]...
```

| Mode | Action |
|------|--------|
| *(none)* | Install, or reinstall cleanly. Your Raspberry Pi Desktop settings (theme, wallpaper, panel, power) return to the defaults. |
| `--refresh` | List available updates, then ask before applying them. Your settings are kept. |
| `--uninstall` | Remove what the script added and restore Debian's setup. |
| `--prepare-upgrade` | Prepare for a Debian release upgrade. |
| `--download` | Build or refresh `packages/` for an offline installation. |
| `--offline` | Install from `packages/`, without a network. |
| `--help` | Show the help. |

| Option | Description |
|--------|-------------|
| `--size SIZE` | Raspberry Pi OS's size presets for fonts, icons, panel and cursor: `small`, `medium` (default), `large` or `larger`. It is saved and reused by later runs. |
| `-v`, `--verbose` | Also print the commands run as root, the files downloaded and other details. |
| `-V`, `--version` | Print the version. |

The look has no other options. Every theme is installed, and the default
theme matches your Debian release (see [Themes](#themes)).

## Changing the look: rpios-look-set

`rpios-look-set` changes the Raspberry Pi Desktop session for the current
user only. It needs no sudo, applies at once and is kept for later logins.

| Option | Action |
|--------|--------|
| `--theme NAME` | Use `pixflat`, `pixnoir`, `pixtrix`, `pixonyx` or `pix`. |
| `--animations on\|off\|default` | Turn animations on or off, or return to the session's default (`on`). |
| `--list` | List the installed themes. |
| `--show` | Show the current look. |
| `--reset` | Return to the session's look, animations included. |

Animations are on by default, as in Raspberry Pi OS. On X, Openbox draws an
outline when a window is minimized or restored, and GTK applications animate
switches, popovers and panels. On Wayland, labwc has no window animations;
only GTK's apply. `--animations off` turns both off. Windows that draw their
own title bar (such as Firefox) and applications with their own animations
are not affected.

Raspberry Pi's Appearance Settings or Control Centre also work, where
installed; otherwise use **Customize Look and Feel**.

## Screen lock and power: rpios-look-power

The session blanks the screen, switches the monitor off, locks the screen
and suspends the computer when idle. It uses Debian's tools: light-locker on
X, swayidle and swaylock on Wayland, and systemd-logind. Other screen lockers
and power managers do not start in this session; other sessions keep theirs.

`rpios-look-power` sets these for the current user only, without sudo.

| Option | Action | Default |
|--------|--------|---------|
| `--lock on\|off` | Lock after `--lock-after`, on waking and with the lock keys | `on` |
| `--lock-after MIN` | Lock after MIN idle minutes | `10` |
| `--blank MIN` | Blank the screen after MIN idle minutes | `10` |
| `--monitor-off MIN` | Switch the monitor off after MIN idle minutes | `10` |
| `--sleep-battery MIN` | Suspend after MIN idle minutes on battery | `30` |
| `--sleep-ac MIN` | Suspend after MIN idle minutes on mains power | `0` (never) |
| `--lid sleep\|lock\|nothing` | Action when the lid closes while you are logged in | `sleep` |
| `--show` | Show your settings and the defaults | |
| `--reset` | Return every setting to the default | |

- Minutes may be written `30`, `30m` or `30min`; `0` or `never` disables the action.
- Any option set to `default` (for example `--sleep-ac default`) returns to the
  default and follows it from then on.
- The defaults are stored in `/usr/share/rpios-look/power.conf`;
  `rpios-look-power --help` lists them.
- On X, the screen locks only with the LightDM login manager. With GDM, SDDM
  or another login manager, the session blanks and suspends but does not lock.

Example: suspend after 30 minutes on mains power and lock after 5:

```bash
rpios-look-power --sleep-ac 30 --lock-after 5
```

## Offline installation

1. On a computer with internet access, run `bash rpios-look.sh --download`.
   It builds `packages/` next to the script.
2. Copy `rpios-look.sh` and `packages/` to the offline computer.
3. There, run `bash rpios-look.sh --offline`.

- **Releases:** Debian 10 to 12 on `amd64` and `i386`; Debian 13 on `amd64`.
  Debian testing and unstable are not covered, because they change daily.
- **Result:** the same as an online installation, but without Raspberry Pi's
  APT source, so `apt` does not update the look.
- **Integrity:** every file is checked against `packages/SHA256SUMS` first.
- **Uninstall:** also works offline, with `packages/` next to the script.

## Updating, upgrading and uninstalling

| Task | How |
|------|-----|
| Update | `sudo apt update && sudo apt full-upgrade` updates the Raspberry Pi packages with Debian (online installations). `bash rpios-look.sh --refresh` also updates the packages the script adapts, and lists every change first. |
| Upgrade Debian | 1. Run `bash rpios-look.sh --prepare-upgrade`. It removes the packages built for this release, restores Debian's panel and file manager, and removes Raspberry Pi's APT source. Themes, icons, fonts and wallpapers stay. 2. Upgrade Debian and reboot. 3. Run `bash rpios-look.sh` again. |
| Uninstall | Run `bash rpios-look.sh --uninstall`. It lists what it removes and asks first. It restores Debian's Openbox, panel and file manager and the current user's settings; other users keep theirs. After a second question, it removes the packages it installed, hardware support included; packages you had before, or that other software needs, stay. Restart to finish. |

## Supported systems

| Debian | PCs | Display | Panel and file manager | Default theme |
|--------|-----|---------|------------------------|---------------|
| 10 (buster) | 32-bit, 64-bit | X | Raspberry Pi OS 10 builds | PiXflat |
| 11 (bullseye) | 32-bit, 64-bit | X | Raspberry Pi OS 11 builds | PiXflat |
| 12 (bookworm) | 32-bit, 64-bit | X | Raspberry Pi OS 12 builds | PiXflat |
| 13 (trixie) | 64-bit | X or Wayland | Raspberry Pi OS 13 | PiXtrix |
| testing, unstable | 64-bit | X or Wayland | Raspberry Pi OS 13 | PiXtrix |

Derivatives of these releases also work.

**Network icon.** On Debian 12 and 13, Raspberry Pi's network item is used
when NetworkManager manages the network and Raspberry Pi OS has a matching
build of `libnma`. Otherwise (always on Debian 10 and 11, usually on testing
and unstable), Debian's network icon (nm-applet) appears in the tray.

### X or Wayland

The session uses **Wayland (labwc)** when all of the following hold, and
**X (Openbox)** otherwise. The plan states the reason.

| Condition | Needed for Wayland |
|-----------|--------------------|
| Debian | 13 or later |
| System | 64-bit, with at least 2 GB of memory |
| Processor | SSE4.2 |
| Graphics | Kernel modesetting and 3D acceleration with `i915`, `xe`, `amdgpu`, `virtio_gpu` or `vmwgfx` |

NVIDIA graphics (the proprietary driver or nouveau) and older AMD graphics
(`radeon`) always use X.

### Other desktops

Other desktops are not changed. They can use the parts of the look that are
ordinary themes, selected in their own appearance settings.

| Part of the look | Raspberry Pi Desktop | Debian's LXDE | Xfce, MATE, Cinnamon | GNOME | KDE Plasma, LXQt |
|------------------|----------------------|---------------|----------------------|-------|------------------|
| GTK theme | Yes | Selectable | Selectable (GTK 2 and 3) | GTK 3 only, in GNOME Tweaks; GTK 4 keeps Adwaita | GTK programs only; Qt programs keep theirs |
| Icons, cursor, fonts | Yes | Selectable | Selectable | Selectable, in GNOME Tweaks | Selectable |
| Wallpapers (`/usr/share/rpd-wallpaper`) | Yes | Selectable | Selectable | Selectable | Selectable |
| Window frames | Openbox on X, labwc on Wayland | Selectable in Openbox's settings | No | No | No |
| Panel, menu, file manager | Raspberry Pi's | Raspberry Pi OS builds on Debian 10 to 12 | No | No | No |
| Keys, screen lock, power, `rpios-look-set` | Yes | No | No | No | No |
| Login screen style | With LightDM, for every desktop | Same | Same | Not with GDM | Not with SDDM |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| The look is missing after login | Select *Raspberry Pi Desktop* in the login screen's session menu. |
| The session runs on X, not Wayland | The plan gives the reason; see [X or Wayland](#x-or-wayland). |
| The login screen is not styled | The style needs LightDM: `sudo apt install lightdm lightdm-gtk-greeter && sudo dpkg-reconfigure lightdm`, then run the script again. |
| dpkg was interrupted | Run `sudo dpkg --configure -a` and `sudo apt-get -f install`, then run the script again. |
| 404 Not Found | Your Debian release has moved to archive.debian.org. Update `/etc/apt/sources.list` as [Debian describes](https://www.debian.org/distrib/archive), run `sudo apt update`, then run the script again. |
| Something looks incomplete | Run the same command again; every step is safe to repeat. |

Each run writes a log to your home folder, for example
`~/rpios-look-install-<date>-<time>.log`. The ten newest logs of each mode are
kept. `-v` adds detail.

## How it works

### Themes

All five themes are installed, each with the icons, cursor, font, window
frames and wallpaper that Raspberry Pi OS gives it. Where Raspberry Pi OS
shows its logo (the menu button and the login screen's user picture), every
theme shows the Debian logo: a white swirl on a red circle.

| Theme | Style | Font | Wallpaper |
|-------|-------|------|-----------|
| `pixflat` | Light; Raspberry Pi OS 10 to 12 | Piboto Light | `temple.jpg` (Debian 10), `clouds.jpg` (11), `fisherman.jpg` (12 and later) |
| `pixnoir` | Dark; Raspberry Pi OS 12 | Piboto Light | As `pixflat` |
| `pixtrix` | Light; Raspberry Pi OS 13 | Nunito Sans Light | `sunrise.jpg` |
| `pixonyx` | Dark; Raspberry Pi OS 13 | Nunito Sans Light | `sunrise.jpg` |
| `pix` | Legacy; Raspbian 9 | Piboto Light | `road.jpg` |

Qt applications follow the theme through the GTK platform themes.

### Keys and buttons

As on Raspberry Pi OS:

| Key | Action |
|-----|--------|
| **Super**, **Ctrl+Esc** | Main menu |
| **Alt+F2** | Run a command |
| **Ctrl+Alt+T** | Terminal |
| **Ctrl+Shift+Esc** | Task manager |
| **Ctrl+Alt+Delete**, **Ctrl+Alt+End** | Shutdown dialog |
| **Print** | Screenshot: `scrot` on X (where installed), Raspberry Pi's screenshot tool on Wayland |
| **Ctrl+Alt+Left/Right** | Move the window to the left or right half of the screen |
| **Ctrl+Alt+Up/Down** | Maximize, restore |
| **Ctrl+Alt+D** | Show the desktop |
| **Alt+F11** | Full screen |
| **Ctrl+Alt+B** | Bluetooth menu |
| **Ctrl+Alt+W** | Network menu (with Raspberry Pi's network item) |
| **Ctrl+Alt+M** | Magnifier, once added to the panel |
| Volume keys | Volume, through the panel |

Added for PCs and laptops:

| Key or button | Action |
|---------------|--------|
| **Ctrl+Alt+L**, the lock key (Fn+F3 on ThinkPads) | Lock the screen |
| The wireless key (Fn+F5 on ThinkPads) | Turn Wi-Fi and Bluetooth off or on together. Where the laptop switches Wi-Fi itself, Bluetooth follows. |
| The power button | Open the shutdown dialog; press again while it is open to shut down. |

Some older laptops do not report a short press of the power button; on
those, only a long press (forced power-off) works. Outside the session, the
power button and the lid follow Debian's settings.

### Compared with Raspberry Pi OS

**From Raspberry Pi OS:**

| Part | Raspberry Pi OS packages |
|------|--------------------------|
| Themes, icons, cursors, fonts, wallpapers | `pixflat-theme`, `pixtrix-theme`, `pix-theme`, `pixflat-icons`, `pixtrix-icons`, `rpd-icons`, `fonts-piboto`, `fonts-nunito-sans`, `rpd-wallpaper*` |
| Panel | Debian 10 to 12: Raspberry Pi OS builds of `lxpanel` with `lxplug-*`. Debian 13: `lxpanel-pi` with `lpplug-*` on X, `wf-panel-pi` with `wfplug-*` on Wayland |
| File manager and desktop | Debian 10 to 12: Raspberry Pi OS builds of `pcmanfm` and `libfm`. Debian 13: `pcmanfm-pi` |
| Window manager on X | Raspberry Pi OS build of `openbox` (keeps corners rounded while moving or resizing) |
| Dialogs and settings | `pishutdown`, `gui-runcmd`, `pipanel`, `rpcc` |
| Magnifier | `mage` (Debian 10, 11), `mage-rpi` (Debian 12, 13) |
| Panel layout, menu, desktop and window settings | Read from `raspberrypi-ui-mods` (Debian 10 to 12) and `rpd-*` (Debian 13); not installed |

**From Debian:** the system services (BlueZ, NetworkManager, PipeWire or
PulseAudio, udisks, systemd-logind), the applications, labwc, lxsession,
LightDM with Debian's greeter, the screen locker and the authentication
agent. Raspberry Pi OS uses the same Debian programs for these.

**Differences:**

| Item | rpios-look | Raspberry Pi OS |
|------|------------|-----------------|
| Keyboard shortcuts | Raspberry Pi OS's for each release; Ctrl+Alt+Space (screen reader installer) is omitted | Full set |
| Resizing a window on X | Contents redraw while dragging | Blank until the mouse is released |
| Menu button and login logo | Debian logo | Raspberry Pi logo |
| Login screen | Debian's LightDM greeter in Raspberry Pi OS's style, with user list and session menu | Raspberry Pi's greeter |
| File manager on Debian 13 | Raspberry Pi's, alongside Debian's | Raspberry Pi's only |
| Network icon | See [Supported systems](#supported-systems) | Raspberry Pi's |
| Magnifier | Installed; add it to the panel to use it | Not installed by default |
| Menu on Debian 10 to 12 | An **Other** category with Debian's legacy menu entries, where Debian's `menu` package is installed | No such entries |
| Shutdown dialog | No "Press Ctrl-Alt-L to lock screen" line (Ctrl+Alt+L still locks) | Shows the line |
| raspi-config, updater, Raspberry Pi Connect, on-screen keyboard, panel power item | Omitted: they need Raspberry Pi hardware or system tools | Included |
| Screen lock, suspend, lid, `rpios-look-power` | Included | Blanking only |
| Menu categories | For every installed application | For the applications it ships |
| `rpios-look-set` | Included | Not available |

Raspberry Pi's programs are used unchanged, with one fix:

| Bug | Releases | Here |
|-----|----------|------|
| The PIN field of the Bluetooth pairing dialog does not accept typing (Bluetooth 2.0 devices) | All | **Fixed**: the field takes keyboard focus |
| Pairing started from this computer stops after 25 seconds | All | Unchanged; start pairing from the other device |
| Ejecting a partition of an internal disk reports "Failed to eject", although it is unmounted | Debian 10 to 12 | Unchanged |

### What changes on the computer

| Area | Changed | Not changed |
|------|---------|-------------|
| Raspberry Pi Desktop | New session | — |
| Debian's LXDE | Uses Raspberry Pi OS's Openbox, and on Debian 10 to 12 its panel and file manager | Its settings, autostart, screen lock and power |
| Other desktops | Raspberry Pi themes become selectable | Their settings, panels, screen lock and power manager |
| Login screen | LightDM's greeter gets Raspberry Pi OS's style | GDM, SDDM and other login managers |
| Packages | Raspberry Pi OS packages listed above; Debian packages the session needs, including hardware support (X server, network, Bluetooth, sound) where missing | Packages already installed |
| System files | Raspberry Pi's APT source, pinned to the look's packages, with an APT check (online installations only); a polkit rule for suspend | Everything else |

The polkit rule lets a local session that is not in the foreground (for
example, behind a locked screen) suspend the computer without a password.
polkit cannot distinguish a locked session from one on another virtual
console. The rule covers suspend only, never remote logins.

### Keeping Debian safe

The script follows Debian's
[DontBreakDebian](https://wiki.debian.org/DontBreakDebian) guidance:

- No Debian package is replaced, except Openbox (and, on Debian 10 to 12,
  the panel and file manager) by Raspberry Pi OS's builds.
- Packages that would replace, break or conflict with Debian packages are
  refused, now and on later APT updates.
- Debian packages come only from your own APT sources.
- Archives are verified against their signing keys, and every package
  against its SHA256 checksum.
- The plan lists every package before anything changes.
- Changed settings are backed up; `--uninstall` restores them.

## Credits and licence

The themes, icons, fonts, wallpapers and desktop settings are the work of
[Raspberry Pi Ltd](https://www.raspberrypi.com/) and the Raspberry Pi desktop
team. This project installs their official packages on Debian. All artwork
keeps its own licence (see `/usr/share/doc/<package>/copyright`).

The script is released under the MIT licence; see [LICENSE](LICENSE).
