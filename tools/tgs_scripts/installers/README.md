# TGS-6 EventScripts wrapper installers

`Configuration/EventScripts/` is a TGS-managed directory whose contents persist
across deploys. TGS does NOT auto-update its contents from the repo on each
compile. That's a deliberate design choice (operator owns those scripts).

Our event scripts (`RoundStart.sh`, `RoundEnd.sh`) need to live there to fire
on `world.TgsTriggerEvent(...)` from DM. But we want their LOGIC to auto-update
from the repo on every deploy. The way to get both is the **wrapper pattern**:

1. Install a thin **wrapper** at `Configuration/EventScripts/<EventName>.sh`
   one time. The wrapper never changes.
2. The wrapper detects which event it is (from its own filename via `$0`)
   and forwards execution to `$GAME_DIR/tools/tgs_scripts/<EventName>.sh` —
   the **real** script, deployed fresh from the repo by every TGS deploy.

This way every change to a `tools/tgs_scripts/*.sh` script auto-applies on the
next deploy without operator intervention. The wrapper itself stays in
EventScripts/ forever, untouched.

## Operator setup (one time, only when initially adopting this PR)

1. In TGS panel → Files & Scripts, **DELETE** any leftover scripts from the
   old custom pipeline:
   - `PostCompile.sh`
   - `DreamDaemonPreLaunch.sh`

2. In TGS panel → Files & Scripts, for each event name below:
   - **CREATE** `<EventName>.sh` (or **REPLACE** if one already exists).
   - **PASTE** the contents of `EventScript-wrapper.sh` from this directory.
   - Save.

   Events to install wrappers for:
   - `RoundStart.sh`
   - `RoundEnd.sh`

That's it. After this one-time setup, every deploy auto-updates the real
script logic without any operator action.

## Persistent data (Configuration/GameStaticFiles)

TGS-6 has a native mechanism for files that persist across deploys and get
linked into the game directory automatically: `Configuration/GameStaticFiles/`.
Anything placed under that directory is hard-linked into the deployed game
directory on every deploy.

For our setup, the persistent `game_data` volume is mounted **directly at the
TGS GameStaticFiles path** in the TGS container — see `docker-compose.yml`:

```yaml
- game_data:/tgs_instances/ResurgenceStation/Configuration/GameStaticFiles/data
```

This is the upstream tgstation `RUNNING_A_SERVER.md` setup:

> "We have two directories which should be setup in the instance's
> Configuration/GameStaticFiles directory: config ... data should be initially
> created as an empty directory. The game stores persistent data here."

No symlink, no PreCompile/PostCompile/DreamDaemonPreLaunch script. TGS sees
`Configuration/GameStaticFiles/data/`, hard-links its contents into
`Game/Live/data/` on every deploy automatically. The game writes to
`data/foo` (relative to its CWD = `Game/Live/`), which resolves through the
hard link back to the persistent volume.

## Native libraries

`rust_g.so`, `libBSQL.so`, and `libquickwrite.so` are committed to the repo
root. Every TGS deploy puts them at `Game/Live/<name>` via the normal
source-tree copy.

BYOND's `call_ext("rust_g", ...)` on Linux maps to `dlopen("rust_g.so")` —
the literal call_ext name plus `.so`. Verified empirically by inspecting the
live DreamDaemon's `/proc/<PID>/maps`, which shows the lib loaded from
`.../rust_g.so` (not `rust_g` and not `librust_g.so`). `dlopen` does NOT search the current working
directory; it searches `LD_LIBRARY_PATH` and the ldconfig cache. TGS-6
launches DD via a wrapper script that does:

```sh
export LD_LIBRARY_PATH="$ORIGIN:$LD_LIBRARY_PATH"
```

where `$ORIGIN` is the BYOND `bin/` dir. The `$LD_LIBRARY_PATH` on the right
side is whatever the TGS process inherits. We set it on the tgs service in
`docker-compose.yml`:

```yaml
environment:
  LD_LIBRARY_PATH: /tgs_instances/ResurgenceStation/Game/Live
```

So DD's effective search path is `BYOND/bin/:Game/Live/`. BYOND finds the
literal `rust_g` file (along with `libBSQL.so` and `libquickwrite.so`) in
`Game/Live/` via this path. No scatter script required. Every deploy refreshes
the lib content automatically.

A one-time cleanup on the live server removes any stale lib copies from
`Byond/<version>/byond/bin/` left over from the old scatter; without this,
BYOND finds the stale BYOND/bin copy first and never reaches the fresh
`Game/Live/` copy.
