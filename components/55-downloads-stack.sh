ID=downloads-stack
TITLE="Downloads stack"
DESC="a Downloads stack in the Dock that previews your newest files"
DEFAULT=on
UUID=downloads-stack@adithya

component_supported() {
  [[ "$SHELL_MAJOR" == 46 ]] || { echo "made for GNOME 46 (you have $SHELL_MAJOR)"; return 1; }
  [[ -d /usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com ]] || { echo "needs Ubuntu Dock"; return 1; }
}

component_install() {
  local dest="$EXT_DIR/$UUID"
  if [[ -L "$dest" ]]; then
    ok "already linked to $(readlink "$dest")"
  else
    track_path "$dest"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp "$LAM_DIR"/downloads-stack/{extension.js,metadata.json,stylesheet.css,thumbnailer.py} "$dest/"
  fi
  # ext_use only downloads when missing, which it never is here
  ext_use "$UUID"
  ok "Downloads stack added (it sits next to the Trash)"
}

component_uninstall() { :; }
