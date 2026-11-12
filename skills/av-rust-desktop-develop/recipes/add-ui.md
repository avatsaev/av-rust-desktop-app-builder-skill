# Add UI, a keyboard shortcut or a menu item

Paths are inside the project; `myapp` stands for the project's machine name. The UI is a React 19 +
TypeScript frontend in `apps/myapp/src`, drawn in the platform webview by Tauri 2. It is thin: it
draws the **view** the shell sends and sends command ids back.

- `crates/shell` (L6, package `myapp-shell`) has no UI toolkit. It owns `UiState`, generates the
  menu bar from the command registry, parses shortcuts, and implements the control protocol.
  `control::view(app)` returns one JSON value, `{ui, document, menus, shellCommands}`: everything
  the frontend draws, and exactly what `ui.inspect` returns. What a person sees is what an agent
  reads.
- The webview boundary is two Tauri commands and one event. `control(method, params)` is a
  control-protocol call. `invoke_command(command)` is a menu click or a shortcut. The event `view`
  carries the view to the webview whenever it changed. There is no frame loop.
- One owner thread owns the `AppShell` and so the `Session`. Tauri commands and the control socket
  only forward requests to it over a channel.

A behaviour the user can trigger is a command first: see [add-command.md](add-command.md). The UI
only dispatches its id.

## Rules for frontend code

- Components get a `Backend` (`control`, `invoke`, `onView`) and the data they draw as props.
- Only `src/lib/backend.ts` imports `@tauri-apps/api`.
- `npm run lint` (oxlint, configured in `.oxlintrc.json`) enforces the two rules above and the next
  one: it rejects a Tauri import anywhere else, and `fetch`, `localStorage` and the other network
  and storage globals. It also checks the React hook rules (`rules-of-hooks`, `exhaustive-deps`),
  floating promises (write `void` in front of a backend call you do not await) and `any`. Fix the
  code; do not disable a rule to get past it.
- No `fetch`, no storage, no document state, no business logic in TypeScript. Anything that is
  logic or state belongs in Rust (engine command or shell state).
- A checkbox that shows document state is controlled: `checked={item.done}` with an `onChange` that
  only asks for the change. React keeps the box at the document's state until the new view
  arrives. The frontend never predicts the result and never calls `preventDefault()` for it.
- A failed command's reason arrives as `ui.status` in the next view and is shown in the status
  bar. Do not build a second error channel.
- Colours and radii come from the tokens in `tokens.css`, never from literals in components.
- Shortcuts and menus are data from the shell. No key handling in components.
- Ids are `u64` in Rust and JSON numbers in the webview: exact only below 2^53. A larger id is an
  error, not a crash. Say so where ids cross the boundary.
- The webview gets the least it needs: no plug-in permissions for the main window, no remote
  content in it. See [add-tauri-plugin.md](add-tauri-plugin.md).

The shapes the shell sends are declared in `apps/myapp/src/lib/types.ts` (`View`, `UiState`,
`DocumentView`, `Menu`, `MenuItem`, `Shortcut`, `Reply`, `Backend`). Keep them in step with the Rust
side; the frontend never builds these itself.

## A component

`apps/myapp/src/components/Items.tsx` is the pattern. It is a function component with a named
export and its props typed inline. It takes the document as a prop, keeps what is being typed in
`useState`, computes what is visible during render, and turns every action into
`backend.control("engine.execute", { command, params })`.

