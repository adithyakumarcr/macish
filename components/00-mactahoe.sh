# Internal: builds the MacTahoe GTK + GNOME Shell themes into ~/.themes.
# Pulled in automatically by "app-theme", "top-bar" and "control-center".
ID=mactahoe
HIDDEN=1
TITLE="MacTahoe theme build"
APT=(git sassc libglib2.0-dev-bin libxml2-utils)

component_install() {
  local src v
  src="$(fetch_repo MacTahoe-gtk-theme)"
  for v in Light Dark; do
    for d in "" -hdpi -xhdpi; do track_path "$HOME/.themes/MacTahoe-$v-solid$d"; done
  done
  track_path "$HOME/.local/bin/gnome-theme-switcher"
  track_path "$HOME/.local/share/applications/org.gnome.GTK4ThemeSwitcher.desktop"
  say "Building the MacTahoe theme (takes a minute)"
  # MacTahoe's installer quietly fails without TERM (it calls setterm)
  (cd "$src" && TERM="${TERM:-xterm}" ./install.sh -o solid -HD) > "$LAM_STATE/mactahoe-build.log" 2>&1 ||
    die "MacTahoe build failed; see $LAM_STATE/mactahoe-build.log"
  [[ -d "$HOME/.themes/MacTahoe-Dark-solid/gnome-shell" ]] ||
    die "MacTahoe build produced no theme; see $LAM_STATE/mactahoe-build.log"
  ok "MacTahoe themes in ~/.themes"
}

component_uninstall() { :; }   # tracked paths are removed by the installer
