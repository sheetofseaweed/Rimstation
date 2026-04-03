#define WHITELISTFILE "[global.config.directory]/whitelist.txt"

GLOBAL_LIST(whitelist)

/proc/load_whitelist()
	GLOB.whitelist = list()
	for(var/line in world.file2list(WHITELISTFILE))
		if(!line)
			continue
		if(findtextEx(line,"#",1,2))
			continue
		GLOB.whitelist += ckey(line)

	if(!GLOB.whitelist.len)
		GLOB.whitelist = null

/proc/check_whitelist_file(ckey)
	if(!GLOB.whitelist)
		return FALSE
	. = (ckey in GLOB.whitelist)


/proc/check_whitelist(key)
	if(!SSdbcore.Connect())
		log_world("Failed to connect to database in check_whitelist(). Falling back to the legacy Whitelist.")
		log_game("Failed to connect to database in check_whitelist(). Falling back to the legacy Whitelist.")
		return check_whitelist_file(key)

	var/datum/db_query/query_get_whitelist = SSdbcore.NewQuery({"
		SELECT id FROM [format_table_name("whitelist")]
		WHERE ckey = :ckey
	"}, list("ckey" = key)
	)

	if(!query_get_whitelist.Execute())
		log_sql("Whitelist check for ckey [key] failed to execute. Rejecting")
		message_admins("Whitelist check for ckey [key] failed to execute. Rejecting")
		qdel(query_get_whitelist)
		return FALSE

	var/allow = query_get_whitelist.NextRow()

	qdel(query_get_whitelist)

	return allow


ADMIN_VERB(whitelist_player, R_BAN, "Whitelist CKey", "Adds a ckey to the database whitelist.", ADMIN_CATEGORY_MAIN)
	var/input_ckey = input("CKey to whitelist: (Adds CKey to the database whitelist)") as null|text
	// The ckey proc "santizies" it to be its "true" form
	var/canon_ckey = ckey(input_ckey)
	if(!input_ckey || !canon_ckey)
		return

	if(!SSdbcore.Connect())
		to_chat(user, span_warning("Failed to connect to the database. [canon_ckey] was added to legacy whitelist."))
		// Dont add them to the whitelist if they are already in it
		if(!(canon_ckey in GLOB.whitelist))
			GLOB.whitelist += canon_ckey
			rustg_file_append("\n[input_ckey]", WHITELISTFILE)
			message_admins("[input_ckey] has been legacy whitelisted by [key_name(user)]")
			log_admin("[input_ckey] has been legacy whitelisted by [key_name(user)]")

		return

	// Don't add them to the whitelist if they are already in it.
	if(check_whitelist(canon_ckey))
		to_chat(user, span_warning("[canon_ckey] is already whitelisted."))
		return

	var/datum/db_query/query_add_whitelist = SSdbcore.NewQuery({"
		INSERT INTO [format_table_name("whitelist")] (ckey)
		VALUES (:ckey)
	"}, list("ckey" = canon_ckey))

	if(!query_add_whitelist.Execute(async = FALSE))
		log_sql("Whitelisting ckey [canon_ckey] by [key_name(user)] failed to execute.")
		to_chat(user, span_warning("Failed to add [canon_ckey] to the database whitelist."))
		qdel(query_add_whitelist)
		return

	qdel(query_add_whitelist)

	if(!GLOB.whitelist)
		GLOB.whitelist = list()
	GLOB.whitelist += canon_ckey

	message_admins("[canon_ckey] has been whitelisted by [key_name(user)]")
	log_admin("[canon_ckey] has been whitelisted by [key_name(user)]")

ADMIN_VERB_CUSTOM_EXIST_CHECK(whitelist_player)
	return CONFIG_GET(flag/usewhitelist)

#undef WHITELISTFILE
