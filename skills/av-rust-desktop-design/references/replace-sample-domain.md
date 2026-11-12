# Replacing the sample domain

The template is a checklist app: an `Item` with text and a done flag, a `Document` holding items,
and `item.*` commands. Replace it with the user's domain in the order below. `myapp` in paths
stands for the project's machine name.

**Rule: the tree builds and the gate, `cargo xtask ci` (eight steps: `fmt`, `web`, `clippy`,
`layers`, `test`, `panic_hunt`, `doctest`, `wasm`), passes after each step. Run it after each
one.** Never batch several steps and debug them together.

## The nine steps

### 1. The model: `crates/doc/src/lib.rs`

Replace `Item` and `Document` with your types. What the file holds today:

- `Item { id: ItemId, text: String, done: bool }` (`done` has `#[serde(default)]`),
- `ItemId(pub u64)`, a typed id, never reused within a document,
- `Document { title: String, items: Vec<Item> }` (`items` has `#[serde(default)]`),
- `Invalid`, the error enum: `TextTooLong { bytes }`, `TooManyItems`, `DuplicateId(ItemId)`, with a
  `Display` message for each,
- the caps `MAX_TEXT_BYTES` (64 KiB) and `MAX_ITEMS` (100,000),
- `Document::validate()`, which checks the title and every item's text against the caps, the item
  count against `MAX_ITEMS`, and ids for duplicates,
- mutators (`add_item`, `set_text`, `remove_item`) that check caps before changing anything, and
  derive a new id from the data (`max id + 1`, saturating) rather than from a stored counter.

Keep `validate()`, a cap on every size, typed ids, ids derived from the data, and
`#[serde(default)]` on fields added later. Keep tests like the two in the file: ids never collide
with loaded ones (including at `u64::MAX`), and oversized input is refused with no change.
Properties of the model crate: see [fixed-and-chosen.md](fixed-and-chosen.md).

### 2. The format: `crates/format/src/lib.rs`

Set `FORMAT` (the envelope's format name, `"myapp"` today) and `EXTENSION` (file extension without
the dot, `"myapp"` today). `VERSION` is 1 today. Know the rest of the file:

- `MAX_BYTES` is the largest file `decode` accepts (16 MiB); raise it only on purpose.
- `FormatError` has four variants: `TooLarge { bytes }`, `NotOurs(String)`, `Newer { found }` and
  `Invalid(String)`.
- `decode` reads the small `Head` (`format`, `version`) first, so a foreign or newer file is named
  as such, and only then parses the `Body` (`document`), runs `validate()` on it and returns it.
  Older versions migrate between those two steps: match on `head.version` and convert before
  validating.
- `encode` writes the envelope `{format, version, document}` as pretty JSON.

Update the round-trip test (build a model with non-ASCII text, encode, decode, compare) and the
hostile-file test (empty input, a foreign format name, a newer version, a missing body, a
duplicate id, an oversized file) for your model. If the app has no files, see "Is there a file?" in
[early-decisions.md](early-decisions.md).

### 3. The commands: `crates/engine/src/`

Replace `item_cmds.rs` with one `<area>_cmds.rs` module per area of your app. Each module has:

- a `pub fn specs() -> Vec<CommandSpec>` listing its commands, each with `id`, `label`, `menu`,
  `shortcut`, `params` doc string, `enabled` and `run`,
- one `fn(&mut Session, &Value) -> Result<Value>` per command, reading params through the
  `params` helpers and changing the model only through `Session::edit("Label", |doc| ...)`,
- tests for behaviour, undo, the disabled state and bad params.

Register each module with one `v.extend(crate::<area>_cmds::specs());` line in `build()` in
`crates/engine/src/commands.rs`, and add `mod <area>_cmds;` to `crates/engine/src/lib.rs`. Nothing
else needs wiring. Keep `edit_cmds.rs` (`edit.undo`, `edit.redo`), `file_cmds.rs` (`file.new`,
`file.open`, `file.save`, `file.saveAs`, `file.close`) and `query_cmds.rs` (`command.list`,
`document.inspect`).

Change `document.inspect` to return what an agent needs to see of your model. Today it returns
`title`, `items`, `revision`, `path`, `dirty`, `undo` (label) and `redo` (label), or `null` when
no document is open. Keep the bookkeeping fields (`revision`, `path`, `dirty`, `undo`, `redo`) and
replace `title` and `items` with your own. The frontend draws exactly this value as the view's
`document`, so step 5 mirrors it in TypeScript.

### 4. The fuzz seed

Every registered command is run with params nobody asked for; the seed state and the param names
decide how deep that goes.

