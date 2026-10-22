ID=touch-id
TITLE="Touch ID"
DESC="your fingerprint logs you in, unlocks the screen and approves sudo and admin prompts"
SUDO=1
DEFAULT=on
APT=(fprintd libpam-fprintd)
FINGER=right-index-finger
BIN_DIR=/usr/local/lib/macish
GATE=$BIN_DIR/touch-id-ready
PROFILE=macish-touch-id
PROFILE_FILE=/usr/share/pam-configs/$PROFILE
FPRINT=(--system --dest net.reactivated.Fprint)
MANAGER=/net/reactivated/Fprint/Manager
LATER="add it in Settings → System → Users → Fingerprint Login, or run ./install.sh --only touch-id again"

component_supported() {
  command -v pam-auth-update > /dev/null || { echo "needs Ubuntu's pam-auth-update"; return 1; }
  has_reader || { echo "no fingerprint reader that Linux supports"; return 1; }
}

# A USB reader libfprint has a driver for (udev's list of them, up to its "Known unsupported
# devices"), or one fprintd already uses, e.g. through a vendor's driver
has_reader() {
  local d present='' lists=()
  for d in /sys/bus/usb/devices/*/; do
    [[ -r "${d}idVendor" ]] && present+="v$(<"${d}idVendor")p$(<"${d}idProduct") "
  done
  for d in /usr/lib/udev/hwdb.d/60-autosuspend-{fingerprint-reader,libfprint-2}.hwdb; do
    [[ -r "$d" ]] && lists+=("$d")
  done
  if (( ${#lists[@]} )) && awk -v present="${present^^}" '
      FNR == 1 || /^# Supported by libfprint/ { skip = 0 }
      /^# Known unsupported/ { skip = 1 }
      !skip && /^usb:/ && index(present, toupper(substr($0, 5, 10))) { found = 1 }
      END { exit !found }' "${lists[@]}"; then
    return 0
  fi
  command -v fprintd-list > /dev/null &&
    [[ "$(timeout 10 gdbus call "${FPRINT[@]}" --object-path "$MANAGER" \
      --method net.reactivated.Fprint.Manager.GetDevices 2> /dev/null)" == *objectpath* ]]
}

# fprint_property NAME  - a property of the reader (name, num-enroll-stages, scan-type), or nothing
fprint_property() {
  local dev
  dev="$(gdbus call "${FPRINT[@]}" --object-path "$MANAGER" \
    --method net.reactivated.Fprint.Manager.GetDefaultDevice 2> /dev/null | grep -o "/net/[^']*")" || return 0
  gdbus call "${FPRINT[@]}" --object-path "$dev" --method org.freedesktop.DBus.Properties.Get \
    net.reactivated.Fprint.Device "$1" 2> /dev/null | sed -E "s/^\(<'?//; s/'?>,\)$//" || true
}

# The fingers saved for you, one per line (right-index-finger, ...)
enrolled() { { fprintd-list "$USER" 2> /dev/null || true; } | sed -n 's/^ - #[0-9]*: //p'; }

# pam_profile_on NAME  - Ubuntu's pam-auth-update has that profile in /etc/pam.d/common-auth
pam_profile_on() { grep -qx "Module: $1" /var/lib/pam/auth 2> /dev/null; }

lid_closed() { grep -qs closed /proc/acpi/button/lid/*/state; }

# dots N TOTAL  - ●●●○○○: N of the TOTAL touches the sensor needs
dots() {
  local i s=''
  (( $2 > 0 )) || { printf '%d so far' "$1"; return 0; }
  for (( i = 0; i < $2; i++ )); do
    if (( i < $1 )); then s+='●'; else s+='○'; fi
  done
  printf '%s' "$s"
}

# enroll FINGER  - saves that finger, the way a Mac sets up Touch ID: rest it on the sensor, lift
# it, rest it again, until every dot is filled. Ctrl+C skips. Returns 1 when it isn't saved.
enroll() {
  local finger="$1" name="${1//-/ }" total scan n=0 line hint='' result=''
  total="$(fprint_property num-enroll-stages)"
  [[ "$total" =~ ^[0-9]+$ ]] || total=0
  scan="$(fprint_property scan-type)"
  if [[ "$scan" == swipe ]]; then
    echo "     Swipe your $name across the sensor, again and again,"
  else
    echo "     Rest your $name on the sensor, lift it, and rest it again,"
  fi
  echo "     until every dot is filled. Ctrl+C skips this."
  [[ "$scan" == swipe ]] ||
    echo "     If the sensor is in the power button, rest your finger without pressing."
  printf '     %s' "$(dots 0 "$total")"
  # Ctrl+C stops fprintd-enroll, not the installer (sudo usually passes it on by itself)
  trap : INT
  while IFS= read -r line; do
    case "$line" in
      *enroll-stage-passed) n=$(( n + 1 )); hint='' ;;
      *enroll-retry-scan|*enroll-remove-and-retry) hint="didn't catch that, try again" ;;
      *enroll-finger-not-centered) hint='put your finger in the middle of the sensor' ;;
      *enroll-swipe-too-short) hint='swipe again, a little slower' ;;
      *enroll-completed) result=done; n=$(( total > 0 ? total : n )); hint='' ;;
      *enroll-duplicate) result='the sensor already has this finger, for another user or system' ;;
      *enroll-data-full) result="the sensor's memory is full" ;;
      *enroll-*) result="the sensor stopped (${line##* })" ;;
      'Using device'*|Enrolling*) continue ;;
      *) result="$line"; continue ;;      # fprintd-enroll's own errors
    esac
    printf '\r     %s  %s\e[K' "$(dots "$n" "$total")" "$hint"
  done < <(sudo fprintd-enroll -f "$finger" "$USER" 2>&1)
  trap - INT
  echo
  case "$result" in
    done) grep -qxF "$finger" <<< "$(enrolled)" && return 0
          warn "the sensor said done, but fprintd doesn't list your $name" ;;
    '') warn "fingerprint skipped" ;;
    *) warn "fingerprint not saved: $result" ;;
  esac
  return 1
}

