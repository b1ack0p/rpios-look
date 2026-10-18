# rpios-look

Makes Debian look like Raspberry Pi OS, without breaking Debian. It brings
the official **PiXflat**, **PiXnoir**, **PiXtrix**, **PiXonyx** and **PiX**
themes with their icons, cursors, fonts and wallpapers, Raspberry Pi's own
panel, file manager and login screen, and Raspberry Pi OS's desktop settings.
As on Raspberry Pi OS, it all comes as sessions on the login screen,
**Raspberry Pi Desktop** (X) and, on Debian 13 and later, **Raspberry Pi
Desktop on Wayland**, next to Debian's own sessions, which stay as they were.

It works on Debian 10 to 13 and later (testing and unstable too), on 64-bit
and 32-bit PCs (amd64, i386) and on ARM (arm64, armhf), on new machines and
old ones such as 32-bit laptops. Other architectures get the themes, icons,
fonts and wallpapers.

Where it differs from Raspberry Pi OS:

- The **Debian logo** is shown wherever Raspberry Pi OS shows the Raspberry
  Pi logo: on the menu button and the login screen.
- Raspberry Pi's system tools are left out: raspi-config, the updater, the
  power and network plugins of the panel. The network icon in the panel
  comes from Debian's nm-applet instead, where NetworkManager is installed.
- The login screen is Debian's LightDM greeter in Raspberry Pi OS's style,
  which keeps the session chooser; Raspberry Pi's own greeter has none
  (`--pi-greeter` uses it anyway).
- The X session is chosen for you; Raspberry Pi OS 13 starts Wayland by
  default. Both are on the login screen.
- Raspberry Pi's panel, file manager and Wayland session are built for Debian
  13 and later. On Debian 10 to 12 the session uses Debian's panel and file
  manager, in the same layout.

