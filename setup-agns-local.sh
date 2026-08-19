#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "${ROOT}" ]]; then
  echo "ERROR: Run this from inside the cloned webstudio repository." >&2
  exit 1
fi

cd "${ROOT}"

BUILDER_URL="http://webstudio.localhost:3000"
PREVIEW_URL="http://agns.localhost:4173"
PREVIEW_CONTAINER="agns-local-preview"

log() {
  printf '\n============================================================\n'
  printf '%s\n' "$1"
  printf '============================================================\n'
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

random_hex() {
  openssl rand -hex "$1"
}

set_env() {
  local key="$1"
  local value="$2"

  python3 - "${key}" "${value}" <<'PY'
from pathlib import Path
import sys

path = Path(".env")
key = sys.argv[1]
value = sys.argv[2]

lines = path.read_text().splitlines()
result = []
found = False

for line in lines:
    if line.startswith(f"{key}="):
        result.append(f"{key}={value}")
        found = True
    elif line.startswith(f"# {key}="):
        result.append(f"{key}={value}")
        found = True
    else:
        result.append(line)

if not found:
    result.append(f"{key}={value}")

path.write_text("\n".join(result) + "\n")
PY
}

get_env() {
  local key="$1"

  sed -n "s/^${key}=//p" .env | tail -1
}

ensure_secret() {
  local key="$1"
  local bytes="$2"
  local current

  current="$(get_env "${key}")"

  case "${current}" in
    ""|change-me|change-me-*|*change-me*)
      set_env \
        "${key}" \
        "$(random_hex "${bytes}")"
      ;;
  esac
}

log "1. Preflight"

for command in \
  git \
  docker \
  openssl \
  python3 \
  curl
do
  command -v "${command}" >/dev/null 2>&1 ||
    fail "Missing required command: ${command}"
done

docker info >/dev/null 2>&1 ||
  fail "Docker is not running. Start Docker Desktop first."

[[ -f docker-compose.yml ]] ||
  fail "docker-compose.yml is missing."

[[ -f .env.example ]] ||
  fail ".env.example is missing."

echo "PASS: repository"
echo "PASS: Docker"
echo "PASS: required tools"

log "2. Create local environment"

if [[ ! -f .env ]]; then
  cp \
    .env.example \
    .env

  echo "Created .env from .env.example"
else
  cp \
    .env \
    ".env.backup-$(date +%Y%m%d-%H%M%S)"

  echo "Existing .env preserved and backed up."
fi

ensure_secret \
  POSTGRES_PASSWORD \
  24

ensure_secret \
  PGRST_JWT_SECRET \
  64

ensure_secret \
  AUTH_SECRET \
  32

ensure_secret \
  AUTH_WS_CLIENT_SECRET \
  32

ensure_secret \
  TRPC_SERVER_API_TOKEN \
  32

ensure_secret \
  MINIO_ROOT_PASSWORD \
  24

set_env \
  AUTH_WS_CLIENT_ID \
  "agns-local"

set_env \
  DEV_LOGIN \
  "true"

set_env \
  DEV_LOGIN_EMAIL \
  "admin@agnsbroadband.in"

set_env \
  DEPLOYMENT_URL \
  "${BUILDER_URL}"

set_env \
  FEATURES \
  "*"

set_env \
  USER_PLAN \
  "Pro"

set_env \
  MAX_ASSETS_PER_PROJECT \
  "50"

set_env \
  MINIO_ROOT_USER \
  "minioadmin"

MINIO_PASSWORD="$(
  get_env MINIO_ROOT_PASSWORD
)"

set_env \
  S3_ENDPOINT \
  "http://minio:9000"

set_env \
  S3_REGION \
  "us-east-1"

set_env \
  S3_ACCESS_KEY_ID \
  "minioadmin"

set_env \
  S3_SECRET_ACCESS_KEY \
  "${MINIO_PASSWORD}"

set_env \
  S3_BUCKET \
  "webstudio-assets"

set_env \
  SELF_HOSTED_PUBLISHER_URL \
  "http://publisher:4000"

set_env \
  PUBLISHER_HOST \
  "sites.localhost"

echo "PASS: local Webstudio environment configured"

log "3. Protect local/generated files"

touch .gitignore

for entry in \
  ".env" \
  ".env.backup-*" \
  ".local/" \
  ".DS_Store"
do
  if ! grep -Fxq "${entry}" .gitignore; then
    echo "${entry}" >> .gitignore
  fi
done

echo "PASS: local secrets ignored by Git"

log "4. Create AGNS website source"

mkdir -p \
  site/agns/assets \
  scripts

