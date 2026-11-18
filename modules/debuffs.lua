-- goomui: status effect ids treated as DEBUFFS in the party buff list (everything else = buff).
--
-- Source: XIUI libs/bufftable.lua (commit e7e390b), buffTable.statusEffects entries with value 1.
--         XIUI is GPL-3.0 (https://github.com/tirem/HXUI); this is its factual id classification.
-- Corrections: XIUI marks these as buffs (0) although its own labels name debuffs:
--   [167] MAGIC_DEF_DOWN, [177] ENCUMBRANCE_II, [217] THRENODY, [473] MUDDLE, [540] GEO_POISON
-- Ids missing from XIUI's table are treated as buffs here (XIUI treats them as debuffs).
-- Edit freely: add [id]=true to mark more debuffs.
return {
    [1]=true, [2]=true, [3]=true, [4]=true, [5]=true, [6]=true, [7]=true, [8]=true, [9]=true, [10]=true,
    [11]=true, [12]=true, [13]=true, [14]=true, [15]=true, [16]=true, [17]=true, [18]=true, [19]=true, [20]=true,
    [21]=true, [22]=true, [23]=true, [28]=true, [29]=true, [30]=true, [31]=true, [128]=true, [129]=true, [130]=true,
    [131]=true, [132]=true, [133]=true, [134]=true, [135]=true, [136]=true, [137]=true, [138]=true, [139]=true, [140]=true,
    [141]=true, [142]=true, [143]=true, [144]=true, [145]=true, [146]=true, [147]=true, [148]=true, [149]=true, [155]=true,
    [156]=true, [167]=true, [168]=true, [171]=true, [172]=true, [173]=true, [174]=true, [175]=true, [177]=true, [186]=true,
    [189]=true, [192]=true, [193]=true, [194]=true, [217]=true, [223]=true, [259]=true, [260]=true, [261]=true, [262]=true,
    [263]=true, [264]=true, [291]=true, [298]=true, [299]=true, [309]=true, [391]=true, [392]=true, [393]=true, [394]=true,
    [395]=true, [396]=true, [397]=true, [398]=true, [399]=true, [400]=true, [404]=true, [448]=true, [449]=true, [450]=true,
    [451]=true, [452]=true, [473]=true, [536]=true, [540]=true, [557]=true, [558]=true, [559]=true, [560]=true, [561]=true,
    [562]=true, [563]=true, [564]=true, [565]=true, [566]=true, [567]=true, [572]=true, [576]=true, [597]=true, [630]=true,
    [631]=true, [798]=true, [805]=true,
};
