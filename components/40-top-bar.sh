ID=top-bar
TITLE="Top bar"
DESC="slim macOS menu bar: clock on the right, app menu, see-through blur"
DEFAULT=on
NEEDS="mactahoe shell-theme theme-sync"

component_install() {
  local jp=/org/gnome/shell/extensions/just-perfection lm=/org/gnome/shell/extensions/Logo-menu
  local bms=/org/gnome/shell/extensions/blur-my-shell

  # Just Perfection: no Activities button, clock moved to the right
  ext_use just-perfection-desktop@just-perfection && {
    set_key $jp/activities-button false
    set_key $jp/clock-menu-position 1
    set_key $jp/clock-menu-position-offset 20
    set_key $jp/ripple-box false
    set_key $jp/startup-status 0
  }
  # Logo Menu: the menu at the left with About, Settings, Force Quit, power options
  ext_use logomenu@aryan_k && {
    set_key $lm/menu-button-icon-image 5
    set_key $lm/menu-button-icon-size 20
    set_key $lm/symbolic-icon true
    set_key $lm/use-custom-icon false
    set_key $lm/show-activities-button false
    set_key $lm/show-lockscreen true
    set_key $lm/show-power-options true
    command -v terminator > /dev/null && set_key $lm/menu-button-terminal "'terminator'"
  }
  # Blur my Shell: the bar shows the blurred wallpaper until a window touches it
  ext_use blur-my-shell@aunetx && {
    set_key $bms/panel/blur true
    set_key $bms/panel/brightness 0.6
    set_key $bms/panel/sigma 30
    set_key $bms/panel/corner-radius 0
    set_key $bms/panel/static-blur true
    set_key $bms/panel/override-background true
    set_key $bms/panel/override-background-dynamically true
  }
  set_key /org/gnome/desktop/interface/clock-show-weekday true
  set_key /org/gnome/desktop/interface/clock-show-date true
  ok "top bar set"
}

component_uninstall() { :; }
