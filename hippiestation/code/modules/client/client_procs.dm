/client/New()
	. = ..()
	mentor_datum_set()
	if(CONFIG_GET(string/ipstack_api_key))
		country = SSipstack.check_ip(address)
		if(country == "???")
			message_admins("<span class='adminnotice'>GeoIP for [key_name_admin(src)] was invalid!</span>")
		else if(country == "Brazil")
			message_admins("<span class='adminnotice'>[key_name_admin(src)] is a Brazilian!</span>")

/client/proc/hippie_client_procs(href_list)
	if(href_list["mentor_msg"])
		if(CONFIG_GET(flag/mentors_mobname_only))
			var/mob/M = locate(href_list["mentor_msg"])
			cmd_mentor_pm(M,null)
		else
			cmd_mentor_pm(href_list["mentor_msg"],null)
		return TRUE

	//Mentor Follow
	if(href_list["mentor_follow"])
		var/mob/living/M = locate(href_list["mentor_follow"])

		if(istype(M))
			mentor_follow(M)
		return TRUE

/client/proc/mentor_datum_set(admin)
	mentor_datum = GLOB.mentor_datums[ckey]
	if(!mentor_datum && check_rights_for(src, R_ADMIN,0)) // admin with no mentor datum?let's fix that
		new /datum/mentors(ckey)
	if(mentor_datum)
		if(!check_rights_for(src, R_ADMIN,0) && !admin)
			GLOB.mentors |= src // don't add admins to this list too.
		mentor_datum.owner = src
		add_mentor_verbs()
		mentor_memo_output("Show")

/client/proc/is_mentor() // admins are mentors too.
	if(mentor_datum || check_rights_for(src, R_ADMIN,0))
		return TRUE

// The HippieStation "Fun > Play TTS" admin verb (mimic1-era) lived here. The new TTS
// subsystem ships its own admin verbs under code/modules/admin/verbs/tts.dm
// (Reestablish TTS Connection / Test TTS), under R_DEBUG.

/client/proc/add_ooc_icons()
	var/icons = ""
	if(holder)
		if(!holder.fakekey)
			if(check_rights_for(src, R_ADMIN))
				icons += "[icon2html('hippiestation/icons/ooc_icons/banhammer.dmi', world)]"
	if(is_mentor())
		if(!holder)
			icons += "[icon2html('hippiestation/icons/ooc_icons/brain.dmi', world)]"
	if(is_donator)
		icons += "[icon2html('hippiestation/icons/ooc_icons/gold_coin.dmi', world)]"
	var/list/flags = icon_states('hippiestation/icons/ooc_icons/countries.dmi')
	if((country && length(country)) || country_icon)
		if(country && length(country) && !country_icon)
			if(country in flags)
				country_icon = country
			else
				for(var/name in flags)
					if(findtext(lowertext(name), lowertext(country)))
						country_icon = name
				if(!country_icon)
					for(var/name in flags)
						if(findtext(lowertext(country), lowertext(name)))
							country_icon = name
		if(country_icon)
			icons += "[icon2html('hippiestation/icons/ooc_icons/countries.dmi', world, country_icon)]"
	return icons
