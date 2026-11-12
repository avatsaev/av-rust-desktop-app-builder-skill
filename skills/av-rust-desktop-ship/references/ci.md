# CI

The workflow has one job to do: install system packages, the Rust toolchain and Node, then run
`cargo xtask ci`. Do not duplicate gate steps in the workflow; add them to the gate (see
[the gate](gate.md)).

**Never run.** The template's `.github/workflows/ci.yml` was written from a large production app's
workflows and has never been run by the authors of this skill-set. The commits its actions are pinned
to were checked to exist on 2026-11-11; that is all that was checked. Run it in your repository and
confirm it goes green before you protect `main` with it.

## Practices the workflow carries

- Actions pinned by commit hash, with the version in a comment.
- `permissions: contents: read`, and `persist-credentials: false` on checkout.
- A newer push cancels a pull request's older run; pushes to `main` always run to the end.
- The build cache is saved only from `main`; pull requests restore it.
- System packages for what Tauri builds against on Linux: `libwebkit2gtk-4.1-dev`, `librsvg2-dev`,
  `libxdo-dev`.
- Node 24 with an npm cache keyed on `apps/myapp/package-lock.json`.
- A first step fails when `Cargo.lock` is out of date, before the gate can refresh it.

The step before the gate fails when `Cargo.lock` does not match the manifests. The gate cannot check
this itself: `cargo xtask` is a plain `cargo run`, which refreshes a stale lock file before any
`--locked` step sees it. The frontend's lock file is checked by the gate itself (`npm ci`).

## `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

# A newer push to a pull request cancels its older run; every push to main runs to the end.
concurrency:
  group: ci-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

env:
  CARGO_TERM_COLOR: always
  RUST_BACKTRACE: 1

jobs:
  gate:
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      # What Tauri builds against on Linux: WebKitGTK (the webview), librsvg, libxdo.
      - name: System packages
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends libwebkit2gtk-4.1-dev librsvg2-dev libxdo-dev
      - uses: step-security/dtolnay-rust-toolchain@8dd607977d06adf4ed49b190381e74c17a9dd25f # v1.0.0
        with:
          toolchain: stable
          components: clippy, rustfmt
          targets: wasm32-unknown-unknown
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: apps/myapp/package-lock.json
      # Only main saves the cache; pull requests restore main's.
      - uses: step-security/rust-cache@8871c8ba063416da7c32246932ea6ae08700453e # v2.9.2
        with:
          save-if: ${{ github.ref == 'refs/heads/main' }}
      - uses: step-security/taiki-e-install-action@76747d22a7567cc4438546a84f11bdf18e670ab8 # v2.87.32
        with:
          tool: cargo-nextest@0.9.150
      # `cargo xtask` is a plain `cargo run`: it would refresh a stale lock file before the gate's
      # `--locked` steps could notice it.
      - name: Cargo.lock is up to date
        run: cargo metadata --locked --format-version 1 > /dev/null
      # The gate runs `npm ci` itself when node_modules is missing, then checks, tests and builds
      # the frontend before any cargo step compiles the app.
      - name: Gate
        run: cargo xtask ci
```

## `.github/dependabot.yml`

Dependabot has three ecosystems, each grouped into one pull request:

```yaml
version: 2
updates:
  # One grouped pull request per ecosystem.
  - package-ecosystem: cargo
    directory: /
    schedule:
      interval: weekly
    groups:
      cargo:
        patterns: ["*"]
  - package-ecosystem: npm
    directory: /apps/myapp
    schedule:
      interval: weekly
    groups:
      npm:
        patterns: ["*"]
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    groups:
      actions:
        patterns: ["*"]
```

## What to add as the project grows

These are what a large production app on this architecture adds, apart from the items marked
*(reasoned)*, which follow from the webview stack and were not built. None is in the template.

- **A shared gate.** With several apps, move the gate into a reusable workflow that takes the package
  list and the command, and have each repository's `ci.yml` call it instead of defining its own
  jobs. Adapt the package list to your stack (the template's is `libwebkit2gtk-4.1-dev
  librsvg2-dev libxdo-dev`):

  ```yaml
  jobs:
    gate:
      uses: <your-org>/<shared-actions-repo>/.github/workflows/gate.yml@<ref>
      with:
        packages: >-
          libwebkit2gtk-4.1-dev librsvg2-dev libxdo-dev
        command: cargo xtask ci
  ```

- **macOS and Windows legs** *(reasoned)*: the three webview engines (WebKitGTK, WKWebView, WebView2)
  differ, and the Linux gate exercises only the first. Run the gate, or at least the frontend and
  app tests, on each platform you ship.
- **Windows legs split** into unit and integration tests that run in parallel, with `sccache`.
- **A job that builds the bundles** *(reasoned)*: `npm run bundle` per platform (see
  [packaging](packaging.md)), so a bundling break shows up before a release.
- **WebDriver end-to-end tests** *(reasoned)* with `tauri-driver` on Linux and Windows (not macOS),
  for the few flows that component tests and the control socket cannot cover. Check Tauri's current
  documentation before coding against it.
- **A dependency source check**: fail when `Cargo.lock` is out of date, or names a git dependency
  from outside your organisation.
- **Jobs that run only when relevant files changed** (path filters): the Windows and macOS legs and
  the bundle job.
- **A corpus job** that runs the parsers against real files fetched at pinned commits.
- **Fuzzing on demand** and a **nightly performance run** on a schedule.
- **Dependabot** for cargo, npm (in `/apps/myapp`) and GitHub Actions, grouped so that each produces
  one pull request. The template generates `.github/dependabot.yml`.

Do not change CI in a feature or fix pull request; make CI changes on their own.
