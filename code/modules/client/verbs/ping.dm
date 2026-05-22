/client/verb/update_ping(time as num)
	set instant = TRUE
	set name = ".update_ping"
	var/ping = pingfromtime(time)
	lastping = ping
	if (!avgping)
		avgping = ping
	else
		avgping = MC_AVERAGE_SLOW(avgping, ping)

/client/proc/pingfromtime(time)
	return ((world.time+world.tick_lag*TICK_USAGE_REAL/100)-time)*100

/client/verb/display_ping(time as num)
	set instant = TRUE
	set name = ".display_ping"
	to_chat(src, "<span class='notice'>Round trip ping took [round(pingfromtime(time),1)]ms</span>")

/client/verb/ping()
	set name = "Ping"
	set category = "OOC"
	// See server_maint.dm:72 for why num2text(..., 20) is required here.
	// BYOND's default `[N]` interpolation flips to scientific notation past
	// ~1e6 (world.time after ~28 hours), which the verb's `time as num` arg
	// parser rejects, so the command line echoes to chat instead of firing.
	winset(src, null, "command=.display_ping+[num2text(world.time + world.tick_lag * TICK_USAGE_REAL / 100, 20)]")