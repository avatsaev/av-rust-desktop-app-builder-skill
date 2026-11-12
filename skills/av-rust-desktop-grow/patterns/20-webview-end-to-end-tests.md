# End-to-end tests against the real webview

**Add it when:** Some flows cannot be covered by component tests with a fake backend or by the control socket, and need a real window and webview engine.

> `myapp` in paths stands for the project's machine name. Evidence: this whole pattern is *(reasoned)* from the architecture and Tauri's documented capabilities. No production app on this architecture is known to do it, it is not in the template, and it was not built by this skill-set: implement it with tests under the project's gate, and check the current documentation of every Tauri API or plug-in named here before coding against it.

## Design

The template's tests are of three kinds: shell tests in Rust (`crates/shell/src/tests.rs`, no window), component tests in TypeScript (a fake backend, jsdom), and driving the running app over the control socket. Add real-webview tests only for the few flows those cannot cover. This pattern is *(reasoned)*; nothing here was built.

- Use WebDriver through `tauri-driver`. It supports Linux and Windows only; it does not cover macOS (WKWebView). Check its current documentation for setup and the driver each platform needs.
- Keep the suite small: flows that depend on the real engine (focus, a real click and key sequence, a webview-specific rendering quirk), not logic.
- Everything else stays where it is cheaper: the engine in `Session` tests, the view in shell tests, a component in a component test.
- On a machine with no display (CI), run under a virtual display such as Xvfb on Linux (the template's `scripts/setup.sh --headless` prepares one).
- Drive the app with a control token file and a fixed loopback port when a test also needs to read state: `ui.inspect` is the oracle for what the screen should show.
- Run it as a separate CI job; it is slow, so run it only when frontend or app-binary files changed, and never inside the quick inner loop.

## Where it goes

Suggested homes: `apps/myapp/e2e/` for the suite and its npm script (outside the Rust workspace, so the layer check does not see it), and a separate job in `.github/workflows/`. Keep it out of `cargo xtask ci` unless you decide the cost is worth it; the gate stays the single definition of green for everything else.

## How it fits the seams

- The tests go through the same two commands and one event the user does; the control socket (seam 5) lets a test read `ui.inspect` to check what is on screen.
- The test never reaches around the architecture: the document is changed only through command ids, so a flow is repeatable by a script.
- Failures reproduce at a lower layer where possible: write the failing shell or component test first, as for any bug.

## Done when

- [ ] Each end-to-end test covers a flow no cheaper test can, and says which.
- [ ] They run on Linux and Windows in CI; macOS is covered by manual testing and said so.
- [ ] Any bug an end-to-end test finds gets a lower-layer test that failed before the fix.
- [ ] The existing gate still passes.

- [ ] `cargo xtask ci` passes (all eight steps, including `web`).
