# Add a Tauri plug-in or a second window *(reasoned)*

Paths are inside the project; `myapp` stands for the project's machine name.

**Evidence label.** The template builds and runs exactly one plug-in, `tauri-plugin-dialog`, called
from Rust behind a `Services` hook. Everything below beyond that pattern is *(reasoned)*: derived
from the architecture and from Tauri's documented capabilities, not built or run by this skill-set.
Tauri's plug-in and window APIs change between releases, so check the current documentation of the
plug-in or API you add before coding against it. This page names features; it does not give their
API details.

Candidates (names only, check their documentation): `tauri-plugin-window-state`,
`tauri-plugin-single-instance`, `tauri-plugin-updater`, `tauri-plugin-opener`,
`tauri-plugin-deep-link`, `tauri-plugin-log`, `bundle.fileAssociations`, `WebviewWindowBuilder`,
`tauri::menu`.

## The model to follow

The template's file dialogs are the pattern: the plug-in is registered in the app binary, called
from Rust through a `Services` hook, and the webview has no permission for it.

```rust
// apps/myapp/src-tauri/src/main.rs
let result = tauri::Builder::default()
    .plugin(tauri_plugin_dialog::init())
    .manage(bridge::Bridge::new(requests))
    .invoke_handler(tauri::generate_handler![commands::control, commands::invoke_command])
```

```rust
// apps/myapp/src-tauri/src/services.rs
use tauri_plugin_dialog::DialogExt as _;

pub fn native(handle: AppHandle) -> Services {
    Services {
        // Called on the thread that owns the shell, never on the main thread: the dialog
        // plug-in's blocking calls wait for the main thread to show the dialog.
        pick_file: Some(Box::new(move |kind| {
            let dialog = handle.dialog().file().add_filter("MyApp document", &[myapp_format::EXTENSION]);
            // ...
        })),
    }
}
```

```json
{
  "identifier": "default",
  "windows": ["main"],
  "permissions": ["core:default"]
}
```

(`apps/myapp/src-tauri/capabilities/default.json`: the main window gets `core:default` and nothing
else.)

## Steps

1. **Add the crate to `[workspace.dependencies]`** in the root `Cargo.toml`, on the same major as
   `tauri`, and reference it from `apps/myapp/src-tauri/Cargo.toml` with `{ workspace = true }`:

   ```toml
   tauri = { version = "2", features = [] }
   tauri-build = { version = "2", features = [] }
   tauri-plugin-dialog = "2"
   ```

   The Tauri family moves together: keep `tauri`, `tauri-build` and every `tauri-plugin-*` on the
   same major version, and `@tauri-apps/api` in `apps/myapp/package.json` on the same minor as
   `tauri`. A plug-in belongs to the app binary only: never add it to a crate below it (the layer
   check rejects `tauri*` there).
2. **Check the licence** of the crate and everything it pulls in against the allowlist (MIT,
   Apache-2.0, BSD, ISC, OFL-1.1, CC0-1.0, CC-BY-4.0 and similar), and any npm package it needs. A
   bundled asset gets a row in `ATTRIBUTION.md`.
3. **Register it in `main.rs`**: `.plugin(<crate>::init())` on the `tauri::Builder` (check the
   plug-in's documentation for its exact initialiser and any extra setup).
4. **Call it from Rust behind a `Services` hook.** Add the hook to `Services` in
   `crates/shell/src/services.rs` as an `Option<Box<dyn FnMut(...)>>`, implement it in
   `apps/myapp/src-tauri/src/services.rs`, and let `menus::invoke` call it. The shell stays
   platform-free, tests fake the hook, and the commands that depend on it are disabled with a reason
   when it is `None`. See [add-ui.md](add-ui.md). If a call blocks (a dialog), it runs on the owner
   thread, never the main thread.
5. **Grant the webview a permission only if the frontend itself must call the plug-in.** Most plug-ins
   should not be reachable from the webview at all. If one must be: add only the specific permission
   it needs to `capabilities/default.json` (check the plug-in's documentation for the permission
   names), add its npm package (`@tauri-apps/plugin-<name>`, same major) and confine its import to
   `src/lib/backend.ts`, the only file that may import Tauri packages. Prefer wrapping it as a
   `Backend` method so components and their fakes (`fakeBackend` in `src/test-support.ts`) stay
   Tauri-free. Update the review checklist answer for "does the webview get a new permission".
6. **Keep the data path validated.** Everything that crosses from the webview or from the plug-in is
   input: check it in Rust like any other, and return errors, never panics.
7. **Test it.** The shell test with a fake hook (as `with_picker` in `crates/shell/src/tests.rs`),
   a component test if the frontend changed, then `cargo xtask ci`.
8. **Run the app.** `cargo xtask web` then `cargo run -p myapp` (or `npm run app`), and exercise the
   feature. This skill-set has not run any plug-in other than the dialog plug-in.

## A second window

A second window (an About box, a preview, embedded documentation) is created by the app binary
(`WebviewWindowBuilder`, check its documentation), opened through a `Services` hook so the shell
stays platform-free. Rules:

- Give it its own label and its own capability file listing only that label.
- **Which windows are open is data in `UiState`**, so `ui.inspect` lists them and automation can see
  them. Add the field as in [add-ui.md](add-ui.md).
- A window that shows your own frontend pages follows the same rules as the main window.
- **Any window that shows web content that is not your own UI** (a sign-in page, an HTML preview,
  embedded documentation) follows rule 6 (the webview gets the least it needs): no capabilities for
  it (remote content gets no IPC), a navigation allow-list, and for sign-in flows a preference for
  the system browser with a loopback or deep-link redirect. The main window never loads remote
  content. Load the `av-rust-desktop-grow` skill and follow its web-content pattern before building
  this.
- Keep the CSP in `tauri.conf.json` strict:
  `default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; connect-src ipc: http://ipc.localhost`.
  A change to it is a security change: review it like a new permission.

## Done when

`cargo xtask ci` passes, `cargo xtask layers` still shows no `tauri*` crate below the app, the
capability file grants nothing the frontend does not use, and the feature has been run in the
window.