- In `crates/engine/tests/panic_hunt.rs`, make `fresh()` build a small state that enables most
  commands. Today it is:

  ```rust
  fn fresh() -> Session {
      let mut s = Session::new();
      s.execute("file.new", json!({"title": "hunt"})).unwrap();
      s.execute("item.add", json!({"text": "one"})).unwrap();
      s.execute("item.setDone", json!({"id": 1, "done": true})).unwrap();
      s
  }
  ```

  (`unwrap` is acceptable in test code.) A command that is disabled in the seed state is never
  exercised past its `enabled` check, so seed a state in which as many commands as possible can
  run.
- In `crates/testkit/src/lib.rs`, put your commands' param names into `adversarial_params()`. It
  returns six objects today, built from the keys `id`, `text`, `done`, `path`, `title`, `filter`
  (and an `unknown` key): empty, wrong types, `u64::MAX`, `1e300`, a 1 MiB string, a path with a
  NUL byte, `..`, a right-to-left override character, and arrays and objects where scalars are
  expected. Add your keys to those values so each of your params sees wrong types, extremes,
  empties and oversized values.

The fuzz test is `#[ignore]`d so a plain `cargo test` stays fast; the gate always runs it
(`cargo test -p myapp-engine --test panic_hunt -- --ignored`).

### 5. The components: `apps/myapp/src/`

The frontend draws the view the shell sends and dispatches command ids; it holds no document state
and no business logic.

- Replace `components/Items.tsx` with your components. A component gets the data it draws as
  props plus a `Backend` (`control`, `invoke`, `onView`), reads the view, and calls
  `backend.control("engine.execute", {command, params})`. It never changes the document itself. A
  checkbox is a controlled input: `checked` is the document's state and `onChange` only asks for
  the change, so the box changes when the new view arrives. A component's styles live in a CSS
  Module beside it (`Items.module.css`). Replace `components/StatusBar.tsx`'s summary line (today
  "N of M left", plus "edited" when dirty) with yours; a failed command's reason arrives as
  `ui.status` and is shown there.
- Update `lib/types.ts`: its `DocumentView` and `Item` mirror what `document.inspect` returns
  (`title`, `items`, `revision`, `path`, `dirty`, `undo`, `redo` today). Change them in step with
  step 3. Ids are `u64` in Rust and JSON numbers here, exact only below 2^53.
- Set `MENU_ORDER` in `crates/shell/src/menus.rs` to your top-level menus (`["File", "Edit",
  "Item", "View"]` today). Commands appear in the menu named by their `menu` path, with their
  label, shortcut and enabled state; the frontend's `MenuBar.tsx` draws them from the generated
  data with no code of its own per command. `item.add` is not in a menu: the text is typed into
  the component.
- `menus::invoke` is where a menu click or a shortcut collects a value that only the platform can
  ask for before running a command: today `file.open` and `file.saveAs` get a path from the file
  dialog through `Services`, and `file.save` on a document with no file behaves as Save As. A value
  the user types or picks in the window travels as params of `engine.execute` instead.
- `needs_picker` in `menus.rs` lists the commands whose menu item first asks the user for a file
  (`file.open`, `file.saveAs`); such items are disabled, with a reason, when the app has no
  `pick_file` service. Update it if your file commands change.
- Colours come from `src/tokens.css` only (CSS custom properties, one block per theme);
  `tokens.test.ts` fails on a colour literal anywhere else. Add a token to every theme block, never
  a literal in a component.

### 6. UI state: `crates/shell/src/state.rs`, `control.rs`, `menus.rs`, `types.ts`

`UiState { theme, hide_done, status }` is one serde struct (`#[serde(default, rename_all =
"camelCase")]`). Replace `hide_done` with your view state (keep `theme` and `status`). Put in it
only what automation should see and set; what a widget needs only while on screen (the text being
typed, which menu is open) stays in the component. Then mirror the fields in three places:

- `control.rs` `set()`: one arm per field, which validates the value (type, and a size cap for
  strings) and returns an error naming the field. `set()` validates every field before applying any,
  so a refused request changes nothing. Today it handles `"theme"` and `"hideDone"` and refuses
  unknown fields. `ui.inspect` returns the whole view, with `UiState` in it, so new fields appear
  there without more work.
- `menus::UI_COMMANDS`: the shell commands that change only view state (`view.theme.dark`,
  `view.theme.light`, `view.hideDone` today). Each has `id`, `label`, `menu`, `run` and `checked`.
  They live in the shell, not the engine: they touch no model, record no history and mean nothing
  to the CLI. Give each piece of view state that a menu toggles one entry.