cat > site/agns/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">

  <meta
    name="viewport"
    content="width=device-width, initial-scale=1"
  >

  <title>AGNS XSTREAM FIBERNET | Sawantwadi Broadband</title>

  <meta
    name="description"
    content="AGNS XSTREAM FIBERNET - fiber broadband, business internet and local support in Sawantwadi."
  >

  <style>
    :root {
      --yellow: #f8d020;
      --black: #080808;
      --soft-black: #151515;
      --white: #ffffff;
      --surface: #f6f6f3;
      --muted: #696969;
      --border: #dedede;
      --max: 1180px;
    }

    * {
      box-sizing: border-box;
    }

    html {
      scroll-behavior: smooth;
    }

    body {
      margin: 0;
      background: var(--white);
      color: var(--black);
      font-family:
        Inter,
        ui-sans-serif,
        system-ui,
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        sans-serif;
    }

    a {
      color: inherit;
      text-decoration: none;
    }

    img {
      display: block;
      max-width: 100%;
    }

    .container {
      width: min(var(--max), calc(100% - 40px));
      margin-inline: auto;
    }

    .announcement {
      padding: 10px 20px;
      background: var(--yellow);
      text-align: center;
      font-size: 14px;
      font-weight: 750;
    }

    .announcement a {
      margin-left: 8px;
      text-decoration: underline;
      text-underline-offset: 4px;
    }

    .header {
      background: #fff;
      border-bottom: 1px solid var(--border);
    }

    .header-inner {
      min-height: 82px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 30px;
    }

    .logo {
      display: flex;
      align-items: center;
      min-width: 190px;
    }

    .logo img {
      width: auto;
      height: 56px;
    }

    .logo-fallback {
      display: none;
      font-weight: 950;
      letter-spacing: -1px;
    }

    .nav {
      display: flex;
      gap: 28px;
      font-size: 14px;
      font-weight: 650;
      color: #555;
    }

    .nav a:hover {
      color: #000;
    }

    .button {
      display: inline-flex;
      min-height: 48px;
      align-items: center;
      justify-content: center;
      padding: 0 24px;
      border-radius: 999px;
      font-weight: 800;
      transition:
        transform .15s ease,
        background .15s ease;
    }

    .button:hover {
      transform: translateY(-1px);
    }

    .button-black {
      background: #000;
      color: #fff;
    }

    .button-yellow {
      background: var(--yellow);
      color: #000;
    }

    .button-outline-light {
      border: 1px solid #555;
      color: #fff;
    }

    .hero {
      background: #050505;
      color: #fff;
      overflow: hidden;
    }

    .hero-grid {
      display: grid;
      grid-template-columns: 1.08fr .92fr;
      gap: 70px;
      align-items: center;
      padding-block: 94px;
    }

    .eyebrow {
      display: inline-flex;
      padding: 9px 14px;
      border-radius: 999px;
      background: var(--yellow);
      color: #000;
      font-size: 12px;
      font-weight: 900;
      letter-spacing: .12em;
      text-transform: uppercase;
    }

    .hero h1 {
      max-width: 780px;
      margin: 24px 0 0;
      font-size: clamp(48px, 6.3vw, 78px);
      line-height: .99;
      letter-spacing: -.055em;
    }

    .yellow {
      color: var(--yellow);
    }

    .hero-copy {
      max-width: 650px;
      margin-top: 26px;
      color: #c9c9c9;
      font-size: 19px;
      line-height: 1.65;
    }

    .hero-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 34px;
    }

    .hero-card {
      padding: 34px;
      border: 1px solid #252525;
      border-radius: 32px;
      background: #101010;
    }

    .hero-card-top {
      display: flex;
      justify-content: space-between;
      margin-bottom: 36px;
      color: #888;
      font-size: 13px;
      font-weight: 800;
      letter-spacing: .13em;
    }

    .status-dot {
      width: 12px;
      height: 12px;
      border-radius: 50%;
      background: var(--yellow);
    }

    .hero-feature {
      padding: 30px;
      border-radius: 25px;
      background: var(--yellow);
      color: #000;
    }

    .hero-feature small {
      font-weight: 900;
      letter-spacing: .12em;
    }

    .hero-feature strong {
      display: block;
      margin-top: 10px;
      font-size: 38px;
      letter-spacing: -.04em;
    }

    .hero-small-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 14px;
      margin-top: 14px;
    }

    .hero-small {
      padding: 24px;
      border: 1px solid #2a2a2a;
      border-radius: 24px;
    }

    .hero-small strong {
      display: block;
      font-size: 24px;
    }

    .hero-small span {
      display: block;
      margin-top: 7px;
      color: #999;
      font-size: 14px;
    }

    .service-strip {
      background: var(--surface);
      border-bottom: 1px solid var(--border);
    }

    .service-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      padding-block: 23px;
      text-align: center;
    }

    .service-item {
      padding: 12px;
    }

    .service-item strong {
      display: block;
      font-size: 15px;
    }

    .service-item span {
      display: block;
      margin-top: 4px;
      color: var(--muted);
      font-size: 13px;
    }

    .section {
      padding-block: 94px;
    }

    .surface {
      background: var(--surface);
    }

    .dark {
      background: #050505;
      color: #fff;
    }

    .section-kicker {
      color: #707070;
      font-size: 13px;
      font-weight: 900;
      letter-spacing: .14em;
      text-transform: uppercase;
    }

    .dark .section-kicker {
      color: var(--yellow);
    }

    .section-title {
      max-width: 720px;
      margin: 12px 0 0;
      font-size: clamp(38px, 5vw, 58px);
      line-height: 1.03;
      letter-spacing: -.045em;
    }

    .section-copy {
      max-width: 700px;
      margin: 20px 0 0;
      color: #646464;
      font-size: 18px;
      line-height: 1.7;
    }

    .dark .section-copy {
      color: #b5b5b5;
    }

    .plans {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 20px;
      margin-top: 46px;
    }

    .plan {
      padding: 30px;
      border: 1px solid var(--border);
      border-radius: 28px;
      background: #fff;
    }

    .plan.featured {
      color: #fff;
      background: #050505;
      border-color: #050505;
      box-shadow: 0 0 0 4px var(--yellow);
    }

    .plan-name {
      font-size: 13px;
      font-weight: 900;
      letter-spacing: .13em;
      text-transform: uppercase;
      color: #6c6c6c;
    }

    .featured .plan-name {
      color: var(--yellow);
    }

    .speed {
      margin-top: 20px;
      font-size: 48px;
      font-weight: 950;
      letter-spacing: -.045em;
    }

    .price {
      margin-top: 24px;
      font-size: 32px;
      font-weight: 950;
    }

    .price span {
      color: #777;
      font-size: 15px;
      font-weight: 500;
    }

    .featured .price span {
      color: #aaa;
    }

    .plan .button {
      width: 100%;
      margin-top: 28px;
      border: 1px solid #111;
    }

    .featured .button {
      border: 0;
    }

    .notice {
      margin-top: 24px;
      color: #686868;
      font-size: 13px;
    }

    .coverage {
      padding-block: 65px;
      background: var(--yellow);
    }

    .coverage-inner {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 50px;
    }

    .coverage h2 {
      max-width: 730px;
      margin: 10px 0 0;
      font-size: clamp(38px, 5vw, 58px);
      letter-spacing: -.045em;
      line-height: 1.03;
    }

    .coverage p {
      max-width: 620px;
      margin: 17px 0 0;
      font-size: 18px;
      line-height: 1.6;
    }

    .cards {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 18px;
      margin-top: 46px;
    }

    .card {
      padding: 28px;
      background: #fff;
      border-radius: 26px;
    }

    .number {
      display: inline-flex;
      width: 45px;
      height: 45px;
      align-items: center;
      justify-content: center;
      border-radius: 15px;
      background: var(--yellow);
      font-weight: 950;
    }

    .card h3 {
      margin: 22px 0 0;
      font-size: 20px;
    }

    .card p {
      margin: 11px 0 0;
      color: #666;
      line-height: 1.65;
    }

    .steps {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 16px;
      margin-top: 44px;
    }

    .step {
      padding: 26px;
      border: 1px solid var(--border);
      border-radius: 25px;
    }

    .step-index {
      color: #a37e00;
      font-weight: 900;
      font-size: 13px;
    }

    .step h3 {
      margin: 17px 0 0;
    }

    .step p {
      color: #666;
      line-height: 1.55;
    }

    .business-grid,
    .support-grid,
    .contact-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 65px;
      align-items: center;
    }

    .business-cards {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 14px;
    }

    .business-card {
      padding: 26px;
      border: 1px solid #2d2d2d;
      border-radius: 24px;
    }

    .business-card:last-child {
      grid-column: 1 / -1;
    }

    .business-card p {
      color: #999;
      line-height: 1.6;
    }

    details {
      padding: 20px;
      border: 1px solid var(--border);
      border-radius: 18px;
      background: #fff;
    }

    details + details {
      margin-top: 12px;
    }

    summary {
      cursor: pointer;
      font-weight: 800;
    }

    details p {
      color: #666;
      line-height: 1.6;
    }

    .contact-box {
      padding: 50px;
      border-radius: 32px;
      background: var(--yellow);
    }

    .contact-details {
      padding: 30px;
      border-radius: 25px;
      background: #fff;
      line-height: 1.75;
    }

    .contact-details a {
      text-decoration: underline;
      text-underline-offset: 3px;
    }

    .final-cta {
      padding-block: 62px;
      background: #050505;
      color: #fff;
    }

    .final-inner {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 40px;
    }

    .final-inner h2 {
      margin: 0;
      font-size: 38px;
      letter-spacing: -.035em;
    }

    .final-inner p {
      color: #999;
    }

    footer {
      border-top: 1px solid var(--border);
      background: #fff;
    }

    .footer-inner {
      padding-block: 38px;
    }

    .footer-top,
    .footer-bottom {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 30px;
    }

    .footer-top {
      padding-bottom: 28px;
    }

    .footer-bottom {
      padding-top: 22px;
      border-top: 1px solid var(--border);
      color: #6a6a6a;
      font-size: 13px;
    }

    .footer-nav {
      display: flex;
      flex-wrap: wrap;
      gap: 22px;
      color: #555;
      font-size: 14px;
    }

    @media (max-width: 900px) {
      .nav {
        display: none;
      }

      .hero-grid,
      .business-grid,
      .support-grid,
      .contact-grid {
        grid-template-columns: 1fr;
      }

      .service-grid,
      .cards,
      .steps {
        grid-template-columns: 1fr 1fr;
      }

      .plans {
        grid-template-columns: 1fr;
      }

      .coverage-inner,
      .final-inner {
        align-items: flex-start;
        flex-direction: column;
      }
    }

    @media (max-width: 560px) {
      .container {
        width: min(100% - 28px, var(--max));
      }

      .header-inner {
        min-height: 72px;
      }

      .logo img {
        height: 44px;
      }

      .header .button {
        min-height: 42px;
        padding-inline: 16px;
        font-size: 13px;
      }

      .hero-grid {
        padding-block: 65px;
      }

      .section {
        padding-block: 70px;
      }

      .service-grid,
      .cards,
      .steps,
      .business-cards {
        grid-template-columns: 1fr;
      }

      .business-card:last-child {
        grid-column: auto;
      }

      .contact-box {
        padding: 25px;
      }

      .footer-top,
      .footer-bottom {
        align-items: flex-start;
        flex-direction: column;
      }
    }
  </style>
