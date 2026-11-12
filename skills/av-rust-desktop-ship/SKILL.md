---
name: av-rust-desktop-ship
description: "Ship a Rust desktop app built on Tauri 2 with a React/TypeScript webview frontend: make `cargo xtask ci` green (eight steps incl. the npm frontend build), tune Cargo build profiles, fix a stale Cargo.lock or package-lock.json, write or fix the GitHub Actions workflow, bundle with the Tauri bundler (deb, rpm, AppImage, dmg, msi, nsis), icons, signing, repository files (AGENTS.md, licences, ATTRIBUTION.md, SECURITY.md), pin git dependencies, upgrade Tauri, and run the before-first-release checklist. Use when asked about CI, the gate, build profiles, installers, release, or 'what must exist before we ship'."
---

# av-rust-desktop-ship

Build, gate, CI, packaging and release for a Rust desktop app on the Tauri 2 stack: a React +
TypeScript frontend in the platform webview, over a layered Cargo workspace with a `cargo xtask ci`
gate. In every path, `myapp` stands for the project's machine name. The template's gate, app and
`.deb` bundle were built and run on Linux only. The CI workflow, macOS and Windows behaviour, the
other bundle formats and signing have not been run by this skill-set's authors; such guidance is
marked *(reasoned)*.

## When to use

- "Make CI green", "why does the gate fail", "the lock file is stale", "`dist/` is missing".
- "Tune the build profile", "the binary is too big", "debug with local variables".
- "Package for Linux/macOS/Windows", "sign a build", "set up releases", "replace the icon".
- "What files must the repository have", "pin a git dependency", "upgrade Tauri".
- "What must exist before the first release".

## Files

| File | Answers |
|---|---|
| [references/gate.md](references/gate.md) | The eight gate steps, why `web` comes first, `--locked`, xtask usage and output, adding steps, nextest config |
| [references/build-profiles.md](references/build-profiles.md) | The `dev` and `release` blocks and rules; the frontend build and sizes; root-manifest facts |
| [references/ci.md](references/ci.md) | The GitHub Actions workflow and Dependabot config in full, practices, what to add as the project grows |
| [references/packaging.md](references/packaging.md) | `npm run bundle`, `tauri.conf.json`, per-platform bundle targets, icons, conventions, hand-written alternative |
| [references/repository-files.md](references/repository-files.md) | Required repository files, starting `AGENTS.md`, git pins, upgrading Tauri, contribution rules, licence allowlist |
| [references/release-checklist.md](references/release-checklist.md) | What is not verified, the twelve items and the webview-specific items before the first release |

## Routing

1. **Make CI green.** Run `cargo xtask ci` and read the `CI summary`: it names the failed step and
   the skipped ones. Fix that step and rerun; see [gate](references/gate.md). A stale lock file or a
   workflow problem: see [CI](references/ci.md).
2. **Tune a build profile.** Edit the profile in the root `Cargo.toml` and measure; see
   [build profiles](references/build-profiles.md). Use `CARGO_PROFILE_DEV_DEBUG=true` for locals
   instead of editing the manifest.
3. **Package for platform X.** In `apps/myapp` run `npm run bundle` (`-- --bundles deb` for one
   format); see [packaging](references/packaging.md). Only the `.deb` was built by the template.
4. **What must exist before release.** Work through [the checklist](references/release-checklist.md)
   and [repository files](references/repository-files.md).

## The gate in brief

`cargo xtask ci` runs these in order and stops at the first failure. It is the single definition of
green, locally and in CI.

| Step | Command | Catches |
|---|---|---|
| `fmt` | `cargo fmt --all -- --check` | Unformatted code |
| `web` | `npm ci` if `node_modules` is missing, then `npm run check`, `lint`, `test`, `build` in `apps/myapp` | Frontend type, lint, test and build failures; produces `dist/`, which Tauri embeds at compile time |
| `clippy` | `cargo clippy --workspace --locked --all-targets -- -D warnings` | Lints, including the no-panic rules |
| `layers` | The layer check | An upward dependency, a webview crate below the app binary, an unregistered crate |
| `test` | `cargo nextest run --profile ci --workspace --locked --lib --bins --tests` | Behaviour (falls back to `cargo test`) |
| `panic_hunt` | The ignored engine test | A command that panics or hangs on bad params |
| `doctest` | `cargo test --workspace --locked --doc` | Broken doc examples |
| `wasm` | `cargo check --target wasm32-unknown-unknown` | OS assumptions in the core |

## Hard rules

- Never set `panic = "abort"`, even though Tauri size guides suggest it: the crash guard needs
  unwinding.
- Commit both lock files: `Cargo.lock` and `apps/myapp/package-lock.json`.
- There is one version, in `[workspace.package]`; `tauri.conf.json` sets none.
- Stop and ask before anything hard to undo: publishing, releases, secrets, spending money,
  destructive git.

## Golden rules

These hold in every project built on this architecture. Each is enforced by tooling in the project.

1. **The core is Rust; the frontend is thin.** Web technology (React, TypeScript) lives only in the webview frontend, `apps/myapp/src`. It draws the view it is sent and sends command ids: no business logic, no document state, no file or network access in TypeScript.
2. **Never crash.** Non-test Rust code has no `unwrap`, `expect`, `panic!`, `unreachable!`, `todo!` or `unimplemented!`, and no `unsafe`. Return the crate's error type. Input is hostile: check bounds, cap sizes, bound recursion. A crash fix ships with a test that panicked before it.
3. **Everything is a command.** User-visible behaviour is a command in `crates/engine/src/*_cmds.rs` with an id, label, menu, shortcut, params doc, `enabled`, `run` and tests. The frontend, the CLI and the control channel dispatch ids.
4. **Layering is enforced.** A crate depends only on lower layers; nothing below the app binary uses tauri, wry or tao. `cargo xtask layers` checks it; register a new crate in `xtask/src/layers.rs`.
5. **UI state is data.** What automation should see is one serde struct in `crates/shell`, and the frontend draws exactly what `ui.inspect` returns. Colours come from the tokens in `tokens.css`. Look at a rendered image (`npm run snapshot`) before calling a UI change done.
6. **The webview gets the least it needs.** Two commands and one event; no plug-in permissions for the main window, a strict CSP, no remote content in it. What the webview sends is validated in Rust like any other input.
7. **The core builds for wasm32.** File-system code is `cfg(not(target_arch = "wasm32"))` or behind `Services`. `cargo xtask wasm` checks it.
8. **Tests are the gate.** Every change comes with tests. `cargo xtask ci` is the single definition of green, locally and in CI.
9. **Permissive licences only.** Crates, npm packages and bundled assets come from an allowlist (MIT, Apache-2.0, BSD, ISC, OFL-1.1, CC0-1.0, CC-BY-4.0 and similar); every bundled asset gets a row in `ATTRIBUTION.md`.

## Related skills

- `av-rust-desktop-architecture`: the stack, the nine rules, layers, seams.
- `av-rust-desktop-bootstrap`: toolchain, scaffolding, first build, troubleshooting.
- `av-rust-desktop-design`: fitting an app into the architecture.
- `av-rust-desktop-develop`: daily work and the review checklist.
- `av-rust-desktop-grow`: growth patterns referenced by the release checklist.
