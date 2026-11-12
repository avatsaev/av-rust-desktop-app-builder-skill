# Day 0: a project that builds

Tick every item before the first feature. `myapp` stands for the project's machine name.

- [ ] Machine name, product name and application id chosen ([scaffold.md](scaffold.md)); the id
      is under a domain the user controls
- [ ] Prerequisites installed: `bash scripts/setup.sh --check` exits 0
      ([prerequisites.md](prerequisites.md))
- [ ] Project scaffolded with those names; the script reported 99 files
- [ ] `cargo fmt --all` run once after scaffolding (the script does it)
- [ ] `Cargo.lock` generated and `npm ci` run (the script does both); both lock files committed
- [ ] `cargo xtask ci` passes all eight steps
- [ ] The window opens, the CLI runs, `npm run snapshot` writes a PNG and someone looked at it
      ([first-run.md](first-run.md))
- [ ] `README.md`, `AGENTS.md`, `ATTRIBUTION.md`, `SECURITY.md` and the licence files read through:
      the script generates them, and the copyright holder, the licence choice and the reporting
      route in `SECURITY.md` are the user's to confirm
- [ ] The placeholder icon noted for replacement before release
      (`npm run tauri icon <your-1024px.png>` in `apps/myapp`)
- [ ] First commit made
- [ ] CI runs the gate on pull requests, and `main` is protected. The generated workflow has not
      been run before: watch its first run
- [ ] If the app will ship on macOS or Windows: the project built and run there once. The template
      has only been run on Linux

The script makes the licence `MIT OR Apache-2.0`. For another licence, change `license` in
`[workspace.package]` in the root manifest and replace `LICENSE-MIT`, `LICENSE-APACHE` and
`NOTICE`.

Next: replace the sample domain with the user's (the `av-rust-desktop-design` skill), then add
features (the `av-rust-desktop-develop` skill).
