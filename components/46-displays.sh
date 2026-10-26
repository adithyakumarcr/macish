ID=displays
TITLE="Remember screen layout"
DESC="not a Mac feature: after a docking station reconnects, the primary screen and the screens' positions come back"
DEFAULT=off

component_supported() {
  command -v systemctl > /dev/null || { echo "needs systemd"; return 1; }
}

component_install() {
  local bin="$HOME/.local/bin/macish-displays" unit="$HOME/.config/systemd/user/macish-displays.service"
  track_path "$bin"
  track_path "$unit"
  track_path "${XDG_STATE_HOME:-$HOME/.local/state}/macish/displays.json"   # what it remembers
  install -D -m 0755 "$LAM_DIR/assets/displays/macish-displays" "$bin"
  install -D -m 0644 "$LAM_DIR/assets/displays/macish-displays.service" "$unit"
  if systemctl --user show-environment > /dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable macish-displays.service > /dev/null 2>&1
    systemctl --user restart macish-displays.service
  else
    "$bin" --once   # no user session manager (e.g. over SSH): remember the screens once
  fi
  ok "screen layout is remembered per monitor, not per connector"
}

component_uninstall() {
  systemctl --user disable --now macish-displays.service > /dev/null 2>&1 || true
}
