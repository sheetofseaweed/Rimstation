/**
 * Research costs more in a campaign than it does on a shift.
 *
 * A station researches for one round and is scrapped. A colony keeps everything it learns, chapter after
 * chapter, so at station prices it would hold the entire techweb within a few sessions and the curve would be
 * over before it was visible. Multiplying the price is the smallest change that stretches the same research
 * across a campaign, and it leaves what players do to earn it exactly as they already understand it.
 *
 * Applied at `get_price()` because every consumer routes through it - affordability checks, the purchase
 * itself, and the price the console displays - so there is no path that sees the station price.
 */
/datum/techweb_node/get_price(datum/techweb/host)
	var/list/costs = ..()
	if(!SScampaign?.is_campaign_active())
		return costs

	// The parent hands back its own research_costs list when there is no host, so this must never edit in
	// place: doing so would multiply the node's real cost again on every call until nothing was affordable.
	costs = costs.Copy()
	for(var/cost_type in costs)
		costs[cost_type] = round(costs[cost_type] * CAMPAIGN_RESEARCH_COST_MULTIPLIER)
	return costs
