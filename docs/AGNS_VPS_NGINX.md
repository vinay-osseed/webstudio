# AGNS Webstudio VPS Edge

This VPS already uses host Nginx for `srv.vinux.in` and
`uptime.vinux.in`. Webstudio therefore does not run a second edge proxy
on ports 80/443.

Production routing is:

- host Nginx + Certbot: ports 80/443
- Webstudio Builder: `127.0.0.1:3000`
- PostgreSQL/PostgREST/MinIO: Docker network only

Caddy is retained behind the optional Compose profile `caddy-edge` and
is disabled during normal deployment.

## DNS

Required:

```text
webstudio.agnsbroadband.in                 -> VPS
*.webstudio.agnsbroadband.in               -> VPS
```

If the DNS provider cannot create the Builder A record correctly, a
valid CNAME to another hostname on the same VPS is acceptable, for
example:

```text
webstudio CNAME srv.vinux.in.
```

Never use an IP address as a CNAME target.

## Deploy

```bash
./scripts/prod/bootstrap-vps.sh \
  --state agns-webstudio-state-YYYYMMDD-HHMMSS.tar.gz
```

Then, after DNS is correct:

```bash
./scripts/prod/configure-host-nginx.sh
```

The Nginx helper discovers all current Webstudio project IDs from
PostgreSQL and obtains certificates for the Builder and each project
hostname.