```tsx
import { useState } from "react";

import type { Backend, DocumentView } from "../lib/types";
import styles from "./Items.module.css";

// A panel reads the view and dispatches command ids. It never changes the document itself.
export function Items({ document: doc, hideDone, backend }: { document: DocumentView | null; hideDone: boolean; backend: Backend }) {
  // What is being typed is this component's own business. It becomes a command's params on Add.
  const [draft, setDraft] = useState("");

  if (!doc) {
    return <p className={styles.empty}>No document. File › New starts one.</p>;
  }
  const visible = doc.items.filter((item) => !(hideDone && item.done));

  function execute(command: string, params: Record<string, unknown>) {
    return backend.control("engine.execute", { command, params });
  }

  async function add() {
    const reply = await execute("item.add", { text: draft });
    // On failure the shell puts the reason in the status bar, and the text stays to be fixed.
    if (reply.ok) {
      setDraft("");
    }
  }

  return (
    <>
      <h1 className={styles.title}>{doc.title}</h1>
      <form
        className={styles.add}
        onSubmit={(event) => {
          event.preventDefault();
          void add();
        }}
      >
        <input type="text" aria-label="New item" placeholder="New item" value={draft} onChange={(event) => setDraft(event.target.value)} />
        <button type="submit">Add</button>
      </form>
      <ul className={styles.list}>
        {visible.map((item) => (
          <li key={item.id}>
            <label className={item.done ? styles.done : undefined}>
              {/* Controlled by the document: the click only asks for the change, and the box changes when the new view arrives. */}
              <input type="checkbox" checked={item.done} onChange={() => void execute("item.setDone", { id: item.id, done: !item.done })} />
              <span>{item.text}</span>
            </label>
            <button type="button" className={styles.small} aria-label={`Delete ${item.text}`} onClick={() => void execute("item.delete", { id: item.id })}>
              Delete
            </button>
          </li>
        ))}
      </ul>
    </>
  );
}
```

The styles are in `Items.module.css`, a CSS Module beside the component; `styles.title`,
`styles.add` and the other names are its classes. It uses only the tokens, for example:

```css
.add {
  display: flex;
  gap: 6px;
  padding-bottom: 8px;
  border-bottom: 1px solid var(--separator);
}

.done span {
  color: var(--text-dim);
  text-decoration: line-through;
}
```

Base styles stay in `app.css` and the tokens in `tokens.css`.

Points to copy:

- Props: the data to draw plus the `backend`. No component imports Tauri.
- `useState` holds only what the widget needs while it is on screen (the text being typed, an open
  menu). What to show is computed from props during render (`visible` above): a plain expression,
  no memo hook needed at this size.
- The text field is controlled: `value={draft}` with an `onChange` that calls `setDraft`.
- The checkbox is controlled by the document: `checked={item.done}` with an `onChange` that only
  asks for the change. React keeps the box at the document's state until the new view arrives, so
  there is no `preventDefault()`.
- Every control has an accessible label (`aria-label`, a `<label>`): tests find widgets by them, and
  so do screen readers.
- A value the user types is passed as params of `engine.execute`; it is not put in `UiState`.
- On a failed command, keep what the user typed and do nothing else: the reason shows in the status
  bar.
- A component that listens to the window or any other source adds the listener in `useEffect` and
  returns a clean-up function, as `MenuBar.tsx` does:

  ```tsx
  useEffect(() => {
    const close = () => setOpen(null);
    const onKeydown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        close();
      }
    };
    window.addEventListener("click", close);
    window.addEventListener("keydown", onKeydown);
    return () => {
      window.removeEventListener("click", close);
      window.removeEventListener("keydown", onKeydown);
    };
  }, []);
  ```

### Wire it in `App.tsx`

`App.tsx` holds the one `view` state (a `useState`, set from the `view` event and from an initial
`ui.inspect`), sets `data-theme` from `view.ui.theme`, and passes slices of the view to components:

```tsx
  if (!view) {
    return <p className={styles.loading}>{failure || "Loading MyApp…"}</p>;
  }
  return (
    <div className={styles.app}>
      <MenuBar menus={view.menus} mac={mac} onInvoke={(id) => void backend.invoke(id)} />
      <main className={styles.main}>
        <Items document={view.document} hideDone={view.ui.hideDone} backend={backend} />
      </main>
      <StatusBar document={view.document} status={view.ui.status} />
    </div>
  );
```

The subscription to the `view` event is a `useEffect` with a clean-up function. `<StrictMode>`
(in `src/main.tsx`) runs effects twice in development, so every subscription must undo itself, or
it is registered twice. `onView` is async, so the unsubscribe function may arrive after the
clean-up has run; the `gone` flag handles that:

