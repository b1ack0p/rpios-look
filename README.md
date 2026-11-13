# rpios-look

rpios-look installs the official Raspberry Pi OS desktop on Debian's LXDE for
64-bit PCs (`amd64`): Raspberry Pi's themes, icons, cursors, fonts,
wallpapers, panel, file manager and login screen style. It adds a separate X
session, **Raspberry Pi Desktop**, beside Debian's LXDE session, which is not
changed. On Debian 13 and later it also adds **Raspberry Pi Desktop
(Wayland)**, Raspberry Pi OS's labwc desktop, as a second session to pick on
the login screen (see [Wayland session](#wayland-session-debian-13-and-later)).

This repository has two scripts:

| Script | Debian | PCs | Install |
|---|---|---|---|
| `rpios-look.sh` (this page) | 13 (trixie) and later | 64-bit | online |
| `rpios-look-legacy.sh` ([LEGACY.md](LEGACY.md)) | 9 to 12 | 32-bit, 64-bit | online or offline |

Each script runs on its own and stops, before changing anything, on a release
that belongs to the other one.

![PiXtrix, the Raspberry Pi OS 13 look, on Debian 13 with the menu open](screenshot/pixtrix.png)
![PiXflat, the Raspberry Pi OS 10 to 12 look](screenshot/pixflat.png)
![PiX, the legacy Raspbian look](screenshot/pix.png)
![The login screen](screenshot/login.png)

> [!WARNING]
> **Use at your own risk.** The scripts install packages and change system
> files as root. They are provided "as is", without warranty of any kind (see
> [LICENSE](LICENSE)). The authors accept no responsibility for a broken
> system, lost data, security issues or any other damage, whether caused by
> the scripts, by the packages they install or by the Debian release they run
> on. Back up your data first. See [Disclaimer](#disclaimer).

## Contents

1. [Quick start](#quick-start)
2. [Modes and options](#modes-and-options)
3. [Looks per release](#looks-per-release)
4. [Changing the look: rpios-look-set](#changing-the-look-rpios-look-set)
5. [Wayland session (Debian 13 and later)](#wayland-session-debian-13-and-later)
6. [Your own keys](#your-own-keys)
7. [Screen, lock and power button](#screen-lock-and-power-button)
8. [Updating, upgrading and uninstalling](#updating-upgrading-and-uninstalling)
9. [Supported systems](#supported-systems)
10. [Troubleshooting](#troubleshooting)
11. [How it works](#how-it-works)
12. [Tests](#tests)
13. [Related](#related)
14. [Disclaimer](#disclaimer)
15. [Credits and licence](#credits-and-licence)

## Quick start

**Requirements:** Debian 13 or later on a 64-bit PC, with Debian's LXDE
desktop (`task-lxde-desktop`); bash 4.4 or later; a normal user account with
sudo rights (do not run the script as root); internet access. For Debian 9 to
12, or a 32-bit PC, see [LEGACY.md](LEGACY.md).

1. Download `rpios-look.sh`, or clone this repository:

   ```bash
   git clone https://github.com/b1ack0p/rpios-look.git
   cd rpios-look
   ```

2. Install:

   ```bash
   bash rpios-look.sh
   ```

3. Read the warnings, enter your password, review the plan (every package
   with its version and origin) and answer `y`.
4. The computer restarts. **Raspberry Pi Desktop** is preselected on the login
   screen; log in.

Every command is safe to run again.

## Modes and options

Run the script from its folder. Give one mode at a time.

| Command | What it does | Your settings |
|---|---|---|
| `bash rpios-look.sh` | Install, or reinstall cleanly | back to the defaults |
| `bash rpios-look.sh --refresh` | List updates, then ask before applying them | kept |
| `bash rpios-look.sh --uninstall` | Remove what the script added, restore Debian's setup | restored |
| `bash rpios-look.sh --help` | Show the help | |
| `bash rpios-look.sh --version` | Print the version | |

Options, added to a mode:

| Option | What it does |
|---|---|
| `--size small\|medium\|large\|larger` | Raspberry Pi OS's size preset for fonts, icons, panel and cursor (default `medium`). `large` and `larger` also give windows the large title bar (the theme's `_l` window theme, bigger buttons), wider scrollbars (GTK 2 programs included, in this session only) and wider resize borders, as Raspberry Pi OS 13 does; PiX has no large title bar. `small`, `large` and `larger` also set the terminal's font, as Raspberry Pi OS's Appearance Settings does: in your `~/.config/lxterminal/lxterminal.conf`, which Debian's LXTerminal reads too; `medium` and `--uninstall` put your font back. Saved and reused by `--refresh` (with `--size`, `--refresh` changes it); a plain run goes back to `medium`. |
| `--no-reboot` | Do not restart at the end. Otherwise an install and `--uninstall` end with a 60-second countdown (Enter restarts at once, `n` or Ctrl+C cancels); `--refresh` asks, and only when an update needs a restart. |
| `-v`, `--verbose` | Also print the commands run as root, the files downloaded and other details. |

Options combine with a mode in any order; `--size=large` works as well as
`--size large`:

```bash
bash rpios-look.sh --refresh --size large --verbose
```

Every run writes a log to your home folder, for example
`~/rpios-look-install-<date>-<time>.log`; the ten newest of each mode are kept.

**What a plain run resets.** `bash rpios-look.sh`, on a first install and on
every later run, puts the session of the user who runs it back to Raspberry
Pi OS's defaults. `--refresh` keeps all of it.

| Reset to the defaults | Kept |
|---|---|
| Theme, icons, cursor, fonts, wallpaper, size preset | Your files and folders, those on the desktop included |
| Panel: items, order, spacers, position, size, icon size | Your other start entries |
| Window settings and your own keys | Default applications |
| File manager preferences, desktop preferences and where desktop icons sit | The terminal's settings other than its font |
| The file manager's bookmarks | Screen layout; the lid, power button and sleep key settings ([E](#e-lid-power-button-and-sleep-key-whole-computer)) |
| Shortcuts on the desktop (launchers and links): Raspberry Pi OS's desktop shows only the Trash and the drives | Other users' settings |
| [Your own power settings](#your-own-power-settings) for the session (A to D): the `power-times` and `light-locker` start entries and the `swayidle` line | |

The bookmarks are GTK's, so file dialogs and Debian's own sessions lose them
too. On Debian 12 and later, Debian's LXDE adds bookmarks of Documents, Music,
Pictures, Videos and Downloads at each login; the Raspberry Pi Desktop session
does not, as Raspberry Pi OS has none, so those five come back only after a
login into Debian's LXDE. The run names the reset in its plan, before it asks
to proceed. The file manager settings that were there before the first
install, and the bookmarks and shortcuts that any plain run removed, are
recorded, and `--uninstall` puts them back:
the bookmarks beside those you added since, and a shortcut under a numbered
name (`name.~1~`) where a file of its name is on the desktop by then. On
Debian 9 to 12 the file manager keeps part of its preferences in a file that
Debian's LXDE reads too (`~/.config/libfm/libfm.conf`); there only the values
the look sets (icon sizes, thumbnails, single or double click, the trash, the
side pane's places) go back to the defaults, and `--uninstall` undoes only
those, so what you changed in that file since stays. Your own power settings
are set aside, not deleted: `--uninstall` puts them back. A `light-locker`
start entry that only hides the locker is Debian's LXDE's own and stays.

## Looks per release

Each Debian release gets the look of its own Raspberry Pi OS release and of
every earlier one, never a later one. The defaults are Raspberry Pi OS's own,
from its settings files. Each package is installed in its newest version that
works on your Debian release.

**Defaults**

| Debian (Raspberry Pi OS) | Theme (dark) | Icons, cursor | Font | Monospace | Wallpaper |
|---|---|---|---|---|---|
| 9 (Stretch) | PiX | PiX, 24 px | PibotoLt 12 | Liberation Mono | `road.jpg` |
| 10 (Buster) | PiXflat | PiXflat, 24 px | PibotoLt 12 | Liberation Mono | `temple.jpg` |
| 11 (Bullseye) | PiXflat | PiXflat, 24 px | PibotoLt 12 | Liberation Mono | `clouds.jpg` |
| 12 (Bookworm) | PiXflat (PiXnoir) | PiXflat, 24 px | PibotoLt 12 | Liberation Mono | `fisherman.jpg` |
| 13 (Trixie) and later | PiXtrix (PiXonyx) | PiXtrix, 24 px | Nunito Sans Light 12 | Liberation Mono | `sunrise.jpg` |

**Included**

| Debian | Themes | Icon and cursor sets | GTK 2 engines | Fonts | Wallpaper sets |
|---|---|---|---|---|---|
| 9 | PiX | PiX, `rpd-icons` | Clearlooks-PiX | Piboto | `rpd-wallpaper`, `cantab-wallpaper` |
| 10, 11 | PiX, PiXflat, PiXnoir | + PiXflat | + PiXflat | Piboto | + `rpd-wallpaper-4k` (11) |
| 12 | PiX, PiXflat, PiXnoir | PiX, PiXflat, `rpd-icons` | Clearlooks-PiX, PiXflat | Piboto | `rpd-wallpaper`, `rpd-wallpaper-4k`, `cantab-wallpaper` |
| 13 and later | PiX, PiXflat, PiXnoir, PiXtrix, PiXonyx | + PiXtrix | Clearlooks-PiX, PiXflat | Piboto, Nunito Sans | + `rpd-wallpaper-trixie`, `rpd-wallpaper-trixie-4k` |

PiXnoir comes with PiXflat in one Raspberry Pi package, so Debian 10 and 11
have it too. A theme, icon set or wallpaper set that Raspberry Pi OS releases
later for your release is added by `--refresh`.

## Changing the look: rpios-look-set

`rpios-look-set` changes the Raspberry Pi Desktop session for you only. It
needs no sudo, applies within about a second and is kept for later logins.
On Debian 13 and later a theme or a reset is set for both sessions, X and
Wayland, as Raspberry Pi OS's Appearance Settings does.

| Command | What it does |
|---|---|
| `rpios-look-set --theme NAME` | Set a theme: `pixtrix`, `pixonyx`, `pixflat`, `pixnoir` or `pix` |
| `rpios-look-set --animations on\|off\|default` | Turn animations on or off, or follow the session |
| `rpios-look-set --list` | List the installed themes |
| `rpios-look-set --show` | Show the current look |
| `rpios-look-set --reset` | Back to the session's look |
| `rpios-look-set --session x\|wayland` | The session your next login starts (Debian 13 and later) |
| `rpios-look-set --help` | Show the help |

`--theme` and `--animations` go together in one command; `--reset` is given
alone:

```bash
rpios-look-set --theme pixonyx --animations off
```

A theme brings its own icons, cursor, font, window frames, colours and
wallpaper, as Raspberry Pi OS gives them, also in the session's GSettings,
which GTK 4 and other programs read. A dark theme (`pixonyx`, `pixnoir`) sets
the dark style of GTK 4 and libadwaita programs, and a light one the light
style, as Raspberry Pi OS's Appearance Settings does. These are kept in the
Raspberry Pi Desktop sessions' own settings, so Debian's sessions are not
changed. A theme with
new icons restarts the panel for a moment; the network and running programs
are not affected.

**Wallpapers.** Each wallpaper set is in its own folder under
`/usr/share/backgrounds/rpios-look`, named after its package. The folders
hold links; the files stay where Raspberry Pi's packages install them, so
their updates keep working. To pick a wallpaper, right-click the desktop,
choose Desktop Preferences and open one of these folders.

**Animations.** `rpios-look-set --animations off` turns off Openbox's
minimize outline and GTK's animations. Programs that draw their own title bar
or animations are not affected.

**Other tools.** **Customize Look and Feel** in the menu also works.

**Window settings (Openbox).** As on Raspberry Pi OS, Openbox reads the
session's settings (`/usr/share/rpios-look/xdg/openbox/rpd-rc.xml`), then
your own file, `~/.config/openbox/rpd-rc.xml`, over them. The session never
writes your file: `rpios-look-set --theme` and Openbox Configuration do,
when you use them, and `rpios-look-set --reset` removes it.
`rpios-look-set` writes only the window theme there,
so settings that your file does not hold, such as the keys, follow the
session's, also after `--refresh`. On Debian 9 to 12 the file is
`lxde-pi-rc.xml`. To add keys of your own, see [Your own keys](#your-own-keys).

## Wayland session (Debian 13 and later)

On Debian 13 and later, rpios-look installs Raspberry Pi OS's Wayland desktop
too, as a second session: **Raspberry Pi Desktop (Wayland)**. Both sessions
are on the login screen for every user; nothing checks the graphics before
installing or before you pick one.

- **Default:** after installing, your first login goes into Raspberry Pi
  Desktop (X), as before. Pick Raspberry Pi Desktop (Wayland) on the login
  screen to try it; LightDM remembers your pick for later logins. Or run
  `rpios-look-set --session wayland` (and `--session x` to go back).
- **What it runs:** Debian's labwc with Raspberry Pi OS 13's settings
  (`/usr/share/rpios-look/xdg/labwc`), Raspberry Pi's panel (wf-panel-pi and
  its plugins; its settings in `/etc/xdg/wf-panel-pi`, where Raspberry Pi OS
  keeps them), Raspberry Pi's file manager for the desktop, kanshi for the
  screen layout and Raspberry Pi's screen lock (`swaylock-pi`, Ctrl+Alt+L).
  X programs run through Xwayland with the same theme, GTK 2 programs
  included. The on-screen keyboard (Debian's squeekboard) starts only with a
  touch screen, as on Raspberry Pi OS.
- **Power:** the power button opens the Shutdown dialog, and the screen is
  not blanked or locked by itself, as on Raspberry Pi OS.
- **Graphics:** without 3D acceleration (some virtual machines, old cards)
  the session draws in software, as Raspberry Pi OS does on graphics that
  lack it. NVIDIA's own driver can show glitches on Wayland; the X session
  works on every PC. If labwc cannot start at all, you are back on the login
  screen: pick Raspberry Pi Desktop (X).
- **Themes:** PiXtrix, PiXonyx, PiXflat and PiXnoir. PiX is an X theme
  (Raspbian Stretch) and stays in the X session: set there, the Wayland
  session keeps its theme. Every other theme, and `--reset`, is set for both
  sessions at once, from either, as on Raspberry Pi OS; the wallpaper and
  desktop icons are shared too. Your window theme goes to
  `~/.config/labwc/rc.xml` and the cursor to `~/.config/labwc/environment`,
  as Raspberry Pi OS's Appearance Settings keeps them. Debian's own labwc
  session reads these files too: before the first change the script records
  them; `--reset`, a clean install and `--uninstall` remove only the look's
  theme and cursor and put your own back, so changes you made since stay.
- **Differences from Raspberry Pi OS 13:** Raspberry Pi OS uses labwc 0.20,
  which needs newer system libraries than Debian 13 has, so Debian's labwc
  0.8.3 runs instead. With it, window titles and menus show Nunito Sans
  Regular instead of Light, and the Alt+Tab switcher shows no application
  icons. The Control Centre (Appearance and Screen settings) is not
  installed, in either session; use `rpios-look-set`, and kanshi or
  `wlr-randr` for screens. Debian's xsettingsd lacks a Raspberry Pi fix that
  lets Xwayland stop when no X program runs, so it stays loaded once one has
  started (some memory, nothing visible).

Debian 9 to 12 (the legacy script) have the X session only: Debian 12 has no
labwc, and Raspberry Pi's needs newer system libraries than Debian 12's.

## Your own keys

The Raspberry Pi Desktop session has Raspberry Pi OS's keys only (see
[Keys and buttons](#keys-and-buttons)). To add a key or change one, put it in
your own Openbox file, `~/.config/openbox/rpd-rc.xml` (`lxde-pi-rc.xml` on
Debian 9 to 12). Debian's LXDE session has its own file and is not affected.

A `<keyboard>` section in your file **replaces all** of the session's keys; it
does not add to them. So start from a copy of the session's keys:

```sh
s=/usr/share/rpios-look/xdg/openbox/rpd-rc.xml  # Debian 9 to 12: lxde-pi-rc.xml
f=~/.config/openbox/${s##*/}
mkdir -p ~/.config/openbox
grep -q '<keyboard>' "$f" 2>/dev/null || {
  { if [ -f "$f" ]; then sed '/<\/openbox_config>/d' "$f"
    else printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
      '<openbox_config xmlns="http://openbox.org/3.4/rc">'; fi
    sed -n '/<keyboard>/,/<\/keyboard>/p' "$s"
    echo '</openbox_config>'; } >"$f.new" && mv "$f.new" "$f"; }
```

This keeps what your file already holds (such as the window theme) and does
nothing if your file has a `<keyboard>` section already. Then open your file
in a text editor and add your keys inside `<keyboard>`, for example:

```xml
<keybind key="C-A-e">
  <action name="Execute"><command>pcmanfm</command></action>
</keybind>
```

`C` is Ctrl, `A` Alt, `S` Shift and `W` Super. To change one of the session's
keys, edit its `<keybind>` in your copy; to drop one, delete it. Log out and
in again to use the new keys.

- **Super combinations:** as on Raspberry Pi OS, pressing **Super** opens the
  menu at once, so **Super+E** and the like open the menu too. To use them,
  delete the `<keybind key="Super_L">` entry in your copy; **Ctrl+Esc** still
  opens the menu.
- **Your keys stay:** logging in, `--refresh` and `rpios-look-set --theme`
  do not change them. `rpios-look-set --reset` deletes
  your file, keys included, so keep a copy of it.
- **New versions:** while your file has its own `<keyboard>` section, changes
  that a later version makes to the session's keys do not reach you. To take
  them, delete the section and run the command above again.

## Screen, lock and power button

The session does what Raspberry Pi OS's session does and adds nothing of its
own: no helper runs for it, and nothing outside the session is changed.

- **Screen:** in the X session the screen blanks and the monitor switches
  off after 10 minutes without use. These are the X server's own defaults,
  which Raspberry Pi OS leaves as they are. The Wayland session does not
  blank the screen, as Raspberry Pi OS's does not.
- **Lock:** the screen never locks by itself. In the Wayland session
  **Ctrl+Alt+L** locks it with Raspberry Pi's screen lock, and the shutdown
  dialog names the key, as on Raspberry Pi OS 13. The X session has no
  screen lock, as Raspberry Pi OS's has none; to add one, see
  [Lock time](#b-lock-time-x-session).
- **Sleep and lid:** the session never puts the computer to sleep. Closing a
  laptop's lid follows Debian's setting (systemd-logind: sleep).
- **Power button:** see [Keys and buttons](#keys-and-buttons).

To set your own screen-off, lock and sleep times, see
[Your own power settings](#your-own-power-settings).

Screen lockers and screensavers that Debian starts in every session
(light-locker, xscreensaver) are not started in this one, as Raspberry Pi OS
has none. Debian's LXDE session keeps its own settings.

### Your own power settings

The look has no power settings of its own. Debian's own tools set the times
below, on every release from 9 on. `--refresh` keeps what you set here; a
plain run sets A to D aside, as part of
[what it resets](#modes-and-options), and `--uninstall` puts them back. Copy a block into a terminal, change the numbers, then log out
and in again. All times are in **seconds** (300 = 5 minutes, 600 = 10,
1800 = 30, 3600 = 1 hour).

| You want | X session (every release) | Wayland session (13 and later) |
|---|---|---|
| The screen to go off after a time | [A](#a-screen-off-time-x-session) | [D](#d-screen-off-lock-and-sleep-times-wayland-session) |
| The screen to lock after a time | [B](#b-lock-time-x-session) | D |
| The computer to sleep after a time | [C](#c-sleep-time-x-session) | D |
| The lid, power button and sleep key | [E](#e-lid-power-button-and-sleep-key-whole-computer) | E |
| To lock, sleep or shut down now | [F](#f-do-it-now) | F |

In the X session choose **B or C**, not both: once the screen is locked,
Debian does not let the locked session put the computer to sleep. With C the
screen locks at the moment the computer goes to sleep, so it is locked when
it wakes. The Wayland session can do all three.

#### A. Screen-off time (X session)

The screen goes off after 10 minutes. To choose another time (here 300
seconds):

```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/power-times.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Power times
Exec=sh -c "xset s 300 300; xset dpms 300 300 300"
OnlyShowIn=LXDE;
EOF
```

Write the same number in all five places. For a screen that never goes off,
use this line instead: `Exec=xset s off -dpms`

#### B. Lock time (X session)

The screen locks a number of seconds **after it went off** (here 60), and
also when the computer sleeps and when the lid closes. Unlock with your
password at the login screen. Do A first, then:

```bash
sudo apt install light-locker
mkdir -p ~/.config/autostart
sed 's|^Exec=.*|Exec=light-locker --lock-after-screensaver=60 --lock-on-suspend --lock-on-lid|' \
    /etc/xdg/autostart/light-locker.desktop > ~/.config/autostart/light-locker.desktop
```

With A at 300 and this at 60, the screen goes off after 5 minutes and locks
after 6. Once you have logged out and in, `light-locker-command -l` locks
the screen at once; to put that on a key, see [Your own keys](#your-own-keys).

| Part of the line | What it does | To turn it off |
|---|---|---|
| `--lock-after-screensaver=60` | Lock 60 seconds after the screen went off | `--lock-after-screensaver=0` |
| `--lock-on-suspend` | Lock when the computer goes to sleep | `--no-lock-on-suspend` |
| `--lock-on-lid` | Lock when the lid closes | `--no-lock-on-lid` |

#### C. Sleep time (X session)

The screen goes black after the first number of seconds (here 300), and the
computer sleeps the second number of seconds **after that** (here 1500, so
after 30 minutes in all). It is locked when it wakes. This block replaces A
and B:

```bash
sudo apt install xss-lock light-locker
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/power-times.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Power times
Exec=sh -c "xset s 300 1500; xset dpms 0 0 0; exec xss-lock -n true --ignore-sleep -- systemctl suspend"
OnlyShowIn=LXDE;
EOF
sed 's|^Exec=.*|Exec=light-locker --lock-after-screensaver=0 --lock-on-suspend --lock-on-lid|' \
    /etc/xdg/autostart/light-locker.desktop > ~/.config/autostart/light-locker.desktop
```

Change only the two numbers after `xset s`. Until the computer sleeps the
screen is black but the monitor stays switched on; it switches off with the
computer. To wake without a locked screen, delete
`~/.config/autostart/light-locker.desktop`.

**To undo A, B or C**, delete the files and log out and in:

```bash
rm -f ~/.config/autostart/power-times.desktop ~/.config/autostart/light-locker.desktop
```

Both files are also read by Debian's own LXDE session, so the same times
apply there.

#### D. Screen-off, lock and sleep times (Wayland session)

The Wayland session does none of these by itself. One line sets all three;
each time counts from the last use of the mouse or keyboard (here: screen
off after 300 seconds, lock after 600, sleep after 1800):

```bash
sudo apt install swayidle wlopm
mkdir -p ~/.config/labwc
cat >> ~/.config/labwc/autostart <<'EOF'
swayidle -w timeout 300 'wlopm --off \*' resume 'wlopm --on \*' timeout 600 'swaylock -f' timeout 1800 'systemctl suspend' before-sleep 'swaylock -f' &
EOF
```

| Part of the line | What it does |
|---|---|
| `timeout 300 'wlopm --off \*' resume 'wlopm --on \*'` | Screen off after 300 seconds, on again at the next key or mouse move |
| `timeout 600 'swaylock -f'` | Lock after 600 seconds |
| `timeout 1800 'systemctl suspend'` | Sleep after 1800 seconds |
| `before-sleep 'swaylock -f'` | Lock whenever the computer goes to sleep |

Leave out the parts you do not want. To change it later or undo it, edit
`~/.config/labwc/autostart` and change or delete the line. Debian's own
labwc session runs this file too.

#### E. Lid, power button and sleep key (whole computer)

These are Debian's system settings (systemd-logind), for every user and
every session. Write only the lines you want to change; the values shown are
Debian's defaults:

```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/power.conf >/dev/null <<'EOF'
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore
HandlePowerKey=poweroff
HandleSuspendKey=suspend
HandleHibernateKey=hibernate
EOF
```

Then restart the computer.

| Line | When |
|---|---|
| `HandleLidSwitch` | The lid closes |
| `HandleLidSwitchExternalPower` | The lid closes while the charger is connected (Debian 10 and later) |
| `HandleLidSwitchDocked` | The lid closes while a second screen or a dock is connected |
| `HandlePowerKey` | The power button is pressed |
| `HandleSuspendKey` | The sleep key is pressed |
| `HandleHibernateKey` | The hibernate key is pressed |

| Value | What the computer does |
|---|---|
| `ignore` | Nothing |
| `lock` | Lock the screen (X session only; needs B or C) |
| `suspend` | Sleep |
| `hibernate` | Save to disk and switch off (needs swap space as large as the memory) |
| `poweroff` | Shut down |
| `reboot` | Restart |

Where the Raspberry Pi Desktop session opens the Shutdown dialog on the
power button (see [Keys and buttons](#keys-and-buttons)), `HandlePowerKey`
applies only outside that session, such as at the login screen. To undo,
delete the file (`sudo rm /etc/systemd/logind.conf.d/power.conf`) and
restart.

#### F. Do it now

| To | Command |
|---|---|
| Lock the screen (X session, needs B or C) | `light-locker-command -l` |
| Lock the screen (Wayland session) | `swaylock` |
| Switch the screen off (X session) | `xset dpms force off` |
| Sleep | `systemctl suspend` |
| Hibernate | `systemctl hibernate` |
| Shut down | `systemctl poweroff` |
| Restart | `systemctl reboot` |
| Show the X session's current times | `xset q` |

## Updating, upgrading and uninstalling

**Update**, keeping your settings:

```bash
bash rpios-look.sh --refresh
```

Every run checks online, and `--refresh` lists before asking (default answer:
no):

- newer versions of every Raspberry Pi package the look installed;
- new looks for your release or an earlier one: themes, icon and cursor sets,
  fonts, wallpaper sets;
- new panel plugins of Raspberry Pi OS's desktop; another new desktop
  program gets a note, not an unchecked install;
- packages that are no longer part of the look, offered for removal;
- a newer version of the script itself, as a one-line note with the command
  to get it (it is never downloaded or run by itself).

`sudo apt update && sudo apt upgrade` also updates the Raspberry Pi
packages that the look uses unchanged (themes, icons, fonts, wallpapers,
panel plugins, dialogs). Those repacked to install beside Debian's (see
[Keeping Debian safe](#keeping-debian-safe)) and the Bluetooth plugin with
its fix come with `--refresh`, which also lists Debian's updates for the
session's packages. If APT ever removes a package of the look (a Debian
update that needs it gone), it says so after installing; `--refresh` brings
it back.

**Upgrade Debian** to its next release. Debian upgrades itself; the
rpios-look script never checks for a new release. Always uninstall the
rpios-look script first and run a clean install afterwards:

1. Uninstall the rpios-look script: `bash rpios-look.sh --uninstall` (on
   Debian 9 to 12: `bash rpios-look-legacy.sh --uninstall`). Debian is back
   to its own LXDE setup.
2. Upgrade Debian as usual and restart.
3. Run a clean install for the new release: `bash rpios-look.sh` (on Debian
   10 to 12: `bash rpios-look-legacy.sh`).

`--refresh` only updates the packages of the release that is installed, from
Debian's and Raspberry Pi's repositories. A newer Raspberry Pi OS release
comes only with a clean install.

If you upgraded Debian with the rpios-look script still installed, Debian's
own sessions keep working, and the Raspberry Pi Desktop session may miss
parts. Run `--uninstall` (it works on any release), then a clean install.

The two scripts never take over each other's install. If one of them
installed the rpios-look script, the other one stops and asks you to
uninstall it first.

**Uninstall:**

```bash
bash rpios-look.sh --uninstall
```

It lists what it removes and asks first. It removes both sessions, the
login screen style, Raspberry Pi's APT source and the programs repacked
beside Debian's, and restores your settings and every user's choice of
session; other users keep their settings. In files that Debian's sessions
read too (labwc's, LXTerminal's), only what the script set goes back. The
network and Bluetooth tools it added (NetworkManager, wpa_supplicant, BlueZ
and their helpers) are removed, so that your network setup from before the
install is back after the restart. A second question removes the other
packages it installed, with the libraries they brought in; packages you had
before or installed by name since, and those other software needs, stay.
Wi-Fi firmware is asked about separately (default: keep). Packages you keep
stay recorded, so that a later `--uninstall` of either script can remove
them, and either script installs again. It also undoes an installation
made by `rpios-look-legacy.sh`. Your files and folders are never
touched. Restart to finish. Where the look is not installed, it says so and
changes nothing.

## Supported systems

| Debian | PCs | Panel and file manager | Default theme |
|---|---|---|---|
| 13 (trixie) | 64-bit | Raspberry Pi OS 13 | PiXtrix |
| later releases | 64-bit | the newest Raspberry Pi OS release | Raspberry Pi OS's |
| testing, unstable | 64-bit | the newest Raspberry Pi OS release | Raspberry Pi OS's |

- The script runs on Debian itself with Debian's LXDE installed, and stops
  before changing anything otherwise. The X session runs on Openbox, the
  Wayland session on labwc.
- **New releases.** The script learns Debian's releases from Debian's own
  table online (kept for a day), then from `distro-info-data`, then from its
  built-in list. If Raspberry Pi OS ships a desktop the script does not know
  yet, it installs the looks it can use and says that a newer script is
  needed.
- **Testing and unstable** use the newest Raspberry Pi OS release and change
  daily; they are supported on a best-effort basis.
- **Older releases.** When a newer Debian stable release exists, the script
  warns before it starts, says when Debian's security support ends or ended,
  and repeats it in the summary.
- **Network icon.** Raspberry Pi's network item is used when NetworkManager
  manages the network and Raspberry Pi OS has a matching build of `libnma`.
  Otherwise only a network icon you already have (such as nm-applet) appears
  in the tray: the script installs none, as Debian's tray icons start in
  every session. NetworkManager and the Wi-Fi tools are installed only for
  that item, on a computer with Wi-Fi and no other network manager; where
  the item is left out, they are not.

When a new Debian stable release comes out, support for the previous one is
frozen (fixes only) in a separate script, as for Debian 9 to 12.

## Troubleshooting

- **The look is missing after login.** Select *Raspberry Pi Desktop* in the
  login screen's session menu.
- **The login screen is not styled.** The script styles LightDM, which
  Debian's LXDE uses. Another login manager (GDM, SDDM, LXDM) is left as it
  is. To switch: `sudo apt install lightdm lightdm-gtk-greeter && sudo
  dpkg-reconfigure lightdm`, then `bash rpios-look.sh --refresh`.
- **"dpkg was interrupted".** A package installation stopped half-way; the
  script changes nothing. Finish it with
  `sudo dpkg --configure -a && sudo apt-get -f install`, then run it again.
- **Something looks incomplete.** `bash rpios-look.sh --refresh`.
- **The theme looks wrong after a change.** `rpios-look-set --reset`, or set
  the theme again.
- **The microphone is unmuted after logging out and in.** WirePlumber's
  behaviour, the same on Raspberry Pi OS 13. Mute it again after logging in.

For more detail, add `--verbose` and read the log in your home folder.

## How it works

### Themes

All themes of the release are installed (see
[Looks per release](#looks-per-release)), each with the icons, cursor, font,
window frames and wallpaper that Raspberry Pi OS gives it. Where Raspberry Pi
OS shows its logo (the menu button, the login screen's user picture), the
session shows the Debian logo: a white swirl on a red circle.

### Qt and GNOME programs

The desktop itself is GTK. For Qt programs (such as VLC), the script installs
the Qt style plugins Raspberry Pi OS 13 uses, `qt5-style-plugins` and
`qt6gtk2`, so that Qt programs follow the GTK theme.

- **Qt versions:** Raspberry Pi's builds are made for Debian 13's Qt. Where
  Debian has a newer Qt (testing, unstable), Qt 5 and Qt 6 programs follow
  the GTK theme through Debian's own `qt5-gtk-platformtheme` and
  `qt6-gtk-platformtheme` instead, which Raspberry Pi OS 13 also installs.
- **Session only:** one setting, `QT_QPA_PLATFORMTHEME=gtk2` (`gtk3` with
  Debian's themes), in the Raspberry Pi Desktop session. Nothing
  system-wide, nothing running in the background; other sessions are not
  changed. `qt5ct` is not used, because Debian's
  `qt5ct` changes every X session.
- **Size:** the plugins are about 1.4 MB. The Qt libraries they need come with
  them as dependencies, about 59 MB on a system without Qt (an estimate from
  Debian's package index).
- **Uninstall:** removes the plugins and the Qt libraries the install brought
  in, only where nothing else uses them: APT checks every installed package
  first, so Qt programs you installed keep their libraries and keep working,
  in Qt's own style. Qt libraries you had before, or installed by name since
  (`sudo apt install libqt5gui5t64`, for a program APT does not know of),
  stay. It never runs `apt autoremove`.

GNOME programs built with libadwaita (Text Editor, Calculator and others)
always draw GNOME's Adwaita style, by GNOME's design, as on Raspberry Pi OS.
They follow the theme's light or dark style (see
[rpios-look-set](#changing-the-look-rpios-look-set)).

### Keys and buttons

As on Raspberry Pi OS 13, from its own Openbox settings:

| Key | Action |
|---|---|
| **Super**, **Ctrl+Esc** | Main menu |
| **Alt+F2** | Run a command |
| **Ctrl+Alt+T** | Terminal |
| **Ctrl+Shift+Esc** | Task manager |
| **Ctrl+Alt+Delete**, **Ctrl+Alt+End** | Shutdown dialog |
| **Print** | Screenshot with `scrot`, if present |
| **Ctrl+Alt+Left/Right** | Window to the left or right half |
| **Ctrl+Alt+Up/Down** | Maximize, restore |
| **Ctrl+Alt+D** | Show the desktop |
| **Alt+F11** | Full screen |
| **Ctrl+Alt+B** | Bluetooth menu |
| **Ctrl+Alt+W** | Network menu (Raspberry Pi's network item) |
| **Ctrl+Alt+M** | Magnifier, once added to the panel (Panel Preferences → Add) |
| **Ctrl+Alt+L** | Lock the screen, in the Wayland session only (as on Raspberry Pi OS 13) |
| Volume keys | Volume, through the panel |

The terminal is LXTerminal, unless you chose another with
`sudo update-alternatives --config x-terminal-emulator`.

- The power button: open the shutdown dialog; press again to shut down, as
  Raspberry Pi OS 12 and later do (on Debian 9 to 11, as Raspberry Pi OS 9
  to 11, systemd-logind handles it, as in Debian's session). Some older
  laptops do not report a short press; there, only a long press (forced
  power-off) works.

Of the keys that Raspberry Pi OS leaves unbound, only one that Debian's LXDE
binds is added: the display key of laptops (`XF86Display`) opens the display
settings (LXRandR). Debian's other LXDE keys (such as **Super+E**) are not:
Raspberry Pi OS's **Super** key opens the menu, and it leaves the rest to
programs. Keys that neither binds, such as the lock and wireless keys of
laptops, stay unbound. To add your own, see
[Your own keys](#your-own-keys).

While the session runs, systemd-logind leaves the power button to it, also
while its screen is locked or another user's session is in front, as on
Raspberry Pi OS; a long press still forces the power off. Without the session
(at the login screen), the power button and the lid follow Debian's settings.

### Compared with Raspberry Pi OS

**The same as on Raspberry Pi OS:**

- the themes with their icons, cursors, fonts, window frames and default
  wallpaper, and the defaults of each release;
- the panel with its layout, main menu and items (clock, volume, Bluetooth,
  network, eject), and the desktop with its file manager;
- the window manager's behaviour, rounded corners included, and the keys;
- the Shutdown and Run dialogs, and the power button opening the Shutdown
  dialog (Debian 12 and later);
- the size presets Small, Medium, Large and Larger of Appearance Settings;
- Qt programs following the GTK theme, and the light or dark style of GTK 4
  programs (Debian 13 and later);
- the Wayland session (Debian 13 and later): labwc with Raspberry Pi OS's
  settings, its panel, its screen lock on Ctrl+Alt+L, the on-screen keyboard
  with a touch screen;
- no automatic screen lock or sleep, and no screen blanking beyond the X
  server's own;
- the login screen's style.

The packages behind this are listed under [Packages](#packages).

**From Raspberry Pi OS:** the theme, icon, cursor, font and wallpaper
packages; the panel (`lxpanel-pi` with its `lpplug-*` plugins), the file
manager and desktop (`pcmanfm-pi`), the window
manager (Raspberry Pi's build of `openbox`, with its rounded corners while
windows move), the dialogs (`pishutdown`, `gui-runcmd`), the Qt style
plugins. Those that would clash with Debian's packages are installed beside
them (see [Keeping Debian safe](#keeping-debian-safe)).
The panel layout, menu, desktop and window settings are read from Raspberry Pi
OS's `rpd-*` packages, which are not installed.

**From Debian:** the system services (BlueZ, NetworkManager, PipeWire,
udisks, systemd-logind), the applications, lxsession, LightDM with Debian's
greeter and the authentication agent, as Raspberry Pi OS uses them too; and
the SSH agent, as in Debian's LXDE (Raspberry Pi OS's
lxsession settings start a second one, which nothing uses).

**Differences** (here; Raspberry Pi OS):

- **Resizing a window:** contents redraw while dragging, as in Debian's LXDE;
  Raspberry Pi OS: blank until the mouse is released.
- **Double click on a title bar (X session):** counted within 400 ms, as
  GTK's programs count one; Raspberry Pi OS and Debian's LXDE: 200 ms.
- **Menu button and login logo:** Debian logo; Raspberry Pi OS: Raspberry Pi
  logo.
- **Login screen:** Debian's LightDM greeter in Raspberry Pi OS's style;
  Raspberry Pi OS: Raspberry Pi's greeter.
- **File manager, Openbox, libnma:** Raspberry Pi's, beside Debian's
  (Debian's sessions keep Debian's); Raspberry Pi OS: Raspberry Pi's only.
- **Terminal:** Debian's LXTerminal; Raspberry Pi OS: Raspberry Pi's build,
  which shows bold text in bright colours.
- **Settings shared with Debian's sessions:** the file manager, terminal,
  bookmarks and default apps keep your settings in the same files in both
  sessions, so a change made in one shows in the other. This includes the
  terminal font that `--size small|large|larger` sets. Raspberry Pi OS has
  one session only.
- **Translations of Raspberry Pi's repacked programs:** Debian's (the same
  message catalogues); a message that only Raspberry Pi's build has shows in
  English.
- **Wallpapers:** every set of the release and earlier ones, 4K and Cambridge
  included, in folders; Raspberry Pi OS: its own sets, in one folder.
- **raspi-config, updater, Raspberry Pi Connect, panel power item, GPU
  monitor:** not installed (they need Raspberry Pi hardware). The on-screen
  keyboard is in the Wayland session only, with a touch screen.
- **Dark themes in Geany, Galculator and Mousepad:** not set. Raspberry Pi
  OS's Appearance Settings writes them into those programs' own settings,
  which Debian's sessions read too.
- **Magnifier:** installed (plugin and program) but not on the panel; add it
  from the panel's right-click menu. Raspberry Pi OS installs the plugin but
  not the program.
- **`rpios-look-set`:** included; Raspberry Pi OS has no such command.
- **Qt settings tools (`qt5ct`, `qt6ct`):** not installed; Qt programs are
  styled through one session setting instead.

Raspberry Pi's programs are used unchanged, with one fix: the PIN field of
the Bluetooth pairing dialog takes keyboard focus, so Bluetooth 2.0 devices
can be paired. The fix applies only while Raspberry Pi's dialog still has the
bug. Those repacked beside Debian's keep their code; only the names of their
program, folders and libraries change.

### Packages

Every run lists the packages it will install, with versions and origins,
before it changes anything. This is the full set, for every release; 32-bit
and 64-bit PCs get the same packages (Debian 13 and later are 64-bit only).

**From Raspberry Pi OS** (Raspberry Pi's archive, `archive.raspberrypi.org`):

| Package | Debian | What it is for |
|---|---|---|
| `pixtrix-theme` | 13+ | The PiXtrix and PiXonyx themes: GTK 2, 3 and 4, window frames, the session's defaults |
| `pixflat-theme` | 10+ | The PiXflat and PiXnoir themes, the same way |
| `pix-theme` | all | The PiX theme of Raspbian Stretch |
| `pixtrix-icons`, `pixflat-icons`, `rpd-icons` | 13+, 10+, all | The icon and cursor sets of PiXtrix, PiXflat and PiX |
| `gtk2-engines-pixflat`, `gtk2-engines-clearlookspix` | 10+, all | The drawing engines that the PiXflat and PiX themes need in GTK 2 programs |
| `fonts-nunito-sans`, `fonts-piboto` | 13+, all | The desktop fonts: Nunito Sans (PiXtrix), Piboto (PiXflat, PiX) |
| `rpd-wallpaper`, `rpd-wallpaper-trixie` | all, 13+ | Raspberry Pi OS's wallpapers, the default one among them |
| `rpd-wallpaper-4k`, `rpd-wallpaper-trixie-4k`, `cantab-wallpaper` | 11+, 13+, all | More wallpapers to pick from: 4K copies and the Cambridge set. Raspberry Pi OS does not install these by default |
| `openbox`, `libobrender32v5` ¹ | all | Raspberry Pi's build of the window manager: windows keep rounded corners while they move |
| `lxpanel-pi` | 13+ | Raspberry Pi's panel |
| `lxpanel`, `lxpanel-data` ¹ | 9 to 12 | Raspberry Pi's build of the panel, which its plugins need |
| `lpplug-menu`, `-clock`, `-ejecter`, `-volumepulse`, `-bluetooth`, `-netman` ² | 13+ | The panel's items: main menu, clock, eject, volume, Bluetooth, network |
| `lpplug-cpu`, `-cputemp`, `-magnifier`, `-batt` ³ | 13+ | Panel items to add by hand (CPU load, temperature, magnifier) and the battery item |
| `lxplug-menu` (11, 12), `-ejecter` (10 to 12), `-volumepulse` (10 to 12), `-volume` (9), `-bluetooth`, `-netman` ² (12) | 9 to 12 | The same panel items, as each release has them |
| `lxplug-cpu` (12), `-cputemp` (10 to 12), `-magnifier` (10 to 12), the battery item ³ | 9 to 12 | The same items to add by hand, and the battery item |
| `pplug-ejecter-data`, `pplug-netman-schema` | 13+ (schema: 12+) | Data and settings that the eject and network items need |
| `mage-rpi` (10, 11: `mage`) | 10+ | The magnifier program that the magnifier item and Ctrl+Alt+M start |
| `pcmanfm-pi` ¹ | 13+ | Raspberry Pi's file manager, which also draws the desktop |
| `pcmanfm`, `libfm4`, `libfm-gtk4`, `libfm-modules`, `libfm-data`, `libfm-gtk-data`, `libfm-extra4` ¹ | 9 to 12 | Raspberry Pi's build of the file manager and its library |
| `pishutdown` | all | The Shutdown dialog |
| `gui-runcmd` | 13+ | The Run dialog (Alt+F2) |
| `libnma0` ¹, `lp-connection-editor` ² | 12+ | The network item's library and its connection editor |
| `wf-panel-pi` | 13+ | Raspberry Pi's panel of the Wayland session |
| `wfplug-menu`, `-imenu`, `-wlist`, `-clock`, `-ejecter`, `-volumepulse`, `-bluetooth`, `-netman` ², `-cpu`, `-cputemp`, `-squeek`, `-batt` ³ | 13+ | Its items: menu, launchers, window list, clock, eject, volume, Bluetooth, network, CPU load and temperature, on-screen keyboard, battery |
| `swaylock` ¹ | 13+ | Raspberry Pi's screen lock of the Wayland session (Ctrl+Alt+L) |
| `gui-screenshot` | 13+ | The screenshot tool of the Wayland session (Print) |
| `qt5-style-plugins`, `qt5-gtk2-platformtheme`, `qt5-style-plugin-cleanlooks`, `-motif`, `-plastique`, `qt6gtk2` | 13 | Qt 5 and Qt 6 programs follow the GTK theme (Raspberry Pi's builds for Debian 13's Qt) |

¹ Repacked to install beside Debian's package of the same name (see
[Keeping Debian safe](#keeping-debian-safe)). ² Only where NetworkManager
manages the network. ³ Only on a computer with a battery.

Read but not installed: `rpd-common`, `rpd-x-core` and `rpd-wayland-core`
(13 and later) and `raspberrypi-ui-mods` (9 to 12), for Raspberry Pi OS's
panel layout, keys, menu and labwc settings. `raspberrypi-archive-keyring` is
downloaded for the key that verifies Raspberry Pi's archive.

**From Debian** (your own APT sources; a package you already have is left as
it is):

| Package | Debian | What it is for |
|---|---|---|
| `lxsession`, `lxpolkit` | all | The session manager and the password prompt, as Raspberry Pi OS uses them |
| `openbox`, `lxpanel`, `pcmanfm` | all | Debian's LXDE, which the look is installed beside; Debian's own session keeps using them |
| `gvfs-backends`, `gvfs-fuse` | all | Removable drives, network folders and the trash in the file manager |
| `lxappearance` | all | Customize Look and Feel, in place of Raspberry Pi's Appearance Settings |
| `dconf-cli`, `libglib2.0-bin`, `python3` | all | Used by the session's own helpers to apply the look's settings and keep them |
| `xserver-xorg`, `x11-utils`, `libgl1-mesa-dri` | all | The X server, where missing |
| `lightdm`, `lightdm-gtk-greeter`, `desktop-base` | all | The login screen, where no other login manager is in use |
| `gtk2-engines-pixbuf`, `libgtk2.0-bin` | all | GTK 2 support that the themes need |
| `gnome-icon-theme`, `adwaita-icon-theme-legacy` (13+) | all | Icons that the Raspberry Pi icon sets fall back to |
| `sound-theme-freedesktop` | all | The event sounds |
| `fonts-liberation` (13+), `fonts-liberation2` (9 to 12) | all | Liberation Mono, the monospace font |
| `pipewire-audio` (12+), `pulseaudio` (10, 11) | 10+ | Sound, on a computer with a sound card and no sound server |
| `bluez`, `rfkill`, `libspa-0.2-bluetooth` or `pulseaudio-module-bluetooth` | all | Bluetooth for the panel's item, on a computer that has it |
| `network-manager`, `wpasupplicant`, `iw`, `wireless-regdb`, `rfkill`, `dnsmasq-base` | 12+ | Wi-Fi for Raspberry Pi's network item, only on a computer with Wi-Fi and no network manager |
| `labwc`, `kanshi`, `wlr-randr`, `xsettingsd`, `squeekboard` | 13+ | The Wayland session: compositor, screen layout, GTK settings for X programs, on-screen keyboard |
| `qt5-style-plugins` (9, 10, 12), `qt5-gtk-platformtheme` (11) | 9 to 12 | Qt 5 programs follow the GTK theme |
| `qt5-gtk-platformtheme`, `qt6-gtk-platformtheme` | testing, unstable | The same, where Raspberry Pi's Qt plugins do not fit Debian's newer Qt |
| `debian-reference-common`, `debian-reference-en` | 9 to 12 | Debian Reference in the Help menu, as on Raspberry Pi OS 9 to 12 |
| `fakeroot`, `apt-transport-https` | 9 | Needed on Debian 9 to build packages and to reach Raspberry Pi's archive; removed by `--uninstall` |

APT adds the libraries these packages depend on; the plan and the log of
each run name them.

### What changes on the computer

- **Raspberry Pi Desktop:** a new session; on Debian 13 and later a second
  one, Raspberry Pi Desktop (Wayland), with Debian's labwc and its Wayland
  tools (kanshi, Xwayland, xsettingsd, squeekboard and others) and
  Raspberry Pi's panel and screen lock (repacked as `swaylock-pi`, beside
  Debian's swaylock). Debian's own labwc session is not changed;
  `rpios-look-set` writes only a look's window theme and cursor into your
  labwc files, which that session reads too, and `--reset` and
  `--uninstall` give back your own.
- **Debian's LXDE:** not changed: Debian's own Openbox, panel and file
  manager, settings, autostart, screen lock and power.
- **Login screen:** LightDM and its greeter are installed where no other
  login manager is in use, and the greeter gets Raspberry Pi OS's style.
- **Packages:** the Raspberry Pi OS packages above; the Debian packages the
  session needs, including hardware support (X server, network, Bluetooth,
  sound) where missing. Packages already installed are not changed.
- **System files:** Raspberry Pi's APT source, pinned to the look's
  packages, with a check after each APT run that names any of them it
  removed; an X session file that gives only the Raspberry Pi Desktop
  session its own settings database (dconf) from the start, so that the
  input method (IBus) reads it too and shows no tray icon, as on Raspberry
  Pi OS.

### Keeping Debian safe

The scripts follow Debian's
[DontBreakDebian](https://wiki.debian.org/DontBreakDebian) guidance:

- No Debian package, file or session is changed. Raspberry Pi's builds of
  Debian's packages (Openbox with `libobrender`, `libnma` for its network
  plugin, the file manager and, on Debian 13, the screen lock) are repacked
  to install beside Debian's: own package names (`rpios-look-openbox`, ...),
  programs (`openbox-pi`, `pcmanfm-pi`, `swaylock-pi`), data folders
  (`/usr/share/pcmanpi`) and
  library names (`libobrender-pi.so`, `libnmapi.so`),
  written into their programs in place. No environment variable is set: a
  Debian program never loads a Raspberry Pi library and the other way round,
  so Debian's `obconf` and `lxappearance-obconf` keep working with Debian's
  Openbox libraries. Only the Raspberry Pi Desktop session starts them.
  Translations, icons and menu entries that Debian's packages already have,
  and Raspberry Pi's system extras (services, autostart entries, maintainer
  scripts), are left out of the repacked packages.
- APT takes from Raspberry Pi's archive only the packages the look uses
  unchanged; everything else there is blocked. The repacked packages are
  updated by `--refresh` only, never by APT.
- Packages that would replace, break or conflict with Debian packages are
  refused at an install and at `--refresh`.
- Debian packages come only from your own APT sources.
- Archives are verified against their signing keys, and every package against
  its SHA256 checksum.
- The plan lists every package before anything changes.
- Every change is recorded; `--uninstall` undoes it.

## Tests

The release tests are described in [tests/TEST-PLAN.md](tests/TEST-PLAN.md)
and their results are recorded in [tests/HISTORY.md](tests/HISTORY.md).
Unit tests of the scripts' decision helpers need no root or network; one of
them checks that the code both scripts share is the same in both:

```bash
sudo apt install bats
bats tests/
```

## Related

- [LEGACY.md](LEGACY.md): `rpios-look-legacy.sh` for Debian 9 to 12, 32-bit
  and 64-bit, with offline installation.
- [thinkpad-acpi-fix](https://github.com/b1ack0p/thinkpad-acpi-fix): fixes for
  older ThinkPads whose volume buttons, sound or beeps do not work (firmware
  volume). Not part of the look.

## Disclaimer

**Use at your own risk.** rpios-look installs packages and changes system
files as root. It is provided "as is", without warranty of any kind, as the
[MIT licence](LICENSE) states. The authors and contributors accept no
responsibility or liability for any damage or loss, including a broken or
unbootable system, lost data, security issues, or problems caused by the
packages it installs, by Raspberry Pi's or Debian's archives, or by the
Debian release it runs on.

**Old Debian releases.** Releases older than the current stable one may have
reached the end of Debian's security support, and the Raspberry Pi OS
packages made for them may no longer be updated. They may contain known
security vulnerabilities that will never be fixed. The scripts warn about
this when they run; using them on such a release is your own choice and risk.

Every mode that changes the computer prints this warning before it starts.
Back up your data first, and read the plan before answering `y`.

## Credits and licence

The themes, icons, fonts, wallpapers and desktop settings are the work of
[Raspberry Pi Ltd](https://www.raspberrypi.com/) and the Raspberry Pi desktop
team. This project installs their official packages on Debian. All artwork
keeps its own licence (see `/usr/share/doc/<package>/copyright`).

The scripts are released under the MIT licence; see [LICENSE](LICENSE).
