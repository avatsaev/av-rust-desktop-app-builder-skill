# Scaffold a project

`scripts/new-project.sh` writes the template to a new directory under the names you choose. It
reads only the template inside this skill and writes only inside the output directory.

## Decide the names first

Ask the user for these before running the script. They are hard to change later.

| Placeholder in the template | Script option | Meaning | Appears in |
|---|---|---|---|
| `myapp` | `--name` (required) | Machine name: the crate prefix (`myapp-engine`), the binaries, the npm package, the file extension and the format name | Manifests, `use myapp_…`, `xtask/src/layers.rs`, `crates/format`, `package.json` |
| `MyApp` | `--title` | Product name in everything a user reads | `tauri.conf.json` (`productName`, window title), `index.html`, `--help`, messages, the documents |
| `MYAPP` | from `--name` | Environment variable prefix (`MYAPP_LOG`, `MYAPP_CONTROL_PORT`) | `apps/myapp/src-tauri/src/main.rs`, `logging.rs` |
| `com.example.myapp` | `--id` | Reverse-DNS application id | `tauri.conf.json` (`identifier`) |
| `__AUTHOR__` | `--author` | Copyright holder | `LICENSE-MIT`, `NOTICE` |

Rules:

- **`--name`**: lowercase ASCII letters and digits, starting with a letter, and not one of the
  template's own crate names (`doc`, `ops`, `format`, `engine`, `shell`, `testkit`, `ui`, `cli`,
  `web`, `xtask`). No hyphens: the name becomes part of Rust identifiers.
- **`--title`**: letters, digits, spaces, dots, hyphens and underscores. Defaults to the name with
  its first letter capitalised.
- **`--id`**: use a domain the user controls. It is how the operating system identifies the app
  (settings directory, bundle identifier, file associations), and changing it after release
  orphans users' data. The default, `com.example.<name>`, is for experiments only.
- **`--author`**: defaults to `The <Title> Authors`.

Machine names are lowercase, product names are not: crates, binaries and command ids say `myapp`;
everything a user reads says `MyApp`.

## Run the script

```sh
bash scripts/new-project.sh ../notepad --name notepad --title NotePad --id org.example.notepad
```

```text
wrote 99 files to /home/you/notepad
  name: notepad   title: NotePad   id: org.example.notepad
initialised a git repository
formatted the sources and generated Cargo.lock (commit it)
installed the frontend's dependencies (apps/notepad/node_modules)

next, in /home/you/notepad:
  cargo xtask ci                          the gate; all eight steps should pass before your first change
  cargo run -p notepad                      the window (after the gate, or `cargo xtask web`, built the frontend)
  cargo run -q -p notepad-cli -- commands   every command the app has
```

| Option | Effect |
|---|---|
| `<dir>` | Where to create the project. It must not exist, or must be empty |
| `--name`, `--title`, `--id`, `--author` | The names, as above |
| `--no-git` | Do not run `git init`. It is also skipped when the directory is already inside a git work tree |
| `--no-install` | Do not run `cargo fmt --all`, `cargo generate-lockfile` and `npm ci` (for a machine without the tools or without network) |
| `--verify` | Run the gate, `cargo xtask ci`, at the end |

What it does, in order:

1. Validates the names and refuses an output directory that is not empty (exit status 2).
2. Copies the template, renaming placeholders in paths and contents. Binary files (the icons) are
   copied as they are. 99 files.
3. Runs `git init`.
4. Runs `cargo fmt --all`. A name of another length moves rustfmt's line breaks, and without this
   the gate fails at its first step.
5. Runs `cargo generate-lockfile` (needs network access). Commit `Cargo.lock`: an application pins
   its dependencies.
6. Runs `npm ci` in `apps/<name>`: the frontend's dependencies, exactly as the template's
   `package-lock.json` pins them (needs network access).
7. With `--verify`, runs `cargo xtask ci`.

The script makes no commit. When cargo or npm is not on `PATH` it writes the files, says which
commands remain, and exits with status 1.

## After scaffolding

1. Run the gate and each frontend: [first-run.md](first-run.md).
2. Work through [day-0-checklist.md](day-0-checklist.md).
3. Replace the sample checklist domain with the user's: load the `av-rust-desktop-design` skill.
