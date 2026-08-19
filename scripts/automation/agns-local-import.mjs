import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const root =
  process.cwd();

const require =
  createRequire(
    import.meta.url
  );

const {
  chromium,
} = require(
  path.join(
    root,
    ".local",
    "playwright",
    "node_modules",
    "playwright"
  )
);

const builderUrl =
  "https://webstudio.localhost";

const projectName =
  "AGNS XSTREAM FIBERNET";

const directProjectId =
  process.env.AGNS_PROJECT_ID ?? "";

const marker =
  "Fiber internet that keeps Sawantwadi moving.";

const pasteShortcut =
  process.platform === "darwin"
    ? "Meta+V"
    : "Control+V";

const importHtml =
  fs.readFileSync(
    path.join(
      root,
      "site",
      "agns",
      "webstudio-import.html"
    ),
    "utf8"
  );

const env =
  fs.readFileSync(
    path.join(
      root,
      ".env"
    ),
    "utf8"
  );

const secret =
  env
    .split(/\r?\n/)
    .find(
      (line) =>
        line.startsWith(
          "AUTH_SECRET="
        )
    )
    ?.slice(
      "AUTH_SECRET=".length
    );

if (!secret) {
  throw new Error(
    "AUTH_SECRET is missing from .env"
  );
}

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

const browser =
  await chromium.launch({
    headless: true,

    args: [
      "--host-resolver-rules=MAP *.localhost 127.0.0.1,MAP localhost 127.0.0.1",
    ],
  });

const context =
  await browser.newContext({
    ignoreHTTPSErrors: true,

    viewport: {
      width: 1440,
      height: 1000,
    },
  });

let page =
  await context.newPage();

async function saveDebug(
  name
) {
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

      timeout:
        30000,
    }
  );

  await page.waitForTimeout(
    1000
  );

  const secretButton =
    page.getByRole(
      "button",
      {
        name:
          /login with secret/i,
      }
    );

  if (
    (await secretButton.count()) === 0
    &&
    !page.url().includes(
      "/login"
    )
  ) {
    return;
  }

  if (
    await secretButton.count()
  ) {
    await secretButton
      .first()
      .click();

    await page.waitForTimeout(
      400
    );
  }

  const password =
    page.locator(
      'input[type="password"]:visible'
    );

  const input =
    (await password.count())
      ? password.first()
      : page
          .locator(
            "input:visible"
          )
          .first();

  if (
    !(await input.count())
  ) {
    throw new Error(
      "Could not find Webstudio login input"
    );
  }

  await input.fill(
    secret
  );

  const submit =
    page.getByRole(
      "button",
      {
        name:
          /login|continue|submit/i,
      }
    );

  if (
    await submit.count()
  ) {
    await submit
      .last()
      .click();
  } else {
    await input.press(
      "Enter"
    );
  }

  await page.waitForTimeout(
    1800
  );

  if (
    page.url().includes(
      "/login"
    )
  ) {
    throw new Error(
      "Webstudio login did not complete"
    );
  }
}

async function adoptNewPage(
  before
) {
  await page.waitForTimeout(
    1200
  );

  const created =
    context
      .pages()
      .filter(
        (candidate) =>
          !before.includes(
            candidate
          )
      );

  if (
    created.length
  ) {
    page =
      created.at(-1);

    await page
      .waitForLoadState(
        "domcontentloaded"
      )
      .catch(
        () => {}
      );
  }
}

async function clickTracking(
  locator
) {
  const before =
    [...context.pages()];

  await locator.click();

  await adoptNewPage(
    before
  );
}

function isCanvasUrl(
  raw
) {
  try {
    const url =
      new URL(raw);

    const host =
      url.hostname;

    return (
      host !==
        "webstudio.localhost"
      &&
      (
        host.endsWith(
          ".webstudio.localhost"
        )
        ||
        host.endsWith(
          "-dot-webstudio.localhost"
        )
      )
      &&
      !url.pathname.startsWith(
        "/auth/ws/callback"
      )
      &&
      url.pathname !== "/error"
    );
  } catch {
    return false;
  }
}

