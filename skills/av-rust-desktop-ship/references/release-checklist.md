# Before the first release

## What is not verified

The template was built and exercised on Linux only, in a container, on 2026-11-12: its gate passed,
its desktop app ran under Xvfb on WebKitGTK and was driven over the control socket and with real
mouse and keyboard input, and `npm run bundle -- --bundles deb` produced a `.deb`. Everything else is
untested. Before release, the project owner must test each of these, because nobody has done it for
you:

- **macOS and Windows** (WKWebView and WebView2). The template was built and run on Linux with
  WebKitGTK only. Build, run and test on each platform you ship.
- **Native file dialogs.** They were not exercised.
- **Every bundle format other than `.deb`**, and **signing, notarization and the updater**.
- **The GitHub Actions workflow.** The template's `ci.yml` was written from a large production app's
  workflows and never run. Run it and get it green.
- **Real GPU hardware.** Anything you add that draws on the GPU was not tested.

The guidance in [packaging](packaging.md) beyond the `.deb` is *(reasoned)*: it follows from Tauri's
documented capabilities, not from a build. The growth patterns named below are proven in a large
production app on this architecture for their engine parts; their webview-shell parts are *(reasoned)*.
They are not part of the template and were not built or tested by this skill-set. Load the
`av-rust-desktop-grow` skill for each one.

## The twelve items

- [ ] **Unsaved changes.** The template replaces or closes a document without asking. Add the prompt,
  and its answer as data for automation.
- [ ] **Autosave and crash recovery.** Growth pattern "Autosave and crash recovery" in the
  `av-rust-desktop-grow` skill.
- [ ] **Preferences** that load leniently. Growth pattern "Preferences and persistent UI state" in
  the `av-rust-desktop-grow` skill (window geometry is a Tauri plug-in concern there).
- [ ] **A log file** in the settings directory. The template logs to standard error only.
- [ ] **Slow work off the UI thread.** Growth pattern "Background jobs with progress and cancel" in
  the `av-rust-desktop-grow` skill.
- [ ] **Application icon, file association, platform metadata.** Growth pattern "Desktop
  integration" in the `av-rust-desktop-grow` skill.
- [ ] **Tested on every platform you ship**, on a real machine of each.
- [ ] **Packaging and a signed build** per platform (see [packaging](packaging.md)).
- [ ] **`SECURITY.md`**, and the control channel off unless asked for; hardened if agents will use
  it. Growth pattern "Hardening the control channel" in the `av-rust-desktop-grow` skill.
- [ ] **Format version policy** written down: what an older build does with a newer file.
- [ ] **Every bundled asset** has a row in `ATTRIBUTION.md`, and every dependency's licence, crate
  and npm package alike, is on the allowlist (see [repository files](repository-files.md)).
- [ ] **Accessibility**: interactive widgets have labels (the same labels the component tests find
  them by).

## Added by the webview shell

- [ ] **Tested on all three webview engines** (WebKitGTK, WKWebView, WebView2): CSS and JavaScript
  features differ between them.
- [ ] **Capabilities and CSP reviewed.** `capabilities/default.json` grants the main window only
  `core:default`, the CSP in `tauri.conf.json` is strict, and the main window loads no remote
  content. Check that nothing you added widened them without need.
- [ ] **The placeholder icon replaced** (`npm run tauri icon <1024px.png>`), and its row in
  `ATTRIBUTION.md` updated.
- [ ] **Minimum OS versions decided and written down**: WebView2 on Windows, the macOS version,
  WebKitGTK 4.1 on Linux.
- [ ] **`devtools` off in release builds.**

Never publish, create a release, touch signing secrets, spend money or run destructive git without
asking the user first.
