# Secrets

Place the following files here (do not commit their contents):

| File | Used by | Description |
|------|---------|-------------|
| `basic_auth_credentials` | Traefik | HTTP Basic Auth for dashboard (htpasswd format). Generate: `htpasswd -nb user password` |
| `cf_dns_api_token` | Traefik | Cloudflare API token for Let's Encrypt DNS challenge. Create a token with Zone:DNS:Edit. |
| `nats_auth.conf` | NATS (Home stack) | Client username/password for `authorization` block. See below. |

### `nats_auth.conf` (NATS)

Create `${DOCKERDIR}/secrets/nats_auth.conf` (this file is gitignored). Minimum example — **change username/password before production**:

```
authorization {
  users: [
    {
      user: homestack
      password: your-strong-password
    }
  ]
}
```

Refs: [Authentication](https://docs.nats.io/running-a-nats-service/configuration/securing_nats/auth_intro), [username/password](https://docs.nats.io/running-a-nats-service/configuration/securing_nats/username_password).

Ensure these files exist before starting the Infrastructure stack.

For Home stack NATS, also ensure `appdata/nats/nats-server.conf` exists (tracked in repo) and `nats_auth.conf` is present before `docker compose -f docker-compose-homestack.yml up -d`.
