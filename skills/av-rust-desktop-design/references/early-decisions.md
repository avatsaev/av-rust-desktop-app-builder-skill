# Decisions to make early

Walk these twelve questions with the user before replacing the sample domain. Ask the user for each
decision that the request does not already answer; write `TODO(verify)` in the decision record
instead of guessing. `myapp` in paths stands for the project's machine name.

Guidance marked *(reasoned)* is derived from the architecture and from Tauri's documented
capabilities, not built by the template and not exercised in a shipping app. Unmarked guidance on
the engine side is what a large production app on this architecture does (its shell is a native
Rust UI toolkit, not a webview); unmarked guidance on the shell side is what the template does.
Growth patterns referenced here live in the `av-rust-desktop-grow` skill; they are not part of the
template and are not built or tested by this skill-set.

## Is there a file?

If the user opens and saves files, keep `crates/format` and the `file.*` commands and change the
envelope's `FORMAT` and `EXTENSION`.

If the app has one persistent state instead (a library, settings, a cache), drop `file.open` and
`file.saveAs`, load the state in the app binary at startup, and save it after each command or on
a timer through the same atomic write. *(reasoned)*

## Do you need undo?

With snapshots, undo costs almost nothing to keep, and users expect it wherever they edit. Keep
`Session::edit` as it is.

Skip the history step where undo would be wrong: for data arriving from outside (a log line, a
network update, a sensor reading) add a second `Session` method that publishes a new snapshot
without recording a step. A production app on this architecture has the same split: its `edit`
forwards to an internal method that takes a "record this" flag. *(the feed use is reasoned)*

## Where does the state live?

- **In memory, saved as a whole** (the template): simplest, and right until the state stops
  fitting in memory or saving takes too long.
- **In memory, saved incrementally**: content-addressed chunks, so a save writes only what
  changed (the "growing the native format" pattern in the `av-rust-desktop-grow` skill). A
  production app on this architecture does this.
- **In an external store** *(reasoned)*: commands stay the only writers. Put the store behind a
  trait in an L3 crate, hand an implementation to the `Session` from the app, and keep the model
  as the in-memory view the frontend reads (the current page, the open record, the query result).
  Bump the revision when a command changes what the view shows. A store that does not build for
  wasm32 goes behind `cfg(not(target_arch = "wasm32"))`, the same way the template's file commands
  do.

## Does anything take long?

Anything slow (parsing a large file, a network call, a computation) must not run inside a command
on the thread that owns the shell, because every other request waits behind it. The pattern is
always the same:

1. A worker thread does the slow part from a snapshot and has no access to the `Session`.
2. It sends a message on the owner thread's channel when it has progress or a result.
3. The owner thread applies the result as one command, and the view goes out as usual.

The template already works this way: the Tauri commands and the control-socket threads forward
requests over one channel to the owner thread (`bridge::spawn_owner` in
`apps/myapp/src-tauri/src/bridge.rs`), which owns the `AppShell` and so the `Session`, and wait for
the reply. There is no frame loop and no repaint call: after each request the owner compares the
view with the last one it sent and emits the `view` event when it differs. A blocking file dialog
also runs on the owner thread, so other requests wait while it is open.

The full version, with progress and cancel, is the "background jobs with progress and cancel"
pattern in the `av-rust-desktop-grow` skill (suggested home: `crates/engine/src/jobs.rs`). Its
engine design is proven in production; the message into the owner thread and the progress in the
view, throttled, are *(reasoned)*.

## Is there async or network code?

Keep the async runtime out of the engine. A production app on this architecture confines `tokio`
to its automation crate and CLI; the engine and the shell crate are synchronous.

For a network client *(reasoned)*: an L4 crate owns the runtime and the protocol, and exposes
plain functions and channels. Results come back through the worker pattern above. The engine never
awaits anything, so it stays testable with plain function calls and still builds for wasm32.

## Does live data arrive on its own?

