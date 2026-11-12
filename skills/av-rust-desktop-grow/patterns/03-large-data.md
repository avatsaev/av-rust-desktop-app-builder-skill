# Large data

**Add it when:** Cloning the model is no longer cheap.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

Engine side:

- **Share, don't copy.** Hold every large payload in the model behind `Arc`, so a snapshot copies pointers.
- **Chunk what is edited in place.** For pixels, samples or big tables, store fixed-size chunks behind `Arc` and mutate with `Arc::make_mut`: an edit copies only the chunks it touches, and the undo history shares the rest. Example for raster data: sparse planes of 256×256 tiles, where a missing tile reads as the default value.
- **Never scan everything on every change.** Cache derived data keyed by the revision counter.
- **Budget memory.** Cap resident chunks and spill cold ones to scratch files (native only).

At the webview boundary: the whole view is serialised to JSON on every change, so it must stay small.

- **Never serialise large data into the view.** Send a window, a page or a summary instead. *(reasoned)*
- Add query commands for ranges (for example rows 200 to 260), and virtualise long lists in the frontend so only visible rows are drawn. *(reasoned)*
- Move binary payloads (images, buffers) through a custom URI scheme protocol or a raw IPC response instead of JSON. *(reasoned)* Check Tauri's current documentation for both, and keep the CSP in `tauri.conf.json` as strict as the chosen route allows.

## Where it goes

Suggested homes: a storage-container crate at L0, e.g. `crates/<storage>` (the layer table puts storage containers with no domain model in L0); the model in L1 `doc` holds the `Arc`s; range queries as commands in `crates/engine/src/*_cmds.rs`; windowing in `crates/shell/src/control.rs` (`view`); virtual-list components in `apps/myapp/src/components/`; a custom URI scheme handler, if used, in `apps/myapp/src-tauri/src/` (platform code). Document the scratch-file behaviour in `docs/`. Spill-to-disk code is `cfg(not(target_arch = "wasm32"))`. Register any new crate in `xtask/src/layers.rs`; `cargo xtask layers` fails on an unregistered crate.

## How it fits the seams

- Cheap clones are what make immutable snapshots work: `Session::edit` clones the model into a private copy, and large payloads behind `Arc` make that a pointer copy.
- Undo and redo swap pointers and share unchanged chunks.
- The revision counter is the cache key for derived data, and a cheap way to tell the owner thread the view changed.
- Range and page queries are registry commands, so the frontend, the CLI and agents read large data the same way. The view stays what `ui.inspect` returns, and stays small.

## Done when

- [ ] A test shows an edit copies only the touched chunks (the others stay shared `Arc`s).
- [ ] No per-request full scan; derived caches are keyed by revision.
- [ ] Hostile input cannot force unbounded allocation (caps checked).
- [ ] A shell test shows the serialised view stays under a chosen size for a large document.
- [ ] Range queries have tests, including out-of-range and oversized requests (errors, not crashes).
- [ ] The core still builds for wasm32.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
