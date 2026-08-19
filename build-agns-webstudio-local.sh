#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

PROJECT_NAME="AGNS XSTREAM FIBERNET"
MARKER="Fiber internet that keeps Sawantwadi moving."

BUILDER_URL="http://webstudio.localhost:3000"

PLAYWRIGHT_DIR="${ROOT}/.local/playwright"
DEBUG_DIR="${ROOT}/.local/webstudio-debug"
SCREENSHOT_DIR="${ROOT}/.local/screenshots"

log() {
  printf '\n============================================================\n'
  printf '%s\n' "$1"
  printf '============================================================\n'
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

log "1. Verify local AGNS setup"

[[ -f .env ]] ||
  fail ".env missing. Run the local setup script first."

[[ -f site/agns/index.html ]] ||
  fail "site/agns/index.html missing."

[[ -s site/agns/index.html ]] ||
  fail "AGNS homepage is empty."

docker info >/dev/null 2>&1 ||
  fail "Docker is not running."

docker compose up -d

READY=0

for _ in $(seq 1 60); do
  CODE="$(
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      http://localhost:3000/health \
      || true
  )"

  if [[ "${CODE}" == "200" ]]; then
    READY=1
    break
  fi

  sleep 2
done

[[ "${READY}" == "1" ]] ||
  fail "Webstudio Builder did not become healthy."

echo "PASS: Webstudio HTTP 200"
echo "PASS: AGNS homepage source found"

log "2. Prepare local browser automation"

mkdir -p \
  "${PLAYWRIGHT_DIR}" \
  "${DEBUG_DIR}" \
  "${SCREENSHOT_DIR}"

if [[ ! -f "${PLAYWRIGHT_DIR}/package.json" ]]; then
  (
    cd "${PLAYWRIGHT_DIR}"
    npm init -y >/dev/null
  )
fi

if [[ ! -d "${PLAYWRIGHT_DIR}/node_modules/playwright" ]]; then
  (
    cd "${PLAYWRIGHT_DIR}"

    npm install \
      --silent \
      --no-audit \
      --no-fund \
      playwright
  )
fi

(
  cd "${PLAYWRIGHT_DIR}"

  if [[ "$(uname -s)" == "Linux" ]]; then
    npx playwright install \
      --with-deps \
      chromium
  else
    npx playwright install \
      chromium
  fi
)

echo "PASS: Playwright ready"

log "3. Create local Webstudio importer"

mkdir -p scripts/automation

cat > scripts/automation/agns-local-import.mjs <<'JS'
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const root = process.cwd();

const require = createRequire(
  import.meta.url
);

const { chromium } = require(
  path.join(
    root,
    ".local",
    "playwright",
    "node_modules",
    "playwright"
  )
);

const builderUrl =
  "http://webstudio.localhost:3000";

const projectName =
  "AGNS XSTREAM FIBERNET";

const marker =
  "Fiber internet that keeps Sawantwadi moving.";

const debugDir =
  path.join(
    root,
    ".local",
    "webstudio-debug"
  );

const screenshotDir =
  path.join(
    root,
    ".local",
    "screenshots"
  );

const projectUrlFile =
  path.join(
    root,
    ".local",
    "agns-local-project-url.txt"
  );

fs.mkdirSync(
  debugDir,
  {
    recursive: true,
  }
);

fs.mkdirSync(
  screenshotDir,
  {
    recursive: true,
  }
);

function envValue(name) {
  const text =
    fs.readFileSync(
      path.join(
        root,
        ".env"
      ),
      "utf8"
    );

  for (
    const line
    of text.split(/\r?\n/)
  ) {
    if (
      line.startsWith(
        `${name}=`
      )
    ) {
      return line.slice(
        name.length + 1
      );
    }
  }

  return "";
}

const secret =
  envValue(
    "AUTH_SECRET"
  );

if (!secret) {
  throw new Error(
    "AUTH_SECRET is missing."
  );
}

const source =
  fs.readFileSync(
    path.join(
      root,
      "site",
      "agns",
      "index.html"
    ),
    "utf8"
  );

const logoPath =
  path.join(
    root,
    "site",
    "agns",
    "assets",
    "agns-logo.webp"
  );

let logoData = "";

if (
  fs.existsSync(
    logoPath
  )
) {
  logoData =
    fs.readFileSync(
      logoPath
    )
      .toString(
        "base64"
      );
}

let html =
  source;

if (logoData) {
  html =
    html.replaceAll(
      "assets/agns-logo.webp",
      `data:image/webp;base64,${logoData}`
    );
}

const browser =
  await chromium.launch({
    headless: true,
  });

const context =
  await browser.newContext({
    viewport: {
      width: 1440,
      height: 1000,
    },
  });

let page =
  await context.newPage();

async function debug(name) {
  try {
    await page.screenshot({
      path:
        path.join(
          debugDir,
          `${name}.png`
        ),

      fullPage: true,
    });
  } catch {}

  try {
    fs.writeFileSync(
      path.join(
        debugDir,
        `${name}.html`
      ),

      await page.content()
    );
  } catch {}
}

