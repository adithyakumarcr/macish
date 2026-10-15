ID=app-theme
TITLE="Apps & windows"
DESC="macOS Tahoe look for apps and title bars, follows Light/Dark"
DEFAULT=on
NEEDS="mactahoe theme-sync"
APT=(git sassc libglib2.0-dev-bin libxml2-utils)

component_install() {
  local src gtk4="$HOME/.config/gtk-4.0" f tmp
  src="$(fetch_repo MacTahoe-gtk-theme)"
  for f in gtk.css gtk-dark.css gtk-Light.css gtk-Dark.css assets windows-assets \
           like-a-mac-dark.css like-a-mac-light.css; do
    backup_file "$gtk4/$f"
  done
  # GTK4/libadwaita apps read ~/.config/gtk-4.0; the GTK3 themes themselves come from "mactahoe",
  # so this run's own ~/.themes output goes to a throwaway folder.
  tmp="$(mktemp -d)"
  (cd "$src" && TERM="${TERM:-xterm}" ./install.sh -l -o solid -HD -d "$tmp") > "$LAM_STATE/app-theme.log" 2>&1 ||
    die "GTK4 theme build failed; see $LAM_STATE/app-theme.log"
  rm -rf "$tmp"
  [[ -f "$gtk4/gtk-Light.css" && -f "$gtk4/gtk-Dark.css" ]] || die "GTK4 theme files missing; see $LAM_STATE/app-theme.log"
  cp "$LAM_DIR/assets/gtk4/overrides-dark.css" "$gtk4/like-a-mac-dark.css"
  cp "$LAM_DIR/assets/gtk4/overrides-light.css" "$gtk4/like-a-mac-light.css"
  if [[ "$(current_mode)" == dark ]]; then
    set_key /org/gnome/desktop/interface/gtk-theme "'MacTahoe-Dark-solid'"
  else
    set_key /org/gnome/desktop/interface/gtk-theme "'MacTahoe-Light-solid'"
  fi
  ok "app theme set (GTK4 apps pick it up when they next start)"
}

component_uninstall() { :; }
