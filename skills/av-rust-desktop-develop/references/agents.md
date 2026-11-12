# Working with coding agents, and contribution rules

The architecture is built to be driven by agents as well as people. `myapp` stands for the
project's machine name.

## What an agent can do

- An agent discovers what the app can do with `myapp-cli commands` or `engine.commands`, and what
  state it is in with `document.inspect` or `ui.inspect`. `ui.inspect` returns the view: exactly
  what the frontend draws, including the generated menus with their enabled states and reasons.
- It verifies its own UI work by drawing the frontend with `npm run snapshot` and reading the
  image, and by printing the view with `cargo run -q -p myapp-shell --example view` (see
  [verify.md](verify.md)).
- `AGENTS.md` at the repository root states the rules and the commands to run before finishing.
  Read it first, and keep it current when a rule or command changes.
- There are two toolchains. Rust work runs with cargo; frontend work runs with npm in `apps/myapp`.
  Run `cargo xtask web` before any cargo command that compiles the app, because Tauri embeds
  `apps/myapp/dist`. An agent that edits TypeScript or React code must run `npm run check`,
  `npm run lint` and `npm test` there too.
- Keep the frontend thin when an agent writes it: if a change needs logic or state, it belongs in
  Rust (an engine command, or `UiState` in `crates/shell`), not in a component.
- When several agents work in one checkout, give each its own build directory
  (`CARGO_TARGET_DIR=target/agent-<name>`) so they do not wait on Cargo's build lock, and put new
  commands in new modules rather than growing shared files. The frontend has one shared output,
  `apps/myapp/dist`: run `npm run build` once, after the frontend changes have landed, not in parallel.

## The dev log

Keep a terse, gitignored dev log entry per working session: what landed, numbers (Rust and
frontend test counts, timings, sizes), and what is still open. That log plus a green tree is how the
next person or agent picks up after an interrupted session. Keep the tree building at every step.

## Contribution rules worth adopting

- **Check before you start.** Read the issue and search open pull requests for the same fix.
- **Verify, don't guess.** Open a definition before using it; confirm the cause in the code.
- **Keep fixes narrow and tested.** Fix what the issue describes, where the bug is, with a test that
  fails without the fix.
- **Review your own diff** before opening a pull request: identifiers exist, the test fails without
  the fix, nothing unrelated changed, the description is true.
- **Report only what ran.** Say what you tested and what you could not (for example "not run on
  macOS or Windows").
- **`main` changes through pull requests only.**
- **Keep secrets and personal details out** of the repository, logs and requests.
- **Don't change CI in a feature or fix pull request.**

Stop and ask before anything hard to undo: publishing, releases, secrets, spending money,
destructive git.
