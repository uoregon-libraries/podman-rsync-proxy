#!/bin/bash
#
# Secure wrapper to automatically start the rsync-proxy service for a given
# project, run it, and then end it and remove the container.
set -euo pipefail

# On exit we run this to ensure that the rsync container exits
cleanup() {
  echo '--- Rsync complete: shutting down "rsync-proxy" service...' >&2
  cd "$project_path"
  podman-compose stop rsync-proxy
  podman-compose rm rsync-proxy
  echo '--- Shutdown complete' >&2
}
trap cleanup EXIT

# Ensure project path and service name were provided
if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <project_path> [rsync_args...]" >&2
  exit 1
fi

# Define the dir that contains all the compose projects so callers aren't
# passing in the full path
PROJECT_ROOT="${PROJECT_ROOT:-/opt/podman-apps}"
project_path="$PROJECT_ROOT/$1"
shift

# If there's no compose file we probably shouldn't do anything
compose_file="${project_path}/compose.yml"
if [[ ! -f "$compose_file" ]]; then
    echo "Error: Compose file not found at '$compose_file'." >&2
    exit 1
fi

echo '--- Starting "rsync-proxy" service...' >&2
cd "$project_path"
podman-compose up -d --force-recreate "rsync-proxy"

# Find the full container name, since compose adds prefixes
CONTAINER_ID=$(podman-compose ps -q "rsync-proxy")
if [[ -z "$CONTAINER_ID" ]]; then
    echo "Error: Could not find running container for service 'rsync-proxy'." >&2
    exit 1
fi
CONTAINER_NAME=$(podman inspect --format '{{.Name}}' "$CONTAINER_ID")
echo "--- Container '$CONTAINER_NAME' is running. Starting rsync proxy." >&2

# Kick off the container's rsync "listener"
exec /usr/bin/podman exec -i "$CONTAINER_NAME" "$@"
