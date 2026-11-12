# How kinds of app fit

Identify the kind of app first; it decides the model, the persistence and the first growth
pattern to reach for. `myapp` below stands for the project's machine name.

## Scope of the evidence

The *document editor* row is what a shipping app on this architecture does. The other rows are
reasoned from the same seams. They have not been exercised by a shipping app or by the template.
Rows and statements marked *(reasoned)* carry that label: treat them as a well-founded plan, not
as proven practice, and check them with a prototype and tests early.

The production evidence comes from a large app whose shell is a native Rust UI toolkit, not a
webview. It covers the engine side of the architecture: commands, snapshots, layering, the
never-crash rules, the control protocol, and the engine parts of the growth patterns. The webview
shell (Tauri and React) is the template's own: the template builds and runs it, but anything the
template does not contain that is specific to the webview is *(reasoned)*.

Growth patterns named in the last column are written up in the `av-rust-desktop-grow` skill. They
are not part of the template and are not built or tested by this skill-set; their engine parts are
proven in a large production app on this stack, their shell parts are *(reasoned)*.

## The table

| Kind of app | The model (L1) | Persistence | Undo | Add first |
|---|---|---|---|---|
| **Document editor**: text, drawings, diagrams, images, audio, CAD | The document | A file format crate (L3) | Yes, snapshot history | Chunked data (growing the native format), a canvas view for heavy custom drawing, dialogs: patterns in the `av-rust-desktop-grow` skill |
| **Library or record manager**: notes, media, inventory, contacts *(reasoned)* | Records and the current query or selection | A store behind a trait in L3, opened by the app | Per edit, or none | Background jobs for indexing and import (background jobs with progress and cancel: `av-rust-desktop-grow` skill) |
| **Utility or tool**: converter, installer, batch processor, settings tool *(reasoned)* | The job description and its results | Preferences only | Rarely | Background jobs with progress and cancel (`av-rust-desktop-grow` skill) |
| **Viewer or monitor**: logs, metrics, devices, files *(reasoned)* | A bounded window of incoming data, plus filters | Often none | No | A feed thread and an ingest command |
| **Client for a service**: chat, API tool, version-control UI *(reasoned)* | Cached remote state and pending operations | A local cache | Limited | An L4 client crate; results applied as commands |
| **Real-time tool**: audio, video, simulation, control *(reasoned)* | The project, plus transport state | A project file | Yes, for the project | A real-time thread fed with snapshots |

## What comes free in every row

The CLI and the control channel come for free in every row, because they talk to the registry and
not to your domain.

## Using the table

- Pick the nearest row, then read [early-decisions.md](early-decisions.md) for the questions that
  row raises (file or no file, undo or not, where the state lives, slow work, live data).
- The "Add first" cell is the first growth pattern to load from the `av-rust-desktop-grow`
  skill, after the sample domain is replaced.
