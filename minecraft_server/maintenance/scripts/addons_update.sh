#!/usr/bin/env bash
# Copyright Roman Glos 2026
# addons_update.sh — Roman fix v2 (adds dedupe_or_mark to avoid 'command not found')
# Version 23.02.2026

# --- compatibility: ensure /scripts exists when only /scripts_ro is mounted (read-only) ---
if [ ! -e /scripts ] && [ -d /scripts_ro ]; then
  ln -snf /scripts_ro /scripts || true
fi
# --- /compat ---

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ -f /scripts/lib_i18n.sh ] && . /scripts/lib_i18n.sh || [ -f "$SCRIPT_DIR/lib_i18n.sh" ] && . "$SCRIPT_DIR/lib_i18n.sh"
[ -f /scripts/lib_notify.sh ] && . /scripts/lib_notify.sh || [ -f "$SCRIPT_DIR/lib_notify.sh" ] && . "$SCRIPT_DIR/lib_notify.sh"
[ -f /scripts/lib_stack.sh ] && . /scripts/lib_stack.sh || [ -f "$SCRIPT_DIR/lib_stack.sh" ] && . "$SCRIPT_DIR/lib_stack.sh"

# --- TESTSCHALTER: nur Restart-Zeile ausgeben und beenden ---
if [ "${TEST_RESTART_LINE:-0}" = "1" ]; then
  : "${MC_CONTAINERS:=}"
  [ -n "$MC_CONTAINERS" ] || MC_CONTAINERS="$(enabled_mc_containers 2>/dev/null || printf '%s' 'minecraftserver_creative minecraftserver_survival')"
  : "${LOG_PREFIX:=[info ]}"
  TS="$(fmt_now_long 2>/dev/null || TZ="${TZ:-Europe/Berlin}" date +'%d.%m.%Y %H:%M Uhr')"
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    echo "$LOG_PREFIX Änderungen erkannt ${TS} -> Restart: $MC_CONTAINERS"
  else
    echo "$LOG_PREFIX Changes detected ${TS} -> restart: $MC_CONTAINERS"
  fi
  exit 0
fi
# --- /TESTSCHALTER ---

set -Eeuo pipefail

[[ "${DEBUG:-}" =~ ^(1|true|TRUE)$ ]] && set -x

LOG_PREFIX="[info ]"
WARN_PREFIX="[warn ]"
ERR_PREFIX="[error]"

: "${CREATIVE_WORLD:=${CREATIVE_LEVEL_NAME:-creative}}"
: "${SURVIVAL_WORLD:=${SURVIVAL_LEVEL_NAME:-Glosis}}"
ROOT_CREATIVE="/creative"
ROOT_SURVIVAL="/survival"
REPO="/repo"

APPRISE_URL="${APPRISE_URL:-}"
NOTIFY_CHANNEL="${NOTIFY_CHANNEL:-auto}"
MC_AUTO_RESTART="${MC_AUTO_RESTART:-false}"
MC_CONTAINERS="${MC_CONTAINERS:-}"
[ -n "$MC_CONTAINERS" ] || MC_CONTAINERS="$(enabled_mc_containers 2>/dev/null || printf %s "")"

# --- Änderungssammlung für Benachrichtigung ---
CHANGE_LOG_FILE="/tmp/addons_update.last"
declare -a CHANGES=()
LAST_COPY_CHANGED=0

# Restart-Ergebnis (für Nachricht)
RESTART_OK=""
RESTART_FAIL=""

data_root() {
  local root="$1"
  if [[ -d "$root/worlds" || -d "$root/behavior_packs" || -d "$root/resource_packs" ]]; then
    echo "$root"
  elif [[ -d "$root/data" ]]; then
    echo "$root/data"
  else
    echo "$root"
  fi
}
bp_dir() { echo "$(data_root "$1")/behavior_packs"; }
rp_dir() { echo "$(data_root "$1")/resource_packs"; }
world_bp_json() { echo "$(data_root "$1")/worlds/$2/world_behavior_packs.json"; }
world_rp_json() { echo "$(data_root "$1")/worlds/$2/world_resource_packs.json"; }

