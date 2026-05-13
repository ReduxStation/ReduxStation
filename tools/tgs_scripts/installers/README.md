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

For our setup, we want `data/` (player_saves, spritesheets, logs, etc.) to
persist. So the operator does one of:

A. **Symlink the existing volume** (no docker-compose change):
```bash
# Inside the TGS container (one-time):
ln -s /tgstation/data /tgs_instances/ResurgenceStation/Configuration/GameStaticFiles/data
```

B. **Re-mount the volume at the TGS path** (docker-compose change):
```yaml
# In docker-compose.yml, change the tgs service's data mount from
#   - resurgencestation_game_data:/tgstation/data
# to
#   - resurgencestation_game_data:/tgs_instances/ResurgenceStation/Configuration/GameStaticFiles/data
```

After either A or B, TGS automatically links `Game/Live/data` → that directory
on every deploy. No PreCompile/PostCompile/DreamDaemonPreLaunch script needed.

## Native libraries

`librust_g.so`, `libBSQL.so`, and `libquickwrite.so` are committed to the repo
root under their standard names. Every TGS deploy places them in the game
directory. BYOND's `call_ext()` finds them there because DreamDaemon's CWD is
the game directory. No scatter, no symlinks, no scripts.