```tsx
  useEffect(() => {
    let stop = () => {};
    let gone = false;
    void backend
      .onView((next) => setView(next))
      .then((unlisten) => {
        if (gone) {
          unlisten();
        } else {
          stop = unlisten;
        }
      });
    void backend.control("ui.inspect").then((reply) => {
      if (gone) {
        return;
      }
      if (!reply.ok) {
        setFailure(reply.error);
      } else {
        // A `view` event that arrived first is newer than this answer.
        setView((current) => current ?? (reply.result as View));
      }
    });
    return () => {
      gone = true;
      stop();
    };
  }, [backend]);
```

To add a component: create it under `src/components/`, import it in `App.tsx`, and pass it the
slice of `view` it draws (plus `backend={backend}` if it dispatches commands). Do not give it its
own copy of document state.

## Where state lives

| The state is... | It lives in |
|---|---|
| Something automation should be able to see and set (theme, a view toggle, the last error) | `UiState` in `crates/shell/src/state.rs`; the frontend draws it from `ui.inspect` |
| Needed only while the widget is on screen (the text being typed, which menu is open) | The component (`useState`) |
| The user's work | The document, in the engine; never in TypeScript |

Decision rule: ask "should an agent be able to read or set this through `ui.inspect` and `ui.set`?"
If yes, `UiState`. If it vanishes harmlessly when the widget does, keep it in the component.

### Add a `UiState` field (a view toggle)

`UiState` is one serde struct (`crates/shell/src/state.rs`); `ui.inspect` returns it, `ui.set`
changes it, tests compare it:

```rust
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct UiState {
    /// The frontend maps this onto its design tokens (`src/tokens.css`).
    pub theme: ThemeKind,
    /// View › Hide Completed.
    pub hide_done: bool,
    /// The last command's error, shown in the status bar. Empty after a success.
    pub status: String,
}
```

1. **`state.rs`**: add the field (it keeps `#[serde(default)]` and camelCase naming).
2. **`ShellCommand` in `UI_COMMANDS`** (`crates/shell/src/menus.rs`) if a menu or a key should reach
   it. Shell commands live in the shell, not the engine: they touch no document, record no history
   and mean nothing to the CLI. They still have ids, run through `AppShell::run`, appear in the menu
   model with a `checked` state, and are listed in `ui.inspect` under `shellCommands`.

   ```rust
   pub struct ShellCommand {
       pub id: &'static str,
       pub label: &'static str,
       pub menu: &'static str,
       pub run: fn(&mut AppShell),
       pub checked: fn(&AppShell) -> bool,
   }

   ShellCommand {
       id: "view.hideDone",
       label: "Hide Completed",
       menu: "View",
       run: |app| app.ui.hide_done = !app.ui.hide_done,
       checked: |app| app.ui.hide_done,
   },
   ```
3. **`set()` arm** in `crates/shell/src/control.rs`, so automation can drive it. `set` validates
   every field, then applies them all:

   ```rust
   "hideDone" => next.hide_done = value.as_bool().ok_or("`hideDone` must be a boolean")?,
   ```

   Update the module doc comment (`ui.set {theme?, hideDone?}`) too.
4. **`apps/myapp/src/lib/types.ts`**: add the field to `UiState` (camelCase, same name). Update
   `sampleView()` in `src/test-support.ts`.
5. **`docs/control-protocol.md`**: the `ui.set` params row. See
   [add-control-method.md](add-control-method.md).
6. Read it in `App.tsx` and pass it to the component as a prop.
7. Tests: a Rust shell test (the `ui.inspect` and `ui.set` assertions in
   `the_control_protocol_drives_and_inspects_the_app`) and a component test.

## A design token

`apps/myapp/src/tokens.css` holds the tokens as CSS custom properties, one block per theme:
`--chrome` (window chrome: menu bar, status bar, panel backgrounds), `--card` (popups and cards),
`--field` (text fields), `--control` (buttons and checkboxes at rest), `--text`, `--text-dim`,
`--accent`, `--danger`, `--separator` and `--radius`.

