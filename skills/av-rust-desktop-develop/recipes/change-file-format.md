# Change the file format

Paths are inside the project; `myapp` stands for the project's machine name and the format name.
The format lives in `crates/format` (L3): bytes in, model out, and back. It has no file-system
access, so the engine does the reading and writing and the core stays buildable for wasm32.

## Which change is it?

- **A new optional field.** Add it to the model in `crates/doc` with `#[serde(default)]`. Older
  files still load, and `VERSION` stays.
- **A change an older build must not misread.** Bump `VERSION` in `crates/format` and add a
  migration arm for the previous version in `decode`.
- **Always** extend the hostile-file test with the new failure modes.

Also keep the model's own rules (`crates/doc`): everything derives `Clone`, `PartialEq`,
`Serialize` and `Deserialize`; invariants are checked in `validate()` with an explicit cap on every
size; identity is a typed id, never an index.

## The envelope

`crates/format/src/lib.rs` carries a format name and a version from the first release:

```rust
pub const FORMAT: &str = "myapp";
pub const VERSION: u32 = 1;
/// File extension, without the dot.
pub const EXTENSION: &str = "myapp";
/// Largest file `decode` accepts.
pub const MAX_BYTES: usize = 16 * 1024 * 1024;

pub enum FormatError {
    TooLarge { bytes: usize },  // "the file is {bytes} bytes; the limit is {MAX_BYTES}"
    NotOurs(String),            // "not a {FORMAT} file: {0}"
    Newer { found: u32 },       // "the file was written by a newer version (format {found}; this build reads up to {VERSION})"
    Invalid(String),            // "the file is damaged: {0}"
}
```

`decode` reads the two envelope fields first (`Head { format, version }`), so a foreign file or one
from a newer version is refused with a message that says so, and an older version has one place to
be migrated:

```rust
pub fn decode(bytes: &[u8]) -> Result<Document, FormatError> {
    if bytes.len() > MAX_BYTES {
        return Err(FormatError::TooLarge { bytes: bytes.len() });
    }
    let head: Head = serde_json::from_slice(bytes).map_err(|e| FormatError::NotOurs(e.to_string()))?;
    if head.format != FORMAT {
        return Err(FormatError::NotOurs(format!("format is `{}`", head.format.chars().take(40).collect::<String>())));
    }
    if head.version > VERSION {
        return Err(FormatError::Newer { found: head.version });
    }
    // Older versions migrate here: match on `head.version` and convert before validating.
    let body: Body = serde_json::from_slice(bytes).map_err(|e| FormatError::Invalid(e.to_string()))?;
    body.document.validate().map_err(|e| FormatError::Invalid(e.to_string()))?;
    Ok(body.document)
}
```

The migration point is the comment line: match on `head.version`, parse the old body shape,
convert it to the current `Document`, and only then validate. `encode` always writes the current
`VERSION`. The engine refuses an oversized file before reading it (`MAX_BYTES` is checked against
file metadata in `file.open`), so keep that constant the single limit.

Write down the format version policy: what an older build does with a newer file. The template's
answer is to refuse it with the `Newer` message, never to half-read it.

## Steps

1. Change the model in `crates/doc` (add `#[serde(default)]` for new optional fields; extend
   `validate()` and the caps).
2. For a breaking change: bump `VERSION`, keep a parser for the previous body shape, and add the
   migration arm in `decode` before `validate()`.
3. Add a migration test: bytes of the previous version decode to the expected current model.
4. Extend the round-trip test (`decode(&encode(&doc)?)? == doc`) with the new data.
5. Extend the hostile-file test with the new failure modes. The template's covers: empty input,
   a foreign `format`, a `version` of 999, an envelope with no body, a duplicate id, and
   `MAX_BYTES + 1` bytes:

   ```rust
   #[test]
   fn hostile_files_are_errors_not_panics() {
       assert!(matches!(decode(b""), Err(FormatError::NotOurs(_))));
       assert!(matches!(decode(b"{\"format\":\"other\",\"version\":1}"), Err(FormatError::NotOurs(_))));
       assert_eq!(decode(b"{\"format\":\"myapp\",\"version\":999}"), Err(FormatError::Newer { found: 999 }));
       assert!(matches!(decode(b"{\"format\":\"myapp\",\"version\":1}"), Err(FormatError::Invalid(_))));
       let twice = br#"{"format":"myapp","version":1,"document":{"title":"t","items":[{"id":1,"text":"a"},{"id":1,"text":"b"}]}}"#;
       assert!(matches!(decode(twice), Err(FormatError::Invalid(m)) if m.contains("more than once")));
       assert!(matches!(decode(&vec![b' '; MAX_BYTES + 1]), Err(FormatError::TooLarge { .. })));
   }
   ```
6. Run `cargo test -p myapp-doc -p myapp-format`, then `cargo xtask ci`.

## Rules

- Never panic on a file: every failure is a `FormatError`. Input is hostile: cap sizes and bound
  recursion in any new nested structure.
- If the app has no files, remove the file commands instead of leaving them half-working.
