// rust_g.dm - DM API for rust_g extension library
#define RUST_G "rust_g"

// Handle 515+ call() -> call_ext() deprecation
#if DM_VERSION >= 515
#define RUSTG_CALL call_ext
#else
#define RUSTG_CALL call
#endif

// dmi and git features not compiled into Docker build — stubs return null/empty (cosmetic only)
#define rustg_dmi_strip_metadata(fname) null
#define rustg_git_revparse(rev) ""
#define rustg_git_commit_date(rev) ""

// rust_g 0.4.2 (the version pinned in dependencies.sh and shipped by the
// build pipeline) ships a 2-arg log_write. Newer rust_g releases added a
// `format` arg for JSON-formatted output, but we compile and ship the 0.4.2
// binary, so callers must pass 2 args. WRITE_LOG in code/__HELPERS/_logging.dm
// matches. Calling with 3 args triggers a runtime "undefined symbol: log_write"
// from BYOND because the ABI mismatch confuses call_ext.
#define rustg_log_write(fname, text) RUSTG_CALL(RUST_G, "log_write")(fname, text)
/proc/rustg_log_close_all() return RUSTG_CALL(RUST_G, "log_close_all")()
