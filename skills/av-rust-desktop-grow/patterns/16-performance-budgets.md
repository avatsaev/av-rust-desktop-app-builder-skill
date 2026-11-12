# Performance as a tracked number

**Add it when:** A slow path has been fixed once and must stay fixed.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

- Benchmarks are `criterion` benches, or examples that print JSON.
- A budgets file names each scenario, its metric and its limit. `enforce = false` marks a target the code does not meet yet: it is reported, and does not fail the build.
- `cargo xtask perf` runs the benches, checks budgets and compares against a recorded baseline. A scheduled CI job runs it nightly.
- Add a frontend bundle-size budget to the same file: a scenario that measures the built `apps/myapp/dist` and a limit for it. *(reasoned)* Also budget the serialised size of the view for a large document, since the whole view is sent on every change.

## Where it goes

Suggested homes: `perf/budgets.toml`, `xtask/src/perf.rs` (add the `perf` command to `xtask/src/main.rs`) and `.github/workflows/perf-nightly.yml`. No new workspace crate beyond bench targets; register any you add in `xtask/src/layers.rs`.

## How it fits the seams

- Benchmarks drive the engine through `Session::execute` or lower-layer functions, the same entry points as tests; the view-size scenario calls `control::view` directly.
- Budgets are checked by xtask, the same single place that defines green; `perf` runs on a schedule rather than inside `cargo xtask ci`.
- Immutable snapshots and the revision counter give stable scenarios to measure.

## Done when

- [ ] Each fixed slow path has a scenario, metric and limit in the budgets file.
- [ ] `enforce = false` entries are reported but do not fail.
- [ ] The nightly job runs `cargo xtask perf` and compares to the baseline.
- [ ] The frontend bundle size and the view size have budgets.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
