# A browser build

**Add it when:** You need the app to run in a browser tab as well as in the desktop window.

> `myapp` in paths stands for the project's machine name. Evidence: this whole pattern is *(reasoned)* from the architecture and Tauri's documented capabilities. No production app on this architecture is known to do it, it is not in the template, and it was not built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

The template has no browser app. The wasm check (`cargo xtask wasm`, over `doc ops format engine shell`) is what keeps one possible: it keeps OS assumptions out of the core. This pattern is *(reasoned)* throughout; nothing here was built.

- Add a third `Backend` implementation, beside `tauriBackend()` and `staticBackend(view)` in `apps/myapp/src/lib/backend.ts`. It is backed by the engine and the shell crate compiled to wasm32 and bound to JavaScript with wasm-bindgen: `control` calls `control::handle`, `invoke` calls `menus::invoke`, and `onView` calls its callback with the new view after each call that changed it.
- Choose the backend in `connect()`: `isTauri()` selects the desktop one, otherwise the wasm one when present, otherwise the static one.
- The glue is a small crate of its own (for example `apps/myapp-browser`, a binary-class crate registered `Class::Exempt` in `xtask/src/layers.rs` like the other apps) and is added to the targets that `cargo xtask wasm` checks. It holds the `AppShell` and nothing else; no logic.
- There are no threads: job-capable commands run inline (the `start` rule in [02](02-background-jobs.md)), and there is no owner-thread channel because one JS call runs to completion.
- File access goes through `Services` hooks the browser implements (a file input and a download); where one is missing, the feature is disabled, as in headless tests. File-system code in the core is already `cfg(not(target_arch = "wasm32"))`.
- The Tauri-only pieces (windows, single instance, updater, the control socket) do not exist in the browser; the engine and the shell crate do not know the difference.
- Keep the frontend rules: only `src/lib/backend.ts` knows how it reaches the engine.
- A page served over the web needs its own CSP and hosting review: it is a different security context from the desktop webview.

## Where it goes

Suggested homes: the Backend in `apps/myapp/src/lib/backend.ts` (the only file that knows how the frontend reaches the engine); the wasm-bindgen glue in `apps/myapp-browser/` (app class); the extra target in `cmd_wasm` in `xtask/src/main.rs`; the Vite build for the browser entry in `apps/myapp/`. If the glue crate is added, register it in `xtask/src/layers.rs`; wasm-bindgen is not in `UI_CRATES`, so the check allows it, but keep it out of L5 and below.

## How it fits the seams

- `Session::execute` and the registry are unchanged; the browser calls the same `control::handle` and `menus::invoke` the desktop reaches through its two commands.
- `Services` is what differs: a browser implementation of the file hooks, others missing and therefore disabled.
- `onView` stands in for the `view` event; the frontend still draws one value that equals `ui.inspect`.
- Without an owner thread, the single-threaded wasm module serialises calls itself; the control socket does not exist, so automation uses the desktop app or the CLI.

## Done when

- [ ] `cargo xtask wasm` builds the glue crate and the layered crates for wasm32.
- [ ] A component test passes the new backend (or a fake of it) and the same components work against all three implementations.
- [ ] Every file-system and platform feature is either a hook the browser provides or disabled with a reason.
- [ ] The page's CSP and hosting were reviewed separately from the desktop app's.

- [ ] You looked at a rendered image (`npm run snapshot`, in `apps/myapp`) of the changed UI.
- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
