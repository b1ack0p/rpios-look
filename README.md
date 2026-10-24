# rpios-look

Makes Debian look like Raspberry Pi OS, without breaking Debian.

It installs the official Raspberry Pi OS themes, icons, cursors, fonts,
wallpapers, panel, file manager and login screen style, and applies Raspberry
Pi OS's desktop settings. Everything is added as a separate session on the
login screen, **Raspberry Pi Desktop**. Your settings in Debian's own sessions
are not changed; on Debian 10 to 12 they use Raspberry Pi OS's panel and file
manager too, unless `--no-pi-apps` is given (see [Panel](#panel)).

![The Raspberry Pi Desktop session on Debian 13, with its menu open](screenshot/scr1.png)
![The Raspberry Pi Desktop session on Wayland, Debian 13](screenshot/scr2.png)
![The login screen](screenshot/scr3.png)
![Debian 12 on a 32-bit PC, with Debian's own panel (--no-pi-apps)](screenshot/scr4.png)

## Contents

1. [Overview](#overview)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Commands](#commands)
5. [Themes](#themes)
6. [Changing the look](#changing-the-look)
7. [X or Wayland](#x-or-wayland)
8. [Panel](#panel)
9. [Install options](#install-options)
10. [What is installed](#what-is-installed)
11. [The session](#the-session)
12. [Updating](#updating)
13. [Upgrading Debian](#upgrading-debian)
14. [Uninstalling](#uninstalling)
15. [Offline installation](#offline-installation)
16. [Troubleshooting](#troubleshooting)
17. [How it works](#how-it-works)
18. [Keeping Debian safe](#keeping-debian-safe)
19. [Credits and licence](#credits-and-licence)

## Overview

- **Supported systems:** Debian 10 to 13 and later, including testing,
  unstable and derivatives, on amd64, i386, arm64 and armhf. Other
  architectures get the themes, icons, fonts and wallpapers only.
- **Themes:** PiXflat, PiXnoir, PiXtrix, PiXonyx and PiX, all installed.
- **Sessions:** *Raspberry Pi Desktop* on X, and on Wayland where the
  computer suits it.
- **Panel and file manager:** Raspberry Pi OS's own, in its layout for
  your Debian release: on Debian 13 and later beside Debian's, on Debian 10
  to 12 in place of Debian's (see [Panel](#panel)).
- **Login screen:** Raspberry Pi OS's style, with Debian's login artwork.
  LightDM is installed where no other login manager is used.

Differences from Raspberry Pi OS:

- The **Debian logo** replaces the Raspberry Pi logo on the menu button and
  the login screen. No program shows the Raspberry Pi logo: the Shutdown
  dialog shows its Shutdown icon on every Debian release, as it does on
  Raspberry Pi OS 13.
- Raspberry Pi's system tools are left out: raspi-config, the updater, and
  the panel's power and network plugins. The network icon comes from
  Debian's `nm-applet`.
- The login screen is Debian's LightDM greeter in Raspberry Pi OS's style,
  with a session chooser. `--pi-greeter` uses Raspberry Pi's greeter instead.

## Requirements

- Debian 10 (buster) or later, or a derivative.
- A normal user account with sudo rights. Do not run the script as root.
- Internet access, except for an [offline installation](#offline-installation).
- About 80 MB of disk space (about 200 MB more for the 4K wallpapers).

## Installation

1. Download `rpios-look.sh`, or clone this repository.
2. In a terminal, in the script's folder, run:

   ```bash
   bash rpios-look.sh
   ```

3. Review the detected computer and the plan, answer `y`, and enter your
   password when asked.
4. When the packages are installed, choose a theme. Press Enter to keep the
   default.
5. Log out. **Raspberry Pi Desktop** is selected on the login screen. Log in.

Running the script again is safe. Without a terminal, or with `-y`, every
question takes its default answer.

## Commands

| Command | Action |
|---------|--------|
| `bash rpios-look.sh` | Install or update |
| `bash rpios-look.sh --refresh` | List available updates, then ask to apply them |
| `bash rpios-look.sh --uninstall` | Remove the look |
| `bash rpios-look.sh --prepare-upgrade` | Prepare for a Debian release upgrade |
| `bash rpios-look.sh --download` | Build `packages/` for an offline installation |
| `bash rpios-look.sh --offline` | Install from `packages/` |
| `bash rpios-look.sh --help` | Show all commands and options |

## Themes

| Name | Style | Font | Wallpaper |
|------|-------|------|-----------|
| `pixflat` | Light, Raspberry Pi OS Buster to Bookworm (default on Debian 10 to 12) | Piboto Light | temple on Debian 10, clouds on 11, fisherman on 12 and later |
| `pixnoir` | Dark, Raspberry Pi OS Bookworm | Piboto Light | as `pixflat` |
| `pixtrix` | Light, Raspberry Pi OS Trixie (default on Debian 13 and later) | Nunito Sans Light | sunrise |
| `pixonyx` | Dark, Raspberry Pi OS Trixie | Nunito Sans Light | sunrise |
| `pix` | Legacy, Raspbian Stretch | Piboto Light | road |

Each wallpaper is the one Raspberry Pi OS uses with that theme in that release.

The installer asks for the theme at the end. To change the default theme for
all users later, run the installer with `--theme`:

```bash
bash rpios-look.sh --theme pixonyx
bash rpios-look.sh --theme auto      # the default for your Debian release
```

## Changing the look

The look is changed for the current user only. Changes apply at once and
are kept for later logins.

| Session | In the menu | Themes |
|---------|-------------|--------|
| X | **Preferences > Customize Look and Feel** | All installed themes |
| Wayland | **Preferences > Control Centre** | Light (PiXtrix) or Dark (PiXonyx), as on Raspberry Pi OS 13 |
| Both | `rpios-look-set` (command line) | All installed themes |

### Control Centre (Wayland)

The Control Centre is Raspberry Pi OS 13's own Appearance Settings
(`pipanel`), with **Defaults**, **Desktop**, **Taskbar** and **Theme** pages.
It is installed with the Wayland session.

### rpios-look-set

`rpios-look-set` changes the look from the command line. It needs no sudo.

#### Options

| Option | Values |
|--------|--------|
| `--theme NAME` | `pixflat`, `pixnoir`, `pixtrix`, `pixonyx`, `pix`, or any GTK theme. Also sets the theme's icons, cursor, window frames and font. |
| `--light`, `--dark` | The light or dark version of the current theme. Icons and font are kept. |
| `--icons NAME` | `pixflat`, `pixtrix`, `pix`, or any icon theme. |
| `--window NAME` | Window frames: `pixflat`, `pixnoir`, `pixtrix`, `pixonyx`, `pix`, or any Openbox theme. `theme` makes them follow the theme again. |
| `--font NAME` | `nunito`, `piboto`, `piboto-condensed`, `sans`, `serif`, `mono`, or any installed font family. |
| `--cursor NAME`, `--cursor-size N` | Cursor theme and size in pixels. |
| `--accent COLOUR` | Highlight colour, for example `'#d6363c'`, or `default`. |
| `--desktop-color COLOUR`, `--desktop-text COLOUR` | Desktop background and icon text colours. |
| `--wallpaper W`, `--wallpaper-mode M` | A wallpaper name or path, or `none`; and `crop`, `fit`, `stretch`, `center`, `tile` or `color`. |
| `--list` | Show the installed themes, icons, window frames and fonts. |
| `--show` | Show the current look. |
| `--reset` | Return to the session's default look. |

The font's style and size are set automatically to suit the theme, as in
Raspberry Pi OS (for example, Nunito Sans Light 12). Window titles use the
same font.

#### Examples

```bash
rpios-look-set --theme pixtrix
rpios-look-set --dark
rpios-look-set --theme pixflat --icons pixtrix --window pixnoir
rpios-look-set --font piboto
rpios-look-set --accent '#2e7d32' --cursor-size 32
rpios-look-set --reset
```

These settings apply to both sessions, X and Wayland. As on Raspberry Pi OS,
windows have rounded corners on X and square corners on Wayland.

## X or Wayland

### How it is chosen

Before installing, the script detects the computer: model, processor,
memory, graphics and driver, 3D acceleration, virtual machine, kernel,
Debian release, installed desktops and login manager. Following Raspberry
Pi OS, it selects:

| Display system | When |
|----------------|------|
| **Wayland (labwc)** | Debian 13 or later, and either a Raspberry Pi (any model, as on Raspberry Pi OS) or a computer with at least 2 GB of memory, a 64-bit system, and 3D graphics with a supported driver: Intel (`i915`, `xe`), AMD (`amdgpu`), ARM boards (`panfrost`, `lima`, `etnaviv` and others), virtual machines with 3D (`virtio_gpu`, `vmwgfx`). |
| **X (Openbox)** | All other cases: Debian 10 to 12, less than 2 GB of memory, 32-bit systems, PC processors without SSE4.2, graphics without 3D acceleration or kernel modesetting, older AMD graphics (`radeon`), NVIDIA graphics. |

Only the Wayland packages are optional. The X server is always installed,
because the login screen runs on it, and the X session is always available.

### Changing it later

Run the installer with one of these options. The choice is remembered, and
your next login uses it.

```bash
bash rpios-look.sh --wayland        # use Wayland
bash rpios-look.sh --no-wayland     # use X only
bash rpios-look.sh --auto           # let the script decide again
```

To switch for one login only, choose the session on the login screen.

### NVIDIA graphics

The X session is used by default. Wayland with NVIDIA's own driver needs
kernel modesetting, which Debian leaves off. If it is off, the script keeps
X even with `--wayland`. To enable it:

```bash
printf 'options nvidia-drm modeset=1\noptions nvidia-current-drm modeset=1\n' \
  | sudo tee /etc/modprobe.d/nvidia-modeset.conf
sudo update-initramfs -u
sudo reboot
```

Then run `bash rpios-look.sh --wayland`. Wayland on NVIDIA can show minor
display glitches; `--no-wayland` returns to X.

## Panel

### Launchers

As on Raspberry Pi OS, the panel shows a generic **Web Browser** launcher
with the standard browser icon. It opens Debian's default browser
(`x-www-browser`), which is also the session's default for web links. To
change the default browser:

```bash
sudo update-alternatives --config x-www-browser
```

### Settings and applets

Right-click the panel to change its settings and applets:

- **On X:** **Panel Settings** and **Add / Remove Panel Items**.
- **On Wayland:** the panel's settings open in the **Control Centre**.

### Layout

The panel is Raspberry Pi OS's own layout for your Debian release (Raspberry
Pi OS 10 to 13), with its spaces and separators: menu, launchers, taskbar,
eject, Bluetooth, network, volume, clock, battery and magnifier. Differences:

- The network icon is `nm-applet`'s, in the notification area, which takes
  the network plugin's place; other programs' tray icons appear there too.
- A **keyboard layout** applet sits before the clock. It shows the current
  layout by its short name (`FR`, `US`, ...); right-click it to add layouts
  and choose the key that switches them. Raspberry Pi OS has none.
- The **battery** appears only on a computer with a battery.
- The **microphone** and **Bluetooth** icons appear only when the computer
  has a microphone or a Bluetooth adapter, as on Raspberry Pi OS.
- Plugins that need Raspberry Pi hardware or tools (updater, power, network)
  are left out.

### Raspberry Pi's panel and file manager on Debian 10 to 12

Before Raspberry Pi OS 13, Raspberry Pi's panel and file manager are its own
builds of Debian's `lxpanel`, `pcmanfm` and `libfm`, under the same names.
From Raspberry Pi OS 11 they use GTK 3, and Debian 11 and 12 build theirs
for GTK 2, so the two cannot be mixed. With `--pi-apps` (the default), the
script installs Raspberry Pi OS's builds for your release in place of
Debian's, with Raspberry Pi's panel plugins (menu, eject, Bluetooth, volume,
battery, magnifier). Debian's LXDE session then uses them too.

- `--uninstall` and `--prepare-upgrade` install Debian's versions again.
- `--no-pi-apps` keeps Debian's panel and file manager, in Raspberry Pi
  OS's layout.
- If Raspberry Pi has no build of a package of these sources that is
  installed here (for example a `-dbg` package), Debian's are kept.

### Applets

On X, Raspberry Pi's panel offers its own applets and these Debian applets:

| Applet | Purpose |
|--------|---------|
| Keyboard Layout Handler (`xkb`) | Keyboard layout |
| Weather (`weather`) | Weather forecast |
| Volume Control (`volume`) | ALSA volume |
| Temperature Monitor (`thermal`) | System temperature |
| Resource Monitors (`monitors`) | CPU and memory graphs |
| Desktop Number (`deskno`) | Current desktop |
| CPU Frequency (`cpufreq`) | CPU frequency |

Debian's network status and keyboard LED applets are not offered: they stop
Raspberry Pi's panel on Debian 13. Programs with a tray icon appear in the
notification area. With `--no-pi-apps`, the session uses Debian's panel,
which offers all of Debian's applets.

## Install options

The installer remembers these options and reuses them on later runs.

| Option | Description | Default |
|--------|-------------|---------|
| `--theme NAME` | Theme from the [table](#themes), or `auto`. | Asked at the end |
| `--icons NAME` | `pixflat`, `pixtrix`, `pix` or `auto`. | `auto` |
| `--wallpaper W` | A file in `/usr/share/rpd-wallpaper`, a path, or `auto`. | `auto` |
| `--4k`, `--no-4k` | 4K wallpapers. | Off |
| `--wayland`, `--no-wayland`, `--auto` | Display system (see [X or Wayland](#x-or-wayland)). | Auto |
| `--pi-apps`, `--no-pi-apps` | Raspberry Pi's panel and file manager; on Debian 10 to 12 in place of Debian's (see [Panel](#panel)). | On |
| `--login-screen`, `--no-login-screen` | Raspberry Pi OS login screen style (LightDM, installed where no other login manager is used). | On |
| `--pi-greeter`, `--no-pi-greeter` | Raspberry Pi's greeter, which has no session chooser. | Off |
| `--login-background B` | `debian`, `raspios`, or a path to a picture. | `debian` |
| `--qt`, `--no-qt` | Qt applications follow the theme. | Off |

These options apply to one run only:

| Option | Description |
|--------|-------------|
| `-d`, `--desktop LIST` | Also apply the look to other desktops, for you only: `xfce`, `gnome`, `budgie`, `cinnamon`, `mate`, `lxqt`, `openbox`, `labwc`, `kde` or `all`. Changed settings are backed up and restored on uninstall. |
| `--bundle LIST` | With `--download`: only these release/architecture pairs, for example `trixie/amd64`. |
| `-y`, `--yes` | Answer yes to every question. |
| `-v`, `--verbose` | Print every command run with sudo. |
| `--no-log` | Do not write a log file. |

## What is installed

### From Raspberry Pi OS

Each package is verified against Raspberry Pi's signing key.

| Kind | Packages |
|------|----------|
| Themes | `pixflat-theme`, `pixtrix-theme`, `pix-theme`, `gtk2-engines-pixflat`, `gtk2-engines-clearlookspix` |
| Icons and cursors | `pixflat-icons`, `pixtrix-icons`, `rpd-icons` |
| Fonts | `fonts-piboto`, `fonts-nunito-sans` |
| Wallpapers | `rpd-wallpaper`, `rpd-wallpaper-trixie`, or their 4K versions |
| Login screen | `pi-greeter` (with LightDM) |
| Panel (Debian 13+) | `lxpanel-pi` and its plugins, `pishutdown`, `gui-runcmd`; for Wayland, `wf-panel-pi` and its plugins |
| Panel (Debian 10 to 12) | Raspberry Pi OS's `lxpanel` and `lxpanel-data`, in place of Debian's, and its plugins (`lxplug-*`) |
| Settings (Wayland) | `rpcc` (Control Centre), `pipanel` (Appearance Settings), `sudopwd` |
| File manager (Debian 13+) | `pcmanfm-pi`, installed beside Debian's |
| File manager (Debian 10 to 12) | Raspberry Pi OS's `pcmanfm` and `libfm`, in place of Debian's |

### From Debian

Only missing packages are installed.

| Kind | Packages |
|------|----------|
| Session | `lxsession`, `openbox`, `lxpanel`, `pcmanfm`, `lxappearance`, `dconf-cli`, `libglib2.0-bin`, `accountsservice` (with LightDM) |
| Display | `xserver-xorg`, `libgl1-mesa-dri`, `x11-utils`; for Wayland, `labwc`, `swaybg`, `kanshi`, `xsettingsd`, `wlr-randr`, `xwayland` |
| Themes | `gtk2-engines-pixbuf`, `libgtk2.0-bin`, `gnome-icon-theme`, `adwaita-icon-theme-legacy` (Debian 13), `sound-theme-freedesktop`, Liberation Mono |
| Help menu | `debian-reference` |

### Hardware support

Added only for hardware the computer has, and kept on uninstall:

- **Wi-Fi:** NetworkManager, `wpasupplicant`, `iw`, `wireless-regdb`,
  `rfkill`, unless another network manager is installed. Interfaces in
  `/etc/network/interfaces` are not changed.
- **Bluetooth:** BlueZ, `rfkill`, Bluetooth audio, and `blueman` where
  Debian's panel is used.
- **Login screen:** LightDM and its GTK greeter where no other login manager
  is used, and `desktop-base` for Debian's login artwork.
- **Sound:** PipeWire (Debian 12 and later) or PulseAudio, if no sound
  server is installed.
- **Firmware:** packages for firmware the kernel failed to load during this
  boot, from Debian's `non-free-firmware` component. If that component is
  not enabled, the summary explains how to add it.

## The session

- **Login screen entries:** *Raspberry Pi Desktop* (X), and *Raspberry Pi
  Desktop on Wayland* where the computer suits it. The first install selects
  the suitable one; the login screen remembers your choice.
- **Settings:** Raspberry Pi OS's values for theme, icons, cursor, fonts,
  hinting, toolbar icons and event sounds.
- **Windows:** the theme's Openbox frames, one desktop, and Raspberry Pi
  OS's keys: Super for the menu, Alt+F2 to run, Ctrl+Alt+T for a terminal,
  Ctrl+Shift+Escape for the task manager, Ctrl+Alt+Delete to shut down.
- **Panel:** Raspberry Pi OS's layout at the top of the screen (see
  [Panel](#panel)).
- **File manager:** on Debian 10 to 12, Raspberry Pi OS's own settings for
  its release (folder tree, thumbnails, window size).
- **Menu:** Raspberry Pi OS's menu and categories, with Help, Preferences
  and Logout.
- **Desktop and file manager:** Raspberry Pi OS's wallpaper, colours, font
  and file manager settings.
- **GTK 4 applications:** use the theme's colours and its light or dark
  style.
- **Wayland:** labwc with Raspberry Pi OS's window settings and keys, and
  Raspberry Pi's Wayland panel.

**Login screen.** LightDM's greeter uses Raspberry Pi OS's colours, theme
and font, with the Debian logo and Debian's login artwork
(`--login-background raspios` uses Raspberry Pi OS's). Without a login
manager, LightDM is installed. Other login managers, such as GDM or SDDM,
are not changed; the sessions are listed there too, and the summary explains
how to switch to LightDM.

**Other desktops** (`--desktop`):

| Desktop | Applied |
|---------|---------|
| Xfce | Theme, icons, cursor, fonts, wallpaper, top panel, window frames |
| GNOME, Budgie | GTK theme, icons, cursor, fonts, button layout, wallpaper |
| Cinnamon, MATE | Theme, icons, cursor, fonts, wallpaper |
| LXQt | Icons, cursor, Openbox theme, wallpaper |
| Openbox, labwc | Window settings; labwc also cursor and GTK settings |
| KDE Plasma | Icons and cursor |

## Updating

No package source is added, so `apt upgrade` does not update the Raspberry
Pi OS packages. To update them:

- `bash rpios-look.sh --refresh` lists available updates, then asks.
- `bash rpios-look.sh` applies updates directly.

Installed packages are never downgraded. Debian packages are updated by
`apt upgrade` as usual.

## Upgrading Debian

1. Run `bash rpios-look.sh --prepare-upgrade`. It removes the Raspberry Pi
   packages that are built for one Debian release (panel, file manager,
   greeter, GTK 2 engines), and on Debian 10 to 12 installs Debian's panel
   and file manager again. Themes, icons, fonts and wallpapers stay.
2. Upgrade Debian and reboot.
3. Run `bash rpios-look.sh`.

## Uninstalling

```bash
bash rpios-look.sh --uninstall
```

The script lists what it removes and asks first. It:

- removes the Raspberry Pi Desktop sessions and restores Debian's login
  screen;
- on Debian 10 to 12, installs Debian's panel and file manager again in
  place of Raspberry Pi OS's;
- after a second question, removes the packages it installed, except those
  other software needs and the hardware support (X server, network,
  Bluetooth, sound, firmware);
- restores the settings that `--desktop` changed for you;
- removes your Raspberry Pi Desktop settings (theme, panel, desktop), which
  no other session reads.

Packages installed before the script, or later, are never removed.

A fresh install detects the computer again: it does not reuse the options
or settings of an earlier install.

## Offline installation

1. On a computer with internet access, run `bash rpios-look.sh --download`.
   This builds `packages/` next to the script for every supported Debian
   release and architecture. Use `--bundle trixie/amd64` to build one only.
2. Copy `rpios-look.sh` and `packages/` to the offline computer.
3. There, run `bash rpios-look.sh --offline`.

`packages/` includes `VERSIONS.md` and `SHA256SUMS`. It is not stored in
this repository.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| The look is missing after login | Choose *Raspberry Pi Desktop* in the login screen's session menu. |
| Windows have no title bars | Log out and back in; the session repairs settings saved by earlier versions. |
| dpkg was interrupted | Run `sudo dpkg --configure -a` and `sudo apt-get -f install`, then the script again. |
| 404 Not Found | Your Debian release has moved to archive.debian.org. Update `/etc/apt/sources.list` as [Debian describes](https://www.debian.org/distrib/archive), run `sudo apt update`, then the script again. |
| Something looks incomplete | Run the same command again; every step is safe to repeat. |

Each run writes a log to your home folder, for example
`rpios-look-install-<date>-<time>.log`. The ten newest logs of each kind are
kept.

## How it works

- **Session:** like Raspberry Pi OS, the session is an LXDE profile
  (`rpd-x`, or `LXDE-pi` before Debian 13). Its settings are in
  `/usr/share/rpios-look`, which only this session reads.
- **Raspberry Pi OS's file names:** your settings use the same files as on
  Raspberry Pi OS, for example `~/.config/openbox/rpd-rc.xml` and
  `~/.config/labwc/rc.xml`, so its own settings programs work unchanged.
  Settings saved by earlier versions are moved at the next login.
- **Generated package:** everything the script writes outside your home
  folder is in one package, `rpios-look-debian`, so dpkg tracks and removes
  it. It holds the session, the login screen style, the icon sets with the
  Debian logo, and `rpios-look-set`.
- **Records:** installed packages, options and replaced files are kept in
  `/var/lib/rpios-look`; per-user records in `~/.local/state/rpios-look`.
- **Releases:** new Debian releases are recognised from `distro-info-data`.
  The script uses the newest Raspberry Pi OS release available for your
  Debian release, and takes panel, menu and settings from Raspberry Pi's own
  packages of that release.
- **Earlier versions:** installs of `raspios-look` (3.0.0) and
  `pixflat-theme` (2) are taken over automatically.

## Keeping Debian safe

The script follows Debian's
[DontBreakDebian](https://wiki.debian.org/DontBreakDebian) guidance:

- **No extra package sources.** Only individual Raspberry Pi packages are
  installed, never a repository. A package is refused if it has the same
  name as a Debian package, replaces or conflicts with one, or changes
  Debian's files. The one exception is Raspberry Pi OS's own builds of
  Debian's panel and file manager on Debian 10 to 12, which `--pi-apps`
  installs in place of Debian's: the plan names them, and `--uninstall`
  and `--prepare-upgrade` install Debian's again (see [Panel](#panel)).
  Packages with compiled code must match your Debian release, and all
  their dependencies must come from Debian; dependencies that only a
  Raspberry Pi needs (`raspi-config` for the Raspberry Pi OS 10 and 11
  battery plugin) are left out.
- **Debian packages come from your APT sources only.** Before installing,
  the script checks every package's origin. APT runs with `--no-remove`, so
  nothing is removed to make room.
- **Everything is tracked.** All system files are in packages dpkg knows
  about. The only exceptions, all undone by `--uninstall`, are
  `/etc/lightdm/pi-greeter.conf` (with `--pi-greeter`), the users' session
  choice, and the records in `/var/lib/rpios-look`.
- **Nothing happens without asking.** The plan lists every package with its
  version and origin before anything changes.

**Verification.** Raspberry Pi indexes are checked against the Raspberry Pi
Archive Signing Key (`CF8A 1AF5 02A2 AA2D 763B AE7E 82B1 2992 7FA3 303E`),
Debian indexes against `debian-archive-keyring`, and every package against
its SHA256. Downloads come only from `https://archive.raspberrypi.org/`,
`https://deb.debian.org/` and `https://archive.debian.org/`.

## Credits and licence

The themes, icons, fonts, wallpapers and desktop settings are the work of
[Raspberry Pi Ltd](https://www.raspberrypi.com/) and the Raspberry Pi desktop
team. This project installs their official packages on Debian. All artwork
keeps its own licence (see `/usr/share/doc/<package>/copyright`).

The script is released under the MIT licence; see [LICENSE](LICENSE).
