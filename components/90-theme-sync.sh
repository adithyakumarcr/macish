# Internal: a small user service that switches the installed parts between their light and
# dark versions whenever GNOME's Light/Dark setting changes.
ID=theme-sync
HIDDEN=1
TITLE="Light/Dark sync"

component_install() {
  local bin="$HOME/.local/bin/like-a-mac-sync" unit="$HOME/.config/systemd/user/like-a-mac-sync.service"
  track_path "$bin"
  track_path "$unit"
  install -D -m 0755 "$LAM_DIR/assets/theme-sync/like-a-mac-sync" "$bin"
  install -D -m 0644 "$LAM_DIR/assets/theme-sync/like-a-mac-sync.service" "$unit"
  if systemctl --user show-environment > /dev/null 2>&1; then
    # an earlier, single-user version of this project ran "mac-theme-sync"; two would fight
    systemctl --user disable --now mac-theme-sync.service > /dev/null 2>&1 || true
    systemctl --user daemon-reload
    systemctl --user enable like-a-mac-sync.service > /dev/null 2>&1
    systemctl --user restart like-a-mac-sync.service
  else
    "$bin" --once > /dev/null   # no user session manager (e.g. over SSH): apply once
  fi
  ok "Light/Dark sync running"
}

component_uninstall() {
  systemctl --user disable --now like-a-mac-sync.service > /dev/null 2>&1 || true
}