need_bin() {
  command -v "$1" >/dev/null 2>&1 && return 0
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    echo "$ERR_PREFIX fehlt: $1" >&2
  else
    echo "$ERR_PREFIX missing: $1" >&2
  fi
  exit 1
}
for b in unzip rsync jq python3 sed; do need_bin "$b"; done
command -v 7z >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v docker >/dev/null 2>&1 || true

parse_manifest() {
  local manifest="$1"
  python3 - "$manifest" << 'PY'
import sys, json, re, os

p = sys.argv[1]

def strip_json_comments(s: str) -> str:
  # Remove // line comments and /* */ block comments outside of strings.
  # Keeps newlines (so error locations remain roughly stable).
  if s.startswith("\ufeff"):
    s = s.lstrip("\ufeff")

  out = []
  i = 0
  in_str = False
  str_ch = ""
  esc = False
  in_line = False
  in_block = False

  while i < len(s):
    ch = s[i]
    nxt = s[i + 1] if i + 1 < len(s) else ""

    if in_line:
      if ch in "\r\n":
        in_line = False
        out.append(ch)
      i += 1
      continue

    if in_block:
      if ch == "*" and nxt == "/":
        in_block = False
        i += 2
      else:
        i += 1
      continue

    if in_str:
      out.append(ch)
      if esc:
        esc = False
      elif ch == "\\":  # escape
        esc = True
      elif ch == str_ch:
        in_str = False
      i += 1
      continue

    if ch in ("\"", "'"):
      in_str = True
      str_ch = ch
      out.append(ch)
      i += 1
      continue

    if ch == "/" and nxt == "/":
      in_line = True
      i += 2
      continue

    if ch == "/" and nxt == "*":
      in_block = True
      i += 2
      continue

    out.append(ch)
    i += 1

  return "".join(out)

def load_manifest(path: str):
  try:
    raw = open(path, "r", encoding="utf-8").read()
  except Exception:
    print(f"ERROR\t{path}\tread\t-", flush=True)
    sys.exit(0)

  cleaned = strip_json_comments(raw)
  try:
    return json.loads(cleaned)
  except Exception:
    # tolerate a common authoring issue: trailing commas
    cleaned2 = re.sub(r",\s*(\]|\})", r"\1", cleaned)
    try:
      return json.loads(cleaned2)
    except Exception:
      print(f"ERROR\t{path}\tjson\t-", flush=True)
      sys.exit(0)

m = load_manifest(p)

name = m.get("header", {}).get("name") or m.get("name") or "unknown"
ver  = m.get("header", {}).get("version") or m.get("version") or [1, 0, 0]
uuid = m.get("header", {}).get("uuid") or m.get("uuid") or ""

modules = m.get("modules") or []
module_types = set()
if isinstance(modules, list):
  for mod in modules:
    if isinstance(mod, dict):
      t = mod.get("type")
      if isinstance(t, str):
        module_types.add(t.strip().lower())

# Determine pack kind by module types.
kind = "unknown"
if "resources" in module_types and not ({"data", "script"} & module_types):
  kind = "resource"
elif {"data", "script"} & module_types:
  kind = "behavior"
elif "client_data" in module_types:
  kind = "behavior"
elif "interface" in module_types:
  kind = "resource"
elif "world_template" in module_types:
  kind = "world_template"

# Heuristic fallback (in case of strange manifests)
if kind == "unknown":
  base = os.path.dirname(p)
  try:
    entries = set(os.listdir(base))
  except Exception:
    entries = set()
  if {"textures", "sounds", "texts", "ui", "models", "render_controllers"} & entries:
    kind = "resource"
  elif {"entities", "functions", "loot_tables", "recipes", "spawn_rules", "items", "blocks", "scripts"} & entries:
    kind = "behavior"

if not uuid:
  print(f"ERROR\t{p}\tno_uuid\t-", flush=True)
  sys.exit(0)

def as_ver(v):
  if isinstance(v, list) and len(v) >= 1:
    a = (v + [0, 0, 0])[:3]
    return [int(a[0]), int(a[1]), int(a[2])]
  if isinstance(v, str):
    parts = [z for z in re.split(r"[., ]+", v) if z.strip()]
    ints = []
    for z in parts[:3]:
      try: ints.append(int(z))
      except: ints.append(0)
    while len(ints) < 3: ints.append(0)
    return ints[:3]
  return [1, 0, 0]

v = as_ver(ver)
print(f"OK\t{p}\t{kind}\t{uuid}\t{v[0]}\t{v[1]}\t{v[2]}\t{name}", flush=True)
PY
}

