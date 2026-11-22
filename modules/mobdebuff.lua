-- goomui: debuffs on the targeted mob, with timers, in their own panel above the target panel (modules/bar.lua).
--
-- Source: XIUI handlers/debuffhandler.lua (commit 136d08a), GPL-3.0 (https://github.com/tirem/XIUI), itself from
-- mousseng's XITools. Durations: modules/mobdebuff_data.lua. Changes: retail durations only (no Horizon overlay),
-- no song+ settings (songs count +0), goomui packet / draw glue at the end.
-- The client is never sent a mob's debuffs: lands are read off 0x028, wear-offs and deaths off 0x029, so
-- timers are estimates; a '?' marks one inferred from a hit (the second resist roll is hidden).
require('common');
local SPELL_TO_DEBUFF = { -- XIUI libs/bufftable.lua spellToDebuff
    [230] = 135, --bio
    [23] = 134, --dia
    [24] = 134, --dia_II
    [25] = 134, --dia_III
    [58] = 4, --paralyze
    [80] = 4, --paralyze_II
    [56] = 13, --slow
    [79] = 13, --slow_II
    [357] = 13, -- slowga
    [216] = 12, --gravity
    [217] = 12, --gravity_II
    [254] = 5, --blind
    [276] = 5, --blind_II
    [361] = 5, --blindga
    [59] = 6, --silence
    [359] = 6, --silencega
    [253] = 2, --sleep
    [259] = 19, --sleep_II
    [273] = 2, --sleepga
    [274] = 19, --sleepga_II
    [258] = 11, --bind
    [362] = 11, --bindga
    [252] = 10, --stun
    [220] = 3, --poison
    [221] = 3, --poison_II
    [222] = 3, --poison_III
    [223] = 3, --poison_IV
    [224] = 3, --poison_V
    [225] = 3, --poisonga
    [226] = 3, --poisonga_II
    [227] = 3, --poisonga_III
    [228] = 3, --poisonga_IV
    [229] = 3, --poisonga_V
    [239] = 132, --shock
    [238] = 131, --rasp
    [237] = 130, --choke
    [236] = 129, --frost
    [235] = 128, --burn
    [240] = 133, --drown
    [421] = 194, --battlefield_elegy
    [422] = 194, --carnage_elegy
    [423] = 194, --massacre_elegy
    [368] = 192, --requiem_1
    [369] = 192, --requiem_2
    [370] = 192, --requiem_3
    [371] = 192, --requiem_4
    [372] = 192, --requiem_5
    [373] = 192, --requiem_6
    [374] = 192, --requiem_7
    [376] = 193, --horde_lullaby
    [377] = 193, --horde_lullaby_II
    [463] = 193, --foe_lullaby
    [471] = 193, --foe_lullaby_II
    [466] = 14,  --maidens_virelai
    [472] = 223, --pining_nocturne
    [454] = 217, --fire_threnody
    [455] = 217, --ice_threnody
    [456] = 217, --wind_threnody
    [457] = 217, --earth_threnody
    [458] = 217, --lightning_threnody
    [459] = 217, --water_threnody
    [460] = 217, --light_threnody
    [461] = 217, --dark_threnody
    [871] = 217, --fire_threnody_II
    [872] = 217, --ice_threnody_II
    [873] = 217, --wind_threnody_II
    [874] = 217, --earth_threnody_II
    [875] = 217, --lightning_threnody_II
    [876] = 217, --water_threnody_II
    [877] = 217, --light_threnody_II
    [878] = 217, --dark_threnody_II
    [597] = 13,  --sprout_smack
    [513] = 3,   --venom_shell
    [515] = 136, --maelstrom
    [524] = 146, --sandspin
    [531] = 11,  --ice_break
    [532] = 10,  --blitzstrahl
    [534] = 12,  --mysterious_light
    [535] = 129, --cold_wave
    [536] = 3,   --poison_breath
    [537] = 138, --stinking_gas
    [539] = 147, --terror_touch
    [548] = 13,  --filamented_hold
    [555] = 12,  --magnetite_cloud
    [561] = 149, --frightful_roar
    [563] = 5,   --hecatomb_wave
    [565] = 13,  --radiant_breath
    [572] = 140, --sound_blast
    [575] = 28,  --jettatura
    [576] = 2,   --yawn
    [582] = 6,   --chaotic_eye
    [584] = 2,   --sheep_song
    [588] = 31,  --lowing
    [596] = 2,   --pinecone_bomb
    [598] = 2,   --soporific
    [599] = 3,   --queasyshroom
    [603] = 138, --wild_oats
    [604] = 13,  --bad_breath
    [606] = 136, --awful_eye
    [608] = 4,   --frost_breath
    [610] = 148, --infrasonics
    [611] = 3,   --disseverment
    [612] = 156, --actinic_burst
    [616] = 10,  --temporal_shift
    [618] = 11,  --blastbomb
    [620] = 137, --battle_dance
    [621] = 5,   --sandspray
    [623] = 10,  --head_butt
    [628] = 10,  --frypan
    [633] = 149, --enervation
    [634] = 5,   --light_of_penance
    [638] = 3,   --feather_storm
    [640] = 10,  --tail_slap
    [644] = 4,   --mind_blast
    [648] = 11,  --regurgitation
    [650] = 149, --seedspray
    [651] = 149, --corrosive_ooze
    [652] = 146, --spiral_spin
    [654] = 4,   --sub-zero_smash
    [660] = 13,  --cimicine_discharge
    [669] = 10,  --whirl_of_rage
    [671] = 6,   --auroral_drape
    [675] = 5,   --thermal_pulse
    [678] = 2,   --dream_flower
    [682] = 31,  --delta_thrust
    [687] = 6,   --water_bomb
    [692] = 10,  --sudden_lunge
    [699] = 146, --barbed_crescent
    [703] = 13,  --embalming_earth
    [704] = 4,   --paralyzing_triad
    [705] = 133, --foul_waters
    [707] = 156, --retinal_glare
    [341] = 4,   --jubaku_ichi
    [342] = 4,   --jubaku_ni
    [343] = 4,   --jubaku_san
    [344] = 13,  --hojo_ichi
    [345] = 13,  --hojo_ni
    [346] = 13,  --hojo_san
    [347] = 5,   --kurayami_ichi
    [348] = 5,   --kurayami_ni
    [349] = 5,   --kurayami_san
    [350] = 3,   --dokumori_ichi
    [351] = 3,   --dokumori_ni
    [352] = 3,   --dokumori_san
    [319] = 147, --aisha_ichi (attack down)
    [508] = 168, --yurin_ichi (inhibit tp)
    [286] = 21,  --addle
    [884] = 21,  --addle_II
    [256] = 31,  --virus (plague)
    [257] = 9,   --curse
    [98] = 19,   --repose
    [356] = 4,   --paralyga
    [366] = 12,  --graviga
    [841] = 148, --distract
    [842] = 148, --distract_II
    [882] = 148, --distract_III
    [843] = 404, --frazzle
    [844] = 404, --frazzle_II
    [883] = 404, --frazzle_III
    [255] = 7,   --break
    [365] = 7,   --breakga
    [879] = 597, --inundation
    -- Helix spells (Tier 1)
    [278] = 186, --geohelix
    [279] = 186, --hydrohelix
    [280] = 186, --anemohelix
    [281] = 186, --pyrohelix
    [282] = 186, --cryohelix
    [283] = 186, --ionohelix
    [284] = 186, --noctohelix
    [285] = 186, --luminohelix
    -- Helix II spells (Tier 2)
    [885] = 186, --geohelix_II
    [886] = 186, --hydrohelix_II
    [887] = 186, --anemohelix_II
    [888] = 186, --pyrohelix_II
    [889] = 186, --cryohelix_II
    [890] = 186, --ionohelix_II
    [891] = 186, --noctohelix_II
    [892] = 186, --luminohelix_II
};

local debuffHandler =
T{
    -- All enemies we have seen take a debuff
    enemies = T{};
    -- Feint and similar: debuff lands on next melee/ranged hit from this actor
    pendingOnHit = T{};
};

-- Reusable tables for GetActiveDebuffs to avoid per-frame allocations
-- These are cleared and reused each call instead of creating new tables
local reusableDebuffIds = {};
local reusableDebuffTimes = {};
local reusableDebuffUncertain = {};

-- Status-on = the server said the effect is on the target (no ?).
-- 101 USES is only "entity uses", not a land — keep it out.
local statusOnMes = {[127]=true, [160]=true, [164]=true, [166]=true, [186]=true, [194]=true, [203]=true, [205]=true, [230]=true, [236]=true, [266]=true, [267]=true, [268]=true, [269]=true, [237]=true, [271]=true, [272]=true, [277]=true, [278]=true, [279]=true, [280]=true, [319]=true, [320]=true, [375]=true, [412]=true, [645]=true, [754]=true, [755]=true, [804]=true};
local statusOffMes = {[64]=true, [159]=true, [168]=true, [204]=true, [206]=true, [321]=true, [322]=true, [341]=true, [342]=true, [343]=true, [344]=true, [350]=true, [378]=true, [531]=true, [647]=true, [805]=true, [806]=true};
local deathMes = {[6]=true, [20]=true, [97]=true, [113]=true, [406]=true, [605]=true, [646]=true};
local spellDamageMes = {[2]=true, [252]=true, [264]=true, [265]=true};
-- Physical/ability hits (110 = bash/jump, 185 = WS). Not a per-ability list.
local physicalHitMes = {[103]=true, [110]=true, [185]=true, [187]=true, [238]=true, [242]=true, [317]=true, [802]=true};
-- Messages only job abilities emit (110/317 damage, 127/266/267/319/320 status,
-- 156/323 no effect). Weapon skills use 185/242/189, so these mark an ability id.
local jaOnlyMes = {[110]=true, [127]=true, [156]=true, [266]=true, [267]=true, [317]=true, [319]=true, [320]=true, [323]=true};
local additionalEffectMes = {[160]=true, [164]=true};
-- Ability / WS miss — do not infer a debuff from the action alone.
-- 158 = JA_MISS, 324 = JA_MISS_2 (Light Shot / Feral Howl etc.)
local missMes = {[15]=true, [63]=true, [158]=true, [188]=true, [213]=true, [324]=true, [354]=true};
-- Hits that deal HP damage (wakes Sleep). Healing messages are omitted.
local damageHitMes = {
    [1]=true, [2]=true, [67]=true, [110]=true, [163]=true, [185]=true,
    [187]=true, [229]=true, [252]=true, [264]=true, [265]=true, [317]=true,
    [352]=true, [353]=true, [379]=true, [576]=true, [577]=true, [802]=true,
};
local SLEEP_BUFF_IDS = { 2, 19, 193 };
local BIND_BUFF_ID = 11;
-- "No effect" confirms a matching uncertain debuff is already present (do not refresh timer).
-- Distinct from complete resist / immunity (655), which means the effect is not present.
-- 75 MAGIC_NO_EFFECT, 156 JA_NO_EFFECT, 189 SKILL_NO_EFFECT, 283 NO_EFFECT, 323 JA_NO_EFFECT_2
local noEffectMes = {[75]=true, [156]=true, [189]=true, [283]=true, [323]=true};
local immuneMes = {[655]=true}; -- MagicCompleteResist — target immune / cannot take the effect
-- TP is already spent when 0x028 arrives, so scaled durations assume a 1-hit WS.
local ASSUMED_TP = 1000;
local ALLIANCE_MEMBER_SLOTS = 18;

local BUFF_SABOTEUR = 454;
local BUFF_STYMIE = 494;
local BUFF_DARK_ARTS = 359;
local JOB_BLM = 4;
local JOB_RDM = 5;
local JOB_BRD = 10;
local JOB_SCH = 20;
-- Client merit IDs from 0x08C (DSP/LSB group-2 offsets). Packet stores upgrade count.
local MERIT_ENFEEBLING_MAGIC_DURATION = 0x090C;
local MERIT_ELEMENTAL_DEBUFF_DURATION = 0x08D2;
-- tHotBar 0x08D category index is 0-based (menu order; 0x2/0x1 swapped in LSB).
local JP_RDM_STYMIE_EFFECT = 2;
local JP_RDM_ENFEEBLE_DURATION = 7;
local JP_BRD_LULLABY_DURATION = 7;
local JP_SCH_DARK_ARTS_EFFECT = 3;
local BRD_SONG_DURATION_GIFT_JP = 1200;
local BRD_SONG_DURATION_GIFT_PCT = 5;

local meritCounts = {};
local jobPointCategories = {};

local function CloneDurationEntry(entry)
    local copy = {};
    for k, v in pairs(entry) do
        copy[k] = v;
    end
    return copy;
end

local durations = require('modules/mobdebuff_data');

local SPELL_DURATIONS = durations.spells;
local WEAPON_SKILL_DURATIONS = durations.weaponSkills or {};
local JA_PHYSICAL_DURATIONS = durations.jaPhysical;
local JA_DURATIONS = durations.ja;
local PET_DURATIONS = durations.pet;
local ADDITIONAL_EFFECT_DURATIONS = durations.additionalEffect;
local ON_HIT_DURATIONS = durations.onHit or {};
local MOB_BUFF_DURATIONS = durations.mobBuff or {};

-- Longest known duration per buff (spells/JA/WS/pets). Unknown status-on uses this, not bolt AE times.
local STATUS_MAX_DURATIONS = {};
local function RecordMaxDuration(data)
    if type(data) ~= 'table' or type(data.duration) ~= 'number' then return; end
    local function consider(buffId)
        if buffId ~= nil and (STATUS_MAX_DURATIONS[buffId] == nil or data.duration > STATUS_MAX_DURATIONS[buffId]) then
            STATUS_MAX_DURATIONS[buffId] = data.duration;
        end
    end
    consider(data.buffId);
    if data.buffIds then
        for i = 1, #data.buffIds do
            consider(data.buffIds[i]);
        end
    end
end
local function RecordTableMax(tbl)
    if not tbl then return; end
    for _, data in pairs(tbl) do
        RecordMaxDuration(data);
    end
end
RecordTableMax(SPELL_DURATIONS);
RecordTableMax(WEAPON_SKILL_DURATIONS);
RecordTableMax(JA_PHYSICAL_DURATIONS);
RecordTableMax(JA_DURATIONS);
RecordTableMax(PET_DURATIONS);

local function UnknownStatusDuration(buffId)
    local maxDur = STATUS_MAX_DURATIONS[buffId];
    if maxDur then return maxDur; end
    if MOB_BUFF_DURATIONS[buffId] then return MOB_BUFF_DURATIONS[buffId]; end
    local aeData = ADDITIONAL_EFFECT_DURATIONS[buffId];
    return aeData and aeData.duration or 30;
end

local function PlayerHasBuff(buffId)
    local buffs = AshitaCore:GetMemoryManager():GetPlayer():GetBuffs();
    if not buffs then return false; end
    for _, b in pairs(buffs) do
        if b == buffId then return true; end
    end
    return false;
end

local function GetMainJob()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return 0; end
    return player:GetMainJob() or 0;
end

local function GetMeritCount(meritId)
    return meritCounts[meritId] or 0;
end

local function GetJobPointCount(job, categoryIndex)
    local jobTable = jobPointCategories[job];
    if not jobTable then return 0; end
    return jobTable[categoryIndex + 1] or 0;
end

local function GetJobPointsSpent(job)
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if not player then return 0; end
    return player:GetJobPointsSpent(job) or 0;
end

local function GetLocalPetServerId()
    local mem = AshitaCore:GetMemoryManager();
    if not mem then return nil; end
    local party = mem:GetParty();
    local entity = mem:GetEntity();
    if not party or not entity then return nil; end
    local playerIndex = party:GetMemberTargetIndex(0);
    if not playerIndex or playerIndex == 0 then return nil; end
    local petIndex = entity:GetPetTargetIndex(playerIndex);
    if not petIndex or petIndex == 0 then return nil; end
    return entity:GetServerId(petIndex);
end

local function IsOwnActor(actorId)
    if actorId == nil then return false; end
    local mem = AshitaCore:GetMemoryManager();
    if not mem then return false; end
    local party = mem:GetParty();
    if party and party:GetMemberServerId(0) == actorId then
        return true;
    end
    return GetLocalPetServerId() == actorId;
end

local function IsAllianceActor(actorId)
    if actorId == nil then return false; end
    if IsOwnActor(actorId) then return true; end
    local mem = AshitaCore:GetMemoryManager();
    local party = mem and mem:GetParty();
    if not party then return false; end
    for memIdx = 0, ALLIANCE_MEMBER_SLOTS - 1 do
        if party:GetMemberIsActive(memIdx) ~= 0 and party:GetMemberServerId(memIdx) == actorId then
            return true;
        end
    end
    return false;
end

local function ResolveDuration(spellData, isOwnActor)
    local duration = spellData.duration or 0;
    if not isOwnActor then
        return duration;
    end

    if spellData.songFamily then
        -- Virelai skips song-duration gifts (LSB calculateSongDuration).
        local giftPct = 0;
        if spellData.songFamily ~= 'songPlusVirelai' and GetMainJob() == JOB_BRD and GetJobPointsSpent(JOB_BRD) >= BRD_SONG_DURATION_GIFT_JP then
            giftPct = BRD_SONG_DURATION_GIFT_PCT;
        end
        duration = math.floor(duration * (1 + giftPct / 100));
        if spellData.songFamily == 'songPlusLullaby' and GetMainJob() == JOB_BRD then
            duration = duration + GetJobPointCount(JOB_BRD, JP_BRD_LULLABY_DURATION);
        end
        return duration;
    end

    if spellData.kind == 'enfeeble' then
        if PlayerHasBuff(BUFF_SABOTEUR) then
            duration = math.floor(duration * 2);
        end
        if GetMainJob() == JOB_RDM then
            duration = duration + (GetMeritCount(MERIT_ENFEEBLING_MAGIC_DURATION) * 6);
            duration = duration + GetJobPointCount(JOB_RDM, JP_RDM_ENFEEBLE_DURATION);
            if PlayerHasBuff(BUFF_STYMIE) then
                duration = duration + GetJobPointCount(JOB_RDM, JP_RDM_STYMIE_EFFECT);
            end
        end
        return duration;
    end

    if spellData.kind == 'elemental' then
        if GetMainJob() == JOB_BLM then
            duration = duration + (GetMeritCount(MERIT_ELEMENTAL_DEBUFF_DURATION) * 12);
        end
        return duration;
    end

    if spellData.kind == 'helix' then
        if PlayerHasBuff(BUFF_DARK_ARTS) then
            duration = duration + (3 * GetJobPointCount(JOB_SCH, JP_SCH_DARK_ARTS_EFFECT));
        end
        return duration;
    end

    return duration;
end

-- goomui: each debuff keeps the order it first landed in (seq), so icons never reshuffle; a refresh keeps its place.
local debuffSeq = 0;
local function ApplyBuffExpiry(targetDebuffs, buffId, expiry, uncertain)
    if buffId == nil or buffId == 0 then return; end
    -- Sleep I/II/Lullaby share one server slot (mutually exclusive). Clear the
    -- other sleep icons so a target only ever shows the active one.
    if buffId == 2 or buffId == 19 or buffId == 193 then
        for i = 1, #SLEEP_BUFF_IDS do
            local sid = SLEEP_BUFF_IDS[i];
            if sid ~= buffId then targetDebuffs[sid] = nil; end
        end
    end
    local prev = targetDebuffs[buffId];
    local seq = (type(prev) == 'table') and prev.seq or nil;
    if seq == nil then debuffSeq = debuffSeq + 1; seq = debuffSeq; end
    targetDebuffs[buffId] = { expiry = expiry, uncertain = uncertain == true, seq = seq };
end

-- Status already present ("no effect"): upgrade uncertain -> certain without refreshing timer.
local function ConfirmUncertainDebuff(targetDebuffs, buffId, now)
    if buffId == nil or buffId == 0 then return; end
    local prev = targetDebuffs[buffId];
    if type(prev) == 'table' and prev.uncertain and prev.expiry and prev.expiry >= now then
        prev.uncertain = false;
    end
end

-- Immunity / complete resist: effect cannot be on the target — clear tracked entry.
local function ClearTrackedDebuff(targetDebuffs, buffId)
    if buffId == nil or buffId == 0 then return; end
    targetDebuffs[buffId] = nil;
end

local function ClearSleepDebuffs(targetDebuffs)
    for i = 1, #SLEEP_BUFF_IDS do
        targetDebuffs[SLEEP_BUFF_IDS[i]] = nil;
    end
end

local function SpellHasBuff(spellData, buffId)
    if spellData == nil or buffId == nil then return false; end
    if spellData.buffIds then
        for i = 1, #spellData.buffIds do
            if spellData.buffIds[i] == buffId then return true; end
        end
        return false;
    end
    return spellData.buffId == buffId;
end

-- Low 16 bits are the action id. 512-1023 is Ashita's JA resource range.
-- Type 11 must not subtract 512: 688-695 are 2-hour mob skills.
local function PacketParamId(id)
    return bit.band(id or 0, 0xFFFF);
end

local function JobAbilityId(id)
    id = PacketParamId(id);
    if id >= 512 and id < 1024 then
        return id - 512;
    end
    return id;
end

local function ResolveActionBuffIds(actionType, spellId, abilityParam, isJobAbility)
    local ids = {};
    if abilityParam ~= nil and abilityParam ~= 0 then
        ids[#ids + 1] = abilityParam;
        return ids;
    end
    if actionType == 4 then
        local buffId = SPELL_TO_DEBUFF[spellId];
        if buffId ~= nil and buffId ~= 0 then
            ids[#ids + 1] = buffId;
        end
        return ids;
    end
    spellId = PacketParamId(spellId);
    local jaId = JobAbilityId(spellId);
    local data;
    if actionType == 3 and isJobAbility then
        -- Ability id in a type 3 packet: never fall back to weapon skills.
        data = JA_DURATIONS[jaId] or JA_PHYSICAL_DURATIONS[jaId];
    elseif actionType == 3 then
        data = WEAPON_SKILL_DURATIONS[spellId] or JA_PHYSICAL_DURATIONS[jaId];
    elseif actionType == 6 or actionType == 14 then
        data = JA_DURATIONS[jaId] or JA_DURATIONS[spellId];
    elseif actionType == 13 then
        data = PET_DURATIONS[spellId] or PET_DURATIONS[jaId];
    else
        data = JA_DURATIONS[spellId] or JA_PHYSICAL_DURATIONS[spellId] or PET_DURATIONS[spellId]
            or JA_DURATIONS[jaId] or JA_PHYSICAL_DURATIONS[jaId] or PET_DURATIONS[jaId]
            or WEAPON_SKILL_DURATIONS[spellId];
    end
    if data then
        if data.buffIds then
            for _, id in ipairs(data.buffIds) do
                ids[#ids + 1] = id;
            end
        elseif data.buffId then
            ids[#ids + 1] = data.buffId;
        end
    end
    return ids;
end

-- 0x028 is sent after SpendCost; party TP is 0 or a stale 0x0DD value.
-- Treat <100 as unknown so tpPer500 stuns are not applied as 0s.
local function GetActorTp(actorId)
    if actorId == nil then return nil; end
    local mem = AshitaCore:GetMemoryManager();
    if not mem then return nil; end
    local party = mem:GetParty();
    if not party then return nil; end
    for memIdx = 0, ALLIANCE_MEMBER_SLOTS - 1 do
        if party:GetMemberIsActive(memIdx) ~= 0 then
            if party:GetMemberServerId(memIdx) == actorId then
                local tp = party:GetMemberTP(memIdx);
                if tp ~= nil and tp >= 100 then
                    return tp;
                end
                return nil;
            end
        end
    end
    return nil;
end

local function ResolveTpTierDuration(tpTier, tp)
    for i = #tpTier, 1, -1 do
        if tp >= tpTier[i][1] then
            return tpTier[i][2];
        end
    end
    if tpTier[1][1] > 0 then
        return math.floor(tpTier[1][2] * tp / tpTier[1][1]);
    end
    return tpTier[1][2];
end

local function ResolveTpDuration(wsData, tp)
    if wsData.duration then
        return wsData.duration;
    end
    if wsData.tpTier then
        return ResolveTpTierDuration(wsData.tpTier, tp);
    end
    if wsData.tpFTP then
        local anchors = wsData.tpFTP;
        if tp >= 3000 then
            return anchors[3];
        elseif tp >= 2000 then
            return math.floor(anchors[2] + (anchors[3] - anchors[2]) * (tp - 2000) / 1000);
        elseif tp >= 1000 then
            return math.floor(anchors[1] + (anchors[2] - anchors[1]) * (tp - 1000) / 1000);
        end
        return math.floor(anchors[1] * tp / 1000);
    end
    if wsData.tpPer500 then
        return math.floor(tp / 500);
    end
    local formula = wsData.tpDuration or wsData;
    local duration = formula.base or 0;
    if formula.per100Tp then
        duration = duration + formula.per100Tp * tp / 100;
    end
    if formula.per1000Tp then
        duration = duration + formula.per1000Tp * tp / 1000;
    end
    if formula.per200Tp then
        duration = duration + formula.per200Tp * tp / 200;
    end
    return math.floor(duration);
end

local function ResolveWeaponSkillDuration(wsData, actorId)
    local tp = GetActorTp(actorId) or ASSUMED_TP;
    return ResolveTpDuration(wsData, tp);
end

local function UsesTpDuration(data)
    return data.tpTier ~= nil or data.tpDuration ~= nil or data.tpFTP ~= nil or data.tpPer500 ~= nil;
end

-- Non-spell Param lookup. Order matters for id collisions (e.g. Invincible vs Energy Drain).
local function LookupNonSpell(id, actionType)
    if actionType == 3 then
        return WEAPON_SKILL_DURATIONS[id] or JA_PHYSICAL_DURATIONS[id];
    end
    if actionType == 6 or actionType == 14 then
        return JA_DURATIONS[id] or JA_PHYSICAL_DURATIONS[id];
    end
    return JA_DURATIONS[id] or JA_PHYSICAL_DURATIONS[id] or PET_DURATIONS[id];
end

-- Type 4 is spells-only so BLU ids do not collide with 2-hours or weapon skills.
local function GetDurationData(actionType, id, isJobAbility)
    id = PacketParamId(id);
    local jaId = JobAbilityId(id);
    if actionType == 4 then
        return SPELL_DURATIONS[id];
    end
    if actionType == 3 then
        -- Damaging/enfeebling JAs also arrive as type 3, so an ability id must never
        -- resolve against weapon skills (Jump 66 vs Gale Axe, Angon 170 vs Randgrith).
        if isJobAbility then
            return JA_DURATIONS[jaId] or JA_PHYSICAL_DURATIONS[jaId];
        end
        return WEAPON_SKILL_DURATIONS[id] or JA_PHYSICAL_DURATIONS[jaId];
    end
    if actionType == 6 or actionType == 14 then
        -- Physical JAs (Angon/Shield Bash) may arrive as type 6; keep out of WS id collisions.
        return JA_DURATIONS[jaId] or JA_DURATIONS[id]
            or JA_PHYSICAL_DURATIONS[jaId] or JA_PHYSICAL_DURATIONS[id];
    end
    if actionType == 13 then
        return PET_DURATIONS[id] or PET_DURATIONS[jaId];
    end
    if actionType == 11 then
        return LookupNonSpell(id, actionType) or SPELL_DURATIONS[id];
    end
    return SPELL_DURATIONS[id] or LookupNonSpell(id, actionType) or LookupNonSpell(jaId, actionType);
end

-- Hidden second roll after a connecting hit (BLU onDamage / bash / resistable WS).
-- Returns the ? flag, or nil to skip (visible AE or wait for status-on).
local function HiddenSecondaryMarker(data, additionalEffect, defaultHidden)
    if not data then return nil; end
    if data.certainOnHit then return false; end
    if additionalEffect ~= nil then return nil; end
    if defaultHidden or data.uncertain or data.onDamage then return true; end
    return nil;
end

-- uncertain is only "inferred from a hit". Confirmed lands pass false.
local function ApplySpellData(targetDebuffs, spellData, isOwnActor, now, packetBuffId, uncertain)
    local expiry = now + ResolveDuration(spellData, isOwnActor);
    if spellData.clearsBuffs then
        for _, clearBuffId in ipairs(spellData.clearsBuffs) do
            targetDebuffs[clearBuffId] = nil;
        end
    end
    -- onDamage AEs land one buff per message. Magical multi-enfeeble (Enervation) lands together.
    if spellData.buffIds and not spellData.onDamage then
        local perBuff = spellData.buffDurations;
        for _, buffId in ipairs(spellData.buffIds) do
            -- Some actions land two statuses on different timers (Blade Bash stun vs plague).
            local own = perBuff and perBuff[buffId];
            ApplyBuffExpiry(targetDebuffs, buffId, own and (now + own) or expiry, uncertain);
        end
        return;
    end
    -- The table's buffId is the intended status, since the packet param can carry
    -- unrelated values (damage). Trust the param only when it names one of this
    -- action's own statuses, which is how a multi-status onDamage row lands.
    local buffId = spellData.displayBuffId;
    if buffId == nil and SpellHasBuff(spellData, packetBuffId) then
        buffId = packetBuffId;
    end
    ApplyBuffExpiry(targetDebuffs, buffId or spellData.buffId or packetBuffId, expiry, uncertain);
end

-- uncertain: true when the WS secondary is inferred (no land message).
local function ApplyWeaponSkillData(targetDebuffs, wsData, actorId, now, uncertain)
    local duration = ResolveWeaponSkillDuration(wsData, actorId);
    if wsData.certainOnHit then
        uncertain = false;
    elseif uncertain == nil then
        uncertain = true;
    end
    local entry = CloneDurationEntry(wsData);
    entry.duration = duration;
    ApplySpellData(targetDebuffs, entry, false, now, nil, uncertain);
end

-- applyOnDamage: certain land on the damage message.
-- onDamage: BLU secondary lands silently, so infer it whenever damage landed.
-- An AE block on the same packet is an unrelated proc, handled separately.
local function ApplyType4Damage(targetDebuffs, spellData, isOwnActor, now, damage)
    if not spellData then return; end
    if spellData.onDamage then
        if (damage or 0) > 0 then
            ApplySpellData(targetDebuffs, spellData, isOwnActor, now, nil, true);
        end
        return;
    end
    if spellData.applyOnDamage then
        ApplySpellData(targetDebuffs, spellData, isOwnActor, now, nil, false);
    end
end

local function ApplyPacketAdditionalEffect(targetDebuffs, spellData, isOwnActor, now, buffId)
    if buffId == nil then return; end
    if SpellHasBuff(spellData, buffId) then
        local landed = CloneDurationEntry(spellData);
        landed.buffIds = nil;
        landed.buffId = buffId;
        ApplySpellData(targetDebuffs, landed, isOwnActor, now, buffId, false);
        return;
    end
    local prev = targetDebuffs[buffId];
    local prevExpiry = prev and prev.expiry;
    local prevCertain = prev and prevExpiry and prevExpiry >= now and not prev.uncertain;
    local aeData = ADDITIONAL_EFFECT_DURATIONS[buffId];
    local newExpiry = now + (aeData and aeData.duration or 30);
    if prevCertain and prevExpiry >= newExpiry then return; end
    local expiry = newExpiry;
    if prevExpiry and prevExpiry > expiry then expiry = prevExpiry; end
    ApplyBuffExpiry(targetDebuffs, buffId, expiry, false);
end

-- Feint and friends arm a debuff for the next melee hit. They are self-targeted,
-- so this has to run before the enemy-only filter in ApplyMessage.
local function ArmOnHitAbility(action, message, now)
    if action.category ~= 6 and action.category ~= 14 then return; end
    if missMes[message] then return; end

    local onHitData = ON_HIT_DURATIONS[JobAbilityId(action.param)];
    if onHitData == nil then return; end

    debuffHandler.pendingOnHit[action.actor] = {
        buffId = onHitData.buffId,
        duration = onHitData.duration,
        expires = now + (onHitData.window or 60),
    };
end

local function ApplyMessage(debuffs, action)

    if (action == nil) then
        return;
    end

    local now = os.time()
    local actorId = action.actor;
    -- Constant for the whole packet; resolve once instead of per target.
    local isOwnActor = IsOwnActor(actorId);

    for _, target in pairs(action.targets) do
        for _, ability in pairs(target.results) do
            ArmOnHitAbility(action, ability.message, now);
        end
    end

    for _, target in pairs(action.targets) do
        -- Only track effects landing on enemies. Buffs/rolls/songs on alliance
        -- members (or self) are not enemy debuffs and must not pollute this table.
        if not IsAllianceActor(target.id) then
            for _, ability in pairs(target.results) do

                local spell = PacketParamId(action.param);
                local message = ability.message
                local additionalEffect

                if (ability.proc ~= nil and ability.proc.message ~= nil) then
                    additionalEffect = ability.proc.message
                end

                if (debuffs[target.id] == nil) then
                    debuffs[target.id] = T{};
                end

                local targetDebuffs = debuffs[target.id];
                local isJobAbility = jaOnlyMes[message];
                local spellData = GetDurationData(action.category, spell, isJobAbility);

                -- Damage wakes Sleep and usually breaks Bind; this action may re-apply
                -- either effect afterward. A blocked or 0-damage hit does not trigger
                -- this inference, so require actual damage.
                if damageHitMes[message] and (ability.value or 0) > 0 then
                    ClearSleepDebuffs(targetDebuffs);
                    ClearTrackedDebuff(targetDebuffs, BIND_BUFF_ID);
                end

                -- Type 1 melee only: Feint applies on regular melee hits (not ranged, not WS).
                if action.category == 1 and physicalHitMes[message] then
                    local pending = debuffHandler.pendingOnHit[actorId];
                    if pending and pending.expires > now then
                        -- Guaranteed on connecting melee hit (including 0 dmg / countered).
                        ApplyBuffExpiry(targetDebuffs, pending.buffId, now + pending.duration, false);
                        debuffHandler.pendingOnHit[actorId] = nil;
                    end
                -- Type 3 WS or physical JA on a hit
                elseif action.category == 3 and physicalHitMes[message] then
                    local jaId = JobAbilityId(spell);
                    -- A 512+id param or a JA-only message means an ability, so keep it out
                    -- of the weapon skill rows its raw id would otherwise match.
                    local jaPhys = (isJobAbility or spell ~= jaId) and JA_PHYSICAL_DURATIONS[jaId] or nil;
                    local wsData = (not isJobAbility and not jaPhys) and WEAPON_SKILL_DURATIONS[spell] or nil;
                    if jaPhys then
                        local marker = HiddenSecondaryMarker(jaPhys, additionalEffect, false);
                        if marker ~= nil then
                            ApplySpellData(targetDebuffs, jaPhys, isOwnActor, now, nil, marker);
                        end
                    elseif wsData then
                        local marker = HiddenSecondaryMarker(wsData, additionalEffect, true);
                        if marker ~= nil then
                            ApplyWeaponSkillData(targetDebuffs, wsData, actorId, now, marker);
                        end
                    elseif spellData then
                        local marker = HiddenSecondaryMarker(spellData, additionalEffect, false);
                        if marker ~= nil then
                            ApplySpellData(targetDebuffs, spellData, isOwnActor, now, nil, marker);
                        end
                    end
                -- Type 13 pet/blood pact: damaging pacts apply the secondary silently,
                -- so infer it on the hit. Confirmed lands go through status-on below.
                elseif action.category == 13 and physicalHitMes[message] then
                    local marker = HiddenSecondaryMarker(spellData, additionalEffect, true);
                    if marker ~= nil then
                        ApplySpellData(targetDebuffs, spellData, isOwnActor, now, nil, marker);
                    end
                elseif action.category == 4 and spellDamageMes[message] then
                    ApplyType4Damage(targetDebuffs, spellData, isOwnActor, now, ability.value);
                elseif statusOnMes[message] then
                    local buffId = ability.value;
                    if buffId == nil or buffId == 0 then
                        buffId = action.category == 4 and SPELL_TO_DEBUFF[spell] or nil;
                    end
                    local wsData = (action.category == 3 and not isJobAbility)
                        and WEAPON_SKILL_DURATIONS[spell] or nil;
                    if wsData or (spellData and UsesTpDuration(spellData)) then
                        ApplyWeaponSkillData(targetDebuffs, wsData or spellData, actorId, now, false);
                    elseif spellData then
                        ApplySpellData(targetDebuffs, spellData, isOwnActor, now, buffId, false);
                    elseif buffId ~= nil then
                        ApplyBuffExpiry(targetDebuffs, buffId, now + UnknownStatusDuration(buffId), false);
                    end
                elseif statusOffMes[message] then
                    if ability.value == 2 then
                        -- Sleep I/II/Lullaby share server slot 2 but are tracked per icon.
                        ClearSleepDebuffs(targetDebuffs);
                    elseif ability.value ~= nil then
                        targetDebuffs[ability.value] = nil
                    end
                -- Confirm ? without refreshing. Only alliance actors.
                elseif noEffectMes[message] then
                    if IsAllianceActor(actorId) then
                        for _, buffId in ipairs(ResolveActionBuffIds(action.category, spell, ability.value, isJobAbility)) do
                            ConfirmUncertainDebuff(targetDebuffs, buffId, now);
                        end
                    end
                elseif immuneMes[message] then
                    for _, buffId in ipairs(ResolveActionBuffIds(action.category, spell, ability.value, isJobAbility)) do
                        ClearTrackedDebuff(targetDebuffs, buffId);
                    end
                -- Type 11: mob skills. Only apply when we have mapped data for the
                -- skill; the packet Param is a status id for buffs but a damage value
                -- for attacks, so we can't safely infer unmapped skills.
                elseif action.category == 11 and not missMes[message] then
                    if spellData then
                        ApplySpellData(targetDebuffs, spellData, isOwnActor, now, ability.value, false);
                    end
                -- Type 6 / 14: bash-style physical JA inferred from a hit.
                -- Do not apply ja[] on "uses" — lands are status-on (e.g. Light Shot 127).
                elseif (action.category == 6 or action.category == 14) and physicalHitMes[message] and not missMes[message] then
                    local jaId = JobAbilityId(spell);
                    local jaPhys = JA_PHYSICAL_DURATIONS[jaId] or JA_PHYSICAL_DURATIONS[spell];
                    local marker = HiddenSecondaryMarker(jaPhys, additionalEffect, false);
                    if marker ~= nil then
                        ApplySpellData(targetDebuffs, jaPhys, isOwnActor, now, nil, marker);
                    end
                end

                if additionalEffect ~= nil and additionalEffectMes[additionalEffect] then
                    ApplyPacketAdditionalEffect(targetDebuffs, spellData, isOwnActor, now, ability.proc.value);
                end
            end
        end
        local td = debuffs[target.id];
        if (td ~= nil and next(td) == nil) then debuffs[target.id] = nil; end
    end
end

local function ClearMessage(debuffs, basic)
    -- if we're tracking a mob that dies, reset its status
    if deathMes[basic.message] and debuffs[basic.target] then
        debuffs[basic.target] = nil
    elseif (basic.message == 321) then --Custom Chi Blast dispel message
        if (debuffs[basic.target] == nil or basic.value == nil) then
            return
        end

        debuffs[basic.target][basic.value] = nil
    elseif statusOffMes[basic.message] then
        if debuffs[basic.target] == nil then
            return
        end

        -- Clear the buffid that just wore off
        if (basic.param ~= nil) then
            if (basic.param == 2) then --Sleep/Lullaby Handling
                ClearSleepDebuffs(debuffs[basic.target]);
            else
                debuffs[basic.target][basic.param] = nil
            end
        end
    end
end

-- Merits (0x08C) and job points (0x08D) feed the duration bonuses.
local function points_packet(e)
    if (e.id == 0x08C) then
        local meritNum = struct.unpack('B', e.data, 0x04 + 1);
        for i = 1, meritNum, 1 do
            local meritId = struct.unpack('H', e.data, 0x04 + (4 * i) + 1);
            local meritCount = struct.unpack('B', e.data, 0x04 + (4 * i) + 0x03 + 1);
            meritCounts[meritId] = meritCount;
        end
    elseif (e.id == 0x08D) then
        local jobPointCount = (e.size / 4) - 1;
        for i = 1, jobPointCount, 1 do
            local offset = i * 4;
            local index = ashita.bits.unpack_be(e.data_raw, offset, 0, 5);
            local job = ashita.bits.unpack_be(e.data_raw, offset, 5, 11);
            local count = ashita.bits.unpack_be(e.data_raw, offset + 3, 2, 6);
            if job ~= 0 then
                if jobPointCategories[job] == nil then
                    jobPointCategories[job] = {};
                end
                jobPointCategories[job][index + 1] = count;
            end
        end
    end
end

function debuffHandler.clear()
    debuffHandler.enemies = {};
    debuffHandler.pendingOnHit = T{};
end

debuffHandler.GetActiveDebuffs = function(serverId)
    if (debuffHandler.enemies[serverId] == nil) then
        return nil
    end

    local count = 0;
    for i = 1, #reusableDebuffIds do
        reusableDebuffIds[i] = nil;
        reusableDebuffTimes[i] = nil;
    end
    for k in pairs(reusableDebuffUncertain) do
        reusableDebuffUncertain[k] = nil;
    end

    local currentTime = os.time();
    for buffId, entry in pairs(debuffHandler.enemies[serverId]) do
        local expiryTime = entry and entry.expiry;
        if expiryTime ~= nil and expiryTime > currentTime then
            count = count + 1;
            reusableDebuffIds[count] = buffId;
            reusableDebuffTimes[count] = expiryTime - currentTime;
            if entry.uncertain then
                reusableDebuffUncertain[buffId] = true;
            end
        else
            -- Drop dead entries so a recycled server id can't inherit them.
            debuffHandler.enemies[serverId][buffId] = nil;
        end
    end

    if count == 0 then
        return nil;
    end

    -- goomui: pairs() order is not stable; sort by first-landed order (insertion sort, a handful of entries).
    local tracked = debuffHandler.enemies[serverId];
    for i = 2, count do
        local id, t = reusableDebuffIds[i], reusableDebuffTimes[i];
        local sq = tracked[id].seq or 0;
        local j = i - 1;
        while j >= 1 and (tracked[reusableDebuffIds[j]].seq or 0) > sq do
            reusableDebuffIds[j + 1], reusableDebuffTimes[j + 1] = reusableDebuffIds[j], reusableDebuffTimes[j];
            j = j - 1;
        end
        reusableDebuffIds[j + 1], reusableDebuffTimes[j + 1] = id, t;
    end

    return reusableDebuffIds, reusableDebuffTimes, reusableDebuffUncertain;
end


------------------------------------------------------------
-- goomui glue: packets in, icons drawn in the target panel
------------------------------------------------------------
local ffi   = require('ffi');
local d3d8  = require('d3d8');
local imgui = require('imgui');
local theme = require('modules/theme');
local ui    = require('modules/ui');
local parse_action = require('modules/action');
local dupes = require('modules/dupes'); -- resent 0x028 (modules/dupes.lua)

-- 0x029 (XiPackets world/server/0x0029): UniqueNoCas, UniqueNoTar, Data, Data2, ActIndexCas, ActIndexTar, MessageNum.
local function parse_message(d)
    return {
        sender  = struct.unpack('I4', d, 0x04 + 1), target = struct.unpack('I4', d, 0x08 + 1),
        param   = struct.unpack('I4', d, 0x0C + 1), value  = struct.unpack('I4', d, 0x10 + 1),
        message = struct.unpack('H',  d, 0x18 + 1),
    };
end

function debuffHandler.packet_in(e)
    local id = e.id;
    if (id == 0x028) then
        if (dupes.repeated(e)) then return; end
        local ok, a = pcall(parse_action, e);
        if (ok and a ~= nil) then ApplyMessage(debuffHandler.enemies, a); end
    elseif (id == 0x029) then
        ClearMessage(debuffHandler.enemies, parse_message(e.data));
    elseif (id == 0x00A) then
        debuffHandler.clear();
    elseif (id == 0x08C or id == 0x08D) then
        points_packet(e);
    end
end

-- Status icons from the client's resources (as party.lua getIcon), as imgui texture ids.
local ICON_OVERRIDE = { [623] = 62 }; -- XIUI: Rampart's icon is the BCNM one, Sentinel's used
local icons = {};
local function icon(id)
    local e = icons[id];
    if (e ~= nil) then return e or nil; end
    icons[id] = false;
    local dev = d3d8.get_device();
    local res = AshitaCore:GetResourceManager():GetStatusIconByIndex(ICON_OVERRIDE[id] or id);
    if (dev == nil or res == nil or res.Bitmap == nil or res.ImageSize == nil or res.ImageSize <= 0) then return nil; end
    local tp = ffi.new('IDirect3DTexture8*[1]');
    if (ffi.C.D3DXCreateTextureFromFileInMemoryEx(dev, res.Bitmap, res.ImageSize, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, tp) ~= ffi.C.S_OK) then
        return nil;
    end
    local tex = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', tp[0]));
    e = { tex = tex, ptr = tonumber(ffi.cast('uint32_t', tex)) };
    icons[id] = e;
    return e;
end

local function fmt(s)
    if (s >= 3600) then return string.format('%dh', math.floor(s / 3600)); end
    if (s >= 60) then return string.format('%dm', math.floor(s / 60)); end
    return tostring(math.floor(s));
end

local V2, P1, P2, UV0, UV1 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 1, 1 };
local TXT, UNSURE = 0xFFFFFFFF, 0xFF40D0FF; -- ABGR: white timer, amber '?'
function debuffHandler.has(sid)
    return (sid ~= nil and sid ~= 0) and (debuffHandler.GetActiveDebuffs(sid) ~= nil);
end

-- In its panel (above the target panel): icon `size` px, seconds left to its right; as many per row as `width` holds.
-- Fixed cell width (widest timer, '59m') so icons never shift as timers count down.
-- Hover: name (#id), time left, on which mob. Not the client's status description: that is written for the player
-- ("Your attack speed is reduced."), wrong on a mob. The target panel takes
-- no mouse input, so the cursor comes from WM_MOUSEMOVE (modules/ui.lua).
local TIP_DIM, TIP_POS, TIP_PIVOT = { 0.7, 0.7, 0.75, 1 }, { 0, 0 }, { 0, 1 };
local function tooltip(id, left, mob, uncertain)
    local name = AshitaCore:GetResourceManager():GetString('buffs.names', id) or '?';
    left = math.max(0, math.floor(left or 0));
    TIP_POS[1], TIP_POS[2] = ui.mouse_x, ui.mouse_y - 4;
    imgui.SetNextWindowPos(TIP_POS, ImGuiCond_Always, TIP_PIVOT); -- above the cursor (bottom-left corner at it)
    imgui.BeginTooltip();
    imgui.Text(('%s (#%d)'):format(name, id));
    imgui.TextColored(TIP_DIM, ('%d:%02d left (estimate)%s'):format(math.floor(left / 60), left % 60,
        (mob ~= nil and mob ~= '') and (' on ' .. mob) or ''));
    if (uncertain) then imgui.TextColored(TIP_DIM, 'Inferred from a hit: may have been resisted.'); end
    imgui.EndTooltip();
end

function debuffHandler.draw(dl, sid, x_pad, width, size, mob)
    if (dl == nil or sid == nil or sid == 0) then return; end
    local ids, times, unsure = debuffHandler.GetActiveDebuffs(sid);
    if (ids == nil) then return; end
    local n, fs = #ids, imgui.GetFontSize();
    local cellW = size + 2 + imgui.CalcTextSize('59m') + 6;
    local per = math.max(1, math.floor((width + 6) / cellW));
    local rows = math.ceil(n / per);
    local cellH = size + 2;
    imgui.SetCursorPosX(imgui.GetCursorPosX() + x_pad);
    local x0, y0 = imgui.GetCursorScreenPos();
    V2[1], V2[2] = width, rows * cellH - 2;
    imgui.Dummy(V2);
    for i = 1, n do
        local col, row = (i - 1) % per, math.floor((i - 1) / per);
        local x, y = x0 + col * cellW, y0 + row * cellH;
        local ic = icon(ids[i]);
        if (ic ~= nil) then
            P1[1], P1[2], P2[1], P2[2] = x, y, x + size, y + size;
            dl:AddImage(ic.ptr, P1, P2, UV0, UV1, 0xFFFFFFFF);
        end
        theme.text_outlined(dl, x + size + 2, y + (size - fs) / 2, TXT, fmt(times[i] or 0));
        if (unsure and unsure[ids[i]]) then
            theme.text_outlined(dl, x + size - imgui.CalcTextSize('?'), y - 3, UNSURE, '?');
        end
        if (ui.mouse_x >= x and ui.mouse_x < x + cellW and ui.mouse_y >= y and ui.mouse_y < y + size) then
            tooltip(ids[i], times[i], mob, unsure and unsure[ids[i]]);
        end
    end
end

return debuffHandler;
