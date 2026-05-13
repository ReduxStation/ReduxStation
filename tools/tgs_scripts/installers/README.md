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

`librust_g.so`, `libBSQL.so`, and `libquickwrite.so` are committed to the repo
root under their standard names. Every TGS deploy places them in the game
directory. BYOND's `call_ext()` finds them there because DreamDaemon's CWD is
the game directory. No scatter, no symlinks, no scripts.
