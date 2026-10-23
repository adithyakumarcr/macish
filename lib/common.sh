# Shared helpers for macish components. Sourced by install.sh.
# shellcheck shell=bash

LAM_STATE="${XDG_DATA_HOME:-$HOME/.local/share}/like-a-mac"
LAM_SRC="$LAM_STATE/src"            # cloned upstream projects
LAM_SAVED="$LAM_STATE/saved"        # what each component changed, so it can be undone
LAM_INSTALLED="$LAM_STATE/installed"
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
SHELL_MAJOR="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"

# Upstream projects, pinned to the commits this was tested with.
# Set LIKE_A_MAC_LATEST=1 to use their newest versions instead.
declare -A LAM_REPOS=(
  [MacTahoe-gtk-theme]="https://github.com/vinceliuice/MacTahoe-gtk-theme 09198632e789f72ed46574812ef6d389a53809f0"
  [MacTahoe-icon-theme]="https://github.com/vinceliuice/MacTahoe-icon-theme 839848b9a8a38a92a6936e30c4abe35cc6f2546d"
  [MacOS-Like]="https://github.com/Scrimas/MacOS-Like efbc63d48d52bbaf52e9a70fb18e0d0c3c0719b2"
  [WhiteSur-cursors]="https://github.com/vinceliuice/WhiteSur-cursors e190baf618ed95ee217d2fd45589bd309b37672b"
  [omdrop-owl]="https://github.com/t4t5/omdrop-owl 8213aee9f018ffd78a3fc71863a364fcddd938cd"
  [omdrop-plugin]="https://github.com/netmojo-systems/omdrop-plugin ff320344329ffaee2c67a2f6f6dcd18cea827201"
)

