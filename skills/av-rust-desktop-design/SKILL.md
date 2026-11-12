---
name: av-rust-desktop-design
description: "Fit a product idea into the layered architecture of a Rust desktop app built with Tauri 2 and a thin React/TypeScript webview frontend (headless engine, command registry, immutable snapshots, cargo xtask ci gate), and replace the template's sample checklist domain with the real one. Use when the user says 'what kind of app is this', 'how should I structure my app', 'does it need undo / a file format / background jobs / a canvas / several windows', 'adapt the template', 'replace the sample domain', 'rename Item and Document', 'design the model', or 'plan a new Rust desktop app' before writing features."
---

# Design: fitting an app into the architecture

Decide what the user's app is, make the early decisions that are expensive to reverse, record
them, then replace the template's sample domain (a checklist: `Item`, `Document`, `item.*`
commands) step by step. The architecture fixes some things and leaves others to you; the first
job is to know which is which. In paths, `myapp` stands for the project's machine name.

## When to use

- A new Rust desktop app is about to be built and nobody has said what its model, file or undo
  story is.
- The template has been scaffolded (see the `av-rust-desktop-bootstrap` skill) and the sample
  domain must be replaced with the real one.
- A request raises one of the early questions: file or no file, undo, slow work, async, live data,
  several windows or documents, a browser build, heavy custom drawing, web content, what UI state
  automation sees.

## Files

| File | Answers |
|---|---|
| [references/fixed-and-chosen.md](references/fixed-and-chosen.md) | What the architecture fixes and what you choose; what the model must be; model crate properties; where UI state lives |
| [references/app-kinds.md](references/app-kinds.md) | How six kinds of app fit (model, persistence, undo, what to add first) and the evidence behind each |
| [references/early-decisions.md](references/early-decisions.md) | The twelve decisions to make early, and the decision record to save in the project |
| [references/replace-sample-domain.md](references/replace-sample-domain.md) | The nine ordered steps with file paths, what not to touch, and the first-feature checklist |

## What is fixed and what you choose

| Fixed: keep these whatever you build | Yours to choose |
|---|---|
| Crates in enforced layers, binaries at the top | Which crates exist in each layer |
| Every action is a command with an id and JSON params | The commands |
| The model is plain serde data, read through snapshots | What the model is, and where it is stored |
| The frontend draws the view and dispatches ids | The components, the layout, the theme |
| Platform code is injected through `Services` | Which services your app needs |
| UI state is data, exposed with the model over the control protocol | The fields |
| The webview is confined: two commands, one event, no remote content in the main window | Which extra windows show web content, and from where |
| One gate: `cargo xtask ci` | What else the gate runs |

The model is "what the user works on": plain serde data, validated in one place with caps on every
size, cheap to clone, changed only by commands. Rename the crate and type to fit (`project`,
`library`, `workspace`, `state`); nothing else depends on the word. UI state that automation should
see is `UiState` in `crates/shell`; what a widget needs only while on screen is component-local.

## Procedure

1. **Identify the kind of app.** Match the request to a row of the table in
   [references/app-kinds.md](references/app-kinds.md): document editor, library or record manager,
   utility or tool, viewer or monitor, client for a service, real-time tool. Only the document
   editor row is what a shipping app does; the others are *(reasoned)* from the same seams, so say
   so to the user.
2. **Walk the early decisions.** Go through the twelve questions in
   [references/early-decisions.md](references/early-decisions.md). Ask the user about each one the
   request does not already answer. Never guess: write `TODO(verify)` in the record instead.
3. **Write the decision record.** Fill the table at the end of `early-decisions.md` and save it in
   the project's `docs/architecture.md`.
4. **Replace the sample domain** in the order of
   [references/replace-sample-domain.md](references/replace-sample-domain.md): model, format,
   commands, fuzz seed, components, UI state, tests, names, documents. The tree builds and
   `cargo xtask ci` (eight steps) passes after each step; run it after each one, not only at the
   end.
5. **Finish with the first-feature checklist** at the end of `replace-sample-domain.md`. Then load
   the `av-rust-desktop-grow` skill for the "Add first" pattern of the chosen kind, and the
   `av-rust-desktop-develop` skill for daily work.

Do not touch `Session::execute` and `edit`, the registry, `ops::History`, the control protocol and
server, the crash guard, the services struct, `xtask`, the root manifest's lints and profiles, or
the webview boundary (`capabilities/default.json`, the CSP) while replacing the sample domain.

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

- `av-rust-desktop-architecture`: the stack, the nine rules, layers, seams, threads, where new code goes.
- `av-rust-desktop-bootstrap`: install the toolchain, scaffold the template, first build, Day-0 checklist.
- `av-rust-desktop-develop`: add a command, query, crate or UI; change the file format; fix a bug.
- `av-rust-desktop-grow`: the growth patterns (background jobs, large data, canvas view, dialogs, preferences, autosave, and more).
- `av-rust-desktop-ship`: build profiles, the gate, CI, packaging and release.
