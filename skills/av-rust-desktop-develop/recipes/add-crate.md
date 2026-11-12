# Add a crate

Paths are inside the project; `myapp` stands for the project's machine name.

## 1. Choose the layer

Ask in this order and stop at the first yes:

1. Is it plain data the user's work consists of? **L1.**
2. Is it a pure function over that data (compute, transform, validate, lay out)? **L2**, in a crate
   named for its domain.
3. Is it bytes in and out of your own format, or a store? **L3.**
4. Is it someone else's format or protocol? A **standalone L0** crate for the format itself, plus
   an **L4** crate that maps it to your model.
5. Is it something a user does? A **command in L5** (in the engine) that calls the code above.
6. Is it UI state, a menu or a shortcut? Data in **L6 `crates/shell`**. Is it something drawn or
   clicked? A **component in the frontend** (`apps/myapp/src`), see [add-ui.md](add-ui.md).
7. Does only one platform have it (a dialog, a socket, a tray icon)? **The app binary**
   (`apps/myapp/src-tauri`), behind a `Services` hook. If it needs `unsafe`, isolate it in its own
   small crate, e.g. `crates/<os-integration>`, with a `SAFETY:` comment on every block.

| Layer | What belongs here |
|---|---|
| L0 | Types with no domain model: geometry, units, colour, storage containers. Also standalone crates that parse or encode a foreign format and depend on no workspace crate, so they stay publishable on their own |
| L1 | The model: plain serde data and the invariants that keep it valid |
| L2 | History, and domain algorithms written as pure functions over L0 and L1 data |
| L3 | The native file format, storage, renderers |
| L4 | Mapping the model to and from foreign formats; a plug-in host |
| L5 | `Session` and the command registry: the facade every frontend talks to |
| L6 | `crates/shell`: UI state, menus and shortcuts as data, the control protocol; an MCP server sits beside it. It has no UI toolkit |
| testkit | Test helpers; other crates use it as a dev-dependency only |
| apps | Binaries: argument parsing, the window, file dialogs, sockets, OS integration |

The layer numbers have gaps on purpose: a crate added later slots in without renumbering. A crate
depends only on lower layers. Two crates in the same layer may not depend on each other unless the
table says so explicitly (see `INTRA_LAYER_ORDER` below). Nothing below the app binary uses tauri,
wry or tao, and nothing below L6 uses any crate in `UI_CRATES`; `cargo xtask layers` checks it.

## 2. Create the crate

1. Create `crates/<name>/Cargo.toml` inheriting from the workspace:

   ```toml
   [package]
   name = "myapp-<name>"
   version.workspace = true
   edition.workspace = true
   license.workspace = true

   [lints]
   workspace = true
   ```

   Write the manifest in one step. `crates/*` is a glob, so a half-written `Cargo.toml` breaks
   every build in the workspace.
2. Start `src/lib.rs` with the two attribute lines:

   ```rust
   #![forbid(unsafe_code)]
   #![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]
   ```

   `clippy.toml` allows `unwrap` and friends in tests only. An unfinished feature returns an
   "unsupported" error.
3. Add `myapp-<name> = { path = "crates/<name>" }` to `[workspace.dependencies]` in the root
   manifest.
4. Add the crate to `TABLE` in `xtask/src/layers.rs` at its layer (below).
5. Run `cargo xtask layers` and `cargo xtask wasm`.

External dependency versions also go in `[workspace.dependencies]`; member crates write
`serde = { workspace = true }`. Check a dependency's licence against the allowlist before adding it.
Dependencies that use git: pin an immutable revision (`rev = "<full hash>"`), never a branch.

## 3. Register it in `xtask/src/layers.rs`

`TABLE` maps package names (without the `myapp-` prefix) to a `Class`. A crate missing from the
table is a violation, so a new crate cannot skip the check; the error reads
`<crate>: not in the layering table`.

```rust
pub enum Class {
    /// A layered crate: it may depend only on crates in lower layers.
    Layer(u8),
    /// Layer 0 and no workspace dependency at all (format parsers, codecs: publishable alone).
    Standalone,
    /// Test tooling: other crates may use it only as a dev-dependency.
    Testkit,
    /// Binaries and build tooling: exempt from the rules.
    Exempt,
}

pub const TABLE: &[(&str, Class)] = &[
    ("doc", Class::Layer(1)),
    ("ops", Class::Layer(2)),
    ("format", Class::Layer(3)),
    ("engine", Class::Layer(5)),
    ("shell", Class::Layer(6)),
    ("testkit", Class::Testkit),
    // Apps and tooling.
    ("myapp", Class::Exempt),
    ("cli", Class::Exempt),
    ("xtask", Class::Exempt),
];

/// Explicit orderings within a layer (earlier may be used by later), e.g. `&["compose", "gpu"]`
/// when a GPU backend reuses the CPU reference.
pub const INTRA_LAYER_ORDER: &[&[&str]] = &[];
```

| Class | Use for | What the check enforces |
|---|---|---|
| `Layer(n)` | Any layered crate (L1 to L6) | Depends only on lower layers; below `UI_MIN_LAYER` (6) it may not depend on a UI crate. `UI_CRATES` starts with `"tauri*"`, `"wry"`, `"tao"`, `"muda"`, `"webview2*"`, `"webkit2gtk*"` and also names the other windowing and native-dialog crates (a trailing `*` is a prefix). wgpu is deliberately not listed: a renderer below the UI layer may use the GPU, but no windows and no webviews |
| `Standalone` | An L0 crate that parses or encodes a foreign format | No workspace dependency at all |
| `Testkit` | Test helpers | Other crates may use it only under `[dev-dependencies]` |
| `Exempt` | Binaries and `xtask` | Exempt, but nothing layered may depend on one |

`INTRA_LAYER_ORDER` is a list of chains: in `&["compose", "gpu"]`, `gpu` may depend on `compose`
though both are L3. Use it only for a real reuse relationship.

The wasm check (`cargo xtask wasm`) runs `cargo check --target wasm32-unknown-unknown` over every
`Layer` and `Standalone` crate in the table (`doc ops format engine shell` in the template). The
apps are not checked. Keep file-system code behind `cfg(not(target_arch = "wasm32"))` or behind
`Services`.

## Done when

`cargo xtask layers` prints the crate with its layer and `layering: ok`, `cargo xtask wasm` passes,
and the crate has tests.
