# Autosave and crash recovery

**Add it when:** Before the first release.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

Because the model is a snapshot, a background thread can serialise one without blocking editing. Reuse the normal format writer to write into a recovery directory, and offer what is found there at the next launch.

The template's atomic write is the base for both normal and recovery saves. `write_atomic` in `crates/engine/src/file_cmds.rs` writes a temp file in the same folder, flushes it and renames it over the target, so a crash or a full disk mid-save leaves the previous file intact.

Put the recovery directory under the app data directory, resolved by the app binary with Tauri's path API. *(reasoned)* The offer at launch is data like any other: a command or a `UiState` field the frontend draws as a dialog (see [05](05-dialogs.md)). *(reasoned)*

## Where it goes

Suggested homes: the recovery-directory logic and launch-time check in `apps/myapp/src-tauri/src/services.rs` (app); the writer is the existing L3 `crates/format`; `write_atomic` stays in `crates/engine/src/file_cmds.rs` (native only). The recovery prompt: data in `crates/shell/src/state.rs`, a component in `apps/myapp/src/components/`. No new crate.

## How it fits the seams

- The autosave thread holds an immutable snapshot, so it needs no lock and never sees a half-applied edit.
- It calls the same `crates/format` encoder as the save command; the recovery directory is reached through the app's `Services` or platform code, not by the engine.
- Offering recovery at launch is an owner-thread step that then opens the file through a normal command; the webview only sees the resulting view.

## Done when

- [ ] A test writes a recovery file from a snapshot while editing continues.
- [ ] A test of an interrupted write shows the previous file intact (temp file, flush, rename).
- [ ] Recovery files are validated like any hostile file when offered.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
