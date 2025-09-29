#!/bin/bash
#
# Secure wrapper to automatically run mysqldump in a given project's db
# container.
set -euo pipefail

# Source config file if it exists
if [[ -f /etc/default/podman-proxy ]]; then
  . /etc/default/podman-proxy
fi

# Send all output to a log file if specified
log_file="${PODMAN_PROXY_LOG_FILE:-}"
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
project_root="${PODMAN_PROJECT_ROOT:-/opt/podman-apps}"
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

# This is very confusing, so here's a breakdown:
#
# - `podman-compose exec`: if this isn't obvious, stop reading.
# - `-T`: disables a pseudo-TTY. It's probably necessary since we're doing a
#   non-interactive command, and things break sometimes without it.
# - `"$service"`: this is the target container, e.g., "db".
#   command. The value comes from the second argument passed to the script.
# - `bash -c '...'`: This is the command that gets executed inside the
#   container. It tells the container to start a `bash` shell and execute the
#   provided command string, which is necessary to properly quote the env vars
#   that we want expanded in the container.
# - `'mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD "$@"'`: This is what needs var
#   expansion mentioned above. Since it's single-quoted, the variables (e.g.,
#   `$MYSQL_USER`) are expanded inside the container, not the host.
# - The first `"$@"` is replaced by the second `"$@"` because of bash magic I
#   don't understand. But it seems to work.
# - `bash`: AI told me to do this.
# - The last `"$@"` expands to the actual args passed to this script, and the
#   magic above passes these through to replace that first `$@` above because...
#   more magic.
log "--- Running mysqldump in service \"$service\" with arguments [$*]"
podman-compose exec -T "$service" bash -c 'mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD "$@"' bash "$@"
log "--- Done"
