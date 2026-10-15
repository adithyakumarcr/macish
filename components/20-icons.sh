ID=icons
TITLE="App icons"
DESC="macOS Tahoe icons, every app on a matching tile (MacTahoe + MacOS-Like)"
DEFAULT=on
NEEDS="theme-sync"
APT=(git python3-pil librsvg2-bin rsync)

component_install() {
  local src icons="$HOME/.local/share/icons" d
  for d in MacTahoe-Bold MacTahoe-Bold-light MacTahoe-Bold-dark MacOS-Like-Light MacOS-Like-Dark; do
    track_path "$icons/$d"
  done
  track_path "$HOME/.local/state/folder-icons"
  track_path "$HOME/.config/macos-like"

  say "Installing the MacTahoe icons"
  src="$(fetch_repo MacTahoe-icon-theme)"
  (cd "$src" && ./install.sh -n MacTahoe-Bold -b) > "$LAM_STATE/icons.log" 2>&1 ||
    die "MacTahoe icons failed; see $LAM_STATE/icons.log"

  say "Building tiles for your apps (a few minutes)"
  src="$(fetch_repo MacOS-Like)"
  # answers "no" to its optional matugen question, if it asks
  (cd "$src" && printf 'n\n' | ./setup.sh --source MacTahoe-Bold) >> "$LAM_STATE/icons.log" 2>&1 ||
    die "MacOS-Like failed; see $LAM_STATE/icons.log"

  if [[ "$(current_mode)" == dark ]]; then
    set_key /org/gnome/desktop/interface/icon-theme "'MacOS-Like-Dark'"
  else
    set_key /org/gnome/desktop/interface/icon-theme "'MacOS-Like-Light'"
  fi
  ok "icons set. Installed new apps later? Run: $LAM_SRC/MacOS-Like/setup.sh --source MacTahoe-Bold"
}

component_uninstall() { :; }
