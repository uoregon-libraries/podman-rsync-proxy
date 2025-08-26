#!/bin/bash
#
# Secure wrapper to automatically start the rsync-proxy service for a given
# project, run it, and then end it and remove the container.
set -euo pipefail

# Source config file if it exists
if [[ -f /etc/default/podman-rsync ]]; then
  . /etc/default/podman-rsync
fi

# Hard-code the service name so that even if other security measures fail, it's
# very unlikely somebody could do anything malicious (most projects won't have
# a service by this name).
service="${RSYNC_SERVICE_NAME:-rsync-proxy}"

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
project_root="${RSYNC_PROJECT_ROOT:-/opt/podman-apps}"
pod_subdir="$1"
shift

# Ensure the path doesn't contain components that could be used for traversal
if [[ "$pod_subdir" =~ \.\. || "$pod_subdir" =~ ^/ ]]; then
  echo 'Error: invalid project subdir "'$pod_subdir'": disallowed characters.' >&2
  exit 1
fi

project_path="$project_root/$pod_subdir"

# After constructing, resolve the real path and check if it's within the root
real_project_path=$(realpath "$project_path")
real_root_path=$(realpath "$project_root")

if [[ "$real_project_path" != "$real_root_path/"* || "$real_project_path" == "$real_root_path" ]]; then
  echo 'Error: project path is outside of the allowed root directory.' >&2
  exit 1
fi


# If there's no compose file we probably shouldn't do anything
compose_file="${project_path}/compose.yml"
if [[ ! -f "$compose_file" ]]; then
  echo 'Error: compose.yml file not found at "'$compose_file'".' >&2
  exit 1
fi

echo '--- Starting "'$service'" service...' >&2
cd "$project_path"
podman-compose up -d --force-recreate "$service"

# Find the full container name, since compose adds prefixes
container_id=$(podman-compose ps -q "$service")
if [[ -z "$container_id" ]]; then
  echo 'Error: could not find running container for service "'$service'".' >&2
  exit 1
fi
container_name=$(podman inspect --format '{{.Name}}' "$container_id")
echo '--- Container "'$container_name'" is running. Starting rsync proxy.' >&2

# Kick off the container's rsync "listener". The first argument from the rsync
# client MUST be "rsync". If it's not, bail.
if [[ "$1" != "rsync" ]]; then
  echo "Error: this script is only a proxy for the 'rsync' command." >&2
  exit 1
fi

# Check for any potentially dangerous characters
for arg in "$@"; do
  if [[ "$arg" =~ [;\&\|\$\`\(\)\{\}\<\>] ]]; then
    echo "Error: disallowed characters detected in rsync arguments." >&2
    exit 1
  fi
done

exec /usr/bin/podman exec -i "$container_name" "$@"
