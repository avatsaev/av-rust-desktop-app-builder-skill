---
name: av-rust-desktop-bootstrap
description: "Start a new native Rust desktop app on Tauri 2 with a React + TypeScript webview frontend, from an empty directory: install the toolchain (rustup, clippy, rustfmt, the wasm32 target, Node.js, the webview's system packages, cargo-nextest) with scripts/setup.sh, scaffold a buildable project from the bundled template with scripts/new-project.sh (Cargo workspace with a headless engine and command registry, undo, file format, Tauri window, CLI, control channel for agents, cargo xtask ci gate), run the first build and every frontend, and fix first-run problems. Use when asked to 'create a new Rust desktop app', 'start a Tauri project', 'scaffold the app', 'set up my machine for the project', 'install the Rust and Tauri tools', 'why does the first build fail', or for the Day-0 checklist."
---

# Bootstrap a Rust desktop app (Tauri + React)

From an empty directory to a running desktop app and CLI. This skill carries two scripts and a
complete project template: a small checklist app with undo, a file format, menus, shortcuts, a
Tauri window whose webview is a thin React frontend, a headless CLI, a control channel for agents,
and a gate (`cargo xtask ci`) that enforces the architecture's rules. Scaffold it, see it pass,
then replace the sample domain with the user's.

In examples `myapp` stands for the project's machine name and `MyApp` for its product name. Script
paths are relative to this skill's directory.

## When to use

- A new Rust desktop app is to be created, or the user wants to try this stack.
- A machine (or a CI image, or a container) must be prepared to build such a project.
- The first build, the first gate run or a first launch fails.
- Not for an existing project's daily work: load `av-rust-desktop-develop` for that.

## Files

| File | What it is |
|---|---|
| [scripts/setup.sh](scripts/setup.sh) | Checks for and installs the prerequisites. `--check` only reports |
| [scripts/new-project.sh](scripts/new-project.sh) | Writes the template to a new directory under the names you give |
| `assets/template/` | The project template the script copies. Do not copy it by hand: paths and names are encoded |
| [references/prerequisites.md](references/prerequisites.md) | What is needed on each platform, what `setup.sh` does and does not do |
| [references/scaffold.md](references/scaffold.md) | Choosing the names, every script option, what the script does |
| [references/first-run.md](references/first-run.md) | The first gate run, and running the window, the CLI, the snapshot tool and the control socket, with expected output |
| [references/template-tour.md](references/template-tour.md) | Every part of the generated project and what to look for in it; reading order |
| [references/troubleshooting.md](references/troubleshooting.md) | Symptoms, causes and fixes |
| [references/day-0-checklist.md](references/day-0-checklist.md) | What must be true before the first feature |

## Procedure

1. **Ask for what cannot be guessed.** The machine name, the product name, the application id (a
   reverse-DNS id under a domain the user controls) and the copyright holder. Rules for each:
   [references/scaffold.md](references/scaffold.md). Do not invent an application id: it cannot be
   changed after release without orphaning users' settings.

2. **Check the machine.**

   ```sh
   bash scripts/setup.sh --check
   ```

   Exit status 0 means everything required is present. Otherwise install:

   ```sh
   bash scripts/setup.sh --yes              # add --headless for CI, containers and remote machines
   ```

   The script installs system packages (apt, dnf or pacman: a C toolchain, pkg-config, and the
   WebKitGTK development files Tauri builds against on Linux), Rust through rustup with clippy,
   rustfmt and the wasm32 target, Node.js through nvm, and `cargo-nextest`. Where it cannot get
   root (no terminal for the `sudo` password) it prints the exact command under "To finish, run":
   give that command to the user, then run `--check` again. Unlike a pure-Rust project, this one
   does not compile without the system packages. Details and the other platforms:
   [references/prerequisites.md](references/prerequisites.md).

3. **Scaffold.**

   ```sh
   bash scripts/new-project.sh ../notepad --name notepad --title NotePad --id org.example.notepad
   ```

   The script refuses a directory that is not empty, renames every placeholder, and runs
   `git init`, `cargo fmt --all`, `cargo generate-lockfile` and `npm ci`. Add `--verify` to run the
   gate at the end.

