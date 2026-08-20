/**
 * A colonist carries what they learned into the next chapter.
 *
 * This is the payload of the whole phase. Preferences already carry a character's name and face between
 * rounds, and the other players remember who did what - skill is the one thing a colonist genuinely cannot
 * bring back with them, so it is the one thing worth writing down.
 *
 * Restoring goes through set_experience() rather than assigning the numbers, because levels, traits and the
 * status effects some skills grant on level-up are all derived from experience by that call. A colonist who
 * came back with the right number and the wrong level would be worse than one who came back untrained.
 */
/datum/unit_test/rimstation_colonist_skills_round_trip

/datum/unit_test/rimstation_colonist_skills_round_trip/Run()
	var/mob/living/carbon/human/veteran = allocate(/mob/living/carbon/human/consistent)
	veteran.mind_initialize()
	veteran.mind.set_experience(/datum/skill/mining, SKILL_EXP_EXPERT, silent = TRUE)
	veteran.mind.set_experience(/datum/skill/construction, SKILL_EXP_APPRENTICE, silent = TRUE)

	var/expected_mining_level = veteran.mind.get_skill_level(/datum/skill/mining)
	TEST_ASSERT(expected_mining_level > SKILL_LEVEL_NONE, "The test could not raise a skill above untrained, so carrying one proves nothing.")

	var/datum/colonist_record/record = new("colonist-1-abcd", "Vera Holt", "playerone")
	allocated += record
	TEST_ASSERT(capture_colonist_skills(record, veteran.mind), "A colonist's skills could not be read out of their mind.")
	TEST_ASSERT_EQUAL(record.skills["[/datum/skill/mining]"], SKILL_EXP_EXPERT, "A colonist's mining experience was not captured.")
	TEST_ASSERT_EQUAL(record.skills["[/datum/skill/construction]"], SKILL_EXP_APPRENTICE, "A colonist's construction experience was not captured.")

	// Untrained skills are not written down: a record should describe what somebody learned, not list the
	// nine things they did not.
	TEST_ASSERT(!("[/datum/skill/gaming]" in record.skills), "A skill the colonist never trained was written into their record.")

	// Through disk, because that is the trip it actually makes.
	var/datum/colonist_record/restored_record = new
	allocated += restored_record
	TEST_ASSERT(restored_record.deserialize(json_decode(json_encode(record.serialize()))), "A record carrying skills did not survive a JSON round trip.")

	var/mob/living/carbon/human/newcomer = allocate(/mob/living/carbon/human/consistent)
	newcomer.mind_initialize()
	TEST_ASSERT_EQUAL(newcomer.mind.get_skill_exp(/datum/skill/mining), 0, "A fresh mind already knew mining, so restoring onto it proves nothing.")

	TEST_ASSERT(restore_colonist_skills(restored_record, newcomer.mind), "A returning colonist's skills could not be restored.")
	TEST_ASSERT_EQUAL(newcomer.mind.get_skill_exp(/datum/skill/mining), SKILL_EXP_EXPERT, "A returning colonist came back with the wrong mining experience.")
	TEST_ASSERT_EQUAL(newcomer.mind.get_skill_level(/datum/skill/mining), expected_mining_level, "A returning colonist came back with the right experience but the wrong level, so nothing derived from level was updated.")
	TEST_ASSERT_EQUAL(newcomer.mind.get_skill_exp(/datum/skill/construction), SKILL_EXP_APPRENTICE, "A returning colonist forgot a second skill.")


/// Skills come off disk, so a record naming something this build no longer has costs that skill, not the colonist.
/datum/unit_test/rimstation_colonist_skills_tolerate_unknown_entries

