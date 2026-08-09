#!/bin/sh
set -eu

config="${HERMES_HOME}/proxy/proxy.yaml"
[ -f "${config}" ] || exit 0

# Hermes detects docker0 from its own network namespace. In a container that
# falls back to loopback, which host-created sandboxes cannot reach. Listen on
# the container interfaces; Compose only publishes these ports on host docker0.
python - "${config}" <<'PY'
from pathlib import Path
import sys
import yaml

path = Path(sys.argv[1])
with path.open(encoding="utf-8") as stream:
    config = yaml.safe_load(stream) or {}
proxy = config.setdefault("proxy", {})
proxy["tunnel_listen"] = "0.0.0.0:9090"
proxy["http_listen"] = "0.0.0.0:9091"

# iron-proxy v0.39 applies `require` to the initial HTTPS CONNECT request,
# before the tunneled Authorization header exists, and rejects every tunnel.
# The sandbox receives only minted proxy tokens, never provider credentials, so
# token replacement remains active while unauthenticated allowlisted requests
# are permitted to reach the upstream normally.
for transform in config.get("transforms", []):
    if transform.get("name") != "secrets":
        continue
    for secret in (transform.get("config") or {}).get("secrets", []):
        secret.setdefault("replace", {})["require"] = False

with path.open("w", encoding="utf-8") as stream:
    yaml.safe_dump(config, stream, sort_keys=False)
PY

for delay in 1 2 3 4 5; do
    hermes egress start && exit 0
    sleep 2
done

exit 1
