ID=dock
TITLE="Dock"
DESC="bottom dock that hides, dots under open apps, genie (magic lamp) minimize, snappier animations"
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
    # Not on the dock: blurring it makes Blur my Shell and Ubuntu Dock fight over the dock's
    # size ("Can't update stage views", dozens of times a second), which stutters
    set_key $bms/dash-to-dock/blur false
    set_key $bms/overview/blur true
    set_key $bms/appfolder/blur true
    set_key $bms/appfolder/sigma 30
    set_key $bms/popup/blur false   # see 40-top-bar.sh
  }
  # Snappier, closer to macOS: GNOME's animations at 0.6x their length
  ext_use just-perfection-desktop@just-perfection && set_key /org/gnome/shell/extensions/just-perfection/animation 4
  ok "dock set"
}

component_uninstall() { :; }
