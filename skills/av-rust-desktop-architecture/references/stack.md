# The stack

What the template uses, what a larger app adds on top, and when this stack is the right choice. In
this file `myapp` stands for the project's machine name.

## Core choices

| Concern | Choice | Notes |
|---|---|---|
| Language | Rust, edition 2024, minimum Rust 1.95; TypeScript 7.0 in the frontend only | The core is Rust; web technology lives only in the webview frontend |
| Build | Cargo workspace, resolver 3, plus one npm project (`apps/myapp`) | Shared Rust dependency versions, lints and profiles live in the root manifest; two lock files (`Cargo.lock`, `apps/myapp/package-lock.json`) |
| Project tasks | `cargo xtask` (a small Rust binary in the workspace): `layers`, `web`, `wasm`, `test`, `ci` | No Makefile and no shell scripts for the gate, so it runs the same on every OS |
| Desktop shell | Tauri 2 (resolved: `tauri` 2.12.5, `wry` 0.57.2, `tao` 0.37.2) | The window, the webview host, the bundler. Keep `tauri`, `tauri-build` and every `tauri-plugin-*` on the same major version |
| Webview | WebView2 on Windows, WKWebView on macOS, WebKitGTK on Linux | The platform's own engine: three different engines to test on |
| Frontend | React 19.3 + TypeScript 7.0, built by Vite 8.3 | `@tauri-apps/api` 2.12 (same minor as `tauri`); the Tauri CLI is the npm package `@tauri-apps/cli` 2.12 (no `cargo install tauri-cli`) |
| Node.js | 22.12 or newer, on an even (LTS) line; npm | Needed for the frontend and the Tauri CLI |
| File dialogs | `tauri-plugin-dialog` 2.8 | Called from Rust code in the app binary, on the owner thread; the webview has no dialog permission |
| Serialisation | `serde`, `serde_json` | The data model, UI state, view, command params and the control protocol are all JSON-shaped |
| Errors | `thiserror` | One error enum per crate; no `anyhow` in libraries |
| Command line | `clap` 4 (derive, env) | |
| Logging | `log` facade (with its `std` feature) and a small logger in the app | |
| Tests | Built-in Rust harness, `cargo-nextest` runner; vitest 5.1 with `@testing-library/react` on jsdom for components | Shell tests need no toolkit and no window; component tests use a fake backend |
| Visual check | `npm run snapshot` (Playwright 1.65, headless Chromium or `--browser webkit`) | Draws the real frontend with the view produced by the real shell |
| Lint and format | clippy with `-D warnings`; rustfmt at 160 columns; for the frontend `tsc --noEmit` and oxlint 1.93 (type-aware, with the React hook rules) | The frontend lint also enforces the thin-frontend rule: no Tauri import outside `src/lib/backend.ts`, no network or storage globals |
| CI | GitHub Actions running one command, `cargo xtask ci` | |
| Packaging | The Tauri bundler: `npm run bundle` (= `tauri build`) | The version comes from `[workspace.package] version` |
| Licence | MIT OR Apache-2.0 | Crates, npm packages and assets restricted to a permissive allowlist (see [principles.md](principles.md)) |

Versions are the ones the template resolved on 2026-11-12: `tauri` 2.12.5, `wry` 0.57.2, `tao`
0.37.2, `tauri-plugin-dialog` 2.8.4, React 19.3.1, Vite 8.3.8, vitest 5.1.0, TypeScript 7.0.2,
`@tauri-apps/api` and `@tauri-apps/cli` 2.12.4, oxlint 1.93.0, Playwright 1.65.0. The lock files list 449 crates
and 183 npm packages.

## Libraries by concern

The template depends on little. This table lists crates known to work together on this stack for
each further need a larger app has. Rows marked *(reasoned)* name a Tauri feature or plug-in that
the template does not contain: they are derived from the architecture and Tauri's documented
capabilities, not built here. Check the current documentation of the plug-in before coding against
it.

