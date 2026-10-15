ID=control-center
TITLE="Control Center"
DESC="Quick Settings restyled like macOS Control Center, with a media tile"
DEFAULT=on
NEEDS="mactahoe shell-theme theme-sync"

component_install() {
  local qst=/org/gnome/shell/extensions/quick-settings-tweaks
  # Quick Settings Tweaks adds the media tile; notifications stay in the clock menu
  if ext_use quick-settings-tweaks@qwreey; then
    set_key $qst/media-enabled true
    set_key $qst/notifications-enabled false
    set_key $qst/volume-mixer-enabled false
    set_key $qst/weather-enabled false
    set_key $qst/dnd-quick-toggle-enabled true
    set_key $qst/datemenu-hide-left-box false
    set_key $qst/datemenu-hide-notifications false
    set_key $qst/datemenu-hide-media-control true
  else
    warn "no media tile (Quick Settings Tweaks isn't available for GNOME $SHELL_MAJOR); the restyle still applies"
  fi
  ok "Control Center set"
}

component_uninstall() { :; }
