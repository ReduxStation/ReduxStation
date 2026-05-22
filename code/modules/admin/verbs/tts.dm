// Admin verbs for the TTS subsystem. R_DEBUG gated.
//
// cmd_reestablish_tts: poke SStts to re-pull the voice list from the gateway.
//   Useful when the gateway container restarts mid-round and SStts went into
//   SS_NO_FIRE because Initialize was the only attempt.
//
// cmd_test_tts: ask the live SStts to read a string in your current voice for
//   yourself only. Useful to confirm audio reaches your client and to audition
//   a voice without forcing speech on others.

/client/proc/cmd_reestablish_tts()
	set name = "Reestablish TTS Connection"
	set category = "Debug"
	set desc = "Re-pull the voice list and pitch capability from the TTS gateway."

	if(!check_rights(R_DEBUG))
		return

	if(!SStts)
		to_chat(src, "<span class='warning'>SStts is not loaded.</span>")
		return

	if(!CONFIG_GET(string/tts_http_url))
		to_chat(src, "<span class='warning'>TTS_HTTP_URL is not set in config. The TTS subsystem will not initialize until you set one.</span>")
		return

	log_admin("[key_name(src)] is reestablishing the TTS connection.")
	message_admins("[key_name_admin(src)] is reestablishing the TTS connection.")

	var/result = SStts.establish_connection_to_tts()
	if(result)
		SStts.flags &= ~SS_NO_FIRE
		to_chat(src, "<span class='notice'>TTS connection reestablished. [length(SStts.available_speakers)] voices available, pitch [SStts.pitch_enabled ? "ON" : "OFF"].</span>")
	else
		to_chat(src, "<span class='warning'>TTS connection attempt failed. Check dd.log for the underlying error.</span>")


/client/proc/cmd_test_tts(text as text, voice as text|null)
	set name = "Test TTS"
	set category = "Debug"
	set desc = "Have your current mob speak a test phrase via TTS. Only you hear it."

	if(!check_rights(R_DEBUG))
		return

	if(!SStts || !SStts.tts_enabled)
		to_chat(src, "<span class='warning'>TTS is not enabled.</span>")
		return

	if(!mob)
		return

	if(!text)
		return

	var/effective_voice = voice
	if(!effective_voice)
		effective_voice = mob.voice
	if(!effective_voice)
		effective_voice = SStts.random_tts_voice()
	if(!effective_voice || !(effective_voice in SStts.available_speakers))
		to_chat(src, "<span class='warning'>No usable voice (asked for '[effective_voice]'). The catalog has [length(SStts.available_speakers)] entries.</span>")
		return

	SStts.queue_tts_message(
		mob,
		text,
		null,                       // language
		effective_voice,
		"",                         // filter
		list(mob),                  // listeners
		TRUE,                       // local (play only to the target)
		world.view,                 // message_range (ignored when local)
		0,                          // volume_offset
		mob.pitch,
		""                          // special_filters
	)
	to_chat(src, "<span class='notice'>Queued TTS line '[text]' on voice '[effective_voice]'.</span>")
