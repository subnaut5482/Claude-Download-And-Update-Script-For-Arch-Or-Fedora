#!/usr/bin/env bash
# aggiorna-claude.sh — checks for and installs updates to Claude Desktop
# (Anthropic's official .deb build) into a local folder, and refreshes
# the application launcher in the KDE Plasma menu.
#
# Unofficial, not affiliated with Anthropic. Use at your own risk.
#
# You can customize the install directory by setting the CLAUDE_INSTALL_DIR
# environment variable before running the script, e.g.:
#   CLAUDE_INSTALL_DIR="$HOME/apps/claude" ./aggiorna-claude.sh
# If not set, ~/Claude is used by default.

set -euo pipefail

# If the script is started without an attached terminal (e.g. double-clicked
# from a file manager, or launched via a .desktop entry), it relaunches
# itself inside a terminal so the user always sees the output instead of
# apparently "nothing happening". This block is skipped if the script was
# already launched from an open terminal.
if [[ ! -t 1 ]]; then
  SCRIPT_PATH="$(readlink -f "$0")"
  CMD="bash -c \"'$SCRIPT_PATH'; echo; read -rp 'Press ENTER to close this window...' _\""
  for term in konsole gnome-terminal xfce4-terminal kitty alacritty foot xterm; do
    if command -v "$term" &>/dev/null; then
      case "$term" in
        konsole)        exec konsole -e bash -c "'$SCRIPT_PATH'; echo; read -rp 'Press ENTER to close this window...' _" ;;
        gnome-terminal)  exec gnome-terminal -- bash -c "'$SCRIPT_PATH'; echo; read -rp 'Press ENTER to close this window...' _" ;;
        xfce4-terminal)  exec xfce4-terminal -e "$CMD" ;;
        *)               exec "$term" -e bash -c "'$SCRIPT_PATH'; echo; read -rp 'Press ENTER to close this window...' _" ;;
      esac
    fi
  done
  # No terminal found: continue anyway in the background,
  # but output may not be visible.
fi

INSTALL_DIR="${CLAUDE_INSTALL_DIR:-$HOME/Claude}"
VERSION_FILE="$INSTALL_DIR/.installed_version"
REPO_BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
PACKAGES_URL="$REPO_BASE/dists/stable/main/binary-amd64/Packages"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Compares two versions with sort -V: returns true if $1 >= $2
version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

# Looks for a version string inside app.asar (useful for manual installs,
# where there's no system package manager to ask for the version)
detect_asar_version() {
  local asar v
  asar="$(find "$INSTALL_DIR" -maxdepth 6 -iname 'app.asar' 2>/dev/null | head -1)"
  [[ -z "$asar" ]] && return 1
  v="$(strings -n 4 "$asar" 2>/dev/null \
        | grep -oE '"version":"[0-9]+\.[0-9]+\.[0-9]+"' \
        | head -1 \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  [[ -n "$v" ]] || return 1
  echo "$v"
}

# Tries several methods, in order of reliability, to figure out which
# version is currently installed — covers users of this script from a
# previous run, users who installed the .deb via apt, users who installed
# an AUR package, and users who (like the original case) extracted the
# .deb by hand.
detect_installed_version() {
  local v pkg

  # 1) Tracking file created by this script on a previous run
  if [[ -f "$VERSION_FILE" ]]; then
    cat "$VERSION_FILE"
    return 0
  fi

  # 2) Package installed via apt/dpkg (Debian/Ubuntu or official repo)
  if command -v dpkg-query &>/dev/null; then
    v="$(dpkg-query -W -f='${Version}' claude-desktop 2>/dev/null || true)"
    if [[ -n "$v" ]]; then
      echo "$v"
      return 0
    fi
  fi

  # 3) Package installed via pacman (AUR — several common package names)
  if command -v pacman &>/dev/null; then
    for pkg in claude-desktop claude-desktop-bin claude-desktop-hardened-bin claude claude-desktop-appimage; do
      v="$(pacman -Qi "$pkg" 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}')"
      if [[ -n "$v" ]]; then
        echo "$v"
        return 0
      fi
    done
  fi

  # 4) Version string found inside the manually extracted app
  if [[ -d "$INSTALL_DIR" ]]; then
    v="$(detect_asar_version || true)"
    if [[ -n "$v" ]]; then
      echo "$v"
      return 0
    fi
  fi

  echo "unknown"
  return 1
}

echo "==> Checking for Claude Desktop updates..."
mkdir -p "$INSTALL_DIR"

