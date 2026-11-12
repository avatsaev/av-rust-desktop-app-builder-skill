# Fix a bug

Paths are inside the project; `myapp` stands for the project's machine name.

## Steps

1. Reproduce it as a failing test at the lowest layer that shows it: an algorithm in its own crate,
   a command through `Session::execute`, a menu click or shortcut through a shell test in
   `crates/shell/src/tests.rs`, a component through a vitest component test in `apps/myapp/src`.
2. Fix the cause where it is, not where it surfaces.
3. For a crash, the test must have panicked before the fix. Run it against the unfixed code first
   and confirm it fails the way the report says.
4. Keep the fix narrow: fix what the issue describes, where the bug is, with a test that fails
   without the fix. Do not refactor unrelated code in the same change.
5. Run the narrow tests, then `cargo xtask ci`. Before opening a pull request, review your own
   diff: identifiers exist, the test fails without the fix, nothing unrelated changed, the
   description is true. Report only what ran.

Check before you start: read the issue and search open pull requests for the same fix. Verify, do
not guess: open a definition before using it, and confirm the cause in the code.

## Checklist for a crash fix

People trust a desktop app with their work, and a crash loses it. A malformed file, a bad command
parameter, a corrupt settings file or a full disk must produce an error the user or agent can act
on, never a panic. When fixing a crash, look for each of these in the code around it, not just at
the line that panicked.

- **No panicking constructs in non-test code.** No `unwrap()`, `expect()`, `panic!`,
  `unreachable!`, `todo!` or `unimplemented!`. Return the crate's error type and propagate with `?`.
  Every crate root carries:

  ```rust
  #![forbid(unsafe_code)]
  #![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]
  ```

  `clippy.toml` allows them in tests only. An unfinished feature returns an "unsupported" error.
- **No `unsafe`.** The workspace sets `unsafe_code = "forbid"`. If one OS integration truly needs
  it, isolate it in its own small crate (e.g. `crates/<os-integration>`) with a `SAFETY:` comment on
  every block.
- **Input-derived numbers are hostile.** Use `get()` rather than `[i]` for indices that come from
  files, params or arithmetic on them. Use `checked_*` and `saturating_*` for lengths, offsets and
  counts. Guard division by zero and NaN. Cap every allocation sized by input.
- **Bound recursion** with depth limits or seen-sets: data can be deep or cyclic.
- **Don't cascade.** Recover from lock poisoning
  (`lock().unwrap_or_else(PoisonError::into_inner)`) and treat thread joins as `Result`s.
- **The crash guard is a net, not a licence.** The engine catches a panic that escapes a command,
  and the app catches one around file operations, reports it and keeps the open state. That needs
  `panic = "unwind"` (the default; never set `"abort"`). Do not rely on it: fix the panic.
- **Prove it.** The regression test panicked before the fix. The `panic_hunt` test runs every
  registered command with adversarial params and fails on any panic or hang:

  ```sh
  cargo test -p myapp-engine --test panic_hunt -- --ignored
  ```

  If the crash came from a param shape the fuzz does not try, add it to `adversarial_params()` in
  `crates/testkit/src/lib.rs`; if the command needs state to reach the crashing code, extend
  `fresh()` in `crates/engine/tests/panic_hunt.rs`. See [add-command.md](add-command.md).
- **Errors are for the reader.** Make the new error say what was wrong and, where possible, what
  would be right: `` `id` must be a non-negative integer, got a string``.
- **Guards say why.** A check that looks removable carries a comment saying what it prevents.

Where the fix is, add the test: model rules in `crates/doc`, file parsing in `crates/format` (extend
the hostile-file test, see [change-file-format.md](change-file-format.md)), command behaviour in
the `<area>_cmds.rs` tests.