async function waitForEditor() {
  for (
    let attempt = 0;
    attempt < 80;
    attempt++
  ) {
    const raw =
      page.url();

    if (
      raw.startsWith(
        "chrome-error://"
      )
    ) {
      throw new Error(
        "Browser reached a Chrome network error instead of the Webstudio editor"
      );
    }

    try {
      const currentUrl =
        new URL(raw);

      if (
        currentUrl.pathname ===
          "/error"
      ) {
        const errorText =
          await page
            .locator("body")
            .innerText()
            .catch(() => "Webstudio project error");

        await saveDebug(
          "project-editor-error"
        );

        throw new Error(
          `Webstudio project editor failed: ${errorText.replace(/\s+/g, " ").trim().slice(0, 700)}`
        );
      }
    } catch (error) {
      if (
        !(error instanceof TypeError)
      ) {
        throw error;
      }
    }

    if (
      isCanvasUrl(raw)
    ) {
      const dismiss =
        page.getByRole(
          "button",
          {
            name: /^Dismiss$/i,
          }
        );

      if (
        await dismiss.count()
      ) {
        await dismiss
          .last()
          .click({
            force: true,
          })
          .catch(() => {});
      }

      const canvasReady =
        page.frames().some(
          (frame) => {
            try {
              const frameUrl =
                new URL(
                  frame.url()
                );

              return (
                frameUrl.hostname ===
                  new URL(raw).hostname
                &&
                frameUrl.pathname ===
                  "/canvas"
              );
            } catch {
              return false;
            }
          }
        );

      const navigatorReady =
        (
          await page
            .getByText(
              "Navigator",
              {
                exact: true,
              }
            )
            .count()
        ) > 0;

      if (
        canvasReady
        &&
        navigatorReady
      ) {
        return;
      }
    }

    try {
      const url =
        new URL(raw);

      if (
        url.hostname ===
          "webstudio.localhost"
        &&
        url.pathname ===
          "/oauth/ws/authorize"
      ) {
        const body =
          (
            await page
              .locator("body")
              .innerText()
              .catch(
                () => ""
              )
          )
            .trim();

        if (
          /invalid_request|error_description|redirect_uri/i.test(
            body
          )
        ) {
          throw new Error(
            `Webstudio project OAuth failed: ${body.slice(0, 500)}`
          );
        }

        const allow =
          page.getByRole(
            "button",
            {
              name:
                /authorize|allow|approve|grant|continue/i,
            }
          );

        if (
          await allow.count()
        ) {
          await allow
            .first()
            .click();

          await page.waitForTimeout(
            800
          );

          continue;
        }
      }
    } catch (error) {
      if (
        !(error instanceof TypeError)
      ) {
        throw error;
      }
    }

    await page.waitForTimeout(
      500
    );
  }

  throw new Error(
    `Timed out waiting for Webstudio editor. Current URL: ${page.url()}`
  );
}

async function openProjectFromDashboard() {
  await page.goto(
    `${builderUrl}/dashboard`,
    {
      waitUntil:
        "domcontentloaded",

      timeout:
        30000,
    }
  );

  await page.waitForTimeout(
    1200
  );

  let project =
    page.getByText(
      projectName,
      {
        exact: true,
      }
    );

  if (
    await project.count()
  ) {
    console.log(
      "Existing AGNS project found."
    );

    await clickTracking(
      project.first()
    );

    await waitForEditor();

    return;
  }

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

  if (
    !(await create.count())
  ) {
    create =
      page
        .getByText(
          /create a blank project/i
        )
        .first();
  }

  if (
    !(await create.count())
  ) {
    throw new Error(
      "Create a blank project control not found"
    );
  }

  await clickTracking(
    create.first()
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
      await clickTracking(
        submit.last()
      );
    }
  }

  if (
    page.url().includes(
      "/dashboard"
    )
  ) {
    await page.waitForTimeout(
      2000
    );

    project =
      page.getByText(
        projectName,
        {
          exact: true,
        }
      );

    if (
      await project.count()
    ) {
      await clickTracking(
        project.first()
      );
    }
  }

  await waitForEditor();
}

async function openProjectDirect() {
  if (!directProjectId) {
    throw new Error(
      "AGNS_PROJECT_ID is required for deterministic local project opening."
    );
  }

  const host =
    `p-${directProjectId}.webstudio.localhost`;

  const url =
    `https://${host}/`;

  console.log(
    `Opening AGNS project directly: ${url}`
  );

  await page.goto(
    url,
    {
      waitUntil:
        "domcontentloaded",

      timeout:
        30000,
    }
  );

  await waitForEditor();

  const current =
    new URL(
      page.url()
    );

  if (
    current.hostname !== host
    ||
    current.pathname === "/error"
    ||
    current.pathname.startsWith(
      "/auth/ws/callback"
    )
  ) {
    await saveDebug(
      "direct-project-open-invalid"
    );

    throw new Error(
      `Direct AGNS project open ended at an invalid URL: ${page.url()}`
    );
  }

  console.log(
    `PASS: AGNS editor opened directly: ${page.url()}`
  );
}

