# update-claude

Unofficial bash script to install and update **Claude Desktop** on Linux distributions not officially supported by Anthropic (e.g. Arch, CachyOS, Manjaro, Fedora and derivatives), without relying on third-party packages.

The script downloads the official `.deb` directly from Anthropic's apt repository (`downloads.claude.ai`), extracts it into a local folder, and keeps the application menu shortcut up to date.

## ⚠️ Disclaimer

- This project is **not affiliated with Anthropic** in any way.
- The downloaded package is the **official** one distributed by Anthropic for Debian/Ubuntu — this script only extracts and runs it on other distros, without modifying its contents.
- Use at your own risk. Read the code before running it, as you should with any script found online.
- Works on any Linux distro with the tools listed below. Menu integration is best on **KDE Plasma** (tested on CachyOS/Arch, Plasma 6); on GNOME-based distros (e.g. Fedora Workstation) it falls back to the standard `update-desktop-database` mechanism, which should still register the app in the menu after your next login.

## Requirements

- `curl`
- `binutils` (provides `ar` and `strings`)
- `tar`
- A supported terminal emulator for the auto-relaunch feature: `konsole`, `gnome-terminal`, `xfce4-terminal`, `kitty`, `alacritty`, `foot`, or `xterm`

These are standard tools available by default or via your package manager on virtually every distro (Arch, Fedora, openSUSE, Debian-based, etc.).

## Installation

```bash
git clone https://github.com/subnaut5482/update-claude.git
cd update-claude
chmod +x update-claude.sh
```

## Usage

Run the script whenever you want to check for and install updates:

```bash
./update-claude.sh
```

On first run, it installs Claude Desktop from scratch into `~/Claude`. On subsequent runs, it checks whether a newer version is available and, if so, automatically replaces the existing installation.

You can also double-click it from your file manager: the script detects if it's not attached to a terminal and reopens itself in one, so you always see the output.

### Custom install directory

By default the app is installed into `~/Claude`. To use a different path:

```bash
CLAUDE_INSTALL_DIR="$HOME/apps/claude" ./update-claude.sh
```

## How it works

1. Downloads the `Packages` index from Anthropic's official apt repository and finds the latest available version (sorting with `sort -V` correctly handles major version bumps, e.g. `1.x` → `2.x`).
2. Detects the currently installed version, trying in order:
   - the tracking file created by the script itself
   - `dpkg` (if installed via apt on Debian/Ubuntu)
   - `pacman` (if installed via an AUR package on Arch-based distros)
   - `rpm` (if installed via an unofficial dnf/rpm repo on Fedora/RHEL)
   - a version string extracted from `app.asar` (for manual installations)
3. If the remote version isn't newer than the installed one, it does nothing (downgrade protection).
4. Otherwise, it downloads the `.deb`, extracts it, and replaces the install directory.
5. Restores SUID permissions on `chrome-sandbox` (requires `sudo`).
6. Updates the `.desktop` file and icons in the application menu, and rebuilds the KDE Plasma cache if available (`kbuildsycoca6`/`kbuildsycoca5`), with a `update-desktop-database` fallback for other desktop environments.

## License

[MIT](LICENSE) — see the file for details. Claude and Claude Desktop are trademarks of Anthropic; this project has no official affiliation.
