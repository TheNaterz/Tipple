local _, addon = ...
local Recipients = {}
addon.Recipients = Recipients

local knownFactions = {}

function Recipients.DisplayCharacterName(name)
    return (name:gsub("%-", " "))
end

function Recipients.IsReadable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function MailName(name, realm)
    if not Recipients.IsReadable(name) or not name or name == "" or name == UNKNOWN then return end
    if Recipients.IsReadable(realm) and realm and realm ~= "" and not name:find("-", 1, true) then
        return name .. "-" .. realm:gsub("%s+", "")
    end
    return name
end

function Recipients.CharacterKey(name, realm)
    local character, suffix = name:match("^([^%-]+)%-(.+)$")
    if character then
        name, realm = character, suffix
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if not realm or realm == "" then return end
    return (name .. "-" .. realm:gsub("%s+", "")):lower()
end

function Recipients.UnitFaction(unit)
    local faction = UnitFactionGroup(unit)
    if Recipients.IsReadable(faction) and (faction == "Alliance" or faction == "Horde") then return faction end
end

local function PlayerLocationFaction(location)
    if not Recipients.IsReadable(location) or not location or not location:IsValid() then return end
    local raceID = C_PlayerInfo.GetRace(location)
    if not Recipients.IsReadable(raceID) or not raceID then return end
    local faction = C_CreatureInfo.GetFactionInfo(raceID)
    if Recipients.IsReadable(faction) and faction and Recipients.IsReadable(faction.groupTag) then
        return faction.groupTag
    end
end

local function PlayerMailName(unit)
    local player = UnitIsPlayer(unit)
    local self = UnitIsUnit(unit, "player")
    if Recipients.IsReadable(player) and player and Recipients.IsReadable(self) and not self then
        return MailName(UnitFullName(unit))
    end
end

function Recipients.RecipientFaction(name, savedFaction)
    local key = name:lower()
    local function CheckUnit(unit)
        local unitName = PlayerMailName(unit)
        if unitName and unitName:lower() == key then return Recipients.UnitFaction(unit) end
    end
    local faction = CheckUnit("target") or CheckUnit("focus") or CheckUnit("mouseover")
    if faction then return faction end
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            faction = CheckUnit("raid" .. index)
            if faction then return faction end
        end
    else
        for index = 1, GetNumSubgroupMembers() do
            faction = CheckUnit("party" .. index)
            if faction then return faction end
        end
    end
    return knownFactions[key] or savedFaction
end

function Recipients.IsSameFactionRecipient(tip)
    local playerFaction = Recipients.UnitFaction("player")
    return playerFaction and Recipients.RecipientFaction(tip.name, tip.faction) == playerFaction
end

local function ClubMemberFaction(member, guild)
    if not Recipients.IsReadable(member) or not member then return end
    local faction = member.faction
    if Recipients.IsReadable(faction) then
        if faction == Enum.PvPFaction.Alliance then return "Alliance" end
        if faction == Enum.PvPFaction.Horde then return "Horde" end
        if faction ~= nil then return end
    else
        return
    end
    if Recipients.IsReadable(guild) and guild and Recipients.IsReadable(guild.crossFaction) and guild.crossFaction == false then
        return Recipients.UnitFaction("player")
    end
end

local function GuildRecipientFaction(name)
    if not IsInGuild() then return end
    local clubID = C_Club.GetGuildClubId()
    if not Recipients.IsReadable(clubID) or not clubID then return end
    local memberIDs = C_Club.GetClubMembers(clubID)
    if not Recipients.IsReadable(memberIDs) or not memberIDs then return end
    local key = name:lower()
    for _, memberID in ipairs(memberIDs) do
        if Recipients.IsReadable(memberID) then
            local member = C_Club.GetMemberInfo(clubID, memberID)
            if Recipients.IsReadable(member) and member then
                local memberName = MailName(member.name)
                if memberName and memberName:lower() == key then
                    return ClubMemberFaction(member, C_Club.GetClubInfo(clubID))
                end
            end
        end
    end
end

local function AddTipEntry(_, menu, context)
    if not context or (Recipients.IsReadable(context.isSelf) and context.isSelf) then return end
    local name, faction
    if Recipients.IsReadable(context.unit) and context.unit then
        name = PlayerMailName(context.unit)
        if not name then return end
        faction = Recipients.UnitFaction(context.unit)
        if faction then knownFactions[name:lower()] = faction end
        local friendly = UnitIsFriend("player", context.unit)
        if not Recipients.IsReadable(friendly) or not friendly then return end
    else
        local realm = context.server
        if not Recipients.IsReadable(realm) or not realm or realm == "" then
            realm = context.surname
        end
        name = MailName(context.name, realm)
        if not name then return end
        local playerName = MailName(UnitFullName("player"))
        if playerName and playerName:lower() == name:lower() then return end
        local guild
        if Recipients.IsReadable(context.isGuildMember) and context.isGuildMember then
            guild = context.clubInfo
        end
        faction = ClubMemberFaction(context.clubMemberInfo, guild) or GuildRecipientFaction(name)
        local lineID = Recipients.IsReadable(context.lineID) and tonumber(context.lineID)
        if not faction and lineID and lineID > 0 then
            faction = PlayerLocationFaction(context.playerLocation)
        end
        faction = faction or Recipients.RecipientFaction(name)
    end
    if faction then knownFactions[name:lower()] = faction end
    if faction and faction == Recipients.UnitFaction("player") then
        menu:CreateButton("Tipple", function() addon.Editor.Open(name) end)
    end
end

function Recipients.RegisterMenus()
    for _, tag in ipairs({
        "PLAYER", "PARTY", "PARTY1", "RAID", "RAID_PLAYER",
        "FRIEND", "FRIEND_OFFLINE", "PLAYER_OFFLINE", "CHAT_ROSTER", "COMMUNITIES_MEMBER",
        "COMMUNITIES_GUILD_MEMBER", "GUILD", "GUILD_OFFLINE",
    }) do
        Menu.ModifyMenu("MENU_UNIT_" .. tag, AddTipEntry)
    end
end
