// TTS subsystem configuration. Mirrors the keys the upstream tgstation TTS subsystem
// reads, so docs and tooling can cross-reference cleanly. All keys live in
// hippiestation_config.txt at deploy time.

/// Base URL of the TTS gateway (e.g. http://tts:5500). When unset, SStts goes
/// SS_INIT_NO_NEED at boot and TTS is silently disabled for the round.
/datum/config_entry/string/tts_http_url
	protection = CONFIG_ENTRY_LOCKED

/// Bearer token sent on every TTS request. Must match the gateway's TTS_AUTHORIZATION_TOKEN.
/// CONFIG_ENTRY_HIDDEN keeps it out of `VV configuration` output.
/datum/config_entry/string/tts_http_token
	config_entry_value = "coolio"
	protection = CONFIG_ENTRY_LOCKED|CONFIG_ENTRY_HIDDEN

/// Maximum concurrent TTS HTTP requests in flight. Caps load on the gateway.
/datum/config_entry/number/tts_max_concurrent_requests
	config_entry_value = 4
	min_val = 1
	max_val = 32

/// Per-request HTTP timeout in seconds. 0 disables.
/datum/config_entry/number/tts_http_timeout_seconds
	config_entry_value = 30
	min_val = 0
	max_val = 600

/// When set, skip TTS for whispered lines.
/datum/config_entry/flag/tts_no_whisper