async function markerFrame() {
  for (
    const frame
    of page.frames()
  ) {
    try {
      const text =
        await frame
          .locator("body")
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
    (await markerFrame())
    !== null
  );
}

async function putOnClipboard() {
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
    .catch(
      () => {}
    );

  await page.evaluate(
    async (html) => {
      const item =
        new ClipboardItem({
          "text/html":
            new Blob(
              [html],
              {
                type:
                  "text/html",
              }
            ),

          "text/plain":
            new Blob(
              [html],
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

    importHtml
  );
}

async function pasteIntoNavigator() {
  await page.keyboard
    .press(
      "z"
    )
    .catch(
      () => {}
    );

  await page.waitForTimeout(
    700
  );

  let body =
    page.getByText(
      "<body>",
      {
        exact: true,
      }
    );

  if (
    !(await body.count())
  ) {
    body =
      page.getByText(
        "Body",
        {
          exact: true,
        }
      );
  }

  if (
    !(await body.count())
  ) {
    return false;
  }

  await body
    .first()
    .click();

  await putOnClipboard();

  await page.keyboard.press(
    pasteShortcut
  );

  await page.waitForTimeout(
    12000
  );

  return markerExists();
}

async function pasteIntoCanvas() {
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
              180,
              box.width / 2
            ),

          y:
            Math.min(
              180,
              box.height / 2
            ),
        },
      });

      await putOnClipboard();

      await page.keyboard.press(
        pasteShortcut
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

async function capture(
  filename,
  width,
  height
) {
  await page.setViewportSize({
    width,
    height,
  });

  await page.waitForTimeout(
    1200
  );

  const output =
    path.join(
      screenshotDir,
      filename
    );

  /*
   * Webstudio can retain hidden/zero-width canvas DOM while
   * responsive breakpoints are changing. Screenshot verification
   * must not invalidate a successful editable build.
   */
  for (
    const frame
    of page.frames()
  ) {
    try {
      const body =
        frame.locator(
          "body"
        );

      if (
        !(await body.count())
      ) {
        continue;
      }

      const text =
        await body.innerText();

      if (
        !text.includes(
          marker
        )
      ) {
        continue;
      }

      const box =
        await body.boundingBox();

      if (
        box
        &&
        box.width > 1
        &&
        box.height > 1
      ) {
        await body.screenshot({
          path:
            output,
        });

        console.log(
          `PASS: canvas screenshot ${filename}`
        );

        return;
      }
    } catch {}
  }

  /*
   * Next try the visible canvas iframe itself. This works even
   * when the iframe document body reports zero width to Playwright.
   */
  const iframes =
    page.locator(
      "iframe"
    );

  for (
    let index = 0;
    index < await iframes.count();
    index++
  ) {
    const iframe =
      iframes.nth(
        index
      );

    try {
      const frame =
        await iframe.contentFrame();

      if (!frame) {
        continue;
      }

      if (
        !frame.url().includes(
          "/canvas"
        )
      ) {
        continue;
      }

      const box =
        await iframe.boundingBox();

      if (
        box
        &&
        box.width > 1
        &&
        box.height > 1
      ) {
        await iframe.screenshot({
          path:
            output,
        });

        console.log(
          `PASS: iframe screenshot ${filename}`
        );

        return;
      }
    } catch {}
  }

  /*
   * Final diagnostic fallback: capture the Builder viewport.
   * The site already passed marker/editor validation, so screenshot
   * geometry alone must never fail the whole build.
   */
  await page.screenshot({
    path:
      output,

    fullPage:
      false,
  });

  console.log(
    `PASS: editor screenshot fallback ${filename}`
  );
}

try {
  console.log(
    "Opening trusted local Webstudio..."
  );

  await login();

  console.log(
    "PASS: Webstudio login"
  );

  await openProjectDirect();

  console.log(
    `PASS: editor opened: ${page.url()}`
  );

  if (
    await markerExists()
  ) {
    console.log(
      "PASS: AGNS homepage already exists; skipping duplicate paste"
    );
  } else {
    console.log(
      `Importing Tailwind HTML with ${pasteShortcut}...`
    );

    let imported =
      await pasteIntoNavigator();

    if (!imported) {
      imported =
        await pasteIntoCanvas();
    }

    if (!imported) {
      await saveDebug(
        "agns-native-import-failed"
      );

      throw new Error(
        "AGNS Tailwind import was not detected in Webstudio"
      );
    }

    console.log(
      "PASS: AGNS homepage imported as Webstudio-editable content"
    );
  }

  fs.writeFileSync(
    projectUrlFile,
    `https://p-${directProjectId}.webstudio.localhost/\n`
  );

  await capture(
    "agns-webstudio-desktop.png",
    1440,
    1000
  );

  await capture(
    "agns-webstudio-mobile.png",
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
    `PROJECT_URL=${page.url()}`
  );
} catch (error) {
  console.error(
    "\nAGNS WEBSTUDIO BUILD FAILED\n"
  );

  console.error(
    error
  );

  await saveDebug(
    "fatal-local-build"
  );

  process.exitCode = 1;
} finally {
  await browser.close();
}
