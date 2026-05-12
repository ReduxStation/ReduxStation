/*
	USAGE:

		var/datum/callback/C = new(object|null, /proc/type/path|"procstring", arg1, arg2, ... argn)
		var/timerid = addtimer(C, time, timertype)
		OR
		var/timerid = addtimer(CALLBACK(object|null, /proc/type/path|procstring, arg1, arg2, ... argn), time, timertype)

		Note: proc strings can only be given for datum proc calls, global procs must be proc paths
		Also proc strings are strongly advised against because they don't compile error if the proc stops existing
		See the note on proc typepath shortcuts

	INVOKING THE CALLBACK:
		var/result = C.Invoke(args, to, add) //additional args are added after the ones given when the callback was created
		OR
		var/result = C.InvokeAsync(args, to, add) //Sleeps will not block, returns . on the first sleep (then continues on in the "background" after the sleep/block ends), otherwise operates normally.
		OR
		INVOKE_ASYNC(<CALLBACK args>) to immediately create and call InvokeAsync

	PROC TYPEPATH SHORTCUTS (these operate on paths, not types, so to these shortcuts, datum is NOT a parent of atom, etc...)

		global proc while in another global proc:
			.procname
			Example:
				CALLBACK(GLOBAL_PROC, .some_proc_here)

		proc defined on current(src) object (when in a /proc/ and not an override) OR overridden at src or any of it's parents:
			.procname
			Example:
				CALLBACK(src, .some_proc_here)


		when the above doesn't apply:
			.proc/procname
			Example:
				CALLBACK(src, .proc/some_proc_here)

		proc defined on a parent of a some type:
			/some/type/.proc/some_proc_here



		Other wise you will have to do the full typepath of the proc (/type/of/thing/proc/procname)

*/

/datum/callback
	var/datum/object = GLOBAL_PROC
	var/delegate
	var/list/arguments
	var/datum/weakref/user

/datum/callback/New(thingtocall, proctocall, ...)
	if (thingtocall)
		object = thingtocall
	delegate = proctocall
	if (length(args) > 2)
		arguments = args.Copy(3)
	if(usr)
		user = WEAKREF(usr)

/world/proc/ImmediateInvokeAsync(thingtocall, proctocall, ...)
	set waitfor = FALSE

	// AUDIT-DISPATCH: INVOKE_ASYNC macro expands to a call here. Bug B button
	// activation goes through this path. Scoped to relevant target types to
	// keep log volume manageable.
	var/should_audit = (thingtocall && thingtocall != GLOBAL_PROC && (istype(thingtocall, /obj/item/grenade) || istype(thingtocall, /obj/machinery/door/airlock) || istype(thingtocall, /obj/item/assembly/control) || istype(thingtocall, /obj/machinery/button)))

	if (!thingtocall)
		return

	var/list/calling_arguments = length(args) > 2 ? args.Copy(3) : null

	if (thingtocall == GLOBAL_PROC)
		call(proctocall)(arglist(calling_arguments))
	else
		if (should_audit)
			var/datum/typed = thingtocall
			log_game("AUDIT ImmediateInvokeAsync: about to call(thing=[thingtocall]([typed.type]), proc=[proctocall])")
		call(thingtocall, proctocall)(arglist(calling_arguments))
		if (should_audit)
			var/datum/typed_after = thingtocall
			log_game("AUDIT ImmediateInvokeAsync: call returned for thing=[thingtocall]([typed_after.type]) proc=[proctocall]")

/datum/callback/proc/Invoke(...)
	// AUDIT-DISPATCH: synchronous version. PushUsr (used by both Invoke and
	// InvokeAsync !usr branches) calls Invoke, so the audit needs to live here
	// to capture timer-fired chem_grenade/airlock callbacks that route through
	// the user-weakref path.
	var/datum/audit_obj = object
	var/should_audit = (object && object != GLOBAL_PROC && (istype(object, /obj/item/grenade) || istype(object, /obj/machinery/door/airlock) || istype(object, /obj/item/assembly/control) || istype(object, /obj/machinery/button)))
	if (should_audit)
		log_game("AUDIT callback/Invoke ENTRY: object=[object]([audit_obj.type]) delegate=[delegate] usr=[usr]")
	if(!usr)
		var/datum/weakref/W = user
		if(W)
			var/mob/M = W.resolve()
			if(M)
				if (should_audit)
					log_game("AUDIT callback/Invoke: !usr branch resolved user=[M] - calling PushUsr (recurses to Invoke)")
				if (length(args))
					return world.PushUsr(arglist(list(M, src) + args))
				return world.PushUsr(M, src)

	if (!object)
		if (should_audit)
			log_game("AUDIT callback/Invoke: !object early-return")
		return

	var/list/calling_arguments = arguments
	if (length(args))
		if (length(arguments))
			calling_arguments = calling_arguments + args //not += so that it creates a new list so the arguments list stays clean
		else
			calling_arguments = args
	if(datum_flags & DF_VAR_EDITED)
		if (should_audit)
			log_game("AUDIT callback/Invoke: DF_VAR_EDITED branch - WrapAdminProcCall")
		return WrapAdminProcCall(object, delegate, calling_arguments)
	if (object == GLOBAL_PROC)
		if (should_audit)
			log_game("AUDIT callback/Invoke: GLOBAL_PROC branch")
		return call(delegate)(arglist(calling_arguments))
	if (should_audit)
		log_game("AUDIT callback/Invoke: about to call(object=[object]([audit_obj.type]), delegate=[delegate])")
	. = call(object, delegate)(arglist(calling_arguments))
	if (should_audit)
		log_game("AUDIT callback/Invoke: call returned for object=[object]([audit_obj.type]) delegate=[delegate] result=[isnull(.) ? "null" : "[.]"]")
	return .

