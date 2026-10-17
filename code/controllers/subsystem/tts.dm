/* Text-to-speech subsystem.
 *
 * Ported from tgstation/code/controllers/subsystem/tts.dm with the following adaptations
 * for our older HippieStation 2020 base:
 *   - Uses our existing /datum/Heap (capital H) instead of tg's /datum/heap.
 *   - Uses `flags |= SS_NO_FIRE` instead of tg's `ss_flags |= SS_NO_FIRE`.
 *   - Substitutes SSsounds.random_available_channel() with our open_sound_channel() builtin.
 *   - Calls our older /mob/proc/playsound_local with positional args instead of the newer
 *     keyword sig (no falloff_exponent / max_distance / use_reverb yet). Our playsound_local
 *     already does distance-based volume falloff and pressure muffling, so spatial audio
 *     works in Phase 1 without porting the new sig.
 *   - Stubs out read_preference() calls. Phase 1 hears at default volume for everyone;
 *     Phase 2 adds player-controlled prefs (off/blips/full, volume slider).
 *   - Drops the TTS_VOICE_BLACKLIST config support (would need a /datum/config_entry/str_list
 *     type we do not have yet). Easy to add later.
 *
 * Communicates with the Python Piper gateway via rust-g HTTP (Phase 0 added http feature
 * to our rust-g build). Output audio files are written directly to tmp/tts/ via rust-g's
 * output_file mechanism and streamed to clients with BYOND's normal /sound() asset path.
 */

SUBSYSTEM_DEF(tts)
	name = "Text To Speech"
	wait = 0.05 SECONDS
	priority = FIRE_PRIORITY_TTS
	init_order = INIT_ORDER_TTS
	runlevels = RUNLEVEL_LOBBY | RUNLEVEL_SETUP | RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	/// Queued HTTP requests that have yet to be sent.
	var/datum/Heap/queued_http_messages

	/// An associative list of speakers mapped to a list of their own /datum/tts_request entries.
	var/list/queued_tts_messages = list()

	/// TTS audio files that are being processed on when to be played.
	var/list/current_processing_tts_messages = list()

	/// HTTP requests currently in progress but not being processed yet.
	var/list/in_process_http_messages = list()

	/// HTTP requests being polled for completion this fire.
	var/list/current_processing_http_messages = list()

	/// Voice names the gateway reports as available. Populated at Initialize.
	var/list/available_speakers = list()

	/// TRUE once we have successfully connected to the gateway.
	var/tts_enabled = FALSE
	/// TRUE if the gateway reports it supports pitch shifting.
	var/pitch_enabled = FALSE

	/// Drop requests older than this. Hard cap to keep the queue from growing under outage.
	var/message_timeout = 7 SECONDS

	/// The max concurrent HTTP requests in flight at once. Capped by config too.
	var/max_concurrent_requests = 4

	/// Rolling average of TTS round-trip time (centiseconds).
	var/average_tts_messages_time = 0

/datum/controller/subsystem/tts/vv_edit_var(var_name, var_value)
	if(NAMEOF(src, tts_enabled) == var_name)
		return FALSE
	return ..()

/datum/controller/subsystem/tts/stat_entry(msg)
	msg = "\n  Active:[length(in_process_http_messages)]|Standby:[queued_http_messages ? length(queued_http_messages.L) : 0]|Avg:[average_tts_messages_time]"
	return ..()

/proc/cmp_word_length_asc(datum/tts_request/a, datum/tts_request/b)
	return length(b.message) - length(a.message)

