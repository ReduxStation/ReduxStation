// The HippieStation-era TTS stored a voice name on /datum/dna so changelings inherited
// it on transform. The new TTS subsystem attaches voice to /atom/movable directly and
// picks it in /mob/living/carbon/human/Initialize, so the DNA hooks are gone.
// transfer_identity / copy_dna / update_dna_identity no longer copy tts_voice; identity
// transfer keeps the destination mob's existing voice. If we want changeling voice
// transfer in a later phase the right place to add it is the body-creation path on the
// destination mob, not DNA.

/datum/dna/initialize_dna(newblood_type, skip_index = FALSE)
	. = ..()
	if(is_banned_from(holder.ckey, CLUWNEBAN) && !check_mutation(CLUWNEMUT))
		add_mutation(CLUWNEMUT) // you can't escape hell

/mob/living/carbon/human/set_species(datum/species/mrace, icon_update = TRUE, pref_load = FALSE)
	..()
	update_teeth()
	if(is_banned_from(ckey, CATBAN) && !istype(dna.species, /datum/species/human/felinid/tarajan))
		set_species(/datum/species/human/felinid/tarajan, icon_update=1) // can't escape hell
	if(is_banned_from(ckey, CLUWNEBAN) && !dna.check_mutation(CLUWNEMUT))
		dna.add_mutation(CLUWNEMUT) // you can't escape hell

/datum/dna/remove_mutation(mutation_name)
	..()
	if(is_banned_from(holder.ckey, CLUWNEBAN) && !check_mutation(CLUWNEMUT))
		add_mutation(CLUWNEMUT) // you can't escape hell
