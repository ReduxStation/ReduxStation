// Low-pop bonus package.
//
// At roundstart, if active player count is below LOW_POP_BONUS_THRESHOLD, the
// station gets a one-shot supply drop plus persistent boosts for the round:
//
//   * Stack drops at fixed coords (uranium, titanium, bluespace crystals,
//     bluespace miner boards, tier-4 stock parts).
//   * Diamond and plasma sheets dropped into a pre-existing crate.
//   * Both clonepods and every DNA scanner on the station get their
//     component_parts swapped to the tier-4 (bluespace) set so their stats
//     RefreshParts to maximum values.
//   * SSresearch points-per-second multiplied by 1.5.
//   * Every department starting budget doubled.
//   * Every job paycheck tripled (single edit on /datum/job.paycheck so all
//     downstream payday() calls pick it up).
//
// Registered from /proc/hippie_initialize so it fires every round.
// Admin verb /client/proc/cmd_admin_force_low_pop_bonus exists for testing.

#define LOW_POP_BONUS_THRESHOLD 7
#define LOW_POP_RESEARCH_MULTIPLIER 1.5
#define LOW_POP_PAYCHECK_MULTIPLIER 3

GLOBAL_VAR_INIT(low_pop_bonus_active, FALSE)

/proc/register_low_pop_bonus()
	SSticker.OnRoundstart(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(check_low_pop_bonus)))

/proc/check_low_pop_bonus()
	var/active = get_active_player_count(alive_check = FALSE, afk_check = TRUE, human_check = FALSE)
	log_game("LOW_POP_BONUS check: active_players=[active] threshold=[LOW_POP_BONUS_THRESHOLD]")
	if(active >= LOW_POP_BONUS_THRESHOLD)
		return
	GLOB.low_pop_bonus_active = TRUE
	apply_low_pop_bonus()

/proc/apply_low_pop_bonus()
	log_game("LOW_POP_BONUS: applying bonus package")
	spawn_low_pop_supplies()
	upgrade_low_pop_cloners()
	boost_low_pop_research()
	boost_low_pop_economy()
	announce_low_pop_bonus()
	log_game("LOW_POP_BONUS: bonus package applied")

/proc/spawn_low_pop_supplies()
	// Uranium and titanium at (185, 93, 2).
	var/turf/uranium_turf = locate(185, 93, 2)
	new /obj/item/stack/sheet/mineral/uranium(uranium_turf, 30)
	new /obj/item/stack/sheet/mineral/titanium(uranium_turf, 50)

	// 5 bluespace miner boards at (103, 104, 2).
	var/turf/board_turf = locate(103, 104, 2)
	for(var/i in 1 to 5)
		new /obj/item/circuitboard/machine/bluespace_miner(board_turf)

	// 30 bluespace crystal sheets at (105, 103, 2).
	var/turf/crystal_turf = locate(105, 103, 2)
	new /obj/item/stack/sheet/bluespace_crystal(crystal_turf, 30)

	// 30 diamond, 50 plasma into the pre-existing crate at (83, 106, 2).
	var/turf/crate_turf = locate(83, 106, 2)
	var/obj/structure/closet/C = locate(/obj/structure/closet) in crate_turf
	new /obj/item/stack/sheet/mineral/diamond(C, 30)
	new /obj/item/stack/sheet/mineral/plasma(C, 50)

	// 4 of each tier-4 (bluespace) stock part at (100, 105, 2).
	var/turf/parts_turf = locate(100, 105, 2)
	var/list/tier4_parts = list(
		/obj/item/stock_parts/capacitor/quadratic,
		/obj/item/stock_parts/scanning_module/triphasic,
		/obj/item/stock_parts/manipulator/femto,
		/obj/item/stock_parts/micro_laser/quadultra,
		/obj/item/stock_parts/matter_bin/bluespace,
		/obj/item/stock_parts/cell/bluespace,
	)
	for(var/part_path in tier4_parts)
		for(var/i in 1 to 4)
			new part_path(parts_turf)

