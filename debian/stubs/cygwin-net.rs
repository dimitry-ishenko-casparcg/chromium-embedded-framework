//! Cygwin-specific networking functionality (stub for Debian builds).
//! Cygwin is a POSIX compatibility layer for Windows.
//! This file is NOT used in Debian builds (Linux-only), but must exist
//! for Rust compiler module resolution during std library compilation.

// Re-export Unix networking (Cygwin is POSIX-compatible)
pub use crate::os::unix::net::*;
