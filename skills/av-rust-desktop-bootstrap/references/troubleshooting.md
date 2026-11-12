# Troubleshooting

`myapp` stands for the project's machine name.

## Setting up

| Symptom | Cause and fix |
|---|---|
| `setup.sh` lists system packages under "To finish, run" instead of installing them | It is not root and `sudo` needs a terminal for its password. Ask the user to run the printed command, then run `setup.sh --check` |
| `setup.sh` installs nothing and exits 1 | It was run without `--yes` and without a terminal to ask on. Pass `--yes` |
| `cargo: command not found` or `npm: command not found` right after `setup.sh` installed them | The current shell has not re-read its profile. Run `source "$HOME/.cargo/env"` and `. "$HOME/.nvm/nvm.sh"`, or start a new login shell |
| `setup.sh` reports `rustup` missing although `cargo` exists | Rust came from the distribution's packages. Those cannot add the wasm32 target or the components the gate needs: install rustup |
| `setup.sh` reports Node.js missing although `node` exists | The version is older than 22.12 or on an odd release line. Let the script install the current LTS with nvm, or install one yourself and pass `--no-node` |
| `cargo install cargo-nextest` fails | Usually no network, no disk space, or no C compiler. The tool is optional: the gate falls back to `cargo test` |
| `No space left on device` during a build | A debug build of the workspace takes several gigabytes in `target/`, and a release build as much again. Free space, or point `CARGO_TARGET_DIR` at a larger disk |

## Scaffolding and the first gate

| Symptom | Cause and fix |
|---|---|
| `new-project.sh: <dir> exists and is not empty` | The script never writes into a directory that has files. Choose a new directory |
| `new-project.sh: --name: …` | The name must be lowercase ASCII letters and digits, start with a letter, and not be one of `doc`, `ops`, `format`, `engine`, `shell`, `testkit`, `ui`, `cli`, `web`, `xtask` |
| A build script fails with `The system library … required by crate … was not found` (`webkit2gtk-4.1`, `javascriptcoregtk-4.1`, `libsoup-3.0`, `gdk-3.0`) | The Linux development packages are missing. Run `setup.sh --check` and install what it lists |
| `pkg-config` is reported as not found by a build script | Install pkg-config (`setup.sh` lists it) |
| A compile error says the `frontendDist` path (`../dist`) does not exist | The frontend has not been built. Run `cargo xtask web` (or `npm run build` in `apps/myapp`), or run the whole gate, which builds it before any cargo step that compiles the app |
| The gate's `web` step fails with `failed to spawn … (is npm installed and on PATH?)` | Node.js is not on `PATH` in this shell: `. "$HOME/.nvm/nvm.sh"` |
| The gate's `web` step fails in `npm ci` | No network, or `package.json` and `package-lock.json` disagree. After changing dependencies run `npm install` in `apps/myapp` and commit the lock file |
| `cargo xtask ci` fails at `fmt` right after scaffolding | The project was renamed and not reformatted (the script was run with `--no-install`). Run `cargo fmt --all` once |
| `cargo xtask ci` fails at `wasm` with `can't find crate for core` | The wasm32 target is not installed: `rustup target add wasm32-unknown-unknown` |
| The gate prints `note: cargo-nextest is not installed, running cargo test` | Not an error. Install it for parallel test runs: `cargo install cargo-nextest --locked` |
| CI fails at "Cargo.lock is up to date" | A manifest changed and the lock file was not committed with it. Run any cargo command locally (it refreshes the file) and commit `Cargo.lock` |
| `cargo xtask layers` reports `<crate>: not in the layering table` | A new crate is not registered. Add it to `TABLE` in `xtask/src/layers.rs` |
| Type errors between `tauri` and a `tauri-plugin-*` crate, or two versions of `tauri` in `Cargo.lock` | A Tauri-family crate was added on another major version. Keep the family together in `[workspace.dependencies]` |

## Running

| Symptom | Cause and fix |
|---|---|
| The window is blank or shows an old UI | `apps/myapp/dist` is missing or stale: the frontend is embedded into the binary when the binary is compiled. Run `cargo xtask web`, then `cargo run -p myapp` again |
| `npm run app` opens a window that cannot load its page | Vite's dev server did not start on port 5173 (the port is fixed; something else holds it). Free the port |
| Running the window where there is no display: CI, a container | Use a virtual display: `Xvfb :99 -screen 0 1280x800x24 &` and then `DISPLAY=:99 cargo run -p myapp` (`setup.sh --headless` installs Xvfb) |
| `libEGL warning: DRI3 error: Could not get DRI3 device` (or `MESA-EGL: warning: …`) under Xvfb | WebKitGTK fell back to software rendering. Harmless |
| A click or a key does nothing, and nothing is logged | Open the webview's developer tools (debug builds: right-click, "Inspect Element") and read the console. A refused IPC call means a capability or a content-security-policy change went wrong |
| `myapp: cannot listen on 127.0.0.1:<port>` at startup | The control port is in use. The port is bound before the window opens so that this is a startup error. Choose another, or `--control 0` for any free port |
| The control connection closes after the first line | The first line must be the `auth` request with the right token. The token is in the `--control-token-file`, or printed on standard error at launch |
| `<file>: expected 64 hexadecimal characters` at startup | The control token file exists but does not hold a token. Delete it and the app creates a fresh one |

## Snapshots

| Symptom | Cause and fix |
|---|---|
| `snapshot: the frontend is not built` | Run `npm run build` in `apps/myapp` first |
| `snapshot: cannot start chromium` | The headless browser is not downloaded: `npm run snapshot:install`. On a minimal Linux it also lacks system libraries: `npx playwright install --with-deps chromium` (needs root) |
| The snapshot differs from the running app | The snapshot is drawn by Playwright's browser, not by the platform webview (WebKitGTK, WKWebView or WebView2). Use it for layout and themes; check platform differences in the app itself. `--browser webkit` is closer to Linux and macOS |
