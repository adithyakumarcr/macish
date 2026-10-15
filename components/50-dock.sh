ID=dock
TITLE="Dock"
DESC="bottom dock that hides, dots under open apps, blur, genie (magic lamp) minimize"
DEFAULT=on

component_supported() {
  grep -qx org.gnome.shell.extensions.dash-to-dock <<< "$(gsettings list-schemas)" ||
    { echo "needs Ubuntu Dock or Dash to Dock"; return 1; }
}

component_install() {
  local d=/org/gnome/shell/extensions/dash-to-dock bms=/org/gnome/shell/extensions/blur-my-shell
  set_key $d/dock-position "'BOTTOM'"
  set_key $d/extend-height false
  set_key $d/dock-fixed false
  set_key $d/autohide true
  set_key $d/intellihide true
  set_key $d/dash-max-icon-size 48
  set_key $d/show-apps-at-top false
  set_key $d/show-mounts false
  set_key $d/show-trash true
  set_key $d/running-indicator-style "'DOTS'"
  set_key $d/click-action "'minimize-or-previews'"
  set_key $d/apply-custom-theme true
  set_key $d/transparency-mode "'DYNAMIC'"

  ext_use compiz-alike-magic-lamp-effect@hermes83.github.com || true
  ext_use blur-my-shell@aunetx && {
    set_key $bms/dash-to-dock/blur true
    set_key $bms/dash-to-dock/brightness 0.6
    set_key $bms/dash-to-dock/sigma 30
    set_key $bms/dash-to-dock/corner-radius 28
    set_key $bms/dash-to-dock/static-blur true
    set_key $bms/dash-to-dock/override-background false
    set_key $bms/dash-to-dock/unblur-in-overview true
    set_key $bms/overview/blur true
    set_key $bms/appfolder/blur true
    set_key $bms/appfolder/sigma 30
  }
  ok "dock set"
}

component_uninstall() { :; }