async function login() {
  await page.goto(
    builderUrl,
    {
      waitUntil:
        "domcontentloaded",
    }
  );

  await page.waitForTimeout(
    1200
  );

  const secretLogin =
    page.getByRole(
      "button",
      {
        name:
          /login with secret/i,
      }
    );

  if (
    (await secretLogin.count()) === 0 &&
    !page.url().includes(
      "/login"
    )
  ) {
    console.log(
      "PASS: existing Webstudio session"
    );

    return;
  }

  if (
    await secretLogin.count()
  ) {
    await secretLogin
      .first()
      .click();

    await page.waitForTimeout(
      400
    );
  }

  const passwords =
    page.locator(
      'input[type="password"]:visible'
    );

  const input =
    (await passwords.count()) > 0
      ? passwords.first()
      : page
          .locator(
            "input:visible"
          )
          .first();

  if (!(await input.count())) {
    await debug(
      "login-input-missing"
    );

    throw new Error(
      "Unable to find Webstudio secret-login input."
    );
  }

  await input.fill(
    secret
  );

  const loginButton =
    page.getByRole(
      "button",
      {
        name:
          /login|continue|submit/i,
      }
    );

  if (
    await loginButton.count()
  ) {
    await loginButton
      .last()
      .click();
  } else {
    await input.press(
      "Enter"
    );
  }

  await page.waitForTimeout(
    2000
  );

  console.log(
    "PASS: Webstudio login"
  );
}

async function dashboard() {
  await page.goto(
    `${builderUrl}/dashboard`,
    {
      waitUntil:
        "domcontentloaded",
    }
  );

  await page.waitForTimeout(
    1500
  );
}

async function switchToPopup(
  popupPromise
) {
  const popup =
    await popupPromise;

  if (!popup) {
    return;
  }

  page = popup;

  await page
    .waitForLoadState(
      "domcontentloaded"
    )
    .catch(() => {});

  await page.waitForTimeout(
    2000
  );
}

async function openExistingProject() {
  await dashboard();

  const named =
    page.getByText(
      projectName,
      {
        exact: true,
      }
    );

  if (!(await named.count())) {
    return false;
  }

  console.log(
    "Existing AGNS project found."
  );

  const popupPromise =
    context
      .waitForEvent(
        "page",
        {
          timeout: 4000,
        }
      )
      .catch(
        () => null
      );

  await named
    .first()
    .click();

  await switchToPopup(
    popupPromise
  );

  await page.waitForTimeout(
    3500
  );

  return true;
}

async function createProject() {
  await dashboard();

  console.log(
    "Creating AGNS project..."
  );

  let create =
    page.getByRole(
      "button",
      {
        name:
          /create a blank project/i,
      }
    );

  if (!(await create.count())) {
    create =
      page.getByText(
        /create a blank project/i
      );
  }

  if (!(await create.count())) {
    await debug(
      "create-project-control-missing"
    );

    throw new Error(
      "Create a blank project control not found."
    );
  }

  const popupPromise =
    context
      .waitForEvent(
        "page",
        {
          timeout: 5000,
        }
      )
      .catch(
        () => null
      );

  await create
    .first()
    .click();

  await switchToPopup(
    popupPromise
  );

  await page.waitForTimeout(
    700
  );

  const dialog =
    page.locator(
      '[role="dialog"]:visible'
    );

  if (
    await dialog.count()
  ) {
    const input =
      dialog
        .locator(
          "input:visible"
        )
        .first();

    if (
      await input.count()
    ) {
      await input.fill(
        projectName
      );
    }

    const submit =
      dialog.getByRole(
        "button",
        {
          name:
            /create|continue|start/i,
        }
      );

    if (
      await submit.count()
    ) {
      await submit
        .last()
        .click();
    }
  }

  await page.waitForTimeout(
    5000
  );

  /*
   * Some Webstudio versions create the project on the
   * dashboard instead of immediately opening the editor.
   */
  if (
    page.url().includes(
      "/dashboard"
    )
  ) {
    const named =
      page.getByText(
        projectName,
        {
          exact: true,
        }
      );

    if (
      await named.count()
    ) {
      const secondPopup =
        context
          .waitForEvent(
            "page",
            {
              timeout:
                5000,
            }
          )
          .catch(
            () => null
          );

      await named
        .first()
        .click();

      await switchToPopup(
        secondPopup
      );

      await page.waitForTimeout(
        4000
      );
    }
  }
}

async function markerFrame() {
  for (
    const frame
    of page.frames()
  ) {
    try {
      const text =
        await frame
          .locator(
            "body"
          )
          .innerText();

      if (
        text.includes(
          marker
        )
      ) {
        return frame;
      }
    } catch {}
  }

  return null;
}

async function markerExists() {
  return (
    await markerFrame()
  ) !== null;
}

