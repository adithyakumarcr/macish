ID=three-finger-drag
TITLE="Three-finger drag"
DESC="drag windows and select text with three fingers (newer libinput from a PPA)"
SUDO=1
DEFAULT=on
# libinput 1.31 with three-finger drag switched on; Ubuntu 24.04 ships 1.25, without it
PPA=ppa:ubuntuhandbook1/libinput
PPA_FILE=/etc/apt/sources.list.d/ubuntuhandbook1-ubuntu-libinput-noble.sources

component_supported() {
  [[ "$(lsb_release -cs 2>/dev/null)" == noble ]] || { echo "the PPA only has builds for Ubuntu 24.04"; return 1; }
  command -v add-apt-repository > /dev/null || { echo "needs add-apt-repository (software-properties-common)"; return 1; }
}

libinput_pkgs() {   # the libinput packages that are installed
  dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 'libinput*' 2>/dev/null |
    awk '/^ii/ {sub(/:.*/, "", $2); print $2}'
}

component_install() {
  local pkgs
  # A PPA added by hand before is taken over, so uninstall removes it too
  touch "$LAM_SAVED/$COMPONENT.ppa"
  if [[ ! -e "$PPA_FILE" ]]; then
    say "Adding $PPA (sudo)"
    sudo add-apt-repository -y "$PPA"
  fi
  mapfile -t pkgs < <(libinput_pkgs)
  say "Updating libinput from the PPA (sudo)"
  sudo apt-get update -qq
  sudo apt-get install -y --only-upgrade "${pkgs[@]}"
  ok "three-finger drag is on after you log out and back in"
}

component_uninstall() {
  local pkgs=() p want
  [[ -f "$LAM_SAVED/$COMPONENT.ppa" ]] || return 0
  say "Removing $PPA and going back to Ubuntu's libinput (sudo)"
  sudo rm -f "$PPA_FILE"
  sudo apt-get update -qq
  for p in $(libinput_pkgs); do
    # Ubuntu's newest version. Not apt's "Candidate": apt never picks an older version itself,
    # so that stays the PPA's even once the PPA is gone.
    want="$(apt-cache madison "$p" | awk 'NR == 1 {print $3}')"
    [[ -n "$want" && "$want" != "$(dpkg-query -W -f='${Version}' "$p")" ]] && pkgs+=("$p=$want")
  done
  (( ${#pkgs[@]} )) && sudo apt-get install -y --allow-downgrades "${pkgs[@]}"
  rm -f "$LAM_SAVED/$COMPONENT.ppa"
  ok "Ubuntu's libinput is back after you log out and back in"
}
