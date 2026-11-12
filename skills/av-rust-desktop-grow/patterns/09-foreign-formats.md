# Foreign file formats

**Add it when:** Import or export of someone else's format.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

- One standalone L0 crate per format family, depending on no workspace crate, with its own format-level types, so it stays publishable on its own. The mapping to your model lives in an L4 `io` crate.
- Test parsers with round trips, a synthetic file generator, `proptest`, and a `cargo-fuzz` target per parser in `crates/<name>/fuzz/`.
- Test against real files. Corpora are fetched at pinned commits and checksum-verified by an xtask command and are never committed (keep the corpus directory in `.gitignore`). The tests that need them sit behind an opt-in `corpus` cargo feature, so a plain `cargo test` skips them.
- In CI: a corpus job runs the parsers against the real files, and fuzzing runs on demand.
- Input is hostile: check bounds, cap sizes, bound recursion; return the crate's error type.

## Where it goes

Suggested homes: `crates/<format>` (L0, standalone), `crates/io` (L4, maps to the model), `xtask/src/corpus.rs` and `xtask/src/corpus_pins.rs` (fetch and verify pinned corpora; add the command to `xtask/src/main.rs`). Register each new crate in `xtask/src/layers.rs` (`Class::Standalone` for the L0 crate, `Class::Layer(4)` for `io`); parser dependencies must pass the licence allowlist.

## How it fits the seams

- Import and export are commands in L5 that call the L4 `io` crate; the engine never parses bytes itself.
- Imported data enters the model as one edit through `Session::execute`, so a failed import changes nothing.
- File picking stays a `Services` hook on the owner thread; file-system access stays behind `cfg(not(target_arch = "wasm32"))` or `Services`; bytes-in/bytes-out parsers build for wasm32.

## Done when

- [ ] Round-trip, synthetic-generator and `proptest` tests; a fuzz target per parser.
- [ ] The L0 crate depends on no workspace crate (`cargo xtask layers`).
- [ ] The corpus is pinned by commit, checksum-verified, never committed, and gated by the `corpus` feature.
- [ ] No panics on malformed input.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
