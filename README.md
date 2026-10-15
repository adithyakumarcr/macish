# like_a_mac

Make Ubuntu look like macOS Tahoe, one part at a time. Run the installer, tick the parts you
want (login screen, app icons, Control Center, dock, ...), and it sets them up. Every part can
be removed again, and removing it puts your earlier settings back.

Made for **Ubuntu 24.04 with GNOME 46** (the default Ubuntu desktop). Most parts also work on
other GNOME versions; the installer leaves out the ones that don't.

## Install

```sh
git clone https://github.com/adithyakumarcr/like_a_mac.git
cd like_a_mac
./install.sh
```

A checklist opens: <kbd>Space</kbd> ticks or unticks a part, <kbd>Enter</kbd> starts. Run it as
yourself, **not** with `sudo`; it asks for your password once if packages need installing (and
for the login screen). When it's done, log out and back in (on X11 you can also press
<kbd>Alt</kbd>+<kbd>F2</kbd>, type `r`, <kbd>Enter</kbd>).

## The parts

| Part | id | What it changes |
|---|---|---|
| Apps & windows | `app-theme` | [MacTahoe](https://github.com/vinceliuice/MacTahoe-gtk-theme) theme for apps and title bars, with extra contrast for sidebars and lists |
| Window buttons on the left | `window-buttons` | close, minimize, maximize on the left |
| App icons | `icons` | [MacTahoe](https://github.com/vinceliuice/MacTahoe-icon-theme) icons; [MacOS-Like](https://github.com/Scrimas/MacOS-Like) puts every other app on a matching tile |
| Mouse pointer | `cursors` | [WhiteSur cursors](https://github.com/vinceliuice/WhiteSur-cursors) |
| Fonts | `fonts` | Inter (closest free font to Apple's SF Pro) for menus, windows and title bars |
| Top bar | `top-bar` | slim menu bar, clock on the right, no Activities button, a menu with About / Force Quit / power options, see-through blur when no window touches it |
| Control Center | `control-center` | Quick Settings restyled like macOS Control Center (same cards as the notification panel), media tile |
| Dock | `dock` | at the bottom, hides when a window needs the space, dots under open apps, blurred background, "genie" minimize |
| Downloads stack | `downloads-stack` | a Downloads stack next to the Trash: previews your newest files, click for a grid (GNOME 46 + Ubuntu Dock) |
| Wallpaper | `wallpaper` | Tahoe wallpaper: day in Light mode, night in Dark mode |
| Terminal | `terminal` | Terminator dressed as macOS Terminal "Pro" with frosted glass (off by default) |
| Login screen | `login-screen` | dark macOS-style login screen (off by default; changes a system file, needs your password) |

**Light and Dark:** switch in Settings → Appearance as usual. A small user service
(`like-a-mac-sync`) switches the app theme, icons, top bar and Control Center with it.

## More options

```sh
./install.sh --list                      # the parts and which are installed
./install.sh --only icons,dock,top-bar   # install just these, no menu
./install.sh --all                       # everything this computer supports
./install.sh --uninstall                 # choose what to remove
./install.sh --uninstall --all           # remove everything
```

`-y` skips the "Continue?" question. Upstream projects are pinned to the versions this was
tested with; `LIKE_A_MAC_LATEST=1 ./install.sh` uses their newest versions instead.

## What it touches

- Themes, icons and extensions go into your home folder (`~/.themes`, `~/.local/share/...`).
  Extensions come from [extensions.gnome.org](https://extensions.gnome.org): User Themes,
  Blur my Shell, Just Perfection, Logo Menu, Compiz alike Magic Lamp Effect, Quick Settings Tweaks.
- Settings are changed with `dconf`; the old value of every key is saved in
  `~/.local/share/like-a-mac/saved/` and put back on uninstall.
- `sudo` is used only for `apt install` (`git sassc libglib2.0-dev-bin libxml2-utils python3-pil
  librsvg2-bin rsync fonts-inter terminator`, only those a chosen part needs) and for the login
  screen, which adds its own theme under `/usr/share/gnome-shell/theme/MacTahoe-GDM` and points
  Ubuntu's `gdm-theme.gresource` setting at it. Ubuntu's own theme file is never modified.

**If the login screen ever doesn't appear:** press <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F3</kbd>,
log in, run `./install.sh --uninstall --only login-screen` from this folder, then `sudo reboot`.

## Notes

- **App icons:** installed an app later and its icon doesn't match? Run
  `~/.local/share/like-a-mac/src/MacOS-Like/setup.sh --source MacTahoe-Bold`.
- **Apps that were already open** keep their old look until you restart them.
- **SF Mono** (Apple's terminal font) can't be shared here. If you have it, put the `.otf`
  files in `fonts/sf-mono/` before installing the Terminal part and it will be used.
- Logs from each part are in `~/.local/share/like-a-mac/`.

## Credits

Built on [MacTahoe GTK theme](https://github.com/vinceliuice/MacTahoe-gtk-theme),
[MacTahoe icons](https://github.com/vinceliuice/MacTahoe-icon-theme) and
[WhiteSur cursors](https://github.com/vinceliuice/WhiteSur-cursors) by vinceliuice,
[MacOS-Like](https://github.com/Scrimas/MacOS-Like) by Scrimas, and the GNOME extensions
listed above by their authors. Not affiliated with Apple.

## License

GPL-3.0 (see [LICENSE](LICENSE)), the same as MacTahoe, which the login screen theme in
`assets/login-screen/` is built from.
