# Web content in its own webview window

**Add it when:** The app must show web content that is not its own UI: an OAuth sign-in page, an HTML preview, embedded documentation.

> `myapp` in paths stands for the project's machine name. Evidence: this whole pattern is *(reasoned)* from the architecture and Tauri's documented capabilities. No production app on this architecture is known to do it, it is not in the template, and it was not built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

Treat remote or foreign content as hostile and give it nothing. Everything here is *(reasoned)*: name the Tauri feature, read its current documentation before coding against it.

**Open it as a second window, never in the main one.**

- The app binary opens the page as a second webview window (`WebviewWindowBuilder`) with its own label. The main window never loads remote content (golden rule 6).
- The window is opened through a `Services` hook, so the shell crate stays platform-free and tests can fake the hook. Where the hook is missing (headless tests, a platform without it), the menu item or command that needs it is disabled with a reason, not broken.

**Give it no capabilities.**

- `apps/myapp/src-tauri/capabilities/default.json` lists `"windows": ["main"]`. Never add the new window's label to it, and never write a capability that matches the new label or a wildcard. Remote content gets no IPC.
- Never inject the app's IPC (the two commands, the `view` event, any init script that exposes them) into a remote page. The page cannot call `control` or `invoke_command`, and the app learns nothing from the page except through channels you designed and validate.
- Anything that does come back (a redirect URL, a code or token) is validated in Rust like any other input: bounded, parsed strictly, and refused if malformed.

**Restrict where it can go.**

- Set a navigation allow-list on the window: the origins the page may load and navigate to. Refuse every other navigation, including redirects to other hosts and new-window requests.
- Allow `https` origins only, unless the feature is a local file served by the app itself.

**Sign-in flows: prefer the system browser.**

- Open the identity provider's page in the user's own browser (`tauri-plugin-opener`), where password managers, passkeys and the user's existing sessions work and the app never sees the credentials.
- Receive the result through a loopback redirect (bind `127.0.0.1` on a random port, as the control server does) or a deep link (`tauri-plugin-deep-link`). Validate the state parameter, accept one response, then close the listener.
- Use an embedded window for sign-in only when the provider requires it, and then with the capability-free, allow-listed window above.

**Local HTML (a preview, bundled documentation).**

- Serve it from the app, not from the network (a custom URI scheme protocol, or a file bundled with the frontend), and give that window its own, stricter CSP than the main window's: no inline script, no remote origins, no `connect-src`.
- Render untrusted HTML in a sandboxed context that cannot reach the app's IPC. Sanitise before display; never assemble HTML from untrusted strings in a component.

**Windows are data.**

- Which windows are open (label, purpose, address, state) is a field in `UiState`, so `ui.inspect` lists them and automation can open and close them through control methods or commands, like dialogs in [05](05-dialogs.md).
- Opening a window is a command (`window.open`-style id) whose `run` records the intent in state; the app binary's `Services` hook does the platform work. Closing it from the OS updates the state through the owner thread.

## Where it goes

Suggested homes: the window state in `crates/shell/src/state.rs` (`UiState`), the hook type next to `PickFileFn` in `crates/shell/src/services.rs` (L6, no platform code), the command in `crates/engine/src/*_cmds.rs` or a shell command in `crates/shell/src/menus.rs`, the implementation (`WebviewWindowBuilder`, the allow-list, the opener, the deep-link or loopback listener) in `apps/myapp/src-tauri/src/services.rs` or a new module beside it, and any panel that lists the windows in `apps/myapp/src/components/`. `capabilities/default.json` and the CSP in `tauri.conf.json` stay as they are unless you are adding a deliberately scoped capability for a window you wrote. Update `SECURITY.md` and the permissive-licence check for any new plug-in. No new crate required; register any you add in `xtask/src/layers.rs`.

## How it fits the seams

- The hook is a `Services` entry filled in by the app binary, so the shell stays toolkit-free and tests inject a fake that records the call.
- Window state is in `UiState`; `ui.inspect` returns it and the frontend draws it from the `view` event, so what a person sees is what an agent reads.
- The platform work runs on the owner thread behind the hook, like the template's file dialog; results coming back from a page or a browser redirect re-enter as a `Request` on the same channel and are applied as one command.
- The two-command boundary is untouched: the new window gets no way into it.

## Done when

- [ ] The new window's label appears in no capability file; `capabilities/default.json` still lists only `main`.
- [ ] No IPC or init script is injected into the new window.
- [ ] The navigation allow-list refuses off-list origins, redirects and new-window requests (tested where the platform allows it, and the allow-list function itself unit-tested).
- [ ] Sign-in opens the system browser; the redirect is validated, one-shot, and bound to loopback.
- [ ] Local HTML has its own strict CSP; the main window's CSP is unchanged.
- [ ] A shell test with a fake hook opens and closes a window through `control::handle` and checks the state in `ui.inspect`.
- [ ] The feature is disabled with a reason when the hook is missing.
- [ ] You tested on each webview engine you ship.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
