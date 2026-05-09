# TGS event scripts (reference copies)

The scripts in this folder are **reference source** for setting up a new TGS instance. They are NOT picked up automatically by TGS6+ even though the folder name suggests TGS4 era conventions.

TGS reads event scripts from the instance volume at `<tgs_instances>/<instance_name>/Configuration/EventScripts/`, not from the codebase. To install one, copy the relevant file into that path and `chmod +x` it. See [docs/tgs-deployment.md](../../docs/tgs-deployment.md) for the exact one-liner.

## Files

- **PostCompile.sh** - scatters `librust_g.so`, `libBSQL.so`, and `libquickwrite.so` from the freshly compiled game directory into `/usr/local/lib`, then runs `ldconfig`. Required for the game to be able to `dlopen()` these libs at runtime. Without this, DB connections fail with "BSQL library failed to provide connect operation".
- **PreStartup.sh** - symlinks the active game's `data/logs` directory to the persistent `/tgstation/data/logs` mount so `logs.owo.fm` (Caddy file_server on the same volume) sees rounds the TGS-managed game writes. Also seeds `/tgstation/data/serverinfo.json` with `{"servers":[]}` if missing so the public-log-parser's ongoing-round-protection has something to fetch on a fresh deploy. Idempotent.
- **RoundStart.sh** - invoked when the game emits `TgsTriggerEvent("RoundStart", ...)` from `code/controllers/subsystem/dbcore.dm::SetRoundID`. Receives the round id as `$1` and writes it to `/tgstation/data/serverinfo.json`. The public-log-parser polls this file and 404s the active round's directory until `RoundEnd` clears it.
- **RoundEnd.sh** - invoked when the game emits `TgsTriggerEvent("RoundEnd", ...)` from `code/controllers/subsystem/dbcore.dm::SetRoundEnd`. Clears `/tgstation/data/serverinfo.json` so the parser stops hiding the round.
- **PreSynchronize.sh / .bat / .ps1** - cross-platform pre-sync hooks. Currently no-op; kept as templates for future use.
