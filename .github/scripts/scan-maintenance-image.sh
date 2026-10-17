#!/usr/bin/env bash
# Scan the selected platform of the immutable OCI artifact, without Docker socket.
set -Eeuo pipefail
INPUT="$(realpath "${1:?usage: scan-maintenance-image.sh OCI_LAYOUT PLATFORM REPORT_DIR}")"
PLATFORM="${2:?platform required}"
OUT="${3:?report directory required}"
case "$PLATFORM" in linux/amd64|linux/arm64) ;; *) exit 2 ;; esac
[[ -s "$INPUT/index.json" && -s "$INPUT/oci-layout" ]]
CACHE="${TRIVY_CACHE_DIR:-${RUNNER_TEMP:-/tmp}/minecraft-maintenance-trivy-cache}"
[[ ! -e "$OUT/trivy.json" ]]
mkdir -p "$OUT" "$CACHE"
OUT="$(realpath "$OUT")"
CACHE="$(realpath "$CACHE")"
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/maintenance-scan.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
# Trivy's OCI --input reader selects the first manifest regardless of --platform.
# Select one platform with Skopeo, preserving its digest from the verified image.
selected="$work/image"
skopeo --override-os linux --override-arch "${PLATFORM#*/}" copy --preserve-digests \
  "oci:$INPUT" "oci:$selected"
skopeo inspect --raw "oci:$selected" > "$OUT/selected-manifest.json"
skopeo inspect --config "oci:$selected" > "$OUT/selected-config.json"
python3 - "$OUT/selected-manifest.json" "$OUT/selected-config.json" "$PLATFORM" <<'PY'
import json, re, sys
manifest = json.load(open(sys.argv[1]))
config = json.load(open(sys.argv[2]))
expected_os, expected_arch = sys.argv[3].split("/")
digest = manifest.get("config", {}).get("digest", "")
if manifest.get("schemaVersion") != 2 or not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
    raise SystemExit("Platform selection did not produce a single image manifest")
if (config.get("os"), config.get("architecture")) != (expected_os, expected_arch):
    raise SystemExit("Selected image configuration does not match the requested platform")
PY
TRIVY_IMAGE="${TRIVY_IMAGE:-ghcr.io/aquasecurity/trivy:latest}"
trivy() {
  docker run --rm \
    --mount "type=bind,src=$selected,dst=/image,readonly" \
    --mount "type=bind,src=$OUT,dst=/out" \
    --mount "type=bind,src=$CACHE,dst=/root/.cache/trivy" \
    "$TRIVY_IMAGE" "$@"
}
# Retain the complete report, including findings with no available fix.
trivy image --input /image --platform "$PLATFORM" --scanners vuln \
  --pkg-types os,library --no-progress --format json --output /out/trivy.json
[[ -s "$OUT/trivy.json" ]]
python3 - "$OUT/trivy.json" "$OUT/selected-manifest.json" "$PLATFORM" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
manifest = json.load(open(sys.argv[2]))
metadata = report.get("Metadata", {})
config = metadata.get("ImageConfig", {})
expected_os, expected_arch = sys.argv[3].split("/")
if (config.get("os"), config.get("architecture")) != (expected_os, expected_arch):
    raise SystemExit("Trivy scanned a different platform than requested")
if metadata.get("ImageID") != manifest["config"]["digest"]:
    raise SystemExit("Trivy scanned a different image than the selected manifest")
if metadata.get("OS", {}).get("Family") != "alpine" or not any(
    result.get("Type") == "alpine" for result in report.get("Results", [])
):
    raise SystemExit("Trivy did not identify the expected Alpine package set")
PY
trivy convert --format sarif --severity HIGH,CRITICAL \
  --output /out/trivy.sarif /out/trivy.json
trivy convert --format table --scanners vuln --severity HIGH,CRITICAL \
  --output /out/all-high-critical.txt /out/trivy.json
# 42 = fixable HIGH/CRITICAL, 43 = detected OS EOL; any other error also blocks.
if trivy image --input /image --platform "$PLATFORM" --scanners vuln \
  --pkg-types os,library --no-progress --skip-db-update \
  --ignore-unfixed --severity HIGH,CRITICAL --exit-code 42 --exit-on-eol 43 \
  --format table --output /out/fixable.txt; then
  [[ -s "$OUT/fixable.txt" ]]
  cat "$OUT/fixable.txt"
else
  rc=$?
  if [[ -f "$OUT/fixable.txt" ]]; then cat "$OUT/fixable.txt"; fi
  printf 'Security gate blocked %s (exit %s).\n' "$PLATFORM" "$rc" >&2
  exit "$rc"
fi
