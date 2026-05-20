// TTS subsystem constants. Ported from tgstation/code/__DEFINES/tts.dm.

/// TTS preference is disabled entirely, no sound will be played.
#define TTS_SOUND_OFF "Disabled"
/// TTS preference is enabled, full text-to-speech.
#define TTS_SOUND_ENABLED "Enabled"
/// TTS preference is set to play character-by-character blips instead of speech.
#define TTS_SOUND_BLIPS "Blips Only"

/// TTS filter to activate start/stop radio clicks on speech.
#define TTS_FILTER_RADIO "radio"
/// TTS filter to activate a silicon effect on speech.
#define TTS_FILTER_SILICON "silicon"

/// Default audible range in tiles for TTS speech playback. Matches our existing world.view ambit
/// for say chat, so any client that hears the chat text also hears the audio.
#define SOUND_RANGE 7
