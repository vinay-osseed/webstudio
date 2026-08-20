# AGNS Webstudio exports

The production Builder is self-hosted at:

```text
https://webstudio.agnsbroadband.in
```

Webstudio's official self-hosting documentation recommends using the
Webstudio CLI when the Builder itself is self-hosted.

## Builder static download

The cloud Builder can provide a direct static ZIP download. A self-hosted
Builder does not provide the same cloud download backend. Do not patch the
Builder UI around `NOT_IMPLEMENTED`.

Use the repository export commands below instead. They produce a portable
static ZIP/tarball and also support Docker/application exports.

## First-time link

In the AGNS project, create a Share link with **Build** permission.

Then run:

```bash
./scripts/prod/export-site.sh link
```

Paste the Build Share link when prompted.

The link metadata is retained under the ignored `exports/agns-source`
workspace.

## Status

```bash
./scripts/prod/status.sh
./scripts/prod/export-site.sh status
```

## Sync

```bash
./scripts/prod/export-site.sh sync
```

## Static site

```bash
./scripts/prod/export-site.sh static
```

The workflow syncs the project, runs the Webstudio SSG template generator,
installs the generated dependencies, builds the final static HTML/CSS/JS,
verifies `index.html`, and creates deployable archives.

Deployable files:

```text
exports/latest-static/
```

Timestamped archives:

```text
exports/artifacts/
```

The contents of `exports/latest-static` are what should be copied to the
separate host serving `agnsbroadband.in`.

## Docker/application export

```bash
./scripts/prod/export-site.sh docker
```

Docker-ready output:

```text
exports/latest-docker/
```

## Export everything

```bash
./scripts/prod/export-site.sh all
```

## Any Webstudio CLI template

```bash
./scripts/prod/export-site.sh template TEMPLATE_NAME
```

## Cleanup generated builds

```bash
./scripts/prod/export-site.sh clean
```

The linked source workspace and packaged artifacts are preserved.

## Legacy command

Existing automation can continue using:

```bash
./scripts/prod/export-static.sh
```

It delegates to the reusable export workflow.
