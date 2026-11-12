# Dialogs

**Add it when:** Commands need parameters from the user.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

A command with parameters gets a dialog that edits a pending copy of its params and calls `execute` once on OK.

Hold open dialogs as data in `UiState`, with their field values in that data. `ui.inspect` then lists them, and control methods (`ui.dialog.open`, `ui.dialog.set`, `ui.dialog.confirm`, `ui.dialog.cancel`) let automation drive them like a person would.

In the webview:

- The frontend draws each open dialog from the view as a modal component and sends field changes and OK or cancel through the control methods. *(reasoned)*
- A field commits its value on change (blur or Enter), not per keystroke, so the owner thread and the view are not hit on every key. *(reasoned)*
- Native file and message dialogs stay behind `Services` and are shown from Rust on the owner thread, as the template does for file pickers; the webview gets no dialog permission. *(reasoned for message dialogs; the file picker is how the template works)*
- Contrast with the template's rule: a value a widget needs only while it is on screen (the text being typed in the new-item box, which menu is open) stays in the component; dialog fields are in `UiState` precisely because automation must set them.

## Where it goes

Suggested homes: the dialog data in `crates/shell/src/state.rs` (`UiState`), the control arms in `crates/shell/src/control.rs` (add each method name to `METHODS`; a request either applies completely or changes nothing, as `ui.set` does), the modal components in `apps/myapp/src/components/` with their types in `apps/myapp/src/lib/types.ts`. Document the methods in `docs/control-protocol.md` and the dialogs in a `docs/ui-dialogs.md`. No new crate.

## How it fits the seams

- The dialog's only effect is one `execute(id, params)` call on OK; cancel changes nothing.
- Dialog state is part of the one serde `UiState`, so `ui.inspect` shows it and `ui.set`-style validation applies (validate every field, then apply).
- The `ui.dialog.*` methods are control methods about the UI itself, which is the case where a control method (not a command) is right. They go over the same two Tauri commands and the same socket, and the `view` event redraws the modal.

## Done when

- [ ] A shell test opens, sets fields, confirms and cancels through `control::handle` (no socket, no window).
- [ ] Confirm calls `execute` exactly once; cancel leaves the model untouched; a bad field value changes nothing.
- [ ] A component test (fake backend) draws the modal from a view and sends the right calls.
- [ ] New control methods are in `METHODS` and documented in `docs/control-protocol.md`.

- [ ] You looked at a rendered image (`npm run snapshot`, in `apps/myapp`) of the changed UI.
- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
