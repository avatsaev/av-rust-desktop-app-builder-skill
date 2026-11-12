# The gate: `cargo xtask ci`

`cargo xtask ci` is the single definition of green, locally and in CI. In every path below `myapp`
stands for the project's machine name. The template's gate passed all eight steps when the template
was built (34 Rust tests, 17 frontend tests, the command fuzz and the wasm32 check).

## The eight steps

It runs, in order, and stops at the first failure:

| Step | Command | Catches |
|---|---|---|
| `fmt` | `cargo fmt --all -- --check` | Unformatted code |
| `web` | `npm ci` when `apps/myapp/node_modules` is missing, then `npm run check`, `npm run lint`, `npm run test`, `npm run build` in `apps/myapp` | Frontend type errors (`tsc --noEmit`), lint findings (oxlint), failing component tests (vitest), a frontend that does not build. Produces `apps/myapp/dist` |
| `clippy` | `cargo clippy --workspace --locked --all-targets -- -D warnings` | Lints, including the no-panic rules; also builds examples |
| `layers` | The layer check | An upward dependency, a webview crate below the app binary, an unregistered crate |
| `test` | `cargo nextest run --profile ci --workspace --locked --lib --bins --tests` | Behaviour. Falls back to `cargo test` without nextest |
| `panic_hunt` | `cargo test --locked -p myapp-engine --test panic_hunt -- --ignored` | A command that panics or hangs on bad params |
| `doctest` | `cargo test --workspace --locked --doc` | Broken examples in doc comments (nextest does not run doctests) |
| `wasm` | `cargo check --target wasm32-unknown-unknown` for the layered crates (`doc ops format engine shell`) | OS assumptions in the core |

## Why `web` runs before `clippy`

Tauri embeds `apps/myapp/dist` into the desktop binary at compile time. Any cargo command that
compiles the app, clippy included, needs `dist/` to exist. So the frontend is checked, tested and
built first. `dist/` is in `.gitignore`: a fresh clone has none until `web` (or `npm run build`) has
run.

## What `cargo xtask web` does

- Runs `npm ci` in `apps/myapp` when `node_modules` is missing.
- Then runs `npm run check` (`tsc --noEmit`), `npm run lint` (oxlint, type-aware, warnings are
  errors), `npm run test` (vitest) and `npm run build` (vite), in that order. The build is not
  optional.
- The lint is configured in `apps/myapp/.oxlintrc.json`. Beyond correctness rules it rejects
  the React hook rules, floating promises, `any`, a Tauri import outside
  `src/lib/backend.ts`, and network or storage globals (`fetch`, `localStorage` and the like).
- On Windows it runs `npm.cmd`, because `npm` is a script there.
- If the program cannot be started, the error says `is npm installed and on PATH?`.

## `--locked` and a stale lock file

`--locked` makes each cargo step use `Cargo.lock` as it is. It does not catch a stale lock file by
itself: `cargo xtask` is a plain `cargo run`, which creates or refreshes the lock file before the
gate starts. Locally that is convenient: commit the refreshed file. In CI it would hide the problem,
so the workflow runs `cargo metadata --locked` first, which fails when the committed lock file does
not match the manifests.

The frontend has its own lock file, `apps/myapp/package-lock.json`, and the gate installs from it
with `npm ci`, which fails when it disagrees with `package.json`. Commit both lock files.

## The xtask subcommands

```text
usage: cargo xtask <command>

commands:
  layers   enforce the crate dependency layering (xtask/src/layers.rs)
  web      the frontend: npm ci when needed, then type check, lint, tests and build (apps/myapp)
  wasm     cargo check --target wasm32-unknown-unknown for the layered crates
  test     workspace tests (cargo nextest when installed, else cargo test), then doctests
  ci       the gate: fmt --check, web, clippy -D warnings, layers, tests, panic_hunt, doctests, wasm
```

The alias that makes `cargo xtask <command>` work is in `.cargo/config.toml`: `xtask = "run -p
xtask --"`. xtask is plain Rust, so the gate behaves the same on every OS and needs nothing but cargo
and npm. Add project tasks (code generation, reports, release helpers) to `xtask` rather than as
shell scripts.

Facts about `xtask/src/main.rs`:

- `GATE_ARGS` is `["--workspace", "--locked"]`: the gate builds exactly what is committed.
- **Nextest fallback.** `cmd_test` runs `cargo nextest run --profile ci` when `cargo nextest
  --version` succeeds. Otherwise it prints `note: cargo-nextest is not installed, running cargo test
  (cargo install cargo-nextest --locked)` and runs `cargo test`. Either way it appends the scope and
  `--lib --bins --tests`; examples are built by clippy and doctests run apart.
- **`panic_hunt`** runs the ignored full-registry fuzz: every command, adversarial params, with
  `cargo test --locked -p myapp-engine --test panic_hunt -- --ignored`.
- **The summary.** `cmd_ci` prints `=== ci: <step> ===` before each step. On failure it prints a
  summary that names the failed step and the skipped ones, then exits with `ci failed at <step>`:

  ```text
  CI summary:
    ok    fmt
    ok    web
    FAIL  clippy: <error>
    skip  layers
    skip  test
    skip  panic_hunt
    skip  doctest
    skip  wasm
  ```

  When everything passes it prints `CI summary: all 8 steps passed (fmt, web, clippy, layers, test,
  panic_hunt, doctest, wasm)`.
- `cargo xtask layers` prints a table of every crate with its layer and workspace dependencies, then
  `layering: ok (<n> crates)` or one line per violation. A crate missing from the `TABLE` in
  `xtask/src/layers.rs` is a violation, so a new crate cannot skip the check.
- `cargo xtask wasm` checks every layered or standalone crate in the table.

## Adding steps to the gate

Add steps to `cmd_ci` in `xtask/src/main.rs` as the project grows. A step is a name and a function
returning `Result<(), String>` in the `steps` list:

```rust
let steps: &[Step] = &[
    ("fmt", || { /* ... */ }),
    ("web", cmd_web),
    // ...
    ("wasm", cmd_wasm),
];
```

Give the new step its own `cmd_*` function that returns a readable error; the summary lists steps
by name. A step that needs a built frontend must come after `web`. Examples of extra steps a large
app adds:

- A check that panel click handlers dispatch command ids.
- A check that generated documents are up to date.

## Test runner configuration

`.config/nextest.toml` has one profile, `ci`: no fail-fast, a hang timeout, and failures repeated at
the end of the output. There is no `gpu` test group: the template has no GPU tests. If you add tests
that each open a GPU device, add a test group that limits how many run at once *(reasoned)*.

```toml
# cargo-nextest (https://nexte.st): every test in its own process, in parallel across binaries.
#   cargo nextest run --workspace     # all tests except doctests
#   cargo test --doc --workspace      # nextest does not run doctests

# CI: collect every failure in one run, kill a hanging test, repeat failures at the end.
[profile.ci]
fail-fast = false
slow-timeout = { period = "60s", terminate-after = 10 }
failure-output = "immediate-final"
```
