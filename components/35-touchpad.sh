ID=touchpad
TITLE="Touchpad"
DESC="Mac-style touchpad: tap to click, natural scrolling, two-finger right-click, swipe gestures"
DEFAULT=on
TP=/org/gnome/desktop/peripherals/touchpad
GESTURES=touchpad-gesture-customization@coooolapps.com
TGC=/org/gnome/shell/extensions/touchpad-gesture-customization
WAYLAND=ubuntu-wayland

component_supported() {
  gsettings list-keys org.gnome.desktop.peripherals.touchpad > /dev/null 2>&1 ||
    { echo "needs GNOME's touchpad settings"; return 1; }
}

# The login session's name in AccountsService (what GDM starts next time), or empty
user_path() {
  busctl call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts \
    FindUserByName s "$USER" 2> /dev/null | awk '{print $2}' | tr -d '"'
}
login_session() {
  local p
  p="$(user_path)" && [[ -n "$p" ]] || return 0
  busctl get-property org.freedesktop.Accounts "$p" org.freedesktop.Accounts.User Session 2> /dev/null |
    awk '{print $2}' | tr -d '"'
}
set_login_session() {
  local p
  p="$(user_path)" && [[ -n "$p" ]] || return 1
  busctl call org.freedesktop.Accounts "$p" org.freedesktop.Accounts.User SetSession s "$1"
}

component_install() {
  local old saved="$LAM_SAVED/$COMPONENT.session"

  set_key "$TP/tap-to-click" true
  set_key "$TP/tap-button-map" "'lrm'"                 # two-finger tap: right-click
  set_key "$TP/natural-scroll" true
  set_key "$TP/click-method" "'fingers'"               # two-finger click: right-click, anywhere on the pad
  set_key "$TP/two-finger-scrolling-enabled" true
  set_key "$TP/edge-scrolling-enabled" false
  set_key "$TP/middle-click-emulation" false
  set_key "$TP/disable-while-typing" true

  # Swipes like a Mac: three or four fingers sideways switch desktops, up and down open and
  # close the overview, a four-finger pinch shows the desktop
  ext_use "$GESTURES" && {
    set_key "$TGC/horizontal-swipe-3-fingers-gesture" "'WORKSPACE_SWITCHING'"
    set_key "$TGC/horizontal-swipe-4-fingers-gesture" "'WORKSPACE_SWITCHING'"
    set_key "$TGC/vertical-swipe-3-fingers-gesture" "'OVERVIEW_NAVIGATION'"
    set_key "$TGC/vertical-swipe-4-fingers-gesture" "'OVERVIEW_NAVIGATION'"
    set_key "$TGC/overview-navigation-states" "'GNOME'"
    set_key "$TGC/pinch-3-finger-gesture" "'NONE'"
    set_key "$TGC/pinch-4-finger-gesture" "'SHOW_DESKTOP'"
    set_key "$TGC/follow-natural-scroll" true
    set_key "$TGC/enable-forward-back-gesture" false
  }

  # Gestures only work on Wayland. With an NVIDIA card GDM starts Xorg for "Ubuntu", so the
  # login session is set to "Ubuntu on Wayland"; the earlier one comes back on uninstall.
  if [[ -e /usr/share/wayland-sessions/$WAYLAND.desktop ]]; then
    old="$(login_session)"
    if [[ "$old" != "$WAYLAND" ]] && set_login_session "$WAYLAND" > /dev/null; then
      [[ -e "$saved" ]] || echo "${old:-ubuntu}" > "$saved"
      warn "log out and back in: the next login uses Ubuntu on Wayland, which gestures need"
    fi
  fi
  ok "touchpad behaves like a Mac's"
}

component_uninstall() {
  local saved="$LAM_SAVED/$COMPONENT.session"
  if [[ -f "$saved" ]]; then
    set_login_session "$(cat "$saved")" > /dev/null || warn "couldn't set the login session back to $(cat "$saved")"
    rm -f "$saved"
  fi
}
