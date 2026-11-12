# Principles

These are constraints, not style preferences. Each is enforced by a tool in the template, and each
is far cheaper to adopt on day one than to retrofit into a codebase that grew without it. Never
weaken one to make a change easier; change the design instead. In this file `myapp` stands for the
project's machine name.

| # | Rule | Enforced by |
|---|---|---|
| 1 | The core is Rust; the frontend is thin | The layer check (no webview crate below the app); the frontend lint (`npm run lint`) rejects a Tauri import outside `src/lib/backend.ts` and network or storage globals; review |
| 2 | Never crash | clippy `deny` lines, `unsafe_code` lint (`forbid`, `deny` in the app crate), the `panic_hunt` test, the crash guard |
| 3 | Everything is a command | The shell has no other way to change the model |
| 4 | Layering is enforced | `cargo xtask layers` |
| 5 | UI state is data | The view is `ui.inspect`; `tokens.test.ts`; component tests with a fake backend; the shell tests |
| 6 | The webview gets the least it needs | `capabilities/default.json`, the CSP in `tauri.conf.json`, review |
| 7 | The core builds for wasm32 | `cargo xtask wasm` |
| 8 | Tests are the gate | `cargo xtask ci` |
| 9 | Permissive licences only | Review; an allowlist |

## 1. The core is Rust; the frontend is thin

The model, history, file format, engine, command registry, shell crate, CLI and the app binary are
Rust. Web technology (React, TypeScript, CSS) lives only in the webview frontend, in
`apps/myapp/src`. The frontend draws the view it is sent and sends command ids back.

One language below the frontend means one set of types from the file parser to the data the
frontend draws, one core test runner, and no second implementation of the rules.

In the frontend, do:

- Get a `Backend` (`control`, `invoke`, `onView`) and the data to draw as props. Components never
  reach for the platform themselves.
- Import `@tauri-apps/api` only in `src/lib/backend.ts`. Everything else talks to the `Backend`
  interface, so tests pass a fake.
- Treat the view as the whole truth about the app: draw it, and ask for changes through command
  ids.
- Keep what a widget needs only while it is on screen (the text being typed, which menu is open)
  in the component. A value the user types or picks travels as params of `engine.execute`.
- Ask for a change and let the next view show it: a checkbox is a controlled input whose `checked`
  is the document's state and whose `onChange` only asks for the change, so the box changes when
  the new view arrives. A failed command's reason arrives as `ui.status` in the next view and is
  shown in the status bar.
- Match shortcuts by comparing the key event with the parsed shortcut data the shell sends, with
  exact modifiers (so `Cmd+Shift+Z` never runs `Cmd+Z`), treating `Cmd` as Ctrl off macOS, and
  leaving undo, redo, select-all and clipboard keys to a focused text field.

In the frontend, never:

- Put business logic, validation rules or document state in TypeScript.
- Call `fetch`, open a socket, read or write storage, or touch files. File and network access are
  Rust's, behind `Services`.
- Parse or define shortcuts, menus or labels that the registry already provides.
- Import Tauri anywhere but `backend.ts`.
- Copy the shell's types by hand and let them drift: `src/lib/types.ts` mirrors `control::view` and
  `document.inspect`, and changes with them.

Ids are `u64` in Rust and JSON numbers in the webview, exact only below 2^53. Say so where ids
cross the boundary; a larger id is an error, never a crash.

## 2. Never crash

People trust a desktop app with their work, and a crash loses it. A malformed file, a bad command
parameter, a message from the webview, a corrupt settings file or a full disk must produce an
error the user or agent can act on, never a panic. This rule is about the Rust code; the frontend
reports a failed reply as a status message and keeps drawing.

- **Non-test Rust code does not panic.** No `unwrap()`, `expect()`, `panic!`, `unreachable!`,
  `todo!` or `unimplemented!`. Return the crate's error type and propagate with `?`. Every library
  crate root carries:

  ```rust
  #![forbid(unsafe_code)]
  #![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]
  ```

  `clippy.toml` allows them in tests only. An unfinished feature returns an "unsupported" error.
- **No `unsafe`.** The workspace sets `unsafe_code = "forbid"`. If one OS integration truly needs
  it, isolate it in its own small crate (e.g. `crates/<os-integration>`) with a `SAFETY:` comment
  on every block.
- **Two documented exceptions in the app crate** (`apps/myapp/src-tauri`):
  - Its `[lints.rust]` sets `unsafe_code = "deny"` instead of `"forbid"`. The crate writes no
    unsafe code, but Tauri's macros generate the app context there and must be able to allow it.
  - `src/commands.rs` carries `#![allow(clippy::unreachable)]`, because `#[tauri::command]`
    generates code beside each function that names `unreachable!`. That module holds nothing but
    the two commands, so the allowance covers no code written by hand. Keep it that way.
- **Input-derived numbers are hostile.** Use `get()` rather than `[i]` for indices that come from
  files, params or arithmetic on them. Use `checked_*` and `saturating_*` for lengths, offsets and
  counts. Guard division by zero and NaN. Cap every allocation sized by input.
- **Bound recursion** with depth limits or seen-sets: data can be deep or cyclic.
- **Don't cascade.** Recover from lock poisoning
  (`lock().unwrap_or_else(PoisonError::into_inner)`) and treat thread joins as `Result`s.
- **Keep a last-resort guard.** The engine catches a panic that escapes a command, and the app
  catches one around file operations, reports it and keeps the open state. This is a safety net,
  not a licence to panic, and it needs `panic = "unwind"` (the default; never set `"abort"`, even
  though size guides for Tauri suggest it).
