# rpios-look-legacy: Debian 9 to 12

`rpios-look-legacy.sh` installs the official Raspberry Pi OS desktop of
Debian 9 to 12 on 32-bit (`i386`) and 64-bit (`amd64`) PCs, online or
offline. It is the frozen edition of rpios-look: it gets fixes and keeps
updating the installed Raspberry Pi packages, but no new features. For
Debian 13 and later, use `rpios-look.sh` ([README](README.md)).

The general documentation applies to both scripts: the
[README](README.md) describes the session, `rpios-look-set`, the keys and
how the look is kept safe for Debian. This
page covers what is different on Debian 9 to 12.

> [!WARNING]
> **Old Debian releases.** Debian 9 to 12 are older than the current stable
> release. Debian's security support for 9, 10 and 11 has ended, and 12 gets
> only LTS updates. Old releases and the packages made for them, Debian's and
> Raspberry Pi OS's, may contain known security vulnerabilities that will not
> be fixed. The script warns about this when it runs and says when support
> ends or ended. Use it at your own risk, keep such a computer away from
> untrusted networks, or upgrade it. See the [Disclaimer](README.md#disclaimer).

## Contents

1. [Quick start](#quick-start)
2. [Modes and options](#modes-and-options)
3. [Looks per release](#looks-per-release)
4. [Offline installation](#offline-installation)
5. [Wi-Fi](#wi-fi)
6. [Qt programs](#qt-programs)
7. [Updating, upgrading and uninstalling](#updating-upgrading-and-uninstalling)
8. [Supported systems](#supported-systems)
9. [Differences from rpios-look.sh](#differences-from-rpios-looksh)

## Quick start

**Requirements:** Debian 9, 10, 11 or 12, 32-bit or 64-bit, with Debian's
LXDE desktop (`task-lxde-desktop`); bash 4.4 or later; a normal user account
with sudo rights (do not run the script as root); internet access, except for
an [offline installation](#offline-installation).

```bash
git clone https://github.com/b1ack0p/rpios-look.git
cd rpios-look
bash rpios-look-legacy.sh
```

Read the warnings, enter your password, review the plan and answer `y`. The
computer restarts; **Raspberry Pi Desktop** is preselected on the login
screen.

## Modes and options

The same modes and options as [rpios-look.sh](README.md#modes-and-options),
plus offline installation:

| Command | What it does | Your settings |
|---|---|---|
| `bash rpios-look-legacy.sh` | Install, or reinstall cleanly | back to the defaults |
| `bash rpios-look-legacy.sh --refresh` | List updates, then ask before applying them | kept |
| `bash rpios-look-legacy.sh --uninstall` | Remove what the script added, restore Debian's setup | restored |
| `bash rpios-look-legacy.sh --download` | Build `packages/` for an offline installation | not touched |
| `bash rpios-look-legacy.sh --offline` | Install from `packages/`, without a network | back to the defaults |

Options: `--size small|medium|large`, `--no-reboot`, `-v`/`--verbose`,
as in the [README](README.md#modes-and-options). A plain run and `--offline`
reset the session's settings and the file manager's, as the README
describes; `--refresh` keeps them. Logs are named
`~/rpios-look-legacy-<mode>-<date>-<time>.log`.

## Looks per release

As in the [README's table](README.md#looks-per-release): each release gets the
look of its own Raspberry Pi OS release and of every earlier one, never a
later one, with Raspberry Pi OS's own defaults.

| Debian | Default theme | Themes | Default wallpaper |
|---|---|---|---|
| 9 (Stretch) | PiX | PiX | `road.jpg` |
| 10 (Buster) | PiXflat | PiX, PiXflat, PiXnoir | `temple.jpg` |
| 11 (Bullseye) | PiXflat | PiX, PiXflat, PiXnoir | `clouds.jpg` |
| 12 (Bookworm) | PiXflat (dark: PiXnoir) | PiX, PiXflat, PiXnoir | `fisherman.jpg` |

- **Debian 9** uses Raspbian Stretch's own packages for PCs, from the `ui`
  section of Raspberry Pi's archive: its panel, file manager and Openbox
  builds where Debian 9 can install them (beside Debian's), otherwise
  Debian's, with a note.
  Raspbian Stretch has no magnifier, so Debian 9 has none and no Ctrl+Alt+M.
  Its eject plugin needs a newer fontconfig than Debian 9 has, so the panel
  has no eject icon there.
  Debian 9 also gets two of Debian's own packages, installed first and
  removed by `--uninstall` (or at once, if the run stops before installing
  the look): `fakeroot` (Debian 9's `dpkg` needs it to build
  packages) and `apt-transport-https` (Debian 9's APT needs it for Raspberry
  Pi's archive). If your APT sources lack `apt-transport-https`, Raspberry
  Pi's archive is not added to APT, and `--refresh` updates the look. If your
  own APT sources use `https`, `--uninstall` keeps `apt-transport-https`.
- **Debian 9 to 12** use Raspberry Pi OS's builds of the panel (`lxpanel`
  with `lxplug-*` plugins), file manager (`pcmanfm`, `libfm`) and Openbox,
  as Raspberry Pi OS of that release has them. They are repacked to install
  beside Debian's packages, with their own names (`rpios-look-lxpanel`,
  `lxpanel-pi`, `pcmanfm-pi`, `openbox-pi`), folders and library names, and
  only the Raspberry Pi Desktop session starts them (see the README's
  [Keeping Debian safe](README.md#keeping-debian-safe)). Raspberry Pi's
  Appearance Settings (`pipanel`) is not installed: it writes into settings
  files that Debian's sessions read too. `--size` and `rpios-look-set` apply
  the same presets and themes; the menu has Debian's Customize Look and Feel.
- **Openbox:** Raspberry Pi's build keeps a window's corners rounded while it
  moves. Its libraries have their own names, so Debian's `obconf` and
  `lxappearance-obconf` (the Window Border tab of LXDE's Appearance) keep
  Debian's Openbox libraries and work in every session.
- **Debian's LXDE session** is not changed: Debian's panel, file manager and
  Openbox, with Debian's layout.

The README lists every package of each release, from Raspberry Pi OS and
from Debian, with what it is for: [Packages](README.md#packages).

## Offline installation

1. On a computer with internet access and Debian 12 or later, in the script's
   folder (an older Debian's `debian-archive-keyring` lacks the keys that
   check the later releases' indexes; the script then stops and says so):

   ```bash
   bash rpios-look-legacy.sh --download
   ```

   It builds `packages/` for Debian 9 to 12, `i386` and `amd64`.
2. Copy `rpios-look-legacy.sh` and `packages/` to the offline computer.
3. There, in the same folder:

   ```bash
   bash rpios-look-legacy.sh --offline
   ```

- **Result:** the same as an online installation, but without Raspberry Pi's
  APT source, so `apt` does not update the look. `packages/` holds Raspberry
  Pi's builds as Raspberry Pi ships them; the offline computer repacks those
  that go beside Debian's, as an online installation does.
- **Integrity:** every file is checked against `packages/SHA256SUMS` first.
- **Later:** once the computer is online, `--refresh` updates the look from
  the online archives.
- `packages/` also keeps the look installable if Raspberry Pi's archives for
  these old releases ever go offline.

## Wi-Fi

Two fixes restore what Debian does by default on older laptops:

- **Missing Wi-Fi firmware.** When the kernel reports that a Wi-Fi driver
  cannot load its firmware, the plan names the Debian package that has it
  (for example `firmware-ipw2x00` for Intel PRO/Wireless 2200). It is
  installed only from your own APT sources, and only if `non-free` (on Debian
  12: `non-free-firmware`) is enabled; otherwise a note says which component
  to enable. APT sources are never edited. Firmware with a licence (Intel's)
  is installed only after you read and accept the licence at a prompt.
  Ethernet and Bluetooth firmware is never touched, and a driver whose
  connection is up is never reloaded.
- **wicd without a Wi-Fi card.** Debian 9 and 10 manage the network with
  wicd. If wicd was set up before the Wi-Fi card worked, its setting
  `wireless_interface = None` is set to the card. wicd restarts, which can
  briefly drop a connection it manages. `--uninstall` puts `None` back if the
  value is still the one the script set and the Wi-Fi interface is not in
  use. The network manager is never replaced.

`--uninstall` removes the network and Bluetooth tools the install added, so
that your network setup from before the install is back after the restart,
and asks separately before removing firmware (default: keep), as removing it
cuts Wi-Fi. Packages you keep stay recorded, so that a later `--uninstall`
can remove them; they do not stop a new install, by either script.

## Qt programs

Qt programs (such as VLC) follow the GTK theme as on Raspberry Pi OS of the
same release, through one setting in the Raspberry Pi Desktop session only:

| Debian | Setting | Package (Debian's) | Added on a system without Qt |
|---|---|---|---|
| 9 | `QT_QPA_PLATFORMTHEME=gtk2` | `qt5-style-plugins` | about 27 MB |
| 10 | `QT_QPA_PLATFORMTHEME=gtk2` | `qt5-style-plugins` | about 29 MB |
| 11 | `QT_QPA_PLATFORMTHEME=gtk3` | `qt5-gtk-platformtheme` | about 23 MB |
| 12 | `QT_QPA_PLATFORMTHEME=gtk2` | `qt5-style-plugins` | about 31 MB |

Sizes are estimates from Debian's package indexes; most is the Qt 5 library
set the plugin needs. Qt 6 is not styled, as on Raspberry Pi OS 9 to 12.
`--uninstall` removes the plugin and the Qt libraries the install brought in,
only where nothing else uses them, so Qt programs you installed keep theirs.
See the [README](README.md#qt-and-gnome-programs).

## Updating, upgrading and uninstalling

- **Update:** `bash rpios-look-legacy.sh --refresh` checks online for fixes
  and updates of every Raspberry Pi package the look installed: themes,
  icons, fonts, wallpapers, GTK engines, panel, plugins, file manager and
  Openbox. Packages with compiled code come only from your release's own
  Raspberry Pi OS. It also notes a newer version of the script.
  On an online installation, `sudo apt upgrade` also updates the Raspberry
  Pi packages installed unchanged; those repacked beside Debian's (panel,
  file manager, Openbox) come with `--refresh`, as described in the README.
- **Upgrade Debian 9 to 12:** `bash rpios-look-legacy.sh --uninstall`,
  upgrade Debian, restart, then a clean install: `bash rpios-look-legacy.sh`.
- **Upgrade to Debian 13:** `bash rpios-look-legacy.sh --uninstall`, upgrade
  Debian, restart, then install with `bash rpios-look.sh`. 32-bit PCs stay
  on Debian 12: Debian 13 has no 32-bit release.
- **Uninstall:** `bash rpios-look-legacy.sh --uninstall`. It also removes an
  installation made by `rpios-look.sh`. Where the look
  is not installed, it says so and changes nothing.

## Supported systems

| Debian | PCs | Panel and file manager | Default theme | Security support |
|---|---|---|---|---|
| 9 (stretch) | 32-bit, 64-bit | Raspbian Stretch builds | PiX | ended |
| 10 (buster) | 32-bit, 64-bit | Raspberry Pi OS 10 builds | PiXflat | ended |
| 11 (bullseye) | 32-bit, 64-bit | Raspberry Pi OS 11 builds | PiXflat | ended |
| 12 (bookworm) | 32-bit, 64-bit | Raspberry Pi OS 12 builds | PiXflat | LTS until 2028-06-30 |

- On Debian 13 and later, the script stops before changing anything and
  points to `rpios-look.sh`. `--uninstall` works on any release,
  `--download` on Debian 12 and later (see
  [Offline installation](#offline-installation)).
- **Network icon:** on Debian 12, Raspberry Pi's network item is used when
  NetworkManager manages the network. Otherwise, and always on 9 to 11,
  only a network icon you already have (such as nm-applet or wicd) appears
  in the tray: the script installs none, as Debian's tray icons start in
  every session. NetworkManager and the Wi-Fi tools are installed only for
  Raspberry Pi's network item, on a computer with Wi-Fi and no other network
  manager; where the item is left out, they are not.
- On Debian 11 and 12, Raspberry Pi's panel and file manager are GTK 3
  programs (Debian's are GTK 2); the session uses about 37 to 74 MB more
  memory than Debian's LXDE. On 9 and 10 it uses the same.

## Differences from rpios-look.sh

- Releases 9 to 12, 32-bit and 64-bit; offline installation (`--download`,
  `--offline`).
- The Wi-Fi fixes above.
- The panel and file manager are Raspberry Pi OS's builds of Debian's
  (`lxpanel`, `pcmanfm`, `libfm`), repacked beside Debian's; on Debian 13 they
  are Raspberry Pi's own programs (`lxpanel-pi`, `pcmanfm-pi`).
- The X session only: no Wayland session (Raspberry Pi's labwc session
  needs newer system libraries than Debian 12's).
- Sizes Small, Medium and Large, as Raspberry Pi OS 9 to 12's Appearance
  Settings offers them (Raspberry Pi OS 13 adds Larger). Large on Debian 9
  to 11 widens the scrollbars and resize borders but keeps the title bar,
  as Raspberry Pi OS 9 to 11 did; Debian 12 also uses the large title bar.
- On Debian 11 the window manager is Openbox. Raspberry Pi OS 11 ran Mutter
  on PCs and larger Pis, and Openbox on smaller Pis and over VNC; Mutter
  would have to be repacked beside Debian's, whose GNOME uses it.
- `rpios-look-set --theme` leaves the session's GSettings (among them the
  light or dark style of GTK 4 and libadwaita programs) at the session's
  defaults, as Raspberry Pi OS 9 to 12's Appearance Settings does. The light
  or dark style is not set there either, also with a dark theme such as
  PiXnoir: nothing in Raspberry Pi OS 9 to 12 sets it.
- Frozen: fixes and package updates only, no new features.
