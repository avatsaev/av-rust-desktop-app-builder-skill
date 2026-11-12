# Plug-ins

**Add it when:** Third parties extend the app.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

Third-party code runs as WebAssembly in `wasmi`, a pure-Rust interpreter, with an instruction budget, a wall-clock deadline and no host imports. That needs no `unsafe` and works on every platform. Plug-ins are driven through commands like everything else.

These are the app's own plug-ins, hosted in Rust. They are unrelated to Tauri plug-ins, and they never run in the webview.

## Where it goes

Suggested homes: `crates/plugins` (L4, plug-in host) and `docs/plugins.md`. Register any new crate in `xtask/src/layers.rs`; `cargo xtask layers` fails on an unregistered crate. The `wasmi` dependency must pass the licence allowlist.

## How it fits the seams

- Plug-in calls are commands (`plugin.*`), so they go through `Session::execute` with params, `enabled` and error handling, on the owner thread.
- A trapped, over-budget or timed-out plug-in becomes an error; the snapshot is untouched.
- With no host imports, a plug-in cannot reach the OS; anything it needs goes through the host's explicit API.

## Done when

- [ ] Tests: infinite loop hits the instruction budget; deadline fires; a module requesting an import is refused; a trap becomes an error.
- [ ] The crate contains no `unsafe` and no panics on hostile modules.
- [ ] `docs/plugins.md` written.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
