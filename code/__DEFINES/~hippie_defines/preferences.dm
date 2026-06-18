// SOUND_TTS (1<<0) was the HippieStation TTS opt-in toggle. The new TTS subsystem
// plays for everyone in range; Phase 2 will add per-player off/blips/full prefs via
// a different schema. Bit 0 is reserved so existing savefile values continue to
// decode predictably; do not reuse it for an unrelated toggle.
#define SOUND_FOOTSTEPS			(1<<1)
#define SOUND_VOX				(1<<2)

#define HIPPIE_TOGGLES_DEFAULT	(SOUND_VOX)
