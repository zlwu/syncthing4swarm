# syncthing4swarm

A small, private-network Syncthing wrapper for Docker Swarm manager nodes.

It deploys one Syncthing task per manager and replicates a single host directory between trusted managers. The intended use is a deployment-control directory, not application data replication.

## Security boundary

This public repository and its GHCR image contain only generic code and placeholders. Do not commit real node names, IP addresses, domains, production stack files, credentials, `.env` files, topology documents, or application data.

The image does not contain your deployment directory. At runtime, mount a private host directory such as `/opt/swarm-stacks`.

## Requirements

- Docker Swarm initialized.
- Trusted manager nodes sharing one internal overlay network.
- The host directory exists on each manager.
- The same folder path is used on each manager.
- Only trusted managers are allowed to access the Syncthing GUI and sync port.

## Deployment example

1. Create the local Syncthing state and private deployment directory on each manager:

```bash
sudo install -d -m 0700 -o root -g root /var/lib/syncthing4swarm/config
sudo install -d -m 0700 -o root -g root /opt/swarm-stacks
```

2. Create a private environment file outside this repository:

```bash
STGUIAPIKEY=replace-with-a-long-random-value
SYNCTHING_FOLDER_ID=swarm-stacks
SYNCTHING_FOLDER_PATH=/var/syncthing/data
PUID=0
PGID=0
UMASK=077
```

3. Replace `OWNER` in `docker-compose.yml` with the public GHCR owner and deploy from one manager:

```bash
set -a
. /path/to/private/syncthing.env
set +a
docker stack deploy -c docker-compose.yml syncthing4swarm
```

The service is constrained to managers. Syncthing state is local at `/var/lib/syncthing4swarm/config`; only `/opt/swarm-stacks` is synchronized.

## Important operating rules

- Initialize the synchronized directory from one authoritative manager before enabling bidirectional sync.
- Only one operator edits the synchronized deployment directory at a time.
- Resolve conflict files before deploying.
- Keep application databases, logs, caches, locks, models, and runtime data outside the synchronized directory.
- Use absolute `/opt/stacks/...` bind-mount paths in the private stack files so deploy can be initiated from any manager while tasks keep using their assigned node's local data.

## Public examples

See `examples/swarm-stacks/`. The examples contain placeholders only. The real `/opt/swarm-stacks` directory must remain private to your cluster.

## Development

```bash
docker build --build-arg SYNCTHING_VERSION=2.1.2 -t syncthing4swarm:local ./dev
docker compose -f dev/docker-compose-dev.yml config
```

The published image currently targets `linux/amd64`, matching the current test cluster. The GHCR workflow publishes from `main` and version tags. A weekly workflow checks both this upstream source repository and Syncthing stable releases, validates changes, and opens a review PR instead of auto-merging.
