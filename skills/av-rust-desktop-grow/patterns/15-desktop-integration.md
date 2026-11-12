# Desktop integration

**Add it when:** Before the first release.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

Each of these is app-binary code and Tauri configuration or plug-ins, behind `cfg(target_os)` where it differs. All are *(reasoned)*: name the Tauri feature, then read its current documentation before coding.

- A native menu bar generated from the same `menus::model` data as the in-window menu (`tauri::menu`); items dispatch command ids.
- One running instance that receives the files a second launch was asked to open (`tauri-plugin-single-instance`).
- File associations (`bundle.fileAssociations` in `tauri.conf.json`) and the application icon (`npm run tauri icon <png>` generates the set that `bundle.icon` lists; replace the template's placeholder icon).
- A log file in the settings directory; the template already has `apps/myapp/src-tauri/src/logging.rs`, so extend it.
- Update checks (`tauri-plugin-updater`).
- A tray icon, if the app lives in the background.

Related packaging facts: macOS bundles need real signing and notarization; ad-hoc signing is for local testing only, because Gatekeeper rejects it on other Macs. Windows needs the WebView2 runtime. The earlier native-shell packaging linked the C runtime statically (`+crt-static`) so no redistributable was needed; check whether that still holds with the Tauri bundler.

## Where it goes

Suggested homes: `apps/myapp/src-tauri/src/` (all platform code lives in the app binary), `apps/myapp/src-tauri/tauri.conf.json` and `apps/myapp/src-tauri/icons/`. No new crate, but if an OS integration needs `unsafe`, isolate it in its own small crate, e.g. `crates/<os-integration>`, and register it in `xtask/src/layers.rs`. Any plug-in you add also adds permissions: add only what it needs, never to the main window's capability unless the webview must call it (see golden rule 6).

## How it fits the seams

- The native menu is generated from the registry data, so it needs no hand-written command list; items go to the owner thread like a menu click (`invoke_command` semantics).
- Files passed to a second launch reach the first instance and open through the normal open command on the owner thread.
- Everything OS-specific stays behind `Services` hooks or in the app binary; a missing hook disables the feature, it does not break.

## Done when

- [ ] Each piece is `cfg(target_os)`-gated where needed; the core and the wasm check are unaffected (`cargo xtask wasm`).
- [ ] The placeholder icon is replaced, and the icon, file association and metadata are present on every platform you ship.
- [ ] A second launch hands its files to the running instance (tested on each platform).
- [ ] Capabilities were reviewed after adding each plug-in.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
