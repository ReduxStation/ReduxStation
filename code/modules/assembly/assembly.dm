#define WIRE_RECEIVE		(1<<0)
#define WIRE_PULSE			(1<<1)
#define WIRE_PULSE_SPECIAL	(1<<2)
#define WIRE_RADIO_RECEIVE	(1<<3)
#define WIRE_RADIO_PULSE	(1<<4)
#define ASSEMBLY_BEEP_VOLUME 5

/obj/item/assembly
	name = "assembly"
	desc = "A small electronic device that should never exist."
	icon = 'icons/obj/assemblies/new_assemblies.dmi'
	icon_state = ""
	flags_1 = CONDUCT_1
	w_class = WEIGHT_CLASS_SMALL
	materials = list(MAT_METAL=100)
	throwforce = 2
	throw_speed = 3
	throw_range = 7

	var/is_position_sensitive = FALSE	//set to true if the device has different icons for each position.
										//This will prevent things such as visible lasers from facing the incorrect direction when transformed by assembly_holder's update_icon()
	var/secured = TRUE
	var/list/attached_overlays = null
	var/obj/item/assembly_holder/holder = null
	var/wire_type = WIRE_RECEIVE | WIRE_PULSE
	var/attachable = FALSE // can this be attached to wires
	var/datum/wires/connected = null

	var/next_activate = 0 //When we're next allowed to activate - for spam control

/obj/item/assembly/get_part_rating()
	return 1

/obj/item/assembly/proc/on_attach()

/obj/item/assembly/proc/on_detach() //call this when detaching it from a device. handles any special functions that need to be updated ex post facto
	if(!holder)
		return FALSE
	forceMove(holder.drop_location())
	holder = null
	return TRUE

/obj/item/assembly/proc/holder_movement()							//Called when the holder is moved
	if(!holder)
		return FALSE
	setDir(holder.dir)
	return TRUE

/obj/item/assembly/proc/is_secured(mob/user)
	if(!secured)
		to_chat(user, "<span class='warning'>The [name] is unsecured!</span>")
		return FALSE
	return TRUE


//Called when another assembly acts on this one, var/radio will determine where it came from for wire calcs
/obj/item/assembly/proc/pulsed(radio = FALSE)
	// AUDIT-DISPATCH: button activation funnels through here. If pulsed fires
	// but neither activate audit (base nor override) appears, INVOKE_ASYNC
	// failed to reach activate. Bug B diagnostic.
	if(istype(src, /obj/item/assembly/control))
		log_game("AUDIT assembly/pulsed FIRED: src=[src] type=[type] wire_type=[wire_type] WIRE_RECEIVE_bit=[!!(wire_type & WIRE_RECEIVE)] WIRE_RADIO_RECEIVE_bit=[!!(wire_type & WIRE_RADIO_RECEIVE)] radio=[radio]")
	if(wire_type & WIRE_RECEIVE)
		if(istype(src, /obj/item/assembly/control))
			log_game("AUDIT assembly/pulsed: WIRE_RECEIVE branch - calling INVOKE_ASYNC(src, PROC_REF(activate))")
		// BYOND 516 dispatch fix: PROC_REF(activate) routes via dynamic dispatch
		// and reaches the /obj/item/assembly/control override that iterates
		// GLOB.machines to open the linked doors. With the old .proc/activate
		// form, the base assembly/activate ran (a no-op for door buttons). Bug B fix.
		INVOKE_ASYNC(src, PROC_REF(activate))
	if(radio && (wire_type & WIRE_RADIO_RECEIVE))
		if(istype(src, /obj/item/assembly/control))
			log_game("AUDIT assembly/pulsed: WIRE_RADIO_RECEIVE branch - calling INVOKE_ASYNC(src, PROC_REF(activate))")
		INVOKE_ASYNC(src, PROC_REF(activate))
	return TRUE


//Called when this device attempts to act on another device, var/radio determines if it was sent via radio or direct
/obj/item/assembly/proc/pulse(radio = FALSE)
	if(connected && wire_type)
		connected.pulse_assembly(src)
		return TRUE
	if(holder && (wire_type & WIRE_PULSE))
		holder.process_activation(src, 1, 0)
	if(holder && (wire_type & WIRE_PULSE_SPECIAL))
		holder.process_activation(src, 0, 1)
	return TRUE


// What the device does when turned on
/obj/item/assembly/proc/activate()
	// AUDIT-DISPATCH: this base body only sets next_activate and returns. If
	// this fires for an /obj/item/assembly/control subtype, dispatch went to
	// the base instead of the door-opening override - Bug B is rooted as a
	// dispatch problem. If this does NOT fire for a control instance but the
	// control override DOES fire, dispatch is fine.
	if(istype(src, /obj/item/assembly/control))
		log_game("AUDIT BASE assembly/activate FIRED on control subtype: src=[src] type=[type] next_activate=[next_activate] secured=[secured]")
	if(QDELETED(src) || !secured || (next_activate > world.time))
		return FALSE
	next_activate = world.time + 30
	return TRUE


/obj/item/assembly/proc/toggle_secure()
	secured = !secured
	update_icon()
	return secured


/obj/item/assembly/attackby(obj/item/W, mob/user, params)
	if(isassembly(W))
		var/obj/item/assembly/A = W
		if((!A.secured) && (!secured))
			holder = new/obj/item/assembly_holder(get_turf(src))
			holder.assemble(src,A,user)
			to_chat(user, "<span class='notice'>You attach and secure \the [A] to \the [src]!</span>")
		else
			to_chat(user, "<span class='warning'>Both devices must be in attachable mode to be attached together.</span>")
		return
	..()

/obj/item/assembly/screwdriver_act(mob/living/user, obj/item/I)
	if(..())
		return TRUE
	if(toggle_secure())
		to_chat(user, "<span class='notice'>\The [src] is ready!</span>")
	else
		to_chat(user, "<span class='notice'>\The [src] can now be attached!</span>")
	add_fingerprint(user)
	return TRUE

/obj/item/assembly/examine(mob/user)
	. = ..()
	. += "<span class='notice'>\The [src] [secured? "is secured and ready to be used!" : "can be attached to other things."]</span>"


/obj/item/assembly/attack_self(mob/user)
	if(!user)
		return FALSE
	user.set_machine(src)
	interact(user)
	return TRUE

/obj/item/assembly/interact(mob/user)
	return ui_interact(user)
