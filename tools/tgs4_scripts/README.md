# TGS event scripts (reference copies)

The scripts in this folder are **reference source** for setting up a new TGS instance. They are NOT picked up automatically by TGS6+ even though the folder name suggests TGS4 era conventions.

TGS reads event scripts from the instance volume at `<tgs_instances>/<instance_name>/Configuration/EventScripts/`, not from the codebase. To install one, copy the relevant file into that path and `chmod +x` it. See [docs/tgs-deployment.md](../../docs/tgs-deployment.md) for the exact one-liner.

## Files

- **PostCompile.sh** - scatters `librust_g.so`, `libBSQL.so`, and `libquickwrite.so` from the freshly compiled game directory into `/usr/local/lib`, then runs `ldconfig`. Required for the game to be able to `dlopen()` these libs at runtime. Without this, DB connections fail with "BSQL library failed to provide connect operation".
- **PreStartup.sh** - symlinks the active game's `data/logs` directory to the persistent `/tgstation/data/logs` mount so `logs.owo.fm` (Caddy file_server on the same volume) sees rounds the TGS-managed game writes. Idempotent across redeploys.
- **PreSynchronize.sh / .bat / .ps1** - cross-platform pre-sync hooks. Currently no-op; kept as templates for future use.
