# Cloudflare Enterprise — Capabilities & API Reference for Agents

> **Purpose.** A single reference so Cloudflare-focused agents understand the full surface
> of an **Enterprise** Cloudflare account: every major product area, what it can do, the
> API entry points to drive it, and decision playbooks for solving real customer cases.
>
> **Knowledge basis.** Compiled from Cloudflare product/API knowledge as of **January 2026**.
> This is a *capabilities catalog*, not a dump of any one zone. To reflect the live state of a
> specific zone/account, drive the real API (see [§2](#2-api-fundamentals)) with a scoped token —
> this document tells the agent *what to query and why*.
>
> **How an agent should use this doc**
> 1. Identify the customer's goal (perf / security / availability / dev-platform / network / Zero Trust).
> 2. Jump to the relevant product section; read **Capabilities** + **When to use** + **Key endpoints**.
> 3. Cross-check **Interactions & gotchas** (ordering, precedence, plan-gating).
> 4. Consult **§19 Playbooks** for end-to-end solution patterns.
> 5. Before any write, follow **§20 Safe-change protocol** (read current state, dry-run, stage, verify, roll back).

---

## Table of contents

1. [Mental model: how Cloudflare fits together](#1-mental-model)
2. [API fundamentals](#2-api-fundamentals)
3. [Accounts, zones, members & RBAC](#3-accounts-zones-members--rbac)
4. [DNS](#4-dns)
5. [SSL/TLS & certificates](#5-ssltls--certificates)
6. [CDN, caching & the Rules engine](#6-cdn-caching--rules-engine)
7. [Performance products](#7-performance-products)
8. [Application security: WAF, DDoS, rate limiting](#8-application-security)
9. [Bot management, API Shield, Page Shield](#9-bot-api-page-shield)
10. [Load balancing, health & Waiting Room](#10-load-balancing-waiting-room)
11. [Spectrum (L4 proxy)](#11-spectrum)
12. [Network services: Magic Transit / WAN / Firewall, BYOIP, CNI](#12-network-services)
13. [Zero Trust / SASE (Access, Gateway, Tunnel, DLP, CASB, RBI)](#13-zero-trust-sase)
14. [Developer platform (Workers, R2, D1, KV, DO, Queues, AI, Pages, Stream)](#14-developer-platform)
15. [Logs, analytics & observability](#15-logs-analytics-observability)
16. [Enterprise-only features & add-ons](#16-enterprise-only-features)
17. [Automation & tooling (Terraform, Wrangler, GraphQL)](#17-automation--tooling)
18. [Plan-gating quick matrix](#18-plan-gating-matrix)
19. [Solution playbooks for common customer cases](#19-playbooks)
20. [Safe-change protocol for agents](#20-safe-change-protocol)

---

<a id="1-mental-model"></a>
## 1. Mental model: how Cloudflare fits together

Cloudflare is a **global reverse proxy + programmable edge** sitting between clients and origins.
Traffic for a proxied hostname flows through one anycast edge PoP, where products execute in a
defined order. Understanding that order is the key to predicting behavior.

**Simplified request lifecycle through the edge (ingress → origin):**

```
Client
  → L3/4 DDoS mitigation (Magic Transit / always-on network DDoS)
  → TLS termination (Edge certificate)
  → HTTP/3 / HTTP/2 handling
  → Rules: Configuration Rules → URL Rewrite/Transform → Redirect Rules
  → Security: WAF custom rules → WAF managed rulesets → Rate limiting → Bot Management → API Shield
  → Workers (fetch event) ── can short-circuit or sub-request
  → Cache lookup (Cache Rules decide eligibility/TTL/keys) → HIT? serve
  → MISS → Origin Rules (host/port/SNI override) → Load Balancing / Argo Smart Routing
  → Origin (or Tunnel / Spectrum / R2 / Pages)
Response path: Polish/Mirage/Image Resizing, Response Header Transform, compression, cache write, Page Shield scan
```

**Two scopes matter for every API call and product:**
- **Account scope** — billing, members, tokens, Workers, R2, Zero Trust, Magic networking, account-level rulesets/WAF, Logpush ownership.
- **Zone scope** — a single domain: DNS, edge certs, cache, page/rules, zone-level WAF, analytics.

Enterprise unlocks **account-level** application of many zone features (e.g. one WAF custom ruleset
deployed across all zones), higher limits, dedicated certs, and contractual products (China Network,
BYOIP, CNI, custom Bot Management, advanced Logpush destinations).

---

<a id="2-api-fundamentals"></a>
## 2. API fundamentals

### Base & shape
- **REST base:** `https://api.cloudflare.com/client/v4/`
- **GraphQL analytics:** `https://api.cloudflare.com/client/v4/graphql`
- **Response envelope (REST):**
  ```json
  { "success": true, "errors": [], "messages": [], "result": { }, "result_info": { } }
  ```
  Always branch on `success`; `errors[].code` is stable and machine-actionable.

### Authentication (prefer scoped API Tokens)
| Method | Header | Notes |
|---|---|---|
| **API Token** (recommended) | `Authorization: Bearer <token>` | Scoped to specific permissions + account/zone resources; supports IP allowlist, TTL, audit. |
| API Key (legacy) | `X-Auth-Email` + `X-Auth-Key` | Full account power — avoid; rotate to tokens. |
| Origin CA Key | `X-Auth-User-Service-Key` | Only for Origin CA cert issuance. |

**Token permission groups** map to product areas (e.g. `DNS:Edit`, `Zone WAF:Edit`,
`Workers Scripts:Edit`, `Logs:Read`, `Account Rulesets:Edit`). Always mint **least-privilege** tokens.
Verify a token: `GET /user/tokens/verify`.

### Conventions agents must handle
- **Pagination:** `?page=1&per_page=50` (max usually 1000/list varies); read `result_info.total_count`.
  Some newer endpoints use **cursor** pagination (`result_info.cursor`).
- **Filtering/sorting:** product-specific query params (`?match=all&type=A&order=name&direction=asc`).
- **Rate limits:** global ~1200 req / 5 min per user; respect `429` + back off. Bulk via batch endpoints where available (e.g. DNS `POST .../dns_records/batch`).
- **Idempotency:** prefer `PATCH` (partial) over `PUT` (full replace) to avoid clobbering. Rulesets use a version model — `PUT` a ruleset replaces all rules.
- **Discovery pattern for "what's configured":** list zones → for each, query `/dns_records`, `/rulesets`, `/settings`, `/ssl/...`, `/workers/routes`, `/load_balancers`. The **Rulesets API entrypoints** (`/rulesets/phases/<phase>/entrypoint`) reveal active WAF, cache, transform, and redirect config in one place.

### The Rulesets API (the backbone of modern config)
Most request-time behavior is now expressed as **rulesets** bound to **phases** at zone or account level:

| Phase | What it controls |
|---|---|
| `http_request_sanitize` | URL normalization |
| `http_request_transform` | URL rewrite, request header transform |
| `http_request_late_transform` | late request header transform |
| `http_request_redirect` | dynamic / bulk redirects (Single Redirects) |
| `http_config_settings` | Configuration Rules (per-request feature toggles) |
| `http_request_origin` | Origin Rules (host/SNI/port override) |
| `http_request_firewall_custom` | WAF custom rules |
| `http_request_firewall_managed` | WAF Managed Rules (deploy + overrides) |
| `http_ratelimit` | Rate limiting rules |
| `http_request_cache_settings` | Cache Rules |
| `http_request_dynamic_redirect` | dynamic redirects |
| `http_response_headers_transform` | Response Header Transform |
| `http_response_compression` | compression rules |
| `ddos_l4` / `ddos_l7` | DDoS managed ruleset overrides |

Read active config: `GET /zones/{zone_id}/rulesets/phases/{phase}/entrypoint`.

---

<a id="3-accounts-zones-members--rbac"></a>
## 3. Accounts, zones, members & RBAC

**Capabilities:** create/manage zones (full setup or **partial/CNAME** setup, or **secondary DNS**),
manage account members, roles, API tokens, audit logs, account settings, subscriptions.

**Key endpoints**
- Accounts: `GET /accounts`, `GET /accounts/{id}`, `PATCH /accounts/{id}`
- Zones: `GET /zones`, `POST /zones`, `PATCH /zones/{id}`, `DELETE /zones/{id}`; activation check `PUT /zones/{id}/activation_check`
- Zone settings (per-feature): `GET/PATCH /zones/{id}/settings/{name}` (e.g. `ssl`, `min_tls_version`, `http3`, `0rtt`, `brotli`, `always_use_https`, `automatic_https_rewrites`, `opportunistic_encryption`, `websockets`, `ip_geolocation`, `security_header` HSTS)
- Members & roles: `GET/POST /accounts/{id}/members`, `GET /accounts/{id}/roles`
- API tokens: `GET/POST /user/tokens`, `/accounts/{id}/tokens`; `GET /user/tokens/permission_groups`
- Audit logs: `GET /accounts/{id}/audit_logs` (or the newer audit-logs v2)

**Enterprise notes:** SSO/SAML + SCIM provisioning, granular custom roles, **Scoped roles** per zone,
domain-scoped tokens, and account-level policy. Use audit logs as the source of truth for change history.

---

<a id="4-dns"></a>
## 4. DNS

**Capabilities**
- Authoritative DNS (primary), **Secondary DNS** (Cloudflare as secondary, inbound AXFR/IXFR), and
  **Secondary Override / hidden primary** patterns; DNSSEC (one-click), multi-signer DNSSEC.
- All record types incl. `A/AAAA/CNAME/MX/TXT/SRV/CAA/NS/PTR/SVCB/HTTPS/TLSA/SSHFP/DS/DNSKEY/SMIMEA/URI/LOC/NAPTR`.
- **CNAME flattening** (apex CNAME), proxied (orange-cloud) vs DNS-only (grey-cloud).
- **Custom nameservers (account & zone level)**, vanity NS.
- **Zone Transfers / Multi-provider**, **Foundation DNS** (Enterprise advanced DNS — dedicated NS, faster propagation, higher resilience).
- **DNS Firewall** (managed resolver protection for external authoritative).
- Analytics: per-record/query-type DNS analytics.

**Key endpoints**
- Records: `GET/POST/PATCH/PUT/DELETE /zones/{id}/dns_records[/{rec}]`; bulk: `POST /zones/{id}/dns_records/batch`; import/export: `/dns_records/import`, `/dns_records/export`
- DNSSEC: `GET/PATCH/DELETE /zones/{id}/dnssec`
- Secondary DNS: `/accounts/{id}/secondary_dns/...` (ACLs, peers, TSIG), zone transfer config under zone
- DNS analytics: `GET /zones/{id}/dns_analytics/report[/bytime]`

**Gotchas:** proxied records hide the origin IP (security win) but mean only HTTP/S (+ Spectrum) ports
are proxied; non-web protocols need DNS-only or Spectrum. Changing proxy status changes which
products apply. `proxied:true` requires a compatible record type.

---

<a id="5-ssltls--certificates"></a>
## 5. SSL/TLS & certificates

**Edge (client ↔ Cloudflare) certificates**
- **Universal SSL** (free, auto SAN).
- **Advanced Certificate Manager (ACM)** — custom hostnames/wildcards, choice of CA (Let's Encrypt, Google Trust Services, SSL.com), cert validity, **Total TLS** (auto-cert every hostname), advanced validation (TXT/HTTP/delegated DCV).
- **Custom certificates** (upload your own / dedicated), **Geo Key Manager** (restrict private-key geography), **Keyless SSL** (private key stays in customer infra).
- **Cloudflare for SaaS / Custom Hostnames** — issue certs for *your customers'* domains pointing at your SaaS (per-hostname certs, custom origin, custom metadata).

**Origin (Cloudflare ↔ origin) security**
- **Origin CA certificates** (free 15-yr certs trusted by Cloudflare).
- **Authenticated Origin Pulls (mTLS)** — zone-wide or per-hostname client cert from edge to origin.
- **SSL/TLS modes:** `off | flexible | full | strict (full strict) | strict_origin_pull`. *Recommend Full (strict).*

**Controls:** `min_tls_version` (1.0–1.3), TLS 1.3, **mTLS for clients** (API Shield), HSTS, automatic HTTPS rewrites, Always Use HTTPS, opportunistic encryption, ECH.

**Key endpoints**
- Edge certs: `GET /zones/{id}/ssl/certificate_packs`, ACM order `POST .../certificate_packs/order`
- Custom certs: `/zones/{id}/custom_certificates`
- Origin CA: `POST /certificates` (with Origin CA key)
- Authenticated Origin Pull: `/zones/{id}/origin_tls_client_auth[/hostnames]`
- Cloudflare for SaaS: `/zones/{id}/custom_hostnames`
- Keyless: `/zones/{id}/keyless_certificates`
- Client mTLS (API Shield): `/zones/{id}/certificate_authorities/hostname_associations`, `/accounts/{id}/mtls_certificates`

**Gotchas:** `flexible` re-encrypts nothing to origin → loops/mixed content; never recommend for prod.
ACM is required for non-Universal SAN/wildcards. Total TLS interacts with DNS proxied state.

---

<a id="6-cdn-caching--rules-engine"></a>
## 6. CDN, caching & the Rules engine

**Caching capabilities**
- **Cache Rules** (modern, ruleset-based): match by URI/host/header/cookie → set edge TTL, browser TTL,
  cache key (custom: query/header/cookie/host/device), cache eligibility, **Cache Reserve** eligibility,
  origin error caching, serve-stale.
- **Tiered Cache** (Smart / Generic / **Custom topology**) — upper-tier PoPs reduce origin load.
- **Cache Reserve** — persistent R2-backed cache layer for long-tail/large objects.
- **Serve Stale / Always Online** (Internet Archive fallback).
- **Purge**: by URL, prefix (Ent), hostname (Ent), tag (Ent — `Cache-Tag` header), everything.
- Cache-control respect, Edge Cache TTL, Origin Cache Control, bypass on cookie.

**Rules engine (all ruleset-based — see §2 phases)**
- **Configuration Rules** — toggle features per request (SSL mode, cache level, Polish, Email Obfuscation, Auto Minify, Rocket Loader, security level, BIC, etc.).
- **Transform Rules** — **URL Rewrite** (path/query), **Request Header Transform**, **Response Header Transform** (set/remove headers, even dynamic from fields).
- **Redirect Rules / Single Redirects** + **Bulk Redirects** (account-level lists, millions of redirects).
- **Origin Rules** — override origin host, **SNI**, port, DNS record, Host header per request.
- **Compression Rules** — choose brotli/gzip/zstd per content type.
- **Snippets** — lightweight JS at the edge (lighter than Workers) for header/logic tweaks.
- **Cloud Connector** — route matching requests to cloud storage (S3/GCS/R2/Azure) without an origin server.
- **Page Rules** (legacy, being superseded by the above — still present; finite per-zone count).

**Key endpoints:** everything via `/zones/{id}/rulesets...` (create ruleset for phase, add rules),
`/zones/{id}/purge_cache`, account Bulk Redirects via **Lists** `/accounts/{id}/rules/lists`.

**Precedence gotchas:** Single Redirects run **before** most security; Cache Rules override Page Rules
caching when both match; Configuration Rules can disable a feature a Page Rule enabled — **migrate off
Page Rules** to avoid conflicting layers. Custom cache keys can fragment or unify cache — test carefully.

---

<a id="7-performance-products"></a>
## 7. Performance products

| Product | What it does | When to use |
|---|---|---|
| **Argo Smart Routing** | Routes over least-congested Cloudflare backbone paths | Dynamic/uncacheable traffic, global users, latency-sensitive |
| **Tiered Cache / Cache Reserve** | Fewer origin pulls, persistent cache | High cache-miss origin load, large catalogs |
| **Image Resizing / Cloudflare Images** | On-the-fly resize/format (AVIF/WebP), storage + variants | Image-heavy sites, responsive delivery |
| **Polish** | Lossy/lossless image optimization + WebP | Quick image perf win without code |
| **Mirage** | Mobile image lazy/adaptive loading | Mobile-first, slow networks |
| **Rocket Loader** | Async JS loading | Legacy sites with many blocking scripts (test for breakage) |
| **Early Hints (103)** | Preload/preconnect hints from cached headers | Improve LCP |
| **HTTP/3 (QUIC), 0-RTT, ECH** | Modern transport | Enable broadly; 0-RTT only for idempotent |
| **Smart Tiered Cache / Regional Tiered Cache** | Topology tuning | Geographically split origins |
| **Zaraz** | Third-party script/tag manager at edge | Offload analytics/marketing tags |
| **Speed/Observatory** | Synthetic Lighthouse + RUM | Measure & track Core Web Vitals |

Most are toggled via **zone settings** or **Configuration Rules**; Images/Stream have dedicated APIs
(`/accounts/{id}/images/v1`, `/accounts/{id}/stream`).

---

<a id="8-application-security"></a>
## 8. Application security: WAF, DDoS, rate limiting

**WAF (ruleset-based)**
- **Managed Rulesets:** *Cloudflare Managed Ruleset*, *Cloudflare OWASP Core Ruleset* (anomaly scoring + paranoia/sensitivity), *Cloudflare Exposed Credentials Check*. Deploy at zone or **account** level; per-rule overrides (action/sensitivity/status), tag-based overrides, skip rules.
- **Custom Rules** (`http_request_firewall_custom`): expression language over rich fields
  (`http.request.uri.path`, `ip.geoip.country`, `cf.threat_score`, `cf.bot_management.score`,
  `http.request.headers`, `ssl`, `cf.waf.score` ML attack score, etc.). Actions: `block, challenge,
  managed_challenge, js_challenge, skip, log, redirect`.
- **WAF Attack Score (ML)** and **Leaked Credentials / Firewall for AI** detections.
- **Sensitive Data Detection** (response-side PII flagging).
- **Custom error responses / block pages**.

**Rate Limiting (`http_ratelimit`)**
- Advanced rate limiting: counting by IP, header, cookie, JA3/JA4, query param; complex characteristics;
  per-period + mitigation timeout; counting on response status/headers; **Account-level**.

**DDoS protection**
- Always-on, unmetered **L3/4 network DDoS** + **L7 HTTP DDoS** managed rulesets (`ddos_l4`, `ddos_l7`)
  with sensitivity/action overrides. Adaptive DDoS, **Advanced TCP/DNS protection** (Magic).
- **Under Attack Mode** (zone security level) for emergencies.

**Key endpoints:** `/zones/{id}/rulesets...` (phases above), legacy `/zones/{id}/firewall/rules` +
`/filters` (deprecated → migrate to custom rules), `/accounts/{id}/rulesets` for account WAF.

**Ordering:** custom rules → managed rules → rate limiting → bots within the security stack; use
`skip` rules to create allowlists that bypass downstream phases. Always test new blocks in **Log**
action first, watch Security Events, then escalate to block.

---

<a id="9-bot-api-page-shield"></a>
## 9. Bot Management, API Shield, Page Shield

**Bot Management (Enterprise)**
- ML **bot score** (1–99), **verified bot** directory, **JA3/JA4 fingerprints**, heuristics, **Anomaly
  detection**, **AI bots / AI crawler** controls (`block AI bots`, AI Audit), **Turnstile** (privacy CAPTCHA alt).
- Drive decisions via custom rules referencing `cf.bot_management.*` (score, verified_bot, ja3_hash,
  static_resource, corporate_proxy). **Bot fight mode / Super Bot Fight Mode** for lower tiers.

**API Shield**
- **Schema validation** (OpenAPI upload → enforce), **mTLS** client cert enforcement, **JWT validation**,
  **API Discovery** (learns endpoints), **Sequence/Volumetric abuse** detection, **Schema learning**,
  **GraphQL malicious query protection**, BOLA/auth checks.
- Endpoints: `/zones/{id}/api_gateway/...` (operations, schemas, user_schemas, settings, discovery).

**Page Shield (client-side security)**
- Monitors **scripts, connections, cookies** loaded in the browser (Magecart/supply-chain), CSP
  reporting, policies/alerts. Endpoints: `/zones/{id}/page_shield/...`.

**Turnstile:** `/accounts/{id}/challenges/widgets` — invisible/managed challenge widget for forms/APIs.

---

<a id="10-load-balancing-waiting-room"></a>
## 10. Load balancing, health monitors & Waiting Room

**Load Balancing**
- Global + local traffic steering: **pools** of origins, **monitors** (HTTP/S/TCP/UDP/ICMP health checks
  from multiple regions), steering policies: off/geo/**dynamic latency**/random/proportional/**least
  outstanding requests**/least connections, **session affinity** (cookie/header/IP), failover, weighted
  pools, **Adaptive Routing**, region/POP-based steering.
- **Zero-Downtime Failover**, origin overrides per pool.

**Endpoints**
- Account pools/monitors: `/accounts/{id}/load_balancers/pools`, `/monitors`
- Zone LBs: `/zones/{id}/load_balancers`
- Analytics & health: `/load_balancers/.../analytics`, pool health

**Waiting Room** (virtual queue for traffic surges)
- Configurable thresholds (active/total users), queueing methods (FIFO/random/passthrough/reject),
  custom HTML, JSON events, **Waiting Room Rules**. Endpoints: `/zones/{id}/waiting_rooms`.

---

<a id="11-spectrum"></a>
## 11. Spectrum (L4 reverse proxy for any TCP/UDP)

- Proxy **arbitrary TCP/UDP** apps (SSH, RDP, gaming, minecraft, SMTP, custom protocols) with DDoS
  protection, Argo, and TLS termination — extends Cloudflare's edge beyond HTTP.
- **Enterprise:** full port ranges, BYO IP, PROXY protocol, more protocols.
- Endpoints: `/zones/{id}/spectrum/apps`.

---

<a id="12-network-services"></a>
## 12. Network services (Magic / connectivity)

| Product | Purpose |
|---|---|
| **Magic Transit** | BGP-advertised or tunneled L3 DDoS protection + routing for on-prem/data-center IP ranges |
| **Magic WAN** | Cloud-delivered SD-WAN: connect sites/clouds/users via anycast GRE/IPsec tunnels + WARP |
| **Magic Firewall** | Network-layer firewall-as-a-service (L3/4 rules, ruleset engine, IDS) |
| **Magic Network Monitoring** | Flow-based network visibility |
| **BYOIP** | Bring your own IP prefixes onto Cloudflare anycast |
| **Cloudflare Network Interconnect (CNI)** | Private interconnect (physical/virtual, cloud onramps) to Cloudflare |
| **Spectrum** | (see §11) app-level L4 |
| **Aegis** | Dedicated egress IPs from Cloudflare to origin (origin allowlisting) |

**Endpoints:** `/accounts/{id}/magic/...` (IPsec/GRE tunnels, static routes, sites), Magic Firewall via
account rulesets (`magic_transit` phases), `/accounts/{id}/addressing/...` (BYOIP prefixes, service bindings).

These are **contractual Enterprise** products — onboarding involves BGP/tunnel coordination, not just API.

---

<a id="13-zero-trust-sase"></a>
## 13. Zero Trust / SASE

A full **SSE/SASE** suite under the account (`/accounts/{id}/...` + the Zero Trust org).

- **Access** (ZTNA): identity-aware app gateway. **Applications** (self-hosted, SaaS, private/L4,
  infrastructure/SSH, RDP, browser-rendered) + **Policies** (allow/deny/bypass with rules on identity,
  device posture, country, mTLS, IdP groups), multiple **IdPs** (SAML/OIDC/social/one-time-PIN),
  **service tokens**, **SCIM**, short-lived SSH certs, **Access for Infrastructure**.
  Endpoints: `/accounts/{id}/access/apps`, `/access/policies`, `/access/identity_providers`,
  `/access/service_tokens`, `/access/groups`.
- **Gateway** (SWG): DNS / network / HTTP filtering, TLS decryption, AV, **DLP profiles**,
  Anti-virus, sandboxing, content categories, **Data Loss Prevention**, **CASB** integrations.
  Endpoints: `/accounts/{id}/gateway/rules`, `/gateway/lists`, `/gateway/locations`, `/gateway/proxy_endpoints`.
- **Tunnel (cloudflared)**: outbound-only connector exposing private apps/networks without inbound
  firewall holes. WARP-to-Tunnel for private routing. Endpoints: `/accounts/{id}/cfd_tunnel`,
  `/accounts/{id}/teamnet/routes` (private network routes), virtual networks.
- **WARP client + Device posture**: managed device enrollment, posture checks (OS, disk encryption,
  firewall, serial, third-party EDR), split tunnels, device profiles.
- **DLP / CASB / RBI**: data classification, SaaS misconfig scanning, **Remote Browser Isolation**
  (clientless or WARP), email security (Area 1 / Cloudflare Email Security).
- **Digital Experience Monitoring (DEX)**: synthetic + fleet network telemetry.

ZTNA + SWG + RBI + DLP + CASB + Email = Cloudflare's **SASE** story; agents solving "secure remote
access / replace VPN / inspect egress / stop data exfiltration" live here.

---

<a id="14-developer-platform"></a>
## 14. Developer platform

| Product | What it is | Key API / tool |
|---|---|---|
| **Workers** | Serverless JS/TS/WASM at the edge; routes, cron triggers, Smart Placement | `/accounts/{id}/workers/scripts`, `/zones/{id}/workers/routes`, Wrangler |
| **Workers KV** | Eventually-consistent global KV store | `/accounts/{id}/storage/kv/namespaces` |
| **Durable Objects** | Strongly-consistent stateful coordination/actors | bindings via Workers + migrations |
| **R2** | S3-compatible object storage, **zero egress fees** | `/accounts/{id}/r2/buckets`, S3 API |
| **D1** | Serverless SQLite database | `/accounts/{id}/d1/database` |
| **Queues** | Message queue between Workers | `/accounts/{id}/queues` |
| **Hyperdrive** | Pooling/cache accelerator for external Postgres/MySQL | `/accounts/{id}/hyperdrive/configs` |
| **Workers AI** | Run open models on Cloudflare GPUs | `/accounts/{id}/ai/run/@cf/...` |
| **AI Gateway** | Caching/rate-limit/observability proxy for LLM APIs | `/accounts/{id}/ai-gateway` |
| **Vectorize** | Vector DB for embeddings/RAG | `/accounts/{id}/vectorize` |
| **Pages** | Git-integrated JAMstack/SSR hosting + Functions | `/accounts/{id}/pages/projects` |
| **Stream** | Video ingest/encode/deliver + live | `/accounts/{id}/stream` |
| **Images** | Image storage/resize/variants | `/accounts/{id}/images/v1` |
| **Workers for Platforms** | Multi-tenant "dispatch" Workers for your customers | dispatch namespaces |
| **Email Routing / Email Workers** | Route + process inbound email | `/zones/{id}/email/routing` |
| **Browser Rendering** | Headless Chromium from Workers (Puppeteer) | binding |
| **Calls / Realtime** | WebRTC SFU/TURN | `/accounts/{id}/calls` |

These let agents **build** solutions (custom edge logic, auth gateways, data APIs, RAG, media) rather
than only configure. Enterprise adds higher limits, **Workers for Platforms**, dedicated support.

---

<a id="15-logs-analytics-observability"></a>
## 15. Logs, analytics & observability

- **GraphQL Analytics API** — the unified analytics source: HTTP requests, firewall events, DNS,
  LB, Workers, Spectrum, etc. with filtering/aggregation. `POST /graphql`. *Preferred for dashboards/agents.*
- **Logpush** (Enterprise) — push raw edge logs (HTTP, firewall, DNS, Spectrum, Gateway, Access, Audit,
  NEL, Page Shield, etc.) to **R2, S3, GCS, Azure, Datadog, Splunk, S3-compatible, HTTP, Sumo, New Relic**.
  Endpoints: `/accounts/{id}/logpush/jobs`, `/zones/{id}/logpush/jobs`, dataset fields discovery.
- **Logpull** (legacy pull), **Instant Logs** (live tail), **Edge log fields** customization.
- **Security Analytics / Security Events**, **Web Analytics (RUM)**, **DNS analytics**, **Account/Audit logs**.
- **Workers observability / Tail / Trace Workers**, **Health Checks** (standalone origin monitoring).

Agents diagnosing incidents should start at GraphQL Analytics + Security Events; for forensic depth use Logpush datasets.

---

<a id="16-enterprise-only-features"></a>
## 16. Enterprise-only features & add-ons

- **Account-level WAF / rulesets / Bulk Redirects / Custom Rules** applied across all zones.
- **Bot Management** (full ML), **API Shield** full, **Page Shield** policies.
- **Advanced Certificate Manager**, **Custom/Dedicated certs**, **Keyless SSL**, **Geo Key Manager**, **mTLS**.
- **Logpush** to all destinations + **Audit Logpush**.
- **Cache:** tag/hostname/prefix purge, **Custom Tiered Cache topology**, **Cache Reserve**.
- **Network:** Magic Transit/WAN/Firewall, **BYOIP**, **CNI**, **Aegis** egress IPs, **Spectrum** full.
- **China Network** (ICP-licensed delivery inside mainland China).
- **Foundation DNS Advanced**, **Secondary DNS / multi-provider**.
- **Custom nameservers**, higher Page Rules/redirect/route limits, **rate limiting account-level**.
- **HTTP/2 to origin, gRPC, WebSockets at scale**, **Prioritized support / TAM / SLA**, **SSO/SAML+SCIM**, custom roles.
- **Cloudflare for SaaS** at scale (custom hostnames, **Orange-to-Orange / O2O**).
- **Cloudforce One** (threat intel/ops), **Security Center** (attack surface mgmt), **Cloudflare One** SASE bundle.

When a customer need touches these, the path is usually **commercial enablement first**, then API/config.

---

<a id="17-automation--tooling"></a>
## 17. Automation & tooling

- **Terraform** — `cloudflare/cloudflare` provider; manage zones, DNS, rulesets, WAF, LB, Access,
  Workers, R2, Zero Trust as code. Use `cf-terraforming` to import existing config into HCL.
- **Wrangler** — Workers/Pages/R2/D1/KV/Queues CLI + local dev (`wrangler dev`, `deploy`, `tail`).
- **GraphQL** — analytics/reporting.
- **flarectl / cloudflare-go / cloudflare-python / cloudflare-typescript** — official SDKs.
- **MCP / API tokens** — scoped automation. For agent fleets, mint **per-purpose least-privilege tokens**
  and prefer Terraform for auditable, reversible change with plan/apply (dry-run = `terraform plan`).

---

<a id="18-plan-gating-matrix"></a>
## 18. Plan-gating quick matrix (orientation, not contract)

| Capability | Free | Pro | Business | Enterprise |
|---|---|---|---|---|
| DNS, Universal SSL, basic cache, CDN | ✅ | ✅ | ✅ | ✅ |
| WAF Managed Rules | partial | ✅ | ✅ | ✅ (+account) |
| Custom Rules / Rate limiting | basic | ✅ | ✅ | ✅ advanced |
| Bot Management (ML) | Bot Fight | SBFM | SBFM | ✅ full |
| Image/Polish/Mirage/Argo | — | some | most | ✅ |
| Advanced Cert Manager / Custom certs | — | — | custom cert | ✅ + dedicated/keyless |
| Load Balancing | add-on | add-on | add-on | ✅ advanced steering |
| Logpush | — | — | — | ✅ |
| Spectrum / Magic / BYOIP / CNI / China | — | — | — | ✅ contractual |
| Account-level rulesets / Bulk Redirects | — | — | — | ✅ |
| Workers/R2/D1/Pages/Zero Trust | ✅ tiered usage-based across plans | | | ✅ higher limits |

Always verify live entitlements via the API (zone `plan`, subscriptions) before promising a feature.

---

<a id="19-playbooks"></a>
## 19. Solution playbooks for common customer cases

**A. "Site is slow globally."**
→ Confirm cache hit ratio (GraphQL). Enable Tiered Cache + tune Cache Rules (cacheable assets, TTLs,
custom cache keys). Add Argo Smart Routing for dynamic content. Enable HTTP/3, Early Hints, Polish/Image
Resizing. Verify origin keep-alive/compression. Measure with Observatory before/after.

**B. "We're under attack / credential stuffing / scraping."**
→ Under Attack Mode for triage. WAF custom rules on `cf.threat_score`, `cf.waf.score`,
`cf.bot_management.score`, geo, ASN. Rate limiting on login endpoints (by IP+header). Exposed
Credentials Check. Bot Management for sophisticated bots; API Shield for API abuse. Watch Security
Events; graduate Log→Challenge→Block.

**C. "Protect our APIs."**
→ API Shield: upload OpenAPI schema → schema validation; enforce mTLS client certs; JWT validation;
API Discovery to find shadow endpoints; sequence/volumetric abuse rules; rate limiting per token.

**D. "Replace our VPN / secure remote access."**
→ Cloudflare One: deploy `cloudflared` Tunnel to private apps, Access policies bound to IdP + device
posture, WARP client for users, Gateway for egress filtering/DLP, RBI for risky apps.

**E. "Origin keeps getting hit directly / IP exposure."**
→ Proxy DNS (orange-cloud), Authenticated Origin Pulls (mTLS), firewall origin to Cloudflare IP ranges
(or Aegis dedicated egress IPs), Origin Rules to standardize host/SNI, consider Tunnel to remove public origin entirely.

**F. "SaaS: serve our customers' custom domains."**
→ Cloudflare for SaaS: Custom Hostnames + fallback origin + per-hostname certs (DCV delegation),
custom metadata for per-tenant Workers logic, O2O if customer is also on Cloudflare.

**G. "Centralize logs into our SIEM."**
→ Logpush jobs (HTTP/firewall/Access/Gateway datasets) → Splunk/Datadog/S3/R2; plus GraphQL for dashboards; Audit Logpush for compliance.

**H. "Build custom edge logic / A-B / auth at edge."**
→ Workers (+ KV/D1/DO/R2/Queues), Snippets for light header logic, Configuration/Transform Rules for
no-code cases. Smart Placement for origin-bound workloads.

**I. "Migrate/standardize config safely across many zones."**
→ Account-level rulesets (WAF, redirects), Terraform with `cf-terraforming` import, staged rollout, plan/apply, audit logs verification.

**J. "Big traffic event / launch / sale."**
→ Waiting Room (queue thresholds), pre-warm cache rules, Load Balancing with health monitors + zero-downtime failover, rate limiting safety nets, DDoS sensitivity review.

---

<a id="20-safe-change-protocol"></a>
## 20. Safe-change protocol for agents (mandatory before writes)

1. **Authenticate least-privilege.** Verify token scope (`GET /user/tokens/verify`); never use global keys.
2. **Read current state first.** Snapshot the resource (DNS record, ruleset entrypoint, setting) and
   keep the original for rollback. For rulesets, capture the current ruleset `id`/`version`.
3. **Prefer additive + Log/Simulate.** New WAF/rate rules start in `log`; redirects/transform tested on
   a canary path; cache changes validated against hit ratio.
4. **Dry-run where possible.** Use `terraform plan`; for rulesets, validate expressions before deploy.
5. **Scope tightly.** Zone-level before account-level; one phase ruleset at a time. Remember `PUT` on a
   ruleset **replaces all rules** — use the rule-level endpoints or re-send the full intended set.
6. **Stage → verify → expand.** Apply to one zone/route, confirm via Security Events / Analytics /
   synthetic request, then widen.
7. **Verify with the real signal.** GraphQL Analytics, Security Events, `curl` with `CF-*` headers,
   health checks — confirm intended behavior and no collateral block.
8. **Roll back fast.** Keep the pre-change payload; re-`PATCH`/restore on regression. Check **Audit Logs**.
9. **Respect precedence & plan-gating.** Re-read §1 ordering and §18 before promising behavior.
10. **Never disable SSL to "fix" errors.** Diagnose mode mismatches (Full strict, origin cert) instead.

---

### Appendix: fast endpoint index

```
Auth/verify          GET    /user/tokens/verify
Zones                GET    /zones ; PATCH /zones/{id}
Zone settings        GET/PATCH /zones/{id}/settings/{name}
DNS                  *      /zones/{id}/dns_records[/batch|/import|/export]
DNSSEC               GET/PATCH /zones/{id}/dnssec
Edge certs (ACM)     *      /zones/{id}/ssl/certificate_packs
Custom hostnames     *      /zones/{id}/custom_hostnames
Origin pulls (mTLS)  *      /zones/{id}/origin_tls_client_auth
Rulesets (all)       *      /zones/{id}/rulesets ; phase entrypoint .../phases/{phase}/entrypoint
Account rulesets     *      /accounts/{id}/rulesets
Purge cache          POST   /zones/{id}/purge_cache
Lists / Bulk redir   *      /accounts/{id}/rules/lists
WAF (legacy)         *      /zones/{id}/firewall/rules ; /filters
Rate limiting        *      via ruleset phase http_ratelimit
API Shield           *      /zones/{id}/api_gateway/...
Page Shield          *      /zones/{id}/page_shield/...
Turnstile            *      /accounts/{id}/challenges/widgets
Load Balancing       *      /accounts/{id}/load_balancers/{pools,monitors} ; /zones/{id}/load_balancers
Waiting Room         *      /zones/{id}/waiting_rooms
Spectrum             *      /zones/{id}/spectrum/apps
Magic networking     *      /accounts/{id}/magic/... ; /accounts/{id}/addressing/...
Zero Trust Access    *      /accounts/{id}/access/{apps,policies,identity_providers,service_tokens,groups}
Zero Trust Gateway   *      /accounts/{id}/gateway/{rules,lists,locations,proxy_endpoints}
Tunnels              *      /accounts/{id}/cfd_tunnel ; /accounts/{id}/teamnet/routes
Workers              *      /accounts/{id}/workers/scripts ; /zones/{id}/workers/routes
KV/R2/D1/Queues      *      /accounts/{id}/storage/kv ; /r2/buckets ; /d1/database ; /queues
Pages/Stream/Images  *      /accounts/{id}/pages/projects ; /stream ; /images/v1
Logpush              *      /accounts/{id}/logpush/jobs ; /zones/{id}/logpush/jobs
Analytics (GraphQL)  POST   /graphql
Audit logs           GET    /accounts/{id}/audit_logs
```

> **Reminder:** endpoint shapes evolve; before automating, confirm against the live OpenAPI schema
> (`https://github.com/cloudflare/api-schemas` / developers.cloudflare.com/api) and the account's actual
> entitlements. This document is the *map*; the live API is the *territory*.
