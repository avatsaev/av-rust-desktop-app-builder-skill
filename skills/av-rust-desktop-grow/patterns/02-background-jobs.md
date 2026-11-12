# Background jobs with progress and cancel

**Add it when:** A command takes longer than a frame or two.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

Anything slow (parsing a large file, a network call, a computation) must not run inside a command on the owner thread, or every other request waits. The basic pattern is always the same three steps:

1. A worker thread does the slow part from a snapshot and has no access to the `Session`.
2. It sends the result over a channel to the owner thread. *(reasoned)* There is no frame loop and no repaint to request: the worker's message is a new `Request` variant on the same `std::sync::mpsc` channel that the Tauri commands and the control socket already use.
3. The owner thread applies the result as one command, and the view goes out as usual: it compares the view with the last one sent and emits the `view` event if it differs.

The template's control server already works in this shape: socket threads forward requests over a channel and the owner thread answers them. Threads in the architecture: the owner thread owns the `Session` and the shell, and commands run there; the Tauri commands and the control-socket threads only forward envelopes and wait for the reply; slow work becomes a background job; data-parallel work inside an algorithm uses rayon, on native targets only.

The full version, with progress and cancel (engine side): a command opts in by doing its heavy work through a job.

- The work closure runs on a worker thread against a snapshot, with a context that carries progress and a cancellation flag. The model is never touched by a worker.
- Its result is applied on the owner thread as one undo step, through the same path as `Session::execute`, so history and everything else behave as for a synchronous command.
- `Session::execute` still runs everything inline, so tests, the CLI and scripts see no difference. `Session::start` runs a job-capable command on a worker and returns a job id. Where the earlier native design had `Session::poll_jobs` called every frame, here a finished worker sends its message to the owner thread, which applies it. *(reasoned)*
- On wasm, where there are no threads, `start` runs inline behind the same API.
- While a job runs on a document, commands that would edit that document are disabled with a message naming the job (the menu item's `reason`, shown as a tooltip).
- A panic in the worker becomes an error and the document is unchanged.
- `jobs.list` and `jobs.cancel` are commands, so automation can wait for a job and cancel it.

In the view:

- Progress is part of the view, throttled so a fast worker does not make the owner thread serialise and emit the whole view hundreds of times a second. *(reasoned)*
- The frontend draws a progress bar and a cancel button from the view and sends `jobs.cancel`; it keeps no job state of its own. *(reasoned)*

## Where it goes

Suggested homes: `crates/engine/src/jobs.rs` (L5, `engine`); the new `Request` variant in `crates/shell/src/control.rs` and its handling in `AppShell::answer` (L6); the owner-thread loop that receives it in `apps/myapp/src-tauri/src/bridge.rs`; the progress component in `apps/myapp/src/components/`. Worker threads are native only; gate with `cfg(not(target_arch = "wasm32"))` and keep the inline path for wasm. No new crate, so nothing to register.

## How it fits the seams

- Applying a result goes through the same path as `Session::execute`: one history step, revision bump, no rollback code.
- The worker reads an immutable snapshot, so it needs no lock and never sees a half-applied edit.
- `jobs.list` and `jobs.cancel` are registry commands; the `enabled` predicate of editing commands reports the running job.
- Worker messages reach the owner thread over the same channel as webview and socket requests, so a job result and a click never race.
- `Session::execute` stays inline, so the CLI and tests are unchanged.

## Done when

- [ ] A job-capable command gives the same result via `execute` (inline) and `start` plus the owner-thread message.
- [ ] A test where the worker panics: an error is returned and the document is unchanged.
- [ ] Cancel stops the work and leaves the document unchanged; `jobs.list` / `jobs.cancel` have tests.
- [ ] Editing commands are disabled, with a message naming the job, while it runs.
- [ ] A shell test shows progress in the view, throttled.
- [ ] `cargo xtask wasm` still passes (inline path).

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
