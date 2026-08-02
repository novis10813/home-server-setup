# CLIProxyAPI Management UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish CLIProxyAPI's built-in management control panel at `https://cliproxyapi.novis.page` behind the existing OAuth middleware.

**Architecture:** Enable CLIProxyAPI remote management and its bundled `management.html` control panel using a separate management key stored in the existing untracked configuration secret. Add a second Traefik router on the same internal HTTPS entrypoint; its root URL redirects to `/management.html`, while the existing `cliproxy.novis.page` API router is unchanged.

**Tech Stack:** Docker Compose, Traefik v3, CLIProxyAPI v7, Docker secret bind mount.

---

### Task 1: Enable the built-in control panel

**Files:**
- Modify: `secrets/cli-proxy-api-config.yaml`

- [x] **Step 1: Generate and record a dedicated management key without exposing it in documentation**

Run:

```bash
openssl rand -base64 32
```

Expected: a non-empty, 32-byte random value encoded as Base64.

- [x] **Step 2: Enable only the required remote-management settings**

Set the existing `remote-management` mapping to:

```yaml
remote-management:
  allow-remote: true
  secret-key: <generated-management-key>
  disable-control-panel: false
```

Expected: `/management.html` becomes available and `/v0/management/*` requires the management key.

### Task 2: Add the management hostname router

**Files:**
- Modify: `compose/apps/cliproxyapi.yml`
- Modify: `docs/app/cliproxyapi.md`
- Modify: `docs/app/README.md`

- [x] **Step 1: Add a root redirect middleware and router for `cliproxyapi.${DOMAINNAME_1}`**

Add Traefik labels that redirect only `https://cliproxyapi.${DOMAINNAME_1}/` to `/management.html`, and route the management hostname to `cli-proxy-api-svc` on port `8317` through `chain-oauth@file`.

Expected: the browser opens the management control panel after OAuth, while API requests to `cliproxy.${DOMAINNAME_1}/v1` keep their existing routing.

- [x] **Step 2: Document the new hostname and two authentication layers**

Document `https://cliproxyapi.${DOMAINNAME_1}` as the control-panel URL, requiring Traefik OAuth followed by the dedicated CLIProxyAPI management key.

Expected: operators do not use the API bearer key for management access.

### Task 3: Apply and verify

**Files:**
- Verify: `compose/apps/cliproxyapi.yml`

- [x] **Step 1: Validate the Compose expansion**

Run:

```bash
docker compose -f docker-compose-app.yml config --quiet
```

Expected: exit code 0.

- [x] **Step 2: Recreate only CLIProxyAPI**

Run:

```bash
docker compose -f docker-compose-app.yml up -d --force-recreate cli-proxy-api
```

Expected: `cli-proxy-api` is running and logs report that the API server started.

- [x] **Step 3: Verify the control-panel response through Traefik**

Run:

```bash
curl -Ik https://cliproxyapi.novis.page/
```

Expected: an OAuth redirect for an unauthenticated request, followed by `/management.html` after OAuth in a browser.
