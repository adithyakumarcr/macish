ID=airdrop
TITLE="AirDrop"
DESC="receive files from iPhones over AirDrop (Wi-Fi is off while visible)"
SUDO=1
DEFAULT=off
APT=(git)
# Wi-Fi drivers omdrop-owl runs without an opt-in ("tested" in its userspace/owl-profiles)
DRIVERS="iwlwifi mt7925e mt76x2u rtw88_8822be"
# Packages needed only to build omdrop-owl; removed again on uninstall if they weren't here before
BUILD_PKGS=(build-essential cmake pkg-config dpkg-dev libev-dev libpcap-dev libnl-3-dev
  libnl-genl-3-dev libnl-route-3-dev)
# /etc/omdrop settings for Intel cards (owl -R 54 -M 550; omdrop-owl PR #64)
INTEL_SETTINGS=("tx-rate 54" "election-metric 550")
# The receiver's port, from the iPhone's link-local address on AirDrop's interface only
UFW_RULE=(allow in on awdl0 proto tcp from fe80::/10 to any port 8771)

wifi_drivers() {
  local w
  for w in /sys/class/net/*/wireless; do
    [[ -e "$w" ]] && basename "$(readlink -f "${w%/wireless}/device/driver")"
  done
}

installed_pkgs() { dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' | sed -n 's/^ii *//p' | sort; }

# remember_new_pkgs BEFORE  - records what was installed since BEFORE (a list from installed_pkgs)
remember_new_pkgs() {
  local file="$LAM_SAVED/$COMPONENT.pkgs"
  comm -13 <(printf '%s\n' "$1") <(installed_pkgs) >> "$file"
  sort -u -o "$file" "$file"
}

component_supported() {
  local cmd drv
  for cmd in apt-get nmcli; do
    command -v "$cmd" > /dev/null || { echo "needs $cmd"; return 1; }
  done
  for drv in $(wifi_drivers); do
    [[ " $DRIVERS " == *" $drv "* ]] && return 0
  done
  echo "needs a Wi-Fi card that omdrop-owl supports"
  return 1
}

component_install() {
  local before owl plugin deb tmp downloads want=() p
  local bin="$HOME/.local/bin" keys="$LAM_STATE/airdrop"
  local unit="$HOME/.config/systemd/user/like-a-mac-airdrop.service"
  local desktop="$HOME/.local/share/applications/like-a-mac-airdrop.desktop"

  before="$(installed_pkgs)"
  for p in "${BUILD_PKGS[@]}"; do
    [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == 'install ok installed' ]] || want+=("$p")
  done
  if (( ${#want[@]} )); then
    say "Installing build tools: ${want[*]} (sudo)"
    sudo apt-get update -qq
    sudo apt-get install -y "${want[@]}"
    remember_new_pkgs "$before"
  fi

  # The AWDL radio: OWL with omdrop-owl's patches, its root helper, polkit rule,
  # NetworkManager rule and udev .link file, as one package.
  track_path "$LAM_SRC/omdrop-owl"
  owl="$(fetch_repo omdrop-owl)"
  # Faster transfers on channel 6, from omdrop-owl PR #64 (not merged upstream yet): three
  # more OWL patches, and two settings files the helper passes on (see INTEL_SETTINGS).
  git -C "$owl" checkout -q -- .
  cp "$LAM_DIR"/assets/airdrop/omdrop-owl/owl-*.patch "$owl/patches/"
  git -C "$owl" apply "$LAM_DIR/assets/airdrop/omdrop-owl/discoverable-settings.patch" ||
    die "the speed-up patch doesn't apply to this version of omdrop-owl"
  sed -i 's/^pkgrel=.*/&+likeamac1/' "$owl/PKGBUILD"   # the package says it's patched
  say "Building omdrop-owl, the AWDL radio helper (log: $LAM_STATE/airdrop-build.log)"
  rm -f "$owl"/omdrop-owl_*.deb
  (cd "$owl" && tools/build-deb.sh) > "$LAM_STATE/airdrop-build.log" 2>&1 ||
    die "building omdrop-owl failed; see $LAM_STATE/airdrop-build.log"
  # apt reads a local .deb as its own _apt user, which can't see into the home folder
  tmp="$(mktemp -d)"
  chmod 755 "$tmp"
  deb="$(echo "$owl"/omdrop-owl_*.deb)"
  install -m 0644 "$deb" "$tmp/"
  say "Installing omdrop-owl (sudo)"
  before="$(installed_pkgs)"
  sudo apt-get install -y --reinstall --no-install-recommends "$tmp/${deb##*/}"
  remember_new_pkgs "$before"
  rm -rf "$tmp"

  # Intel cards: a faster data rate, and this computer as AWDL's sync master, so it keeps the
  # timing instead of drifting behind the iPhone's. Deleting the two files undoes it.
  if [[ " $(wifi_drivers | tr '\n' ' ') " == *" iwlwifi "* ]]; then
    local etc="$LAM_SAVED/$COMPONENT.etc" setting name value
    if [[ ! -d /etc/omdrop ]]; then
      sudo mkdir -p /etc/omdrop
      echo /etc/omdrop >> "$etc"
    fi
    for setting in "${INTEL_SETTINGS[@]}"; do
      read -r name value <<< "$setting"
      [[ -e "/etc/omdrop/$name" ]] && continue   # ours from before, or the user's own
      printf '%s\n' "$value" | sudo tee "/etc/omdrop/$name" > /dev/null
      echo "/etc/omdrop/$name" >> "$etc"
    done
  fi

  if command -v ufw > /dev/null; then
    say "Letting AirDrop through the firewall: TCP 8771 on awdl0 only (sudo)"
    sudo ufw "${UFW_RULE[@]}" > /dev/null
    touch "$LAM_SAVED/$COMPONENT.ufw"
  fi

  # The receiver (/Discover, /Ask, /Upload), patched to ask before accepting anything
  track_path "$LAM_SRC/omdrop-plugin"
  plugin="$(fetch_repo omdrop-plugin)"
  git -C "$plugin" checkout -q -- .
  git -C "$plugin" apply "$LAM_DIR/assets/airdrop/ask-hook.patch" ||
    die "the Accept/Decline patch doesn't apply to this version of omdrop"

  downloads="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
  [[ -n "$downloads" && "$downloads" != "$HOME" ]] || downloads="$HOME/Downloads"
  mkdir -p "$downloads"

  for p in like-a-mac-airdrop like-a-mac-airdrop-notify; do
    track_path "$bin/$p"
    install -D -m 0755 "$LAM_DIR/assets/airdrop/$p" "$bin/$p"
  done
  track_path "$keys"
  mkdir -p "$keys"
  chmod 700 "$keys"
  track_path "$unit"
  mkdir -p "$(dirname "$unit")"
  sed -e "s|@RECEIVER@|$plugin|g" -e "s|@KEYS@|$keys|g" -e "s|@DOWNLOADS@|$downloads|g" \
    "$LAM_DIR/assets/airdrop/like-a-mac-airdrop.service" > "$unit"
  track_path "$desktop"
  mkdir -p "$(dirname "$desktop")"
  sed "s|@BIN@|$bin/like-a-mac-airdrop|" "$LAM_DIR/assets/airdrop/like-a-mac-airdrop.desktop" > "$desktop"
  systemctl --user daemon-reload 2> /dev/null || true

  ok "AirDrop installed: open AirDrop from the app grid (or run like-a-mac-airdrop on)"
  echo "     While it's on, this computer is visible to Everyone for 10 minutes and Wi-Fi is off."
}

component_uninstall() {
  local file="$LAM_SAVED/$COMPONENT.pkgs" pkgs=() keep p

  if [[ -x "$HOME/.local/bin/like-a-mac-airdrop" ]]; then
    # omdrop-owl's own removal script also turns the radio off, so going on is safe
    "$HOME/.local/bin/like-a-mac-airdrop" off || warn "AirDrop didn't turn off cleanly"
  fi
  systemctl --user stop like-a-mac-airdrop.service 2> /dev/null || true

  if [[ -f "$LAM_SAVED/$COMPONENT.ufw" ]]; then
    say "Removing the AirDrop firewall rule (sudo)"
    sudo ufw delete "${UFW_RULE[@]}" > /dev/null || warn "couldn't remove the firewall rule: ufw ${UFW_RULE[*]}"
    rm -f "$LAM_SAVED/$COMPONENT.ufw"
  fi

  if [[ -f "$LAM_SAVED/$COMPONENT.etc" ]]; then
    say "Removing AirDrop's settings in /etc/omdrop (sudo)"
    while IFS= read -r p; do   # newest first: the files, then the folder
      [[ "$p" == /etc/omdrop || "$p" == /etc/omdrop/* ]] || continue
      if [[ -d "$p" ]]; then sudo rmdir "$p" 2> /dev/null || true; else sudo rm -f -- "$p"; fi
    done < <(tac "$LAM_SAVED/$COMPONENT.etc")
    rm -f "$LAM_SAVED/$COMPONENT.etc"
  fi

  if [[ -f "$file" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == 'install ok installed' ]] &&
        pkgs+=("$p")
    done < "$file"
  fi
  if (( ${#pkgs[@]} )); then
    # Anything else that has come to need these packages since would go too: keep them then
    keep="$(apt-get -s purge "${pkgs[@]}" | sed -n 's/^\(Purg\|Remv\) \([^ :]*\).*/\2/p' |
      grep -vxF -f <(printf '%s\n' "${pkgs[@]}" | sed 's/:.*//') || true)"
    if [[ -n "$keep" ]]; then
      warn "keeping the packages AirDrop brought in: other software now needs them (${keep//$'\n'/ })"
      if [[ " ${pkgs[*]} " == *" omdrop-owl "* ]]; then pkgs=(omdrop-owl); else pkgs=(); fi
    fi
  fi
  if (( ${#pkgs[@]} )); then
    say "Removing ${pkgs[*]} (sudo)"
    sudo apt-get purge -y "${pkgs[@]}"
  fi
  rm -f "$file"
  ok "AirDrop removed"
}