</head>

<body>

  <div class="announcement">
    New broadband connection in Sawantwadi?

    <a href="https://wa.me/919096781147?text=Hi%20AGNS%20XSTREAM%20FIBERNET%2C%20I%20want%20to%20check%20broadband%20availability.">
      Check availability on WhatsApp
    </a>
  </div>

  <header class="header">
    <div class="container header-inner">

      <a href="#home" class="logo">
        <img
          src="assets/agns-logo.webp"
          alt="AGNS XSTREAM FIBERNET"
          onerror="this.style.display='none';this.nextElementSibling.style.display='block';"
        >

        <span class="logo-fallback">
          AGNS XSTREAM FIBERNET
        </span>
      </a>

      <nav class="nav">
        <a href="#plans">Plans</a>
        <a href="#business">Business</a>
        <a href="#coverage">Coverage</a>
        <a href="#support">Support</a>
        <a href="#contact">Contact</a>
      </nav>

      <a
        class="button button-black"
        href="https://wa.me/919096781147?text=Hi%20AGNS%20XSTREAM%20FIBERNET%2C%20I%20want%20a%20new%20broadband%20connection."
      >
        Get Connection
      </a>

    </div>
  </header>

  <main id="home">

    <section class="hero">
      <div class="container hero-grid">

        <div>
          <div class="eyebrow">
            Fiber broadband in Sawantwadi
          </div>

          <h1>
            Fiber internet that keeps
            <span class="yellow">Sawantwadi moving.</span>
          </h1>

          <p class="hero-copy">
            AGNS XSTREAM FIBERNET brings straightforward broadband
            for homes and businesses, backed by a local team you can
            reach directly.
          </p>

          <div class="hero-actions">

            <a
              class="button button-yellow"
              href="https://wa.me/919096781147?text=Hi%20AGNS%20XSTREAM%20FIBERNET%2C%20please%20check%20availability%20at%20my%20location."
            >
              Check Availability
            </a>

            <a
              class="button button-outline-light"
              href="tel:+917276938332"
            >
              Call 7276938332
            </a>

          </div>
        </div>

        <div class="hero-card">

          <div class="hero-card-top">
            <span>AGNS XSTREAM</span>
            <span class="status-dot"></span>
          </div>

          <div class="hero-feature">
            <small>HOME FIBER</small>
            <strong>Simple plans.</strong>
            <div>Local assistance.</div>
          </div>

          <div class="hero-small-grid">

            <div class="hero-small">
              <strong>FTTH</strong>
              <span>Fiber broadband</span>
            </div>

            <div class="hero-small">
              <strong>Local</strong>
              <span>Sawantwadi office</span>
            </div>

          </div>

        </div>

      </div>
    </section>

    <section class="service-strip">
      <div class="container service-grid">

        <div class="service-item">
          <strong>FTTH Broadband</strong>
          <span>Home connectivity</span>
        </div>

        <div class="service-item">
          <strong>Business Internet</strong>
          <span>For growing teams</span>
        </div>

        <div class="service-item">
          <strong>Leased Lines</strong>
          <span>Dedicated connectivity</span>
        </div>

        <div class="service-item">
          <strong>Local Support</strong>
          <span>Talk to AGNS directly</span>
        </div>

      </div>
    </section>

    <section id="plans" class="section">
      <div class="container">

        <div class="section-kicker">
          Broadband plans
        </div>

        <h2 class="section-title">
          Choose the speed that works for you.
        </h2>

        <p class="section-copy">
          Plan information from the existing AGNS website.
          Contact AGNS to confirm current pricing and availability
          at your address.
        </p>

        <div class="plans">

          <article class="plan">
            <div class="plan-name">Basic</div>
            <div class="speed">5 Mbps</div>

            <div class="price">
              ₹600
              <span>/ month</span>
            </div>

            <a
              class="button"
              href="https://wa.me/919096781147?text=Hi%20AGNS%2C%20I%20am%20interested%20in%20the%205%20Mbps%20plan."
            >
              Ask About This Plan
            </a>
          </article>

          <article class="plan featured">
            <div class="plan-name">
              Everyday · Popular
            </div>

            <div class="speed">
              15 Mbps
            </div>

            <div class="price">
              ₹800
              <span>/ month</span>
            </div>

            <a
              class="button button-yellow"
              href="https://wa.me/919096781147?text=Hi%20AGNS%2C%20I%20am%20interested%20in%20the%2015%20Mbps%20plan."
            >
              Choose This Plan
            </a>
          </article>

          <article class="plan">
            <div class="plan-name">Xtreme</div>
            <div class="speed">200 Mbps</div>

            <div class="price">
              ₹2,500
              <span>/ month</span>
            </div>

            <a
              class="button"
              href="https://wa.me/919096781147?text=Hi%20AGNS%2C%20I%20am%20interested%20in%20the%20200%20Mbps%20plan."
            >
              Ask About This Plan
            </a>
          </article>

        </div>

        <p class="notice">
          Please confirm current pricing, plan details and availability
          with AGNS before installation.
        </p>

      </div>
    </section>

    <section id="coverage" class="coverage">
      <div class="container coverage-inner">

        <div>
          <div class="section-kicker">
            Check your area
          </div>

          <h2>
            Is AGNS available at your address?
          </h2>

          <p>
            Send your locality or pincode on WhatsApp and the AGNS
            team can confirm service availability.
          </p>
        </div>

        <a
          class="button button-black"
          href="https://wa.me/919096781147?text=Hi%20AGNS%20XSTREAM%20FIBERNET%2C%20please%20check%20broadband%20availability.%0A%0ALocality%3A%20%0APincode%3A%20"
        >
          Check on WhatsApp
        </a>

      </div>
    </section>

    <section class="section surface">
      <div class="container">

        <div class="section-kicker">
          Why AGNS
        </div>

        <h2 class="section-title">
          Internet without unnecessary complexity.
        </h2>

        <div class="cards">

          <article class="card">
            <div class="number">01</div>
            <h3>Fiber connectivity</h3>
            <p>
              FTTH broadband for homes and everyday internet use.
            </p>
          </article>

          <article class="card">
            <div class="number">02</div>
            <h3>Local team</h3>
            <p>
              Contact the AGNS office and support team directly
              in Sawantwadi.
            </p>
          </article>

          <article class="card">
            <div class="number">03</div>
            <h3>Business options</h3>
            <p>
              Business internet and leased-line connectivity when
              you need more.
            </p>
          </article>

          <article class="card">
            <div class="number">04</div>
            <h3>Simple contact</h3>
            <p>
              Call, email or WhatsApp without navigating a
              complicated support portal.
            </p>
          </article>

        </div>

      </div>
    </section>

    <section class="section">
      <div class="container">

        <div style="text-align:center;">
          <div class="section-kicker">
            Getting connected
          </div>

          <h2 class="section-title" style="margin-inline:auto;">
            Four simple steps.
          </h2>
        </div>

        <div class="steps">

          <article class="step">
            <div class="step-index">01</div>
            <h3>Check availability</h3>
            <p>Send your locality or pincode.</p>
          </article>

          <article class="step">
            <div class="step-index">02</div>
            <h3>Choose a plan</h3>
            <p>Pick the speed that fits your needs.</p>
          </article>

          <article class="step">
            <div class="step-index">03</div>
            <h3>Confirm installation</h3>
            <p>
              The AGNS team confirms the connection details.
            </p>
          </article>

          <article class="step">
            <div class="step-index">04</div>
            <h3>Get online</h3>
            <p>Start using your AGNS connection.</p>
          </article>

        </div>

      </div>
    </section>

    <section id="business" class="section dark">
      <div class="container business-grid">

        <div>

          <div class="section-kicker">
            AGNS for business
          </div>

          <h2 class="section-title">
            Connectivity for offices and organisations.
          </h2>

          <p class="section-copy">
            Talk with AGNS about business internet, leased lines
            and hotspot connectivity based on your requirements.
          </p>

          <div style="margin-top:30px;">
            <a
              class="button button-yellow"
              href="mailto:sales@agnsbroadband.in?subject=Business%20Internet%20Enquiry"
            >
              Talk to Business Sales
            </a>
          </div>

        </div>

        <div class="business-cards">

          <article class="business-card">
            <h3>Business Internet</h3>
            <p>
              Broadband connectivity for offices, shops and teams.
            </p>
          </article>

          <article class="business-card">
            <h3>Leased Line</h3>
            <p>
              Discuss dedicated connectivity requirements with AGNS.
            </p>
          </article>

          <article class="business-card">
            <h3>Hotspot Solutions</h3>
            <p>
              Connectivity solutions for locations that need
              managed hotspot access.
            </p>
          </article>

        </div>

      </div>
    </section>

    <section id="support" class="section surface">
      <div class="container support-grid">

        <div>

          <div class="section-kicker">
            Local support
          </div>

          <h2 class="section-title">
            Need help with your connection?
          </h2>

          <p class="section-copy">
            Existing customers can contact AGNS support directly
            by phone, WhatsApp or email.
          </p>

          <div class="hero-actions">

            <a
              class="button button-black"
              href="tel:+919175406933"
            >
              Call Support
            </a>

            <a
              class="button"
              href="mailto:support@agnsbroadband.in"
              style="border:1px solid #ccc;background:#fff;"
            >
              Email Support
            </a>

          </div>

        </div>

        <div>

          <details>
            <summary>
              How do I check whether AGNS is available in my area?
            </summary>

            <p>
              Send your locality and pincode to the AGNS WhatsApp
              number or call the team directly.
            </p>
          </details>

          <details>
            <summary>
              How do I request a new connection?
            </summary>

            <p>
              Contact AGNS with your location. The team will confirm
              availability and installation requirements.
            </p>
          </details>

          <details>
            <summary>
              Does AGNS provide business connectivity?
            </summary>

            <p>
              Yes. Contact sales to discuss business broadband,
              leased lines and hotspot solutions.
            </p>
          </details>

          <details>
            <summary>
              Who do I contact for billing?
            </summary>

            <p>
              Billing and account queries can be sent to
              accounts@agnsbroadband.in.
            </p>
          </details>

        </div>

      </div>
    </section>

    <section id="contact" class="section">
      <div class="container contact-box">

        <div class="contact-grid">

          <div>

            <div class="section-kicker">
              Visit or contact AGNS
            </div>

            <h2 class="section-title">
              Local internet. Local people.
            </h2>

            <p class="section-copy" style="color:#292929;">
              Advance Global Network Solution serves customers
              from its Sawantwadi office.
            </p>

          </div>

          <div class="contact-details">

            <strong>
              Advance Global Network Solution
            </strong>

            <p>
              Asmita Apartment, Shop No. 2<br>
              Junabazer, Sawantwadi 416510
            </p>

            <p>
              <strong>Mobile:</strong><br>
              <a href="tel:+917276938332">7276938332</a>
              /
              <a href="tel:+919175406933">9175406933</a>
            </p>

            <p>
              <strong>WhatsApp:</strong><br>
              <a href="https://wa.me/919096781147">
                90967 81147
              </a>
            </p>

            <p>
              <strong>Sales:</strong><br>
              <a href="mailto:sales@agnsbroadband.in">
                sales@agnsbroadband.in
              </a>
            </p>

            <p>
              <strong>Support:</strong><br>
              <a href="mailto:support@agnsbroadband.in">
                support@agnsbroadband.in
              </a>
            </p>

            <p>
              <strong>Accounts:</strong><br>
              <a href="mailto:accounts@agnsbroadband.in">
                accounts@agnsbroadband.in
              </a>
            </p>

            <p>
              GST No: 27AWZPD7540F1Z5
            </p>

          </div>

        </div>

      </div>
    </section>

    <section class="final-cta">
      <div class="container final-inner">

        <div>
          <h2>
            Ready to check your connection?
          </h2>

          <p>
            Send AGNS your locality and pincode on WhatsApp.
          </p>
        </div>

        <a
          class="button button-yellow"
          href="https://wa.me/919096781147?text=Hi%20AGNS%20XSTREAM%20FIBERNET%2C%20I%20want%20a%20new%20broadband%20connection.%0A%0ALocality%3A%20%0APincode%3A%20"
        >
          Get a New Connection
        </a>

      </div>
    </section>

  </main>

  <footer>
    <div class="container footer-inner">

      <div class="footer-top">

        <a href="#home" class="logo">

          <img
            src="assets/agns-logo.webp"
            alt="AGNS XSTREAM FIBERNET"
            onerror="this.style.display='none';this.nextElementSibling.style.display='block';"
          >

          <span class="logo-fallback">
            AGNS XSTREAM FIBERNET
          </span>

        </a>

        <nav class="footer-nav">
          <a href="#plans">Plans</a>
          <a href="#business">Business</a>
          <a href="#support">Support</a>
          <a href="#contact">Contact</a>
        </nav>

      </div>

      <div class="footer-bottom">
        <div>
          © AGNS XSTREAM FIBERNET
        </div>

        <div>
          Advance Global Network Solution · Sawantwadi
        </div>
      </div>

    </div>
  </footer>

