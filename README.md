# rpios-look

rpios-look gives Debian the official Raspberry Pi OS desktop on 32-bit
(`i386`) and 64-bit (`amd64`) PCs. It installs Raspberry Pi's own themes,
icons, cursors, fonts, wallpapers, panel, file manager and login screen
style as a separate session, **Raspberry Pi Desktop**. Debian and your other
sessions stay as they are.

![The Raspberry Pi Desktop session on Debian 13, with its menu open](screenshot/scr1.png)
![The Raspberry Pi Desktop session on Wayland, Debian 13](screenshot/scr2.png)
![The login screen](screenshot/scr3.png)
![Debian 12 on a 32-bit PC](screenshot/scr4.png)

## Contents

1. [Support](#support)
2. [Installation](#installation)
3. [Script options](#script-options)
4. [Themes](#themes)
5. [Tweaks for each user](#tweaks-for-each-user)
6. [Keys and buttons](#keys-and-buttons)
7. [Compared with Raspberry Pi OS](#compared-with-raspberry-pi-os)
8. [What changes on the computer](#what-changes-on-the-computer)
9. [Updating, upgrading and uninstalling](#updating-upgrading-and-uninstalling)
10. [Troubleshooting](#troubleshooting)
11. [Credits and licence](#credits-and-licence)

## Support

| Debian | PCs | Session | Panel and file manager | Network icon | Default theme |
|--------|-----|---------|------------------------|--------------|---------------|
| 10 (buster) | 32-bit, 64-bit | X | Raspberry Pi OS 10's builds | Debian's, in the tray | PiXflat |
| 11 (bullseye) | 32-bit, 64-bit | X | Raspberry Pi OS 11's builds | Debian's, in the tray | PiXflat |
| 12 (bookworm) | 32-bit, 64-bit | X | Raspberry Pi OS 12's builds | Raspberry Pi's | PiXflat |
| 13 (trixie) | 64-bit | X or Wayland | Raspberry Pi OS 13's | Raspberry Pi's | PiXtrix |
| testing, unstable | 64-bit | X or Wayland | Raspberry Pi OS 13's | Debian's, in the tray | PiXtrix |

Derivatives of these releases work too.

**Requirements:** bash 4.4 or later; a normal user account with sudo rights
(do not run the script as root); internet access, except for an
[offline installation](#offline-installation); about 80 MB of disk space.

### X or Wayland

As on Raspberry Pi OS, the session uses **Wayland (labwc)** when all of
these hold, and **X (Openbox)** otherwise. The plan states the reason.

| Condition | Needed for Wayland |
|-----------|--------------------|
| Debian | 13 or later |
| System | 64-bit, with at least 2 GB of memory |
| Processor | SSE4.2 |
| Graphics | Kernel modesetting and 3D acceleration with `i915`, `xe`, `amdgpu`, `virtio_gpu` or `vmwgfx` |

NVIDIA graphics use X. Wayland with NVIDIA's own driver needs kernel
modesetting, which Debian leaves off:

```bash
printf 'options nvidia-drm modeset=1\noptions nvidia-current-drm modeset=1\n' \
  | sudo tee /etc/modprobe.d/nvidia-modeset.conf
sudo update-initramfs -u && sudo reboot
```

Then run the script again.

## Installation

1. Download `rpios-look.sh`, or clone this repository.
2. In a terminal, in the script's folder, run `bash rpios-look.sh`.
3. Enter your password, review the plan (every package with its version and
   origin) and answer `y`.
4. Log out, choose **Raspberry Pi Desktop** on the login screen and log in.

Running the script again is safe. Run from a terminal inside the session, it
also refreshes the running desktop.

### Offline installation

1. On a computer with internet access, run `bash rpios-look.sh --download`.
   It builds `packages/` next to the script.
2. Copy `rpios-look.sh` and `packages/` to the offline computer.
3. There, run `bash rpios-look.sh --offline`.

| | Offline installation |
|-|----------------------|
| Releases | Debian 10 to 12 on `amd64` and `i386`; Debian 13 on `amd64` |
| Not covered | Debian testing and unstable, which change daily |
| Result | The same as an online installation, without Raspberry Pi's APT source |
| Integrity | Every file is checked against `packages/SHA256SUMS` first |
| Uninstall | Works offline too, with `packages/` next to the script |

## Script options

```bash
bash rpios-look.sh [MODE] [OPTION]...
```

| Mode | Action |
|------|--------|
| *(none)* | Install, or update an existing installation |
| `--refresh` | List available updates, then ask to apply them |
| `--uninstall` | Remove everything the script added and give Debian back as it was |
| `--prepare-upgrade` | Prepare for a Debian release upgrade |
| `--download` | Build or refresh `packages/` for an offline installation |
| `--offline` | Install from `packages/`, without a network |
| `--help` | Show the help |

| Option | Description |
|--------|-------------|
| `--size SIZE` | Raspberry Pi OS's size presets for fonts, icons, panel and cursor: `small`, `medium` (default), `large` or `larger`. It is saved and reused by later runs. |
| `-v`, `--verbose` | Also print the commands run as root, the files downloaded and other details |
| `-V`, `--version` | Print the version |

The look itself has no options. The script always installs every theme, the
standard wallpapers, Raspberry Pi's Openbox, panel and file manager where they work
on your release, the login screen style where LightDM is or can be the login
manager, and the GTK platform themes for Qt, so that Qt applications follow
the theme.

## Themes

All five themes are installed, each with the icons, cursor, font, window
frames and wallpaper that Raspberry Pi OS gives it.

| Theme | Style | Font | Wallpaper |
|-------|-------|------|-----------|
| `pixflat` | Light; Raspberry Pi OS 10 to 12 | Piboto Light | The release's own (below) |
| `pixnoir` | Dark; Raspberry Pi OS 12 | Piboto Light | The release's own (below) |
| `pixtrix` | Light; Raspberry Pi OS 13 | Nunito Sans Light | `sunrise.jpg` |
| `pixonyx` | Dark; Raspberry Pi OS 13 | Nunito Sans Light | `sunrise.jpg` |
| `pix` | Legacy; Raspbian 9 | Piboto Light | `road.jpg` |

| Debian | Session theme | PiXflat wallpaper |
|--------|---------------|-------------------|
| 10 | PiXflat | `temple.jpg` |
| 11 | PiXflat | `clouds.jpg` |
| 12 | PiXflat | `fisherman.jpg` |
| 13 and later | PiXtrix | `fisherman.jpg` |

## Tweaks for each user

Two commands change the session for the current user only. They need no
sudo, apply at once and are kept for later logins.

### Look: `rpios-look-set`

| Option | Action |
|--------|--------|
| `--theme NAME` | Use `pixflat`, `pixnoir`, `pixtrix`, `pixonyx` or `pix` |
| `--list` | Show the installed themes |
| `--show` | Show the current look |
| `--reset` | Return to the session's look, as installed |

Raspberry Pi's Appearance Settings or Control Centre works as well, where
installed; otherwise **Customize Look and Feel**.

### Screen lock and power: `rpios-look-power`

The session blanks the screen, switches the monitor off, locks the screen
and puts the computer to sleep when it is not in use, with Debian's own
tools: light-locker (the login screen locks) on X, swayidle and swaylock on
Wayland, and systemd-logind. Other screen lockers and power managers do not
start in this session; Debian's other sessions keep theirs. Times are
minutes without use; `0` is never.

| Option | Action | Default |
|--------|--------|---------|
| `--lock on\|off` | Lock the screen after `--lock-after`, on waking and with the lock keys | `on` |
| `--lock-after MIN` | Lock after MIN minutes | `10` |
| `--blank MIN` | Blank the screen after MIN minutes | `10` |
| `--monitor-off MIN` | Switch the monitor off after MIN minutes | `10` |
| `--sleep-battery MIN` | Sleep after MIN minutes on battery | `30` |
| `--sleep-ac MIN` | Sleep after MIN minutes on mains power | `0` |
| `--lid sleep\|lock\|nothing` | What closing the lid does while you are logged in | `sleep` |
| `--show` | Show your settings | |
| `--reset` | Return to the defaults | |

For example: `rpios-look-power --lock-after 5 --sleep-battery 15`.

On X, the screen locks with LightDM only; with GDM, SDDM or another login
manager, the session blanks and sleeps but does not lock.

## Keys and buttons

In the Raspberry Pi Desktop session, as on Raspberry Pi OS:

| Key | Action |
|-----|--------|
| **Super**, **Ctrl+Esc** | Main menu |
| **Alt+F2** | Run a command |
| **Ctrl+Alt+T** | Terminal |
| **Ctrl+Shift+Esc** | Task manager |
| **Ctrl+Alt+Delete**, **Ctrl+Alt+End** | Shutdown dialog |
| **Print** | Screenshot: `scrot` on X where installed, Raspberry Pi's screenshot tool on Wayland |
| **Ctrl+Alt+Left/Right** | Window to the left or right half of the screen |
| **Ctrl+Alt+Up/Down** | Maximise, restore |
| **Ctrl+Alt+D** | Show the desktop |
| **Alt+F11** | Full screen |
| **Ctrl+Alt+B** | Bluetooth menu (Raspberry Pi's panel) |
| **Ctrl+Alt+W** | Network menu (Raspberry Pi's network item) |
| **Ctrl+Alt+M** | Magnifier, once added to the panel |
| Volume keys | Volume, through the panel |

Added for PCs and laptops:

| Key or button | Action |
|---------------|--------|
| **Ctrl+Alt+L**, the lock key (Fn+F3 on ThinkPads) | Lock the screen |
| The wireless key (Fn+F5 on ThinkPads) | Wi-Fi and Bluetooth off and on together; where the laptop switches Wi-Fi itself, Bluetooth follows it |
| The power button | Shutdown dialog; pressed again while it is open, shut down |

Some old laptops do not report a short press of the power button to the
system; there, only holding it (a forced power-off) works. Outside the
session, the power button and the lid follow Debian's settings.

## Compared with Raspberry Pi OS

### From Raspberry Pi OS

| Part | Raspberry Pi OS packages |
|------|--------------------------|
| Themes, icons, cursors, fonts, wallpapers | `pixflat-theme`, `pixtrix-theme`, `pix-theme`, `pixflat-icons`, `pixtrix-icons`, `rpd-icons`, `fonts-piboto`, `fonts-nunito-sans`, `rpd-wallpaper*` |
| Panel and its items | Debian 10 to 12: Raspberry Pi OS's builds of `lxpanel` with `lxplug-*`. Debian 13: `lxpanel-pi` with `lpplug-*` on X, `wf-panel-pi` with `wfplug-*` on Wayland |
| File manager and desktop | Debian 10 to 12: Raspberry Pi OS's builds of `pcmanfm` and `libfm`. Debian 13: `pcmanfm-pi` |
| Window manager on X | Raspberry Pi OS's build of `openbox`, which keeps the corners rounded while a window is moved or resized |
| Dialogs and settings | `pishutdown`, `gui-runcmd`, `pipanel`, `rpcc` |
| Magnifier | `mage-rpi` (Debian 12 and 13), `mage` (Debian 10 and 11) |
| Panel layout, menu, desktop and window settings | Read from `raspberrypi-ui-mods` (Debian 10 to 12) and `rpd-*` (Debian 13), not installed |

### From Debian

The system and its services (BlueZ, NetworkManager, PipeWire or PulseAudio,
udisks, systemd-logind), the applications, the window manager on Wayland
(labwc), the session manager (lxsession), the login screen (LightDM with
Debian's greeter), the screen locker and the authentication agent.
Raspberry Pi OS uses the same Debian programs for these.

### Side by side

| Item | Here | Raspberry Pi OS |
|------|------|-----------------|
| Themes, icons, cursors, fonts, wallpapers | Same | |
| Panel: items, order, spacing, size, menus | Same | |
| Main menu, file manager, desktop | Same | |
| Keyboard shortcuts | Raspberry Pi OS's own for each release; Ctrl+Alt+T opens Debian's terminal on Wayland, and Ctrl+Alt+Space (screen reader installer) is left out | |
| Window corners | Same: rounded per theme on X, also while a window is moved or resized; square on Wayland | |
| Resizing a window on X | Its contents are redrawn while dragging | Blank and unshaped until the mouse is released |
| Menu button and login logo | Debian logo; Debian's white logo on the dark themes, from the next login | Raspberry Pi logo |
| Login screen | Debian's LightDM greeter in Raspberry Pi OS's style, with user list and session chooser | Raspberry Pi's greeter |
| File manager on Debian 13 | Raspberry Pi's, beside Debian's | Raspberry Pi's only |
| Network icon on Debian 10, 11, testing, unstable | Debian's, in the tray | Raspberry Pi's |
| Magnifier | Installed, not on the panel until added | Hidden until installed |
| Menu on Debian 10 to 12 | An **Other** category with Debian's old menu entries (Bash, Dash, screensaver commands), where Debian's `menu` package is installed, as in Debian's LXDE | No such entries |
| Shutdown dialog | No "Press Ctrl-Alt-L to lock screen" line: the dialog looks for Raspberry Pi's own lock binding (Ctrl+Alt+L still locks) | Shows the line |
| raspi-config, updater, Raspberry Pi Connect, on-screen keyboard, the panel's power item | Left out: they need Raspberry Pi hardware or system tools | Included |
| Screen lock, sleep, lid, `rpios-look-power` | Included | Blanking only |
| One menu category per application | For every installed application | For the applications it ships |
| `rpios-look-set` | Included | — |

### Raspberry Pi OS bugs

Raspberry Pi's programs are used as Raspberry Pi ships them, with one fix:

| Bug | Releases | Here |
|-----|----------|------|
| The PIN field of the Bluetooth pairing dialog cannot be typed in (older Bluetooth 2.0 devices) | All | **Fixed**: the field takes the keyboard focus; nothing else changes |
| Pairing started from this computer gives up after 25 seconds | All | As on Raspberry Pi OS; start pairing from the other device |
| Ejecting a partition of an internal disk reports "Failed to eject", although it is unmounted | Debian 10 to 12 | As on Raspberry Pi OS 12 |

## What changes on the computer

| Area | Changed | Not changed |
|------|---------|-------------|
| Raspberry Pi Desktop (new session) | Everything in this README | — |
| Debian's LXDE | It uses Raspberry Pi OS's build of Openbox, and on Debian 10 to 12 its builds of the panel and file manager | Its settings, autostart, screen lock and power |
| GNOME, KDE Plasma, Xfce, MATE, Cinnamon, LXQt | The Raspberry Pi themes can be chosen in their appearance settings | Their settings, panels, screen lock and power manager |
| Login screen | LightDM's greeter gets Raspberry Pi OS's style | GDM, SDDM and other login managers |
| System files | Raspberry Pi's APT source, pinned to the look's packages, with a check (online installations only); a polkit rule for sleep | Everything else |

The polkit rule lets a local session that is not in front, such as one with
a locked screen, put the computer to sleep without a password. polkit cannot
tell a locked session from one switched away from on another console. It
covers sleep only, never remote logins.

### Keeping Debian safe

The script follows Debian's
[DontBreakDebian](https://wiki.debian.org/DontBreakDebian) guidance:

- No Debian package is replaced, except Openbox, and the panel and file
  manager on Debian 10 to 12, by Raspberry Pi OS's builds of them.
- Packages that would replace, break or conflict with Debian packages are
  refused; APT's check refuses them on later updates too.
- Debian packages come only from your own APT sources.
- Archives are verified against their signing keys, and every package
  against its SHA256.
- The plan lists every package before anything changes.
- Changed settings are backed up, and `--uninstall` gives Debian back as it
  was.

## Updating, upgrading and uninstalling

| Task | How |
|------|-----|
| Update | `sudo apt update && sudo apt full-upgrade` updates the look's Raspberry Pi packages with Debian. `bash rpios-look.sh --refresh` updates everything, including packages the script adapts, and lists them first. |
| Upgrade Debian | Run `bash rpios-look.sh --prepare-upgrade` (it removes the packages built for this release and takes Raspberry Pi's archive out of APT), upgrade Debian and reboot, then run `bash rpios-look.sh` again. |
| Uninstall | Run `bash rpios-look.sh --uninstall`. It lists what it removes and asks first, puts Debian's Openbox, panel and file manager back, restores the settings it changed and, after a second question, removes the packages it installed. Packages you had before stay. Restart to finish. |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| The look is missing after login | Choose *Raspberry Pi Desktop* in the login screen's session menu. |
| The session runs on X, not Wayland | The plan gives the reason; see [X or Wayland](#x-or-wayland). |
| dpkg was interrupted | Run `sudo dpkg --configure -a` and `sudo apt-get -f install`, then the script again. |
| 404 Not Found | Your Debian release has moved to archive.debian.org. Update `/etc/apt/sources.list` as [Debian describes](https://www.debian.org/distrib/archive), run `sudo apt update`, then the script again. |
| Something looks incomplete | Run the same command again; every step is safe to repeat. |

Each run writes a log to your home folder, such as
`~/rpios-look-install-<date>-<time>.log`; `-v` adds details.

## Credits and licence

The themes, icons, fonts, wallpapers and desktop settings are the work of
[Raspberry Pi Ltd](https://www.raspberrypi.com/) and the Raspberry Pi desktop
team. This project installs their official packages on Debian. All artwork
keeps its own licence (see `/usr/share/doc/<package>/copyright`).

The script is released under the MIT licence; see [LICENSE](LICENSE).
