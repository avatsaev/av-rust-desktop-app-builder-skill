# Growing the native format

**Add it when:** The model gains fields or gets large.

> `myapp` in paths stands for the project's machine name. Evidence: the engine-side design of this pattern is proven in a large production app on this architecture, whose shell is a native Rust UI toolkit. The webview-side parts are *(reasoned)* from the architecture and Tauri's documented capabilities; the label marks them wherever they appear. None of it is in the template or was built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

Changing the file format (day-to-day rules):

- A new optional field: add it to the model with `#[serde(default)]`. Older files still load, and `VERSION` stays.
- A change an older build must not misread: bump `VERSION` in `crates/format` and add a migration arm for the previous version in `decode`.
- Always extend the hostile-file test with the new failure modes.

As the format grows:

- **Make forgetting a field a compile error.** Give the format its own manifest structs instead of serialising the model types directly, and convert with exhaustive destructuring:

  ```rust
  let Item { id, text, done } = item;   // a new field in Item fails to compile here until it is saved
  ```

- **Stay backward compatible.** New manifest fields get `#[serde(default)]`. Bump the format version only for a change an older build must refuse.
- **Save incrementally.** A large app's bundle is a small versioned manifest plus content-addressed, compressed chunks (named by their BLAKE3 hash), so a save writes only new chunks and garbage-collects unreferenced ones.
- **Keep what you do not understand.** When importing a foreign format, carry unknown blocks through verbatim so a round trip does not destroy them.

The format is below the shell, so this pattern changes nothing in the webview unless a new field is shown: then add it to `document.inspect`'s output and to `apps/myapp/src/lib/types.ts` together.

## Where it goes

Suggested homes: `crates/format/src/lib.rs`, `crates/format/src/convert.rs` (exhaustive destructuring), `crates/format/src/manifest.rs` (L3, existing crate). The model stays in L1 `doc`. A chunk-store dependency (BLAKE3, compression) must pass the licence allowlist. No new crate.

## How it fits the seams

- Saving encodes an immutable snapshot, so it can run on a worker or the autosave thread.
- Open and save remain commands (`file.*`); only their codec changes.
- The format is bytes in and out of your own format, hence L3, below the engine.

## Done when

- [ ] Old-file load test for each new `#[serde(default)]` field; migration test for each `VERSION` bump.
- [ ] The hostile-file test covers the new failure modes (bounds, sizes, recursion).
- [ ] Adding a model field without saving it fails to compile in `convert.rs`.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