- **Prove it.** Every crash fix comes with a small test that panicked before the fix. The
  `panic_hunt` test runs every registered command with adversarial params and fails on any panic
  or hang.

## 3. Everything is a command

A user-visible action is an entry in the engine's command registry: a stable id, a label, a menu
path, a shortcut, a description of its params, an `enabled` predicate and a `run` function, plus
tests.

The window, keyboard shortcuts, the CLI, the control channel and tests all dispatch commands by id.
The shell has no other way to change the model.

What this buys:

- The app is scriptable and agent-drivable with no extra work.
- Every feature is testable without a window.
- Menus, shortcut tables and command documentation are generated, so they cannot drift from
  behaviour.
- Undo is uniform: one command is one history step.

Only pure view state (theme, panel visibility, zoom, which tab is showing) lives in the shell, as
"shell commands" that still have ids.

## 4. Layering is enforced

A crate depends only on crates in lower layers, and nothing below the app binary may name a UI
toolkit or webview crate (`tauri`, `wry`, `tao`, a native dialog crate). `cargo xtask layers` reads
`cargo metadata` and fails on a violation. A new crate must be registered in the layer table or the
gate fails (details in [layers.md](layers.md)).

Without the tool, layering erodes one convenient import at a time. With it, the engine and the
`shell` crate stay usable from a CLI and a test because they cannot be otherwise.

## 5. UI state is data

- What automation should be able to see and set is one serde struct in `crates/shell` (`UiState`).
  The frontend draws exactly what `ui.inspect` returns: what a person sees is what an agent reads.
  The view is generated by the shell from the registry and the state, never composed in the
  frontend.
- What a widget needs only while it is on screen stays in the component. Decide per field: if
  automation or a test should read or set it, it belongs in `UiState`; if not, it stays local.
- Widgets read the view and dispatch command ids. They do not hold business logic or mutate the
  model.
- Colours and radii come from design tokens: CSS custom properties in `apps/myapp/src/tokens.css`,
  one block per theme. `tokens.test.ts` fails on a colour literal anywhere else and checks that
  every theme defines the same tokens.
- A UI change is checked by looking at a rendered image. Run `npm run snapshot`: it draws the real
  frontend in headless Chromium, fed with the view from the real shell.
- Test at two levels: shell tests in Rust (no toolkit, no window) for behaviour, component tests in
  TypeScript with a fake backend for drawing.

## 6. The webview gets the least it needs

The webview is a browser engine inside the app; treat everything it can reach as an attack surface.

- **Two commands and one event.** The frontend calls `control(method, params)` and
  `invoke_command(command)`, and listens for the `view` event. Nothing else of the app is
  reachable from it. Do not add a Tauri command casually: each is new surface.
- **No plug-in permissions for the main window.** `capabilities/default.json` grants the main
  window only `core:default`. File dialogs are opened from Rust, so the webview has no dialog
  permission. Grant a permission only when a feature cannot be done from Rust.
- **A strict CSP.** In `tauri.conf.json`:

  ```text
  default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; connect-src ipc: http://ipc.localhost
  ```

  Never loosen it to make something load.
- **No remote content in the main window.** `tauri.conf.json` has no `devUrl`, so a plain
  `cargo run -p myapp` uses the embedded `dist/`; `npm run app` adds
  `src-tauri/tauri.dev.conf.json` (the Vite dev server on port 5173, hot reload) for development
  only.
- **Validate in Rust.** Everything the webview sends (method names, params, command ids) is input
  like any other: it goes through the registry's params checks and never makes the core panic
  (rule 2).

## 7. The core builds for wasm32

Everything layered (`doc ops format engine shell` in the template) must pass
`cargo check --target wasm32-unknown-unknown`. File-system code is behind
`cfg(not(target_arch = "wasm32"))` or goes through an injected service.

Even if you never ship a browser build, this gate is what keeps file-system, thread and OS
assumptions out of the core, and that is what makes the core testable and the shell replaceable.
The `av-rust-desktop-design` skill covers when to narrow it.

## 8. Tests are the gate

Every change comes with tests. `cargo xtask ci` is the single definition of "green", locally and in
CI: format, the frontend (`web`: type check, lint, tests, build), lint, layering, tests, the adversarial
command fuzz, doctests and the wasm check. A contributor runs exactly what CI runs.

Test at the lowest layer that can show the behaviour: an algorithm in its own crate, a command
through `Session::execute`, a click through a shell test or a component test with a fake backend.

## 9. Permissive licences only

Crates, npm packages and bundled assets use licences from an allowlist: `ISC`, `MIT`,
`BSD-2-Clause`, `BSD-3-Clause`, `Apache-2.0`, `OFL-1.1`, `CC0-1.0`, `CC-BY-4.0` and similar. Check a
dependency's licence before adding it, npm packages included (the frontend's transitive tree counts
too). Record every bundled asset (path, title, author, source, licence) in `ATTRIBUTION.md` in the
change that adds it.

Study other products for behaviour only. Never copy their code, strings, shaders or assets.

## Conventions that follow from the rules

- **Ids are public API.** Command ids and control methods are used by scripts and agents. Never
  rename one after a release.
- **Errors are for the reader.** An error says what was wrong and, where possible, what would be
  right: `` `id` must be a non-negative integer, got a string ``.
- **Disabled explains itself.** A command that cannot run now returns the reason. It becomes the
  menu item's tooltip and the message an agent reads.
- **Guards say why.** A check that looks removable carries a comment saying what it prevents.
- **Machine names are lowercase, product names are not.** Crates, binaries and ids are `myapp`;
  everything a user reads says `MyApp`.