</body>
</html>
HTML

cp \
  site/agns/index.html \
  site/agns/homepage.html

echo "PASS: AGNS website source created"

log "5. Find official AGNS logo"

LOGO_TARGET="${ROOT}/site/agns/assets/agns-logo.webp"

if [[ -s "${LOGO_TARGET}" ]]; then
  echo "PASS: existing official logo preserved"
else
  LOGO_SOURCE="${AGNS_LOGO:-}"

  if [[ -z "${LOGO_SOURCE}" ]]; then
    for candidate in \
      "${ROOT}/agns-logo.webp" \
      "${HOME}/Downloads/agns-logo.webp" \
      "${HOME}/Desktop/agns-logo.webp"
    do
      if [[ -s "${candidate}" ]]; then
        LOGO_SOURCE="${candidate}"
        break
      fi
    done
  fi

  if [[ -n "${LOGO_SOURCE}" ]] &&
     [[ -s "${LOGO_SOURCE}" ]]
  then
    cp \
      "${LOGO_SOURCE}" \
      "${LOGO_TARGET}"

    echo "PASS: official AGNS logo copied from:"
    echo "  ${LOGO_SOURCE}"
  else
    echo "NOTE: official AGNS logo was not found locally."
    echo
    echo "The website will use the text-logo fallback for now."
    echo
    echo "Later place the original logo at:"
    echo "  ${LOGO_TARGET}"
    echo
    echo "Or rerun with:"
    echo "  AGNS_LOGO=/full/path/to/agns-logo.webp ./setup-agns-local.sh"
  fi
