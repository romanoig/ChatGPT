# Cloudflare MCP ("NFR — all account") setup

This wires a Cloudflare MCP server named **`cloudflare-NFR`** into the project's `.mcp.json`,
authenticated via the **all-account** API token. The token value is **never** stored in the repo —
it is read from an environment variable at runtime.

> ⚠️ **This is an all-account token.** It grants full access to the Cloudflare account
> (`39300af2f5e12fb8efac6bc8881a992e`). Treat every operation as production-impacting and follow the
> safe-change protocol in `CLOUDFLARE_ENTERPRISE_CAPABILITIES.md` §20. Prefer a scoped, least-privilege
> token for day-to-day automation.

## What's committed
- `.mcp.json` — declares the `cloudflare-NFR` server and maps two env vars. **No secrets.**

## What you must provide (outside the repo)

### 1. Set the environment variables (secret store, NOT in chat or git)
| Variable | Value |
|---|---|
| `CLOUDFLARE_NFR_API_TOKEN` | the all-account API token (`cfat_…`) |
| `CLOUDFLARE_NFR_ACCOUNT_ID` | `39300af2f5e12fb8efac6bc8881a992e` |

For Claude Code on the web, add these in the **environment's variables/secrets** settings
(https://code.claude.com/docs/en/claude-code-on-the-web), not in a committed file.

> R2 S3 credentials (Access Key ID / Secret Access Key, endpoint
> `https://39300af2f5e12fb8efac6bc8881a992e.r2.cloudflarestorage.com`) are **not** needed for the
> Cloudflare API MCP. If you wire R2 separately, store them the same way (env/secret store), e.g.
> `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`.

### 2. Choose the MCP server package
Replace `REPLACE_WITH_CLOUDFLARE_MCP_PACKAGE` in `.mcp.json` with the local/self-hosted Cloudflare MCP
server you intend to run (the one that authenticates via `CLOUDFLARE_API_TOKEN`). The first-party
Cloudflare remote MCP servers use OAuth instead and would be added as `"url": "https://…mcp.cloudflare.com/sse"`
entries rather than a token-based `command` — pick the model that matches your token-based requirement.

### 3. Open egress
This server calls `api.cloudflare.com` (and R2 calls hit `*.cloudflarestorage.com`). Both are currently
**blocked** by the environment's network policy. Add them to the **egress allowlist** or the MCP server
will fail with `403 host_not_allowed`.

## Verify the token (once egress is open)
```
curl -X GET "https://api.cloudflare.com/client/v4/accounts/39300af2f5e12fb8efac6bc8881a992e/tokens/verify" \
     -H "Authorization: Bearer $CLOUDFLARE_NFR_API_TOKEN"
```
Expect `"status": "active"` in the result.

## Checklist
- [ ] Egress allowlist includes `api.cloudflare.com` (+ `*.cloudflarestorage.com` if using R2)
- [ ] `CLOUDFLARE_NFR_API_TOKEN` set in env/secret store (not in git)
- [ ] `CLOUDFLARE_NFR_ACCOUNT_ID` set
- [ ] `.mcp.json` package field replaced with the real server
- [ ] Token verified via `/tokens/verify`
- [ ] (Recommended) Replace all-account token with a least-privilege scoped token
