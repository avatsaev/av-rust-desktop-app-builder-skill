# Preferences and persistent UI state

**Add it when:** There is a first setting.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

- Preferences are a serde struct in the engine, changed through a command (`prefs.set {path, value}`) that validates each value.
- Loading is lenient: an unreadable or invalid value falls back to its default and is reported, instead of failing the whole file. A corrupt settings file must never stop the app from starting.
- Window geometry and panel layout are persisted by the app binary: use `tauri-plugin-window-state` for window geometry *(reasoned)* and resolve the app's own settings directory with Tauri's path API *(reasoned)*, then hand the path to the engine through `Services` or an argument. Check both plug-ins' current documentation before coding.
- Theme and `hideDone` already live in `UiState`; persist whichever of them the user expects to survive a restart through the same lenient loader. *(reasoned)*

## Where it goes

Suggested homes: `crates/engine/src/prefs.rs` (L5) for the struct and the `prefs.set` command; `apps/myapp/src-tauri/src/main.rs` (plug-in registration) and `apps/myapp/src-tauri/src/services.rs` (settings directory) for the platform side. File access for the settings file is `cfg(not(target_arch = "wasm32"))` or behind `Services`. No new crate.

## How it fits the seams

- `prefs.set` is a registry command, so the frontend, CLI and agents change settings the same way and it is testable.
- The settings directory is resolved in the app binary, not in the engine or the shell crate.
- Window geometry is platform state kept by a Tauri plug-in; it is not part of the view or the preferences.
- A preference that changes what is drawn reaches the webview through the next `view` event.

## Done when

- [ ] `prefs.set` validates each value and has tests for bad values.
- [ ] Tests load a file with an invalid value, a truncated file and garbage: the app starts with defaults and reports it.
- [ ] The main window's capability is still only what it needs (review `capabilities/default.json`).
- [ ] `cargo xtask wasm` still passes.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