```css
:root,
[data-theme="dark"] {
  color-scheme: dark;
  /* Window chrome: menu bar, status bar, panel backgrounds. */
  --chrome: #323232;
  /* Popups and cards. */
  --card: #3c3c3c;
  /* Text fields. */
  --field: #262626;
  /* Buttons and checkboxes at rest. */
  --control: #4a4a4a;
  --text: #e0e0e0;
  --text-dim: #9a9a9a;
  --accent: #378ef0;
  --danger: #f06a6a;
  --separator: #4a4a4a;
  --radius: 4px;
}

[data-theme="light"] {
  color-scheme: light;
  --chrome: #f0f0f0;
  --card: #ffffff;
  --field: #ffffff;
  --control: #e2e2e2;
  --text: #202020;
  --text-dim: #6a6a6a;
  --accent: #1a6fd6;
  --danger: #c02b2b;
  --separator: #d0d0d0;
  --radius: 4px;
}
```

To add one, add the property to **both** blocks, then use `var(--name)` in the component's CSS
Module (`Items.module.css` sits beside `Items.tsx`). Never write a colour literal anywhere else:
`src/tokens.test.ts` reads every `.css` and every `.tsx` file (an inline `style` counts) other than
test files and `tokens.css`, and fails on a hex colour or an `rgb(`, `hsl(`, `oklch(`, `oklab(`,
`lab(`, `lch(` or `color(` function in them. It also fails when the two blocks do not define the
same tokens.
Check both themes in a rendered image.

## A command that needs something only the platform can provide

A command never opens UI. When the value can only come from the platform (a file path from a native
dialog), the shell asks through a `Services` hook and passes the answer as params. A value the user
types or picks inside the window is not this case: the component sends it as params of
`engine.execute` (see above).

`menus::invoke` (`crates/shell/src/menus.rs`) is what a menu click or a shortcut ends in:

```rust
const NO_PICKER: &str = "file dialogs are not available here";

/// Commands whose menu click first asks the user for a file.
fn needs_picker(id: &str) -> bool {
    matches!(id, "file.open" | "file.saveAs")
}

/// What a menu click or a shortcut does. Commands that need a value only the platform can ask
/// for get it here (a file dialog); everything else runs with its default params. A value the
/// user types into the frontend travels as params of `engine.execute` instead.
pub fn invoke(app: &mut AppShell, id: &str) -> Result<Value, String> {
    // Save on a document that has no file yet behaves as Save As.
    let id = if id == "file.save" && app.session.active().is_some_and(|d| d.path.is_none()) { "file.saveAs" } else { id };
    let params = match id {
        "file.open" | "file.saveAs" => {
            let kind = if id == "file.open" { PickKind::Open } else { PickKind::Save };
            let Some(pick) = app.services.pick_file.as_mut() else {
                app.ui.status = NO_PICKER.into();
                return Err(NO_PICKER.into());
            };
            match pick(kind) {
                Some(path) => json!({"path": path}),
                // The user cancelled: nothing ran and nothing changed.
                None => return Ok(Value::Null),
            }
        }
        _ => Value::Null,
    };
    app.run(id, params)
}
```

`invoke_command` is not offered on the control socket because it may open a native dialog.

The hook (`crates/shell/src/services.rs`):

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PickKind {
    Open,
    Save,
}

/// Ask the user for a file. `None` when they cancel.
pub type PickFileFn = Box<dyn FnMut(PickKind) -> Option<PathBuf>>;

