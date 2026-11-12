# Commands you will type

`myapp` stands for the project's machine name. The project has two toolchains, cargo and npm; the
npm project is `apps/myapp`. While iterating, run the narrow command for the crate or component you
are in. Keep `cargo xtask ci` as the final check.

**Tauri embeds `apps/myapp/dist` into the app binary at compile time.** Any cargo command that
compiles the app (`cargo run -p myapp`, `cargo clippy --workspace`, `cargo test --workspace`) needs
`dist/` to exist: run `cargo xtask web` (or `npm run build` in `apps/myapp`) first, and again after
frontend changes. A missing or stale `dist/` gives a blank window or a `frontendDist` compile error.

| Command | What it does |
|---|---|
| `cargo run -p myapp` | Run the desktop app with the built frontend (`dist/`). Add `--release` for anything performance-sensitive |
| `npm run app` (in `apps/myapp`) | Run the desktop app on Vite's dev server: frontend changes reload at once |
| `cargo xtask web` | The frontend: `npm ci` when needed, then type check, lint, tests and build |
| `npm run check` (in `apps/myapp`) | `tsc --noEmit`: types for the TypeScript and React code |
| `npm run lint` (in `apps/myapp`) | oxlint, type-aware, warnings are errors: the React hook rules, floating promises, `any`, a Tauri import outside `src/lib/backend.ts`, and network or storage globals (`fetch`, `localStorage` and the like) |
| `npm test` (in `apps/myapp`) | The component tests (vitest) |
| `npm run snapshot` (in `apps/myapp`) | Draw the real frontend to a PNG without opening the app (see [verify.md](verify.md)) |
| `cargo test -p <crate> --lib --tests` | One crate's tests, skipping examples and doctests |
| `cargo test -p <crate> --test <file>` | One integration-test file |
| `cargo test -p myapp-engine --test panic_hunt -- --ignored` | The adversarial command fuzz |
| `cargo nextest run --workspace` | Every Rust test, in parallel across test binaries |
| `cargo clippy -p <crate> --all-targets -- -D warnings` | Lint what you touched |
| `cargo fmt --all` | Format |
| `cargo xtask layers` | Print the dependency table and any violations |
| `cargo xtask wasm` | `cargo check` for wasm32 on the layered crates (`doc ops format engine shell`) |
| `cargo xtask ci` | The whole gate. Run it before you call something done |
| `npm run bundle` (in `apps/myapp`) | Build installers with the Tauri bundler (`tauri build`) |

`cargo xtask` also accepts `test` (workspace tests, then doctests).

**Debugging tip.** The `dev` profile builds your own code at `opt-level = 1` with
`debug = "line-tables-only"`, and dependencies at `opt-level = 2` with no debug info. To debug with
local variables, build with `CARGO_PROFILE_DEV_DEBUG=true` instead of editing the manifest:

```sh
CARGO_PROFILE_DEV_DEBUG=true cargo run -p myapp
```

Never set `panic = "abort"` in any profile, although Tauri size guides suggest it: the crash guard
needs unwinding.

## Before you finish a change

```sh
cargo test -p <crates you touched>
cargo clippy -p <crates> --all-targets -- -D warnings
(cd apps/myapp && npm run check && npm run lint && npm test)    # when you touched the frontend
cargo xtask ci
```

Keep the tree building at every step. Each working session, also append a terse entry to a
gitignored dev log (see [agents.md](agents.md)); that log plus a green tree is how the next person
or agent picks up after an interrupted session.

## The gate: `cargo xtask ci`

It runs eight steps in order and stops at the first failure, printing a summary of what passed,
what failed and what was skipped. The commands are from `cmd_ci` in `xtask/src/main.rs`:

| Step | Command | Catches |
|---|---|---|
| `fmt` | `cargo fmt --all -- --check` | Unformatted code |
| `web` | `npm ci` when `apps/myapp/node_modules` is missing, then `npm run check`, `npm run lint`, `npm run test`, `npm run build` (in `apps/myapp`) | Type errors, lint findings, failing component tests, a frontend that does not build. It also produces the `dist/` the next steps need, so it runs before clippy |
| `clippy` | `cargo clippy --workspace --locked --all-targets -- -D warnings` | Lints, including the no-panic rules; also builds examples |
| `layers` | The layer check (`cargo xtask layers`) | An upward dependency, a UI or webview crate below the UI layer, an unregistered crate |
| `test` | `cargo nextest run --profile ci --workspace --locked --lib --bins --tests` | Behaviour. Falls back to `cargo test` without nextest |
| `panic_hunt` | `cargo test --locked -p myapp-engine --test panic_hunt -- --ignored` | A command that panics or hangs on bad params |
| `doctest` | `cargo test --workspace --locked --doc` | Broken examples in doc comments (nextest does not run doctests) |
| `wasm` | `cargo check --target wasm32-unknown-unknown -p myapp-doc -p myapp-ops -p myapp-format -p myapp-engine -p myapp-shell` | OS assumptions in the core |

A passing run ends with:

```text
CI summary: all 8 steps passed (fmt, web, clippy, layers, test, panic_hunt, doctest, wasm)
```

`--locked` makes each step use `Cargo.lock` as it is. `cargo xtask` is a plain `cargo run`, which
creates or refreshes the lock file before the gate starts, so commit the refreshed `Cargo.lock`
whenever a manifest changes, and `package-lock.json` whenever `package.json` changes (`npm ci`
needs them to agree). The `ci` profile in `.config/nextest.toml` collects every failure in one run
(`fail-fast = false`), kills a hanging test (`slow-timeout = { period = "60s", terminate-after = 10 }`)
and repeats failures at the end.

Common failures:

| Symptom | Cause and fix |
|---|---|
| Fails at `fmt` right after a rename | Run `cargo fmt --all` once |
| Fails at `web` with `npm` not found | Node is not on `PATH` for the shell running xtask; load it (for example `nvm use`) |
| Fails at `clippy` or `test` with a `frontendDist` error | `apps/myapp/dist` is missing: run `cargo xtask web` |
| "Cargo.lock is up to date" fails in CI | A manifest changed and the lock file was not committed. Run any cargo command locally and commit `Cargo.lock` |
| `cargo xtask layers` reports `<crate>: not in the layering table` | Add the crate to `TABLE` in `xtask/src/layers.rs` (see [../recipes/add-crate.md](../recipes/add-crate.md)) |
