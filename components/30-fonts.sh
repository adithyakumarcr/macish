ID=fonts
TITLE="Fonts"
DESC="Inter as the system font (closest free match to Apple's SF Pro)"
DEFAULT=on
APT=(fonts-inter)

component_install() {
  local i=/org/gnome/desktop/interface
  set_key $i/font-name "'Inter 11'"
  set_key $i/document-font-name "'Inter 11'"
  set_key /org/gnome/desktop/wm/preferences/titlebar-font "'Inter SemiBold 11'"
  set_key $i/font-antialiasing "'grayscale'"
  set_key $i/font-hinting "'slight'"
  ok "system font set to Inter"
}

component_uninstall() { :; }
