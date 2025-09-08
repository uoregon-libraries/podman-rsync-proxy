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

# Set a flag so we only clean up the project if there's a need
dirty=0

# On exit we run this to ensure that the rsync container exits
cleanup() {
  if [[ $dirty != 0 ]]; then
    log '--- Rsync complete: shutting down "'$service'" service...'
    cd "$project_path"
    podman-compose stop $service >/dev/null
    log '--- Shutdown complete'
  fi
}
trap cleanup EXIT

# Send all output to a log file if specified
log_file="${RSYNC_LOG_FILE:-}"
log() {
  if [[ -n "$log_file" ]]; then
    dt=$(date +"%Y-%m-%dT%H:%M:%S%z")
    echo "[$dt]" "$@" >> "$log_file"
  fi
}

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

# Check for any potentially dangerous characters
for arg in "$@"; do
  if [[ "$arg" =~ '[;\&\|\$\`\(\)\{\}\<\>]' ]]; then
    echo "Error: disallowed characters detected in rsync arguments." >&2
    exit 1
  fi
done

log '--- Starting "'$service'" service...'
cd "$project_path"
dirty=1
podman-compose up -d --force-recreate "$service" >/dev/null

set -- "rsync" "$@"
log "--- Running service \"$service\" with arguments [$@]"
podman-compose exec "$service" "$@"
