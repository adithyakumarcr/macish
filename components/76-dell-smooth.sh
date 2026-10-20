ID=dell-smooth
TITLE="Dell 14 Premium smoothness"
DESC="smooth animations and gestures on the Dell 14 Premium (changes system files)"
SUDO=1
DEFAULT=off
MODEL="Dell 14 Premium DA14250"
# Intel's GuC firmware the kernel asks for (70.53; Ubuntu ships 70.36), from linux-firmware
FW=/lib/firmware/updates/i915/mtl_guc_70.bin
FW_URL=https://gitlab.com/kernel-firmware/linux-firmware/-/raw/20260410/i915/mtl_guc_70.bin
FW_SHA256=7794f0b6abe5fcd9c6f47035dafe2199f30a6e7d230bd5a53fbf8005a60e5911
UDEV_RULE=/etc/udev/rules.d/61-mutter-ignore-nvidia.rules
PPD_DIR=/etc/systemd/system/power-profiles-daemon.service.d

component_supported() {
  [[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" == "$MODEL" ]] ||
    { echo "only for the $MODEL"; return 1; }
  command -v prime-select > /dev/null || { echo "needs NVIDIA's driver (prime-select)"; return 1; }
}

# What this part owns, one per line, so uninstall can undo exactly that:
#   file PATH   a file it installed, or found identical (set up by hand with smooth-setup.sh)
#   dir PATH    a folder it may remove again once empty
#   prime MODE  the NVIDIA mode to go back to
RECORD_NAME=system

# own_file SRC DST  - installs SRC as DST; prints "changed" when DST is new
own_file() {
  local src="$1" dst="$2" rec="$LAM_SAVED/$COMPONENT.$RECORD_NAME"
  if [[ -e "$dst" ]] && ! grep -qxF "file $dst" "$rec" 2>/dev/null; then
    if ! cmp -s "$src" "$dst"; then
      warn "$dst is someone else's and differs from macish's; left as it is"
      return 0
    fi
  elif ! cmp -s "$src" "$dst" 2>/dev/null; then
    sudo install -D -m 0644 "$src" "$dst"
    echo changed
  fi
  grep -qxF "file $dst" "$rec" 2>/dev/null || echo "file $dst" >> "$rec"
}

component_install() {
  local rec="$LAM_SAVED/$COMPONENT.$RECORD_NAME" tmp changed='' mode
  touch "$rec"
  tmp="$(mktemp -d)"
  say "Downloading Intel's GPU firmware (linux-firmware 20260410)"
  curl -fsSL "$FW_URL" -o "$tmp/mtl_guc_70.bin"
  sha256sum -c --quiet - <<< "$FW_SHA256  $tmp/mtl_guc_70.bin" ||
    { rm -rf "$tmp"; die "the firmware download doesn't match its checksum"; }

  say "Installing the firmware, the NVIDIA rule and the power-mode fix (sudo)"
  # /lib/firmware/updates wins over Ubuntu's file and survives linux-firmware upgrades
  changed+="$(own_file "$tmp/mtl_guc_70.bin" "$FW")"
  rm -rf "$tmp"
  # GNOME leaves the NVIDIA GPU alone (it drives no screen here), so it can power down
  changed+="$(own_file "$LAM_DIR/assets/dell-smooth/61-mutter-ignore-nvidia.rules" "$UDEV_RULE")"
  # GNOME's power modes reach Dell's thermal modes: power-profiles-daemon waits for dell_pc
  grep -qxF "dir $PPD_DIR" "$rec" || echo "dir $PPD_DIR" >> "$rec"
  changed+="$(own_file "$LAM_DIR/assets/dell-smooth/wait-dell-pc.conf" "$PPD_DIR/wait-dell-pc.conf")"

  if ! grep -q '^prime ' "$rec"; then
    mode="$(prime-select query)"
    # Already on-demand next to smooth-setup.sh's rule: that script switched it from nvidia
    [[ "$mode" == on-demand ]] && grep -qxF "file $UDEV_RULE" "$rec" && mode=nvidia
    echo "prime $mode" >> "$rec"
  fi
  if [[ "$(prime-select query)" != on-demand ]]; then
    sudo prime-select on-demand
    changed=1
  fi

  if [[ -n "$changed" ]]; then
    sudo systemctl daemon-reload
    sudo systemctl restart power-profiles-daemon
    sudo update-initramfs -u
    ok "done: restart the computer to load the new firmware and GPU settings"
  else
    ok "already set up on this computer; macish now looks after it"
  fi
}

component_uninstall() {
  local rec="$LAM_SAVED/$COMPONENT.$RECORD_NAME" kind path
  [[ -f "$rec" ]] || return 0
  say "Undoing the Dell fixes (sudo)"
  while read -r kind path; do
    case "$kind" in
      file) [[ "$path" == /lib/firmware/updates/* || "$path" == /etc/* ]] && sudo rm -f -- "$path" ;;
      prime) [[ "$(prime-select query)" == "$path" ]] || sudo prime-select "$path" ;;
    esac
  done < "$rec"
  while read -r kind path; do
    [[ "$kind" == dir && "$path" == /etc/* ]] && sudo rmdir --ignore-fail-on-non-empty -- "$path"
  done < "$rec"
  sudo systemctl daemon-reload
  sudo systemctl restart power-profiles-daemon
  sudo update-initramfs -u
  rm -f "$rec"
  ok "undone: restart the computer to go back to the old firmware and GPU settings"
}
