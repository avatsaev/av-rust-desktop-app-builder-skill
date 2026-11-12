---
name: av-rust-desktop-grow
description: "Add a structural growth pattern to a Rust desktop app built on Tauri 2 with a React webview frontend and a headless command engine: several open documents or tabs, background jobs with progress and cancel, large data, a canvas view, dialogs, preferences, autosave and recovery, format growth, foreign formats, macros and batch, an MCP server, control hardening, plug-ins, translations, desktop integration, performance budgets, generated docs, web content windows, a browser build, webview end-to-end tests. Use when asked to 'add tabs', 'run this off the UI thread', 'add a progress bar', 'add autosave', 'import a format', 'embed a web page', 'OAuth login window', 'browser build', 'canvas', 'add an MCP server' or 'add plug-ins'."
---

# Growing a Rust desktop app

The template is the smallest project with the right shape. These 20 patterns are the next structural steps. None is in the template and none is needed on day one. Each fits the five seams (`Session::execute`, the command registry, immutable snapshots, `Services`, `UiState` plus the control protocol) without changing them. In examples, `myapp` stands for the project's machine name.

**Evidence.** The engine-side design of each pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities, and each is marked so. Patterns 18 to 20 are new for the webview shell and are *(reasoned)* throughout. None of it is in the template or was built or tested by this skill-set: implement each pattern yourself, with tests, under the project's gate, and check the current documentation of every Tauri API or plug-in a pattern names before coding against it.

## When to use

- A trigger in the table below has become true for the user's project.
- The user asks for a feature that matches a pattern (tabs, progress and cancel, autosave, import, agent access, plug-ins, an embedded web page, a browser build).
- Do not add a pattern speculatively; the template deliberately leaves them out.

## Patterns

| # | Pattern | Add it when | File |
|---|---|---|---|
| 1 | Several open documents | The app has tabs or more than one file open | [patterns/01-several-open-documents.md](patterns/01-several-open-documents.md) |
| 2 | Background jobs | A command takes longer than a frame or two | [patterns/02-background-jobs.md](patterns/02-background-jobs.md) |
| 3 | Large data | Cloning the model is no longer cheap | [patterns/03-large-data.md](patterns/03-large-data.md) |
| 4 | A canvas view | One widget needs more drawing than HTML and SVG do smoothly | [patterns/04-canvas-view.md](patterns/04-canvas-view.md) |
| 5 | Dialogs | Commands need parameters from the user | [patterns/05-dialogs.md](patterns/05-dialogs.md) |
| 6 | Preferences | There is a first setting | [patterns/06-preferences.md](patterns/06-preferences.md) |
| 7 | Autosave and recovery | Before the first release | [patterns/07-autosave-and-recovery.md](patterns/07-autosave-and-recovery.md) |
| 8 | Format growth | The model gains fields or gets large | [patterns/08-native-format-growth.md](patterns/08-native-format-growth.md) |
| 9 | Foreign formats | Import or export of someone else's format | [patterns/09-foreign-formats.md](patterns/09-foreign-formats.md) |
| 10 | Actions and batch | Users repeat sequences | [patterns/10-actions-and-batch.md](patterns/10-actions-and-batch.md) |
| 11 | MCP server | Agents should use the app as a tool | [patterns/11-mcp-server.md](patterns/11-mcp-server.md) |
| 12 | Control hardening | The control channel leaves your own machine's test runs | [patterns/12-control-channel-hardening.md](patterns/12-control-channel-hardening.md) |
| 13 | Plug-ins | Third parties extend the app | [patterns/13-plugins.md](patterns/13-plugins.md) |
| 14 | Translations and fonts | A second language, or custom type | [patterns/14-translations-and-fonts.md](patterns/14-translations-and-fonts.md) |
| 15 | Desktop integration | Before the first release | [patterns/15-desktop-integration.md](patterns/15-desktop-integration.md) |
| 16 | Performance budgets | A slow path has been fixed once and must stay fixed | [patterns/16-performance-budgets.md](patterns/16-performance-budgets.md) |
| 17 | Generated documents | A hand-kept list starts to drift | [patterns/17-generated-documents.md](patterns/17-generated-documents.md) |
| 18 | Web content windows | The app must show web content that is not its own UI (OAuth page, HTML preview, docs) | [patterns/18-web-content-windows.md](patterns/18-web-content-windows.md) |
| 19 | Browser build | The app must also run in a browser tab | [patterns/19-browser-build.md](patterns/19-browser-build.md) |
| 20 | Webview end-to-end tests | Flows that need a real window and webview engine | [patterns/20-webview-end-to-end-tests.md](patterns/20-webview-end-to-end-tests.md) |

Every file has the same parts: Design, Where it goes (layer and suggested paths), How it fits the seams, Done when.

## How to apply a pattern

1. Confirm the trigger really holds. If a simpler change in the existing design solves the problem, stop.
2. Read the pattern file in full, and the `av-rust-desktop-architecture` skill if layers or seams are unfamiliar.
3. Place the code by layer: plain data in L1, pure functions in L2, own-format bytes in L3, foreign formats in L0 plus L4, user actions as commands in L5, UI state, menus and shortcuts as data in L6 `crates/shell`, components in `apps/myapp/src`, platform code in `apps/myapp/src-tauri/src` behind a `Services` hook. Register any new crate in `xtask/src/layers.rs`.
4. Implement behaviour as commands (id, label, menu, shortcut, params doc, `enabled`, `run`, tests) and keep automation-visible UI state in `UiState`. Follow the `av-rust-desktop-develop` skill for the mechanics.
5. Write the tests listed under "Done when", including hostile-input and panic cases, and component tests with a fake backend for webview parts.
6. Run `cargo xtask ci`; for UI changes also look at a rendered image (`npm run snapshot`).

Suggested paths in the pattern files are suggestions for the user's project, not files that exist.

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
- `av-rust-desktop-develop`: add a command, query, crate, UI or control method; verify by rendered image.
- `av-rust-desktop-design`: fit the kind of app into the architecture, decisions to make early.
- `av-rust-desktop-ship`: the gate, CI, packaging, pre-release checklist.
- `av-rust-desktop-bootstrap`: install the toolchain and scaffold the template.
