ID=spotlight
TITLE="Spotlight"
DESC="Alt+Space (Cmd+Space) opens a search bar: apps, websites, folders, recent searches"
DEFAULT=on
UUID=spotlight@adithya
APT=(libglib2.0-bin)

component_supported() {
  [[ "$SHELL_MAJOR" == 46 ]] || { echo "made for GNOME 46 (you have $SHELL_MAJOR)"; return 1; }
}

component_install() {
  local dest="$EXT_DIR/$UUID"
  if [[ -L "$dest" ]]; then
    ok "already linked to $(readlink "$dest")"
  else
    track_path "$dest"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -r "$LAM_DIR"/extensions/spotlight/{extension.js,search.js,metadata.json,stylesheet.css,icons,schemas} "$dest/"
  fi
  glib-compile-schemas "$dest/schemas"
  # Alt+Space opens GNOME's window menu (Move, Resize, Close...); that moves to Alt+F3
  set_key /org/gnome/desktop/wm/keybindings/activate-window-menu "['<Alt>F3']"
  track_path "$LAM_STATE/spotlight"   # recent searches, removed with the part
  ext_use "$UUID"
  ok "Spotlight added: Alt+Space opens it (the window menu moved to Alt+F3)"
}

component_uninstall() { :; }
