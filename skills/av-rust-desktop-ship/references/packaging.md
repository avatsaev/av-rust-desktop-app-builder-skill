# Packaging and documentation site

**Status of this page.** The template packages with the Tauri bundler. Only the `.deb` bundle was
built (on Linux, 2026-11-12, 2.9 MiB; the release binary is about 8.8 MB). Every other bundle
format, signing, notarization and the updater are marked *(reasoned)*: they follow from Tauri's
documented capabilities and were not built or run by this skill-set's authors. Check Tauri's current
documentation before coding against any of them. The hand-written packaging described at the end is
what a large production app on this architecture ships; the template does not exercise it.

In every path below `myapp` stands for the project's machine name.

## Build the bundles

In `apps/myapp`:

```sh
npm run bundle                      # = tauri build: every target for the host platform
npm run bundle -- --bundles deb     # one format; the same pattern for the others
```

`npm run bundle` runs `npm run build` first (`beforeBuildCommand` in `tauri.conf.json`), then builds
the release binary with the workspace's `release` profile and packages it. The Tauri CLI is the npm
package `@tauri-apps/cli`; there is no `cargo install tauri-cli`. A plain binary without installers
comes from:

```sh
cargo build --release -p myapp -p myapp-cli
```

(the frontend's `dist/` must exist first: run `npm run build` in `apps/myapp`).

## Configuration: `apps/myapp/src-tauri/tauri.conf.json`

```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "MyApp",
  "identifier": "com.example.myapp",
  "build": {
    "frontendDist": "../dist",
    "beforeBuildCommand": "npm run build"
  },
  "app": {
    "windows": [
      {
        "label": "main",
        "title": "MyApp",
        "width": 960,
        "height": 640,
        "minWidth": 480,
        "minHeight": 320,
        "center": true
      }
    ],
    "security": {
      "csp": "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; connect-src ipc: http://ipc.localhost"
    }
  },
  "bundle": {
    "active": true,
    "targets": "all",
    "icon": ["icons/32x32.png", "icons/128x128.png", "icons/128x128@2x.png", "icons/icon.icns", "icons/icon.ico"]
  }
}
```

- **Identifier and name.** `identifier` is the application id (reverse DNS, under a domain you
  control) and `productName` is the name users read. Both are set when the project is scaffolded.
- **Version.** `tauri.conf.json` sets none: the version comes from `[workspace.package] version`.
- **Targets.** `"targets": "all"` builds every bundle format the host can build.
- **Icons.** The template ships a placeholder icon, listed in `ATTRIBUTION.md`. Replace it before
  release: `npm run tauri icon <your-1024px.png>` in `apps/myapp` regenerates every size.

## Per platform *(reasoned, except the `.deb`)*

| Platform | Bundle targets | Tooling | Notes |
|---|---|---|---|
| Linux | `deb` (built by the template), `rpm`, `AppImage` | The Tauri bundler; build with the Linux system packages installed (`libwebkit2gtk-4.1-dev librsvg2-dev libxdo-dev` on Debian/Ubuntu) | The webview is WebKitGTK 4.1 from the system. An AppImage runs on any distribution whose glibc is at least the build host's, so build on the oldest one you support |
| macOS | `app`, `dmg` | The Tauri bundler on macOS; signing and notarization through Tauri's configuration and environment variables | Ad-hoc signing is for local testing only: Gatekeeper rejects it on other Macs. The webview is WKWebView |
| Windows | `msi`, `nsis` | The Tauri bundler on Windows | The webview is WebView2: decide how the runtime is provided (check the current documentation for the options) |

Signing, notarization and an auto-updater (`tauri-plugin-updater`) are Tauri-configured features:
read the current documentation for each before enabling it. Signing material exists only as CI
secrets.

## Size notes for a webview app

- The frontend is a Vite build: watch the size of `apps/myapp/dist` as dependencies are added; a
  bundle-size budget is a growth pattern in the `av-rust-desktop-grow` skill.
- Never reach for `panic = "abort"` to shrink the binary: the crash guard needs unwinding.
- The runtime webview is not in the bundle on Linux (a system package) or, normally, on macOS and
  Windows *(reasoned)*.

## Conventions worth copying

- **One version.** It lives in `[workspace.package] version`. Scripts read it from there and an xtask
  command sets it. Never keep a second copy of the version.
- **Build provenance.** The commit and the build date are passed as environment variables and read at
  compile time, for `--version` and the About window.
- **One environment file.** If packaging scripts appear, a shared `env.sh` gives every one of them
  the root, the version, the output directory and the provenance variables.
- **Releases come from a branch.** A push to the `release` branch runs the release workflow, which
  builds and signs. Signing material exists only as CI secrets.
- **Stop and ask** before anything hard to undo: publishing, releases, secrets, spending money,
  destructive git.

Suggested homes in your project for what grows: `docs/releasing.md` and
`.github/workflows/release.yml`.

## The alternative when the bundler does not fit

A large production app on this architecture, whose shell is a native Rust UI toolkit rather than a
webview, ships hand-written per-platform packaging scripts under `packaging/`. That is the
production evidence for the conventions above. This is what they produce and with what:

| Platform | Artifacts | Tooling | Notes |
|---|---|---|---|
| Linux | AppImage, `.deb`, `.rpm`, `.tar.gz`, Flatpak | `nfpm` for deb and rpm, AppImage tooling at verified pins, a `.desktop` file | An AppImage runs on any distribution whose glibc is at least the build host's, so build on the oldest one you support |
| macOS | `.dmg` with an `.app` (universal, or per architecture); CLI | `codesign`, `notarytool`, an `Info.plist` template | Ad-hoc signing is for local testing only: Gatekeeper rejects it on other Macs |
| Windows | `.msi`, portable zip, symbols zip | WiX v5, `signtool`, `winresource` in `build.rs` for the icon and version info | The C runtime is linked statically (`+crt-static`), so no redistributable is needed |
| FreeBSD | A package | A script | |

## Documentation site

A large production app builds an mdBook from `book/` with its own workflow. For a new project, plain
Markdown under `docs/` is enough until someone asks for a site.
