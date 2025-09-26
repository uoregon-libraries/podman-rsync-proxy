#!/bin/bash
#
# Secure wrapper to automatically run mysqldump in a given project's db
# container.
set -euo pipefail

# Source config file if it exists
if [[ -f /etc/default/podman-mysqldump ]]; then
  . /etc/default/podman-mysqldump
fi

# Send all output to a log file if specified
log_file="${MYSQLDUMP_LOG_FILE:-}"
log() {
  if [[ -n "$log_file" ]]; then
    dt=$(date +"%Y-%m-%dT%H:%M:%S%z")
    echo "[$dt]" "$@" >> "$log_file"
  fi
}

# Project path and service name are required.
if [[ "$#" -lt 2 ]]; then
  echo "Usage: $0 <project_path> <service_name> [mysqldump_args...]" >&2
  exit 1
fi

# Define the dir that contains all the compose projects so callers aren't
# passing in the full path
project_root="${MYSQLDUMP_PROJECT_ROOT:-/opt/podman-apps}"
pod_subdir="$1"
service="$2"
shift 2

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

log '--- Switching to dir "'$project_path'"...'
cd "$project_path"

log "--- Running mysqldump in service \"$service\" with arguments [$*]"
podman-compose exec -T "$service" mysqldump "$@"
log "--- Done"
