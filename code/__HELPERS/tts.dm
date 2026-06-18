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
///
/// Piper treats short all-uppercase tokens as acronyms and spells them out
/// ("IT" -> "I.T"). For a fully-shouted message we lowercase the whole thing
/// so "WE ARE GOING TO MAKE IT" reads as a sentence. Messages with any
/// lowercase letter are left alone, which preserves mixed-case acronyms like
/// "Call NASA now".
/proc/tts_speech_filter(text)
	var/static/regex/bad_chars_regex = regex("\[^a-zA-Z0-9 ,?.!'&-]", "g")
	var/static/regex/has_lowercase = regex("\[a-z]")
	var/static/regex/has_letter = regex("\[A-Za-z]")
	text = html_decode(text)
	if(has_letter.Find(text) && !has_lowercase.Find(text))
		text = lowertext(text)
	return bad_chars_regex.Replace(text, " ")

/// Substitute the templating tokens used by the gateway's ffmpeg filter strings,
/// then URL-encode for safe transit in a query parameter.
/proc/tts_filter_encode(text, speaker, pitch, blips = FALSE)
	text = replacetext(text, "%PITCH%", SStts.pitch_enabled ? pitch : 0)
	text = replacetext(text, "%FEMALE%", !!findtext(speaker, "Woman"))
	text = replacetext(text, "%BLIPS%", blips)
	return url_encode(text)
