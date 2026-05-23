// TTS text and filter sanitization helpers. Ported from
// tgstation/code/__HELPERS/tts.dm. Used by SStts.queue_tts_message before any
// text leaves the game to the Python TTS gateway.

/// Strip everything except alphanumerics and a small set of punctuation. Anything
/// else becomes a space. This defeats shell-injection through the text body and
/// keeps the audio engine from choking on control characters.
///
/// /mob/living/say() pipes input through sanitize() before TTS sees it, which
/// html-encodes apostrophes (`'` -> `&#39;`), less-than (`<` -> `&lt;`), and so
/// on. Piper reads those literally ("thirty nine" for `&#39;`), so html_decode
/// first to recover the user's actual characters before the regex strip.
/proc/tts_speech_filter(text)
	var/static/regex/bad_chars_regex = regex("\[^a-zA-Z0-9 ,?.!'&-]", "g")
	return bad_chars_regex.Replace(html_decode(text), " ")

/// Substitute the templating tokens used by the gateway's ffmpeg filter strings,
/// then URL-encode for safe transit in a query parameter.
/proc/tts_filter_encode(text, speaker, pitch, blips = FALSE)
	text = replacetext(text, "%PITCH%", SStts.pitch_enabled ? pitch : 0)
	text = replacetext(text, "%FEMALE%", !!findtext(speaker, "Woman"))
	text = replacetext(text, "%BLIPS%", blips)
	return url_encode(text)