async function clipboard() {
  const origin =
    new URL(
      page.url()
    ).origin;

  await context
    .grantPermissions(
      [
        "clipboard-read",
        "clipboard-write",
      ],
      {
        origin,
      }
    )
    .catch(() => {});

  await page.evaluate(
    async (value) => {
      const item =
        new ClipboardItem({
          "text/html":
            new Blob(
              [value],
              {
                type:
                  "text/html",
              }
            ),

          "text/plain":
            new Blob(
              [value],
              {
                type:
                  "text/plain",
              }
            ),
        });

      await navigator
        .clipboard
        .write(
          [item]
        );
    },

    html
  );
}

async function pasteNavigator() {
  const body =
    page.getByText(
      "Body",
      {
        exact: true,
      }
    );

  if (!(await body.count())) {
    return false;
  }

  console.log(
    "Pasting AGNS page into Navigator..."
  );

  await body
    .first()
    .click();

  await clipboard();

  await page.keyboard.press(
    "Control+V"
  );

  await page.waitForTimeout(
    12000
  );

  return await markerExists();
}

async function pasteCanvas() {
  console.log(
    "Trying Webstudio canvas paste..."
  );

  for (
    const frame
    of page.frames()
  ) {
    if (
      frame ===
      page.mainFrame()
    ) {
      continue;
    }

    try {
      const body =
        frame.locator(
          "body"
        );

      const box =
        await body.boundingBox();

      if (!box) {
        continue;
      }

      await body.click({
        position: {
          x:
            Math.min(
              200,
              Math.max(
                20,
                box.width / 2
              )
            ),

          y:
            Math.min(
              200,
              Math.max(
                20,
                box.height / 2
              )
            ),
        },
      });

      await clipboard();

      await page.keyboard.press(
        "Control+V"
      );

      await page.waitForTimeout(
        12000
      );

      if (
        await markerExists()
      ) {
        return true;
      }
    } catch {}
  }

  return false;
}

async function screenshot(
  filename,
  width,
  height
) {
  await page.setViewportSize({
    width,
    height,
  });

  await page.waitForTimeout(
    1000
  );

  const frame =
    await markerFrame();

  if (frame) {
    await frame
      .locator(
        "body"
      )
      .screenshot({
        path:
          path.join(
            screenshotDir,
            filename
          ),
      });

    return;
  }

  await page.screenshot({
    path:
      path.join(
        screenshotDir,
        filename
      ),

    fullPage: true,
  });
}

try {
  await login();

  const existing =
    await openExistingProject();

  if (!existing) {
    await createProject();
  }

  console.log(
    `Project/editor URL: ${page.url()}`
  );

  if (
    page.url().includes(
      "/oauth/ws/authorize"
    )
  ) {
    await debug(
      "local-oauth-error"
    );

    throw new Error(
      "Local project stopped on Webstudio OAuth authorization."
    );
  }

  await page.waitForTimeout(
    3500
  );

  if (
    await markerExists()
  ) {
    console.log(
      "PASS: AGNS page already exists"
    );
  } else {
    let imported =
      await pasteNavigator();

    if (!imported) {
      imported =
        await pasteCanvas();
    }

    if (!imported) {
      await debug(
        "local-import-failed"
      );

      throw new Error(
        "AGNS page could not be detected after paste."
      );
    }

    console.log(
      "PASS: AGNS page imported"
    );
  }

  fs.writeFileSync(
    projectUrlFile,
    `${page.url()}\n`
  );

  await screenshot(
    "agns-local-desktop.png",
    1440,
    1000
  );

  await screenshot(
    "agns-local-mobile.png",
    430,
    900
  );

  console.log(
    "PASS: desktop screenshot"
  );

  console.log(
    "PASS: mobile screenshot"
  );

  console.log(
    ""
  );

  console.log(
    "AGNS LOCAL WEBSTUDIO PROJECT READY"
  );

  console.log(
    page.url()
  );
} catch (error) {
  console.error(
    "\nAGNS LOCAL BUILD FAILED\n"
  );

  console.error(
    error
  );

  await debug(
    "fatal-local-build"
  );

  process.exitCode = 1;
} finally {
  await browser.close();
}
JS

node --check \
  scripts/automation/agns-local-import.mjs

echo "PASS: importer syntax"

log "4. Build AGNS inside local Webstudio"

node \
  scripts/automation/agns-local-import.mjs

log "5. Verify"

[[ -s .local/agns-local-project-url.txt ]] ||
  fail "Project URL was not saved."

[[ -s .local/screenshots/agns-local-desktop.png ]] ||
  fail "Desktop screenshot missing."

[[ -s .local/screenshots/agns-local-mobile.png ]] ||
  fail "Mobile screenshot missing."

echo
echo "Project:"
cat \
  .local/agns-local-project-url.txt

echo
echo "Screenshots:"
echo "  ${ROOT}/.local/screenshots/agns-local-desktop.png"
echo "  ${ROOT}/.local/screenshots/agns-local-mobile.png"

echo
echo "Builder:"
echo "  ${BUILDER_URL}"

echo
echo "============================================================"
echo "AGNS LOCAL WEBSTUDIO BUILD COMPLETE"
echo "============================================================"

if command -v open >/dev/null 2>&1; then
  open "$(cat .local/agns-local-project-url.txt)" || true
fi
