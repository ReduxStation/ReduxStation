# TGS Deployment Runbook

This codebase runs in production under [tgstation-server](https://github.com/tgstation/tgstation-server) (TGS) v6 or later. Bare DreamDaemon is no longer supported.

## First-time install

After provisioning a host with Docker Engine + Compose v2, work through the steps below ONCE per instance.

### 1. Clone the repo and provision the env file

```bash
git clone https://github.com/ResurgenceStation/ResurgenceStation.git
cd ResurgenceStation
cp .env.example .env
$EDITOR .env  # set MYSQL_ROOT_PASSWORD and MYSQL_PASSWORD to strong values
```

### 2. Configure server-local overrides (optional)

Anything specific to one deployment lives in `docker-compose.override.yml`, which Compose merges automatically. Keeps the canonical compose file generic.

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
mkdir -p caddy-sites.d
$EDITOR docker-compose.override.yml
```

The default override template enables the bundled TGS web control panel (the upstream image only ships the API by default) and mounts a `./caddy-sites.d/` directory at `/etc/caddy/sites.d/` inside the Caddy container. The canonical `docker/caddy/Caddyfile` ends with `import /etc/caddy/sites.d/*.caddy`, so anything you drop in `caddy-sites.d/<name>.caddy` becomes an additional site block on next reload — without touching the tracked Caddyfile.

If you want to reverse-proxy to a totally separate compose stack on the same host (e.g. a personal project hosted off the same domain), don't add it as a service block here. Run that project from its own directory with its own `docker-compose.yml`, give its container a network alias on this stack's default network, and add a snippet in `caddy-sites.d/<site>.caddy` that reverse-proxies to the alias.

### 3. Bring up the stack

```bash
docker compose build
docker compose up -d
```

The mariadb image's `/docker-entrypoint-initdb.d/01-init.sh` runs once on first volume creation and seeds:
- `ss13` schema (game database, with `tgstation_schema_prefixed.sql` + `mentor.sql` + `donator.sql` + `brdetector.sql`)
- `statbus` schema (slimbus alt_db)
- `tgs` schema (TGS server's own state, empty — TGS populates on first launch)

Grants `ss13` user access to all three.

### 4. Pin BYOND to 516.1680 in the panel

Open the panel hostname (default: `panel.owo.fm`; the canonical Caddyfile reverse-proxies it to `tgs:5000`) and complete TGS first-run setup: create initial admin, create instance, set repo URL.

In the **Engine** tab, install and activate **BYOND 516.1680**. `dependencies.sh` declares this exact build. Newer 516.x builds (1681+) have a regressed lexer that rejects integer-suffix CSS time units like `1500ms` inside DM multi-line strings, breaking `interface/stylesheet.dm` compilation.

### 5. Install PostCompile (once)

Only `PostCompile` needs a manual install. From the next deploy onward, PostCompile self-installs the other event scripts (`PreStartup`, `RoundStart`, `RoundEnd`) automatically — see the loop at the bottom of `tools/tgs4_scripts/PostCompile.sh`.

```bash
docker run --rm \
  -v "$PWD/tools/tgs4_scripts":/src:ro \
  -v resurgencestation_tgs_instances:/v \
  alpine sh -c 'cp /src/PostCompile.sh /v/ResurgenceStation/Configuration/EventScripts/PostCompile && chmod +x /v/ResurgenceStation/Configuration/EventScripts/PostCompile'
```

What each event script does once installed:

| Script | Purpose |
|---|---|
| `PostCompile` | Scatters `librust_g.so`, `libBSQL.so`, `libquickwrite.so` into every path BYOND's `call_ext()` checks (`/usr/local/lib`, `/usr/lib/i386-linux-gnu`, the BYOND `bin/` dir, plus the game working dir under multiple name variants) so DB connections and logging do not fail with cryptic dlopen errors. Also re-installs the sibling event scripts on each compile. |
| `PreStartup` | Symlinks the active game directory's `data/` to the persistent `/tgstation/data` mount. EVERY game-state file (logs, player_saves, npc_saves, spritesheets, photo albums, mode.txt, etc.) survives across deploys. Also seeds `serverinfo.json` so the public log-parser does not block all rounds on a brand-new deploy. |
| `RoundStart` | Receives the new round's id from the game via `TgsTriggerEvent("RoundStart", ...)` and writes it into `/tgstation/data/serverinfo.json`. The public-log-parser polls this file and 404s the active round's logs until `RoundEnd` fires. |
| `RoundEnd` | Receives the ended round's id and clears `/tgstation/data/serverinfo.json` so the log-parser stops hiding it. |

Trigger one deploy from the panel (or by pushing to master). PostCompile runs, scatters the libs, and copies the latest `PreStartup` / `RoundStart` / `RoundEnd` from the deployed source tree into `Configuration/EventScripts/`. From there the chain self-syncs.

The `tools/tgs4_scripts/` folder name is legacy from TGS3/TGS4 conventions where event scripts lived in the codebase. TGS6+ reads scripts from the instance Configuration directory instead, but we keep the folder as the reference source of truth — the auto-install copies *from* there *to* there on every compile.

### 6. Wire the auto-deploy GitHub Actions workflow (optional but recommended)

If you want every merge to master to auto-deploy, configure four repository secrets under `Settings → Secrets and variables → Actions`:

| Secret | Value |
|---|---|
| `TGS_URL` | Your TGS panel URL (e.g. `https://panel.owo.fm`) |
| `TGS_USERNAME` | Name of a TGS user with the perms below |
| `TGS_PASSWORD` | Password for that user |
| `TGS_INSTANCE_ID` | Numeric instance id (visible as `(N)` after the instance name in the panel header) |

Create that TGS user with the minimum perm set:
- **Repository → Update Branch** (so the workflow can `POST /api/Repository {"updateFromOrigin": true}`)
- **Deployment → Create Deployment** (so the workflow can `PUT /api/DreamMaker`)

Granting more is harmless but unnecessary; granting less makes the workflow 403 on either step. The whoami probe in `.github/workflows/tgs-auto-deploy.yml` will dump the user's effective perms in the run log if anything misroutes.

If the secrets are unset, the workflow logs a notice and exits 0 — it does not redden master CI.

## Per-deploy workflow

In normal operation, every PR merged into `master` triggers the `TGS auto-deploy` workflow. It:

1. Logs into the TGS HTTP API at `${TGS_URL}/api/` with the `TGS_USERNAME` / `TGS_PASSWORD` repository secrets.
2. `POST /api/Repository {"updateFromOrigin": true}` — pulls the new HEAD on the live instance.
3. `PUT /api/DreamMaker` — queues a fresh compile.
4. TGS runs `PostCompile` (scatters native libs, refreshes sibling event scripts), validates the new build, and hot-swaps the watchdog. The running round is unaffected; the next round runs the new code.

PRs that have NOT been merged stay testable through TGS's **Test Merge** feature on the panel.

### Manual deploy fallback

If the auto-deploy workflow is broken or you want to deploy without merging (e.g. during incident response), the panel works end-to-end:

1. **Repository tab** → Reset/Update from Remote (pulls the latest master).
2. **Deployment tab** → Deploy. TGS clones, runs DreamMaker, runs PostCompile, then hot-swaps the game.
3. Watch the **Jobs** tab for the compile and watchdog launch.

You can also fire the workflow on demand from the GitHub UI (Actions → TGS auto-deploy → Run workflow) without merging anything, since it has `workflow_dispatch:` enabled.

## Migrating an existing deployment

If you are pointing a fresh checkout at an existing `mariadb_data` volume (rather than starting fresh), `01-init.sh` will not run — it only fires on first volume creation. Manually create the `tgs` database that the seed would have made:

```bash
docker exec -e MPW="$MYSQL_ROOT_PASSWORD" <mariadb_container> \
  mariadb -uroot -p"$MPW" -e \
  "CREATE DATABASE IF NOT EXISTS tgs CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   GRANT ALL PRIVILEGES ON tgs.* TO 'ss13'@'%';
   FLUSH PRIVILEGES;"
```

For nuking and rebuilding game data without touching TGS state (panel users, deploy history, instance config), use `tools/wipe-game-data.sh --yes-i-mean-it` — drops and re-seeds `ss13` and `statbus` from the schema files in the mariadb image and clears `/tgstation/data/logs/*` plus `serverinfo.json`. The `tgs` schema is intentionally untouched.

## Common failures

### Logs at logs.owo.fm 404 even though the game is writing round files

PreStartup did not run, or it failed before symlinking. The active game directory's `data/` should be a symlink to `/tgstation/data`:

```bash
docker exec <tgs_container> ls -la /tgs_instances/<instance>/Game/Live/data
```

Should show `Game/Live/data -> /tgstation/data`. If it shows a real directory instead, run the script manually:

```bash
docker exec <tgs_container> /tgs_instances/<instance>/Configuration/EventScripts/PreStartup /tgs_instances/<instance>/Game/Live
```

### Player saves vanish across deploys

Same root cause as the logs 404 above — `data/` is not symlinked into `/tgstation/data`. Players' `preferences.sav` lives at `data/player_saves/<letter>/<ckey>/preferences.sav`; without the symlink, those writes go to the per-deploy `Game/<uuid>/` directory and die when TGS hot-swaps to a fresh game dir on the next compile.

Fix is identical: confirm or run PreStartup. Older revisions of PreStartup only symlinked `data/logs` and missed everything else; if you are recovering from that case, merge whatever's in `Game/Live/data/` into `/tgstation/data/` (rsync `-au` for newer-wins semantics) before running the new PreStartup so existing characters survive.

### "libbyond.so: undefined symbol: log_write" (or similar) at world.New()

```
Runtime in code/__HELPERS/_logging.dm, line 174:
/tgs_instances/.../Byond/<ver>/byond/bin/libbyond.so: undefined symbol: log_write
proc name: log world (/proc/log_world)
src: null
call stack:
log world("World loaded at HH:MM:SS!")
world: New()
```

BYOND's `call_ext()` resolution checks the game working directory under several name variants (bare, `.so`, `lib-` prefix) and the BYOND install's own `bin/` directory before falling back to `LD_LIBRARY_PATH` and the `ldconfig` cache. When none of those satisfy, dlopen fails and BYOND reports the error as if `libbyond.so` itself has an undefined symbol. The misleading message blames `libbyond.so` even though the real problem is that the rust_g binary is not in the path BYOND checks first.

PostCompile scatters every native lib (`librust_g.so`, `libBSQL.so`, `libquickwrite.so`) to all four location families:

| Family | Variants written |
|---|---|
| Game working dir (`$1`) | `<BASE>`, `<BASE>.so`, `lib<BASE>.so` |
| `/usr/local/lib` | `<BASE>.so`, `lib<BASE>.so` |
| `/usr/lib/i386-linux-gnu` | `<BASE>.so`, `lib<BASE>.so` |
| BYOND `bin/` (read from `Byond/ActiveVersion.txt`) | `<BASE>`, `<BASE>.so`, `lib<BASE>.so` |

If you see the runtime, install the latest PostCompile, run it manually for the active `Game/Live`, then restart the watchdog so DD re-dlopens fresh.

### "BSQL library failed to provide connect operation for connection id (MySql)"

Same root cause as the `log_write` runtime above (BYOND's `call_ext` dlopen chain not finding the lib in the path it checks first). Same fix: install the latest PostCompile, run it for `Game/Live`, restart the watchdog. Verify with:

```bash
docker exec <tgs_container> ldconfig -p | grep -iE "BSQL|rust_g|quickwrite"
```

You should see all three. If not, ensure `Configuration/EventScripts/PostCompile` exists and is executable, then redeploy.

### "DMAPI interop version is less than tgstation-server's version"

The codebase's bundled DMAPI is older than the running TGS server. The library lives in `code/modules/tgs/` and `code/__DEFINES/tgs.dm`. The `.github/workflows/dmapi-updater.yml` workflow opens a PR with the bump on a weekly schedule; merge it (after fixing any consumer-side compile errors that surface — typical drift: chat command `Run` signature changes, test_merge field renames).

### "instance cannot be placed at the given path because it is not empty"

A bind mount in `docker-compose.yml` is pre-creating the instance directory tree before TGS gets a chance to populate it. Confirm `docker-compose.yml` does NOT bind-mount any path under `/tgs_instances/<instance>/`. The `./config:` bind mount that older copies of the compose file used has been removed; if yours still has it, drop the line, restart TGS, create the instance, then ensure your live game config is copied INTO the volume's `Configuration/GameStaticFiles/config/` directory (TGS-canonical location for static game files).

### Webpanel only shows a logo

`ControlPanel.Enable` defaults to `false` in the bundled TGS configuration. The `docker-compose.override.yml.example` template includes the override block that flips it on:

```yaml
services:
  tgs:
    environment:
      ControlPanel__Enable: "true"
      ControlPanel__AllowAnyOrigin: "true"
```

If your override file is missing this, copy the block in and `docker compose up -d tgs`.
