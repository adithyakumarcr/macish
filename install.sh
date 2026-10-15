#!/usr/bin/env bash
# like_a_mac — make Ubuntu (GNOME) look like macOS. Pick the parts you want.
#
#   ./install.sh                     choose what to install from a menu
#   ./install.sh --only icons,dock   install just these
#   ./install.sh --all               install everything
#   ./install.sh --uninstall         choose what to remove (puts your old settings back)
#   ./install.sh --list              show the parts and what is installed
#
# Run it as yourself, not with sudo: it asks for your password only when a part needs it.
set -euo pipefail

LAM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LAM_DIR/lib/common.sh"

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

# ---- read the components -------------------------------------------------------
declare -A C_FILE C_TITLE C_DESC C_DEFAULT C_HIDDEN C_NEEDS C_APT C_UNSUPPORTED
ALL_IDS=()
for f in "$LAM_DIR"/components/*.sh; do
  IFS=$'\t' read -r id title desc def hidden needs apt unsupported < <(
    unset -f component_supported
    ID= TITLE= DESC= DEFAULT=on HIDDEN=0 NEEDS= APT=()
    # shellcheck source=/dev/null
    source "$f"
    why=
    if declare -F component_supported > /dev/null; then why="$(component_supported)" || true; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ID" "$TITLE" "${DESC:--}" "$DEFAULT" "$HIDDEN" \
      "${NEEDS:--}" "${APT[*]:--}" "${why:--}")
  ALL_IDS+=("$id")
  C_FILE[$id]="$f"; C_TITLE[$id]="$title"; C_DESC[$id]="${desc#-}"; C_DEFAULT[$id]="$def"
  C_HIDDEN[$id]="$hidden"; C_NEEDS[$id]="${needs#-}"; C_APT[$id]="${apt#-}"; C_UNSUPPORTED[$id]="${unsupported#-}"
done
USER_IDS=()
for id in "${ALL_IDS[@]}"; do [[ "${C_HIDDEN[$id]}" == 1 ]] || USER_IDS+=("$id"); done

# ---- arguments -----------------------------------------------------------------
ACTION=install ONLY= ALL=0 YES=0
while (( $# )); do
  case "$1" in
    --only) ONLY="${2:?--only needs a list, e.g. --only icons,dock}"; shift ;;
    --all) ALL=1 ;;
    --uninstall|--remove) ACTION=uninstall ;;
    --list) ACTION=list ;;
    -y|--yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown option: $1" ;;
  esac
  shift
done

[[ $EUID -ne 0 ]] || die "run this as yourself, without sudo (it asks for your password when needed)"
command -v gnome-shell > /dev/null || die "this needs the GNOME desktop"
for cmd in dconf gsettings python3 curl; do command -v "$cmd" > /dev/null || die "missing program: $cmd"; done

if [[ "$ACTION" == list ]]; then
  for id in "${USER_IDS[@]}"; do
    state="        "; is_installed "$id" && state="[installed]"
    [[ -n "${C_UNSUPPORTED[$id]}" ]] && state="[n/a: ${C_UNSUPPORTED[$id]}]"
    printf '  %-16s %-28s %s  %s\n' "$id" "${C_TITLE[$id]}" "${C_DESC[$id]}" "$state"
  done
  exit 0
fi

# ---- choose -----------------------------------------------------------------------
choose() {   # prints the chosen ids, one per line
  local candidates=() id status label
  for id in "${USER_IDS[@]}"; do
    if [[ "$ACTION" == uninstall ]]; then is_installed "$id" && candidates+=("$id")
    else [[ -z "${C_UNSUPPORTED[$id]}" ]] && candidates+=("$id"); fi
  done
  (( ${#candidates[@]} )) || { [[ "$ACTION" == uninstall ]] && echo "Nothing from like_a_mac is installed." >&2; return 0; }

  if [[ -n "$ONLY" ]]; then
    tr ',' '\n' <<< "$ONLY"; return
  elif (( ALL )); then
    printf '%s\n' "${candidates[@]}"; return
  fi

  local verb="install" title="like_a_mac"
  [[ "$ACTION" == uninstall ]] && verb="remove (your earlier settings come back)"
  if command -v whiptail > /dev/null && [[ -t 0 && -t 2 ]]; then
    local items=() cols
    cols="$(stty size < /dev/tty 2>/dev/null | cut -d' ' -f2)"
    cols=$(( ${cols:-100} - 4 )); (( cols > 120 )) && cols=120
    for id in "${candidates[@]}"; do
      label="${C_TITLE[$id]} — ${C_DESC[$id]}"
      [[ "$ACTION" == install ]] && is_installed "$id" && label+=" (installed)"
      status="${C_DEFAULT[$id]}"; [[ "$ACTION" == uninstall ]] && status=off
      items+=("$id" "$label" "$status")
    done
    whiptail --title "$title" --separate-output --checklist \
      "Make Ubuntu look like a Mac. Choose what to $verb:\n(Space selects, Enter confirms)" \
      $(( ${#candidates[@]} + 9 )) "$cols" ${#candidates[@]} "${items[@]}" 3>&1 1>&2 2>&3 || return 1
  else
    local i=1 defaults=() answer n
    echo "Choose what to $verb:" >&2
    for id in "${candidates[@]}"; do
      printf '  %2d) %-26s %s\n' "$i" "${C_TITLE[$id]}" "${C_DESC[$id]}" >&2
      [[ "$ACTION" == install && "${C_DEFAULT[$id]}" == on ]] && defaults+=("$i")
      i=$((i + 1))
    done
    read -r -p "Numbers separated by spaces [${defaults[*]:-none}]: " answer
    answer="${answer:-${defaults[*]:-}}"
    for n in ${answer//,/ }; do
      [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#candidates[@]} )) && echo "${candidates[n-1]}"
    done
  fi
}

mapfile -t CHOSEN < <(choose) || true
(( ${#CHOSEN[@]} )) || { echo "Nothing selected."; exit 0; }
KEEP=()
for id in "${CHOSEN[@]}"; do
  [[ -n "${C_FILE[$id]:-}" && "${C_HIDDEN[$id]}" != 1 ]] || die "unknown part: $id (see ./install.sh --list)"
  [[ "$ACTION" == install && -n "${C_UNSUPPORTED[$id]}" ]] && die "$id can't be installed here: ${C_UNSUPPORTED[$id]}"
  if [[ "$ACTION" == uninstall ]] && ! is_installed "$id"; then warn "$id isn't installed; skipped"; continue; fi
  KEEP+=("$id")
done
CHOSEN=("${KEEP[@]}")
(( ${#CHOSEN[@]} )) || exit 0

# ---- run one component in a subshell, so its definitions don't leak --------------
run_component() {   # run_component install|uninstall ID
  local action="$1" id="$2" rc
  set +e
  (
    set -e
    COMPONENT="$id"
    # shellcheck source=/dev/null
    source "${C_FILE[$id]}"
    if [[ "$action" == install ]]; then
      component_install
      mark_installed "$id"
    else
      component_uninstall
      restore_keys "$id"
      restore_files "$id"
      remove_tracked_paths "$id"
      release_extensions "$id"
      mark_removed "$id"
    fi
  )
  rc=$?
  set -e
  return $rc
}

# internal parts (theme build, shell theme, Light/Dark sync) needed by what is installed
needed_internal() {
  local id dep
  declare -A want=()
  for id in "${USER_IDS[@]}"; do
    is_installed "$id" || continue
    for dep in ${C_NEEDS[$id]}; do want[$dep]=1; for d2 in ${C_NEEDS[$dep]}; do want[$d2]=1; done; done
  done
  for id in "${ALL_IDS[@]}"; do [[ -n "${want[$id]:-}" ]] && echo "$id"; done
}

# ---- confirm ----------------------------------------------------------------------
echo
if [[ "$ACTION" == install ]]; then echo "${C_B}Installing:${C_0}"; else echo "${C_B}Removing:${C_0}"; fi
for id in "${CHOSEN[@]}"; do echo "  • ${C_TITLE[$id]}"; done
if (( ! YES )) && [[ -t 0 ]]; then
  read -r -p "Continue? [Y/n] " a
  [[ "${a:-y}" =~ ^[Yy] ]] || exit 0
fi

FAILED=()
if [[ "$ACTION" == install ]]; then
  # packages for the chosen parts and the internal parts they need, in one apt run
  declare -A plan=()
  for id in "${CHOSEN[@]}"; do
    plan[$id]=1
    for dep in ${C_NEEDS[$id]}; do plan[$dep]=1; for d2 in ${C_NEEDS[$dep]}; do plan[$d2]=1; done; done
  done
  missing=()
  for id in "${!plan[@]}"; do
    for pkg in ${C_APT[$id]}; do
      [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null)" == 'install ok installed' ]] ||
        [[ " ${missing[*]} " == *" $pkg "* ]] || missing+=("$pkg")
    done
  done
  if (( ${#missing[@]} )) && [[ "${LIKE_A_MAC_SKIP_APT:-0}" == 1 ]]; then
    warn "not installing packages (LIKE_A_MAC_SKIP_APT=1): ${missing[*]}"
  elif (( ${#missing[@]} )); then
    command -v apt-get > /dev/null || die "please install these packages first: ${missing[*]}"
    say "Installing packages: ${missing[*]} (asks for your password)"
    sudo apt-get update -qq
    sudo apt-get install -y "${missing[@]}"
  fi

  # theme build first (00-), then the chosen parts, then shell theme and sync (80-, 90-)
  for id in "${ALL_IDS[@]}"; do
    [[ -n "${plan[$id]:-}" ]] || continue
    [[ "${C_HIDDEN[$id]}" == 1 && "$id" != mactahoe ]] && continue   # done after, see below
    [[ "$id" == mactahoe ]] && is_installed mactahoe && continue      # built once
    say "${C_TITLE[$id]}"
    run_component install "$id" || FAILED+=("$id")
  done
else
  for id in "${CHOSEN[@]}"; do
    say "Removing ${C_TITLE[$id]}"
    run_component uninstall "$id" || FAILED+=("$id")
  done
fi

# ---- bring the internal parts in line with what is installed now -------------------
mapfile -t NEED < <(needed_internal)
for id in "${ALL_IDS[@]}"; do
  [[ "${C_HIDDEN[$id]}" == 1 && "$id" != mactahoe ]] || continue
  if [[ " ${NEED[*]} " == *" $id "* ]]; then
    say "${C_TITLE[$id]}"
    run_component install "$id" || FAILED+=("$id")      # rebuilt: its contents depend on the others
  elif is_installed "$id"; then
    run_component uninstall "$id" || FAILED+=("$id")
  fi
done
if is_installed mactahoe && [[ " ${NEED[*]} " != *" mactahoe "* ]]; then
  run_component uninstall mactahoe || FAILED+=(mactahoe)
fi

echo
if (( ${#FAILED[@]} )); then
  warn "these didn't finish: ${FAILED[*]} (logs in $LAM_STATE)"
fi
ok "Done."
if [[ "${XDG_SESSION_TYPE:-}" == wayland ]]; then
  echo "   Log out and back in to see every change."
else
  echo "   Log out and back in to see every change (or press Alt+F2, type r, Enter)."
fi
(( ${#FAILED[@]} == 0 ))
