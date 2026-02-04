# Secrets

Place the following files here (do not commit their contents):

| File | Used by | Description |
|------|---------|-------------|
| `basic_auth_credentials` | Traefik | HTTP Basic Auth for dashboard (htpasswd format). Generate: `htpasswd -nb user password` |
| `cf_dns_api_token` | Traefik | Cloudflare API token for Let's Encrypt DNS challenge. Create a token with Zone:DNS:Edit. |

Ensure these files exist before starting the Infrastructure stack.
