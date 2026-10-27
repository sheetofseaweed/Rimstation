/datum/language/thessian
	name = "High Thessian"
	desc = "High Thessian is not really a language in the standard sense, but rather a set of rules that allows asari to \
		cobble together and use multiple local Thessian languages into one multilanguage, so that they can easily \
		communicate with each other."
	key = "e"
	default_priority = 90
	flags = TONGUELESS_SPEECH
	syllables = list(
		"yi", "ye", "wa", "wi", "wu", "we", "wyu", "va", "vi", "vu", "ve", "vo", "vya", "vyu", "vye", "vyo",
		"kye", "gye", "kwa", "kwi", "kwe", "kwo", "kwa", "gwa", "gwi", "gwe", "gwo", "gwa", "she", "je", "si", "zi",
		"tsa", "tsi", "tse", "tso", "tsyu", "ti", "tu", "tyu", "di", "du", "dyu", "nye", "hye", "bye", "si", "pye",
		"fa", "fi", "fe", "fo", "fo", "fyu", "fye", "fyo", "mye", "rye", "la", "li", "lu", "le", "lo", "lya",
	)
	icon = ICON_RIMSTATION_LANGUAGES
	icon_state = "asari"

/datum/language_holder/asari
	understood_languages = list(
		/datum/language/common = list(LANGUAGE_ATOM),
		/datum/language/thessian = list(LANGUAGE_ATOM),
	)
	spoken_languages = list(
		/datum/language/common = list(LANGUAGE_ATOM),
		/datum/language/thessian = list(LANGUAGE_ATOM),
	)
