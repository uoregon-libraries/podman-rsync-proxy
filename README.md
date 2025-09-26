# Podman rsync proxy

This repo will hold a simple setup for proxying `rsync` and `mysqldump` through
podman on a highly secure server:

- Podman runs as a single user in rootless mode.
- The server doesn't allow sshing by the podman user; devs have to ssh in and
  switch users to do anything podman-related.
- The podman data volumes are inaccessible to anybody but podman, and because
  of how rootless podman works, even the podman user can't easily get at a
  volume's files directly.

For simpler instructions, we're pretending your podman user is `sir_podman`.

You'll also have to install two scripts on the podman host: `podman-rsync.sh`,
a wrapper that secures and automates the process of running the rsync
container; and `podman-mysqldump.sh`, which does the same for running
`mysqldump` inside any container.

## Setup

### The on-demand rsync container

Proxying rsync requires a custom image and container to exist on any project
you want to allow syncing files. You won't need this container running except
when a request is coming in for an rsync call.

#### Build the podman image

Clone this repo on your production server, then build the image:

```bash
# Switch to sir_podman to build this image since podman images are per-user in
# rootless mode
sudo su - sir_podman

cd ~/
git clone https://github.com/uoregon-libraries/podman-rsync-proxy.git
cd podman-rsync-proxy
podman build -t uoregon-libraries/podman-rsync-proxy .
```

#### Configure your podman-compose project

You'll need to add `uoregon-libraries/podman-rsync-proxy` to your podman
compose project as a new service, and potentially alter how you start the
stack. If you're doing `podman compose up`, you need to change that to only
start the necessary services so that the rsync service doesn't start up
automatically (though if it does, it isn't the end of the world: the service
will just exit immediately).

Your compose definition (`compose.yml` or `compose.override.yml`) would get
something like this added:

```yaml
  rsync-proxy:
    image: uoregon-libraries/podman-rsync-proxy
    volumes:
    - vol1:/mnt/vol1:ro
    - vol2:/mnt/vol2:ro
    ...
```

By default, the service name in your compose file must be `rsync-proxy`. This
can be overridden via a podman-host-side configuration file, explained in the
script setup section below.

### Common Setup

Both scripts have to be installed on the server somewhere so that a dev's
`sudo` commands (through `ssh`) can use them to handle the command proxying.

#### Installation

Copy the two scripts to a location on your podman host, such as
`/usr/local/bin`. Then set ownership and permissions to restrict their use.
They should be set up so that nobody can edit them except root, and nobody can
read or execute them except `sir_podman`, e.g.:

```bash
cd /usr/local/bin
chown sir_podman podman-rsync.sh podman-mysqldump.sh
chmod 500 podman-rsync.sh podman-mysqldump.sh
```

#### Configuration

You should create a file at `/etc/default/podman-proxy` to override default
settings in the two scripts. These variables are currently available:

- `RSYNC_SERVICE_NAME`: The name of the rsync service in your `compose.yml`
  file. Defaults to `rsync-proxy`. Not used for DB exporting.
- `PODMAN_PROJECT_ROOT`: The base directory where your podman compose projects
  are located. Defaults to `/opt/podman-apps`.
- `PODMAN_PROXY_LOG_FILE`: A full path to a log file if you want high-level
  information telling you when certain pieces of the scripts were executed. If
  left empty, no logs will be created.

### Set up sudoers

To allow developers to use the above scripts, and especially the `rsync`'s
`rsh` command, devs will need to be able to run them as `sir_podman` *without*
having to authenticate. This requires a carefully constructed set of sudoer
directives.

**Warning:** This is the most security-sensitive step. The file we're creating
must set up rules that are as restrictive as possible. Only the specified
scripts should be allowed to run passwordless, and only as `sir_podman`.

For example, you might create `/etc/sudoers.d/rsync-proxy` like this:

```
Cmnd_Alias RSYNC_PROXY = /usr/local/bin/podman-rsync.sh
Cmnd_Alias MYSQLDUMP_PROXY = /usr/local/bin/podman-mysqldump.sh
User_Alias PODMAN_PROXY_USERS = jechols, alovelace, cdarwin
PODMAN_PROXY_USERS ALL=(sir_podman) NOPASSWD: RSYNC_PROXY
PODMAN_PROXY_USERS ALL=(sir_podman) NOPASSWD: MYSQLDUMP_PROXY
```

### Usage: rsync

Once everything above has been done, you just need to tell `rsync` how to do
the connection and transfer, like so:

```bash
export dev="<dev username>"
export pod_host="<podman host>"
export pod_subdir="<podman project subdir, relative to the server-configured podman root>"
export container_path="<path to volumes *inside* the container>"
export local_path="<path where the mirrored data should live locally>"

rsync -avz --no-times --no-perms --stats --progress \
  --rsh="ssh $dev@$pod_host sudo -u sir_podman /usr/local/bin/podman-rsync.sh $pod_subdir" \
  ":$container_path/" $local_path/
```

Most flags can be customized to your liking. The only magic to be very careful
with is the value of the `--rsh` flag.

You can run the rsync as root if you need to get permissions and times synced
up, but only if you're copying from your podman host to your local system. The
syntax is sort of weird, though, e.g.:

```bash
sudo rsync -avz --stats --progress \
  --rsh="sudo -u $dev ssh $dev@$pod_host sudo -u sir_podman /usr/local/bin/podman-rsync.sh $pod_subdir" \
  ":$container_path/" $local_path/
```

This uses sudo on the rsync command to ensure rsync has the rights to change
ownership and timestamps. It *also* uses sudo on the `ssh` command (in the
`--rsh` flag) so that you're sshing in with whatever keys you'd normally use.

**Note**: the bash variables (e.g., `$pod_host`) are optional. You can just jam
that stuff inline if desired. They're there more to help document what's going
on with the `rsync` command.

**Note 2**: if you rsync back up to a service, you likely need to fix
permissions inside the container! Getting a copy of files for local development
has the same requirement, but usually you'll have an easier time changing
permissions / ownership on a dev system.

### Usage: mysqldump

Executing `mysqldump` against an arbitrary container is fairly easy:

```bash
export dev="<dev username>"
export pod_host="<podman host>"
export pod_subdir="<podman project subdir, relative to the server-configured podman root>"
export service="<name of the compose service for the database>"

ssh $dev@$pod_host sudo -u sir_podman \
    /usr/local/bin/podman-mysqldump.sh $pod_subdir $service --all-databases > all-dbs.sql
```

This command connects to the podman host, runs the `podman-mysqldump.sh` script
to execute `mysqldump` in the specified container, and pipes the output to a
local file. Any arguments passed after the service name will be passed directly
to the `mysqldump` command.
