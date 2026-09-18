#!/usr/bin/env node
// Minimal Home Assistant WebSocket API client (2026.x auth format).
//
// Usage:
//   node ha_ws.mjs <ha_url> <access_token> '<json array of commands>'
//
// Examples:
//   node ha_ws.mjs http://192.168.90.29:8123 "$TOKEN" \
//     '[{"type":"call_service","domain":"automation","service":"reload"}]'
//   node ha_ws.mjs http://192.168.90.29:8123 "$TOKEN" \
//     '[{"type":"automation/config","entity_id":"automation.xxx"}]'
//
// Notes:
//   - First server message is {"type":"auth_required"} — the auth reply must
//     NOT include an "id" field (2026.x rejects it: extra keys not allowed).
//   - call_service takes separate domain/service keys + a target object.
//   - Success returns {id,type:"result",context:{...}} (no "success" key);
//     failure returns {success:false,error:{code,message}}.
//
// Requires Node 22+ (built-in WebSocket).

import { readFileSync } from "fs";

const [, , URL, TOKEN, cmdJson] = process.argv;
if (!URL || !TOKEN || !cmdJson) {
  console.error("usage: node ha_ws.mjs <ha_url> <token> '<json commands array>'");
  process.exit(2);
}
const cmds = JSON.parse(cmdJson);
const wsUrl = URL.replace(/^http/, "ws") + "/api/websocket";

const ws = new WebSocket(wsUrl);
let nextId = 100;
const pending = new Map();

ws.onmessage = (ev) => {
  const msg = JSON.parse(typeof ev.data === "string" ? ev.data : Buffer.from(ev.data).toString());
  if (msg.type === "auth_required") {
    ws.send(JSON.stringify({ type: "auth", access_token: TOKEN }));
    return;
  }
  if (msg.type === "auth_ok") {
    for (const c of cmds) {
      const id = nextId++;
      ws.send(JSON.stringify({ ...c, id }));
      pending.set(id, c.type);
    }
    return;
  }
  if (msg.type === "auth_invalid") {
    console.error("AUTH_INVALID — check the token");
    process.exit(3);
  }
  if (pending.has(msg.id)) {
    const label = pending.get(msg.id);
    pending.delete(msg.id);
    console.log(`=== ${label} ===`);
    console.log(JSON.stringify(msg.success === false ? msg : msg.result ?? msg, null, 1).slice(0, 6000));
    if (pending.size === 0) process.exit(0);
  }
};
ws.onerror = (e) => {
  console.error("WS_ERROR", e.message || String(e));
  process.exit(1);
};
setTimeout(() => {
  console.error("TIMEOUT — HA not responding or commands hung");
  process.exit(2);
}, 15000);