fi

log "6. Create permanent local helper"

cat > scripts/agns-local.sh <<'HELPER'
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

PREVIEW_CONTAINER="agns-local-preview"

builder_url() {
  echo "http://webstudio.localhost:3000"
}

preview_url() {
  echo "http://agns.localhost:4173"
}

start_builder() {
  docker compose \
    up \
    -d \
    postgrest \
    app
}

start_preview() {
  docker rm \
    -f \
    "${PREVIEW_CONTAINER}" \
    >/dev/null 2>&1 \
    || true

  docker run \
    -d \
    --name "${PREVIEW_CONTAINER}" \
    --restart unless-stopped \
    -p "127.0.0.1:4173:80" \
    -v "${ROOT}/site/agns:/usr/share/nginx/html:ro" \
    nginx:alpine \
    >/dev/null
}

case "${1:-status}" in

  start)
    start_builder
    start_preview

    echo
    echo "Webstudio:"
    echo "  $(builder_url)"

    echo
    echo "AGNS preview:"
    echo "  $(preview_url)"
    ;;

  stop)
    docker rm \
      -f \
      "${PREVIEW_CONTAINER}" \
      >/dev/null 2>&1 \
      || true

    docker compose \
      stop
    ;;

  restart)
    "$0" stop
    "$0" start
    ;;

  status)
    echo "Webstudio health:"

    curl \
      --silent \
      --output /dev/null \
      --write-out \
      '  HTTP %{http_code}\n' \
      "$(builder_url)/health" \
      || true

    echo
    echo "Docker:"
    docker compose ps

    echo
    echo "Preview:"

    curl \
      --silent \
      --output /dev/null \
      --write-out \
      '  HTTP %{http_code}\n' \
      "$(preview_url)" \
      || true
    ;;

  logs)
    docker compose \
      logs \
      --tail=150 \
      -f \
      app \
      postgrest \
      db
    ;;

  secret)
    sed -n \
      's/^AUTH_SECRET=//p' \
      .env
    ;;

  url)
    builder_url
    ;;

  preview-url)
    preview_url
    ;;

  reset)
    echo
    echo "WARNING:"
    echo "This deletes the LOCAL Webstudio database, assets and projects."
    echo
    read -r -p "Type RESET-LOCAL to continue: " answer

    [[ "${answer}" == "RESET-LOCAL" ]] ||
      exit 1

    docker rm \
      -f \
      "${PREVIEW_CONTAINER}" \
      >/dev/null 2>&1 \
      || true

    docker compose \
      down \
      -v

    "$0" start
    ;;

  *)
    echo "Usage:"
    echo "  ./scripts/agns-local.sh start"
    echo "  ./scripts/agns-local.sh stop"
    echo "  ./scripts/agns-local.sh restart"
    echo "  ./scripts/agns-local.sh status"
    echo "  ./scripts/agns-local.sh logs"
    echo "  ./scripts/agns-local.sh secret"
    echo "  ./scripts/agns-local.sh url"
    echo "  ./scripts/agns-local.sh preview-url"
    echo "  ./scripts/agns-local.sh reset"
    exit 1
    ;;

