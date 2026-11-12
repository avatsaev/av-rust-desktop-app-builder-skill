# Translations and fonts

**Add it when:** A second language, or custom type.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

- Strings in code stay English and are the lookup keys. Command ids and the control protocol stay English.
- Catalogs live outside the app repository and are embedded by `build.rs` from a directory named by an environment variable. Without it the build is English only, and everything still works.
- Fonts are an optional build input in the same way and are never committed to the app repository.
- Every bundled font and catalogue needs an `ATTRIBUTION.md` row and an allowed licence (OFL-1.1 is on the allowlist).

Strings now live in two places *(reasoned)*:

- **Rust**: command labels, errors and the menu labels the registry supplies. Wrap user-facing strings in a macro (for example `tl!("Export…")`) and translate registry labels in the shell when it builds the view, so the frontend receives menus already in the user's language.
- **Components**: give the frontend a small lookup fed from the same catalog, keyed by the English string.
- Fonts are frontend assets: `@font-face` with woff2 files, each with an `ATTRIBUTION.md` row. To keep the download small, ship only the faces and subsets used.

## Where it goes

Suggested homes: the macro, catalogue embedding and its `build.rs` in `crates/shell` (L6; `crates/shell/src/i18n.rs`, `crates/shell/build.rs`), the lookup in `apps/myapp/src/lib/`, the font files and `@font-face` rules under `apps/myapp/src/`. Mind golden rule 1: the lookup is a lookup, not logic. No new crate required; register any you add in `xtask/src/layers.rs`.

## How it fits the seams

- Labels from the registry (`CommandSpec.label`) are English keys translated when the view is built; ids never change.
- The build-time environment variable keeps the default build and the gate English-only and deterministic.
- The control protocol and `ui.inspect` field names stay English, so automation does not depend on locale.

## Done when

- [ ] A build with no catalogue environment variable works and is English.
- [ ] A shell test shows a missing translation falls back to the English key, in menus too.
- [ ] A component test shows the frontend lookup falls back the same way.
- [ ] No fonts or catalogues are committed; attribution rows exist for any bundled ones.

- [ ] You looked at a rendered image (`npm run snapshot`, in `apps/myapp`) of the changed UI.
- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
