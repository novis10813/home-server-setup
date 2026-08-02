# CLIProxyAPI Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CLIProxyAPI to the App Docker Compose stack with internal Traefik access and secret-managed API configuration.

**Architecture:** The service runs in `compose/apps/cliproxyapi.yml` on the existing `t3_proxy` network. Traefik exposes only HTTPS on the internal entrypoint, protected by the existing OAuth chain; CLIProxyAPI's configuration is supplied as a Docker secret and runtime credentials/logs live under `${DATADIR}`.

**Tech Stack:** Docker Compose, Traefik v3, Docker secrets, MkDocs.

---

### Task 1: Add the service definition

**Files:**
- Create: `compose/apps/cliproxyapi.yml`
- Modify: `docker-compose-app.yml`

- [x] Define `cli-proxy-api` using the upstream `eceasy/cli-proxy-api` image, the required restart and no-new-privileges settings, `t3_proxy`, persistent runtime directories, and resource limits.
- [x] Mount `cli_proxy_api_config` at `/CLIProxyAPI/config.yaml` as a read-only secret so API keys and management credentials are never tracked.
- [x] Add an internal HTTPS Traefik router for `cliproxy.${DOMAINNAME_1}`, protect it with `chain-oauth@file`, and target port `8317`.
- [x] Include the service and declare its secret in `docker-compose-app.yml`.
- [x] Verify with `docker compose -f docker-compose-app.yml config --quiet`.

### Task 2: Document secure deployment

**Files:**
- Modify: `.env.example`
- Modify: `secrets/README.md`
- Create: `docs/app/cliproxyapi.md`
- Modify: `docs/app/README.md`
- Modify: `docs/infrastructure/configuration.md`
- Modify: `mkdocs.yml`

- [x] Add a commented image-version setting to `.env.example`.
- [x] Document the required secret configuration file, including non-placeholder API key and disabled remote management defaults.
- [x] Document startup, Codex device login, endpoint usage, persistent paths, and backup requirements.
- [x] Add the application to the App service inventory and MkDocs navigation.
- [x] Verify with `mkdocs build --strict` when MkDocs is installed.
