ID=terminal
TITLE="Terminal"
DESC="Terminator styled like macOS Terminal (Pro profile, frosted glass)"
DEFAULT=off
APT=(terminator)

component_install() {
  local conf="$HOME/.config/terminator/config" css="$HOME/.config/gtk-3.0/gtk.css"
  local bms=/org/gnome/shell/extensions/blur-my-shell font f

  # SF Mono is Apple's and can't be shared here. If you have it, put the .otf files in
  # fonts/sf-mono/ next to install.sh (or install them yourself) and it is used.
  if [[ -z "$(fc-list 'SF Mono')" ]] && compgen -G "$LAM_DIR/fonts/sf-mono/*.otf" > /dev/null; then
    track_path "$HOME/.local/share/fonts/SFMono"
    mkdir -p "$HOME/.local/share/fonts/SFMono"
    cp "$LAM_DIR"/fonts/sf-mono/*.otf "$HOME/.local/share/fonts/SFMono/"
    fc-cache -f "$HOME/.local/share/fonts" > /dev/null
  fi
  for f in 'SF Mono' 'Menlo' 'JetBrains Mono' 'DejaVu Sans Mono'; do
    [[ -n "$(fc-list "$f")" ]] && { font="$f 11"; break; }
  done
  font="${font:-Monospace 11}"

  backup_file "$conf"
  mkdir -p "$(dirname "$conf")"
  sed "s/^\(\s*font = \).*/\1$font/" "$LAM_DIR/assets/terminal/terminator.config" > "$conf"

  # macOS-like padding inside the terminal (GTK3 user CSS, between markers so it can be removed)
  backup_file "$css"
  mkdir -p "$(dirname "$css")"
  touch "$css"
  sed -i '/like_a_mac terminal begin/,/like_a_mac terminal end/d' "$css"
  { echo "/* like_a_mac terminal begin */"; cat "$LAM_DIR/assets/gtk3/terminal-padding.css"
    echo "/* like_a_mac terminal end */"; } >> "$css"

  # frosted glass behind the terminal only
  ext_use blur-my-shell@aunetx && {
    set_key $bms/applications/blur true
    set_key $bms/applications/enable-all false
    set_key $bms/applications/whitelist "['Terminator', 'terminator']"
    set_key $bms/applications/sigma 30
    set_key $bms/applications/brightness 1.0
    set_key $bms/applications/opacity 255
    set_key $bms/applications/corner-radius 12
    set_key $bms/applications/dynamic-opacity false
    set_key $bms/applications/blur-on-overview false
  }
  ok "Terminator styled (font: $font)"
}

component_uninstall() { :; }
