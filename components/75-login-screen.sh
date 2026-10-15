ID=login-screen
TITLE="Login screen"
DESC="dark macOS-style login screen (asks for your password: changes a system file)"
DEFAULT=off
DEST_DIR=/usr/share/gnome-shell/theme/MacTahoe-GDM
ALT_NAME=gdm-theme.gresource

component_supported() {
  [[ "$SHELL_MAJOR" == 46 ]] || { echo "built for GNOME 46 (you have $SHELL_MAJOR)"; return 1; }
  update-alternatives --list "$ALT_NAME" > /dev/null 2>&1 ||
    { echo "needs Ubuntu's login screen (GDM theme alternative)"; return 1; }
}

component_install() {
  local src="$LAM_DIR/assets/login-screen/gdm-theme-mactahoe.gresource"
  grep -q /org/gnome/shell/theme/gdm.css <<< "$(gresource list "$src" 2>/dev/null)" ||
    die "the login theme file is damaged"
  say "Installing the login screen theme (sudo)"
  # Ubuntu's own Yaru theme file is not touched, so updates won't undo this and the desktop is unaffected
  sudo install -D -m 0644 "$src" "$DEST_DIR/gnome-shell-theme.gresource"
  sudo update-alternatives --install /usr/share/gnome-shell/gdm-theme.gresource "$ALT_NAME" \
    "$DEST_DIR/gnome-shell-theme.gresource" 20 > /dev/null
  sudo update-alternatives --set "$ALT_NAME" "$DEST_DIR/gnome-shell-theme.gresource"
  ok "login screen changes the next time you log out or restart"
  cat <<'MSG'
     If the login screen ever fails to appear: press Ctrl+Alt+F3, log in, and run
       ./install.sh --uninstall --only login-screen
     then: sudo reboot
MSG
}

component_uninstall() {
  if grep -qx "$DEST_DIR/gnome-shell-theme.gresource" <<< "$(update-alternatives --list "$ALT_NAME" 2>/dev/null)"; then
    sudo update-alternatives --remove "$ALT_NAME" "$DEST_DIR/gnome-shell-theme.gresource"
  fi
  sudo update-alternatives --auto "$ALT_NAME"
  sudo rm -rf "$DEST_DIR"
  ok "Ubuntu's login screen is back (after the next log out)"
}
