//! `log` records to standard error. MyApp's own crates log at `info`, everything else (wgpu,
//! winit) at `warn`; `MYAPP_LOG=debug` or `trace` raises MyApp's level.

use log::{Level, LevelFilter, Log, Metadata, Record};

struct StderrLogger {
    own: Level,
}

impl Log for StderrLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= if metadata.target().starts_with("myapp") { self.own } else { Level::Warn }
    }

    fn log(&self, record: &Record) {
        if self.enabled(record.metadata()) {
            eprintln!("{:<5} {}: {}", record.level(), record.target(), record.args());
        }
    }

    fn flush(&self) {}
}

pub fn init() {
    let own = match std::env::var("MYAPP_LOG").as_deref() {
        Ok("trace") => Level::Trace,
        Ok("debug") => Level::Debug,
        Ok("warn") => Level::Warn,
        Ok("error") => Level::Error,
        _ => Level::Info,
    };
    // Fails only if a logger is already set; then that one stays.
    if log::set_boxed_logger(Box::new(StderrLogger { own })).is_ok() {
        log::set_max_level(LevelFilter::Trace);
    }
}
