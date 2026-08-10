/**
 * Telemetry is the only way a raid gets tuned after the fact.
 *
 * The schema is asserted rather than the values: a record missing warning time or spent budget cannot answer
 * "was that raid fair", which is the entire reason to record one.
 */
/datum/unit_test/rimstation_raid_telemetry_schema

/datum/unit_test/rimstation_raid_telemetry_schema/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/datum/colony_raid_telemetry/telemetry = raid.telemetry
	TEST_ASSERT_NOTNULL(telemetry, "A raid was created without a telemetry record.")

	raid.threat_budget = 100
	telemetry.record_composition(list(/mob/living/basic/trooper/pirate/melee = 3), 60)
	telemetry.record_state(COLONY_RAID_WARNING)
	telemetry.record_state(COLONY_RAID_ASSAULTING)
	telemetry.record_casualty(TRUE)
	telemetry.record_casualty(TRUE)
	telemetry.record_casualty(FALSE)
	raid.resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "the attackers were killed")

	var/list/payload = telemetry.build_payload()
	TEST_ASSERT_NOTNULL(payload, "The telemetry record produced no payload.")

	// Everything needed to reconstruct whether the fight was winnable.
	var/list/required_fields = list(
		"raid_id",
		"offered_budget",
		"spent_budget",
		"composition",
		"warning_seconds",
		"insertion_direction",
		"attacker_casualties",
		"defender_casualties",
		"core_capture_progress",
		"duration_seconds",
		"controlled_units",
		"ai_units",
		"settlement_damage",
		"outcome",
	)
	for(var/field in required_fields)
		TEST_ASSERT(payload.Find(field), "The raid telemetry payload is missing '[field]', so the raid cannot be evaluated afterwards.")

	TEST_ASSERT_EQUAL(payload["outcome"], COLONY_RAID_OUTCOME_REPELLED, "Telemetry did not record the raid outcome.")
	TEST_ASSERT_EQUAL(payload["spent_budget"], 60, "Telemetry did not record the budget actually spent.")
	TEST_ASSERT_EQUAL(payload["offered_budget"], 100, "Telemetry did not record the budget the raid was offered.")
	TEST_ASSERT_EQUAL(payload["attacker_casualties"], 2, "Telemetry miscounted attacker casualties.")
	TEST_ASSERT_EQUAL(payload["defender_casualties"], 1, "Telemetry miscounted defender casualties.")


/// Damage is measured against a registered list, never by scanning the world.
/datum/unit_test/rimstation_raid_telemetry_damage

/datum/unit_test/rimstation_raid_telemetry_damage/Run()
	var/datum/colony_raid_telemetry/telemetry = new
	allocated += telemetry

	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core)
	telemetry.register_settlement_structure(core)

	telemetry.sample_settlement_integrity()
	TEST_ASSERT_EQUAL(telemetry.settlement_damage_sample(), 0, "An untouched settlement reported damage.")

	core.take_damage(200, BRUTE, sound_effect = FALSE)
	var/damage = telemetry.settlement_damage_sample()
	TEST_ASSERT(damage > 0, "Damage to a registered structure was not reflected in the settlement sample.")

	// A destroyed structure must count as fully lost rather than silently dropping out of the sample.
	var/baseline = telemetry.baseline_integrity
	TEST_ASSERT(baseline > 0, "The settlement baseline was never sampled.")
	qdel(core)
	TEST_ASSERT(telemetry.settlement_damage_sample() >= damage, "A destroyed structure reduced the recorded settlement damage.")
