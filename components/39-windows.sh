ID=windows
TITLE="Window tiling"
DESC="tile like macOS: Ctrl+Option+arrows, drag to an edge or corner; Ctrl+Cmd+drag moves a window"
DEFAULT=on
TA=tiling-assistant@ubuntu.com
TAS=org.gnome.shell.extensions.tiling-assistant

component_supported() {
  (( ${SHELL_MAJOR:-0} >= 45 )) || { echo "needs GNOME 45 or newer"; return 1; }
  gsettings list-keys $TAS > /dev/null 2>&1 || { echo "needs Ubuntu's Tiling Assistant"; return 1; }
}

component_install() {
  # Ubuntu's Tiling Assistant does the tiling. Turned on only if it was off, so removing this
  # part turns it off again only then.
  gnome-extensions info "$TA" 2> /dev/null | grep -q 'Enabled: Yes' || ext_use "$TA"

  # Drag to an edge for a half, a corner for a quarter, the top to fill, without Windows'
  # Snap Assist popup offering the other windows afterwards
  set_key "/${TAS//.//}/enable-tiling-popup" false

  # The shortcuts the Mac keyboard sends for Ctrl+Option+arrows, F, C, R, Enter (on PC keys
  # they're Super+arrows and Ctrl+Super+arrows / C / Enter)
  local wm=org.gnome.desktop.wm.keybindings
  add_binding $TAS tile-left-half '<Super>Left'
  add_binding $TAS tile-right-half '<Super>Right'
  add_binding $TAS tile-maximize '<Super>Up'
  add_binding $TAS restore-window '<Super>Down'
  add_binding $TAS tile-top-half '<Control><Super>Up'
  add_binding $TAS tile-bottom-half '<Control><Super>Down'
  add_binding $TAS center-window '<Control><Super>c'
  add_binding $wm toggle-fullscreen '<Control><Super>Return'
  # A window filling the half next to another monitor goes on to it (GNOME's own, Super+Shift+arrows)
  add_binding $wm move-to-monitor-left '<Super><Shift>Left'
  add_binding $wm move-to-monitor-right '<Super><Shift>Right'
  add_binding $wm move-to-monitor-up '<Super><Shift>Up'
  add_binding $wm move-to-monitor-down '<Super><Shift>Down'

  # Super+drag moves a window; the Mac keyboard turns Ctrl+Cmd into Super for it
  [[ "$(gsettings get org.gnome.desktop.wm.preferences mouse-button-modifier)" == "'<Super>'" ]] ||
    set_key /org/gnome/desktop/wm/preferences/mouse-button-modifier "'<Super>'"

  ok "window tiling set: Ctrl+Option+arrows tile, Ctrl+Option+Enter is full screen, Ctrl+Cmd+drag moves (with the Mac keyboard)"
}

component_uninstall() { :; }
