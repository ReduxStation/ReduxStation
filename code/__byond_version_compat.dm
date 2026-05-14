// BYOND 516 compatibility macros for callback dispatch.
//
// In BYOND 516, `call(object, /typepath/proc/name)(args)` became STATIC dispatch:
// it executes the literal base proctype body and bypasses subclass overrides.
// Pre-516, the same call did dynamic dispatch and hit overrides correctly.
//
// `CALLBACK(src, .proc/X)` / `INVOKE_ASYNC(src, .proc/X)` stores the typepath
// `/the/type/proc/X` in the callback's delegate. When SSTimer (or any other
// invoker) fires it via `call(object, delegate)(arglist(args))`, BYOND 516
// runs the base body, not the override. The override never gets hit.
//
// Upstream tgstation fixed this in PR #71161 with the PROC_REF macro. The
// macro expands to `nameof(.proc/X)` which evaluates to a STRING (the proc
// name). `call(object, "name_string")(args)` is dynamic dispatch by name in
// BYOND 516 -- it walks the object's type hierarchy and finds the override.
//
// Use PROC_REF(name) inside CALLBACK/INVOKE_ASYNC instead of .proc/name to
// get the override-respecting behavior we relied on pre-516.
//
// References:
//   - upstream code/__byond_version_compat.dm
//   - upstream PR #71161 "515 Compatibility"
//   - C:\Users\marwa\.claude\plans\full-report-bug-audit-2026-05-12.md
//
// Note: the BYOND version gate lives in code/_compile_options.dm (the
// MIN_COMPILER_VERSION / MIN_COMPILER_BUILD pair). Bumping that to a value
// where these macros (and call-by-string dispatch) are guaranteed to behave
// like upstream needs a separate, deliberate change to the version gate, not
// a redefinition here. dependencies.sh already pins BYOND 516.1680 for the
// live build, and nameof() has been available since BYOND 514, so the
// macros below compile and behave correctly on every supported build.

/// Call-by-name proc reference. Use inside CALLBACK / INVOKE_ASYNC so the
/// callback hits overrides via dynamic dispatch instead of the base proctype.
#define PROC_REF(X) (nameof(.proc/##X))

/// Call-by-name verb reference. Same dispatch semantics as PROC_REF.
#define VERB_REF(X) (nameof(.verb/##X))

/// Call-by-name proc reference on an explicit type. Use when the callback's
/// target object's declared type differs from the enclosing proc's type.
#define TYPE_PROC_REF(TYPE, X) (nameof(##TYPE.proc/##X))

/// Call-by-name verb reference on an explicit type.
#define TYPE_VERB_REF(TYPE, X) (nameof(##TYPE.verb/##X))

/// Call-by-typepath proc reference for global procs. Global procs have no
/// override dispatch (single-path), so the typepath form is correct here.
/// Use inside `CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(X))`.
#define GLOBAL_PROC_REF(X) (/proc/##X)
