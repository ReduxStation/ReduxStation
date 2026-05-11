// Demo subsystem overrides.
//
// DM proc resolution rule: when the same proc is defined multiple times on
// the same type across different files, the LAST definition wins entirely.
// `..()` from the surviving definition jumps to the PARENT TYPE, not to the
// shadowed sibling. The old wrappers in this file were `. = ..()` calls
// that hit /obj/machinery/door/update_icon (which only sets "door0"/"door1"),
// not the airlock/firedoor/poddoor/window-specific bodies — and so during
// cycling, animation, welding, etc. every door reverted to the generic
// /obj/machinery/door look. That's Bug A.
//
// Each override below mirrors its base body verbatim, then tacks
// SSdemo.mark_dirty(src) on the end. If the base body changes upstream,
// these need to follow.

// Base airlock.dm #undef's the AIRLOCK_* state enums at its file bottom
// (lines 1587-1605). We need them in scope to dispatch the same way the
// base body does, so re-#define them here and #undef at end of block.
#define AIRLOCK_CLOSED	1
#define AIRLOCK_CLOSING	2
#define AIRLOCK_OPEN	3
#define AIRLOCK_OPENING	4
#define AIRLOCK_DENY	5
#define AIRLOCK_EMAG	6

// Mirrors /obj/machinery/door/airlock/update_icon @ code/game/machinery/doors/airlock.dm:432
// IMPORTANT: must call set_airlock_overlays(state) — that's the proc that
// builds frame/filling/lights/panel/weld/sparks/damag/note overlays. Without
// it the airlock has the correct icon_state shell but NO overlay stack, so
// cycling airlocks visibly freeze on whatever overlay was last applied
// (the user-reported "cycling airlock sprite issue").
/obj/machinery/door/airlock/update_icon(state = 0, override = 0)
	if(operating && !override)
		return
	switch(state)
		if(0)
			if(density)
				state = AIRLOCK_CLOSED
			else
				state = AIRLOCK_OPEN
			icon_state = ""
		if(AIRLOCK_OPEN, AIRLOCK_CLOSED)
			icon_state = ""
		if(AIRLOCK_DENY, AIRLOCK_OPENING, AIRLOCK_CLOSING, AIRLOCK_EMAG)
			icon_state = "nonexistenticonstate" //MADNESS
	set_airlock_overlays(state)
	SSdemo.mark_dirty(src)

#undef AIRLOCK_CLOSED
#undef AIRLOCK_CLOSING
#undef AIRLOCK_OPEN
#undef AIRLOCK_OPENING
#undef AIRLOCK_DENY
#undef AIRLOCK_EMAG

// Mirrors /obj/machinery/door/firedoor/update_icon @ code/game/machinery/doors/firedoor.dm:172
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

// Mirrors /obj/machinery/door/poddoor/update_icon @ code/game/machinery/doors/poddoor.dm:80
/obj/machinery/door/poddoor/update_icon()
	if(density)
		icon_state = "closed"
	else
		icon_state = "open"
	SSdemo.mark_dirty(src)

// Mirrors /obj/machinery/door/window/update_icon @ code/game/machinery/doors/windowdoor.dm:58
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
