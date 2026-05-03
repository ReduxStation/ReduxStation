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

#define rustg_log_write(fname, text, format) RUSTG_CALL(RUST_G, "log_write")(fname, text, format)
/proc/rustg_log_close_all() return RUSTG_CALL(RUST_G, "log_close_all")()
