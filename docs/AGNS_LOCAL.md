# AGNS XSTREAM FIBERNET — Local Webstudio

The local development environment uses trusted HTTPS and wildcard
project hosts so the self-hosted Webstudio canvas behaves like a
normal Webstudio deployment.

## URLs

- Builder: `https://webstudio.localhost`
- Static reference: `http://agns.localhost:4173`

## Commands

```bash
./scripts/agns-local.sh start
./scripts/agns-local.sh build
./scripts/agns-local.sh status
./scripts/agns-local.sh open
./scripts/agns-local.sh logs
```

## Editable site

`site/agns/webstudio-import.html` is the initial Tailwind HTML import
source.

Webstudio converts the supported Tailwind markup to native editable
Builder structure and styles.

After the initial import, normal content/layout changes should be made
inside Webstudio.

`site/agns/index.html` remains the static visual reference/fallback.

## Local TLS

`mkcert` creates trusted local certificates under:

```text
.local/certs/
```

Certificates and `.env` are ignored by Git.

`docker-compose.local.yml` provides the local Builder domain and an
Nginx HTTPS/wildcard proxy.

## Logo

Do not recreate the AGNS logo.

When the original logo is available, place it at:

```text
site/agns/assets/agns-logo.webp
```

Then upload/use that original asset from Webstudio's Assets panel.

## Pricing

The 5 Mbps, 15 Mbps, and 200 Mbps prices are legacy values and remain
explicitly marked for confirmation before installation.