- `apps/myapp/src/lib/types.ts`: the `UiState` interface (`theme`, `hideDone`, `status` today), and
  `sampleView()` in `test-support.ts`.

### 7. The tests

Rewrite these against your commands. They are the pattern, not the content.

- `crates/shell/src/tests.rs`: headless shell tests in Rust, with no toolkit and no window: the view
  is the UI state, the document and the generated menu bar; a menu click runs a command as one undoable
  step; a failed command reaches the status bar and a success clears it; commands that need a file
  ask the service and a cancel changes nothing; without a file service the items are disabled and say
  why; the control protocol drives and inspects the app; requests from a channel are answered in
  order.
- `apps/myapp/src/**/*.test.{ts,tsx}`: component tests (vitest and `@testing-library/react` on jsdom) with
  a fake backend. `sampleView()` and `fakeBackend()` in `src/test-support.ts` give a view like the
  shell sends and a backend that records what the frontend asked for instead of running it; update
  `sampleView()` to your view. `App.test.tsx`, `components/Items.test.tsx` and
  `components/MenuBar.test.tsx` are the pattern; `lib/shortcuts.test.ts` and `tokens.test.ts` stay.
- `apps/myapp-cli/tests/cli.rs`: runs the built binary (a `run` that edits and saves a file, `info`
  reading it back, a failing command that exits 1 and saves nothing, and `commands --filter`) as
  a script or an agent sees it.

Also update the tests inside the engine modules you replaced.

### 8. Names and identity

Set the application id, the product name, the window title and the `--help` text. The scaffolding
script substitutes the placeholders for you; when editing by hand, this is what each means:

| Placeholder | Script option | Meaning | Appears in |
|---|---|---|---|
| `myapp` | `--name` | Machine name: the crate prefix (`myapp-engine`), the binaries, the file extension and the format name | Manifests, `use myapp_…`, `xtask/src/layers.rs`, `crates/format` |
| `MyApp` | `--title` | Product name in everything a user reads | Window title, `--help`, `apps/myapp/index.html`, messages |
| `MYAPP` | from `--name` | Environment variable prefix (`MYAPP_LOG`, `MYAPP_CONTROL_PORT`) | `apps/myapp/src-tauri/src/main.rs`, `logging.rs` |
| `com.example.myapp` | `--id` | Reverse-DNS application id | `apps/myapp/src-tauri/tauri.conf.json` |

By hand, also check:

- `apps/myapp/src-tauri/tauri.conf.json`: `productName`, `identifier` and the main window's `title`,
- `apps/myapp/index.html`: the `<title>`,
- the application icon: replace the placeholder with `npm run tauri icon <png>` (run in
  `apps/myapp`).

Use a domain you control for the id: it is how the desktop environment identifies the app, and
changing it after release orphans users' window state and file associations.

### 9. The documents

Update the files that still describe the sample:

- `README.md`: what the app is and how to run it.
- `AGENTS.md`: the workspace map, if crates were added, renamed or removed.
- `docs/control-protocol.md`: the `ui.set` fields (today `theme` and `hideDone`), and any command
  examples that name `item.*`.
- `docs/development.md`: the examples that use `item.add` and the sample file.
- `docs/architecture.md`: the decision record from [early-decisions.md](early-decisions.md).

## What you should not need to touch

`Session::execute` and `edit`, the registry, `ops::History`, the control protocol and server, the
crash guard, the services struct, `xtask`, the root manifest's lints and profiles, the webview
boundary (two Tauri commands and one event, `capabilities/default.json`, the CSP in
`tauri.conf.json`).

If a step seems to need a change to one of these, stop and ask whether the domain can be
expressed as commands and model data instead. (Registering a new crate in `xtask/src/layers.rs` is
the expected exception when you add a crate.)

## First real feature: your domain in place of the sample

Tick every item before calling the replacement done.

- [ ] The model replaced with your types, with `validate()` and a cap on every size
- [ ] `FORMAT` and `EXTENSION` set, or the file commands removed if the app has no files
- [ ] Round-trip and hostile-file tests updated for your model
- [ ] A command for every user action, each with tests for behaviour, undo, the disabled state and
      bad params
- [ ] `panic_hunt`'s seed state and the testkit's adversarial params updated for your commands
- [ ] The sample `item.*` commands and the items component removed
- [ ] `document.inspect` returns what an agent needs to see, and `types.ts` mirrors it
- [ ] Menus and shortcuts come from the registry; no key handling in components
- [ ] The UI checked from a rendered image (`npm run snapshot`), in both themes
