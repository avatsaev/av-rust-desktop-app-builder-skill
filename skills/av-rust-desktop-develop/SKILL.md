---
name: av-rust-desktop-develop
description: "Daily development in a Rust desktop app built on Tauri 2 with a thin React/TypeScript webview frontend and a headless command-registry engine: add a command, query, crate, UI component, design token, keyboard shortcut, menu item, control-protocol method, Tauri plug-in or second window; change the file format; fix a bug or crash; verify a UI change by rendering a snapshot; run the cargo xtask ci gate; review a change. Use when asked to 'add a command', 'add a feature', 'add a menu item', 'add a shortcut', 'add a React component', 'new crate', 'fix this crash', 'change the file format', 'check the UI', 'run the checks' or 'before I finish' in such a project."
---

# Develop a Rust desktop app on the Tauri + React command-registry architecture

Daily workflow for a project generated from the template: a layered Cargo workspace, a headless
engine with a command registry and immutable snapshots, a UI-toolkit-free shell crate that produces
the view as data, a thin React 19 + TypeScript frontend drawn in the platform webview by Tauri 2,
and a `cargo xtask ci` gate. Every recipe says where the code goes, the exact shape to copy, the
tests to write and the commands to run. Paths are inside the project; `myapp` stands for the
project's machine name (`MyApp` is the product name). The npm project is `apps/myapp`; its Tauri
crate is `apps/myapp/src-tauri`.

## When to use

Any change to an existing project: a feature, a bug fix, a new crate, a UI tweak, a format change,
or verifying and reviewing work. For the big picture (layers, seams, threads) load
`av-rust-desktop-architecture`; for larger capabilities (background jobs, autosave, plug-ins, web
content) load `av-rust-desktop-grow`.

## Where to look

| You want to... | Open |
|---|---|
| Add a user-visible action (the most common change) | [recipes/add-command.md](recipes/add-command.md) |
| Add a read-only command an agent can call | [recipes/add-query.md](recipes/add-query.md) |
| Add a crate and pick its layer | [recipes/add-crate.md](recipes/add-crate.md) |
| Add a component, design token, view toggle, platform hook, shortcut or menu item; write a UI test | [recipes/add-ui.md](recipes/add-ui.md) |
| Add or change a control-protocol method (or, rarely, a Tauri command) | [recipes/add-control-method.md](recipes/add-control-method.md) |
| Add a Tauri plug-in or a second window | [recipes/add-tauri-plugin.md](recipes/add-tauri-plugin.md) |
| Change the model or the file format | [recipes/change-file-format.md](recipes/change-file-format.md) |
| Fix a bug or a crash | [recipes/fix-bug.md](recipes/fix-bug.md) |
| Look up a cargo or npm command, or what each gate step does | [references/commands.md](references/commands.md) |
| Run the window, CLI, view, snapshot, control socket to verify; troubleshoot | [references/verify.md](references/verify.md) |
| Work with other agents, keep a dev log, follow contribution rules | [references/agents.md](references/agents.md) |
| Review a change | [references/review-checklist.md](references/review-checklist.md) |

## The rule that decides most things

**A feature is not done until it is a command.** Write the logic in the lowest crate that fits, add
a `CommandSpec` (id, label, menu, shortcut, params doc, `enabled`, `run`) in
`crates/engine/src/<area>_cmds.rs`, change the model only through `Session::edit`, and test it. The
frontend, the CLI and the control channel then get it for free. The frontend only draws the view and
sends ids; a value typed in the window travels as params of `engine.execute`.

## Procedure for a typical change

1. Pick the recipe above and read it.
2. Put logic at the lowest layer that fits (new crate: [recipes/add-crate.md](recipes/add-crate.md)).
   Logic or state never goes in TypeScript.
3. Write the test first or with the change; for a bug, it must fail before the fix. Rust tests for
   the engine and the shell, vitest component tests for the frontend.
4. Iterate with the narrow command for the crate or component you are in (table below).
5. For UI, run `npm run snapshot` and look at the PNG in both themes
   ([references/verify.md](references/verify.md)).
6. Finish with the commands below, and review against
   [references/review-checklist.md](references/review-checklist.md).

## Daily commands

`apps/myapp/dist` must exist before any cargo command that compiles the app (`cargo run -p myapp`,
`cargo clippy --workspace`): Tauri embeds it at compile time. Run `cargo xtask web` first, and again
after frontend changes. A blank window or a `frontendDist` error means it is missing or stale.

| Command | What it does |
|---|---|
| `cargo xtask web` | Frontend: `npm ci` if needed, type check, lint, tests, build (makes `dist/`) |
| `cargo run -p myapp` | Run the desktop app on the built `dist/` (`--release` for performance work) |
| `npm run app` (in `apps/myapp`) | Run the desktop app on Vite's dev server, with hot reload |
| `npm run check` / `npm run lint` / `npm test` (in `apps/myapp`) | `tsc --noEmit` / oxlint / component tests (vitest) |
| `npm run snapshot` (in `apps/myapp`) | Draw the real frontend to a PNG, no window |
| `cargo test -p <crate> --lib --tests` | One crate's tests |
| `cargo test -p myapp-engine --test panic_hunt -- --ignored` | The adversarial command fuzz |
| `cargo clippy -p <crate> --all-targets -- -D warnings` | Lint what you touched |
| `cargo fmt --all` | Format |
| `cargo xtask layers` / `cargo xtask wasm` | Layering check / wasm32 check |
| `cargo xtask ci` | The whole gate (eight steps); the single definition of green |

The full table and the eight gate steps are in [references/commands.md](references/commands.md).

## Before you finish a change

```sh
cargo test -p <crates you touched>
cargo clippy -p <crates> --all-targets -- -D warnings
(cd apps/myapp && npm run check && npm run lint && npm test)    # when you touched the frontend
cargo xtask ci
```

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

- `av-rust-desktop-architecture`: the stack, the nine rules, layers, the five seams, threads.
- `av-rust-desktop-bootstrap`: install the toolchain, scaffold a project, first build.
- `av-rust-desktop-design`: fit a kind of app into the architecture; replace the sample domain.
- `av-rust-desktop-grow`: background jobs, large data, canvas view, dialogs, preferences, autosave,
  MCP, plug-ins, web content and other growth patterns.
- `av-rust-desktop-ship`: build profiles, CI, packaging, release, pre-release checklist.
