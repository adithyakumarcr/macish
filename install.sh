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
declare -A C_FILE C_TITLE C_DESC C_DEFAULT C_HIDDEN C_NEEDS C_APT C_UNSUPPORTED C_SUDO
ALL_IDS=()
for f in "$LAM_DIR"/components/*.sh; do
  IFS=$'\t' read -r id title desc def hidden needs apt unsupported sudo < <(
    unset -f component_supported
    ID= TITLE= DESC= DEFAULT=on HIDDEN=0 NEEDS= APT=() SUDO=0
    # shellcheck source=/dev/null
    source "$f"
    why=
    if declare -F component_supported > /dev/null; then why="$(component_supported)" || true; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ID" "$TITLE" "${DESC:--}" "$DEFAULT" "$HIDDEN" \
      "${NEEDS:--}" "${APT[*]:--}" "${why:--}" "$SUDO")
  ALL_IDS+=("$id")
  C_FILE[$id]="$f"; C_TITLE[$id]="$title"; C_DESC[$id]="${desc#-}"; C_DEFAULT[$id]="$def"
  C_HIDDEN[$id]="$hidden"; C_NEEDS[$id]="${needs#-}"; C_APT[$id]="${apt#-}"; C_UNSUPPORTED[$id]="${unsupported#-}"
  C_SUDO[$id]="$sudo"   # 1: the part itself runs sudo (the password is asked once, up front)
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
    state="        "
    if is_installed "$id"; then state="[installed]"; elif has_state "$id"; then state="[partly installed]"; fi
    [[ -n "${C_UNSUPPORTED[$id]}" ]] && state="[n/a: ${C_UNSUPPORTED[$id]}]"
    printf '  %-16s %-28s %s  %s\n' "$id" "${C_TITLE[$id]}" "${C_DESC[$id]}" "$state"
  done
  exit 0
fi

# ---- choose -----------------------------------------------------------------------
# The menu runs when you start ./install.sh in a terminal without --only or --all
MENU=0
[[ -z "$ONLY" ]] && (( ! ALL )) && [[ -t 0 && -t 2 ]] && MENU=1

banner() {
  printf '%s\n' '==================================================' \
    '         MAKE YOUR UBUNTU, WORK LIKE MAC' \
    '==================================================' >&2
}

# checklist ID...: arrows (or j/k) move, Space ticks, a ticks or unticks all, Enter starts,
# q quits. Draws on the terminal and prints the ticked ids, one per line.
checklist() {
  local ids=("$@") on=() n=$# cur=0 top=0 i id key rest rows cols shown line mark verb all
  local width=0
  verb=install; [[ "$ACTION" == uninstall ]] && verb=remove
  for id in "${ids[@]}"; do
    if [[ "$ACTION" == install && "${C_DEFAULT[$id]}" == on ]]; then on+=(1); else on+=(0); fi
    (( ${#C_TITLE[$id]} > width )) && width=${#C_TITLE[$id]}
  done
  printf '\e[?1049h\e[?25l' >&2                  # a screen of its own, without the cursor
  trap 'printf "\e[?25h\e[?1049l" >&2' EXIT
  while true; do
    read -r rows cols < <(stty size < /dev/tty)
    shown=$(( rows - 10 )); (( shown < 3 )) && shown=3
    (( cur < top )) && top=$cur
    (( cur >= top + shown )) && top=$(( cur - shown + 1 ))
    {
      printf '\e[H\e[J'
      banner
      if [[ "$ACTION" == install ]]; then printf '\n Choose what to install:\n\n'
      else printf '\n Choose what to remove (your earlier settings come back):\n\n'; fi
      for (( i = top; i < n && i < top + shown; i++ )); do
        id="${ids[i]}"; mark=' '; (( on[i] )) && mark=x
        line="[$mark] $(printf '%-*s' "$width" "${C_TITLE[$id]}")  ${C_DESC[$id]}"
        [[ "$ACTION" == install ]] && is_installed "$id" && line+="  (installed)"
        line="${line:0:cols-4}"
        if (( i == cur )); then printf ' \e[7m %s \e[0m\n' "$line"; else printf '  %s\n' "$line"; fi
      done
      if (( top + shown < n )); then printf '   ...\n'; else printf '\n'; fi
      # The keys stand out: most people would otherwise just press Enter
      printf '\n \e[1;7m ↑↓ \e[0m \e[1mmove\e[0m    \e[1;7m Space \e[0m \e[1mselect\e[0m    \e[1;7m a \e[0m \e[1mall\e[0m'
      printf '    \e[1;7m Enter \e[0m \e[1m%s\e[0m    \e[1;7m q \e[0m \e[1mquit\e[0m' "$verb"
    } >&2
    IFS= read -rsn1 key < /dev/tty
    case "$key" in
      $'\e')
        rest=''; IFS= read -rsn2 -t 0.05 rest < /dev/tty || true
        case "$rest" in
          '[A'|OA) (( cur > 0 )) && cur=$(( cur - 1 )) ;;
          '[B'|OB) (( cur < n - 1 )) && cur=$(( cur + 1 )) ;;
          '') return 1 ;;                         # Esc on its own
        esac ;;
      k) (( cur > 0 )) && cur=$(( cur - 1 )) ;;
      j) (( cur < n - 1 )) && cur=$(( cur + 1 )) ;;
      ' ') on[cur]=$(( 1 - on[cur] )) ;;
      a|A)
        all=0; for i in "${!on[@]}"; do (( on[i] )) || all=1; done
        for i in "${!on[@]}"; do on[i]=$all; done ;;
      q|Q) return 1 ;;
      '') break ;;                                # Enter
    esac
  done
  printf '\e[?25h\e[?1049l' >&2
  trap - EXIT
  for i in "${!ids[@]}"; do (( on[i] )) && echo "${ids[i]}"; done
  return 0
}

choose() {   # prints the chosen ids, one per line
  local candidates=() id i=1 defaults=() answer n
  for id in "${USER_IDS[@]}"; do
    if [[ "$ACTION" == uninstall ]]; then has_state "$id" && candidates+=("$id")
    else [[ -z "${C_UNSUPPORTED[$id]}" ]] && candidates+=("$id"); fi
  done
  (( ${#candidates[@]} )) || { [[ "$ACTION" == uninstall ]] && echo "Nothing from like_a_mac is installed." >&2; return 0; }

  if [[ -n "$ONLY" ]]; then
    tr ',' '\n' <<< "$ONLY"; return
  elif (( ALL )); then
    printf '%s\n' "${candidates[@]}"; return
  elif (( MENU )); then
    checklist "${candidates[@]}"; return
  fi

  # Not a terminal the menu can draw on: numbers instead
  banner
  echo "Choose what to $([[ "$ACTION" == uninstall ]] && echo remove || echo install):" >&2
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
  return 0
}

mapfile -t CHOSEN < <(choose) || true
(( ${#CHOSEN[@]} )) || { echo "Nothing selected."; exit 0; }
KEEP=()
for id in "${CHOSEN[@]}"; do
  [[ -n "${C_FILE[$id]:-}" && "${C_HIDDEN[$id]}" != 1 ]] || die "unknown part: $id (see ./install.sh --list)"
  [[ "$ACTION" == install && -n "${C_UNSUPPORTED[$id]}" ]] && die "$id can't be installed here: ${C_UNSUPPORTED[$id]}"
  if [[ "$ACTION" == uninstall ]] && ! has_state "$id"; then warn "$id isn't installed; skipped"; continue; fi
  KEEP+=("$id")
done
CHOSEN=("${KEEP[@]}")
(( ${#CHOSEN[@]} )) || exit 0

# ---- run one component in a subshell, so its definitions don't leak --------------
run_component() {   # run_component install|uninstall ID  (call it through try_component)
  local action="$1" id="$2"
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
}

# try_component install|uninstall ID - runs it and notes a failure in FAILED. Never as
# "run_component ... || ...": bash ignores set -e in anything followed by ||, so a part would
# carry on after a failed command and be marked installed.
try_component() {
  local rc
  set +e
  run_component "$@"
  rc=$?
  set -e
  (( rc == 0 )) || FAILED+=("$2")
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
# The menu's Enter already said go; --only and --all still ask, unless -y
if (( ! YES && ! MENU )) && [[ -t 0 ]]; then
  read -r -p "Continue? [Y/n] " a
  [[ "${a:-y}" =~ ^[Yy] ]] || exit 0
fi

# packages for the chosen parts and the internal parts they need, in one apt run
declare -A plan=()
missing=()
if [[ "$ACTION" == install ]]; then
  for id in "${CHOSEN[@]}"; do
    plan[$id]=1
    for dep in ${C_NEEDS[$id]}; do plan[$dep]=1; for d2 in ${C_NEEDS[$dep]}; do plan[$d2]=1; done; done
  done
  for id in "${!plan[@]}"; do
    for pkg in ${C_APT[$id]}; do
      [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null)" == 'install ok installed' ]] ||
        [[ " ${missing[*]} " == *" $pkg "* ]] || missing+=("$pkg")
    done
  done
  if (( ${#missing[@]} )) && [[ "${LIKE_A_MAC_SKIP_APT:-0}" == 1 ]]; then
    warn "not installing packages (LIKE_A_MAC_SKIP_APT=1): ${missing[*]}"
    missing=()
  fi
fi

# ---- the password, once -------------------------------------------------------------
# Asked here, before anything changes, and kept valid to the end: no part stops to ask again.
need=()
for id in "${CHOSEN[@]}"; do [[ "${C_SUDO[$id]}" == 1 ]] && need+=("${C_TITLE[$id]}"); done
(( ${#missing[@]} )) && need+=("packages (${missing[*]})")
if (( ${#need[@]} )); then
  echo
  printf 'Your password is needed for: %s.\n' "$(printf '%s, ' "${need[@]}" | sed 's/, $//')"
  echo "It's asked once, now:"
  sudo -v || die "no password given; nothing was changed"
  ( while kill -0 $$ 2> /dev/null; do sudo -n -v 2> /dev/null; sleep 30; done ) &
  SUDO_KEEPALIVE=$!
  trap 'kill "$SUDO_KEEPALIVE" 2> /dev/null' EXIT
fi

FAILED=()
if [[ "$ACTION" == install ]]; then
  if (( ${#missing[@]} )); then
    command -v apt-get > /dev/null || die "please install these packages first: ${missing[*]}"
    say "Installing packages: ${missing[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${missing[@]}"
  fi

  # theme build first (00-), then the chosen parts, then shell theme and sync (80-, 90-)
  for id in "${ALL_IDS[@]}"; do
    [[ -n "${plan[$id]:-}" ]] || continue
    [[ "${C_HIDDEN[$id]}" == 1 && "$id" != mactahoe ]] && continue   # done after, see below
    [[ "$id" == mactahoe ]] && is_installed mactahoe && continue      # built once
    say "${C_TITLE[$id]}"
    try_component install "$id"
  done
else
  for id in "${CHOSEN[@]}"; do
    say "Removing ${C_TITLE[$id]}"
    try_component uninstall "$id"
  done
fi

# ---- bring the internal parts in line with what is installed now -------------------
mapfile -t NEED < <(needed_internal)
for id in "${ALL_IDS[@]}"; do
  [[ "${C_HIDDEN[$id]}" == 1 && "$id" != mactahoe ]] || continue
  if [[ " ${NEED[*]} " == *" $id "* ]]; then
    say "${C_TITLE[$id]}"
    try_component install "$id"      # rebuilt: its contents depend on the others
  elif is_installed "$id"; then
    try_component uninstall "$id"
  fi
done
if is_installed mactahoe && [[ " ${NEED[*]} " != *" mactahoe "* ]]; then
  try_component uninstall mactahoe
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
