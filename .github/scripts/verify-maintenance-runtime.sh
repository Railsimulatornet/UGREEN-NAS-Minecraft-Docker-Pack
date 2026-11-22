#!/usr/bin/env bash
# Start the exact candidate with repository mounts and no host Docker access.
set -Eeuo pipefail
image="${1:?Image reference required}"
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
container=""
cleanup() { [[ -z "$container" ]] || docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
container="$(docker run -d --network none \
  --mount "type=bind,src=$root/minecraft_server/maintenance/scripts,dst=/scripts_ro,readonly" \
  --mount "type=bind,src=$root/minecraft_server/maintenance/cron/root,dst=/crontab_ro,readonly" \
  --mount "type=bind,src=$root/minecraft_server/maintenance/www,dst=/www,readonly" \
  --env COMPOSE_PROFILES=none --env BACKUP_TARGETS=none --env MC_AUTO_RESTART=0 \
  --env WATCHDOG_DRY_RUN=1 --env NOTIFY_DRY_RUN=1 \
  --health-interval=1s --health-timeout=5s --health-start-period=0s --health-retries=3 \
  --entrypoint /bin/sh "$image" /scripts_ro/entrypoint.sh)"
healthy=false
for _ in {1..45}; do
  status="$(docker inspect --format '{{.State.Health.Status}}' "$container")"
  if [[ "$status" == healthy ]]; then healthy=true; break; fi
  [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]]
  sleep 1
done
[[ "$healthy" == true ]] || { docker logs "$container"; exit 1; }
docker exec "$container" python3 /usr/local/libexec/maintenance_health.py
# Missing scheduled work must fail even while cron and the HTTP server still run.
docker exec "$container" /bin/sh -c 'rm /etc/crontabs/root'
if docker exec "$container" python3 /usr/local/libexec/maintenance_health.py; then
  echo 'Missing maintenance schedule was incorrectly accepted.' >&2
  exit 1
fi