/// Every hook is optional: where one is missing (tests, a platform without it), the menu items
/// that need it are disabled instead of failing.
#[derive(Default)]
pub struct Services {
    pub pick_file: Option<PickFileFn>,
}
```

To add a hook:

1. Add a type alias and an `Option<...>` field to `Services` in the shell crate.
2. Implement it in `apps/myapp/src-tauri/src/services.rs`, in `native(handle)`. The template's file
   picker uses the dialog plug-in's blocking calls, which run on the thread that owns the shell,
   never on the main thread (the blocking calls wait for the main thread to show the dialog):

   ```rust
   pub fn native(handle: AppHandle) -> Services {
       Services {
           // Called on the thread that owns the shell, never on the main thread: the dialog
           // plug-in's blocking calls wait for the main thread to show the dialog.
           pick_file: Some(Box::new(move |kind| {
               let dialog = handle.dialog().file().add_filter("MyApp document", &[myapp_format::EXTENSION]);
               let picked = match kind {
                   PickKind::Open => dialog.blocking_pick_file(),
                   PickKind::Save => dialog.set_file_name(format!("Untitled.{}", myapp_format::EXTENSION)).blocking_save_file(),
               };
               picked.and_then(|path| path.into_path().ok())
           })),
       }
   }
   ```

   A blocking dialog holds the owner thread, so other requests wait while it is open.
3. Leave the hook `None` where the platform lacks it (tests, a headless run).
4. Disable what depends on it when it is `None`. In `menus::items`, with the reason as the item's
   tooltip:

   ```rust
   let mut enabled = (spec.enabled)(&app.session);
   if needs_picker(spec.id) && app.services.pick_file.is_none() {
       enabled = Err(NO_PICKER.into());
   }
   ```
5. Test with a fake hook in `crates/shell/src/tests.rs` (see below): the command asks the service,
   a cancel changes nothing, and the item is disabled with its reason when the hook is `None`.

The webview never opens dialogs: it has no dialog permission.

## A shortcut or a menu item

Set `shortcut` or `menu` on the `CommandSpec` in the engine. Nothing else: the shell generates the
menu model (`menus::model`) from the registry, each item with `id`, `label`, parsed `shortcut`,
`enabled`, `reason` (the tooltip) and `checked`, and the frontend draws it and matches key events
against it. For a new top-level menu, add its name to `MENU_ORDER` in `crates/shell/src/menus.rs`:

```rust
pub const MENU_ORDER: &[&str] = &["File", "Edit", "Item", "View"];
```

A command whose menu click cannot supply its params (it needs text) stays out of menus: give it
`menu: &[]` and call it from a component.

Two Rust tests guard the registry: one in `crates/engine/src/commands.rs` fails if two commands
share an id or a shortcut, and `every_registered_shortcut_parses` in
`crates/shell/src/shortcuts.rs` fails if a shortcut string does not parse.

### Shortcut syntax

`+`-separated parts: any of the modifiers `Cmd`, `Ctrl`, `Shift`, `Alt`, then exactly one key.
`Cmd+Shift+Z`, `Cmd+S`, `Alt+F4`, `Ctrl+Space`, `Delete`. `Cmd` is the platform's command key: Cmd
on macOS, Ctrl elsewhere; use `Ctrl` only for the literal Ctrl key. Accepted key names, from
`key_value` in `crates/shell/src/shortcuts.rs`:

| Key | Names |
|---|---|
| A letter or digit | `A`..`Z`, `0`..`9` (matched case-insensitively) |
| Punctuation | one of `,` `.` `/` `;` `'` `[` `]` `\` `-` `=` `` ` `` |
| Space | `Space` |
| Function keys | `F1`..`F12` |
| Named keys | `Enter`, `Escape`, `Tab`, `Backspace`, `Delete`, `Insert`, `Home`, `End`, `PageUp`, `PageDown`, `ArrowUp`, `ArrowDown`, `ArrowLeft`, `ArrowRight` |

Anything else (`NoSuchKey`, `F13`, two keys, no key, an empty string) does not parse and fails the
test above. The parsed value is sent as data:

```rust
pub struct Shortcut {
    /// As written in the registry, e.g. `Cmd+Shift+Z`.
    pub text: String,
    pub cmd: bool,
    pub ctrl: bool,
    pub shift: bool,
    pub alt: bool,
    /// The lowercased `KeyboardEvent.key` this shortcut matches, e.g. `z`, `enter`, `f2`.
    pub key: String,
}
```

### How the frontend matches keys (`src/lib/shortcuts.ts`)

```ts
/** Exact match: an extra modifier is a different shortcut, so `Cmd+Shift+Z` never runs `Cmd+Z`. */
export function matches(shortcut: Shortcut, event: KeyboardEvent, mac: boolean): boolean {
  const ctrl = mac ? shortcut.ctrl : shortcut.cmd || shortcut.ctrl;
  const meta = mac ? shortcut.cmd : false;
  return (
    event.ctrlKey === ctrl &&
    event.metaKey === meta &&
    event.shiftKey === shortcut.shift &&
    event.altKey === shortcut.alt &&
    event.key.toLowerCase() === shortcut.key
  );
}
```

