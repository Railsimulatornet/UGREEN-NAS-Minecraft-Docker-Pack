#!/bin/sh
# Copyright Roman Glos 2026
set -eu

SERVER_PROFILES_RAW="${COMPOSE_PROFILES:-creative,survival}"
# normalize: lowercase, no spaces
SERVER_PROFILES="$(printf '%s' "$SERVER_PROFILES_RAW" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
BACKUP_TARGETS_RAW="${BACKUP_TARGETS:-active}"
BACKUP_TARGETS="$(printf '%s' "$BACKUP_TARGETS_RAW" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"

profile_enabled() {
  _name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case ",${SERVER_PROFILES}," in
    *,${_name},*) return 0 ;;
    *) return 1 ;;
  esac
}

backup_target_requested() {
  _name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$BACKUP_TARGETS" in
    active|'') profile_enabled "$_name" ;;
    none) return 1 ;;
    *)
      case ",${BACKUP_TARGETS}," in
        *,${_name},*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
  esac
}

creative_enabled() { profile_enabled creative; }
survival_enabled() { profile_enabled survival; }
backup_creative_enabled() { creative_enabled && backup_target_requested creative; }
backup_survival_enabled() { survival_enabled && backup_target_requested survival; }

creative_container_name() { printf '%s\n' "${CREATIVE_CONTAINER_NAME:-minecraftserver_creative}"; }
survival_container_name() { printf '%s\n' "${SURVIVAL_CONTAINER_NAME:-minecraftserver_survival}"; }
backup_container_name() { printf '%s\n' "${BACKUP_CONTAINER_NAME:-minecraftserver_backup}"; }

creative_world_name() { printf '%s\n' "${CREATIVE_LEVEL_NAME:-creative}"; }
survival_world_name() { printf '%s\n' "${SURVIVAL_LEVEL_NAME:-Glosis}"; }

enabled_mc_containers() {
  _out=""
  if creative_enabled; then _out="$(creative_container_name)"; fi
  if survival_enabled; then _out="${_out}${_out:+ }$(survival_container_name)"; fi
  printf '%s\n' "$_out"
}

enabled_backup_targets() {
  _out=""
  if backup_creative_enabled; then _out="creative"; fi
  if backup_survival_enabled; then _out="${_out}${_out:+,}survival"; fi
  if [ -z "$_out" ]; then
    printf 'none\n'
  else
    printf '%s\n' "$_out"
  fi
}

enabled_world_count() {
  _n=0
  creative_enabled && _n=$((_n+1)) || true
  survival_enabled && _n=$((_n+1)) || true
  printf '%s\n' "$_n"
}

enabled_backup_world_count() {
  _n=0
  backup_creative_enabled && _n=$((_n+1)) || true
  backup_survival_enabled && _n=$((_n+1)) || true
  printf '%s\n' "$_n"
}
