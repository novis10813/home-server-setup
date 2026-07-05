# MinIO

Homestack uses a single-node MinIO service as S3-compatible object storage for raw
market data and Nautilus catalog output.

## Endpoints

| 用途 | Endpoint | 說明 |
|------|----------|------|
| Docker services | `http://minio:9000` | `homestack` Docker network 內部連線 |
| LAN / human S3 clients | `https://s3.${DOMAINNAME_1}` | Traefik `websecure-internal`，middleware `chain-no-auth-relaxed@file` |
| Console | `https://minio.${DOMAINNAME_1}` | Traefik `websecure-internal`，middleware `chain-oauth@file` |

S3 API 不套 OAuth，因為 S3 clients 不能完成瀏覽器 OAuth flow。保護邊界是
internal-only Traefik entrypoint 與 MinIO access key/secret key。

## Data And Credentials

| 項目 | 值 |
|------|----|
| Data volume | `${DATADIR}/minio` |
| Root credentials | `${DOCKERDIR}/secrets/minio.env` |
| App credentials | `MINIO_APP_ACCESS_KEY` / `MINIO_APP_SECRET_KEY` in `secrets/minio.env` |
| Buckets | `market-data`, `nautilus-data` |
| App policy | `homestack-s3` read/write on both buckets |

`minio-init` is an idempotent one-shot container. It creates the buckets, creates
or verifies the `homestack-s3` policy, creates the app user, and attaches the
policy.

## Operations

```bash
cd ${DOCKERDIR}

docker compose -f docker-compose-homestack.yml up -d minio minio-init
docker compose -f docker-compose-homestack.yml logs -f minio minio-init
docker compose -f docker-compose-homestack.yml ps minio

curl -fsS https://s3.${DOMAINNAME_1}/minio/health/live
```

Create a local `mc` alias from another container on the Homestack network:

```bash
docker run --rm --network homestack \
  --env-file ${DOCKERDIR}/secrets/minio.env \
  minio/mc:${MINIO_MC_VERSION:-latest} \
  sh -c 'mc alias set local http://minio:9000 "$MINIO_APP_ACCESS_KEY" "$MINIO_APP_SECRET_KEY" && mc ls local'
```

## Migration From Remote MinIO

After local MinIO is running, mirror only the buckets used by Homestack:

```bash
docker run --rm --network homestack \
  --env-file ${DOCKERDIR}/secrets/minio.env \
  minio/mc:${MINIO_MC_VERSION:-latest} sh

mc alias set old http://140.113.87.172:9000 "$OLD_MINIO_ACCESS_KEY" "$OLD_MINIO_SECRET_KEY"
mc alias set new http://minio:9000 "$MINIO_APP_ACCESS_KEY" "$MINIO_APP_SECRET_KEY"

mc mirror --overwrite old/market-data new/market-data
mc mirror --overwrite old/nautilus-data new/nautilus-data

mc du old/market-data new/market-data
mc du old/nautilus-data new/nautilus-data
mc ls --recursive old/market-data | wc -l
mc ls --recursive new/market-data | wc -l
mc ls --recursive old/nautilus-data | wc -l
mc ls --recursive new/nautilus-data | wc -l
```

Only restart S3 consumers after object counts and sizes match.