- **Exact-modifier matching.** An extra modifier is a different shortcut, so `Cmd+Shift+Z` never runs
  `Cmd+Z`. There is no "try the longest first" ordering to maintain.
- **`Cmd` is Ctrl off macOS** and the command key on macOS.
- **The text-field exception.** While a text field has the focus, `findShortcut` returns `null` for
  undo, redo, select all and the clipboard keys (`z`, `y`, `a`, `c`, `v`, `x` with Ctrl or Cmd and
  no Alt), so the field keeps them. Other shortcuts still fire. Checkboxes, radios and buttons are
  not text fields.
- `App.tsx` turns a match into `backend.invoke(id)` and calls `preventDefault()`, in a `keydown`
  listener that a `useEffect` adds and removes. Never handle keys in components.

## Tests

Two kinds, no window needed for either.

### Shell tests in Rust

`crates/shell/src/tests.rs` drives the shell with no toolkit: menus, `menus::invoke`, the control
protocol and the channel. Copy one:

```rust
fn app() -> AppShell {
    let mut app = AppShell::new(Session::new(), Services::default());
    app.run("file.new", json!({"title": "Today"})).unwrap();
    app
}

fn texts(app: &AppShell) -> Vec<String> {
    app.session.snapshot().unwrap().items.iter().map(|i| format!("{}{}", if i.done { "x " } else { "" }, i.text)).collect()
}

#[test]
fn a_menu_click_runs_the_command_as_one_undoable_step() {
    let mut app = app();
    app.run("item.add", json!({"text": "milk"})).unwrap();
    app.run("item.setDone", json!({"id": 1})).unwrap();
    assert_eq!(menus::invoke(&mut app, "item.clearDone"), Ok(json!({"removed": 1})));
    assert!(texts(&app).is_empty());
    assert_eq!(app.session.active().unwrap().history.undo_label(), Some("Clear Completed"));
    menus::invoke(&mut app, "edit.undo").unwrap();
    assert_eq!(texts(&app), ["x milk"]);
    menus::invoke(&mut app, "view.hideDone").unwrap();
    assert!(app.ui.hide_done, "shell commands are invoked the same way");
}

#[test]
fn a_failed_command_reaches_the_status_bar_and_a_success_clears_it() {
    let mut app = app();
    assert!(app.run("item.add", json!({"text": "   "})).is_err());
    assert_eq!(app.ui.status, "bad params: `text` is empty");
    app.run("item.add", json!({"text": "milk"})).unwrap();
    assert_eq!(app.ui.status, "");
}
```

A fake service records what it was asked and answers on cue:

```rust
/// A picker that answers with `answer` and records what it was asked.
fn with_picker(answer: Option<PathBuf>) -> (AppShell, Rc<RefCell<Vec<PickKind>>>) {
    let asked = Rc::new(RefCell::new(Vec::new()));
    let log = Rc::clone(&asked);
    let services = Services {
        pick_file: Some(Box::new(move |kind| {
            log.borrow_mut().push(kind);
            answer.clone()
        })),
    };
    let mut app = AppShell::new(Session::new(), services);
    app.run("file.new", json!({"title": "Today"})).unwrap();
    (app, asked)
}
```

Run with `cargo test -p myapp-shell --lib --tests`.

### Component tests in TypeScript

`apps/myapp/src/**/*.test.{ts,tsx}`, run by vitest on jsdom with `@testing-library/react` and
`@testing-library/user-event`. Components get
`fakeBackend(view, answer?)` from `src/test-support.ts`: it records what the frontend asked for
(`calls`) instead of running it, answers `ui.inspect` with the view you give it, and `emit(view)`
simulates the `view` event. `sampleView()` returns a view like the shell sends (a document with
`milk` and `eggs`, an Edit and a View menu). Find widgets by label or role, click, type, and assert
on `calls` and on what is drawn. From `Items.test.tsx`:

