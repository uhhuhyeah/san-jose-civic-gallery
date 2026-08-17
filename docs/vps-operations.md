# VPS Operations

This is the maintenance and recreation playbook for the production Hostinger
VPS. The application deploys through Kamal; see `config/deploy.yml` for the
current host, roles, persistent Rails volume, and proxy hosts.

## Storage model

The production data is deliberately split across services:

| Data | Location | Expected VPS impact |
| --- | --- | --- |
| Canonical application data and Solid Queue tables | Remote production Postgres | None |
| Active Storage attachment files | Cloudflare R2 | None |
| Solid Cache SQLite database | `san_jose_civic_gallery_storage` Docker volume | Bounded to 256 MB by `config/cache.yml`; cache entries are retained for at most 7 days |
| Rails application images, containers, proxy, and remote-build cache | VPS Docker storage | Requires routine maintenance |

The Rails storage volume is mounted at `/rails/storage` in the web and jobs
containers. It must be kept when migrating or rebuilding the VPS because it
contains the local Solid Cache database, but it is not the durable source of
record data.

## Remote BuildKit cache

Kamal builds the production image on the VPS (`builder.remote` in
`config/deploy.yml`). Docker BuildKit stores that cache in a named Docker
volume, normally named similarly to:

```
buildx_buildkit_kamal-remote-ssh---root-<host>_state
```

On the original Hostinger host this cache grew to 66.46 GB, despite the
application storage volume being only about 83 MB. BuildKit's automatic
defaults can allow the cache to use most of a 100 GB disk, so do not rely on
those defaults for this VPS size.

### Inspect disk use

Run as `root` on the VPS:

```sh
df -h /
docker system df -v
docker volume ls
docker volume inspect san_jose_civic_gallery_storage
docker run --rm -v san_jose_civic_gallery_storage:/storage alpine sh -c 'du -h -d 1 /storage'
du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null
```

`docker system df -v` reports the BuildKit state volume directly under **Local
Volumes space usage**. Do not mistake it for the Rails `storage` volume.

### Immediate cache recovery

This removes only unused BuildKit cache. It does not delete running
containers, production database records, R2 objects, or the Rails storage
volume. A later deployment may take longer while layers are recreated.

```sh
BUILDKIT="$(docker ps --filter 'name=buildx_buildkit' --format '{{.Names}}')"
docker exec "$BUILDKIT" buildctl du --verbose
docker exec "$BUILDKIT" buildctl prune --all
df -h /
```

If an obsolete Playwright probe image is present and not needed for an active
operation, it can also be removed independently:

```sh
docker image rm mcr.microsoft.com/playwright:v1.52.0-noble
```

Use `kamal prune` from the deploy machine periodically to remove superseded
application images and stopped containers. That is separate from BuildKit cache
cleanup.

## Scheduled BuildKit cleanup

The VPS does not include the `cron` package. Use the systemd timer below.
It keeps build cache used in the previous seven days and runs at 03:25 UTC each
Sunday. The dynamic builder lookup means the same configuration works when the
VPS address, and therefore Kamal's generated BuildKit container name, changes.

Create `/usr/local/sbin/prune-buildkit-cache` with mode `755`:

```sh
#!/bin/sh
set -eu

BUILDKIT="$(docker ps --filter 'name=buildx_buildkit' --format '{{.Names}}')"
[ -n "$BUILDKIT" ] && docker exec "$BUILDKIT" buildctl prune --all --keep-duration 168h
```

Create `/etc/systemd/system/buildkit-cache-prune.service`:

```ini
[Unit]
Description=Prune unused Kamal remote BuildKit cache

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/prune-buildkit-cache
```

Create `/etc/systemd/system/buildkit-cache-prune.timer`:

```ini
[Unit]
Description=Weekly BuildKit cache cleanup

[Timer]
OnCalendar=Sun *-*-* 03:25:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and verify it:

```sh
systemctl daemon-reload
systemctl enable --now buildkit-cache-prune.timer
systemctl list-timers buildkit-cache-prune.timer
```

`Persistent=true` runs a missed cleanup shortly after boot. To test the cleanup
without waiting for Sunday, run:

```sh
systemctl start buildkit-cache-prune.service
systemctl status buildkit-cache-prune.service --no-pager
```

## Recreating or moving the VPS

1. Provision Docker and a systemd-based Linux host with sufficient disk space.
2. Update `DEPLOY_HOST` (or the default in `config/deploy.yml`) and confirm the
   target IP, DNS, firewall, and SSH access.
3. Ensure all Kamal secrets are available to the deploy machine. The canonical
   Postgres data remains remote and attachment files remain in R2, so neither is
   copied from the old VPS.
4. Deploy with Kamal. This creates the application storage volume and the
   remote BuildKit builder on the new host.
5. Install and enable the systemd BuildKit cleanup timer above.
6. Verify `/up`, each configured public host, `docker system df -v`, and
   `df -h /`.

There is no need to transfer the old BuildKit cache. It is disposable and
should not be migrated. Transferring the Rails storage volume is optional: it
preserves a small, disposable Solid Cache database but is not required for
application correctness.