if [[ -t 1 ]]; then
  C_B=$'\e[1m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_0=$'\e[0m'
else
  C_B=; C_G=; C_Y=; C_R=; C_0=
fi
say()  { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%s  ✗%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

mkdir -p "$LAM_SRC" "$LAM_SAVED"
touch "$LAM_INSTALLED"

# ---- installed components ---------------------------------------------------
is_installed() { grep -qx "$1" "$LAM_INSTALLED"; }
mark_installed() { is_installed "$1" || echo "$1" >> "$LAM_INSTALLED"; }
mark_removed() { sed -i "/^$1\$/d" "$LAM_INSTALLED"; }
any_installed() { local c; for c in "$@"; do is_installed "$c" && return 0; done; return 1; }
# has_state ID  - installed, or left saved state behind (an install that failed halfway), so
# uninstall still has something to undo
has_state() { is_installed "$1" || compgen -G "$LAM_SAVED/$1.*" > /dev/null; }

# ---- upstream sources ---------------------------------------------------------
# fetch_repo NAME -> prints the checkout directory
fetch_repo() {
  local name="$1" url sha dir
  read -r url sha <<< "${LAM_REPOS[$name]}"
  dir="$LAM_SRC/$name"
  if [[ "${LIKE_A_MAC_LATEST:-0}" == 1 ]]; then
    if [[ -d "$dir/.git" ]]; then
      git -C "$dir" fetch -q --depth 1 origin HEAD && git -C "$dir" checkout -q FETCH_HEAD
    else
      git clone -q --depth 1 "$url" "$dir"
    fi
  elif [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$sha" ]]; then
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" fetch -q --depth 1 "$url" "$sha"
    git -C "$dir" checkout -q FETCH_HEAD
  fi >&2
  echo "$dir"
}

# ---- settings, remembered so uninstall can put the old value back ------------
# set_key /org/gnome/.../key "GVariant value"   (uses $COMPONENT)
set_key() {
  local key="$1" value="$2" file="$LAM_SAVED/$COMPONENT.keys"
  touch "$file"
  if ! grep -qF "$key"$'\t' "$file"; then
    printf '%s\t%s\n' "$key" "$(dconf read "$key")" >> "$file"
  fi
  dconf write "$key" "$value"
}

# add_binding SCHEMA KEY ACCEL  - GNOME also answers to ACCEL; yours stay
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

restore_keys() {
  local file="$LAM_SAVED/$1.keys" key old
  [[ -f "$file" ]] || return 0
  while IFS=$'\t' read -r key old; do
    if [[ -z "$old" ]]; then dconf reset "$key"; else dconf write "$key" "$old"; fi
  done < "$file"
  rm -f "$file"
}

# ---- files and folders we create, removed again on uninstall ------------------
# track_path PATH   - call BEFORE creating PATH; only new paths are recorded
track_path() {
  local file="$LAM_SAVED/$COMPONENT.paths"
  [[ -e "$1" || -L "$1" ]] && return 0
  grep -qxF "$1" "$file" 2>/dev/null || echo "$1" >> "$file"
}

remove_tracked_paths() {
  local file="$LAM_SAVED/$1.paths" p
  [[ -f "$file" ]] || return 0
  while IFS= read -r p; do
    [[ -n "$p" && "$p" == "$HOME"/* ]] && rm -rf -- "$p"
  done < "$file"
  rm -f "$file"
}

# backup_file PATH  - keeps the user's own copy so uninstall can restore it
backup_file() {
  local src="$1" dst="$LAM_SAVED/$COMPONENT.files/${1#"$HOME"/}"
  [[ -e "$dst" || -e "$dst.absent" ]] && return 0
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$src" ]]; then cp -a "$src" "$dst"; else touch "$dst.absent"; fi
}

restore_files() {
  local root="$LAM_SAVED/$1.files" f rel
  [[ -d "$root" ]] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$root"/}"
    if [[ "$rel" == *.absent ]]; then
      rm -rf -- "$HOME/${rel%.absent}"
    else
      mkdir -p "$(dirname "$HOME/$rel")"
      rm -rf -- "${HOME:?}/$rel"
      cp -a "$f" "$HOME/$rel"
    fi
  done < <(find "$root" -mindepth 1 \( -type f -o -type l \) -print0)
  rm -rf "$root"
}

# ---- GNOME Shell extensions --------------------------------------------------
enabled_list() { gsettings get org.gnome.shell "$1"; }

# list_edit KEY add|remove UUID
list_edit() {
  local new
  new="$(python3 - "$(enabled_list "$1")" "$2" "$3" <<'PY'
import ast, sys
raw, op, uuid = sys.argv[1:]
items = ast.literal_eval(raw.replace('@as ', ''))
items = [i for i in items if i != uuid]
if op == 'add':
    items.append(uuid)
print(repr(items))
PY
)"
  gsettings set org.gnome.shell "$1" "$new"
}

# ext_use UUID  - installs (from extensions.gnome.org if missing) and enables it
ext_use() {
  local uuid="$1" info url tmp
  if [[ ! -d "$EXT_DIR/$uuid" && ! -d "/usr/share/gnome-shell/extensions/$uuid" ]]; then
    info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$SHELL_MAJOR")" ||
      { warn "$uuid has no version for GNOME $SHELL_MAJOR; skipped"; return 1; }
    url="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["download_url"])' <<< "$info")"
    tmp="$(mktemp --suffix=.zip)"
    curl -fsSL "https://extensions.gnome.org$url" -o "$tmp"
    gnome-extensions install --force "$tmp"
    rm -f "$tmp"
    echo "$uuid" >> "$LAM_STATE/extensions-downloaded"
    ok "downloaded extension $uuid"
  fi
  list_edit disabled-extensions remove "$uuid"
  list_edit enabled-extensions add "$uuid"
  gsettings set org.gnome.shell disable-user-extensions false
  grep -qxF "$uuid" "$LAM_SAVED/$COMPONENT.ext" 2>/dev/null || echo "$uuid" >> "$LAM_SAVED/$COMPONENT.ext"
}

# Disables (and deletes, if we downloaded it) every extension this component used,
# unless another installed component still needs it.
release_extensions() {
  local comp="$1" uuid other used
  [[ -f "$LAM_SAVED/$comp.ext" ]] || return 0
  while IFS= read -r uuid; do
    used=0
    while IFS= read -r other; do
      [[ "$other" != "$comp" ]] && grep -qxF "$uuid" "$LAM_SAVED/$other.ext" 2>/dev/null && used=1
    done < "$LAM_INSTALLED"
    (( used )) && continue
    list_edit enabled-extensions remove "$uuid"
    if grep -qxF "$uuid" "$LAM_STATE/extensions-downloaded" 2>/dev/null; then
      rm -rf -- "${EXT_DIR:?}/$uuid"
      sed -i "/^$uuid\$/d" "$LAM_STATE/extensions-downloaded"
    fi
  done < "$LAM_SAVED/$comp.ext"
  rm -f "$LAM_SAVED/$comp.ext"
}

# ---- light / dark -------------------------------------------------------------
current_mode() {
  [[ "$(gsettings get org.gnome.desktop.interface color-scheme)" == "'prefer-dark'" ]] && echo dark || echo light
}
