# An MCP server for agents

**Add it when:** Agents should use the app as a tool.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

An L6 `automation` crate beside `shell`, built on `rmcp` and `tokio`, exposes the registry as MCP tools: list commands, run one, run a batch, plus document open, save, inspect and render.

It runs in two modes:

- headless over stdio: `myapp-cli mcp`,
- bridged to a running window through the control channel: `myapp-cli mcp --bridge 127.0.0.1:<port>`.

File access for agents goes through explicitly granted read and write roots (`cap-std`).

Keep the async runtime out of the engine: confine `tokio` to the automation crate and the CLI; the engine and the shell crate stay synchronous.

## Where it goes

Suggested homes: `crates/automation` (L6, beside `shell`), the `mcp` subcommand in `apps/myapp-cli`, and `docs/mcp.md`. The `rmcp`, `tokio` and `cap-std` dependencies must pass the licence allowlist. Register any new crate in `xtask/src/layers.rs`; `cargo xtask layers` fails on an unregistered crate.

## How it fits the seams

- Tools map onto `engine.commands` and `engine.execute`; nothing is reimplemented.
- Bridge mode speaks the control protocol to the running app's loopback socket, which forwards to the owner thread; headless mode drives `Session::execute` directly.
- Anything an agent changes reaches the open window as a normal `view` event, so a person sees what the agent did.
- Harden the control channel before agents use it over anything but local test runs (see [12](12-control-channel-hardening.md)).

## Done when

- [ ] Tests list tools, run a command and a batch, and reject paths outside the granted roots.
- [ ] Both modes work (stdio headless and `--bridge`).
- [ ] `tokio` appears in no crate below L6 (`cargo xtask layers`).
- [ ] `docs/mcp.md` documents both modes.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
