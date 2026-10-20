# Internal: the GNOME Shell theme behind "top-bar" and "control-center".
# Rebuilt every time either of them is installed or removed: MacTahoe's solid shell theme
# plus the CSS of whichever of the two is installed.
ID=shell-theme
HIDDEN=1
TITLE="GNOME Shell theme"
NEEDS="mactahoe"

component_install() {
  local mode Mode dst css part
  for mode in dark light; do
    Mode="${mode^}"
    dst="$HOME/.themes/LikeAMac-$Mode"
    track_path "$dst"
    rm -rf "$dst"
    cp -a "$HOME/.themes/MacTahoe-$Mode-solid" "$dst"
    sed -i "s/MacTahoe-$Mode-solid/LikeAMac-$Mode/g" "$dst/index.theme"
    css="$dst/gnome-shell/gnome-shell.css"
    printf '\n/* ---- macish ---- */\n#panel { height: 32px !important; }\n' >> "$css"
    for part in top-bar control-center; do
      if is_installed "$part"; then
        printf '\n' >> "$css"
        cat "$LAM_DIR/assets/shell/$part-$mode.css" >> "$css"
      fi
    done
  done
  ext_use user-theme@gnome-shell-extensions.gcampax.github.com ||
    die "the User Themes extension is needed for the top bar and Control Center"
  local name key=/org/gnome/shell/extensions/user-theme/name
  name="'LikeAMac-$(current_mode | sed 's/./\U&/')'"
  set_key "$key" "$name"
  # the shell only rereads a stylesheet when the theme name changes: blank it, then set it again
  dconf write "$key" "''"
  dconf write "$key" "$name"
  ok "shell theme built"
}

component_uninstall() { :; }
