
// /obj/machinery/door/airlock/update_icon at code/game/machinery/doors/airlock.dm
// has airlock-specific switch-on-state logic that builds the layered overlays
// via set_airlock_overlays(state). It does NOT have a /obj/machinery/door
// parent fallback that knows about AIRLOCK_CLOSED/AIRLOCK_OPENING/etc.
//
// In DM, two definitions of the same proc on the same type behave as
// "last include wins, the previous body becomes inaccessible". A wrapper
// pattern like
//
//   /obj/machinery/door/airlock/update_icon(state, override)
//       . = ..()
//       SSdemo.mark_dirty(src)
//
// SHADOWS the base body and `..()` skips up to /obj/machinery/door, which
// only knows icon_state = "door0/door1". The airlock-specific overlay logic
// is orphaned and the airlock sprite freezes on whatever it was last set
// to, regardless of what state we asked for. This was the cycling-airlock-
// animation desync bug: close() called update_icon(AIRLOCK_CLOSING, 1) but
// neither the closing animation nor the closed sprite ever got applied.
//
// Replace with a complete reimplementation that mirrors the base airlock
// body and appends the SSdemo.mark_dirty(src) call. If the upstream airlock
// update_icon ever changes shape, this override has to be re-mirrored - the
// duplication is unavoidable as long as the demo subsystem needs a hook
// here without touching the upstream tree.
//
// Numeric literals below correspond to airlock.dm's per-file
// AIRLOCK_CLOSED=1 / CLOSING=2 / OPEN=3 / OPENING=4 / DENY=5 / EMAG=6
// defines. Those defines are #undef'd at the bottom of airlock.dm and so
// are not visible from this file; using the integers keeps the file
// self-contained without forcing a redefine that would conflict on
// recompile if the originals shift.
/obj/machinery/door/airlock/update_icon(state=0, override=0)
	if(operating && !override)
		return
	switch(state)
		if(0)
			if(density)
				state = 1 // AIRLOCK_CLOSED
			else
				state = 3 // AIRLOCK_OPEN
			icon_state = ""
		if(1, 3) // AIRLOCK_CLOSED, AIRLOCK_OPEN
			icon_state = ""
		if(2, 4, 5, 6) // AIRLOCK_CLOSING, AIRLOCK_OPENING, AIRLOCK_DENY, AIRLOCK_EMAG
			icon_state = "nonexistenticonstate" //MADNESS
	set_airlock_overlays(state)
	SSdemo.mark_dirty(src)

// firedoor, poddoor, and window each have their OWN update_icon body in
// code/game/machinery/doors/{firedoor,poddoor,windowdoor}.dm with subtype-
// specific icon_state and overlay logic. The wrapper-pattern override that
// used to live here `. = ..()` followed by SSdemo.mark_dirty(src) shadows
// those bodies because in DM two definitions of the same proc on the same
// type fall to "last include wins, previous body inaccessible" (see the
// long airlock comment above). `..()` skipped up to /obj/machinery/door
// /update_icon which only knows generic "door0"/"door1" icon_states, so
// none of these doors rendered correctly until the round was a few seconds
// in - the symptom on firedoors was particularly visible during fire alerts
// (welded overlay missing, generic door sprite under the alert frame).
//
// Same fix as the airlock above: full reimplementation that mirrors the
// base body and appends the SSdemo hook at the end.

/obj/machinery/door/firedoor/update_icon()
	cut_overlays()
	if(density)
		icon_state = "door_closed"
		if(welded)
			add_overlay("welded")
	else
		icon_state = "door_open"
		if(welded)
			add_overlay("welded_open")
	SSdemo.mark_dirty(src)

/obj/machinery/door/poddoor/update_icon()
	if(density)
		icon_state = "closed"
	else
		icon_state = "open"
	SSdemo.mark_dirty(src)

/obj/machinery/door/window/update_icon()
	if(density)
		icon_state = base_state
	else
		icon_state = "[base_state]open"
	SSdemo.mark_dirty(src)

/turf/ChangeTurf(path, list/new_baseturfs, flags)
	. = ..()
	SSdemo.mark_turf(src)

/atom/movable/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	. = ..()
	if(.)
		SSdemo.mark_dirty(src)
