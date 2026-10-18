#!/usr/bin/env bash
# Publish the verified OCI archive; full version tags never change their content.
set -Eeuo pipefail
umask 077
archive="$(realpath "${1:?Verified OCI archive required}")"
version="${2:?Maintenance image version required}"
mode="${3:?Publication mode required}"
[[ -s "$archive" ]]
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
case "$mode" in release|latest) ;; *) exit 2 ;; esac
: "${DOCKERHUB_USERNAME:?Docker Hub user required}"
: "${DOCKERHUB_TOKEN:?Docker Hub token required}"
repo="docker.io/railsimulatornet/minecraft-maintenance"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
auth="$work/auth.json"
printf '%s' "$DOCKERHUB_TOKEN" | skopeo login --authfile "$auth" \
  --username "$DOCKERHUB_USERNAME" --password-stdin docker.io
skopeo inspect --raw "oci-archive:$archive" > "$work/source.json"
expected="$(skopeo manifest-digest "$work/source.json")"
[[ "$expected" =~ ^sha256:[a-f0-9]{64}$ ]]

tags=()
if [[ "$mode" == release ]]; then
  # Check the fixed name before changing any registry tag. Authentication and
  # network failures must not be interpreted as an absent release.
  if skopeo inspect --authfile "$auth" --raw "docker://$repo:$version" \
      > "$work/existing.json" 2> "$work/error"; then
    [[ "$(skopeo manifest-digest "$work/existing.json")" == "$expected" ]] || {
      echo "Refusing to overwrite release $version; increase the maintenance image version." >&2
      exit 1
    }
  elif grep -Eqi 'manifest unknown|MANIFEST_UNKNOWN' "$work/error"; then
    tags+=("$version")
  else
    cat "$work/error" >&2
    exit 1
  fi
  # The minor tag is a moving alias for the most recent release in that series.
  tags+=("${version%.*}")
fi
# Weekly security rebuilds update only latest, leaving all version tags intact.
tags+=(latest)
for tag in "${tags[@]}"; do
  skopeo copy --authfile "$auth" --all --preserve-digests \
    "oci-archive:$archive" "docker://$repo:$tag"
  skopeo inspect --authfile "$auth" --raw "docker://$repo:$tag" > "$work/published.json"
  [[ "$(skopeo manifest-digest "$work/published.json")" == "$expected" ]]
  printf '%s:%s -> %s\n' "$repo" "$tag" "$expected"
done
