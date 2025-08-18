#!/bin/bash
#
# Secure wrapper to automatically start the rsync-proxy service for a given
# project, run it, and then end it and remove the container.
set -euo pipefail

# Hard-code the service name so that even if other security measures fail, it's
# very unlikely somebody could do anything malicious (most projects won't have
# a service by this name).
service="rsync-proxy"

# On exit we run this to ensure that the rsync container exits
cleanup() {
  echo '--- Rsync complete: shutting down "'$service'" service...' >&2
  cd "$project_path"
  podman-compose stop $service
  podman-compose rm $service
  echo '--- Shutdown complete' >&2
}
trap cleanup EXIT

# Project path is required. Other args are arguably necessary, but without them
# the container just won't start rsync.
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

echo '--- Starting "'$service'" service...' >&2
cd "$project_path"
podman-compose up -d --force-recreate "$service"

# Find the full container name, since compose adds prefixes
CONTAINER_ID=$(podman-compose ps -q "$service")
if [[ -z "$CONTAINER_ID" ]]; then
    echo 'Error: Could not find running container for service "'$service'".' >&2
    exit 1
fi
container_name=$(podman inspect --format '{{.Name}}' "$CONTAINER_ID")
echo "--- Container '$container_name' is running. Starting rsync proxy." >&2

# Kick off the container's rsync "listener"
exec /usr/bin/podman exec -i "$container_name" "rsync -av $@"
