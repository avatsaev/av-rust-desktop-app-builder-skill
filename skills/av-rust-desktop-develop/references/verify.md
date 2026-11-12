# Verify by running the pieces

Run each part of the project as a verification tool: the window, the CLI, the view as JSON, the
frontend snapshot, and the control socket. `myapp` stands for the project's machine name, `MYAPP`
for its environment-variable prefix, and `.myapp` for its file extension. Commands for the frontend
run in `apps/myapp` (the npm project; its Tauri crate is `apps/myapp/src-tauri`).

The template does the following plainly: the window ran under Xvfb on WebKitGTK, was driven over the
control socket and with real mouse and keyboard input; `npm run app` started the window on the Vite
dev server; `npm run snapshot` wrote PNGs of both themes. macOS (WKWebView) and Windows (WebView2)
were not exercised.

## The window

```sh
cargo xtask web                     # once, and after frontend changes: builds apps/myapp/dist
cargo run -p myapp                  # starts with a new, empty document
cargo run -p myapp -- list.myapp    # opens a file
```

`cargo run -p myapp` shows the embedded `dist/`, so it needs `dist/` to exist and to be current (see
[commands.md](commands.md)). For frontend work use hot reload:

```sh
cd apps/myapp
npm run app                         # the window on Vite's dev server (port 5173); edits reload at once
```

`npm run app` adds `src-tauri/tauri.dev.conf.json` (`devUrl` `http://localhost:5173`, `beforeDevCommand`
`npm run dev`); `tauri.conf.json` has no `devUrl`, so plain `cargo run` uses the embedded `dist/`.

Webview devtools: in a debug build, right-click in the window and choose "Inspect Element".
Release builds have them off.

## The CLI

Results are JSON lines on standard output; diagnostics go to standard error. Exit status 1 is a
failed command, 2 a usage error. `run` parses every `--cmd` before running any, so a typo fails
before anything changes; a failing command exits 1 and saves nothing.

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

- `run [FILE | --new TITLE] --cmd '<id> <json params>'... --out FILE` runs commands in order on a
  new or existing file.
- `info FILE` prints the document state.
- `commands [--filter TEXT]` lists the registry with what is enabled and why not.

More examples: `myapp-cli commands --filter item`, and
`myapp-cli run list.myapp --cmd 'item.setDone {"id":1}' --cmd document.inspect --out list.myapp`.

## The view as JSON, without any browser

The shell produces the view as data. Print what the frontend would draw after a script of
control-protocol calls:

```sh
cargo run -q -p myapp-shell --example view -- \
  --script '[["engine.execute", {"command": "item.add", "params": {"text": "milk"}}], ["ui.set", {"theme": "light"}]]'
```

`--script` is a JSON array of `[method, params]` calls, applied in order to a new document. Each
reply goes to standard error, the view (`{ui, document, menus, shellCommands}`) to standard output.
Use it to check what an agent will read: menu enabled states and reasons, shortcuts, `ui.status`.

## The frontend as a picture: `npm run snapshot`

`npm run snapshot` draws the **real frontend** (the built `dist/`) in a headless browser, fed with
the view from the real shell (the `view` example above), and saves a PNG. No window is opened.

```sh
cd apps/myapp
npm run snapshot:install        # once: downloads the headless browser
npm run build
npm run snapshot -- --out ui.png --size 720x420 \
  --script '[["engine.execute", {"command": "item.add", "params": {"text": "milk"}}], ["ui.set", {"theme": "light"}]]'
```

```text
engine.execute: {"ok":true,"result":{"id":1}}
ui.set: {"ok":true,"result":null}
wrote /home/you/myapp/apps/myapp/ui.png (1440×840)
```

(The `--size` is in CSS pixels; with the default `--scale 2` the file is twice that.)

| Option | Meaning |
|---|---|
| `--out FILE` | PNG to write (default `snapshot.png`) |
| `--size WxH` | Size in CSS pixels (default `960x640`) |
| `--scale N` | Device pixels per CSS pixel (default `2`) |
| `--script JSON` | Control-protocol calls applied in order to a new document (default `[]`) |
| `--view FILE` | Draw this saved view instead of asking the shell |
| `--click NAME` | Click the button with this accessible name first, e.g. a menu: `--click File` |
| `--browser NAME` | `chromium` (default) or `webkit` |

Rules:

- It needs the built frontend: the script stops with "the frontend is not built: run `npm run build`
  first" otherwise. Rebuild after every frontend change.
- **Always open the PNG and look at it, in both themes** (`["ui.set", {"theme": "dark"}]` and
  `{"theme": "light"}`). Check layout, clipping, contrast, empty states and the status bar. Use
  `--click View` to put an open menu in the picture, and `--script` to put the app in the state under
  test.
- **The browser is Playwright's, not the platform webview the app runs in.** Trust the picture for
  layout and themes; check platform behaviour (fonts, form controls, scrolling) in the running app.
  `--browser webkit` is closer to WKWebView and WebKitGTK but is still not the platform webview.
