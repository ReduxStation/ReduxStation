/datum/hud/human/New(mob/living/carbon/human/owner, ui_style = 'icons/mob/screen_midnight.dmi')
	..()
	staminas = new()
	infodisplay += staminas
	combo_object = new()
	infodisplay += combo_object
	// HippieStation's TTS HUD indicator (tts_ready / tts_cooldown icon) was added here.
	// The new TTS subsystem has no HUD element; cooldown is internal to SStts.