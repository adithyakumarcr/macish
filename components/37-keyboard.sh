ID=keyboard
TITLE="Mac keyboard"
DESC="Alt is Command, Win is Option: Cmd+C, Cmd+Tab, Cmd+Space, text keys and Option's characters like a Mac"
SUDO=1
DEFAULT=on
APT=(python3-evdev)
UUID=macish-keys@adithya
BIN_DIR=/usr/local/lib/macish
BIN=$BIN_DIR/macish-keys
UNIT=/etc/systemd/system/macish-keys.service
TOSHY_RULE=/etc/udev/rules.d/70-toshy-keymapper-input.rules
KEYBOARD_DEFAULT=/etc/default/keyboard

component_supported() {
  (( ${SHELL_MAJOR:-0} >= 45 )) || { echo "needs GNOME 45 or newer"; return 1; }
  command -v systemctl > /dev/null || { echo "needs systemd"; return 1; }
  # Two key translators would fight over the keyboard
  [[ ! -d "$HOME/.config/toshy" ]] || { echo "Toshy is installed; remove it first"; return 1; }
  ! systemctl is-active --quiet keyd 2> /dev/null || { echo "keyd is running; stop it first"; return 1; }
}

# swap_source FROM TO  - the keyboard layout FROM ('de') becomes TO ('de+mac') in your input
# sources; the rest of the list, and its order, stay
swap_source() {
  local key cur new
  for key in sources mru-sources; do
    cur="$(gsettings get org.gnome.desktop.input-sources $key 2> /dev/null)" || continue
    new="$(python3 - "$cur" "$1" "$2" <<'PY'
import ast, sys
cur, old, new = sys.argv[1:]
items = ast.literal_eval(cur.replace('@a(ss) ', ''))
out = [(t, new if (t, i) == ('xkb', old) else i) for t, i in items]
print(repr(out) if out != items else '')
PY
)"
    if [[ -n "$new" ]]; then gsettings set org.gnome.desktop.input-sources $key "$new"; fi
  done
}

# system_keyboard  - the login screen's layout: XKBLAYOUT and XKBVARIANT, one a line
system_keyboard() {
  ( . "$KEYBOARD_DEFAULT" 2> /dev/null; printf '%s\n%s\n' "${XKBLAYOUT:-}" "${XKBVARIANT:-}" )
}

# set_system_keyboard LAYOUT VARIANT  - edited in the file: Debian's localectl can't set it
# (localed only reads it, for GDM). The model, options and the rest stay.
set_system_keyboard() {
  sudo sed -i -E -e "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$1\"/" -e "s/^XKBVARIANT=.*/XKBVARIANT=\"$2\"/" \
    "$KEYBOARD_DEFAULT"
  grep -q '^XKBVARIANT=' "$KEYBOARD_DEFAULT" ||
    echo "XKBVARIANT=\"$2\"" | sudo tee -a "$KEYBOARD_DEFAULT" > /dev/null
}

component_install() {
  local rec="$LAM_SAVED/$COMPONENT.system" ext="$EXT_DIR/$UUID" unit sources pc mac old new
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

  # The power button is the service's now: a press locks, Ctrl+press asks to power off. GNOME's
  # own action (a popup on every press) would fight it, so it's off; uninstall puts it back.
  [[ "$(gsettings get org.gnome.settings-daemon.plugins.power power-button-action)" == "'nothing'" ]] ||
    set_key /org/gnome/settings-daemon/plugins/power/power-button-action "'nothing'"

  # Which app is in front (Terminal, browser, Files) and which keyboard layout is in use
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

  # Layouts with a Mac version that types the same printed keys: Option types what it types on
  # a Mac (Option+L is @ on German). Only the first time: a layout you put back stays put.
  sources="$(gsettings get org.gnome.desktop.input-sources sources)"
  while read -r pc mac; do
    [[ "$sources" == *"('xkb', '$pc')"* && "$sources" != *"('xkb', '$mac')"* ]] || continue
    grep -qxF "layout $pc $mac" "$rec" && continue
    echo "layout $pc $mac" >> "$rec"
    swap_source "$pc" "$mac"
    ok "keyboard layout $pc is now $mac: Option types like on a Mac (the right Alt too)"
  done < <(python3 "$LAM_DIR/assets/keyboard/macish-keys" --mac-layouts)

  # The login screen the same way, in its own layout's language, so a password types there as
  # in your session. Also once; uninstall puts it back if it's still the one set here.
  if [[ -f "$KEYBOARD_DEFAULT" ]] && ! grep -q '^login-layout ' "$rec"; then
    mapfile -t old < <(system_keyboard)
    mapfile -t new < <(python3 "$LAM_DIR/assets/keyboard/macish-keys" --mac-system "${old[@]}")
    if (( ${#new[@]} == 2 )); then
      echo "login-layout ${old[0]:--} ${old[1]:--} ${new[0]} ${new[1]:--}" >> "$rec"
      set_system_keyboard "${new[0]}" "${new[1]}"
      ok "login screen: layout ${old[0]} ${old[1]} is now ${new[0]} ${new[1]}, so Option types there too"
    fi
  fi

  # Toshy (removed) left a rule and a group that let any program read your keystrokes
  if [[ -e "$TOSHY_RULE" ]]; then
    say "Removing what Toshy left behind (sudo)"
    sudo rm -f "$TOSHY_RULE"
    sudo udevadm control --reload-rules
    if [[ " $(id -nG "$USER") " == *" input "* ]]; then sudo gpasswd -d "$USER" input > /dev/null; fi
    ok "Toshy's keyboard access removed (your account leaves the input group at the next login)"
  fi

  ok "Mac keyboard on: Alt is Command, Win is Option. Ctrl+Win+Alt+Esc switches it off and on"
  echo "     Log out and back in once, so Terminal, browser and Files shortcuts know the app in front"
  echo "     and Option knows the keyboard layout."
}

component_uninstall() {
  local rec="$LAM_SAVED/$COMPONENT.system" kind path pc mac old_l old_v new_l new_v now
  [[ -f "$rec" ]] || return 0
  # The layouts switched to their Mac version go back, wherever they are in the list now
  while read -r kind pc mac; do
    if [[ "$kind" == layout ]]; then swap_source "$mac" "$pc"; fi
  done < "$rec"
  say "Removing the Mac keyboard service (sudo)"
  # The login screen's too, unless it was changed since
  while read -r kind old_l old_v new_l new_v; do
    [[ "$kind" == login-layout ]] || continue
    mapfile -t now < <(system_keyboard)
    if [[ "${now[0]}" == "$new_l" && "${now[1]:--}" == "$new_v" ]]; then
      set_system_keyboard "${old_l#-}" "${old_v#-}"
    fi
  done < "$rec"
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