ensure_world_json() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  if [[ ! -s "$file" ]] || ! jq -e type >/dev/null 2>&1 <"$file"; then
    echo "[]" > "$file"
  fi
  chmod 0644 "$file" 2>/dev/null || true
}

json_contains_uuid() {
  local json_file="$1" uuid="$2"
  jq -e --arg u "$uuid" '.[]? | select(.pack_id==$u)' "$json_file" >/dev/null 2>&1
}

json_upsert_raw() {
  local json_file="$1" uuid="$2" vA="$3" vB="$4" vC="$5"
  ensure_world_json "$json_file"
  if json_contains_uuid "$json_file" "$uuid"; then
    jq --arg u "$uuid" --argjson a "$vA" --argjson b "$vB" --argjson c "$vC" \
       'map(if .pack_id==$u then .version=[$a,$b,$c] else . end)' \
       "$json_file" > "${json_file}.tmp" && mv -f "${json_file}.tmp" "$json_file"
  else
    jq --arg u "$uuid" --argjson a "$vA" --argjson b "$vB" --argjson c "$vC" \
       '. += [{"pack_id":$u,"version":[$a,$b,$c]}]' \
       "$json_file" > "${json_file}.tmp" && mv -f "${json_file}.tmp" "$json_file"
  fi
  chmod 0644 "$json_file" 2>/dev/null || true
}

rsync_would_change() {
  local src="$1" dest="$2" root_for_chown="${3:-}"
  [[ ! -d "$dest" ]] && return 0
  local chown_flag=""; [ -n "$root_for_chown" ] && chown_flag="$(rsync_chown_for_root "$root_for_chown")"
  local out; out="$(rsync -i $RSYNC_FLAGS_BASE $RSYNC_PERM_FLAGS $chown_flag --dry-run "$src/" "$dest/" || true)"
  [[ -n "$out" ]]
}

# rsync flags:
RSYNC_FLAGS_BASE='-a --delete --checksum --omit-dir-times'
# default perms: dirs 775, files 664
RSYNC_PERM_FLAGS='--chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r'

# compute --chown for a given data root; falls back to TARGET_UID/GID env or stat on data_root
rsync_chown_for_root() {
  local root="$1"
  local d; d="$(data_root "$root")"
  local uid gid
  uid="${TARGET_UID:-$(stat -c %u "$d" 2>/dev/null || echo 0)}"
  gid="${TARGET_GID:-$(stat -c %g "$d" 2>/dev/null || echo 0)}"
  if [ "$uid" != "0" ] || [ "$gid" != "0" ]; then
    printf -- '--chown=%s:%s' "$uid" "$gid"
  else
    printf -- ''
  fi
}

PACKS_CHANGED=0