//copy and pasted because fuck proc overhead
/datum/callback/proc/InvokeAsync(...)
	set waitfor = FALSE

	// AUDIT-DISPATCH: async version. SSTimer fires callbacks via this path.
	// Bug A and Bug F both come through here.
	var/datum/audit_obj_async = object
	var/should_audit_async = (object && object != GLOBAL_PROC && (istype(object, /obj/item/grenade) || istype(object, /obj/machinery/door/airlock) || istype(object, /obj/item/assembly/control) || istype(object, /obj/machinery/button)))
	if (should_audit_async)
		log_game("AUDIT callback/InvokeAsync ENTRY: object=[object]([audit_obj_async.type]) delegate=[delegate] usr=[usr]")

	if(!usr)
		var/datum/weakref/W = user
		if(W)
			var/mob/M = W.resolve()
			if(M)
				if (should_audit_async)
					log_game("AUDIT callback/InvokeAsync: !usr branch resolved user=[M] - calling PushUsr (routes to Invoke)")
				if (length(args))
					return world.PushUsr(arglist(list(M, src) + args))
				return world.PushUsr(M, src)

	if (!object)
		if (should_audit_async)
			log_game("AUDIT callback/InvokeAsync: !object early-return")
		return

	var/list/calling_arguments = arguments
	if (length(args))
		if (length(arguments))
			calling_arguments = calling_arguments + args //not += so that it creates a new list so the arguments list stays clean
		else
			calling_arguments = args
	if(datum_flags & DF_VAR_EDITED)
		if (should_audit_async)
			log_game("AUDIT callback/InvokeAsync: DF_VAR_EDITED branch - WrapAdminProcCall")
		return WrapAdminProcCall(object, delegate, calling_arguments)
	if (object == GLOBAL_PROC)
		if (should_audit_async)
			log_game("AUDIT callback/InvokeAsync: GLOBAL_PROC branch")
		return call(delegate)(arglist(calling_arguments))
	if (should_audit_async)
		log_game("AUDIT callback/InvokeAsync: about to call(object=[object]([audit_obj_async.type]), delegate=[delegate])")
	. = call(object, delegate)(arglist(calling_arguments))
	if (should_audit_async)
		log_game("AUDIT callback/InvokeAsync: call returned for object=[object]([audit_obj_async.type]) delegate=[delegate] result=[isnull(.) ? "null" : "[.]"]")
	return .


/datum/callback_select
	var/list/finished
	var/pendingcount
	var/total

/datum/callback_select/New(count, savereturns)
	total = count
	if (savereturns)
		finished = new(count)


/datum/callback_select/proc/invoke_callback(index, datum/callback/callback, list/callback_args, savereturn = TRUE)
	set waitfor = FALSE
	if (!callback || !istype(callback))
		//This check only exists because the alternative is callback_select would block forever if given invalid data
		CRASH("invalid callback passed to invoke_callback")
	if (!length(callback_args))
		callback_args = list()
	pendingcount++
	var/rtn = callback.Invoke(arglist(callback_args))
	pendingcount--
	if (savereturn)
		finished[index] = rtn




//runs a list of callbacks asynchronously, returning once all of them return.
//callbacks can be repeated.
//callbacks-args is an optional list of argument lists, in the same order as the callbacks,
//	the inner lists will be sent to the callbacks when invoked() as additional args.
//can optionly save and return a list of return values, in the same order as the original list of callbacks
//resolution is the number of byond ticks between checks.
/proc/callback_select(list/callbacks, list/callback_args, savereturns = TRUE, resolution = 1)
	if (!callbacks)
		return
	var/count = length(callbacks)
	if (!count)
		return
	if (!callback_args)
		callback_args = list()

	callback_args.len = count

	var/datum/callback_select/CS = new(count, savereturns)
	for (var/i in 1 to count)
		CS.invoke_callback(i, callbacks[i], callback_args[i], savereturns)

	while(CS.pendingcount)
		sleep(resolution*world.tick_lag)
	return CS.finished

/proc/___callbacknew(typepath, arguments)
	new typepath(arglist(arguments))
