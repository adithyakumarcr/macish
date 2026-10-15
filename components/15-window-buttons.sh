ID=window-buttons
TITLE="Window buttons on the left"
DESC="close, minimize, maximize on the left like macOS"
DEFAULT=on

component_install() {
  set_key /org/gnome/desktop/wm/preferences/button-layout "'close,minimize,maximize:'"
  ok "window buttons moved to the left"
}

component_uninstall() { :; }
