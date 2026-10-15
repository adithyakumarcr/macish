ID=cursors
TITLE="Mouse pointer"
DESC="macOS pointer (WhiteSur cursors)"
DEFAULT=on
APT=(git)

component_install() {
  local src
  track_path "$HOME/.local/share/icons/WhiteSur-cursors"
  src="$(fetch_repo WhiteSur-cursors)"
  (cd "$src" && ./install.sh) > "$LAM_STATE/cursors.log" 2>&1 || die "cursor install failed; see $LAM_STATE/cursors.log"
  set_key /org/gnome/desktop/interface/cursor-theme "'WhiteSur-cursors'"
  ok "pointer set"
}

component_uninstall() { :; }
