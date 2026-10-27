/datum/language/khelish
	name = "Khelish"
	desc = "A unified language the quarians were forced to form after their expulsion from their native system."
	key = "q"
	default_priority = 90
	flags = TONGUELESS_SPEECH
	syllables = list(
		"ai", "ao", "ba", "bi", "bo", "se", "su", "so", "si",
		"li", "lo", "la", "vi", "vo", "te", "tu", "to", "ti",
		"ni", "no", "na", "ni", "no", "ge", "gu", "go", "gi",
		"ci", "co", "ca", "qi", "qo", "qe", "qu", "qo", "qi",
		"'",
	)
	icon = ICON_RIMSTATION_LANGUAGES
	icon_state = "quarian"

/datum/language_holder/quarian
	understood_languages = list(
		/datum/language/common = list(LANGUAGE_ATOM),
		/datum/language/khelish = list(LANGUAGE_ATOM),
	)
	spoken_languages = list(
		/datum/language/common = list(LANGUAGE_ATOM),
		/datum/language/khelish = list(LANGUAGE_ATOM),
	)
