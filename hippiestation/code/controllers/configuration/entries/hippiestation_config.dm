/datum/config_entry/flag/mentors_mobname_only

/datum/config_entry/string/internet_address_to_use

/datum/config_entry/string/token_generator

/datum/config_entry/string/token_consumer

/datum/config_entry/flag/mentor_legacy_system	//Defines whether the server uses the legacy mentor system with mentors.txt or the SQL system
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/flag/allow_vote_shuttlecall	// allow shuttle to be called via vote

/datum/config_entry/flag/enable_demo
	protection = CONFIG_ENTRY_LOCKED

// The HippieStation-era TTS_API / ENABLE_TTS / TTS_COMMAND / TTS_VOICE_MALE /
// TTS_VOICE_FEMALE config entries lived here. The new TTS subsystem uses its own
// keys (TTS_HTTP_URL, TTS_HTTP_TOKEN, TTS_MAX_CONCURRENT_REQUESTS,
// TTS_HTTP_TIMEOUT_SECONDS, TTS_NO_WHISPER) defined in
// code/controllers/configuration/entries/tts_config.dm.

/datum/config_entry/string/ipstack_api_key
	protection = CONFIG_ENTRY_HIDDEN | CONFIG_ENTRY_LOCKED