copy_pack() {
  local src="$1" dest_root="$2" kind="$3" uuid="$4"
  local dest_dir
  LAST_COPY_CHANGED=0
  if [[ "$kind" == "behavior" ]]; then dest_dir="$(bp_dir "$dest_root")"; else dest_dir="$(rp_dir "$dest_root")"; fi
  mkdir -p "$dest_dir/$uuid"
  # ensure dir ownership/mode so Bedrock UID/GID can modify/delete
  chown -hR $(stat -c %u "$(data_root "$dest_root")" 2>/dev/null || echo 0):$(stat -c %g "$(data_root "$dest_root")" 2>/dev/null || echo 0) "$dest_dir" 2>/dev/null || true
  chmod -R u+rwX,g+rwX "$dest_dir" 2>/dev/null || true
  if rsync_would_change "$src" "$dest_dir/$uuid" "$dest_root"; then
    if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
      echo "$LOG_PREFIX kopiere per rsync kind=$kind src='$src' -> '$dest_dir/$uuid/'"
    else
      echo "$LOG_PREFIX rsync copy kind=$kind src='$src' -> '$dest_dir/$uuid/'"
    fi
    local chown_flag; chown_flag="$(rsync_chown_for_root "$dest_root")"
    rsync $RSYNC_FLAGS_BASE $RSYNC_PERM_FLAGS $chown_flag "$src/" "$dest_dir/$uuid/"
    PACKS_CHANGED=1
    LAST_COPY_CHANGED=1
  else
    if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
      echo "$LOG_PREFIX keine Änderungen für kind=$kind uuid=$uuid"
    else
      echo "$LOG_PREFIX no changes for kind=$kind uuid=$uuid"
    fi
  fi
}

