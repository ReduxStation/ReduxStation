// The HippieStation "Hear/Silence Text-to-Speech" toggle (SOUND_TTS bit) lived
// here. Phase 1 of the new TTS plays for everyone in range by default; per-player
// off/blips/full toggle lands in Phase 2 alongside per-character voice prefs.

TOGGLE_CHECKBOX(/datum/verbs/menu/Settings/Sound, toggle_footsteps)()
	set name = "Hear/Silence Footsteps"
	set category = "Preferences"
	set desc = "Hear In-game Footsteps"
	usr.client.prefs.hippie_toggles ^= SOUND_FOOTSTEPS
	usr.client.prefs.save_preferences()
	if(usr.client.prefs.hippie_toggles & SOUND_FOOTSTEPS)
		to_chat(usr, "You will now hear people's footsteps.")
	else
		to_chat(usr, "You will no longer hear people's footsteps.")
	SSblackbox.record_feedback("nested tally", "preferences_verb", 1, list("Toggle Footsteps", "[usr.client.prefs.toggles & SOUND_FOOTSTEPS ? "Enabled" : "Disabled"]")) //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
/datum/verbs/menu/Settings/Sound/toggle_footsteps/Get_checked(client/C)
	return C.prefs.hippie_toggles & SOUND_FOOTSTEPS

TOGGLE_CHECKBOX(/datum/verbs/menu/Settings/Sound, toggle_vox)()
	set name = "Hear/Silence AI VOX"
	set category = "Preferences"
	set desc = "Hear AI VOX"
	usr.client.prefs.hippie_toggles ^= SOUND_VOX
	usr.client.prefs.save_preferences()
	if(usr.client.prefs.hippie_toggles & SOUND_VOX)
		to_chat(usr, "You will now hear AI VOX.")
	else
		to_chat(usr, "You will no longer hear AI VOX.")
	SSblackbox.record_feedback("nested tally", "preferences_verb", 1, list("Toggle AI VOX", "[usr.client.prefs.hippie_toggles & SOUND_VOX ? "Enabled" : "Disabled"]")) //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/verbs/menu/Settings/Sound/toggle_vox/Get_checked(client/C)
	return C.prefs.hippie_toggles & SOUND_VOX
