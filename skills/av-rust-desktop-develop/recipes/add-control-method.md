# Add a control method (or, rarely, a Tauri command)

Paths are inside the project; `myapp` stands for the project's machine name.

Prefer a new command. A command in the engine is available to every frontend at once (the
webview, the CLI, the control channel, tests). Add a control method only for something about the UI
state itself: inspecting or setting `UiState`, a dialog, a screenshot. Add a Tauri command almost
never (see the end of this page).

## Steps for a control method

1. Add an arm to `handle()` in `crates/shell/src/control.rs`, and the method name to `METHODS`.
2. Keep the rule that a request either applies completely or changes nothing: validate everything
   first, then apply.
3. Update `docs/control-protocol.md` in the same change: the method, its params and its result.
4. If the webview calls it or its result changes the view's shape, update
   `apps/myapp/src/lib/types.ts` (and `sampleView()` in `src/test-support.ts`).
5. Test it by calling `control::handle` directly (no socket).
6. Run `cargo xtask ci`.

## The protocol facts

`crates/shell/src/control.rs` is transport-free. The desktop app feeds it from the webview and from
a loopback socket (`apps/myapp/src-tauri/src/control_server.rs`); tests and the `view` example call
`handle` directly. The webview uses the same methods through the Tauri command `control`
(`Backend.control(method, params)` in `types.ts`). Four methods exist:

| Method | Does |
|---|---|
| `engine.execute {command, params?}` | Runs any command by id (shell commands too) |
| `engine.commands` | Lists the registry with what is enabled now and why not |
| `ui.inspect` | Returns the view: `{ui, document, menus, shellCommands}`, exactly what the frontend draws |
| `ui.set {theme?, hideDone?}` | Changes UI state; an unknown field is an error and nothing changes |

```rust
pub const METHODS: &[&str] = &["engine.commands", "engine.execute", "ui.inspect", "ui.set"];

/// `{"ok": true, "result": …}` or `{"ok": false, "error": "…"}`.
pub fn reply(result: Result<Value, String>) -> Value {
    match result {
        Ok(result) => json!({"ok": true, "result": result}),
        Err(error) => json!({"ok": false, "error": error}),
    }
}

/// Answer one control-protocol call.
pub fn handle(app: &mut AppShell, method: &str, params: &Value) -> Value {
    reply(match method {
        "engine.execute" => execute(app, params),
        "engine.commands" => app.run("command.list", Value::Null),
        "ui.inspect" => Ok(view(app)),
        "ui.set" => set(app, params),
        other => Err(format!("unknown method `{other}`; methods: {}", METHODS.join(", "))),
    })
}
```

Reply shape: `{"ok": true, "result": ...}` or `{"ok": false, "error": "..."}`. Over the socket each
line also carries the request `id`, the first line on a connection must authenticate, a request line
is at most 1 MiB, and an unanswered request gets `timeout: no reply in 60s` (see
`docs/control-protocol.md` and [../references/verify.md](../references/verify.md)).

`view` builds what the frontend draws and what `ui.inspect` returns:

```rust
pub fn view(app: &mut AppShell) -> Value {
    let shell: Vec<Value> = menus::UI_COMMANDS.iter().map(|c| json!({"id": c.id, "label": c.label, "checked": (c.checked)(app)})).collect();
    json!({
        "ui": app.ui,
        "document": app.session.execute("document.inspect", Value::Null).ok(),
        "menus": menus::model(app),
        "shellCommands": shell,
    })
}
```

A new top-level key in the view must be declared in `View` in `types.ts` and drawn by a component.

### Requests and threads

`AppShell::answer(&Request)` is the one entry for both sources. A `Request` is either
`Control { method, params }` (the only kind automation can send) or `Invoke { command }` (a menu
click or a shortcut; it may open a native dialog, so it is not on the socket). Each request is wrapped
in an `Envelope` with a reply channel and crosses one `std::sync::mpsc` channel to the owner thread,
which owns the `AppShell`. After each request the owner compares the view with the last one sent and
emits the `view` event if it differs. A new method therefore runs on the owner thread: it may use
`AppShell` freely but must not block for long (the asker waits at most 60 s).

## Validate everything, then apply

`set` is the model for any method that changes state: it clones the UI state, validates and applies
each field to the clone, and assigns the clone only if every field passed.

```rust
/// Validate every field, then apply them all: a bad request changes nothing.
fn set(app: &mut AppShell, params: &Value) -> Result<Value, String> {
    let fields = params.as_object().ok_or("`ui.set` takes a JSON object")?;
    let mut next = app.ui.clone();
    for (key, value) in fields {
        match key.as_str() {
            "theme" => next.theme = value.as_str().and_then(ThemeKind::from_name).ok_or("`theme` is `dark` or `light`")?,
            "hideDone" => next.hide_done = value.as_bool().ok_or("`hideDone` must be a boolean")?,
            other => return Err(format!("unknown field `{other}`")),
        }
    }
    app.ui = next;
    Ok(Value::Null)
}
```

