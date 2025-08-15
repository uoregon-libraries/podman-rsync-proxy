# `rsync` proxy

This repo will hold a simple setup for proxying `rsync` through podman on a
highly secure server:

- Podman runs as a single user in rootless mode.
- The server doesn't allow sshing by the podman user; devs have to ssh in and
  switch users to do anything podman-related.
- The podman data volumes are inaccessible to anybody but podman, and because
  of how rootless podman works, even the podman user can't easily get at a
  volume's files directly.

In order to sync production files to a dev or staging server:

- An rsync-proxy podman image definition must be created. It needs only have
  rsync installed.
- A per-project container definition will be needed to connect the proxy image
  to the project's volumes.
- An rsync script must be written which invokes the container's rsync command.
  - It must be read-only, even to the podman user.
  - It must not be usable by anybody but the podman user.
  - It must take parameters that tell it how to connect to the project.
- A sudoer rule must be set up to allow devs to run the rsync script without
  entering a password (hence all the paranoia above).

On the dev / staging server, devs will have to run `rsync` with the `--rsync`
flag to tell the remote server (podman host) to run the above-mentioned script
as the podman user.

LLMs suggest these things are all possible. This repo is where we find out (or
come up with another solution).
