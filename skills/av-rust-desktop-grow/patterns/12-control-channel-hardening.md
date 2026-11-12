# Hardening the control channel

**Add it when:** The control channel leaves your own machine's test runs.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

The baseline is the template's control server (`apps/myapp/src-tauri/src/control_server.rs`), which already has these properties:

- it binds loopback only (`127.0.0.1`), never another interface, and binds before the window opens so a port in use is a startup error;
- the first line must authenticate with `{"method": "auth", "params": {"token": "<64 hex>"}}`; nothing is dispatched before it, and a wrong token closes the connection;
- the token comparison takes the same time wherever two tokens differ;
- a request line is bounded (`MAX_REQUEST_BYTES`, 1 MiB); a longer one is an error, not an allocation;
- a token file (`--control-token-file`, `MYAPP_CONTROL_TOKEN_FILE`) is created readable by its owner only, with a fresh random token when missing;
- a reply deadline of 60 seconds.

Harden it further:

- **Challenge authentication.** The token never crosses the socket (HMAC over nonces), and the server proves it holds the token before the client reveals anything derived from it.
- **A deadline to authenticate**, and a limit on simultaneous connections.
- **Two different timeouts.** A request never dispatched says `timeout: not run` and is safe to re-send; `timeout: no reply in 60s` means it may still be running.
- **A preference that turns agent control off.**

The webview side of golden rule 6 *(reasoned)*: the socket and the webview reach the same owner thread, so keep the webview's reach as small as the socket's.

- `invoke_command` (which may open a native dialog) stays off the socket; a new control method is added to `METHODS` only after its inputs are validated like any request.
- The main window's capability stays `core:default` and its CSP strict; hardening the socket does not widen either.
- Everything the webview sends is validated in Rust, exactly as socket input is.

## Where it goes

Suggested homes: `crates/automation/src/security.rs` (L6, challenge/HMAC logic as pure code), `apps/myapp/src-tauri/src/control_server.rs` (app: sockets, deadlines, connection limit), `apps/myapp/src-tauri/src/bridge.rs` (the 60 s reply deadline and the `timeout:` messages), and `docs/control-protocol.md`. If you add `crates/automation`, register it in `xtask/src/layers.rs`. Keep `SECURITY.md` in step.

## How it fits the seams

- The control channel is seam 5: socket threads only parse and forward over a channel to the owner thread, so automation never races the user or the webview; hardening changes only the socket layer, not `control::handle`.
- The off switch is a preference (see [06](06-preferences.md)).
- Tests and the `view` example still call the handler directly, with no socket.

## Done when

- [ ] Tests: no dispatch before auth, wrong token closes, overlong request refused (as in the template) plus: authentication deadline, connection limit, both timeout messages.
- [ ] The token never appears on the wire in challenge mode; the server proves possession first.
- [ ] Turning the preference off refuses control connections.
- [ ] `docs/control-protocol.md` and `SECURITY.md` updated; `capabilities/default.json` and the CSP unchanged.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