Rules: errors say what was wrong; sizes are capped (everything the webview or a socket client sends
is hostile); unknown fields are errors; no `unwrap`. Method names are public API for scripts and
agents: never rename one after a release.

## Test it

Call `control::handle` directly, as `crates/shell/src/tests.rs` does:

```rust
#[test]
fn the_control_protocol_drives_and_inspects_the_app() {
    let mut app = app();
    let call = |app: &mut AppShell, method: &str, params: Value| control::handle(app, method, &params);
    let added = call(&mut app, "engine.execute", json!({"command": "item.add", "params": {"text": "eggs"}}));
    assert_eq!(added, json!({"ok": true, "result": {"id": 1}}));
    assert_eq!(call(&mut app, "ui.set", json!({"theme": "light", "hideDone": true}))["ok"], true);
    let seen = call(&mut app, "ui.inspect", Value::Null);
    assert_eq!(seen["result"]["ui"]["theme"], "light");
    assert_eq!(seen["result"]["document"]["items"][0]["text"], "eggs");
    assert_eq!(call(&mut app, "engine.execute", json!({"command": "view.theme.dark"}))["ok"], true, "shell commands run by id too");
    assert_eq!(app.ui.theme, ThemeKind::Dark);

    let before = app.ui.clone();
    let refused = call(&mut app, "ui.set", json!({"hideDone": false, "nope": 1}));
    assert_eq!(refused, json!({"ok": false, "error": "unknown field `nope`"}));
    assert_eq!(app.ui, before, "a refused ui.set changes nothing");
    assert_eq!(call(&mut app, "ui.nope", Value::Null)["ok"], false);
    assert_eq!(call(&mut app, "engine.execute", json!({"command": "item.delete", "params": {"id": 99}}))["error"], "bad params: no item with id 99");
    let listed = call(&mut app, "engine.commands", Value::Null);
    assert!(listed["result"].as_array().unwrap().iter().any(|c| c["id"] == "edit.redo" && c["enabled"] == false));
}
```

Test the refusal path of a new method too: a bad request must leave `app.ui` and the model
unchanged. The channel path is covered by `requests_from_a_channel_are_answered_in_order`, which
builds `Envelope::new(Request::Control { .. })` and calls `app.answer`, with no socket and no window.

To see the effect in a picture, put the call in `npm run snapshot`'s `--script` (a JSON array of
`[method, params]` pairs), or print the resulting view with
`cargo run -q -p myapp-shell --example view -- --script '[...]'`. See
[../references/verify.md](../references/verify.md).

## Adding a Tauri command (almost never)

The webview boundary is two Tauri commands and one event, and that is deliberate: the less the
webview can call, the less to validate. Before adding a third, check that none of these fits:

- a new **engine command** (every frontend gets it, and `engine.execute` already reaches it);
- a new **control method** (above), which the webview already reaches through `control`;
- a **`Services` hook** for something only the platform can do (see [add-ui.md](add-ui.md)).

If a Tauri command is still needed:

1. Put it in `apps/myapp/src-tauri/src/commands.rs`, which holds nothing but such commands. It has
   `#![allow(clippy::unreachable)]` because `#[tauri::command]` generates code that names
   `unreachable!`; that is why nothing else may live there.
2. It forwards a new `Request` variant (`crates/shell/src/control.rs`) to the owner thread through
   `Bridge::ask`, and `AppShell::answer` handles the variant. It never touches the session
   directly: one thread owns the `Session`, so a click and an automation request can never race.
3. Register it in `generate_handler!` in `apps/myapp/src-tauri/src/main.rs`.
4. Add the call to `Backend` and `tauriBackend()` in `src/lib/backend.ts` (the only file that imports
   `@tauri-apps/api`), and a fake in `fakeBackend` in `src/test-support.ts`.
5. Validate every argument in Rust like any other input.
6. Update `docs/control-protocol.md`, add a shell test, and run `cargo xtask ci`.

The existing two commands, for the shape:

```rust
/// A control-protocol call: the same four methods automation uses.
#[tauri::command]
pub async fn control(bridge: State<'_, Bridge>, method: String, params: Option<Value>) -> Result<Value, String> {
    bridge.ask(Request::Control { method, params: params.unwrap_or(Value::Null) }).await
}

/// A menu click or a shortcut.
#[tauri::command]
pub async fn invoke_command(bridge: State<'_, Bridge>, command: String) -> Result<Value, String> {
    bridge.ask(Request::Invoke { command }).await
}
```

```rust
.invoke_handler(tauri::generate_handler![commands::control, commands::invoke_command])
```

The template's `capabilities/default.json` grants the main window only `core:default`; do not widen
it for a command of the app's own. If you are unsure how Tauri treats a new command's permissions,
check its current documentation and run the app to confirm (see
[add-tauri-plugin.md](add-tauri-plugin.md)).
