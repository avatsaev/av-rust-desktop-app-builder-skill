# Add a command

This is the most common change. A feature is not done until it is a command. Paths are inside the
project; `myapp` stands for the project's machine name (crate `myapp-engine`, test helper
`myapp-testkit`).

## Steps

1. **Choose the id.** `<area>.<verb>` in camelCase: `item.setDone`, `file.saveAs`. Ids are public
   API for scripts and agents. Never rename one after a release.
2. **Put the logic in the lowest crate that fits.** A domain algorithm belongs in an L2 crate with
   its own unit tests. The command only reads params, calls that code inside `Session::edit`, and
   shapes the result.
3. **Write the command** in `crates/engine/src/<area>_cmds.rs` (see the sample below). For a new
   module, add one `v.extend(crate::<area>_cmds::specs());` line to `build()` in
   `crates/engine/src/commands.rs` and a `mod <area>_cmds;` line in `crates/engine/src/lib.rs`.
4. **Follow the four habits** that keep commands safe:
   - Read params with the helpers in `params.rs`. A missing key is `None`; a wrong type is a
     `BadParams` that names the key.
   - Change the model only through `Session::edit`. The command is then one undo step and cannot
     half-apply.
   - Give `enabled` a reason that explains itself. It is the disabled menu item's tooltip and the
     error an agent reads.
   - Write the `params` string for a reader who has nothing else: types, defaults, units.
5. **Test it in the same module**: the behaviour, undo and redo, the disabled state, and bad params
   returning `Err` without recording a history step. The template's `item_cmds.rs` tests are the
   pattern (reproduced below).
6. **If it needs a value from the user**, decide where the value comes from. A command never opens
   UI, so it stays runnable from the CLI and by agents; the value always arrives as params.
   - *Typed or picked in the window* (a name, a number, a choice): the frontend component collects
     it and sends it as the params of `engine.execute`, for example
     `backend.control("engine.execute", { command: "item.add", params: { text } })`. The command
     then has `menu: &[]` and no shortcut, as `item.add` does in the template, because a menu
     click carries no text. See [add-ui.md](add-ui.md).
   - *Only the platform can ask* (a file path from a native dialog): `menus::invoke` in
     `crates/shell/src/menus.rs` asks through a `Services` hook and passes the answer as params.
     The command keeps its `menu` path and shortcut. See [add-ui.md](add-ui.md).
7. **Run `cargo xtask ci`.** `panic_hunt` covers the new command with no extra work (see below).

## The shape of a command

```rust
pub fn specs() -> Vec<CommandSpec> {
    vec![CommandSpec {
        id: "item.setText",
        label: "Rename Item",
        menu: &[],                                   // &["Item"] to appear in a menu
        shortcut: None,                              // Some("Cmd+R")
        params: r#"{"id": u64, "text": string}"#,
        enabled: has_doc,
        run: set_text,
    }]
}

fn set_text(s: &mut Session, p: &Value) -> Result<Value> {
    let (id, text) = (id_param(p)?, text_param(p)?);
    s.edit("Rename Item", |doc| if doc.set_text(id, text)? { Ok(()) } else { Err(no_item(id)) })?;
    Ok(Value::Null)
}
```

### `CommandSpec`

Defined in `crates/engine/src/commands.rs`:

```rust
/// Runs the command. Returns a JSON result; records at most one history step.
pub type Run = fn(&mut Session, &Value) -> Result<Value>;
/// `Err(reason)` when the command cannot run now. Shown as the disabled menu item's tooltip.
pub type Enabled = fn(&Session) -> std::result::Result<(), String>;

/// Metadata and implementation of one command.
pub struct CommandSpec {
    /// Stable, dotted, camelCase: `item.setDone`. Never renamed once released.
    pub id: &'static str,
    pub label: &'static str,
    /// Menu placement, e.g. `["Edit"]`. Empty = not in menus.
    pub menu: &'static [&'static str],
    /// Default shortcut (`Cmd+Shift+Z`); `Cmd` is Ctrl on Windows and Linux.
    pub shortcut: Option<&'static str>,
    /// What agents and scripts read: the params, their types and defaults.
    pub params: &'static str,
    pub enabled: Enabled,
    pub run: Run,
}
```

`Session::execute` finds the spec, checks the params are a JSON object (`null` becomes `{}`),
checks `enabled`, and runs `run` inside `catch_unwind`. The menu bar, shortcut table,
`myapp-cli commands` and `engine.commands` are all generated from the registry, so a spec with a
`menu` path gets its menu item, shortcut and tooltip with no UI code.

### `enabled` predicates

