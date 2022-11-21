-- CONSTANTS

local COLOR_LOG = "|cffaad372"
local COLOR_DEBUG = "|cffff7f00"
local COLOR_GOLD = "|cfffed100"
local COLOR_GREEN = "|cff00ff00"
local COLOR_ORANGE = "|cffff7f00"
local COLOR_RESUME = "|r"

local ADDON_NAME = "ThorLockout"
local ADDON_VERSION = "1.0"
local ADDON_IDENTIFIER = ADDON_NAME .. " " .. ADDON_VERSION .. " by Thorinson"

local DATABASE_DEFAULTS = {
	global = {
		characters = {
			['*'] = {
                class = nil,
				lockouts = {}
			}
		}
	}
}

-- FUNCTIONS

local function FormatColor(color, message, ...)
    return color .. string.format(message, ...) .. COLOR_RESUME
end

local function Log(message, ...)
    print(FormatColor(COLOR_LOG, message, ...))
end

local function LogDebug(message, ...)
    print(FormatColor(COLOR_DEBUG, "[" .. ADDON_NAME .. "][DBG] " .. message, ...))
end

local function RoundToNearestHour(seconds)
    local HOUR = 3600
    return floor((seconds / HOUR) + 0.5) * HOUR
end

local function GetCharacterId()
	local realm = GetNormalizedRealmName()
	local name = UnitName("player")

	return format("%s.%s", realm, name)
end

local function GetCharacterClass()
    local classFilename, classId = UnitClassBase("player")
    return classFilename
end

local function FormatProgress(progress, encounters)
    if progress == nil then
        return nil
    end
    local color = (progress == encounters) and COLOR_GREEN or COLOR_ORANGE
    return FormatColor(color, "%i", progress)
end

----- CLASS - Character

local Character = {}
function Character:New(id, class)
    local result = {}
    setmetatable(result, self)
    self.__index = self
    result.id = id
    _, result.name = strsplit('.', result.id)
    result.class = class
    local _, _, _, color = GetClassColor(result.class)
    result.colorName = FormatColor("|c"..color, result.name)
    return result
end

function Character:Less(other)
    return self.name < other.name
end

----- CLASS - Characters

local Characters = {}
function Characters:New()
    local result = {}
    setmetatable(result, self)
    self.__index = self
    result.byId = {}
    result.sorted = {}
    return result
end

function Characters:Add(character)
    self.byId[character.id] = character
    table.insert(self.sorted, character)
    table.sort(self.sorted, function(a, b) return a:Less(b) end)
end

----- CLASS - Raid

local Raid = {}
function Raid:New(name, size, isHeroic, encounters)
    local result = {}
    setmetatable(result, self)
    self.__index = self
    result.name = name
    result.size = size
    result.isHeroic = isHeroic
    result.encounters = encounters
    result.id = string.format("%s %i%s", result.name, result.size, result.isHeroic and "H" or "N")
    return result
end

function Raid:Equal(other)
    return self.name == other.name
        and self.size == other.size
        and self.isHeroic == other.isHeroic
end

function Raid:Less(other)
    return self.name < other.name
        or (self.name == other.name
            and self.size < other.size)
        or (self.name == other.name
            and self.size == other.size
            and not self.isHeroic and other.isHeroic)
end

----- CLASS - Raids

local Raids = {}
function Raids:New()
    local result = {}
    setmetatable(result, self)
    self.__index = self
    result.byId = {}
    result.sorted = {}
    return result
end

function Raids:Add(raid)
    if self.byId[raid.id] ~= nil then
        return false
    end
    self.byId[raid.id] = raid
    table.insert(self.sorted, raid)
    table.sort(self.sorted, function(a, b) return a:Less(b) end)
    return true
end

----- CLASS - ThorLockout

local ThorLockout = {}
LibStub("AceEvent-3.0"):Embed(ThorLockout)

function ThorLockout:GetRaidLockouts()
    local now = GetServerTime()
    local result = {}

	for i = 1, GetNumSavedInstances() do
		local instanceName, instanceID, instanceReset, difficulty, locked, extended, _, isRaid, maxPlayers, difficultyName, 
				numEncounters, encounterProgress, extendDisabled = GetSavedInstanceInfo(i)
        local name, groupType, isHeroic, isChallengeMode, displayHeroic, displayMythic, toggleDifficultyID = GetDifficultyInfo(difficulty)
        local resetTime = RoundToNearestHour(now + instanceReset)

        if isRaid and (instanceReset > 0) then
            table.insert(result, {name=instanceName, size=maxPlayers, isHeroic=isHeroic, progress=encounterProgress, encounters=numEncounters, resetTime=resetTime})
        end
	end

    return result
end

