// Register the new TTS debug verbs on /client/verbs so they appear in the admin
// panel. The check_rights(R_DEBUG) call inside each verb body is defense in
// depth, but the verbs must also be in client.verbs to be invokable through
// the panel at all.
/client/add_admin_verbs()
	. = ..()
	if(holder)
		var/rights = holder.rank.rights
		if(rights & R_DEBUG)
			verbs += /client/proc/cmd_reestablish_tts
			verbs += /client/proc/cmd_test_tts

/client/remove_admin_verbs()
	. = ..()
	verbs.Remove(/client/proc/cmd_reestablish_tts)
	verbs.Remove(/client/proc/cmd_test_tts)