- `npm run snapshot:install` runs `playwright install chromium` once. On Linux, the browser needs
  system libraries; install them with `npx playwright install --with-deps chromium`.
- The snapshot starts `cargo run -p myapp-shell --example view`, so it compiles the shell crate (not
  the Tauri app) and needs a Rust toolchain.

## The running app, driven from outside

```sh
cargo run -p myapp -- --control 7878 --control-token-file control.token &
TOKEN=$(tr -d '\r\n' < control.token)
printf '%s\n' "{\"id\":\"auth\",\"method\":\"auth\",\"params\":{\"token\":\"$TOKEN\"}}" \
  '{"id":1,"method":"engine.execute","params":{"command":"item.add","params":{"text":"milk"}}}' \
  '{"id":2,"method":"ui.inspect","params":{}}' | nc -q 2 127.0.0.1 7878
```

The first two replies:

```text
{"id":"auth","ok":true,"result":{"authenticated":true}}
{"id":1,"ok":true,"result":{"id":1}}
```

The third reply is the view: `{"id":2,"ok":true,"result":{...}}` where `result` has four keys,
`ui`, `document`, `menus` and `shellCommands`. `ui` is `{"hideDone":false,"status":"","theme":"dark"}`
in a fresh app, `document` is what `document.inspect` returns (here the document with one `milk`
item, `dirty` true, `undo` `"Add Item"`), `menus` is the menu bar generated from the registry (each
item has `id`, `label`, `shortcut`, `enabled`, `reason` and `checked`), and `shellCommands` lists the
view toggles with their `checked` state.

- `--control <port>` (or `MYAPP_CONTROL_PORT`) starts a loopback JSON-lines control server; port 0
  means any free port. `--control-token-file <file>` (or `MYAPP_CONTROL_TOKEN_FILE`) names the file
  holding the 64-hex-character token; it is created with a fresh token when missing.
- The first line on a connection must authenticate. The token file is created on first use,
  readable by its owner only. The server binds the loopback interface only.
- Each request line gets one reply line. The methods are `engine.execute`, `engine.commands`,
  `ui.inspect` and `ui.set`; see [../recipes/add-control-method.md](../recipes/add-control-method.md).
- `nc -q 2` is the OpenBSD netcat found on most Linux distributions: it waits two seconds for
  replies after its input ends. Any client that writes and reads lines over TCP works.
- A command run over the socket changes the real window: the owner thread emits a `view` event when
  the view changed, so you can watch it, or take the next `ui.inspect`.

## Without a display, and with real input

Running the window needs a display. In CI or a container use a virtual one:

```sh
Xvfb :99 -screen 0 1280x800x24 &
DISPLAY=:99 cargo run -p myapp
```

The snapshot tool, the view example, the CLI and every test need no display. To exercise the real
window (typing, clicks, shortcuts, a menu) on that virtual display, drive it with real input, for
example with `xdotool` (install it if it is missing), and read the effect
back with `ui.inspect` over the control socket. This is optional; the template's own checks did this
once under Xvfb on WebKitGTK.

## Logging

Logs go to standard error. The project's own crates log at `info`, everything else at `warn`. Raise
the project's level with `MYAPP_LOG=debug` or `MYAPP_LOG=trace` (`warn` and `error` also work):

```sh
MYAPP_LOG=debug cargo run -p myapp
```

## Troubleshooting: the window and the frontend

| Symptom | Cause and fix |
|---|---|
| The window opens blank, or shows an old UI | `apps/myapp/dist` is missing or stale. Run `cargo xtask web` (or `npm run build`) and run again |
| A cargo command fails with a `frontendDist` error | Same: `dist/` does not exist yet. Run `cargo xtask web` |
| A white window under `npm run app` | Vite is not serving on port 5173 (the port is strict: another process may hold it). Free the port and run again |
| `libEGL warning: DRI3 ...` on the console under Xvfb | Harmless: WebKitGTK found no GPU path. Nothing to fix |
| Running the window where there is no display: CI, a container | Use a virtual display: `Xvfb :99 -screen 0 1280x800x24 &` and then `DISPLAY=:99 cargo run -p myapp` |
| `cargo xtask web` or `cargo xtask ci` fails with `npm` not found | Node is not on `PATH` for that shell. Load it (for example `nvm use`), then run again |
| `npm run snapshot` says it cannot start the browser | Run `npm run snapshot:install` once (on Linux, `npx playwright install --with-deps chromium`) |
| `npm run snapshot` says the frontend is not built | Run `npm run build` first |
| Cargo reports two versions of a Tauri crate, or mismatched types | Keep `tauri`, `tauri-build` and every `tauri-plugin-*` on the same major version, and `@tauri-apps/api` on the same minor as `tauri`; upgrade them together, then run the gate and look at a snapshot |
