ID=wallpaper
TITLE="Wallpaper"
DESC="macOS Tahoe wallpaper, day in Light mode and night in Dark mode"
DEFAULT=on
APT=(git)

component_install() {
  local src dir="$HOME/.local/share/backgrounds/like-a-mac" b=/org/gnome/desktop/background
  src="$(fetch_repo MacTahoe-gtk-theme)"
  track_path "$dir"
  mkdir -p "$dir"
  cp "$src"/wallpaper/MacTahoe-{day,night}.jpeg "$dir/"
  set_key $b/picture-uri "'file://$dir/MacTahoe-day.jpeg'"
  set_key $b/picture-uri-dark "'file://$dir/MacTahoe-night.jpeg'"
  set_key $b/picture-options "'zoom'"
  set_key /org/gnome/desktop/screensaver/picture-uri "'file://$dir/MacTahoe-night.jpeg'"
  ok "wallpaper set"
}

component_uninstall() { :; }
