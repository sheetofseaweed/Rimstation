/**
 * The recorded result of one chapter.
 *
 * This datum only ever *describes* what happened. It is explicitly not allowed to enact anything: Phase 1
 * runs in a non-destructive test campaign, so a lost chapter announces and logs and leaves every world save
 * exactly where it was. Phase 2 adds the authority to promote or close a campaign generation, and it reads
 * this record rather than replacing it.
 *
 * Resolution is first-writer-wins. A real outcome must not be overwritten by a later, vaguer one - an
 * ordinary round ending after a raid was already repelled should not turn a win into "round ended".
 */
/datum/colony_chapter_outcome
	/// One of COLONY_OUTCOME_PENDING, COLONY_OUTCOME_SUCCESS or COLONY_OUTCOME_FAILURE.
	var/result = COLONY_OUTCOME_PENDING
	/// Human-readable explanation of why the chapter ended this way.
	var/reason
	/// world.time at which the result was recorded.
	var/resolved_at = 0
	/// Identifier of the raid that decided the chapter, when one did.
	var/raid_id
	/// Telemetry record for the deciding event, when one exists.
	var/datum/colony_raid_telemetry/telemetry
	/**
	 * Whether resolving this outcome modified persistent campaign state.
	 *
	 * Always FALSE in Phase 1 and asserted as such by the tests. It exists so that when Phase 2 does gain
	 * that authority, the moment it starts being used is visible rather than implicit.
	 */
	var/touched_persistence = FALSE

/// TRUE once a result has been recorded.
/datum/colony_chapter_outcome/proc/is_resolved()
	return result != COLONY_OUTCOME_PENDING

/**
 * Records the chapter result. Returns TRUE if this call is the one that decided it.
 *
 * Refuses anything outside the outcome vocabulary, and refuses to overwrite an already-recorded result.
 */
/datum/colony_chapter_outcome/proc/resolve(new_result, new_reason, deciding_raid_id, datum/colony_raid_telemetry/deciding_telemetry)
	if(!(new_result in list(COLONY_OUTCOME_SUCCESS, COLONY_OUTCOME_FAILURE)))
		log_game("Colony chapter outcome rejected an unknown result '[new_result]'.")
		return FALSE
	if(is_resolved())
		log_game("Colony chapter outcome already resolved as [result]; ignoring later [new_result] ([new_reason]).")
		return FALSE

	result = new_result
	reason = new_reason
	resolved_at = world.time
	raid_id = deciding_raid_id
	telemetry = deciding_telemetry

	log_game("Colony chapter resolved as [result]: [reason].")
	message_admins("Colony chapter resolved as [result]: [reason].")
	return TRUE

/datum/colony_chapter_outcome/Destroy(force)
	telemetry = null
	return ..()
