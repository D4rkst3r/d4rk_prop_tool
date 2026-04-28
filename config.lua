Config = {}

Config.Command       = 'ptool'
Config.OnlyAdmins    = true   -- true = nur ACE permission 'd4rk_prop_tool.use'

Config.DefaultMoveSpeed   = 0.01
Config.DefaultRotateSpeed = 1.0

Config.MoveSpeeds   = { 0.001, 0.005, 0.01, 0.05, 0.1 }
Config.RotateSpeeds = { 0.5, 1.0, 5.0, 10.0, 45.0 }

Config.Props = {
    -- Food & Drinks
    'prop_cs_burger_01',
    'prop_cs_coffee_cup',
    'prop_cs_cup_001',
    'prop_cs_bottle_wine',
    'prop_cs_wine_bottle',
    'prop_beer_bottle',
    'prop_cs_beer_bot_01',
    'prop_wine_red',
    'prop_food_bs_chips',
    'prop_food_bs_hotdog',
    'prop_food_1_ing_ketch',
    'prop_food_bs_burger',
    'prop_food_burg',
    'prop_food_bs_meal_01',
    -- Smoking
    'prop_cigar_01',
    'prop_cs_ciggy_01',
    'prop_amb_ciggy_01',
    -- Bags & Cases
    'prop_amb_handbag_01',
    'prop_ld_jerrycan_01',
    'prop_ld_case_01',
    'prop_ld_briefcase_01',
    'prop_med_bag_01b',
    'prop_cs_duffel_bag_01',
    'prop_cs_shopping_bag',
    'prop_pap_bag_01',
    'prop_sh_gift_box_01',
    -- Tools
    'prop_tool_broom2',
    'prop_tool_shovel',
    'prop_tool_hammer',
    'prop_tool_screwdvr01',
    'prop_tool_wrench',
    'prop_tool_pickaxe',
    'prop_tool_box_03',
    'prop_tool_cable_tie',
    'prop_tool_extinguisher',
    'prop_tool_flashlight',
    -- Phones & Electronics
    'prop_cs_phone_01',
    'prop_npc_phone',
    'prop_npc_phone_02',
    'prop_cs_ipad_01',
    'prop_cs_remote_01',
    'prop_cs_walkie_talkie',
    'prop_cs_tablet',
    -- Weapons (Props only, kein Schaden)
    'prop_cs_baseball_bat',
    'prop_cs_crowbar',
    'prop_cs_knife_01',
    -- Medical
    'prop_defilbrilator',
    'prop_fire_exting_2b',
    'prop_cs_syringe_01',
    -- Documents & Office
    'prop_cs_clipboard',
    'prop_cs_folder_01',
    'prop_cs_notebook_01',
    'prop_cs_protest_sign',
    'prop_cs_paper_bag_01',
    'prop_notepad_01',
    -- Misc
    'prop_cs_bottle_cap',
    'prop_plas_bottle_01',
    'prop_cs_dildo_01',
    'prop_cs_comb_01',
    'prop_cs_lipstick_01',
    'prop_cs_mirror_01',
    'prop_cs_key_fob',
    'prop_cs_glass_bottle',
    'prop_cs_cash_note',
    'prop_cs_torch',
    'prop_amb_fags_01',
}

Config.Animations = {
    { label = 'Eat Burger',    dict = 'mp_player_inteat@burger',              anim = 'mp_player_int_eat_burger',   flags = 49 },
    { label = 'Drink Cup',     dict = 'mp_player_intdrink',                   anim = 'loop_bottle',                flags = 49 },
    { label = 'Hold Phone',    dict = 'cellphone@',                           anim = 'cellphone_call_listen_base', flags = 49 },
    { label = 'Smoke',         dict = 'amb@world_human_smoking@male@idle_a',  anim = 'idle_a',                    flags = 49 },
    { label = 'Sweep Broom',   dict = 'anim@amb@drug_field_workers@rake@male_b@base', anim = 'base',              flags = 49 },
    { label = 'Idle (Stand)',  dict = 'anim@amb@casino@bball@idle@male',      anim = 'idle_a',                    flags = 49 },
    { label = 'Look At Phone', dict = 'cellphone@',                           anim = 'cellphone_text_in',         flags = 49 },
    { label = 'Drink Bottle',  dict = 'mp_player_intdrink',                   anim = 'loop_bottle',               flags = 49 },
    { label = 'Carry Box',     dict = 'anim@heists@box_carry@',               anim = 'idle',                      flags = 49 },
    { label = 'Hold Clipboard',dict = 'missfbi3_carmeet',                     anim = 'carmeet_idlea_worker',      flags = 49 },
}

Config.Bones = {
    { name = 'SKEL_R_Hand',     id = 57005 },
    { name = 'SKEL_L_Hand',     id = 18905 },
    { name = 'SKEL_R_Forearm',  id = 28252 },
    { label = 'SKEL_L_Forearm', name = 'SKEL_L_Forearm', id = 61163 },
    { name = 'SKEL_Spine2',     id = 24817 },
    { name = 'SKEL_R_UpperArm', id = 40269 },
    { name = 'SKEL_L_UpperArm', id = 45509 },
    { name = 'IK_R_Hand',       id = 6286  },
    { name = 'IK_L_Hand',       id = 36029 },
    { name = 'PH_R_Hand',       id = 28422 },
    { name = 'PH_L_Hand',       id = 60309 },
    { name = 'SKEL_Head',       id = 31086 },
    { name = 'SKEL_Pelvis',     id = 11816 },
}
