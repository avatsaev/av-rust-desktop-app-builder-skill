# Actions, macros and batch

**Add it when:** Users repeat sequences.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

A recorded action is a list of `(id, params)`. Add one field to `CommandSpec` beyond the template's, `journal: bool`, which is false for queries so that they are not recorded. Recording happens in `Session::execute`; replay calls `execute`. Batch processing is the CLI applying one recording to many files.

The frontend only needs record, stop, play and the list of recordings, as commands and view data. *(reasoned)*

## Where it goes

Suggested home: `crates/engine/src/cmd.rs` (L5, where `CommandSpec` lives; adding the field means updating every `specs()` module) plus a CLI subcommand in `apps/myapp-cli`; a recordings panel, if wanted, in `apps/myapp/src/components/`. No new crate.

## How it fits the seams

- Recording hooks `Session::execute`, the single entry point, so the webview, the CLI and the control socket are recorded the same way.
- Replay is just more `execute` calls; ids and params are JSON, so a recording is plain data.
- The registry gains the `journal` flag; queries set it false.

## Done when

- [ ] Queries are not recorded; mutating commands are.
- [ ] A recording replays to the same state in a test.
- [ ] A batch test runs one recording over several files via the CLI.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
