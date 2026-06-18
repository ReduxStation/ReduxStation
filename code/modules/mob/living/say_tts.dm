/* TTS hook between our /mob/living say pipeline and SStts.queue_tts_message.
 *
 * Called by /mob/living/say after send_speech, on the same listener set the chat
 * message reached. Phase 1 keeps the policy minimal: humans (and any /mob/living
 * with a voice set) get TTS, everyone else is skipped. Filter system and mask
 * voice override land in Phase 3.
 */

/// Returns the mob that should receive a TTS sound() resource. Default null so
/// non-mob atoms in the listener set silently skip TTS playback.
/atom/movable/proc/get_listening_mob()
	return null

/mob/get_listening_mob()
	return src

/// Compose the speech metadata SStts expects and forward to queue_tts_message.
/// Returns early if TTS isn't enabled or this mob has no voice assigned.
/mob/living/proc/say_tts(message, datum/language/language, message_mode)
	if(!SStts || !SStts.tts_enabled)
		return
	if(!voice)
		return
	if(message_mode == MODE_WHISPER && CONFIG_GET(flag/tts_no_whisper))
		return

	// Gather the same hearers chat already used. The view radius matches send_speech
	// defaults so anyone who saw the text gets the audio.
	var/turf/T = get_turf(src)
	if(!T)
		return
	var/list/listeners = hearers(world.view, T)
	if(!length(listeners))
		return

	var/volume_offset = 0
	if(message_mode == MODE_WHISPER)
		volume_offset = -25

	SStts.queue_tts_message(
		src,
		message,
		language,
		voice,
		voice_filter,
		listeners,
		FALSE,
		world.view,
		volume_offset,
		pitch,
		tts_silicon_voice_effect ? TTS_FILTER_SILICON : ""
	)