![The Raspberry Pi Desktop session on Debian 13, with its menu open](screenshot/scr1.png)
![The Raspberry Pi Desktop session on Wayland, Debian 13](screenshot/scr2.png)
![The login screen](screenshot/scr3.png)
![Debian 12 on a 32-bit PC, with Debian's own panel](screenshot/scr4.png)

## Quick start

1. Download `rpios-look.sh` (or clone this repository).
2. Open a terminal in its folder and run:

   ```bash
   bash rpios-look.sh
   ```

3. Choose the look, read the plan, answer `y`, and enter your password when
   asked. The script asks at the terminal; without one every question takes
   its default (`-y` answers yes).
4. Log out. The login screen has **Raspberry Pi Desktop** chosen for you;
   log in.

Running it again is safe. To undo it, see [Uninstall](#uninstall).

## Requirements

- Debian 10 (buster) or later, or a derivative.
- A normal user account with sudo rights. Do not run it as root.
- Internet access, except for an [offline install](#offline-install).
- About 80 MB of disk space (the wallpapers are most of it; 4K ones, about
  200 MB more).

## Usage

```bash
bash rpios-look.sh                   # install or update
bash rpios-look.sh --refresh         # list updates, then ask
bash rpios-look.sh --uninstall       # undo the look
bash rpios-look.sh --prepare-upgrade # before a Debian upgrade
bash rpios-look.sh --download        # fill packages/ (offline)
bash rpios-look.sh --offline         # install from packages/
bash rpios-look.sh --help            # commands and options
```

The session is added for every user. Anyone can switch on the login
screen; it remembers the choice. The look appears only in the Raspberry Pi
Desktop session: Debian's LXDE, Xfce, GNOME and other sessions keep their own
settings. Settings a user makes in the session, for example in *Appearance
Settings*, are kept in that user's files and win over the defaults.

## Themes

| Theme (`--theme`) | Look | Font | Wallpaper |
|-------------------|------|------|-----------|
| `pixflat` | light, Raspberry Pi OS Bookworm (default on Debian 10 to 12) | Piboto | fisherman |
| `pixnoir` | dark, Raspberry Pi OS Bookworm | Piboto | fisherman |
| `pixtrix` | light, Raspberry Pi OS Trixie (default on Debian 13 and later) | Nunito Sans Light | sunrise |
| `pixonyx` | dark, Raspberry Pi OS Trixie | Nunito Sans Light | sunrise |
| `pix` | legacy, Raspberry Pi OS Buster/Bullseye | Piboto | fisherman |

Every theme is installed; the first install asks which one the session
uses. Change it later with, for example:

```bash
bash rpios-look.sh --theme pixonyx
bash rpios-look.sh --theme auto      # back to the one for your Debian
```

That changes the session for everyone. For yourself only, without sudo and
at once in the running session, use `rpios-look-set`, which the install adds:

```bash
rpios-look-set --theme pixonyx                  # with its icons, cursor and font
rpios-look-set --icons pixflat --cursor pixtrix --cursor-size 32
rpios-look-set --accent '#d6363c'               # highlight colour
rpios-look-set --desktop-color '#202020' --wallpaper none
rpios-look-set --wallpaper aurora --wallpaper-mode fit
rpios-look-set --font "Nunito Sans Light 13"
rpios-look-set --show                           # the look now
rpios-look-set --reset                          # back to the session's look
```

It writes the same files as *Customize Look and Feel* and *Desktop
Preferences*, which only the Raspberry Pi Desktop session reads. The
highlight colour is kept as Raspberry Pi OS keeps it, in a copy of each
Raspberry Pi theme (`~/.local/share/rpios-look`). Window borders keep the old
cursor until the next login. On Debian 10 to 12, Debian's file manager shows
new colours fully, and the desktop a new colour or font, from the next login
(a new wallpaper at once). The session on Wayland does not use these
settings yet.

In *Customize Look and Feel* each Raspberry Pi icon set and cursor appears
once, by its own name (the set adapted for Debian), and the lists are sorted.

## Options

Options go after the command, for example:

```bash
bash rpios-look.sh --theme pixnoir --icons pixtrix
```

### Remembered options

The script remembers these and uses them again on later runs until you give
a new value.

- **`--theme NAME`**: the look, from the table above, or `auto`. Default:
  `auto`.
- **`--icons NAME`**: the icon set, `pixflat`, `pixtrix`, `pix` or `auto`
  (the theme's own). Default: `auto`.
- **`--wallpaper W`**: a file in `/usr/share/rpd-wallpaper` (for example
  `aurora`), a path, or `auto` (the theme's own). Default: `auto`.
- **`--4k`**, **`--no-4k`**: the 4K wallpapers instead of the standard ones.
  Default: standard.
- **`--pi-apps`**, **`--no-pi-apps`**: Raspberry Pi's own panel and file
  manager, installed beside Debian's (Debian 13 and later), or Debian's.
  Default: Raspberry Pi's.
- **`--login-screen`**, **`--no-login-screen`**: the Raspberry Pi OS login
  screen, where LightDM is the login manager, or the login screen as it is.
  Default: Raspberry Pi OS's.
- **`--pi-greeter`**, **`--no-pi-greeter`**: Raspberry Pi's own login box,
  exactly as on Raspberry Pi OS but without a session chooser, or Debian's
  greeter in its style. Default: Debian's.
- **`--login-background B`**: the picture behind the login box: `debian`
  (Debian's own login artwork, which follows Debian's active theme),
  `raspios` (Raspberry Pi OS's) or a full path to a picture. Default:
  `debian`.
- **`--wayland`**, **`--no-wayland`**: also the Raspberry Pi Desktop session
  on Wayland (Debian 13 and later). Default: on.
- **`--qt`**, **`--no-qt`**: Qt applications follow the theme in the session
  (installs Debian's Qt GTK platform themes). Default: off.

### One-run options

- **`-d`, `--desktop LIST`**: also give these desktops the look, for you
  only: `xfce`, `gnome`, `budgie`, `cinnamon`, `mate`, `lxqt`, `openbox`,
  `labwc`, `kde`, `all` or `none`. Default: `none`. Every setting it changes
  is backed up, and `--uninstall` restores it.

  ```bash
  bash rpios-look.sh --desktop xfce
  ```

- **`--bundle LIST`**: with `--download`, only these release/architecture
  pairs, for example `bookworm/i386,trixie/amd64`.
- **`--no-log`**: write no log file.
- **`-y`**, **`--yes`**: answer yes to every question.
- **`-v`**, **`--verbose`**: print every command run with sudo.

## What changes

### Packages

From Raspberry Pi OS, each verified against Raspberry Pi's signing key:

- **Themes:** `pixflat-theme` (PiXflat, PiXnoir), `pixtrix-theme` (PiXtrix,
  PiXonyx), `pix-theme` (PiX), with their GTK 2 engines
  `gtk2-engines-pixflat` and `gtk2-engines-clearlookspix`.
- **Icons and cursors:** `pixflat-icons`, `pixtrix-icons`, `rpd-icons`.
- **Fonts:** `fonts-piboto`, `fonts-nunito-sans`.
- **Wallpapers:** `rpd-wallpaper`, `rpd-wallpaper-trixie` (or their 4K
  sets).
- **Login screen:** `pi-greeter`, where LightDM is installed.
- **Panel (Debian 13 and later):** `lxpanel-pi` and, for Wayland,
  `wf-panel-pi`, each with every plugin Raspberry Pi OS installs that works on
  Debian (menu, volume, Bluetooth, clock, battery, eject, magnifier, CPU,
  CPU temperature, GPU), `pishutdown` (the Shutdown dialog) and `gui-runcmd`
  (the Run dialog).
- **File manager (Debian 13 and later):** `pcmanfm-pi`, installed beside
  Debian's as its own program (see [Don't break Debian](#dont-break-debian)).

From Debian:

- **The session:** `lxsession`, `openbox`, `lxpanel`, `pcmanfm`,
  `lxappearance`, `dconf-cli` and, with LightDM, `accountsservice`, where
  missing; for Wayland, `labwc`,
  `swaybg`, `kanshi`, `xsettingsd`, `wlr-randr` and `xwayland`.
- **For the themes:** `gtk2-engines-pixbuf`, `libgtk2.0-bin`,
  `gnome-icon-theme`, `adwaita-icon-theme-legacy` (Debian 13),
  `sound-theme-freedesktop`, and Liberation Mono (`fonts-liberation` or
  `fonts-liberation2`).
- **Help menu:** `debian-reference`.

### Hardware support

The panel's network, Bluetooth and volume icons need the services behind
them, as on Raspberry Pi OS. The script looks at the hardware and adds only
what this computer uses, from Debian:

- **Wi-Fi adapter:** NetworkManager with `wpasupplicant`, `iw`,
  `wireless-regdb` and `rfkill`, unless another network manager (ConnMan,
  Wicd) is installed. Interfaces set up in `/etc/network/interfaces` stay
  as they are. The network icon is NetworkManager's `nm-applet`, also added
  where NetworkManager is installed already; Raspberry Pi's own network
  plugin needs a Raspberry Pi rebuild of a Debian library, so it is left out.
- **Bluetooth adapter:** BlueZ, `rfkill`, Bluetooth audio for the sound
  server in use, and `blueman` on Debian 10 to 12.
- **Sound card without a sound server:** PipeWire (Debian 12 and later) or
  PulseAudio; Raspberry Pi OS's volume plugin needs one.
- **Missing firmware:** the drivers are part of Debian's kernel; what a
  device can lack is its firmware. The script reads this boot's kernel log
  for firmware a driver could not load, looks each file up in Debian's
  signed index of its firmware component, and installs the package, such as
  `firmware-iwlwifi`, through APT. Where your APT sources lack that
  component (`non-free-firmware`, or `non-free` before Debian 12), the
  summary names the package and how to add it. Reboot afterwards.

These packages are kept when the look is uninstalled: removing them could
leave the computer without its network or sound.

Debian's own panel plugins (CPU frequency, network status, weather,
keyboard layout and others) stay installed with Debian's panel. They cannot
be loaded into Raspberry Pi's panel, which is a separate program; with
`--no-pi-apps` the session uses Debian's panel, and they can be added to it.

### The session

- **Login screen entries:** *Raspberry Pi Desktop* (X) and *Raspberry Pi
  Desktop on Wayland*, next to Debian's sessions. The first install chooses
  the X session for you; the login screen remembers what you pick. With
  LightDM, Debian's `accountsservice` is added where missing: LightDM keeps
  each user's choice there.
- **Settings:** Raspberry Pi OS's own, from its configuration packages
  (`raspberrypi-ui-mods` for Bookworm, `rpd-common` and `rpd-x-core` for
  Trixie): the theme, icons, cursor and font at 12 pt; full hinting and
  subpixel order; 24 px cursors and toolbar icons; no icons in menus and
  buttons; event sounds.
- **Windows:** the theme's Openbox look with round corners and invisible
  resize handles, one desktop, and Raspberry Pi OS's keys (Super for the
  menu, Alt+F2 to run, Ctrl+Alt+Delete to shut down, Ctrl+Alt+T for a
  terminal, Ctrl+Shift+Escape for the task manager, the volume keys).
- **Panel:** Raspberry Pi OS's layout at the top: menu, browser, file
  manager and terminal launchers, taskbar, then eject, Bluetooth, tray,
  volume, clock, battery and magnifier.
- **Menu:** Raspberry Pi OS's own menu, categories and entry names, taken
  from its package for that release, with Help (Debian Reference),
  Preferences and Logout.
- **Desktop and file manager:** the wallpaper, colours and font; trash and
  drives on the first monitor; Raspberry Pi OS's file manager settings. On
  Debian 13 Raspberry Pi's file manager opens folders, and is the only *File
  Manager* in the menu.
- **Tray:** clipboard managers and second volume applets, which Raspberry
  Pi OS does not show, are hidden in the session. Turn one on again in
  *Desktop Session Settings*.
- **Monospace:** Liberation Mono, as on Raspberry Pi OS.
- **GTK 4 and libadwaita applications:** they cannot use the themes, but take
  the theme's colours while the session runs, and its light or dark style.
- **Wayland:** labwc with Raspberry Pi OS's window settings and keys,
  Raspberry Pi's Wayland panel, the desktop, and your system's keyboard
  layout. Graphics without 3D acceleration are drawn in software.

### Login screen (LightDM)

Debian's LightDM greeter with Raspberry Pi OS's colours, theme and font,
the Debian logo as the user picture, the user list, and its session chooser
and power menu, in front of Debian's own login artwork
(`--login-background raspios` shows Raspberry Pi OS's instead). With `--pi-greeter`, Raspberry Pi's own
greeter, where it can run. The login screen is shared by all users and
sessions. With another login manager (GDM, SDDM) the login screen is left
alone; the sessions are listed there as well.

### Other desktops (`--desktop`)

| Desktop | Applied |
|---------|---------|
| Xfce | theme, icons, cursor, fonts, wallpaper, top panel, and an Xfwm4 theme made from the official Openbox theme |
| GNOME, Budgie | GTK 3 theme, icons, cursor, fonts, button layout, wallpaper |
| Cinnamon, MATE | theme, icons, cursor, fonts, wallpaper |
| LXQt | icons, cursor, Openbox theme, wallpaper |
| Openbox, labwc | the window settings above; labwc also cursor and GTK settings |
| KDE Plasma | icons and cursor (Plasma and Qt keep Breeze) |

## Staying up to date

No package source is added, so `apt upgrade` does not update the Raspberry
Pi OS packages. Run the script again instead:

- `bash rpios-look.sh --refresh` lists what an update would change, then
  asks: newer official packages, missing ones, a Debian change, changed
  options. With nothing to update it says so and changes nothing.
- `bash rpios-look.sh` applies the same updates without listing them.

A newer installed version is never downgraded. The Debian packages are
updated by your usual `apt upgrade`.

## Upgrading Debian

1. Run `bash rpios-look.sh --prepare-upgrade`. It lists what it removes
   and asks first: the Raspberry Pi OS packages with compiled code (panel,
   file manager, greeter, GTK 2 engines), which are built for one Debian
   release. The themes, icons, fonts and wallpapers stay, and the session
   uses Debian's panel, file manager and login screen meanwhile.
2. Upgrade Debian as usual and reboot.
3. Run `bash rpios-look.sh`.

## Uninstall

```bash
bash rpios-look.sh --uninstall
```

It lists what it removes and asks first.

For everyone:

- The Raspberry Pi Desktop session is removed from the login screen. Users
  who chose it log in to the login screen's default session again.
- The login screen returns to Debian's.
- After a second question, the packages the script installed are removed,
  with the dependencies only they used. A package that other software has
  come to need is kept; APT's own simulation decides. Hardware support
  (network, Bluetooth, sound, firmware) is kept.

For you, the user running it: the settings `--desktop` changed are restored.

Never removed: packages you had before or installed later.

## Offline install

1. On any computer with internet access, run:

   ```bash
   bash rpios-look.sh --download
   ```

   This fills the `packages/` folder next to the script, for every Debian
   release from 10 and architecture Raspberry Pi publishes, each package
   filed by kind in `packages/pool/` (`themes`, `icons`, `fonts`,
   `wallpapers`, `engines`, `panel`, `files`, `greeter`, `session`,
   `network`, `sound`, `firmware`, `sounds`, `dependencies`).
   `--bundle trixie/i386` builds one release and architecture only. Unchanged
   packages are reused; `VERSIONS.md` lists every package and `SHA256SUMS`
   every file.
2. Copy `rpios-look.sh` and `packages/` to the offline computer.
3. There, run:

   ```bash
   bash rpios-look.sh --offline
   ```

`packages/` is built locally and not kept in this repository.

## Troubleshooting

- **Log files.** Each run writes a log to your home folder, named after its
  mode: `rpios-look-install-<date>-<time>.log`, or
  `rpios-look-uninstall-…`, `rpios-look-refresh-…`, and so on. The
  newest ten of each mode are kept.
- **The look is not there after logging in.** Check that the login screen's
  session menu shows *Raspberry Pi Desktop*.
- **dpkg was interrupted.** Run `sudo dpkg --configure -a` and
  `sudo apt-get -f install`, then run the script again.
- **Another package manager is running.** The script waits for it.
- **404 Not Found.** Debian has moved your release to archive.debian.org
  (Debian 11's security updates moved in 2026). Point
  `/etc/apt/sources.list` there, as
  [Debian describes](https://www.debian.org/distrib/archive), run
  `sudo apt update`, then run the script again. APT downloads everything
  before installing, so the failed run changed nothing.
- **Something looks half done.** Run the same command again; every step is
  safe to repeat.

## New releases

Nothing in the script names a release it has to know in advance:

- Debian's releases come from Debian's own `distro-info-data` where it is
  installed, so a new release is known by its name; testing, unstable and
  derivatives such as Ubuntu or Linux Mint are matched by the Debian
  release they follow (`/etc/debian_version`).
- The script uses the newest Raspberry Pi OS release that publishes the look
  for your Debian release or an older one. Raspberry Pi OS 14 (forky) is
  empty yet, so Debian 14 and unstable use Raspberry Pi OS 13; once
  Raspberry Pi publishes it, `--refresh` shows the move and applies it.
- The architectures are those Raspberry Pi's signed index lists.
- A Debian release that has reached its end is fetched from Debian's archive
  server, with Debian's retired keys.
- The panels, menu and application entries come from Raspberry Pi OS's own
  packages of that release (unpacked, never installed), so a change Raspberry
  Pi makes is taken as it comes; only what cannot work on Debian is left out.

## How it works

- **The session.** Raspberry Pi OS is an LXDE session profile: its login
  screen entry starts `lxsession` with its own profile (`rpd-x`, or
  `LXDE-pi` before Raspberry Pi OS 13), menu and data directories. The
  session here is built the same way. Its settings are in
  `/usr/share/rpios-look`, which only the session puts first in
  `XDG_CONFIG_DIRS` and `XDG_DATA_DIRS`; Debian's sessions never read them.
  The session's programs fall back to Debian's panel, file manager and
  greeter when Raspberry Pi's are not installed.
- **One package.** Everything the script writes outside your home folder is
  in a package it generates, `rpios-look-debian`: the session, the login
  screen style, the icon sets with the Debian logo (`PiXflat-Debian`, …),
  Xfwm4 themes and `rpios-look-set`. dpkg tracks it, and the uninstall
  removes it. The one other
  file is `/etc/lightdm/pi-greeter.conf`, kept and put back.
- **Records.** What the script installed, the options and the replaced login
  screen file are kept in `/var/lib/rpios-look`; the settings `--desktop`
  changed, in `~/.local/state/rpios-look`.
- **An earlier install.** The script was named raspios-look (3.0.0) and,
  before that, pixflat-theme (2). An install under either name is taken over:
  its records carry over, the users who chose its session keep the Raspberry
  Pi Desktop session, and pixflat-theme 2 gives Debian's LXDE session its own
  settings back.
- **The script.** `rpios-look.sh` is one file in twelve numbered sections,
  listed at its top.

## Don't break Debian

Debian's own advice on keeping a system healthy is
[DontBreakDebian](https://wiki.debian.org/DontBreakDebian). This is how the
script follows it, point by point.

- **Don't make a FrankenDebian.** No package source is added: not Raspberry
  Pi's, not another Debian release's, so `apt upgrade` never takes anything
  from elsewhere. Raspberry Pi OS is a Debian derivative, and Debian advises
  against its repositories, so only individual, verified packages are
  installed, each of which:
  - has no namesake in your Debian sources (a Raspberry Pi rebuild of a
    Debian package is never installed);
  - is built for your Debian release when it holds compiled code (for
    Debian 9 and testing or unstable, the nearest release Raspberry Pi
    has), and is installed only when every dependency, with its version,
    comes from Debian;
  - replaces no Debian package and changes no Debian file. Raspberry Pi's
    file manager, which would replace Debian's, is repacked to run beside
    it; `pi-greeter`'s install script, which edits Debian's
    `/etc/lightdm/lightdm.conf`, is left out (that edit, made by
    pixflat-theme 2, is undone where it can be undone exactly); any other
    Raspberry Pi package that would replace, break, conflict with or stand
    in for a Debian package, or whose install scripts touch Debian's files,
    is refused.

  Before installing, the script checks where APT would take every package
  from, and stops unless it is Debian (its security updates included) or one
  of the verified files.
- **Don't use GPU manufacturer install scripts.** Nothing is installed
  outside APT. Firmware a device lacks comes from Debian's own firmware
  packages, through your APT sources.
- **Don't suffer from Shiny New Stuff Syndrome.** No Debian package is
  upgraded beyond your release: Debian packages come from your sources only,
  and APT runs with `--no-remove`, so nothing is removed to make room. The
  Raspberry Pi OS packages get no support from Debian's security team; they
  are themes, artwork and desktop programs, and `--refresh` updates them.
- **`make install` can conflict with packages.** Everything the script puts
  outside your home folder is in packages dpkg tracks: the official ones and
  `rpios-look-debian`, which it generates. The exceptions, all recorded
  and undone by `--uninstall`: `/etc/lightdm/pi-greeter.conf` (with
  `--pi-greeter`; the original is kept), the users' session choice in
  AccountsService (through its own interface) and LightDM's copy of it, and
  the records in `/var/lib/rpios-look`.
- **Don't blindly follow bad advice.** The script shows its plan, every
  package with its version and origin, and asks before changing anything;
  `--refresh` lists updates before applying them. Each run writes a log.
- **Don't blindly remove software.** The uninstall lists what it removes and
  asks. It removes only packages it installed itself: never one that was
  there before, nor one other software needs (APT's simulation decides),
  nor the hardware support it added (network, Bluetooth, sound, firmware).
- **Read package descriptions before installing.** The plan lists every
  package; `VERSIONS.md` in `packages/` lists the offline ones with their
  origin.
- **Take notes.** What the script changed is recorded in
  `/var/lib/rpios-look` and `~/.local/state/rpios-look`, each run's log
  is kept in your home folder, and `dpkg -L rpios-look-debian` lists every
  file of its generated package.

Packages are verified as they are downloaded: Raspberry Pi indexes against
the Raspberry Pi Archive Signing Key pinned in the script
(`CF8A 1AF5 02A2 AA2D 763B AE7E 82B1 2992 7FA3 303E`), Debian indexes against
`debian-archive-keyring`, every package against its SHA256. Downloads come
only from `https://archive.raspberrypi.org/`, `https://deb.debian.org/` and
`https://archive.debian.org/`; other addresses, plain HTTP and redirects are
refused.

## Where the packages come from

**Raspberry Pi OS**: <https://archive.raspberrypi.org/debian/>
(signed indexes in
[`dists/`](https://archive.raspberrypi.org/debian/dists/), packages in
[`pool/main/`](https://archive.raspberrypi.org/debian/pool/main/)).
The login screen wallpaper comes from
[rpd-common](https://archive.raspberrypi.org/debian/pool/main/r/rpd-metas/),
which is unpacked but never installed. The desktop settings are the values
of [raspberrypi-ui-mods](https://archive.raspberrypi.org/debian/pool/main/r/raspberrypi-ui-mods/)
and [rpd-metas](https://archive.raspberrypi.org/debian/pool/main/r/rpd-metas/);
those packages configure a Raspberry Pi system, so they are never installed.

**Debian**: your APT sources, or <https://deb.debian.org/debian/> when
building `packages/`.

## Credits and licence

The themes, icons, fonts, wallpapers and desktop settings are the work of
[Raspberry Pi Ltd](https://www.raspberrypi.com/) and the Raspberry Pi
desktop team; this project installs their official packages on Debian and
applies their settings. All artwork keeps its own licence (see
`/usr/share/doc/<package>/copyright` after installation).

The script: MIT licence; see [LICENSE](LICENSE).
