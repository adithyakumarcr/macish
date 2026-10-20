ID=keyboard
TITLE="Mac keyboard"
DESC="Alt is Command, Win is Option: Cmd+C, Cmd+Tab, Cmd+Space and text keys like a Mac"
SUDO=1
DEFAULT=on
APT=(python3-evdev)
UUID=macish-keys@adithya
BIN_DIR=/usr/local/lib/macish
BIN=$BIN_DIR/macish-keys
UNIT=/etc/systemd/system/macish-keys.service
TOSHY_RULE=/etc/udev/rules.d/70-toshy-keymapper-input.rules

component_supported() {
  (( ${SHELL_MAJOR:-0} >= 45 )) || { echo "needs GNOME 45 or newer"; return 1; }
  command -v systemctl > /dev/null || { echo "needs systemd"; return 1; }
  # Two key translators would fight over the keyboard
  [[ ! -d "$HOME/.config/toshy" ]] || { echo "Toshy is installed; remove it first"; return 1; }
  ! systemctl is-active --quiet keyd 2> /dev/null || { echo "keyd is running; stop it first"; return 1; }
}

# add_binding SCHEMA KEY ACCEL  - GNOME also answers to ACCEL (the service sends it); yours stay
add_binding() {
  local cur new
  cur="$(gsettings get "$1" "$2" 2> /dev/null)" || return 0
  new="$(python3 - "$cur" "$3" <<'PY'
import ast, sys
cur, accel = sys.argv[1:]
items = ast.literal_eval(cur.replace('@as ', ''))
print('' if accel in items else repr(items + [accel]))
PY
)"
  if [[ -n "$new" ]]; then set_key "/${1//.//}/$2" "$new"; fi
}

component_install() {
  local rec="$LAM_SAVED/$COMPONENT.system" ext="$EXT_DIR/$UUID" unit
  local wm=org.gnome.desktop.wm.keybindings shell=org.gnome.shell.keybindings

  # The GNOME shortcuts the service turns Mac shortcuts into
  add_binding $wm switch-applications '<Super>Tab'
  add_binding $wm switch-applications-backward '<Shift><Super>Tab'
  add_binding $wm switch-group '<Super>Above_Tab'
  add_binding $wm switch-group-backward '<Shift><Super>Above_Tab'
  add_binding $wm switch-to-workspace-left '<Super>Page_Up'
  add_binding $wm switch-to-workspace-right '<Super>Page_Down'
  add_binding $wm minimize '<Super>h'
  add_binding $shell screenshot '<Shift>Print'
  add_binding $shell show-screenshot-ui 'Print'
  add_binding org.gnome.settings-daemon.plugins.media-keys screensaver '<Super>l'
  [[ "$(gsettings get org.gnome.mutter overlay-key)" == "'Super_L'" ]] ||
    set_key /org/gnome/mutter/overlay-key "'Super_L'"

  # Which app is in front (Terminal, browser, Files)
  track_path "$ext"
  rm -rf "$ext"
  mkdir -p "$ext"
  cp "$LAM_DIR"/extensions/macish-keys/{extension.js,metadata.json} "$ext/"
  ext_use "$UUID"

  # The service, as root: nothing of yours needs access to your keystrokes
  say "Installing the Mac keyboard service (sudo)"
  touch "$rec"
  [[ -d "$BIN_DIR" ]] || grep -qxF "dir $BIN_DIR" "$rec" || echo "dir $BIN_DIR" >> "$rec"
  grep -qxF "file $BIN" "$rec" || echo "file $BIN" >> "$rec"
  grep -qxF "file $UNIT" "$rec" || echo "file $UNIT" >> "$rec"
  sudo install -D -m 0755 "$LAM_DIR/assets/keyboard/macish-keys" "$BIN"
  unit="$(mktemp)"
  sed "s/@UID@/$(id -u)/" "$LAM_DIR/assets/keyboard/macish-keys.service" > "$unit"
  sudo install -m 0644 "$unit" "$UNIT"
  rm -f "$unit"
  sudo systemctl daemon-reload
  sudo systemctl enable macish-keys.service > /dev/null 2>&1
  sudo systemctl restart macish-keys.service
  sleep 1
  systemctl is-active --quiet macish-keys.service ||
    die "the Mac keyboard service didn't start: journalctl -u macish-keys"

  # Toshy (removed) left a rule and a group that let any program read your keystrokes
  if [[ -e "$TOSHY_RULE" ]]; then
    say "Removing what Toshy left behind (sudo)"
    sudo rm -f "$TOSHY_RULE"
    sudo udevadm control --reload-rules
    if [[ " $(id -nG "$USER") " == *" input "* ]]; then sudo gpasswd -d "$USER" input > /dev/null; fi
    ok "Toshy's keyboard access removed (your account leaves the input group at the next login)"
  fi

  ok "Mac keyboard on: Alt is Command, Win is Option. Ctrl+Win+Alt+Esc switches it off and on"
  echo "     Log out and back in once, so Terminal, browser and Files shortcuts know the app in front."
}

component_uninstall() {
  local rec="$LAM_SAVED/$COMPONENT.system" kind path
  [[ -f "$rec" ]] || return 0
  say "Removing the Mac keyboard service (sudo)"
  sudo systemctl disable --now macish-keys.service > /dev/null 2>&1 || true
  while read -r kind path; do
    [[ "$kind" == file && ( "$path" == "$BIN_DIR"/* || "$path" == "$UNIT" ) ]] && sudo rm -f -- "$path"
  done < "$rec"
  while read -r kind path; do
    [[ "$kind" == dir && "$path" == "$BIN_DIR" ]] && sudo rmdir --ignore-fail-on-non-empty -- "$path"
  done < "$rec"
  sudo systemctl daemon-reload
  rm -f "$rec"
  ok "plain PC keys again"
}