| Need | Crates | Notes |
|---|---|---|
| Data parallelism | `rayon` | Native targets only; wasm runs the same loops serially |
| Shared state, plain-data casts | `arc-swap`, `bytemuck` | |
| Date and time | `chrono`, `web-time` | All calendar conversion goes through `chrono`; `web-time` is a monotonic clock that also works in wasm |
| Hashing, compression | `blake3`, `crc32fast`, `flate2` (zlib-rs backend), `ruzstd`, `lz4_flex` | Used in a core that also builds for wasm32 |
| Files | `tempfile`, `rustix`, `cap-std` | Atomic writes; capability-scoped file access for automation |
| Images | `image`, `png`, `tiff`, `exr`, `zune-jpeg`, `jpeg-encoder`, `image-webp`, `zune-jpegxl`, `jxl-oxide` | |
| Vector, text | `kurbo`, `resvg`, `parley`, `skrifa`, `unicode-bidi`, `icu_casemap` | Geometry, SVG, text layout and shaping, font reading |
| Clipboard *(reasoned)* | Tauri's clipboard support (a plug-in) | App binary only; the webview gets no permission it does not need |
| Native menus, OS APIs *(reasoned)* | `tauri::menu` for a native menu bar built from the same `menus::model` data | The template draws menus in the frontend |
| Window state, single instance, updater, opening URLs, deep links, logging *(reasoned)* | `tauri-plugin-window-state`, `tauri-plugin-single-instance`, `tauri-plugin-updater`, `tauri-plugin-opener`, `tauri-plugin-deep-link`, `tauri-plugin-log` | App-binary code and Tauri plug-ins |
| Preferences on disk | `serde_json` | The settings directory comes from Tauri's path API *(reasoned)* |
| Async runtime | `tokio` | Confined to the automation crate and the CLI; the engine has no async code |
| Agents | `rmcp` (MCP server), `schemars` | |
| Plug-ins | `wasmi` | A pure-Rust WebAssembly interpreter: sandboxed, and works under wasm32 too |
| Property tests, fuzzing, benches | `proptest`, `cargo-fuzz` with `libfuzzer-sys`, `criterion` | |
| Frontend | React, Vite, vitest, `@testing-library/react`, Playwright | As in the core choices table |

Write in-house only what is your product's core domain; everything else is plumbing you depend on.
A large production app on this architecture writes three things itself because they are its core
domain (colour management, a layered-document file format, and its compositors). The equivalent
decision in your app is which part is the product and which part is plumbing.

## When this stack fits

It fits well when:

- The app is a tool people work in for long stretches: an editor, a viewer, an analysis or
  production tool, an internal utility.
- You want one codebase for Windows, macOS and Linux with a Rust core and a web-technology UI.
- The UI is forms, lists, tables, panels and menus, where web technology is strongest; heavy custom
  drawing (canvases, timelines, node graphs, plots) is possible with a canvas, see the `canvas view`
  pattern in the `av-rust-desktop-grow` skill.
- The app must be scriptable or driven by agents. The command registry gives you that as a side
  effect.
- Reliability matters more than time to first demo: the rules in [principles.md](principles.md) cost
  effort up front.

Know these properties before choosing it:

- **The UI is web technology in the platform's webview.** It looks like the same web UI everywhere,
  and it runs on three different engines (WebView2, WKWebView, WebKitGTK): test on each, because
  CSS and JavaScript features differ.
- **The frontend redraws from a view event, not per frame.** The shell serialises the whole view on
  every change, so the view must stay small. Never put large data in it (the `av-rust-desktop-grow`
  skill covers the large-data pattern).
- **Web content is possible, with duties.** Rich text, embedded HTML and web pages can be shown,
  but rule 6 in [principles.md](principles.md) applies: the webview gets the least it needs.
- **Two toolchains and two lock files.** Cargo and npm both have to be installed, kept up to date
  and reviewed; the gate runs both.
- **The ecosystem moves.** Tauri, wry, React and Vite make breaking releases regularly. Keep the
  Tauri family on one major version and `@tauri-apps/api` on the same minor as `tauri`, upgrade
  them together on purpose, run the gate and look at a rendered snapshot afterwards. Pin git
  dependencies by full `rev`, never a branch.
- **Compile times and binary size are real.** The template's lock files list 449 crates and 183 npm
  packages. The dev profile in the template is tuned for this (the `av-rust-desktop-ship` skill
  covers build profiles).

The architecture does not depend on Tauri: the engine and the `shell` crate never name a UI
toolkit or a webview (see [layers.md](layers.md)). Replacing the webview shell means rewriting
`apps/myapp` only.

## Where the evidence comes from

This skill-set marks how much each statement is backed. There are three levels:

- **Built and run by the template.** The template was built and exercised on 2026-11-12 in an
  Ubuntu 24.04 container with Rust 1.99.1 and Node 22: the gate passed all eight steps (34 Rust
  tests, 17 frontend tests, the command fuzz, the wasm32 check); the desktop app ran under Xvfb on
  WebKitGTK, was driven over the control socket, and was driven with real mouse and keyboard input
  (typing an item and pressing Enter, clicking a checkbox, Ctrl+Z, a menu click that switched the
  theme); `npm run app` started the window on the Vite dev server; `npm run snapshot` wrote images
  of both themes and they were looked at; `npm run bundle -- --bundles deb` produced a 2.9 MiB
  `.deb` (release binary about 8.8 MB). Where this skill says "the template does this", it means
  this level.
- **Proven in production, but under another shell.** The engine-side architecture (commands,
  snapshots, layering, never-crash rules, the control protocol, the engine parts of the growth
  patterns) comes from a large production app on this architecture whose shell is a native Rust UI
  toolkit, not a webview. The skill-set says "proven in a large production app on this
  architecture" for those parts.
- ***(reasoned)***: everything Tauri-, webview- or React-specific that the template does not
  contain is derived from the architecture and from Tauri's documented capabilities, not built.

Not exercised at all: macOS and Windows (WKWebView, WebView2); native file dialogs; every bundle
format other than `.deb`; signing, notarization and the updater; the GitHub Actions workflow; real
GPU hardware.
