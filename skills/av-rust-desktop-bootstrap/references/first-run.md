# First run

From a freshly scaffolded project to a passing gate and every frontend seen running. Run these
from the project directory. `myapp` stands for the project's machine name, `MYAPP` for its
environment-variable prefix and `.myapp` for its file extension.

## 1. The gate

```sh
cargo xtask ci
```

It runs eight steps in order and stops at the first failure:

| Step | What it runs | Catches |
|---|---|---|
| `fmt` | `cargo fmt --all -- --check` | Unformatted Rust |
| `web` | `npm ci` when `node_modules` is missing, then `npm run check`, `npm run lint`, `npm run test`, `npm run build` in `apps/myapp` | Type errors, lint findings and failing component tests in the frontend; and it builds `dist/` |
| `clippy` | `cargo clippy --workspace --locked --all-targets -- -D warnings` | Lints, including the no-panic rules |
| `layers` | The layer check | An upward dependency, a webview crate below the app, an unregistered crate |
| `test` | `cargo nextest run --profile ci --workspace --locked --lib --bins --tests` (or `cargo test`) | Behaviour |
| `panic_hunt` | The ignored engine test | A command that panics or hangs on bad params |
| `doctest` | `cargo test --workspace --locked --doc` | Broken examples in doc comments |
| `wasm` | `cargo check --target wasm32-unknown-unknown` for the layered crates | File-system and OS assumptions in the core |

`web` comes before `clippy` because Tauri embeds `apps/myapp/dist` into the desktop binary at
compile time: every cargo step that compiles the app needs it.

The gate ends with:

```text
CI summary: all 8 steps passed (fmt, web, clippy, layers, test, panic_hunt, doctest, wasm)
```

A first run compiles about 450 crates and takes a few minutes; later runs take seconds. On an
untouched scaffold the `test` step runs 34 Rust tests and the `web` step 17 frontend tests.

When a step fails the summary names it and the steps it skipped. On an untouched scaffold a
failure is a machine problem: [troubleshooting.md](troubleshooting.md).

`cargo xtask layers` prints the table the gate checks:

```text
crate                layer          workspace deps
myapp                app/tooling    engine format shell
myapp-cli            app/tooling    engine
myapp-doc            L1
myapp-engine         L5             doc format ops testkit
myapp-format         L3             doc
myapp-ops            L2             doc
myapp-shell          L6             engine
myapp-testkit        testkit
xtask                app/tooling

layering: ok (9 crates)
```

## 2. The CLI

The same engine and the same commands as the window, with no window.

```sh
cargo run -q -p myapp-cli -- run --new Groceries --cmd 'item.add {"text":"milk"}' --out list.myapp
cargo run -q -p myapp-cli -- info list.myapp
cargo run -q -p myapp-cli -- commands --filter undo
```

```text
{"command":"item.add","result":{"id":1}}
{"dirty":false,"items":[{"done":false,"id":1,"text":"milk"}],"path":"list.myapp","redo":null,"revision":0,"title":"Groceries","undo":null}
{"enabled":false,"id":"edit.undo","label":"Undo","menu":["Edit"],"params":"{}","reason":"no document open","shortcut":"Cmd+Z"}
```

Results are JSON lines on standard output; diagnostics go to standard error. Exit status 1 is a
failed command, 2 a usage error.

## 3. The window

```sh
cargo run -p myapp                  # starts with a new, empty document
cargo run -p myapp -- list.myapp    # opens a file
```

The window shows a menu bar (File, Edit, Item, View), the document's title, a "New item" field
with an Add button, the items with a checkbox and a Delete button each, and a status bar. Check
that typing an item and pressing Enter adds it, that Ctrl+Z (Cmd+Z on macOS) removes it again, and
that View › Light Theme changes the colours.

This uses the frontend that the gate (or `cargo xtask web`) built into `apps/myapp/dist`. While
working on the frontend, run the window on Vite's dev server instead, with hot reload:

```sh
cd apps/myapp
npm run app
```

Where there is no display (a container, a remote machine), start a virtual one first:

```sh
Xvfb :99 -screen 0 1280x800x24 &
DISPLAY=:99 cargo run -p myapp
```

## 4. The UI without the app

`npm run snapshot` draws the real frontend in a headless browser and saves a PNG. The view it
draws comes from the real shell, after the control-protocol calls in `--script`.