```tsx
function show(hideDone = false, answer?: Parameters<typeof fakeBackend>[1]) {
  const fake = fakeBackend(null, answer);
  render(<Items document={sampleView().document} hideDone={hideDone} backend={fake.backend} />);
  return fake;
}

it("dispatches item.add with what was typed and clears the field once it succeeded", async () => {
  const { calls } = show();
  const field = screen.getByLabelText("New item");
  await userEvent.type(field, "bread{Enter}");
  expect(calls).toEqual([["control", "engine.execute", { command: "item.add", params: { text: "bread" } }]]);
  await waitFor(() => expect(field).toHaveProperty("value", ""));
});

it("keeps the text when the command fails", async () => {
  const { calls } = show(false, () => ({ ok: false, error: "bad params: `text` is empty" }));
  const field = screen.getByLabelText("New item");
  await userEvent.type(field, "   ");
  await userEvent.click(screen.getByRole("button", { name: "Add" }));
  expect(calls).toHaveLength(1);
  expect(field).toHaveProperty("value", "   ");
});

it("asks for the change on a click and draws only the document", async () => {
  const { calls } = show();
  const milk = screen.getByLabelText("milk");
  await userEvent.click(milk);
  expect(calls).toEqual([["control", "engine.execute", { command: "item.setDone", params: { id: 1, done: true } }]]);
  expect(milk).toHaveProperty("checked", false);
  await userEvent.click(screen.getByRole("button", { name: "Delete eggs" }));
  expect(calls[1]).toEqual(["control", "engine.execute", { command: "item.delete", params: { id: 2 } }]);
});
```

Two helpers matter when state changes outside a user event:

- `await waitFor(...)` for state that is set after an awaited backend call (the field is cleared
  only once `item.add` has been answered).
- `act(...)` around a view the test pushes itself. From `App.test.tsx`:

  ```tsx
  const next = sampleView();
  next.ui = { theme: "light", hideDone: true, status: "bad params: `text` is empty" };
  act(() => fake.emit(next));
  expect(await screen.findByText("bad params: `text` is empty")).toBeTruthy();
  ```

Vitest runs without global test functions, so React Testing Library cannot register its own
clean-up or tell React that updates belong inside `act`. `src/test-setup.ts` does both once for
every test file:

```ts
// Vitest runs without global test functions, so React Testing Library cannot register these itself.
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

// Tells React that state updates in tests are expected to happen inside `act`.
(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

// Unmount what a test rendered before the next one starts.
afterEach(cleanup);
```

A menu component is tested the same way (`MenuBar.test.tsx`): it draws the generated menus and reports
the chosen id, disables what cannot run and says why, and shows toggles with their state:

```tsx
it("draws the generated menus and reports the chosen id", async () => {
  const onInvoke = vi.fn<(id: string) => void>();
  render(<MenuBar menus={sampleView().menus} mac={false} onInvoke={onInvoke} />);
  expect(screen.queryByRole("menu")).toBeNull();
  await userEvent.click(screen.getByRole("button", { name: "Edit" }));
  const undo = screen.getByRole("menuitem", { name: /Undo/ });
  expect(undo.textContent).toContain("Ctrl+Z");
  await userEvent.click(undo);
  expect(onInvoke).toHaveBeenCalledWith("edit.undo");
  expect(screen.queryByRole("menu")).toBeNull();
});
```

Add a component test for every component: the click or key dispatches the right command with the
right params, a failure keeps the user's input, and what is drawn comes from the props. Keep
`sampleView()` in step with `types.ts`. Run with `npm test` (once) in `apps/myapp`, or
`cargo xtask web` for check, test and build.

## Check it by looking

A UI change is not done until someone has looked at a rendered image, in both themes. From
`apps/myapp`:

```sh
npm run snapshot:install        # once
npm run build
npm run snapshot -- --out ui.png --size 720x420 \
  --script '[["engine.execute", {"command": "item.add", "params": {"text": "milk"}}], ["ui.set", {"theme": "light"}]]'
```

Render with `{"theme": "dark"}` and `{"theme": "light"}`, and use `--click File` (any button's
accessible name) to open a menu in the picture. Open the PNG and look. Every option, and the caveat
that the browser is not the platform webview, is in [../references/verify.md](../references/verify.md).
