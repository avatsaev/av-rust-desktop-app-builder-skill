# Review checklist for any change

Use this before calling a change done and when reviewing someone else's.

- [ ] Is the behaviour a command, with an id that will never need renaming?
- [ ] Is the logic in the lowest layer that fits?
- [ ] Is any logic or state in TypeScript that belongs in Rust?
- [ ] Can any input make it panic, hang or allocate without bound? (Everything the webview sends is
      input too.)
- [ ] Is there a test that fails without the change?
- [ ] Does the webview get a new permission, and is it needed?
- [ ] For UI: did someone look at a rendered image (`npm run snapshot`), in both themes?
- [ ] Does `cargo xtask ci` pass?

## Conventions that follow from the rules

Check the change against these as well.

- **Ids are public API.** Command ids and control methods are used by scripts and agents. Never
  rename one after a release.
- **Errors are for the reader.** An error says what was wrong and, where possible, what would be
  right: `` `id` must be a non-negative integer, got a string``.
- **Disabled explains itself.** A command that cannot run now returns the reason. It becomes the
  menu item's tooltip and the message an agent reads.
- **Guards say why.** A check that looks removable carries a comment saying what it prevents.
- **Machine names are lowercase, product names are not.** Crates, binaries and ids are `myapp`;
  everything a user reads says `MyApp`.

## Frontend extras

- Components take a `Backend` and props; only `src/lib/backend.ts` imports `@tauri-apps/api`.
- No `fetch`, storage or document state in TypeScript.
- Colours come from `tokens.css`, defined in both themes (`tokens.test.ts` enforces it).
- A checkbox or toggle shows the document's state, not the click.
- `types.ts` matches what the shell sends, and `docs/control-protocol.md` matches `control.rs`.
- Every interactive widget has an accessible label, and the component test finds it by that label.
