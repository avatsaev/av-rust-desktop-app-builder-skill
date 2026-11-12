# Several open documents

**Add it when:** The app has tabs or more than one file open.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

The template's `Session` holds one model. For tabs or several open files (engine side, unchanged by the shell):

- Hold a list of open document states and an active index in `Session`.
- Keep commands calling `Session::active()`; add commands to switch and close documents.
- Give each document a stable id (a `DocId`), so that a background job can find its target again after the user switches tabs.

In the webview:

- Tabs are data in the view: have `control::view` add the list of open documents (id, title, dirty, which is active) next to `document`, which stays the active document. The frontend draws a tab strip from it and sends the switch and close command ids; it holds no document list of its own. *(reasoned)*
- Ids are `u64` in Rust and JSON numbers in the webview, exact only below 2^53. A `DocId` crossing the boundary must stay below that; a larger one is an error, not a crash.

## Where it goes

Suggested homes: `crates/engine/src/session/documents.rs` (L5, `engine`; turn `session.rs` into a module directory if it is not one). The id type can live next to the model in L1 `doc`. The tab list in the view: `crates/shell/src/control.rs` (`view`); the types in `apps/myapp/src/lib/types.ts`; the tab strip as a component in `apps/myapp/src/components/`. No new crate, so nothing to register.

## How it fits the seams

- `Session::execute` and the registry do not change: commands still ask `Session::active()` for their target.
- Switch and close are ordinary commands with ids, params docs, `enabled` and tests; the tab strip dispatches them through `backend.invoke` or `engine.execute`.
- Each document keeps its own immutable snapshot, history and revision counter; a job or autosave holds a snapshot and finds its document by `DocId`.
- The owner thread owns all documents; a switch changes what the next `view` event carries, so `ui.inspect` shows the same tabs a person sees.

## Done when

- [ ] Open, switch and close are commands with tests, including closing the last document.
- [ ] A job started on one document still lands on it after switching tabs (test with a stable id).
- [ ] A shell test checks the view lists the open documents and the active one.
- [ ] A component test (fake backend) draws the tabs and dispatches switch and close.
- [ ] Existing single-document commands pass unchanged.
- [ ] You looked at a rendered image (`npm run snapshot`, in `apps/myapp`) of the changed UI.
- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