4. **Run the gate** in the new directory. Every one of its eight steps must pass before the first
   change:

   ```sh
   cargo xtask ci
   ```

   ```text
   CI summary: all 8 steps passed (fmt, web, clippy, layers, test, panic_hunt, doctest, wasm)
   ```

5. **Run the pieces** and look at them: the window, the CLI, and a snapshot of the UI (open the
   PNG). Commands and expected output: [references/first-run.md](references/first-run.md).

6. **Finish Day 0**: [references/day-0-checklist.md](references/day-0-checklist.md). Commit,
   including `Cargo.lock` and `apps/<name>/package-lock.json`.

7. **Hand over.** Replacing the sample checklist domain with the user's is the
   `av-rust-desktop-design` skill; adding features is `av-rust-desktop-develop`.

## Hard rules

- Never install anything without the user's consent: run `setup.sh --check` first, and pass `--yes`
  only when the user asked for the machine to be set up.
- Never scaffold into a directory that has files, and never edit `assets/template/` to fit one
  project: change the generated project instead.
- Do not start replacing the sample domain until the gate passes on the untouched scaffold. A
  failure there is a machine problem, and it is far easier to see before the code changes.
- Report only what ran. If the window could not be opened (no display) or the snapshot could not
  be rendered (no headless browser), say so.

## What has and has not been exercised

On 2026-11-12 the scripts and the template were run in fresh Linux containers (Ubuntu, Fedora, Arch): see
[references/first-run.md](references/first-run.md#what-was-run) for exactly what. macOS and
Windows, native file dialogs, every bundle format other than `.deb`, signing, and the generated
GitHub Actions workflow have **not** been run. Say so when the user's platform is one of them, and
expect to fix first-run problems there.

## Golden rules

These hold in every project built on this architecture. Each is enforced by tooling in the project.

1. **The core is Rust; the frontend is thin.** Web technology (React, TypeScript) lives only in the webview frontend, `apps/myapp/src`. It draws the view it is sent and sends command ids: no business logic, no document state, no file or network access in TypeScript.
2. **Never crash.** Non-test Rust code has no `unwrap`, `expect`, `panic!`, `unreachable!`, `todo!` or `unimplemented!`, and no `unsafe`. Return the crate's error type. Input is hostile: check bounds, cap sizes, bound recursion. A crash fix ships with a test that panicked before it.
3. **Everything is a command.** User-visible behaviour is a command in `crates/engine/src/*_cmds.rs` with an id, label, menu, shortcut, params doc, `enabled`, `run` and tests. The frontend, the CLI and the control channel dispatch ids.
4. **Layering is enforced.** A crate depends only on lower layers; nothing below the app binary uses tauri, wry or tao. `cargo xtask layers` checks it; register a new crate in `xtask/src/layers.rs`.
5. **UI state is data.** What automation should see is one serde struct in `crates/shell`, and the frontend draws exactly what `ui.inspect` returns. Colours come from the tokens in `tokens.css`. Look at a rendered image (`npm run snapshot`) before calling a UI change done.
6. **The webview gets the least it needs.** Two commands and one event; no plug-in permissions for the main window, a strict CSP, no remote content in it. What the webview sends is validated in Rust like any other input.
7. **The core builds for wasm32.** File-system code is `cfg(not(target_arch = "wasm32"))` or behind `Services`. `cargo xtask wasm` checks it.
8. **Tests are the gate.** Every change comes with tests. `cargo xtask ci` is the single definition of green, locally and in CI.
9. **Permissive licences only.** Crates, npm packages and bundled assets come from an allowlist (MIT, Apache-2.0, BSD, ISC, OFL-1.1, CC0-1.0, CC-BY-4.0 and similar); every bundled asset gets a row in `ATTRIBUTION.md`.

## Related skills

- `av-rust-desktop-architecture`: the stack, the nine rules, layers, the five seams, the webview boundary, threads.
- `av-rust-desktop-design`: fit a kind of app into the architecture; replace the sample domain.
- `av-rust-desktop-develop`: add a command, query, crate, component or plug-in; fix a bug; verify by rendered image.
- `av-rust-desktop-grow`: background jobs, large data, a canvas view, dialogs, preferences, autosave, web content windows, MCP, plug-ins.
- `av-rust-desktop-ship`: build profiles, the gate, CI, the Tauri bundler, release.
