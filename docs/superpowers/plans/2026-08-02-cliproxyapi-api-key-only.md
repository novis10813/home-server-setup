# CLIProxyAPI API Key-Only Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow internal API clients to access `cliproxy.novis.page` with only a CLIProxyAPI bearer key, without Traefik OAuth.

**Architecture:** Replace the API router's OAuth middleware with the existing `chain-no-auth@file`, which keeps Traefik rate limiting and security headers. The management hostname remains on `chain-oauth@file`; CLIProxyAPI continues to enforce the configured `api-keys` for API calls.

**Tech Stack:** Docker Compose, Traefik v3, CLIProxyAPI v7.

---

### Task 1: Remove OAuth only from the API router

**Files:**
- Modify: `compose/apps/cliproxyapi.yml`
- Modify: `docs/app/cliproxyapi.md`

- [x] **Step 1: Change the API router middleware to the no-auth chain**

Replace this label in `compose/apps/cliproxyapi.yml`:

```yaml
- "traefik.http.routers.cli-proxy-api-rtr.middlewares=chain-oauth@file"
```

with:

```yaml
- "traefik.http.routers.cli-proxy-api-rtr.middlewares=chain-no-auth@file"
```

Expected: `cliproxy.${DOMAINNAME_1}` no longer redirects API requests to OAuth, but retains TLS, rate limiting, and security headers.

- [x] **Step 2: Update the API client documentation**

State that the API endpoint requires the `api-keys` bearer token but does not require OAuth; retain the management page's OAuth and management-key requirements.

Expected: the documented access policy matches the active Traefik routers.

### Task 2: Apply and verify

**Files:**
- Verify: `compose/apps/cliproxyapi.yml`

- [x] **Step 1: Validate the Compose expansion**

Run:

```bash
docker compose -f docker-compose-app.yml config --quiet
```

Expected: exit code 0.

- [x] **Step 2: Recreate only the target service**

Run:

```bash
docker compose -f docker-compose-app.yml up -d --force-recreate cli-proxy-api
```

Expected: `cli-proxy-api` is running.

- [x] **Step 3: Confirm the API endpoint does not redirect to OAuth**

Run:

```bash
curl -sk -o /dev/null -w '%{http_code}\n' --resolve cliproxy.novis.page:443:127.0.0.1 https://cliproxy.novis.page/v1/models
```

Expected: CLIProxyAPI returns `401` for the missing bearer key, not Traefik's OAuth redirect.