/datum/unit_test/rimstation_colonist_skills_tolerate_unknown_entries/Run()
	var/mob/living/carbon/human/newcomer = allocate(/mob/living/carbon/human/consistent)
	newcomer.mind_initialize()

	var/datum/colonist_record/record = new("colonist-1-abcd", "Vera Holt", "playerone")
	allocated += record
	record.skills = list(
		"[/datum/skill/mining]" = SKILL_EXP_EXPERT,
		"/datum/skill/a_skill_this_build_does_not_have" = SKILL_EXP_MASTER,
		"not even a typepath" = 400,
	)

	TEST_ASSERT(restore_colonist_skills(record, newcomer.mind), "A record naming a retired skill restored nothing at all.")
	TEST_ASSERT_EQUAL(newcomer.mind.get_skill_exp(/datum/skill/mining), SKILL_EXP_EXPERT, "Dropping an unknown skill also dropped a valid one.")

	// A typepath that exists but is not a skill must not be restored either.
	record.skills = list("[/datum/skill]" = 100, "[/mob/living/carbon/human]" = 100)
	TEST_ASSERT(restore_colonist_skills(record, newcomer.mind), "A record naming a non-skill typepath was refused outright.")


/**
 * Skill decay ships switched off, and is exactly lossless while it is.
 *
 * Carryover with no counterweight only ever ratchets upward, which is why the mechanism exists at all - but
 * the right rate cannot be judged before anybody has played several chapters, so the default has to be zero
 * and zero has to mean *nothing happens*, not "nearly nothing".
 */
/datum/unit_test/rimstation_colonist_skills_decay

/datum/unit_test/rimstation_colonist_skills_decay/Run()
	TEST_ASSERT_EQUAL(CONFIG_GET(number/campaign_skill_decay_per_chapter), 0, "Skill decay does not default to off.")

	// Ten chapters at the shipped default must return the number that went in, exactly.
	var/carried = SKILL_EXP_EXPERT
	for(var/chapter in 1 to 10)
		carried = decay_colonist_experience(carried, 0)
	TEST_ASSERT_EQUAL(carried, SKILL_EXP_EXPERT, "Ten chapters of the default decay lost a colonist experience they should have kept.")

	// A configured rate takes that proportion off each chapter.
	TEST_ASSERT_EQUAL(decay_colonist_experience(1000, 0.1), 900, "A tenth of a colonist's experience was not taken by a tenth decay.")
	TEST_ASSERT_EQUAL(decay_colonist_experience(1000, 0.5), 500, "Half a colonist's experience was not taken by a half decay.")

	// Decay approaches untrained and stops there. Negative experience is not a thing a colonist can have.
	var/ground_down = 100
	for(var/chapter in 1 to 50)
		ground_down = decay_colonist_experience(ground_down, 0.9)
	TEST_ASSERT(ground_down >= 0, "Decaying a colonist for fifty chapters took them below untrained.")

	TEST_ASSERT_EQUAL(decay_colonist_experience(0, 0.5), 0, "Decaying an untrained skill produced something other than untrained.")
	// A nonsense rate off a config file must not hand out experience or take it all at once.
	TEST_ASSERT_EQUAL(decay_colonist_experience(1000, -1), 1000, "A negative decay rate gave a colonist experience they had not earned.")
	TEST_ASSERT_EQUAL(decay_colonist_experience(1000, 5), 0, "A decay rate above one produced something other than untrained.")


/**
 * A stored experience figure is named the same thing the game would call it.
 *
 * The register works this out from the number rather than from a mind, because most of the roster is not in
 * the round - the away and the dead have no mind to ask. That makes it a second implementation of
 * update_skill_level(), and a second implementation that disagrees would quietly mislabel everybody.
 */
/datum/unit_test/rimstation_colonist_skill_level_names

