# Jellyseerr Design

## Architecture

Jellyseerr is added to the existing Media stack and follows the same routing and security conventions as other media services. The service joins both the default network and the external `t3_proxy` network. The default network is used for internal API connections (e.g., to Jellyfin and later to Sonarr/Radarr), while `t3_proxy` is used for Traefik routing to the Web UI. The Web UI is internal-only via `websecure-internal` and protected by `chain-no-auth@file`, matching the rest of the media stack. Routing is provided at `jellyseerr.${DOMAINNAME_1}` and the Traefik service targets port `5055`, Jellyseerr's internal port. Container settings are consistent with repo conventions: `container_name` is specified, `init: true` is enabled per official image guidance, `restart: unless-stopped` is enabled, and `security_opt` enforces `no-new-privileges:true`.

## Data & Configuration

Jellyseerr does not need direct media library access. It only needs a persistent configuration directory and timezone settings. Per user requirement, the config path is stored under `${DOCKERDIR}/appdata/jellyseerr:/app/config`, aligning with the official image documentation and keeping the configuration under version-controlled appdata conventions used in this repo. Initial setup is performed in the Jellyseerr Web UI by connecting to Jellyfin (via `http://jellyfin:8096` over the default network) and selecting libraries to sync. Optional integrations to Sonarr/Radarr can be added later within Jellyseerr without additional container changes.