// For a given existing stock part instance, return the tier-4 typepath that
// replaces it. Returns null for non-stock_parts entries (circuit board, cable
// coil, glass sheet) so they pass through untouched.
/proc/low_pop_tier4_upgrade_path(obj/item/part)
	if(istype(part, /obj/item/stock_parts/capacitor))
		return /obj/item/stock_parts/capacitor/quadratic
	if(istype(part, /obj/item/stock_parts/scanning_module))
		return /obj/item/stock_parts/scanning_module/triphasic
	if(istype(part, /obj/item/stock_parts/manipulator))
		return /obj/item/stock_parts/manipulator/femto
	if(istype(part, /obj/item/stock_parts/micro_laser))
		return /obj/item/stock_parts/micro_laser/quadultra
	if(istype(part, /obj/item/stock_parts/matter_bin))
		return /obj/item/stock_parts/matter_bin/bluespace
	if(istype(part, /obj/item/stock_parts/cell))
		return /obj/item/stock_parts/cell/bluespace
	return null

// Swap every stock_parts entry in M.component_parts with its tier-4 equivalent.
// Preserves circuit board / cable coil / glass sheet so deconstruction still
// works. New parts are created at null loc so they live in component_parts only
// and never get dumped when the machine opens. Returns count of parts swapped.
/proc/low_pop_upgrade_machine_parts(obj/machinery/M)
	var/list/new_parts = list()
	var/swapped = 0
	for(var/obj/item/part in M.component_parts)
		var/upgrade_path = low_pop_tier4_upgrade_path(part)
		if(upgrade_path)
			new_parts += new upgrade_path(null)
			qdel(part)
			swapped++
		else
			new_parts += part
	M.component_parts = new_parts
	M.RefreshParts()
	return swapped

/proc/upgrade_low_pop_cloners()
	var/pods = 0
	for(var/obj/machinery/clonepod/CP in GLOB.machines)
		if(low_pop_upgrade_machine_parts(CP))
			pods++
	var/scanners = 0
	for(var/obj/machinery/dna_scannernew/DS in GLOB.machines)
		if(low_pop_upgrade_machine_parts(DS))
			scanners++
	log_game("LOW_POP_BONUS: upgraded [pods] clonepod(s) and [scanners] DNA scanner(s) to tier-4 stock parts")

/proc/boost_low_pop_research()
	var/before = SSresearch.single_server_income[TECHWEB_POINT_TYPE_GENERIC]
	SSresearch.single_server_income[TECHWEB_POINT_TYPE_GENERIC] = before * LOW_POP_RESEARCH_MULTIPLIER
	log_game("LOW_POP_BONUS: research income [before] -> [SSresearch.single_server_income[TECHWEB_POINT_TYPE_GENERIC]] pts/sec")

/proc/boost_low_pop_economy()
	// Double every department starting budget.
	for(var/dep_id in SSeconomy.department_accounts)
		var/datum/bank_account/D = SSeconomy.get_dep_account(dep_id)
		if(!D)
			continue
		var/before = D.account_balance
		D.adjust_money(D.account_balance)
		log_game("LOW_POP_BONUS: dept [dep_id] balance [before] -> [D.account_balance]")
	// Triple every job paycheck. Roundstart paychecks plus all later payday()
	// calls scale because account_job.paycheck is read fresh on each payday.
	for(var/datum/job/J in SSjob.occupations)
		J.paycheck *= LOW_POP_PAYCHECK_MULTIPLIER
	log_game("LOW_POP_BONUS: all job paychecks multiplied by [LOW_POP_PAYCHECK_MULTIPLIER]")

/proc/announce_low_pop_bonus()
	priority_announce(
		"Skeleton crew operations confirmed. Emergency supply caches have been pre-staged on the station. Department budgets doubled and salaries tripled for this shift. Research and Development systems pre-boosted. Medical cloners pre-upgraded.",
		"CentCom Logistics"
	)

/client/proc/cmd_admin_force_low_pop_bonus()
	set name = "Force Low-Pop Bonus"
	set category = "Server"
	if(!check_rights(R_ADMIN))
		return
	if(GLOB.low_pop_bonus_active)
		to_chat(usr, "<span class='warning'>Low-pop bonus is already active this round.</span>")
		return
	GLOB.low_pop_bonus_active = TRUE
	apply_low_pop_bonus()
	message_admins("[key_name_admin(usr)] forced the low-pop bonus package to fire.")
	log_admin("[key_name(usr)] forced the low-pop bonus package to fire.")