Two helpers in `commands.rs` cover most commands:

```rust
pub fn always(_: &Session) -> std::result::Result<(), String> {
    Ok(())
}

pub fn has_doc(s: &Session) -> std::result::Result<(), String> {
    s.active().map(|_| ()).ok_or_else(|| "no document open".to_string())
}
```

For anything else, write a private predicate next to the command. It returns the reason the command
cannot run now:

```rust
fn any_done(s: &Session) -> std::result::Result<(), String> {
    let d = s.active().ok_or("no document open")?;
    if d.doc.items.iter().any(|i| i.done) { Ok(()) } else { Err("no completed items".into()) }
}
```

### Reading params (`crates/engine/src/params.rs`)

A missing key (or `null`) is `None`; a key of the wrong type is `EngineError::BadParams` that names
the key and says what was found, for example `` `id` must be a non-negative integer, got a string``.
Nothing here indexes or unwraps.

| Helper | Returns |
|---|---|
| `str_param(p, key)` | `Result<Option<&str>>` |
| `req_str(p, key)` | `Result<&str>`; missing is `` `key` is required`` |
| `u64_param(p, key)` | `Result<Option<u64>>`; negative or fractional is an error |
| `req_u64(p, key)` | `Result<u64>` |
| `bool_param(p, key)` | `Result<Option<bool>>` |
| `kind(&Value)` | `"null"`, `"a boolean"`, `"a number"`, `"a string"`, `"an array"`, `"an object"` |

Wrap them in small local helpers when several commands share a parameter, and reject empty or
oversized values there:

```rust
fn id_param(p: &Value) -> Result<ItemId> {
    params::req_u64(p, "id").map(ItemId)
}

fn no_item(id: ItemId) -> EngineError {
    EngineError::BadParams(format!("no item with id {}", id.0))
}

fn text_param(p: &Value) -> Result<String> {
    let text = params::req_str(p, "text")?.trim();
    if text.is_empty() { Err(EngineError::BadParams("`text` is empty".into())) } else { Ok(text.to_string()) }
}
```

### Errors (`crates/engine/src/error.rs`)

```rust
pub enum EngineError {
    UnknownCommand(String),                 // "unknown command `{0}`"
    Disabled { id: String, reason: String },// "`{id}` is unavailable: {reason}" (what greys a menu item out)
    BadParams(String),                      // "bad params: {0}"
    Other(String),                          // "{0}"
}
pub type Result<T> = std::result::Result<T, EngineError>;
```

`From<myapp_doc::Invalid>` maps to `BadParams`, and `From<myapp_format::FormatError>` maps to
`Other`, so `?` works on both. An error says what was wrong and, where possible, what would be right.

## A complete small command module

`crates/engine/src/item_cmds.rs` in the template is the pattern; this is a two-command cut of it.
A command is a `specs()` list and one function per command.

```rust
use myapp_doc::ItemId;
use serde_json::{Value, json};

use crate::commands::{CommandSpec, has_doc};
use crate::{EngineError, Result, Session, params};

pub fn specs() -> Vec<CommandSpec> {
    vec![
        CommandSpec {
            id: "item.setDone",
            label: "Check Item",
            menu: &[],
            shortcut: None,
            params: r#"{"id": u64, "done": bool = toggle}"#,
            enabled: has_doc,
            run: set_done,
        },
        CommandSpec {
            id: "item.clearDone",
            label: "Clear Completed",
            menu: &["Item"],
            shortcut: Some("Cmd+Shift+K"),
            params: "{}",
            enabled: any_done,
            run: clear_done,
        },
    ]
}

fn any_done(s: &Session) -> std::result::Result<(), String> {
    let d = s.active().ok_or("no document open")?;
    if d.doc.items.iter().any(|i| i.done) { Ok(()) } else { Err("no completed items".into()) }
}

fn id_param(p: &Value) -> Result<ItemId> {
    params::req_u64(p, "id").map(ItemId)
}

fn no_item(id: ItemId) -> EngineError {
    EngineError::BadParams(format!("no item with id {}", id.0))
}

fn set_done(s: &mut Session, p: &Value) -> Result<Value> {
    let id = id_param(p)?;
    let want = params::bool_param(p, "done")?;
    let done = s.edit("Check Item", |doc| {
        let item = doc.item_mut(id).ok_or_else(|| no_item(id))?;
        item.done = want.unwrap_or(!item.done);
        Ok(item.done)
    })?;
    Ok(json!({"id": id.0, "done": done}))
}

fn clear_done(s: &mut Session, _: &Value) -> Result<Value> {
    let removed = s.edit("Clear Completed", |doc| {
        let before = doc.items.len();
        doc.items.retain(|i| !i.done);
        Ok(before - doc.items.len())
    })?;
    Ok(json!({"removed": removed}))
}
```

