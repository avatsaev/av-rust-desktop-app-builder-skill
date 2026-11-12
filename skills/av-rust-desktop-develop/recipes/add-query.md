# Add a query

A query is a command that only reads. It returns JSON and never calls `Session::edit`, so it
records no history step. Paths are inside the project; `myapp` stands for the project's machine
name.

Queries are what agents call first, so make them complete: an agent cannot look at the screen.
`document.inspect` should return everything an agent needs to know about the model and its state.

## Steps

1. Choose the id like any command (`<area>.<verb>` in camelCase) and follow
   [add-command.md](add-command.md). Put it in `crates/engine/src/query_cmds.rs` or a module of its
   own.
2. Use `enabled: always` for a query that does not need a document, `enabled: has_doc` for one that
   does.
3. Read params with the helpers in `params.rs`; build the result with `json!`.
4. Do not call `Session::edit`. Take what you need from `s.active()` or `s.snapshot()`.
5. Test it: the result for a fresh document, the result after a change, and bad params.

## The pattern: `command.list` and `document.inspect`

`crates/engine/src/query_cmds.rs` in the template:

```rust
//! Read-only commands: what agents call first to learn what exists and what state it is in.

use serde_json::{Value, json};

use crate::commands::{CommandSpec, always, command_specs, has_doc, list_entry};
use crate::{Result, Session, params};

pub fn specs() -> Vec<CommandSpec> {
    vec![
        CommandSpec {
            id: "command.list",
            label: "List Commands",
            menu: &[],
            shortcut: None,
            params: r#"{"filter": string = ""}"#,
            enabled: always,
            run: command_list,
        },
        CommandSpec { id: "document.inspect", label: "Inspect Document", menu: &[], shortcut: None, params: "{}", enabled: has_doc, run: inspect },
    ]
}

fn command_list(s: &mut Session, p: &Value) -> Result<Value> {
    let needle = params::str_param(p, "filter")?.unwrap_or("").to_lowercase();
    let rows = command_specs().iter().filter(|c| c.id.to_lowercase().contains(&needle) || c.label.to_lowercase().contains(&needle));
    Ok(Value::Array(rows.map(|c| list_entry(s, c)).collect()))
}

fn inspect(s: &mut Session, _: &Value) -> Result<Value> {
    let Some(d) = s.active() else { return Ok(Value::Null) };
    Ok(json!({
        "title": d.doc.title,
        "items": d.doc.items,
        "revision": d.revision,
        "path": d.path,
        "dirty": d.dirty(),
        "undo": d.history.undo_label(),
        "redo": d.history.redo_label(),
    }))
}
```

Notes on the pattern:

- `command.list` returns one row per command: `id`, `label`, `menu`, `shortcut`, `params`,
  `enabled` and `reason` (why not, when disabled). `list_entry` in `commands.rs` builds each row.
  `myapp-cli commands` and the control method `engine.commands` both call it.
- `document.inspect` returns the model plus `revision`, `path`, `dirty` and the undo and redo
  labels. It returns `null` when no document is open. `ui.inspect` embeds its result as the
  `document` of the view, which is what the frontend draws: every field you add is serialised on
  every change, so keep the result small.
- Keep the query cheap: use the snapshot, never lock or clone large payloads.

## Checks

- `cargo test -p myapp-engine --lib --tests`
- `cargo test -p myapp-engine --test panic_hunt -- --ignored` (queries are fuzzed like any command)
- Try it from outside:
  `cargo run -q -p myapp-cli -- run list.myapp --cmd document.inspect`
