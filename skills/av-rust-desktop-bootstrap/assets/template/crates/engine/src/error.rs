#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum EngineError {
    #[error("unknown command `{0}`")]
    UnknownCommand(String),
    /// The command exists but cannot run now (what greys its menu item out).
    #[error("`{id}` is unavailable: {reason}")]
    Disabled { id: String, reason: String },
    #[error("bad params: {0}")]
    BadParams(String),
    #[error("{0}")]
    Other(String),
}

pub type Result<T> = std::result::Result<T, EngineError>;

impl From<myapp_doc::Invalid> for EngineError {
    fn from(e: myapp_doc::Invalid) -> Self {
        EngineError::BadParams(e.to_string())
    }
}

impl From<myapp_format::FormatError> for EngineError {
    fn from(e: myapp_format::FormatError) -> Self {
        EngineError::Other(e.to_string())
    }
}