Everything above sits in one file, with its tests in a `#[cfg(test)] mod tests` at the bottom:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn session() -> Session {
        let mut s = Session::new();
        s.execute("file.new", json!({})).unwrap();
        s
    }

    fn texts(s: &Session) -> Vec<String> {
        s.snapshot().unwrap().items.iter().map(|i| format!("{}{}", if i.done { "x " } else { "" }, i.text)).collect()
    }

    // Behaviour, and each command undoing as exactly one step.
    #[test]
    fn check_and_clear_each_undo_as_one_step() {
        let mut s = session();
        let id = s.execute("item.add", json!({"text": "milk"})).unwrap()["id"].clone();
        assert_eq!(s.execute("item.setDone", json!({"id": id})).unwrap()["done"], true);
        assert_eq!(texts(&s), ["x milk"]);
        s.execute("item.clearDone", json!({})).unwrap();
        assert!(texts(&s).is_empty());
        for expected in [vec!["x milk"], vec!["milk"]] {
            s.execute("edit.undo", json!({})).unwrap();
            assert_eq!(texts(&s), expected);
        }
        s.execute("edit.redo", json!({})).unwrap();
        assert_eq!(texts(&s), ["x milk"]);
    }

    // Bad params are errors that record no history step.
    #[test]
    fn bad_params_are_errors_and_record_no_history() {
        let mut s = session();
        for (id, p) in [
            ("item.setDone", json!({"id": 99})),
            ("item.setDone", json!({"id": -1})),
            ("item.setDone", json!({"id": "1"})),
        ] {
            assert!(matches!(s.execute(id, p.clone()), Err(EngineError::BadParams(_))), "{id} {p}");
        }
        assert_eq!(s.active().unwrap().history.past_len(), 0);
    }

    // The disabled state: the command refuses until its precondition holds.
    #[test]
    fn clear_completed_is_disabled_until_something_is_done() {
        let mut s = session();
        let id = s.execute("item.add", json!({"text": "a"})).unwrap()["id"].clone();
        assert!(matches!(s.execute("item.clearDone", json!({})), Err(EngineError::Disabled { .. })));
        s.execute("item.setDone", json!({"id": id, "done": true})).unwrap();
        assert_eq!(s.execute("item.clearDone", json!({})).unwrap()["removed"], 1);
    }
}
```

The tests drive commands through `Session::execute`, the same entry point the window, the CLI and
the control channel use. `edit.undo` and `edit.redo` are commands, and `undo` is `Disabled` at the
start of history. `history.past_len()` is how a test proves no step was recorded.

## How `panic_hunt` covers the new command

`crates/engine/tests/panic_hunt.rs` runs every registered command with every value of
`myapp_testkit::adversarial_params()`. Each call runs on a fresh session on its own thread with a
10-second deadline, and a process-wide panic hook counts panics (because `Session::execute` would
otherwise turn a command's panic into an ordinary `Err` and hide it). The test is `#[ignore]`d so a
plain `cargo test` stays fast; the gate always runs it. Run just that test:

```sh
cargo test -p myapp-engine --test panic_hunt -- --ignored
```

A new command is picked up automatically. Extend two things only when needed:

- **`adversarial_params()` in `crates/testkit/src/lib.rs`**: when the command introduces a param
  name the list does not yet use, add it with hostile values (wrong types, extremes, empties,
  oversized strings, odd paths). The current list uses `id`, `text`, `done`, `path`, `title`,
  `filter` and `unknown`. Values include `-1`, `u64::MAX`, `1e300`, a 1 MiB string, a path with a
  NUL, a right-to-left override character, `[1]`, `{"a": 1}` and `null`.
- **`fresh()` in `crates/engine/tests/panic_hunt.rs`**: when the command is only reachable in some
  state, make `fresh()` produce it. The template's `fresh()` creates a document, adds an item and
  marks it done, so `item.clearDone` is enabled and its body is exercised:

  ```rust
  fn fresh() -> Session {
      let mut s = Session::new();
      s.execute("file.new", json!({"title": "hunt"})).unwrap();
      s.execute("item.add", json!({"text": "one"})).unwrap();
      s.execute("item.setDone", json!({"id": 1, "done": true})).unwrap();
      s
  }
  ```

  A command that is `Disabled` in the seed state is rejected before its body runs, so the fuzz
  would prove nothing about it.