esac
HELPER

chmod +x \
  scripts/agns-local.sh

bash -n \
  scripts/agns-local.sh

echo "PASS: local helper created"

log "7. Pull Webstudio images"

docker compose pull

log "8. Start local Webstudio"

docker compose \
  up \
  -d \
  postgrest \
  app

echo
echo "Waiting for Webstudio..."

READY=0

for _ in $(seq 1 90); do
  CODE="$(
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      "${BUILDER_URL}/health" \
      || true
  )"

  if [[ "${CODE}" == "200" ]]; then
    READY=1
    break
  fi

  sleep 2
done

if [[ "${READY}" != "1" ]]; then
  echo
  docker compose ps

  echo
  docker compose logs \
    --tail=150 \
    app \
    postgrest \
    db

  fail "Webstudio did not become healthy."
fi

echo "PASS: Webstudio HTTP 200"

log "9. Start AGNS local website preview"

docker rm \
  -f \
  "${PREVIEW_CONTAINER}" \
  >/dev/null 2>&1 \
  || true

docker run \
  -d \
  --name "${PREVIEW_CONTAINER}" \
  --restart unless-stopped \
  -p "127.0.0.1:4173:80" \
  -v "${ROOT}/site/agns:/usr/share/nginx/html:ro" \
  nginx:alpine \
  >/dev/null

