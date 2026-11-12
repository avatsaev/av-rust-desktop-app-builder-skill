# What is fixed and what you choose

The template is a checklist app, but the architecture is not about checklists. Separate what the
architecture fixes (keep it whatever you build) from what you choose (shape it to the product).
`myapp` in paths below stands for the project's machine name.

## The table

| Fixed: keep these whatever you build | Yours to choose |
|---|---|
| Crates in enforced layers, binaries at the top | Which crates exist in each layer |
| Every action is a command with an id and JSON params | The commands |
| The model is plain serde data, read through snapshots | What the model is, and where it is stored |
| The frontend draws the view and dispatches ids | The components, the layout, the theme |
| Platform code is injected through `Services` | Which services your app needs |
| UI state is data, exposed with the model over the control protocol | The fields |
| The webview is confined: two commands, one event, no remote content in the main window | Which extra windows show web content, and from where |
| One gate: `cargo xtask ci` | What else the gate runs |

Never trade a left-hand cell for convenience. When a request seems to need that, find the
right-hand cell that serves it instead.

## The model is "what the user works on"

The template calls its model `Document` because the sample is an editor. The architecture only
needs the model to be:

- plain data (`Clone`, `Serialize`, `Deserialize`, `PartialEq`),
- validated in one place, with caps on every size,
- cheap to clone (large payloads behind `Arc`),
- changed only by commands.

Rename the crate and the type to fit your domain (`project`, `library`, `workspace`, `state`).
Nothing else depends on the word.

## Properties of the model crate

The model crate is `crates/doc` (layer L1). It is pure data: no I/O, no history, no UI. When you
rewrite it for your domain, keep these properties:

- Everything derives `Clone`, `PartialEq`, `Serialize` and `Deserialize`.
- A field added later gets `#[serde(default)]`, so older files still load.
- Invariants are checked in one place, `validate()`, with an explicit cap on every size: the data
  may come from a file or an agent.
- Identity is a typed id (`ItemId` in the template), never an index. Indices change under undo.
- New ids are derived from the data rather than from a stored counter, so a file cannot supply a
  counter that collides.

The crate also carries `#![forbid(unsafe_code)]` and the clippy `deny` list (`unwrap_used`,
`expect_used`, `panic`, `unimplemented`, `todo`, `unreachable`) at its root, like every other
library crate in the workspace.

Ids are `u64` in Rust and JSON numbers in the webview, which are exact only below 2^53. Say so
wherever ids cross the boundary; a larger id is an error, never a crash.

## Where UI state lives

Decide this for every piece of state the frontend shows:

- **`UiState` in `crates/shell`** (`crates/shell/src/state.rs`) for what automation should be able
  to see and set. It is one serde struct (`#[serde(default, rename_all = "camelCase")]`); `ui.inspect`
  returns it, `ui.set` changes it, the frontend draws it and tests compare it. In the template:
  `theme`, `hide_done` and `status`.
- **Component-local** (`useState` inside the component) for what a widget needs only while it
  is on screen: the text being typed, which menu is open. In the template the new item's text is
  the `draft` in `Items.tsx`; it travels as params of `engine.execute` when the user presses Add
  and is never in `UiState`.

Test: if an agent driving the app over the control channel would need to read or set it, it is
`UiState`; if it disappears with the widget and no command needs it, it is component-local. The
frontend keeps no document state and no business logic either way.
