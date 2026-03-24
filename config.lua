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
    { name = 'SKEL_R_Hand',     id = 28422 },
    { name = 'SKEL_L_Hand',     id = 57005 },
    { name = 'SKEL_R_Forearm',  id = 61007 },
    { name = 'SKEL_L_Forearm',  id = 63931 },
    { name = 'SKEL_Spine2',     id = 24818 },
    { name = 'SKEL_R_UpperArm', id = 40269 },
    { name = 'SKEL_L_UpperArm', id = 45509 },
    { name = 'IK_R_Hand',       id = 36029 },
    { name = 'IK_L_Hand',       id = 65245 },
    { name = 'PH_R_Hand',       id = 26613 },
    { name = 'PH_L_Hand',       id = 18905 },
    { name = 'Head',            id = 31086 },
    { name = 'Pelvis',          id = 11816 },
}