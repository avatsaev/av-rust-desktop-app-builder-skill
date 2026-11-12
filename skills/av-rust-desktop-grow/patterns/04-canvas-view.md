# A canvas view inside the UI

**Add it when:** One widget needs more drawing than HTML and SVG do smoothly: a canvas, viewport, plot or large graph.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

Not at first. The DOM, SVG and CSS draw shapes, text, images, plots and tables well enough for most panels. Add a canvas view when one widget must draw more than they can per frame. *(reasoned)* Two routes; pick one per widget:

**Route A: draw in the webview.** *(reasoned)*

- Draw with a `<canvas>` in a component, fed with data from Rust (query commands for the visible range, not the whole model).
- WebGL2 is the baseline. WebGPU is not in every platform webview (WebView2, WKWebView and WebKitGTK differ), so do not depend on it; check the current state on each engine you ship.
- The component draws what it is sent and sends command ids for edits; pan and zoom that only change what is visible can be component-local state, while anything automation should see belongs in `UiState`.

**Route B: render in Rust and ship frames or tiles.** *(reasoned)*

- Render on the CPU, or on the GPU offscreen with `wgpu`, in an L3 crate that depends on `wgpu` and on no webview crate. The layer check allows this: `wgpu` is deliberately not in its `UI_CRATES` list (tauri, wry, tao, muda, the webview bindings and the other windowing and dialog crates), which forbids windows and webviews below L6, not the GPU.
- Send the frames or tiles to the webview as binary through a custom URI scheme protocol or a raw IPC response, never as JSON in the view (see [03](03-large-data.md)).

Either route (engine-side lessons, proven in a large production app with a native UI toolkit):

- Keep a CPU implementation as the reference and test the GPU or WebGL one against it within a tolerance, on a software adapter in CI.
- Handle device loss: check a health flag where the GPU is used and switch to the CPU path for the rest of the session.
- Guard startup on the Rust GPU path: before creating the device, write a marker file and clear it once the first frames are on screen. A launch that finds the marker knows the previous start died inside the graphics driver, and starts with a safer backend (for example the CPU path).
- Where no GPU adapter exists (headless tests, a browser build), fall back to the CPU path.

## Where it goes

Suggested homes: Route A: a component in `apps/myapp/src/components/` plus range-query commands in L5 `engine`. Route B: the renderer in `crates/gpu` (L3, no webview crate; register it in `xtask/src/layers.rs`, and add an intra-layer ordering entry in `INTRA_LAYER_ORDER` if it reuses a CPU renderer in the same layer), the startup marker in `apps/myapp/src-tauri/src/gpu_startup.rs` (app, platform code), the scheme handler in `apps/myapp/src-tauri/src/`. GPU tests that need an adapter can be grouped in a nextest `gpu` group so they run serially. Register any new crate in `xtask/src/layers.rs`; `cargo xtask layers` fails on an unregistered crate.

## How it fits the seams

- The renderer or the canvas data source reads an immutable snapshot keyed by the revision counter; it never mutates the model.
- Both routes keep the two-command boundary: the canvas component edits through `engine.execute` or `backend.invoke`, and pixels or tiles travel on a separate binary route, not in the `view` event.
- Which backend is active (WebGL2, Rust renderer, CPU) is a candidate field in `UiState`, so `ui.inspect` reports it. *(reasoned)*
- The CPU path keeps headless tests, the CLI and a browser build working without a GPU.

## Done when

- [ ] A test compares the GPU or WebGL output with the CPU reference within a tolerance on a software adapter.
- [ ] Fallback to CPU works with no adapter and after simulated device loss.
- [ ] (Route B) `cargo xtask layers` passes with the L3 crate registered, `wgpu` outside `UI_CRATES`, and no webview crate below L6.
- [ ] (Route B) The startup marker is written before device creation and cleared after the first frames; a present marker selects the safer backend.
- [ ] No large payload travels in the view JSON.
- [ ] You tested the canvas on each webview engine you ship (WebView2, WKWebView, WebKitGTK).

- [ ] You looked at a rendered image (`npm run snapshot`, in `apps/myapp`) of the changed UI.
- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