scan_pack_dir() { find "$1" -type f -iname manifest.json -print0; }
unpack_any() {
  local file="$1" outdir="$2"
  if unzip -qq -o "$file" -d "$outdir" >/dev/null 2>&1; then return 0; fi
  if command -v 7z >/dev/null 2>&1 && 7z x -y -o"$outdir" "$file" >/dev/null 2>&1; then return 0; fi
  return 1
}
expand_nested_archives() {
  local root="$1"
  for pass in 1 2; do
    mapfile -d '' -t nested < <(find "$root" -type f \( -iname "*.mcpack" -o -iname "*.zip" \) -print0)
    [[ ${#nested[@]} -eq 0 ]] && break
    for z in "${nested[@]}"; do
      mkdir -p "${z%.*}"; unpack_any "$z" "${z%.*}" || {
        if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
          echo "$WARN_PREFIX verschachteltes Entpacken fehlgeschlagen: $z"
        else
          echo "$WARN_PREFIX nested extraction failed: $z"
        fi
      }
    done
  done
}

collect_packs() {
  local root="$1" kind="$2"
  declare -g -A found_b=() found_r=()
  while IFS= read -r -d '' mf; do
    local line; line="$(parse_manifest "$mf")" || continue
    IFS=$'\t' read -r status path kind uuid vA vB vC name <<<"$line"
    [[ "$status" != "OK" ]] && {
      if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
        echo "$WARN_PREFIX Manifest unlesbar: $mf"
      else
        echo "$WARN_PREFIX manifest unreadable: $mf"
      fi
      continue
    }
    if [[ "$kind" == "behavior" ]]; then
      found_b["$uuid"]="$vA:$vB:$vC:$(dirname "$mf"):$name"
    elif [[ "$kind" == "resource" ]]; then
      found_r["$uuid"]="$vA:$vB:$vC:$(dirname "$mf"):$name"
    fi
  done < <(scan_pack_dir "$root")
}

# --- Neue Funktion: JSON-Dedupe & Perm-Fix ---
uniq_world_json() {
  local file="$1" dest_root="$2"
  ensure_world_json "$file"
  # gruppiert nach pack_id, behält jeweils den letzten Eintrag
  jq 'if type=="array" then group_by(.pack_id) | map(.[-1]) else . end' "$file" > "${file}.tmp" && mv -f "${file}.tmp" "$file"
  chmod 0644 "$file" 2>/dev/null || true
  local d; d="$(data_root "$dest_root")"
  local uid gid; uid="$(stat -c %u "$d" 2>/dev/null || echo 0)"; gid="$(stat -c %g "$d" 2>/dev/null || echo 0)"
  [ "$uid" != "0" ] || [ "$gid" != "0" ] && chown "$uid:$gid" "$file" 2>/dev/null || true
}

dedupe_or_mark() {
  if command -v creative_enabled >/dev/null 2>&1 && creative_enabled; then
    uniq_world_json "$(world_bp_json "$ROOT_CREATIVE" "$CREATIVE_WORLD")" "$ROOT_CREATIVE"
    uniq_world_json "$(world_rp_json "$ROOT_CREATIVE" "$CREATIVE_WORLD")" "$ROOT_CREATIVE"
  fi
  if command -v survival_enabled >/dev/null 2>&1 && survival_enabled; then
    uniq_world_json "$(world_bp_json "$ROOT_SURVIVAL" "$SURVIVAL_WORLD")" "$ROOT_SURVIVAL"
    uniq_world_json "$(world_rp_json "$ROOT_SURVIVAL" "$SURVIVAL_WORLD")" "$ROOT_SURVIVAL"
  fi
}

process_repo_for_world() {
  local dest_root="$1" world_name="$2" repo_root="$3"
  local world_root; world_root="$(data_root "$dest_root")"
  local tmpdir; tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' RETURN

  # 1) ZIP/MCPACK/MADDON in temp entpacken, inkl. nested
  if compgen -G "$repo_root/*.[zZ][iI][pP]" >/dev/null || compgen -G "$repo_root/*.[mM][cC][pP][aA][cC][kK]" >/dev/null || compgen -G "$repo_root/*.[mM][cC][aA][dD][dD][oO][nN]" >/dev/null; then
    for f in "$repo_root"/*; do
      [[ -f "$f" ]] || continue
      case "$f" in
        *.zip|*.mcpack|*.mcaddon) mkdir -p "$tmpdir/$(basename "$f")"; unpack_any "$f" "$tmpdir/$(basename "$f")" || {
          if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
            echo "$WARN_PREFIX Entpacken fehlgeschlagen: $f"
          else
            echo "$WARN_PREFIX extraction failed: $f"
          fi
        } ;;
      esac
    done
    expand_nested_archives "$tmpdir"
  fi

  # 2) Zusätzliche offene Ordner (bereits entpackte Packs) berücksichtigen
  for d in "$repo_root"/*/ ; do
    [[ -d "$d" ]] || continue
    find "$d" -maxdepth 2 -type f -iname manifest.json | grep -q . || continue
    cp -a "$d" "$tmpdir/." 2>/dev/null || true
  done

  # 3) Alle Packs einsammeln und in Ziel kopieren
  collect_packs "$tmpdir" "both"
  for uuid_meta in "${!found_b[@]}"; do
    IFS=':' read -r vA vB vC dirpath name <<< "${found_b[$uuid_meta]}"
    copy_pack "$dirpath" "$world_root" "behavior" "$uuid_meta"
    json_upsert_raw "$(world_bp_json "$world_root" "$world_name")" "$uuid_meta" "$vA" "$vB" "$vC"
    if [[ $LAST_COPY_CHANGED -eq 1 ]]; then
      CHANGES+=("[$world_name] behavior ${name:-?(ohne Name)}  v${vA}.${vB}.${vC}  (${uuid_meta})")
    fi
  done
  for uuid_meta in "${!found_r[@]}"; do
    IFS=':' read -r vA vB vC dirpath name <<< "${found_r[$uuid_meta]}"
    copy_pack "$dirpath" "$world_root" "resource" "$uuid_meta"
    json_upsert_raw "$(world_rp_json "$world_root" "$world_name")" "$uuid_meta" "$vA" "$vB" "$vC"
    if [[ $LAST_COPY_CHANGED -eq 1 ]]; then
      CHANGES+=("[$world_name] resource ${name:-?(ohne Name)}  v${vA}.${vB}.${vC}  (${uuid_meta})")
    fi
  done

  rm -rf "$tmpdir"; trap - RETURN

  # Abschluss: JSONs hübsch formatieren
  finalize_json_like_gut "$(world_bp_json "$world_root" "$world_name")" "behavior" "$world_root"
  finalize_json_like_gut "$(world_rp_json "$world_root" "$world_name")" "resource"  "$world_root"
}

# --- Notifier mit sicherem JSON-Escaping ---
notify() {
  local title
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    title="Minecraft Addons Aktualisierung"
  else
    title="Minecraft Addons Updater"
  fi
  local msg="$1"

  msg="$(printf %s "$msg" | sed -E 's/§\|//g; s/§[0-9a-frk-or]//gi')"
  msg="$(printf %b "$msg")"

  if command -v notify_dispatch >/dev/null 2>&1; then
    local esc subject html
    esc="$(printf "%s" "$msg" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
    subject="${title} - $(fmt_now_long 2>/dev/null || TZ="${TZ:-Europe/Berlin}" date +'%d.%m.%Y %H:%M Uhr')"
    if [ ${#CHANGES[@]} -gt 0 ]; then
      html="$(build_change_html)"
    else
      html='<pre style="font-family:Consolas,Menlo,Monaco,monospace;white-space:pre-wrap">'"$esc"'</pre>'
    fi
    notify_dispatch "$subject" "$html" "$msg" >/dev/null 2>&1 || true
  fi
}

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

build_change_html() {
  local title hdr_changes lbl_worlds lbl_restart_ok lbl_restart_fail lbl_last_run lbl_changes_count
  local col_world col_type col_name col_version lbl_uuid worlds_info now rows row_count restart_ok_text restart_fail_text
  local line world kind name version uuid re row_html uuid_block name_html

  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    title="Minecraft Addons Aktualisierung"
    hdr_changes="Erkannte Änderungen"
    lbl_worlds="Welten"
    lbl_restart_ok="Restart OK"
    lbl_restart_fail="Restart fehlgeschlagen"
    lbl_last_run="Letzter Lauf"
    lbl_changes_count="Änderungen"
    col_world="Welt"
    col_type="Typ"
    col_name="Addon"
    col_version="Version"
    lbl_uuid="UUID"
  else
    title="Minecraft Addons Updater"
    hdr_changes="Detected changes"
    lbl_worlds="Worlds"
    lbl_restart_ok="Restart OK"
    lbl_restart_fail="Restart failed"
    lbl_last_run="Last run"
    lbl_changes_count="Changes"
    col_world="World"
    col_type="Type"
    col_name="Addon"
    col_version="Version"
    lbl_uuid="UUID"
  fi

  worlds_info=""
  if command -v creative_enabled >/dev/null 2>&1 && creative_enabled; then
    worlds_info="${CREATIVE_WORLD}@$(data_root "$ROOT_CREATIVE")"
  fi
  if command -v survival_enabled >/dev/null 2>&1 && survival_enabled; then
    worlds_info="${worlds_info}${worlds_info:+, }${SURVIVAL_WORLD}@$(data_root "$ROOT_SURVIVAL")"
  fi
  [ -n "$worlds_info" ] || worlds_info='-'
  now="$(fmt_now_long 2>/dev/null || TZ="${TZ:-Europe/Berlin}" date +'%d.%m.%Y %H:%M Uhr')"

  rows=""
  row_count=0
  re='^\[([^][]+)\][[:space:]]+(behavior|resource)[[:space:]]+(.*)[[:space:]]+v([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]+\(([^()]*)\)$'
  for line in "${CHANGES[@]}"; do
    row_count=$((row_count+1))
    if [[ "$line" =~ $re ]]; then
      world="${BASH_REMATCH[1]}"
      kind="${BASH_REMATCH[2]}"
      name="${BASH_REMATCH[3]}"
      version="${BASH_REMATCH[4]}"
      uuid="${BASH_REMATCH[5]}"
    else
      world='?'
      kind='-'
      name="$line"
      version='-'
      uuid='-'
    fi

    if [ -n "$uuid" ] && [ "$uuid" != "-" ]; then
      uuid_block="<div style='margin-top:3px;color:#666666;font-size:11px;line-height:1.3;font-family:Consolas,Menlo,Monaco,monospace;word-break:break-all'>$(html_escape "$lbl_uuid"): $(html_escape "$uuid")</div>"
    else
      uuid_block=""
    fi

    name_html="<div style='font-weight:600;line-height:1.35;word-break:break-word'>$(html_escape "$name")</div>${uuid_block}"

    row_html="$(cat <<EOF_ROW
<tr>
  <td style="padding:6px 8px;border:1px solid #D0D0D0;white-space:nowrap;vertical-align:top">$(html_escape "$world")</td>
  <td style="padding:6px 8px;border:1px solid #D0D0D0;white-space:nowrap;vertical-align:top">$(html_escape "$kind")</td>
  <td style="padding:6px 8px;border:1px solid #D0D0D0;vertical-align:top">${name_html}</td>
  <td style="padding:6px 8px;border:1px solid #D0D0D0;white-space:nowrap;text-align:center;vertical-align:top">$(html_escape "$version")</td>
</tr>
EOF_ROW
)"
    rows="${rows}${row_html}"
  done

  restart_ok_text="${RESTART_OK:-—}"
  restart_fail_text="${RESTART_FAIL:-—}"

  cat <<EOF_HTML
<h3 style="margin:0 0 8px 0;font-family:Segoe UI,Arial,Helvetica,sans-serif;">$(html_escape "$title")</h3>
<table role="presentation" cellspacing="0" cellpadding="0" border="0" style="font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;margin:0 0 12px 0">
  <tr>
    <td style="padding:0 16px 4px 0"><b>$(html_escape "$lbl_changes_count"):</b></td>
    <td style="padding:0 0 4px 0">${row_count}</td>
  </tr>
  <tr>
    <td style="padding:0 16px 4px 0"><b>$(html_escape "$lbl_worlds"):</b></td>
    <td style="padding:0 0 4px 0">$(html_escape "$worlds_info")</td>
  </tr>
  <tr>
    <td style="padding:0 16px 4px 0"><b>$(html_escape "$lbl_restart_ok"):</b></td>
    <td style="padding:0 0 4px 0">$(html_escape "$restart_ok_text")</td>
  </tr>
  <tr>
    <td style="padding:0 16px 4px 0"><b>$(html_escape "$lbl_restart_fail"):</b></td>
    <td style="padding:0 0 4px 0">$(html_escape "$restart_fail_text")</td>
  </tr>
  <tr>
    <td style="padding:0 16px 4px 0"><b>$(html_escape "$lbl_last_run"):</b></td>
    <td style="padding:0 0 4px 0">$(html_escape "$now")</td>
  </tr>
</table>

<h4 style="margin:0 0 8px 0;font-family:Segoe UI,Arial,Helvetica,sans-serif;">$(html_escape "$hdr_changes")</h4>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;border:1px solid #D0D0D0">
  <thead>
    <tr style="background:#F3F3F3">
      <th align="left" style="text-align:left;padding:6px 8px;border:1px solid #D0D0D0;white-space:nowrap;width:72px">$(html_escape "$col_world")</th>
      <th align="left" style="text-align:left;padding:6px 8px;border:1px solid #D0D0D0;white-space:nowrap;width:70px">$(html_escape "$col_type")</th>
      <th align="left" style="text-align:left;padding:6px 8px;border:1px solid #D0D0D0">$(html_escape "$col_name")</th>
      <th align="center" style="text-align:center;padding:6px 8px;border:1px solid #D0D0D0;white-space:nowrap;width:70px">$(html_escape "$col_version")</th>
    </tr>
  </thead>
  <tbody>
${rows}
  </tbody>
</table>
EOF_HTML
}

finalize_json_like_gut() {
  local file="$1" kind="$2" dest_root="$3"
  ensure_world_json "$file"
  jq . "$file" > "${file}.tmp" && mv -f "${file}.tmp" "$file"
  chmod 0644 "$file" 2>/dev/null || true
  local d; d="$(data_root "$dest_root")"
  local uid gid; uid="$(stat -c %u "$d" 2>/dev/null || echo 0)"; gid="$(stat -c %g "$d" 2>/dev/null || echo 0)"
  [ "$uid" != "0" ] || [ "$gid" != "0" ] && chown "$uid:$gid" "$file" 2>/dev/null || true
}

maybe_restart_mc() {
  [[ "${MC_AUTO_RESTART,,}" != "true" ]] && return 0
  local ok=() fail=()
  for c in ${MC_CONTAINERS:-}; do
    if docker restart "$c" >/dev/null 2>&1; then ok+=("$c"); else fail+=("$c"); fi
  done
  RESTART_OK="${ok[*]:-}"; RESTART_FAIL="${fail[*]:-}"
}

build_change_message() {
  local body worlds_info=""
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    body="Änderungen erkannt:
"
  else
    body="Changes detected:
"
  fi
  for line in "${CHANGES[@]}"; do
    body+="- $line
"
  done
  if command -v creative_enabled >/dev/null 2>&1 && creative_enabled; then
    worlds_info="${CREATIVE_WORLD}@$(data_root "$ROOT_CREATIVE")"
  fi
  if command -v survival_enabled >/dev/null 2>&1 && survival_enabled; then
    worlds_info="${worlds_info}${worlds_info:+, }${SURVIVAL_WORLD}@$(data_root "$ROOT_SURVIVAL")"
  fi
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    body+="
Welten: ${worlds_info:-keine aktiven Welten}
"
  else
    body+="
Worlds: ${worlds_info:-no active worlds}
"
  fi

  if [[ -n "$RESTART_OK" ]];   then body+="Restart OK:   ${RESTART_OK}
"; fi
  if [[ -n "$RESTART_FAIL" ]]; then body+="Restart FAIL: ${RESTART_FAIL}
"; fi

  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    body+="
Letzter Lauf: $(fmt_now_long 2>/dev/null || TZ="${TZ:-Europe/Berlin}" date +'%d.%m.%Y %H:%M Uhr')"
  else
    body+="
Last run: $(fmt_now_long 2>/dev/null || TZ="${TZ:-Europe/Berlin}" date +'%Y-%m-%d %H:%M %Z')"
  fi
  printf "%s" "$body"
}

main() {
  for arg in "$@"; do
    if [ "$arg" = "--test-mail" ]; then
      if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
        echo "$LOG_PREFIX sende Testmail (addons_update.sh)..."
      else
        echo "$LOG_PREFIX sending test mail (addons_update.sh)..."
      fi
      local msg
      if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
        msg="Testbenachrichtigung aus addons_update.sh

Host: $(hostname)
APPRISE_URL=${APPRISE_URL:-<unset>}
Zeit: $(fmt_now_long 2>/dev/null || TZ="${TZ:-Europe/Berlin}" date +'%d.%m.%Y %H:%M Uhr')"
      else
        msg="Test notification from addons_update.sh

Host: $(hostname)
APPRISE_URL=${APPRISE_URL:-<unset>}
Time: $(fmt_now_long 2>/dev/null || TZ="${TZ:-Europe/Berlin}" date +'%Y-%m-%d %H:%M %Z')"
      fi
      notify "$msg"
      if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
        echo "$LOG_PREFIX === Fertig (Testmail-Modus)."
      else
        echo "$LOG_PREFIX === Done (test mail mode)."
      fi
      return 0
    fi
  done

  if command -v creative_enabled >/dev/null 2>&1 && creative_enabled; then
    mkdir -p "$(data_root "$ROOT_CREATIVE")/worlds/$CREATIVE_WORLD"
    process_repo_for_world "$ROOT_CREATIVE" "$CREATIVE_WORLD" "$REPO/creative"
  fi

  if command -v survival_enabled >/dev/null 2>&1 && survival_enabled; then
    mkdir -p "$(data_root "$ROOT_SURVIVAL")/worlds/$SURVIVAL_WORLD"
    process_repo_for_world "$ROOT_SURVIVAL" "$SURVIVAL_WORLD" "$REPO/survival"
  fi

  dedupe_or_mark

  if [[ $PACKS_CHANGED -eq 1 ]]; then
    maybe_restart_mc
    local msg; msg="$(build_change_message)"
    printf "%s
" "$msg" > "$CHANGE_LOG_FILE"
    notify "$msg"
  else
    if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
      echo "$LOG_PREFIX Keine Änderungen erkannt."
    else
      echo "$LOG_PREFIX No changes detected."
    fi
  fi

  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    echo "$LOG_PREFIX === Fertig."
  else
    echo "$LOG_PREFIX === Done."
  fi
}
main "$@"