/datum/unit_test/rimstation_colonist_skill_level_names/Run()
	TEST_ASSERT_EQUAL(colonist_skill_level_name(0), SSskills.level_names[SKILL_LEVEL_NONE], "An untrained colonist was not called untrained.")
	TEST_ASSERT_EQUAL(colonist_skill_level_name(SKILL_EXP_NOVICE), SSskills.level_names[SKILL_LEVEL_NOVICE], "A novice was not called a novice.")
	TEST_ASSERT_EQUAL(colonist_skill_level_name(SKILL_EXP_EXPERT), SSskills.level_names[SKILL_LEVEL_EXPERT], "An expert was not called an expert.")
	TEST_ASSERT_EQUAL(colonist_skill_level_name(SKILL_EXP_LEGENDARY), SSskills.level_names[SKILL_LEVEL_LEGENDARY], "A legend was not called a legend.")

	// Between thresholds a colonist is what they last passed, not what they are approaching.
	TEST_ASSERT_EQUAL(colonist_skill_level_name(SKILL_EXP_EXPERT + 1), SSskills.level_names[SKILL_LEVEL_EXPERT], "Experience just past a threshold promoted a colonist early.")
	TEST_ASSERT_EQUAL(colonist_skill_level_name(SKILL_EXP_EXPERT - 1), SSskills.level_names[SKILL_LEVEL_JOURNEYMAN], "Experience just short of a threshold promoted a colonist anyway.")

	// Beyond the last threshold there is nothing higher to be called.
	TEST_ASSERT_EQUAL(colonist_skill_level_name(SKILL_EXP_LEGENDARY * 10), SSskills.level_names[SKILL_LEVEL_LEGENDARY], "Experience past the last threshold was named something beyond legendary.")

	// And it must agree with the mind that would hold the same figure, or the register lies about live people.
	var/mob/living/carbon/human/reference = allocate(/mob/living/carbon/human/consistent)
	reference.mind_initialize()
	reference.mind.set_experience(/datum/skill/mining, SKILL_EXP_JOURNEYMAN, silent = TRUE)
	TEST_ASSERT_EQUAL(colonist_skill_level_name(SKILL_EXP_JOURNEYMAN), reference.mind.get_skill_level_name(/datum/skill/mining), "The register named a skill level differently from the mind holding it.")


/**
 * A colonist's skills reach their record whether or not their body survives the chapter.
 *
 * Capture at commit can only read bodies that are still standing. Somebody who logged off, or who was gibbed,
 * would otherwise donate a chapter of learning to nobody - so the binding writes their skills down as it is
 * torn off, and the commit is a sweep of whoever is still here rather than the only chance to be recorded.
 */
/datum/unit_test/rimstation_colonist_chapter/skills_captured_at_commit

/datum/unit_test/rimstation_colonist_chapter/skills_captured_at_commit/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/datum/colonist_record/dan = SScampaign.roster.find_or_create("playertwo", "Dan Reyes", generation_number = 1, chapter = 1)

	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent)
	vera_body.mind_initialize()
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")
	vera_body.mind.set_experience(/datum/skill/mining, SKILL_EXP_EXPERT, silent = TRUE)

	var/mob/living/carbon/human/dan_body = allocate(/mob/living/carbon/human/consistent)
	dan_body.mind_initialize()
	TEST_ASSERT(SScampaign.bind_colonist(dan_body, dan), "A second colonist could not be bound to a body.")
	dan_body.mind.set_experience(/datum/skill/construction, SKILL_EXP_JOURNEYMAN, silent = TRUE)

	// Dan leaves before the chapter ends. His learning has to be written down as he goes.
	QDEL_NULL(dan_body)
	TEST_ASSERT_EQUAL(dan.skills["[/datum/skill/construction]"], SKILL_EXP_JOURNEYMAN, "A colonist whose body was deleted mid-chapter lost what they had learned.")

	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down the chapter.")
	TEST_ASSERT_EQUAL(vera.skills["[/datum/skill/mining]"], SKILL_EXP_EXPERT, "A colonist still standing at the end of the chapter did not have their skills captured.")
	TEST_ASSERT_EQUAL(dan.skills["[/datum/skill/construction]"], SKILL_EXP_JOURNEYMAN, "Capturing the chapter overwrote the skills of a colonist who had already left.")

	// Committing twice must not decay or double anything, since a failed commit can be retried.
	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down the chapter a second time.")
	TEST_ASSERT_EQUAL(vera.skills["[/datum/skill/mining]"], SKILL_EXP_EXPERT, "Capturing the chapter twice changed what a colonist knew.")
