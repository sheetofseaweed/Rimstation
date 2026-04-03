/mob/living/carbon/human/click_ctrl_shift(mob/user)
	SEND_SIGNAL(src, COMSIG_CLICK_CTRL_SHIFT, user)
	return
