# Generated status documents

**Add it when:** A hand-kept list starts to drift.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

Anything that can be derived from code should be. A large app generates its menu coverage list from the registry (`cargo xtask parity`) and a scorecard from checklist files (`cargo xtask scorecard`), and its gate checks that the committed scorecard is current.

The same idea gives you a command reference for nothing: print `command.list` (the control protocol's `engine.commands` returns it).

## Where it goes

Suggested homes: `xtask/src/scorecard.rs` (generator and freshness check wired into `cargo xtask ci`), `docs/scorecard.md` and `docs/parity-checklist.md` (generated output). No new workspace crate.

## How it fits the seams

- The registry is the source of truth, so generated lists are always complete: menus, shortcuts and `command.list` all come from it.
- The freshness check lives in the gate, so a stale generated file fails the same `cargo xtask ci` as any other check.

## Done when

- [ ] The generator runs from xtask and its output is committed.
- [ ] The gate fails when the committed file is out of date.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