PREVIEW_READY=0

for _ in $(seq 1 30); do
  CODE="$(
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      "${PREVIEW_URL}" \
      || true
  )"

  if [[ "${CODE}" == "200" ]]; then
    PREVIEW_READY=1
    break
  fi

  sleep 1
done

[[ "${PREVIEW_READY}" == "1" ]] ||
  fail "AGNS preview did not become healthy."

echo "PASS: AGNS preview HTTP 200"

log "10. Final local status"

echo "Webstudio Builder:"
echo "  ${BUILDER_URL}"

echo
echo "AGNS website:"
echo "  ${PREVIEW_URL}"

echo
echo "Webstudio login email:"
echo "  $(get_env DEV_LOGIN_EMAIL)"

echo
echo "Webstudio login password:"
echo "  $(get_env AUTH_SECRET)"

echo
echo "Permanent commands:"
echo "  ./scripts/agns-local.sh start"
echo "  ./scripts/agns-local.sh stop"
echo "  ./scripts/agns-local.sh restart"
echo "  ./scripts/agns-local.sh status"
echo "  ./scripts/agns-local.sh logs"
echo "  ./scripts/agns-local.sh secret"

echo
echo "AGNS website source:"
echo "  ${ROOT}/site/agns/index.html"

echo
echo "Official logo location:"
echo "  ${ROOT}/site/agns/assets/agns-logo.webp"

echo
echo "Docker status:"
docker compose ps

echo
echo "Git changes:"
git status --short

if command -v open >/dev/null 2>&1; then
  echo
  echo "Opening local AGNS website..."
  open "${PREVIEW_URL}" || true

  echo "Opening local Webstudio..."
  open "${BUILDER_URL}" || true
fi

echo
echo "============================================================"
echo "AGNS LOCAL DEVELOPMENT READY"
echo "============================================================"
