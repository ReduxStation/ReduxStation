// rust_g.dm - DM API for rust_g extension library
#define RUST_G "rust_g"

// Handle 515+ call() -> call_ext() deprecation
#if DM_VERSION >= 515
#define RUSTG_CALL call_ext
#else
#define RUSTG_CALL call
#endif

// rustg_dmi_strip_metadata is REQUIRED for spritesheet rendering.
// /datum/asset/spritesheet/ensure_stripped() saves multi-state DMI-PNGs to disk,
// then calls this to flatten the file in place. Without it BYOND reads the file
// back as a multi-state icon and only emits the first frame when serialising
// for the client, producing the user-visible "every sprite is the first sprite"
// bug across the RPD, vending, fridges, chem dispenser, achievements, etc.
#define rustg_dmi_strip_metadata(fname) RUSTG_CALL(RUST_G, "dmi_strip_metadata")(fname)

// git stubs kept in place — git2 needs libgit2 which is a 32-bit Docker
// dependency we haven't wired up yet. getrev.dm gracefully handles "" returns,
// so the changelog/revision UI just lacks commit info, not a real bug. Enable
// in a follow-up once libgit2-dev:i386 is added to the rust_g_builder stage.
#define rustg_git_revparse(rev) ""
#define rustg_git_commit_date(rev) ""

#define rustg_log_write(fname, text, format) RUSTG_CALL(RUST_G, "log_write")(fname, text, format)
/proc/rustg_log_close_all() return RUSTG_CALL(RUST_G, "log_close_all")()

// http feature, built into librust_g.so alongside dmi and log. Used by /datum/http_request
// (code/datums/http.dm) and the TTS subsystem. Backed by ureq + rustls, no system openssl needed.
#define RUSTG_HTTP_METHOD_GET "get"
#define RUSTG_HTTP_METHOD_PUT "put"
#define RUSTG_HTTP_METHOD_DELETE "delete"
#define RUSTG_HTTP_METHOD_PATCH "patch"
#define RUSTG_HTTP_METHOD_HEAD "head"
#define RUSTG_HTTP_METHOD_POST "post"
#define rustg_http_request_blocking(method, url, body, headers, options) RUSTG_CALL(RUST_G, "http_request_blocking")(method, url, body, headers, options)
#define rustg_http_request_async(method, url, body, headers, options) RUSTG_CALL(RUST_G, "http_request_async")(method, url, body, headers, options)
#define rustg_http_request_fire_and_forget(method, url, body, headers, options) RUSTG_CALL(RUST_G, "http_request_fire_and_forget")(method, url, body, headers, options)
#define rustg_http_check_request(req_id) RUSTG_CALL(RUST_G, "http_check_request")(req_id)
#define RUSTG_JOB_NO_RESULTS_YET "NO RESULTS YET"
#define RUSTG_JOB_ERROR "JOB PANICKED"

// file feature, needed by TTS to bootstrap tmp/tts/init.txt before rustg HTTP can write
// response bodies into the directory. Pure-rust stdlib, no extra deps.
#define rustg_file_write(text, fname) RUSTG_CALL(RUST_G, "file_write")(text, fname)
#define rustg_file_read(fname) RUSTG_CALL(RUST_G, "file_read")(fname)
