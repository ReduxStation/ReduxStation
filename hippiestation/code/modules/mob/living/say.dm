/mob/living/carbon/human/treat_message(message)
	if(lisp)
		message = lisp(message, lisp)
	return ..()

/mob/living/can_speak_vocal(message)
	if(pulledby && pulledby.grab_state == GRAB_KILL)
		return FALSE

	return ..()

/mob/living/say(message, bubble_type,var/list/spans = list(), sanitize = TRUE, datum/language/language = null, ignore_spam = FALSE, forced = null)
	// If we're in soft crit and tried to talk, automatically make us whisper
	if (length(message) > 2)
		var/first_char = copytext(message, 1, 2)

		if (first_char != "*" && stat == SOFT_CRIT && get_message_mode(message) != MODE_WHISPER)
			message = "#" + message

	. = ..()

	if (!.)
		return
	if(findtext(message, "rouge"))
		var/mob/living/carbon/human/H = src
		to_chat(src, "<span class='warning'><b>You feel like a fucking idiot.</b></span>")
		playsound_local(src, 'hippiestation/sound/effects/whistlefail.ogg', 50, 0)	//Rip
		if(istype(src, /mob/living/carbon/human/))
			var/trauma_type = pickweight(list(BRAIN_TRAUMA_MILD = 100,BRAIN_TRAUMA_SEVERE = 30,BRAIN_TRAUMA_MAGIC = 10,BRAIN_TRAUMA_SPECIAL = 1))
			var/trauma_resistance
			switch(trauma_type)
				if(BRAIN_TRAUMA_MILD)
					trauma_resistance = TRAUMA_RESILIENCE_BASIC
				if(BRAIN_TRAUMA_SEVERE)
					trauma_resistance = TRAUMA_RESILIENCE_SURGERY
				if(BRAIN_TRAUMA_MAGIC)
					trauma_resistance = TRAUMA_RESILIENCE_MAGIC
				if(BRAIN_TRAUMA_SPECIAL)
					trauma_resistance = TRAUMA_RESILIENCE_BASIC
			H.adjustBrainLoss(20)
			H.gain_trauma_type(trauma_type, trauma_resistance)
	// The HippieStation-era say_tts proc (mimic1 shellout, /datum/tts queue, HUD
	// indicator) lived here. Phase 1 of the new TTS replaces it. The hook into
	// the new pipeline lives in code/modules/mob/living/say.dm and calls the
	// replacement say_tts proc in code/modules/mob/living/say_tts.dm, so this
	// override just falls through.