/// Pulls the live voice list from the gateway and verifies pitch support. Blocking.
/// Returns TRUE on success.
/datum/controller/subsystem/tts/proc/establish_connection_to_tts()
	var/datum/http_request/request = new()
	var/list/headers = list()
	headers["Authorization"] = CONFIG_GET(string/tts_http_token)
	request.prepare(RUSTG_HTTP_METHOD_GET, "[CONFIG_GET(string/tts_http_url)]/tts-voices", "", headers, timeout_seconds = CONFIG_GET(number/tts_http_timeout_seconds))
	request.begin_async()
	UNTIL(request.is_complete())
	var/datum/http_response/response = request.into_response()
	if(response.errored || response.status_code != 200)
		stack_trace(response.error || "TTS /tts-voices returned [response.status_code]")
		return FALSE
	available_speakers = json_decode(response.body)
	tts_enabled = TRUE

	var/datum/http_request/request_pitch = new()
	var/list/headers_pitch = list()
	headers_pitch["Authorization"] = CONFIG_GET(string/tts_http_token)
	request_pitch.prepare(RUSTG_HTTP_METHOD_GET, "[CONFIG_GET(string/tts_http_url)]/pitch-available", "", headers_pitch, timeout_seconds = CONFIG_GET(number/tts_http_timeout_seconds))
	request_pitch.begin_async()
	UNTIL(request_pitch.is_complete())
	pitch_enabled = TRUE
	var/datum/http_response/response_pitch = request_pitch.into_response()
	if(response_pitch.errored || response_pitch.status_code != 200)
		pitch_enabled = FALSE

	rustg_file_write(json_encode(available_speakers), "data/cached_tts_voices.json")
	// rustg HTTP can't create the destination directory itself, so we touch a file
	// in tmp/tts/ to make sure the dir exists before the first audio download.
	rustg_file_write("init", "tmp/tts/init.txt")
	return TRUE

/datum/controller/subsystem/tts/Initialize()
	if(!CONFIG_GET(string/tts_http_url))
		// No backend configured. Mark ourselves SS_NO_FIRE so we never wake,
		// and chain to the parent Initialize so .initialized = TRUE (the
		// subsystem_init unit test asserts on that).
		flags |= SS_NO_FIRE
		return ..()

	queued_http_messages = new /datum/Heap(GLOBAL_PROC_REF(cmp_word_length_asc))
	max_concurrent_requests = CONFIG_GET(number/tts_max_concurrent_requests)
	if(!establish_connection_to_tts())
		log_world("TTS subsystem failed to connect to gateway at [CONFIG_GET(string/tts_http_url)], disabling for the round.")
		flags |= SS_NO_FIRE
		return ..()
	log_world("TTS subsystem connected, [length(available_speakers)] voices available, pitch [pitch_enabled ? "ON" : "OFF"].")
	return ..()

/datum/controller/subsystem/tts/proc/play_tts(target, list/listeners, sound/audio, sound/audio_blips, datum/language/language, range = 7, volume_offset = 0)
	var/turf/turf_source = get_turf(target)
	if(!turf_source)
		log_world("TTS play_tts: target [target] has no turf, bailing.")
		return

	log_world("TTS play_tts: target=[target] file=[audio ? audio.file : "null"] listeners=[length(listeners)] range=[range]")
	var/channel = open_sound_channel()
	var/list/combined = listeners | SSmobs.dead_players_by_zlevel[turf_source.z]
	log_world("TTS play_tts: combined listener count after dead-player union=[length(combined)]")
	for(var/atom/movable/hearer in combined)
		var/mob/listening_mob = hearer.get_listening_mob()
		if(isnull(listening_mob))
			log_world("TTS play_tts: skipped hearer [hearer] ([hearer.type]) — get_listening_mob returned null")
			continue
		if(QDELETED(listening_mob))
			stack_trace("TTS tried to play a sound to a deleted mob.")
			continue
		// Phase 1: every client hears at default volume in TTS_SOUND_ENABLED mode. Phase 2 adds prefs.
		var/volume_modifier = 1.0
		var/sound_volume = ((hearer == target) ? 60 : 85) + volume_offset
		sound_volume = sound_volume * volume_modifier
		var/datum/language_holder/holder = listening_mob.get_language_holder()
		var/audio_to_use = audio
		if(language && holder && !holder.has_language(language))
			log_world("TTS play_tts: [listening_mob] skipped — does not know language [language]")
			continue
		var/dist = get_dist(hearer, turf_source)
		if(dist <= range)
			log_world("TTS play_tts: calling playsound_local on [listening_mob] vol=[sound_volume] dist=[dist] channel=[channel] client=[listening_mob.client ? "yes" : "NO"]")
			// Our playsound_local: (turf_source, soundin, vol, vary, frequency, falloff, channel, pressure_affected, sound/S)
			listening_mob.playsound_local(
				turf_source,
				null,
				sound_volume,
				FALSE,
				null,
				null,
				channel,
				TRUE,
				audio_to_use
			)
		else
			log_world("TTS play_tts: [listening_mob] out of range dist=[dist] range=[range]")

