# Build profiles

Tune profiles in the root `Cargo.toml`. In every path below `myapp` stands for the project's machine
name. The settings here are the template's own. The template builds and runs; the tuning advice
beyond what the template contains comes from a large production app on this architecture, whose
shell is a native Rust UI toolkit rather than a webview. Anything marked *(reasoned)* is derived
from the architecture and from Tauri's documented behaviour, not built: check the current Tauri
documentation before relying on it.

## The profiles

| Profile | Settings | Why |
|---|---|---|
| `dev` | Own code at `opt-level = 1` with `debug = "line-tables-only"`; dependencies at `opt-level = 2` with no debug info | The app is unpleasant unoptimised. Dependencies are compiled once, so optimising them is cheap; line tables keep file and line in backtraces and make links faster |
| `test` | Inherits `dev` | |
| `release` | `lto = "thin"`, `codegen-units = 1` | Desktop binaries |

There is no separate profile for a browser build: the template has none. The frontend is built by
Vite, not by cargo (see below).

## The profile blocks in the root `Cargo.toml`

```toml
# Dependencies are optimized and carry no debug info: the app stays responsive in dev builds, and
# the target dir and link times shrink. The test profile inherits both settings.
[profile.dev.package."*"]
opt-level = 2
debug = false

[profile.dev]
opt-level = 1
# Line tables keep file:line in panic backtraces but drop variable info (faster links).
# To inspect locals in a debugger: CARGO_PROFILE_DEV_DEBUG=true.
debug = "line-tables-only"

# Never add `panic = "abort"` here, although size guides for Tauri suggest it: the crash guard
# needs unwinding.
[profile.release]
lto = "thin"
codegen-units = 1
```

## Rules that go with them

- **Never set `panic = "abort"`**, although size guides for Tauri suggest it. The crash guard needs
  unwinding.
- **To debug with local variables**, build with `CARGO_PROFILE_DEV_DEBUG=true` instead of editing the
  manifest.
- **Measure before tuning.** Change one setting, rebuild, compare the binary and the build time, and
  keep it only if it pays. A large production app sets optimisation per crate for its hot per-pixel
  crates; the template needs none of that.
- **Watch test-build time.** A large production app builds its largest UI-side crate at
  `opt-level = 0` under the `test` profile because its tests run no heavy code, and sets
  `CARGO_PROFILE_DEV_DEBUG=0` on Windows CI.

## The frontend build

`vite build` (run by `npm run build` in `apps/myapp`) writes `apps/myapp/dist`. Tauri embeds that
directory into the binary at compile time, so `dist/` must exist before any cargo command that
compiles the app. The gate's `web` step builds it before `clippy` for that reason (see
[the gate](gate.md)).

Measured for the template: about 226 kB of JavaScript (71 kB gzipped, most of it React) and 3 kB of
CSS; the release binary is about
8.8 MB; the `.deb` bundle is 2.9 MiB. Watch the frontend's size as it grows: a bundle-size budget is
a growth pattern in the `av-rust-desktop-grow` skill.

## Root-manifest facts to keep true

- **`[workspace.dependencies]`** is the only place a Rust version is written. Internal crates are
  listed too, so a member writes `myapp-doc = { workspace = true }`. Never write a version in a
  member manifest. npm versions live in `apps/myapp/package.json`.
- **The Tauri family moves together.** Keep `tauri`, `tauri-build` and every `tauri-plugin-*` on the
  same major version, and `@tauri-apps/api` in `apps/myapp/package.json` on the same minor as
  `tauri`. The template's comment says so beside the entries:

```toml
[workspace.dependencies]
# internal: one line per crate, so members write `myapp-doc = { workspace = true }`
myapp-doc = { path = "crates/doc" }
myapp-ops = { path = "crates/ops" }
myapp-format = { path = "crates/format" }
myapp-engine = { path = "crates/engine" }
myapp-shell = { path = "crates/shell" }
myapp-testkit = { path = "crates/testkit" }

# external: versions live here only
thiserror = "2"
serde = { version = "1", features = ["derive", "rc"] }
serde_json = "1"
clap = { version = "4", features = ["derive", "env"] }
# `std`: the app installs its own boxed logger.
log = { version = "0.4", features = ["std"] }
getrandom = "0.3"
# The Tauri family moves together: keep `tauri`, `tauri-build` and every `tauri-plugin-*` on the
# same major version, and `@tauri-apps/api` in apps/myapp/package.json on the same minor as `tauri`.
tauri = { version = "2", features = [] }
tauri-build = { version = "2", features = [] }
tauri-plugin-dialog = "2"
```

- **`[workspace.lints]`** forbids `unsafe` everywhere; each library crate opts in with
  `[lints] workspace = true`. The workspace table:

```toml
[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
cognitive_complexity = "deny"
too_many_arguments = "deny"
wildcard_imports = "deny"
dbg_macro = "warn"
todo = "warn"
```

- **The app crate has its own `[lints]`** (`apps/myapp/src-tauri/Cargo.toml`) with `unsafe_code`
  at `"deny"` instead of `"forbid"`: this crate writes no unsafe code, but Tauri's macros generate the
  app context there and must be able to allow it. It is the only crate that does this:

```toml
# The workspace lints, with `unsafe_code` at "deny" instead of "forbid": this crate writes no
# unsafe code, but Tauri's macros generate the app context here and must be able to allow it.
[lints.rust]
unsafe_code = "deny"

[lints.clippy]
cognitive_complexity = "deny"
too_many_arguments = "deny"
wildcard_imports = "deny"
dbg_macro = "warn"
todo = "warn"
```

- **The workspace has no `default-members`.** The desktop app is a normal member at
  `apps/myapp/src-tauri`.
- **`tauri.conf.json` sets no version.** The app version comes from `[workspace.package] version`.