```sh
cd apps/myapp
npm run snapshot:install     # once per machine: downloads the headless browser
npm run snapshot -- --out ui.png --size 720x420 \
  --script '[["engine.execute", {"command": "item.add", "params": {"text": "milk"}}], ["ui.set", {"theme": "light"}]]'
```

```text
engine.execute: {"ok":true,"result":{"id":1}}
ui.set: {"ok":true,"result":null}
wrote /home/you/myapp/apps/myapp/ui.png (1440×840)
```

**Open the PNG and look at it.** This is how a UI change is checked, and how an agent produces
before-and-after images, without opening a window. `--click File` opens a menu before the picture
is taken; `--browser webkit` uses Playwright's WebKit instead of Chromium.

The browser is Playwright's, not the platform webview the app runs in. Trust the snapshot for
layout and themes; check platform behaviour in the running app.

The same view as JSON, with no browser at all:

```sh
cargo run -q -p myapp-shell --example view -- --script '[["ui.set", {"theme": "light"}]]'
```

## 5. The running app, driven from outside

```sh
cargo run -p myapp -- --control 7878 --control-token-file control.token &
TOKEN=$(tr -d '\r\n' < control.token)
printf '%s\n' "{\"id\":\"auth\",\"method\":\"auth\",\"params\":{\"token\":\"$TOKEN\"}}" \
  '{"id":1,"method":"engine.execute","params":{"command":"item.add","params":{"text":"milk"}}}' \
  '{"id":2,"method":"ui.inspect","params":{}}' | nc -q 2 127.0.0.1 7878
```

```text
{"id":"auth","ok":true,"result":{"authenticated":true}}
{"id":1,"ok":true,"result":{"id":1}}
{"id":2,"ok":true,"result":{"document":{"dirty":true,"items":[{"done":false,"id":1,"text":"milk"}],…},"menus":[…],"shellCommands":[…],"ui":{"hideDone":false,"status":"","theme":"dark"}}}
```

(The third reply is shortened here: `menus` holds the whole menu bar.) The item appears in the
window at once: the app sends the webview the new view after every request, whoever made it.

The first line on a connection must authenticate. The token file is created on first use,
readable by its owner only. The server binds the loopback interface only.

`nc -q 2` is the OpenBSD netcat found on most Linux distributions: it waits two seconds for
replies after its input ends. Any client that writes and reads lines over TCP works.

## 6. An installer

```sh
cd apps/myapp
npm run bundle -- --bundles deb     # on Linux; without --bundles, every format for the platform
```

The bundles land under `target/release/bundle/`. For the template the `.deb` is about 2.9 MiB.
Packaging is the `av-rust-desktop-ship` skill's subject.

## What was run

On 2026-11-12, with Rust 1.99.1, React 19.3.1 and TypeScript 7.0.2:

| Where | What |
|---|---|
| Fresh `ubuntu:24.04` container, as root | `setup.sh --check` (exit 1, listing everything), `setup.sh --yes --headless` (system packages, rustup, Node.js 26 through nvm, cargo-nextest), `setup.sh --check` (exit 0). `new-project.sh … --name fieldnotes --title "Field Notes" --verify`: 99 files, gate passed all eight steps with nextest. Sections 2 to 6 above: the CLI, the window under Xvfb opening a file given on the command line and driven over the control socket (a screenshot was taken and looked at), a snapshot PNG, a `.deb` |
| Fresh `fedora:latest` and `archlinux:latest` containers, as root | The same setup (without cargo-nextest), scaffold and gate (all eight steps, with `cargo test`), the CLI, and the window under Xvfb driven over the control socket |
| A development container (Ubuntu 24.04, Node.js 22) | The window driven with real mouse and keyboard input through xdotool: typing an item and pressing Enter, clicking a checkbox, Ctrl+Z, View › Light Theme. `npm run app` (the window on the Vite dev server). Screenshots of both themes and of an open menu were looked at |
| An Ubuntu 26.04 machine without root (Node.js 24) | `setup.sh --check` and `--yes`, run on 2026-11-11: the script listed the system-package command it could not run and installed the rest. The frontend's type check, lint, tests and build |

Not run: anything on macOS or Windows; a native file dialog; bundle formats other than `.deb`;
signing; the generated GitHub Actions workflow.