component_install() {
  local rec="$LAM_SAVED/$COMPONENT.system" reader fingers args=()
  reader="$(fprint_property name)"
  [[ -n "$reader" ]] || die "fprintd doesn't find the fingerprint reader (fprintd-list $USER says why)"

  # The lock screen takes the fingerprint while this is on (GNOME's default), and so does the
  # login screen: both ask fprintd themselves, next to the password
  [[ "$(gsettings get org.gnome.login-screen enable-fingerprint-authentication)" == true ]] ||
    set_key /org/gnome/login-screen/enable-fingerprint-authentication true

  # sudo in a terminal and admin prompts: a profile for Ubuntu's pam-auth-update that asks for
  # the fingerprint only there (touch-id-ready decides), and for the password after 10 seconds
  say "Letting sudo and admin prompts take your fingerprint (sudo)"
  touch "$rec"
  [[ -d "$BIN_DIR" ]] || grep -qxF "dir $BIN_DIR" "$rec" || echo "dir $BIN_DIR" >> "$rec"
  grep -qxF "file $GATE" "$rec" || echo "file $GATE" >> "$rec"
  grep -qxF "file $PROFILE_FILE" "$rec" || echo "file $PROFILE_FILE" >> "$rec"
  sudo install -D -m 0755 "$LAM_DIR/assets/touch-id/touch-id-ready" "$GATE"
  sudo install -m 0644 "$LAM_DIR/assets/touch-id/$PROFILE" "$PROFILE_FILE"
  # Ubuntu's own fingerprint profile asks everywhere, at the login screen too, where the
  # password can't be typed until it gives up; it's off while this one is on
  if pam_profile_on fprintd; then
    grep -qxF "pam fprintd" "$rec" || echo "pam fprintd" >> "$rec"
    args+=(--disable fprintd)
  fi
  sudo env DEBIAN_FRONTEND=noninteractive pam-auth-update "${args[@]}" --enable "$PROFILE"
  grep -q touch-id-ready /etc/pam.d/common-auth ||
    die "pam-auth-update left /etc/pam.d/common-auth as it is (it has changes of its own)"

  fingers="$(enrolled)"
  if [[ -n "$fingers" ]]; then
    fingers="${fingers//-/ }"
    ok "your fingerprint is already saved (${fingers//$'\n'/, })"
  elif ! [[ -t 0 && -t 1 ]]; then
    warn "no fingerprint saved yet: $LATER"
  elif lid_closed; then
    warn "no fingerprint saved yet, the lid is closed: open it and $LATER"
  else
    say "Saving your fingerprint on the $reader"
    # Recorded first, so uninstall deletes it even if this stops halfway
    grep -qxF "finger $FINGER" "$rec" || echo "finger $FINGER" >> "$rec"
    if enroll "$FINGER"; then
      ok "your ${FINGER//-/ } is saved"
    else
      sed -i "/^finger $FINGER\$/d" "$rec"
      echo "     To use Touch ID, $LATER"
    fi
  fi

  if [[ -n "$(enrolled)" ]]; then
    ok "Touch ID is on: your fingerprint logs you in, unlocks the screen and approves sudo and admin prompts"
    echo "     After logging in with it, the first app that needs a saved password (Chrome, Wi-Fi)"
    echo "     asks for your password once: Ubuntu's keyring opens only with the password."
  fi
}

component_uninstall() {
  local rec="$LAM_SAVED/$COMPONENT.system" kind what args
  [[ -f "$rec" ]] || return 0
  say "Removing Touch ID (sudo)"
  if pam_profile_on "$PROFILE" || grep -q touch-id-ready /etc/pam.d/common-auth; then
    args=(--disable "$PROFILE")
    grep -qxF "pam fprintd" "$rec" && args+=(--enable fprintd)
    sudo env DEBIAN_FRONTEND=noninteractive pam-auth-update "${args[@]}"
  fi
  # Should pam-auth-update refuse, the line stays but skips the fingerprint once the helper is gone
  grep -q touch-id-ready /etc/pam.d/common-auth &&
    warn "pam-auth-update left /etc/pam.d/common-auth as it is; sudo asks for your password anyway"
  while read -r kind what; do
    case "$kind" in
      file) [[ "$what" == "$GATE" || "$what" == "$PROFILE_FILE" ]] && sudo rm -f -- "$what" ;;
      # The fingerprint macish saved goes too: the login and lock screens would still take it
      finger) grep -qxF "$what" <<< "$(enrolled)" && sudo fprintd-delete "$USER" -f "$what" > /dev/null ;;
    esac
  done < "$rec"
  while read -r kind what; do
    [[ "$kind" == dir && "$what" == "$BIN_DIR" ]] && sudo rmdir --ignore-fail-on-non-empty -- "$what"
  done < "$rec"
  rm -f "$rec"
  ok "Touch ID removed: your password again, everywhere"
}
