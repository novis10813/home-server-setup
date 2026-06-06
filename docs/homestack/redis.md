# Redis

Redis is used by `dashboard-api` as an ephemeral hot cache for short-term Bookmap
visual data.

## Purpose

- Store the latest 5 minutes of derived Heatmap columns and Volume Bubble records.
- Let `financial-dashboard` hydrate PairFocus immediately after card reopen or browser
  refresh.
- Avoid storing long-term raw orderbook history in Redis.

## Runtime

Redis runs only on the internal `homestack` Docker network. Browsers do not connect to
Redis directly; all access goes through `dashboard-api`.

Persistence is disabled:

```text
redis-server --save "" --appendonly no
```

This is intentional because the cache is short-lived visual state.

## Dashboard API Environment

```text
REDIS_URL=redis://redis:6379
BOOKMAP_CACHE_TTL_SEC=360
BOOKMAP_CACHE_COLUMNS=300
BOOKMAP_CACHE_SAMPLE_MS=1000
```

## Operations

```bash
cd /opt/docker
docker compose -f docker-compose-homestack.yml ps redis
docker compose -f docker-compose-homestack.yml logs -f redis
docker compose -f docker-compose-homestack.yml exec redis redis-cli ping
```
