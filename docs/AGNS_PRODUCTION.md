# AGNS Webstudio production deployment

This production branch is for the **Webstudio Builder only**.

- Builder: `https://webstudio.agnsbroadband.in`
- Project editor/canvas hosts: `https://p-<project-id>.webstudio.agnsbroadband.in`
- Public website: `https://agnsbroadband.in` is intentionally **not** served by this stack.
- Static exports are generated separately and can be uploaded to any static host.

## Security first

Do not reuse secrets that have appeared in chat, terminal logs, screenshots, old `.env` files, or support tickets.

Before production, rotate/generate fresh values for:

- PostgreSQL password
- PostgREST JWT secret
- Webstudio `AUTH_SECRET`
- Webstudio CLI OAuth secret
- MinIO password/S3 secret
- any previously exposed Google OAuth client secret

`./scripts/prod/generate-env.sh` generates fresh infrastructure secrets and asks for the new Google OAuth credentials without printing the secret.

## 1. DNS

Keep the public AGNS site pointed at its separate static hosting IP.

Add only these records for the Builder VPS:

| Type | Name | Value |
|---|---|---|
| A | `webstudio.agnsbroadband.in` | `<VPS IPv4>` |
| A | `*.webstudio.agnsbroadband.in` | `<VPS IPv4>` |

If the VPS has a stable public IPv6 address, add matching AAAA records. Otherwise do not add AAAA records for these two names.

The existing `agnsbroadband.in` A/AAAA records and the general `*.agnsbroadband.in` record can remain on the static host. The explicit `webstudio` and `*.webstudio` records take care of the Builder and project canvases.

## 2. Google OAuth

Create a new Google OAuth 2.0 **Web application** credential or rotate the exposed client secret.

Configure:

- Authorized JavaScript origin: `https://webstudio.agnsbroadband.in`
- Authorized redirect URI: `https://webstudio.agnsbroadband.in/auth/google/callback`

For a private Builder, keep the OAuth consent screen restricted to your allowed Google/Workspace users. `DEV_LOGIN` is disabled in the production compose file.

If you migrate the existing local database, sign in with the same email used by the local Webstudio account (`admin@agnsbroadband.in`) so project ownership remains consistent.

## 3. Prepare the production environment

On the VPS after cloning the `prod` branch:

```bash
./scripts/prod/generate-env.sh
./scripts/prod/check.sh
```

The real file is `.env.production`; it is ignored by Git and should stay mode `0600`.

The first production bootstrap also resolves mutable image tags to immutable image digests and writes those digests into `.env.production`.

## 4. Migrate the existing local AGNS Webstudio project

On your **local Mac**, from this repository:

```bash
./scripts/prod/export-local-state.sh
```

This creates a bundle under `prod-state/` containing:

- PostgreSQL Webstudio project data
- MinIO assets
- Builder uploads

No `.env` secrets are included.

Copy the generated bundle to the VPS, for example:

```bash
scp prod-state/agns-webstudio-state-*.tar.gz user@VPS:/home/user/
```

Then on the VPS:

```bash
./scripts/prod/bootstrap-vps.sh \
  --state /home/user/agns-webstudio-state-YYYYMMDD-HHMMSS.tar.gz
```

The import refuses to overwrite a production database that already contains projects.

## 5. Fresh deployment without local state

If you intentionally want an empty Builder instead:

```bash
./scripts/prod/bootstrap-vps.sh
```

## 6. Firewall

The VPS must allow inbound TCP:

- 22 for SSH
- 80 for ACME/HTTP redirect
- 443 for HTTPS

Database, PostgREST, MinIO and Builder port 3000 are not published directly to the Internet.

## 7. TLS architecture

Caddy terminates HTTPS.

The fixed Builder hostname receives ordinary automatic HTTPS. Project canvas hostnames are created dynamically by Webstudio, so Caddy uses restricted On-Demand TLS for names matching only:

```text
p-<uuid>.webstudio.agnsbroadband.in
```

The internal `tls-ask` service rejects certificate requests for other names. This avoids requiring a DNS-provider API for a wildcard certificate while still supporting dynamic project subdomains.

## 8. Operations

Status:

```bash
./scripts/prod/status.sh
```

Logs:

```bash
./scripts/prod/logs.sh
```

Backup:

```bash
./scripts/prod/backup.sh
```

## 9. Static export

Webstudio documents the CLI as the export path when the Builder itself is self-hosted.

One-time link:

```bash
./scripts/prod/export-static.sh link
```

Create a Build-enabled Share link from the production Builder and paste it when the CLI prompts.

For later exports:

```bash
./scripts/prod/export-static.sh all
```

That runs:

```text
webstudio sync
webstudio build --template ssg
```

inside a Node 22 container. The workspace is kept under `exports/agns-static/` and is ignored by Git. Upload the generated static site to the separate hosting service that serves `agnsbroadband.in`.

Static export has Webstudio's documented limitations, including no dynamic pages, webhook forms, redirects/statuses, image optimization, robots.txt, or sitemap.xml.

## 10. Production architecture

```text
Internet
   |
   +-- agnsbroadband.in --------------------> separate static host
   |
   +-- webstudio.agnsbroadband.in ----------> AGNS Builder VPS
   |                                             |
   |                                             +-- Caddy :80/:443
   |                                             +-- Webstudio Builder
   |                                             +-- PostgreSQL
   |                                             +-- PostgREST
   |                                             +-- MinIO
   |
   +-- p-*.webstudio.agnsbroadband.in ------> same Builder VPS
                                                 |
                                                 +-- Caddy On-Demand TLS
                                                 +-- Webstudio project editor/canvas
```

## Production checks before declaring the VPS ready

- DNS exact Builder record resolves to the VPS.
- DNS `*.webstudio` wildcard resolves to the VPS.
- `https://webstudio.agnsbroadband.in/health` returns `OK`.
- Google login succeeds.
- Existing AGNS project opens.
- A project canvas hostname receives valid public TLS.
- `./scripts/prod/backup.sh` succeeds.
- Static CLI link/sync/build succeeds before moving the public root domain.