// Need to wait for all HTTP requests to complete here because of a rustg crash bug
// that causes crashes when DD restarts while HTTP requests are ongoing.
/datum/controller/subsystem/tts/Shutdown()
	tts_enabled = FALSE
	for(var/datum/tts_request/data in in_process_http_messages)
		var/datum/http_request/request = data.request
		var/datum/http_request/request_blips = data.request_blips
		UNTIL((!request || request.is_complete()) && (!request_blips || request_blips.is_complete()))

#define SHIFT_DATA_ARRAY(tts_message_queue, target, data) \
	popleft(##data); \
	if(length(##data) == 0) { \
		##tts_message_queue -= ##target; \
	};

#define TTS_ARBRITRARY_DELAY "arbritrary delay"

/datum/controller/subsystem/tts/fire(resumed)
	if(!tts_enabled)
		flags |= SS_NO_FIRE
		return

	if(!resumed)
		while(length(in_process_http_messages) < max_concurrent_requests && length(queued_http_messages.L) > 0)
			var/datum/tts_request/entry = queued_http_messages.Pop()
			var/timeout = entry.start_time + message_timeout
			if(timeout < world.time)
				entry.timed_out = TRUE
				continue
			entry.start_requests()
			in_process_http_messages += entry
		current_processing_http_messages = in_process_http_messages.Copy()
		current_processing_tts_messages = queued_tts_messages.Copy()

	var/list/processing_messages = current_processing_http_messages
	while(processing_messages.len)
		var/datum/tts_request/current_request = processing_messages[processing_messages.len]
		processing_messages.len--
		if(!current_request.requests_completed())
			continue

		var/datum/http_response/response = current_request.get_primary_response()
		in_process_http_messages -= current_request
		average_tts_messages_time = MC_AVERAGE(average_tts_messages_time, world.time - current_request.start_time)
		var/identifier = current_request.identifier
		if(current_request.requests_errored())
			current_request.timed_out = TRUE
			var/datum/http_response/normal_response = current_request.request ? current_request.request.into_response() : null
			var/datum/http_response/blips_response = current_request.request_blips ? current_request.request_blips.into_response() : null
			log_tts("TTS HTTP request errored | Normal: [normal_response ? normal_response.error : "n/a"] | Blips: [blips_response ? blips_response.error : "n/a"]", list(
				"normal" = normal_response,
				"blips" = blips_response
			))
			continue
		current_request.audio_length = text2num(response.headers ? response.headers["audio-length"] : 0) * 10
		if(!current_request.audio_length)
			current_request.audio_length = 0
		current_request.audio_file = "tmp/tts/[identifier].ogg"
		if(current_request.request_blips)
			current_request.audio_file_blips = "tmp/tts/[identifier]_blips.ogg"
		current_request.request = null
		current_request.request_blips = null
		if(MC_TICK_CHECK)
			return

	var/list/processing_tts_messages = current_processing_tts_messages
	while(processing_tts_messages.len)
		if(MC_TICK_CHECK)
			return

		var/datum/tts_target = processing_tts_messages[processing_tts_messages.len]
		var/list/data = processing_tts_messages[tts_target]
		processing_tts_messages.len--
		if(QDELETED(tts_target))
			queued_tts_messages -= tts_target
			continue

		var/datum/tts_request/current_target = data[1]
		var/timeout_start = current_target.when_to_play
		if(!timeout_start)
			timeout_start = current_target.start_time

		var/timeout = timeout_start + message_timeout
		if(timeout < world.time || current_target.timed_out)
			SHIFT_DATA_ARRAY(queued_tts_messages, tts_target, data)
			continue

		if(current_target.audio_file)
			if(current_target.audio_file == TTS_ARBRITRARY_DELAY)
				if(current_target.when_to_play < world.time)
					SHIFT_DATA_ARRAY(queued_tts_messages, tts_target, data)
				continue
			var/sound/audio_file
			var/sound/audio_file_blips
			if(current_target.local)
				audio_file = new(current_target.audio_file)
				SEND_SOUND(current_target.target, audio_file)
				SHIFT_DATA_ARRAY(queued_tts_messages, tts_target, data)
			else if(current_target.when_to_play < world.time)
				audio_file = new(current_target.audio_file)
				if(current_target.audio_file_blips)
					audio_file_blips = new(current_target.audio_file_blips)
				log_world("TTS fire: dispatching [current_target.audio_file] target=[tts_target] listeners=[length(current_target.listeners)] language=[current_target.language]")
				play_tts(tts_target, current_target.listeners, audio_file, audio_file_blips, current_target.language, current_target.message_range, current_target.volume_offset)
				if(length(data) != 1)
					var/datum/tts_request/next_target = data[2]
					next_target.when_to_play = world.time + current_target.audio_length
				else
					var/datum/tts_request/arbritrary_delay = new()
					arbritrary_delay.when_to_play = world.time + current_target.audio_length
					arbritrary_delay.audio_file = TTS_ARBRITRARY_DELAY
					queued_tts_messages[tts_target] += arbritrary_delay
				SHIFT_DATA_ARRAY(queued_tts_messages, tts_target, data)


#undef TTS_ARBRITRARY_DELAY

/datum/controller/subsystem/tts/proc/queue_tts_message(datum/target, message, datum/language/language, speaker, filter, list/listeners, local = FALSE, message_range = 7, volume_offset = 0, pitch = 0, special_filters = "")
	if(!tts_enabled)
		return

	// TGS updates may clear tmp/, ensure the dir exists for the next batch of downloads.
	if(!fexists("tmp/tts/init.txt"))
		rustg_file_write("init", "tmp/tts/init.txt")

	var/static/regex/contains_alphanumeric = regex("\[a-zA-Z0-9]")
	if(contains_alphanumeric.Find(message) == 0)
		return

	var/shell_scrubbed_input = tts_speech_filter(message)
	shell_scrubbed_input = copytext(shell_scrubbed_input, 1, 300)
	// Self-heal stale speaker labels (e.g. after a gateway engine swap mid-round).
	// If the mob's voice no longer exists in the catalog, re-roll on the mob and
	// keep going. Without this, queue_tts_message silently drops every message
	// from every mob that initialized under the old catalog.
	if(!(speaker in available_speakers))
		if(ismob(target))
			var/mob/M = target
			var/new_voice = random_tts_voice(M.gender)
			if(new_voice)
				M.voice = new_voice
				speaker = new_voice
		if(!(speaker in available_speakers))
			return
	var/identifier = "[sha1(speaker + filter + num2text(pitch) + special_filters + shell_scrubbed_input)].[world.time]"

	var/list/headers = list()
	headers["Content-Type"] = "application/json"
	headers["Authorization"] = CONFIG_GET(string/tts_http_token)
	var/datum/http_request/request = new()
	var/file_name = "tmp/tts/[identifier].ogg"
	request.prepare(RUSTG_HTTP_METHOD_GET, "[CONFIG_GET(string/tts_http_url)]/tts?voice=[url_encode(speaker)]&identifier=[identifier]&filter=[tts_filter_encode(filter, speaker, pitch)]&pitch=[pitch]&special_filters=[url_encode(special_filters)]", json_encode(list("text" = shell_scrubbed_input)), headers, file_name, timeout_seconds = CONFIG_GET(number/tts_http_timeout_seconds))
	// Phase 1 never reads the blips response (no per-client TTS_SOUND_BLIPS pref yet)
	// so we do not fire the second HTTP request at all. Saves a full round-trip plus a
	// disk write per message. Phase 2 will re-introduce conditional blips when a client
	// in the listener set wants TTS_SOUND_BLIPS, by constructing request_blips here.
	var/datum/http_request/request_blips = null
	var/datum/tts_request/current_request = new /datum/tts_request(identifier, request, request_blips, shell_scrubbed_input, target, local, language, message_range, volume_offset, listeners, pitch)
	var/list/player_queued_tts_messages = queued_tts_messages[target]
	if(!player_queued_tts_messages)
		player_queued_tts_messages = list()
		queued_tts_messages[target] = player_queued_tts_messages
	player_queued_tts_messages += current_request
	if(length(in_process_http_messages) < max_concurrent_requests)
		current_request.start_requests()
		in_process_http_messages += current_request
	else
		queued_http_messages.Insert(current_request)

/// Returns a random TTS voice name, optionally filtered by gender.
/datum/controller/subsystem/tts/proc/random_tts_voice(gender = NEUTER)
	if(!tts_enabled || !length(available_speakers))
		return null

	var/sanity = 0
	while(sanity < 10)
		var/voice = pick(available_speakers)
		if(gender != MALE && gender != FEMALE)
			return voice
		if(gender == MALE && findtext(voice, "Man"))
			return voice
		if(gender == FEMALE && findtext(voice, "Woman"))
			return voice
		sanity += 1

	return pick(available_speakers) // failsafe

/// A struct containing information on an individual TTS request.
/datum/tts_request
	/// The mob to play this TTS message on
	var/mob/target
	/// The hearers who will receive this audio. Ignored when local = TRUE.
	var/list/listeners
	/// HTTP request for the full-speech audio.
	var/datum/http_request/request
	/// HTTP request for the blips variant.
	var/datum/http_request/request_blips
	/// Language to limit playback to.
	var/datum/language/language
	/// The scrubbed message text being read.
	var/message
	/// Identifier hash used for the audio filename and gateway dedup.
	var/identifier
	/// Volume offset applied to the playback volume.
	var/volume_offset = 0
	/// If TRUE, send only to the target (used for previews).
	var/local = FALSE
	/// Tile range for the play_tts loop.
	var/message_range = 7
	/// world.time at which this request was created.
	var/start_time

	/// Audio file path once the HTTP request completes.
	var/audio_file
	/// Audio file path for the blips variant once the HTTP request completes.
	var/audio_file_blips
	/// Audio length in centiseconds (parsed from the gateway response header).
	var/audio_length
	/// Earliest world.time at which the audio is allowed to play.
	var/when_to_play = 0
	/// TRUE if the request hit its timeout.
	var/timed_out = FALSE
	/// TRUE if the player wants blips-only mode (Phase 2 prefs hook).
	var/use_blips = FALSE
	/// Pitch shift in semitones (-12 to +12).
	var/pitch = 0


/datum/tts_request/New(identifier, datum/http_request/request, datum/http_request/request_blips, message, target, local, datum/language/language, message_range, volume_offset, list/listeners, pitch)
	. = ..()
	src.identifier = identifier
	src.request = request
	src.request_blips = request_blips
	src.message = message
	src.language = language
	src.target = target
	src.local = local
	src.message_range = message_range
	src.volume_offset = volume_offset
	src.listeners = listeners
	src.pitch = pitch
	start_time = world.time

/datum/tts_request/proc/start_requests()
	// Phase 1: no per-client blips preference. Phase 2 reads from prefs and sets
	// use_blips per-message before calling start_requests; queue_tts_message will
	// create request_blips when at least one listener wants blips.
	if(local)
		if(use_blips && request_blips)
			request_blips.begin_async()
		else
			request.begin_async()
		return
	request.begin_async()
	if(request_blips)
		request_blips.begin_async()

/datum/tts_request/proc/get_primary_request()
	if(local && use_blips && request_blips)
		return request_blips
	return request

/datum/tts_request/proc/get_primary_response()
	if(local && use_blips && request_blips)
		return request_blips.into_response()
	return request.into_response()

/datum/tts_request/proc/requests_errored()
	var/datum/http_response/primary
	if(local)
		if(use_blips && request_blips)
			primary = request_blips.into_response()
		else
			primary = request.into_response()
		return primary.errored
	primary = request.into_response()
	if(primary.errored)
		return TRUE
	if(request_blips)
		var/datum/http_response/secondary = request_blips.into_response()
		if(secondary.errored)
			return TRUE
	return FALSE

/datum/tts_request/proc/requests_completed()
	if(local)
		if(use_blips && request_blips)
			return request_blips.is_complete()
		return request.is_complete()
	if(!request.is_complete())
		return FALSE
	if(request_blips && !request_blips.is_complete())
		return FALSE
	return TRUE

#undef SHIFT_DATA_ARRAY