For a monitor or a feed *(reasoned)*:

- Ingest through one command (or the non-recording method above), in batches, not one command per
  sample. Throttle the batches: every change re-serialises and emits the whole view.
- Keep the buffer bounded in the model: drop or downsample old data in L2 code with tests.
- There is no repaint timer to ask for. The view is emitted when it changes, so a feed that
  changes nothing visible costs nothing; keep the view small (send a window or a summary, not the
  buffer).

## One window or several?

One `AppShell` and one `UiState` either way. Further windows are Tauri windows; which windows are
open is data in `UiState`, so `ui.inspect` lists them and automation can see and change it.
*(reasoned; the template has one window)*

## One open model or several?

The template's `Session` holds one. For tabs or several open files, hold a list and an active
index in `Session` and give each a stable id (the "several open documents" pattern in the
`av-rust-desktop-grow` skill); tabs are then data in the view. Commands keep calling
`Session::active()`.

## Do you need a browser build?

No, by default: the template has no browser app. Keep `cargo xtask wasm` anyway: it checks the
layered crates (`doc ops format engine shell`) for wasm32, which is what keeps OS assumptions out
of the core and keeps a browser build possible later. A browser build is the "a browser build"
pattern in the `av-rust-desktop-grow` skill: a third `Backend` implementation backed by the engine
and the shell compiled to wasm32. *(reasoned)*

Narrow the wasm check only when a core dependency truly cannot build for wasm32. Then exclude that
crate and the ones above it from the check in `xtask`, and keep the rest. *(reasoned)*

## Does the app need heavy custom drawing?

Not at first. The webview's HTML and CSS draw panels, lists, tables and forms well enough for most
apps. Add a canvas view when one widget must draw more than the DOM can: the "a canvas view"
pattern in the `av-rust-desktop-grow` skill (a `<canvas>` fed with data from Rust, or rendering in
Rust and shipping frames or tiles to the webview). *(reasoned)*

## Does the app show web content that is not its own UI?

An OAuth page, an HTML preview, embedded documentation. The main window loads no remote content
and gets no extra permissions, whatever the answer. Content that is not the app's own goes in its
own webview window with no capabilities, opened by the app binary through a `Services` hook, with a
navigation allow-list: the "web content in its own webview" pattern in the `av-rust-desktop-grow`
skill. Decide now which pages, from where, because it shapes the permissions and the window list in
`UiState`. Golden rule 6 applies. *(reasoned)*

## Which UI state does automation need to see?

Sort every piece of view state into `UiState` (what an agent should read or set over `ui.inspect`
and `ui.set`: the theme, filters, which dialog or window is open, the status message) or
component-local (what a widget needs only while it is on screen: the text being typed, which menu is
open). See "Where UI state lives" in [fixed-and-chosen.md](fixed-and-chosen.md). Everything in
`UiState` is also mirrored in `types.ts`, `ui.set`'s validation and the control-protocol document.

## Decision record

Fill this in with the user and save it into the project's `docs/architecture.md` (a short
"Decisions" section). Use `TODO(verify)` in the "Choice" column for anything the user has not
confirmed.

| Decision | Choice | Why |
|---|---|---|
| Kind of app (nearest row of the table in [app-kinds.md](app-kinds.md)) | | |
| Is there a file? (format name, extension, or none) | | |
| Undo: on, off, or per kind of change | | |
| Where the state lives (memory + whole save, incremental save, external store) | | |
| Slow work and how it reaches the owner thread | | |
| Async or network code, and which crate owns the runtime | | |
| Live data: ingest command, buffer bound, batch throttle | | |
| Windows: one or several (and the set of windows in `UiState`) | | |
| Open models: one or several | | |
| Browser build: not now, or planned | | |
| Heavy custom drawing: needed or not (canvas view) | | |
| Web content that is not the app's own UI: none, or which pages and from where | | |
| UI state automation sees (`UiState` fields) versus component-local state | | |
