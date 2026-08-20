#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

ENV_FILE=".env.production"
COMPOSE_FILE="docker-compose.prod.yml"
BUILDER_HOST="webstudio.agnsbroadband.in"
VPS_IPV4="${VPS_IPV4:-103.174.126.148}"
SITE_FILE="/etc/nginx/sites-available/agns-webstudio"
SITE_LINK="/etc/nginx/sites-enabled/agns-webstudio"
ACME_ROOT="/var/www/certbot"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v nginx >/dev/null 2>&1 ||
  fail "Host Nginx is not installed."

command -v certbot >/dev/null 2>&1 ||
  fail "Certbot is not installed."

[[ -f "${ENV_FILE}" ]] ||
  fail "${ENV_FILE} is missing."

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

compose() {
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    "$@"
}

curl -fsS http://127.0.0.1:3000/health \
  | grep -qi '^ok$' \
  || fail "Builder is not healthy on 127.0.0.1:3000."

builder_ip="$(
  getent ahostsv4 "${BUILDER_HOST}" \
    | awk 'NR == 1 {print $1}'
)"

[[ "${builder_ip}" == "${VPS_IPV4}" ]] || {
  echo "Current ${BUILDER_HOST} resolution: ${builder_ip:-<none>}" >&2
  echo "Expected: ${VPS_IPV4}" >&2
  echo >&2
  echo "Fix DNS before requesting SSL." >&2
  echo "Valid choices:" >&2
  echo "  A     webstudio  ${VPS_IPV4}" >&2
  echo "or, if ServerByt keeps mangling the A record:" >&2
  echo "  CNAME webstudio  srv.vinux.in." >&2
  exit 1
}

mapfile -t project_ids < <(
  compose exec \
    -T \
    -e "PGPASSWORD=${POSTGRES_PASSWORD}" \
    db \
    psql \
      -h 127.0.0.1 \
      -U postgres \
      -d webstudio \
      -tA \
      -c 'SELECT id FROM "Project" ORDER BY id;' \
    | sed '/^[[:space:]]*$/d'
)

[[ "${#project_ids[@]}" -gt 0 ]] ||
  fail "No Webstudio projects were found after state import."

domains=("${BUILDER_HOST}")

for project_id in "${project_ids[@]}"; do
  domains+=("p-${project_id}.webstudio.agnsbroadband.in")
done

echo "Domains that will be configured:"
printf '  %s\n' "${domains[@]}"

for domain in "${domains[@]}"; do
  resolved="$(
    getent ahostsv4 "${domain}" \
      | awk 'NR == 1 {print $1}'
  )"

  [[ "${resolved}" == "${VPS_IPV4}" ]] || {
    echo "ERROR: ${domain} resolves to ${resolved:-<none>}, expected ${VPS_IPV4}." >&2
    exit 1
  }
done

sudo mkdir -p "${ACME_ROOT}"

server_names="$(
  printf '%s ' "${domains[@]}"
)"

tmp="$(mktemp -t agns-webstudio-nginx.XXXXXX)"
trap 'rm -f "${tmp}"' EXIT

cat > "${tmp}" <<NGINX
map \$http_upgrade \$agns_connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;

    server_name ${server_names};

    client_max_body_size 100m;

    location ^~ /.well-known/acme-challenge/ {
        root ${ACME_ROOT};
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$agns_connection_upgrade;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}
NGINX

sudo cp "${tmp}" "${SITE_FILE}"
sudo ln -sfn "${SITE_FILE}" "${SITE_LINK}"

sudo nginx -t
sudo systemctl reload nginx

certbot_args=(
  sudo certbot
  --nginx
  --non-interactive
  --agree-tos
  --redirect
  --keep-until-expiring
  --email "${ACME_EMAIL}"
)

for domain in "${domains[@]}"; do
  certbot_args+=(
    -d "${domain}"
  )
done

"${certbot_args[@]}"

sudo nginx -t
sudo systemctl reload nginx

curl -fsS "https://${BUILDER_HOST}/health" \
  | grep -qi '^ok$' \
  || fail "Public Builder HTTPS health check failed."

echo
echo "PASS: host Nginx + Certbot configured."
echo "Builder:"
echo "  https://${BUILDER_HOST}"
echo
echo "Projects:"
for project_id in "${project_ids[@]}"; do
  echo "  https://p-${project_id}.webstudio.agnsbroadband.in/"
done
