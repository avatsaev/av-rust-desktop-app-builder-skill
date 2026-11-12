//! MyApp desktop app: a Tauri window whose webview draws the shell's view.
//!
//! Usage: `myapp [options] [file]`; `myapp --help` lists the options.
//!
//! `--control <port>` (or `MYAPP_CONTROL_PORT`) starts a loopback JSON-lines control server:
//! the first line authenticates, then each request line gets one reply line. The methods are
//! in `myapp_shell::control`.

// Release builds on Windows are GUI-subsystem apps: no console window from the Start menu.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]
#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]

mod bridge;
mod commands;
mod control_server;
mod crash_guard;
mod logging;
mod services;

use std::path::PathBuf;
use std::sync::mpsc::channel;

use clap::Parser;

#[derive(Parser)]
#[command(name = "myapp", version, about = "MyApp")]
struct Args {
    /// Document to open.
    file: Option<PathBuf>,
    /// Serve the JSON control protocol on 127.0.0.1:<PORT> (0 = any free port).
    #[arg(long, env = "MYAPP_CONTROL_PORT", value_name = "PORT")]
    control: Option<u16>,
    /// File holding the control token (64 hex characters); created with a fresh token when missing.
    #[arg(long, env = "MYAPP_CONTROL_TOKEN_FILE", value_name = "FILE")]
    control_token_file: Option<PathBuf>,
}

fn main() {
    let args = Args::parse();
    logging::init();
    crash_guard::install_hook();
    // Bind before the window opens: a port in use is a startup error, not a silent no-op.
    let control = match args.control.map(|port| control_server::bind(port, args.control_token_file.as_deref())) {
        Some(Ok(bound)) => Some(bound),
        Some(Err(e)) => {
            eprintln!("myapp: {e}");
            std::process::exit(2);
        }
        None => None,
    };
    // Every request, from the webview and from the control socket, crosses this channel to the
    // one thread that owns the session.
    let (requests, inbox) = channel();
    if let Some((listener, token)) = control {
        control_server::start(listener, token, requests.clone());
    }
    let file = args.file;
    let result = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(bridge::Bridge::new(requests))
        .invoke_handler(tauri::generate_handler![commands::control, commands::invoke_command])
        .setup(move |app| {
            bridge::spawn_owner(app.handle().clone(), inbox, file);
            Ok(())
        })
        .run(tauri::generate_context!());
    if let Err(e) = result {
        eprintln!("myapp: {e}");
        std::process::exit(1);
    }
}
