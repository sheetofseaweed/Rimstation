#undef INTERACTION_COOLDOWN
#define INTERACTION_COOLDOWN 0.25 SECONDS

#define ORGAN_SLOT_BUTT "butt"
#define ORGAN_SLOT_BELLY "belly"

#define BELLY_MIN_SIZE 1
#define BELLY_MAX_SIZE 7

#define span_lewd(str) span_purple(str)

#define INTERACTION_REQUIRE_SELF_MOUTH "self_mouth"
#define INTERACTION_REQUIRE_TARGET_MOUTH "target_mouth"
#define INTERACTION_REQUIRE_SELF_TOPLESS "self_topless"
#define INTERACTION_REQUIRE_TARGET_TOPLESS "target_topless"
#define INTERACTION_REQUIRE_SELF_BOTTOMLESS "self_bottomless"
#define INTERACTION_REQUIRE_TARGET_BOTTOMLESS "target_bottomless"
#define INTERACTION_REQUIRE_SELF_FEET "self_feet"
#define INTERACTION_REQUIRE_TARGET_FEET "target_feet"
#define INTERACTION_REQUIRE_SELF_HUMAN "self_human"
#define INTERACTION_REQUIRE_TARGET_HUMAN "target_human"

#define INTERACTION_BOTH "both"

#define INTERACTION_EXTREME (1<<0)
#define INTERACTION_HARMFUL (1<<1)
#define INTERACTION_UNHOLY (1<<2)

#define INTERACTION_CAT_LEWD "lewd"
#define INTERACTION_CAT_EXTREME "extreme"
#define INTERACTION_CAT_HARMFUL "harmful"
#define INTERACTION_CAT_UNHOLY "unholy"

#define INTERACTION_FILLS_CONTAINERS list( \
	"info" = "You can fill a container if you have it in your active hand or are pulling it", \
	"icon" = "flask", \
	"color" = "transparent", \
)
#define INTERACTION_MAY_CONTAIN_DRINK list( \
	"info" = "May contain reagents", \
	"icon" = "cow", \
	"color" = "white", \
)
#define INTERACTION_MAY_CAUSE_PREGNANCY list( \
	"info" = "May cause pregnancies", \
	"icon" = "person-pregnant", \
	"color" = "white", \
)

#define INTERACTION_OVERRIDE_FLUID_TRANSFER (1<<0)

#define CLIMAX_VAGINA "vagina"
#define CLIMAX_PENIS "penis"
#define CLIMAX_BOTH "both"
#define CLIMAX_POSITION_USER "climax_user"
#define CLIMAX_POSITION_TARGET "climax_target"
#define CLIMAX_TARGET_MOUTH "mouth"
#define CLIMAX_TARGET_SHEATH "sheath"

#define INTERACTION_SPEED_MIN 0.5 SECONDS
#define INTERACTION_SPEED_MAX 4 SECONDS

#define INIT_ORDER_INTERACTIONS -150
