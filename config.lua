Config = {}

Config.Command       = 'ptool'
Config.OnlyAdmins    = false   -- true = nur ACE permission 'd4rk_prop_tool.use'

Config.DefaultMoveSpeed   = 0.01
Config.DefaultRotateSpeed = 1.0

Config.MoveSpeeds   = { 0.001, 0.005, 0.01, 0.05, 0.1 }
Config.RotateSpeeds = { 0.5, 1.0, 5.0, 10.0, 45.0 }

Config.Props = {
    'prop_cs_burger_01',
    'prop_ld_jerrycan_01',
    'prop_tool_broom2',
    'prop_beer_bottle',
    'prop_wine_red',
    'prop_cigar_01',
    'prop_amb_handbag_01',
    'prop_cs_beer_bot_01',
}

Config.Animations = {
    { label = 'Eat Burger',   dict = 'mp_player_inteat@burger',              anim = 'mp_player_int_eat_burger',  flags = 49 },
    { label = 'Drink Cup',    dict = 'mp_player_intdrink',                   anim = 'loop_bottle',               flags = 49 },
    { label = 'Hold Phone',   dict = 'cellphone@',                           anim = 'cellphone_call_listen_base', flags = 49 },
    { label = 'Smoke',        dict = 'amb@world_human_smoking@male@idle_a',  anim = 'idle_a',                    flags = 49 },
    { label = 'Sweep Broom',  dict = 'anim@amb@drug_field_workers@rake@male_b@base', anim = 'base',              flags = 49 },
    { label = 'Idle (Stand)', dict = 'anim@amb@casino@bball@idle@male',      anim = 'idle_a',                    flags = 49 },
}

Config.Bones = {
    { name = 'SKEL_R_Hand',     id = 57005 }, -- Korrigiert (war 28422 -> PH_R_Hand)
    { name = 'SKEL_L_Hand',     id = 18905 }, -- Korrigiert (war 57005 -> SKEL_R_Hand)
    { name = 'SKEL_R_Forearm',  id = 28252 }, -- Korrigiert (war 61007 -> RB_L_ForeArmRoll)
    { name = 'SKEL_L_Forearm',  id = 61163 }, -- Korrigiert (war 63931 -> SKEL_L_Calf / linke Wade)
    { name = 'SKEL_Spine2',     id = 24817 }, -- Korrigiert (war 24818 -> SKEL_Spine3)
    { name = 'SKEL_R_UpperArm', id = 40269 }, -- War richtig!
    { name = 'SKEL_L_UpperArm', id = 45509 }, -- War richtig!
    { name = 'IK_R_Hand',       id = 6286 },  -- Korrigiert (war 36029 -> IK_L_Hand)
    { name = 'IK_L_Hand',       id = 36029 }, -- Korrigiert (war 65245 -> IK_L_Foot)
    { name = 'PH_R_Hand',       id = 28422 }, -- Korrigiert (war 26613 -> SKEL_L_Finger30)
    { name = 'PH_L_Hand',       id = 60309 }, -- Korrigiert (war 18905 -> SKEL_L_Hand)
    { name = 'SKEL_Head',       id = 31086 }, -- ID war richtig (31086), Name als 'SKEL_Head' ist sauberer
    { name = 'SKEL_Pelvis',     id = 11816 }, -- ID war richtig (11816), Name als 'SKEL_Pelvis' ist sauberer
}