# Prerequisites

What a machine needs to build, test and run a project made from the template, and what
`scripts/setup.sh` does about it.

## What is needed

- **Rust** stable, 1.95 or newer, installed with rustup, plus:

  ```sh
  rustup component add clippy rustfmt
  rustup target add wasm32-unknown-unknown
  ```

  The wasm32 target is for the gate's `wasm` step, which checks that the core stays free of
  file-system and OS assumptions. The app itself is not compiled to wasm.

- **Node.js** 22.12 or newer on an even (LTS) release line, with npm. It builds and tests the web
  frontend (React, TypeScript, Vite) and provides the Tauri command line (`npm run tauri`), so
  there is no `cargo install tauri-cli`.

- **Linux**: a C compiler, pkg-config, and the development files Tauri builds against: WebKitGTK
  (the webview; it brings GTK), librsvg and libxdo.

  | Distribution | Command |
  |---|---|
  | Debian, Ubuntu | `sudo apt install build-essential pkg-config libwebkit2gtk-4.1-dev librsvg2-dev libxdo-dev` |
  | Fedora, RHEL | `sudo dnf install gcc pkgconf-pkg-config webkit2gtk4.1-devel librsvg2-devel libxdo-devel` |
  | Arch | `sudo pacman -S gcc pkgconf webkit2gtk-4.1 librsvg xdotool` |

  These are required, not optional: the desktop crate does not compile without them, and so
  neither does the gate.

- **Windows**: the MSVC toolchain with the "Desktop development with C++" workload, and the
  WebView2 runtime (part of Windows 11 and of current Windows 10).
- **macOS**: the Xcode command line tools (`xcode-select --install`).
- **Optional**: `cargo install cargo-nextest --locked`, the parallel test runner. Without it the
  gate falls back to `cargo test`.
- **Running the window without a display** (CI, containers, remote machines): Xvfb.
- **Rendering snapshots** (`npm run snapshot`): a headless browser that Playwright downloads once
  per machine, `npm run snapshot:install` in `apps/<name>`. On a minimal Linux it also needs
  system libraries: `npx playwright install --with-deps chromium` (uses the package manager, so it
  needs root).

## What `setup.sh` does

```sh
bash scripts/setup.sh --check      # report only; exit 0 when everything required is present
bash scripts/setup.sh --yes        # install what is missing, without asking
```

| Option | Effect |
|---|---|
| `--check` | Report what is present and what is missing. Installs nothing |
| `--yes` | Install without asking. Needed when there is no terminal to ask on, which is the usual case for an agent |
| `--no-nextest` | Skip `cargo-nextest` |
| `--no-system` | Skip system packages |
| `--no-node` | Skip Node.js |
| `--headless` | Also install Xvfb |

In order:

1. **System packages** (Linux with apt, dnf or pacman): installs the ones that are missing, with
   `sudo` when not root. With pacman it downloads the package database first only when there is
   none (a fresh container); it never refreshes an existing one. On macOS it checks for the Xcode
   command line tools. On Windows it can
   only print what is required.
2. **Rust**: installs rustup when there is no Rust at all (minimal profile, with clippy, rustfmt
   and the wasm32 target), updates a toolchain older than 1.95, adds missing components and the
   target.
3. **Node.js**: when `node` is missing or too old, installs nvm and with it the current LTS
   release. An nvm that is already installed is used as it is.
4. **`cargo-nextest`** with `cargo install --locked`. It compiles from source, which takes a few
   minutes.
5. Prints a summary, and under "To finish, run" every command it did not run itself.

Exit status: 0 when everything required is present, 1 when something required is missing, 2 on a
usage error.

Things to know:

- **Nothing is installed without consent.** Without `--yes` the script asks before each
  installation, and when there is no terminal to ask on it installs nothing and lists the commands
  instead.
- **No root, no terminal.** When the script is not root and `sudo` would need a password it cannot
  ask for, it does not try. The system-package command appears under "To finish, run": give it to
  the user, then run `--check` again. The rest (Rust, Node.js, cargo-nextest) installs into the
  home directory and needs no root.
- **A new shell does not see the new tools.** rustup and nvm are set up through the shell profile.
  In a shell that was already open, load them yourself:

  ```sh
  source "$HOME/.cargo/env"
  . "$HOME/.nvm/nvm.sh"
  ```

  An agent that starts a fresh shell for each command needs these in front of `cargo` and `npm`
  commands until the session is restarted. `cargo xtask ci` needs both on `PATH`: it runs npm.
- **Rust from the distribution's packages is not enough.** The gate needs clippy, rustfmt and the
  wasm32 target, which rustup provides. When the script finds cargo without rustup it says so.
- **What it does not install**: the snapshot browser (it is per project: `npm run
  snapshot:install`), signing tools, and anything on Windows.

## What was run

On 2026-11-12 `setup.sh --yes --headless` was run as root in fresh `ubuntu:24.04`,
`fedora:latest` and `archlinux:latest` containers; see [first-run.md](first-run.md#what-was-run)
for the results. The macOS and Windows branches of the script have not been run. The non-root
path with a `sudo` that needs a password was run on an Ubuntu 26.04 machine: the script listed the
package command and installed the rest.
