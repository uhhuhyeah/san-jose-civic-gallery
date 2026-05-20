#!/usr/bin/env bash
set -euo pipefail

encoded="$(base64 -i docs/spikes/simbli/vps-probe.mjs | tr -d '\n')"

bundle exec kamal server exec \
  "docker run --rm -e PROBE_B64=${encoded} -e PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 mcr.microsoft.com/playwright:v1.52.0-noble bash -lc 'cd /tmp && npm init -y >/dev/null && npm install playwright@1.52.0 --ignore-scripts >/dev/null && printf %s \"\$PROBE_B64\" | base64 -d > /tmp/simbli-vps-probe.mjs && node /tmp/simbli-vps-probe.mjs'"