function ThorLockout:ProcessData()
    -- TODO some kind of caching
    -- TODO remove old values

    local characters = Characters:New()
    for id, data in pairs(self.db.global.characters) do
        class = data.class
        characters:Add(Character:New(id, class))
    end

    local raids = Raids:New()
    local lockouts = {}
    for _, character in pairs(characters.sorted) do
        for _, lockout in pairs(self.db.global.characters[character.id].lockouts) do
            raid = Raid:New(lockout.name, lockout.size, lockout.isHeroic, lockout.encounters)
            if raids:Add(raid) then
                lockouts[raid.id] = {}
            end
            lockouts[raid.id][character.id] = lockout.progress
        end
    end

    return characters, raids, lockouts
end

function ThorLockout:UpdateRaidLockouts()
    local lockouts = self:GetRaidLockouts()

    self.charDb.lockouts = lockouts
end

function ThorLockout:OnEventBossKill()
    LogDebug("OnEventBossKill")
    self:TriggerInstanceInfo()
end

function ThorLockout:OnEventInstanceLockStart()
    LogDebug("OnEventInstanceLockStart")
    self:TriggerInstanceInfo()
end

function ThorLockout:OnEventInstanceLockStop()
    LogDebug("OnEventInstanceLockStop")
    self:TriggerInstanceInfo()
end

function ThorLockout:OnEventInstanceLockWarning()
    LogDebug("OnEventInstanceLockWarning")
    self:TriggerInstanceInfo()
end

function ThorLockout:OnEventUpdateInstanceInfo()
    LogDebug("OnEventUpdateInstanceInfo")
    self:UpdateRaidLockouts()
end

function ThorLockout:OnLdbClick()
    LogDebug("OnLdbClick")
end

function ThorLockout:OnLdbEnter(anchor)
    LogDebug("OnLdbEnter")

    if self.qtip:IsAcquired("ThorLockoutTip") then
        return
    end

    self.tooltip = self.qtip:Acquire("ThorLockoutTip")
    self.tooltip.OnRelease = function() self:OnTooltipRelease() end
    self.tooltip:SmartAnchorTo(anchor);
    self.tooltip:SetAutoHideDelay(0.25, anchor);
    self:UpdateTooltip()
    self.tooltip:Show();
end

function ThorLockout:OnLdbLeave()
    LogDebug("OnLdbLeave")
end

function ThorLockout:OnTooltipRelease()
    LogDebug("OnTooltipRelease")

    self.tooltip = nil
end

function ThorLockout:UpdateTooltip()
    local characters, raids, lockouts = self:ProcessData()

    local nrCharacters = #characters.sorted
    local nrRaids = #raids.sorted
    local nrColumns = 1 + nrCharacters

    self.tooltip:SetColumnLayout(nrColumns);
    self.tooltip:AddHeader("ThorLockout");
    self.tooltip:AddSeparator();

    if nrCharacters == 0 or nrRaids == 0 then
        self.tooltip:AddLine(FormatColor(COLOR_GOLD, "No lockouts known"))
        return
    end

    local lineNr = self.tooltip:AddLine()
    for characterNr, character in ipairs(characters.sorted) do
        self.tooltip:SetCell(lineNr, 1 + characterNr, character.colorName)
    end

    for _, raid in pairs(raids.sorted) do
        lineNr = self.tooltip:AddLine(FormatColor(COLOR_GOLD, raid.id))
        for charNr, character in ipairs(characters.sorted) do
            local progress = FormatProgress(lockouts[raid.id][character.id], raid.encounters)

            self.tooltip:SetCell(lineNr, 1 + charNr, progress, nil, "CENTER")
        end
    end
end

function ThorLockout:TriggerInstanceInfo()
    RequestRaidInfo()
end

function ThorLockout:OnInitialize()
    LogDebug("OnInitialize")

    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    self.charId = GetCharacterId()
    self.charClass = GetCharacterClass()
    self.db = LibStub("AceDB-3.0"):New("ThorLockoutDB", DATABASE_DEFAULTS)
    self.charDb = self.db.global.characters[self.charId]
    self.charDb.class = self.charClass
    self.qtip = LibStub("LibQTip-1.0")
    self.tooltip = nil

    self.ldb = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON_NAME, {
        type = "data source",
        icon = "Interface\\Icons\\spell_holy_championsbond",
        text = ADDON_NAME,})
    self.ldb.OnClick = function() self:OnLdbClick() end
    self.ldb.OnEnter = function(anchor) self:OnLdbEnter(anchor) end
    self.ldb.OnLeave = function() self:OnLdbLeave() end
    
    self:RegisterEvent("BOSS_KILL", "OnEventBossKill")
    self:RegisterEvent("INSTANCE_LOCK_START", "OnEventInstanceLockStart")
    self:RegisterEvent("INSTANCE_LOCK_STOP", "OnEventInstanceLockStop")
    self:RegisterEvent("INSTANCE_LOCK_WARNING", "OnEventInstanceLockWarning")
    self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnEventUpdateInstanceInfo")

    self:TriggerInstanceInfo()

    Log(ADDON_IDENTIFIER .. " initialized")
end

function ThorLockout:Start()
    ThorLockout:RegisterEvent("PLAYER_ENTERING_WORLD", "OnInitialize")
    Log(ADDON_IDENTIFIER .. " loaded")
end

-- Start the addon

ThorLockout:Start()