curl -fsSL "$PACKAGES_URL" -o "$TMP_DIR/Packages.txt"

# Extracts the latest available version (Version + Filename paired),
# works for any current or future version scheme (1.x, 2.x, etc.)
read -r LATEST_VERSION LATEST_FILE < <(
  awk '
    /^Version:/  { v=$2 }
    /^Filename:/ { f=$2 }
    /^$/         { if (v && f) print v"\t"f; v=""; f="" }
    END          { if (v && f) print v"\t"f }
  ' "$TMP_DIR/Packages.txt" | sort -V | tail -1
)

if [[ -z "${LATEST_VERSION:-}" ]]; then
  echo "Could not determine the latest version from the repository. Please try again later."
  exit 1
fi

INSTALLED_VERSION="$(detect_installed_version)"

echo "    Installed version: $INSTALLED_VERSION"
echo "    Available version:  $LATEST_VERSION"

if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
  echo "==> You're already on the latest version. No update needed."
  [[ -f "$VERSION_FILE" ]] || echo "$LATEST_VERSION" > "$VERSION_FILE"
  echo
  read -rp "Press ENTER to close this window..." _
  exit 0
fi

if [[ "$INSTALLED_VERSION" != "unknown" ]] && version_ge "$INSTALLED_VERSION" "$LATEST_VERSION"; then
  echo "==> The locally detected version ($INSTALLED_VERSION) is already equal to or newer"
  echo "    than the one in the repository ($LATEST_VERSION). Skipping to avoid a downgrade."
  echo
  read -rp "Press ENTER to close this window..." _
  exit 0
fi

echo "==> New version found, downloading package..."
curl -fsSL -o "$TMP_DIR/claude-desktop.deb" "$REPO_BASE/$LATEST_FILE"

echo "==> Extracting package..."
mkdir -p "$TMP_DIR/extract"
(
  cd "$TMP_DIR/extract"
  ar x "$TMP_DIR/claude-desktop.deb"
  tar xf data.tar.*
)

if [[ ! -d "$TMP_DIR/extract/usr" ]]; then
  echo "Extraction failed: usr/ folder not found in the package."
  exit 1
fi

echo "==> Replacing $INSTALL_DIR with the new version..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
mv "$TMP_DIR/extract/usr" "$INSTALL_DIR/usr"
echo "$LATEST_VERSION" > "$VERSION_FILE"

# SUID permissions required by the Chromium/Electron sandbox
SANDBOX_BIN="$INSTALL_DIR/usr/lib/claude-desktop/chrome-sandbox"
if [[ -f "$SANDBOX_BIN" ]]; then
  echo "==> Setting SUID permissions on chrome-sandbox (requires sudo)..."
  sudo chown root:root "$SANDBOX_BIN"
  sudo chmod 4755 "$SANDBOX_BIN"
fi

# Update the .desktop shortcut and icons for the KDE menu
DESKTOP_SRC_DIR="$INSTALL_DIR/usr/share/applications"
ICON_SRC_DIR="$INSTALL_DIR/usr/share/icons"
DESKTOP_DEST_DIR="$HOME/.local/share/applications"
ICON_DEST_DIR="$HOME/.local/share/icons"

mkdir -p "$DESKTOP_DEST_DIR" "$ICON_DEST_DIR"

if compgen -G "$DESKTOP_SRC_DIR"/*.desktop > /dev/null; then
  echo "==> Updating the application menu shortcut..."
  for f in "$DESKTOP_SRC_DIR"/*.desktop; do
    name="$(basename "$f")"
    sed "s|^Exec=.*claude-desktop|Exec=$INSTALL_DIR/usr/lib/claude-desktop/claude-desktop|" \
      "$f" > "$DESKTOP_DEST_DIR/$name"
  done
fi

if [[ -d "$ICON_SRC_DIR" ]]; then
  cp -rf "$ICON_SRC_DIR"/* "$ICON_DEST_DIR"/ 2>/dev/null || true
fi

echo "==> Refreshing the KDE Plasma menu cache..."
if command -v kbuildsycoca6 &>/dev/null; then
  kbuildsycoca6 --noincremental
elif command -v kbuildsycoca5 &>/dev/null; then
  kbuildsycoca5 --noincremental
fi
command -v update-desktop-database &>/dev/null && \
  update-desktop-database "$DESKTOP_DEST_DIR" 2>/dev/null || true

echo "==> Done! Claude Desktop updated to $LATEST_VERSION."
echo
read -rp "Press ENTER to close this window..." _
