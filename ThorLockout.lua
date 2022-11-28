-- CONSTANTS

local ADDON_NAME = "ThorLockout"
local ADDON_VERSION = "1.2.0"
local ADDON_AUTHOR = "Thorinsøn"

local COMMAND_NAME = "thorlockout"
local TOOLTIP_NAME = ADDON_NAME .. "Tip"
local DATABASE_NAME = ADDON_NAME .. "DB"
local DATABASE_DEFAULTS = {
	global = {
		characters = {
			['*'] = {
                class = nil,
				lockouts = {}
			}
		}
	},
    char = {
        minimap = { hide = false }
    }
}

local COLOR_LOG = "|cffff7f00"
local COLOR_GOLD = "|cfffed100"
local COLOR_GREEN = "|cff00ff00"
local COLOR_ORANGE = "|cffff7f00"
local COLOR_RESUME = "|r"


-- FUNCTIONS

local function FormatColor(color, message, ...)
    return color .. string.format(message, ...) .. COLOR_RESUME
end

local function FormatColorClass(class, message, ...)
    local _, _, _, color = GetClassColor(class)
    return FormatColor("|c" .. color, message, ...)
end

local function Log(message, ...)
    print(FormatColor(COLOR_LOG, "[" .. ADDON_NAME .. "] " .. message, ...))
end

local function LogDebug(message, ...)
    -- Log("[DBG] " .. message, ...)
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
    result.colorName = FormatColorClass(result.class, result.name)
    return result
end

function Character:Less(other)
    return self.name < other.name
end

----- CLASS - Instance

local Instance = {}
function Instance:New(name, size, isHeroic, isRaid, encounters)
    local result = {}
    setmetatable(result, self)
    self.__index = self
    result.name = name
    result.size = size
    result.isHeroic = isHeroic
    result.isRaid = isRaid
    result.encounters = encounters
    result.id = string.format("%s %s%s", result.name, result.isRaid and tostring(result.size) or "", result.isHeroic and "H" or "N")
    return result
end

function Instance:Equal(other)
    return self.name == other.name
        and self.size == other.size
        and self.isHeroic == other.isHeroic
end

function Instance:Less(other)
    return self.name < other.name
        or (self.name == other.name
            and self.size < other.size)
        or (self.name == other.name
            and self.size == other.size
            and not self.isHeroic and other.isHeroic)
end

----- CLASS - Container

local Container = {}
function Container:New()
    local result = {}
    setmetatable(result, self)
    self.__index = self
    result.byId = {}
    result.sorted = {}
    return result
end

function Container:Add(raid)
    if self.byId[raid.id] ~= nil then
        return false
    end
    self.byId[raid.id] = raid
    table.insert(self.sorted, raid)
    table.sort(self.sorted, function(a, b) return a:Less(b) end)
    return true
end

----- CLASS - ThorLockout

local ThorLockout = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")

function ThorLockout:GetLockouts()
    local now = GetServerTime()
    local result = {}

	for i = 1, GetNumSavedInstances() do
		local instanceName, instanceID, instanceReset, difficulty, locked, extended, _, isRaid, maxPlayers, difficultyName, 
				numEncounters, encounterProgress, extendDisabled = GetSavedInstanceInfo(i)
        local name, groupType, isHeroic, isChallengeMode, displayHeroic, displayMythic, toggleDifficultyID = GetDifficultyInfo(difficulty)
        local resetTime = RoundToNearestHour(now + instanceReset)

        if instanceReset > 0 then
            table.insert(result, {
                name=instanceName,
                size=maxPlayers,
                isHeroic=isHeroic,
                progress=encounterProgress,
                encounters=numEncounters,
                resetTime=resetTime,
                isRaid=isRaid})
        end
	end

    return result
end

function ThorLockout:ProcessData()
    local now = GetServerTime()

    local characters = Container:New()
    local instances = {[true]=Container:New(), [false] = Container:New()}
    local lockouts = {}

    for characterId, character in pairs(self.db.global.characters) do
        local characterHasLockouts = false

        for _, lockout in pairs(character.lockouts) do
            if lockout.resetTime > now then
                local isRaid = lockout.isRaid
                if isRaid == nil then
                    isRaid = true
                end

                local instance = Instance:New(lockout.name, lockout.size, lockout.isHeroic, isRaid, lockout.encounters)
                if instances[isRaid]:Add(instance) then
                    lockouts[instance.id] = {}
                end
                characterHasLockouts = true
                lockouts[instance.id][characterId] = lockout.progress
            end
        end

        if characterHasLockouts then
            characters:Add(Character:New(characterId, character.class))
        end
    end

    return characters, instances, lockouts
end

function ThorLockout:UpdateRaidLockouts()
    local lockouts = self:GetLockouts()

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

    if self.qtip:IsAcquired(TOOLTIP_NAME) then
        return
    end

    self.tooltip = self.qtip:Acquire(TOOLTIP_NAME)
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

local function AddLockoutsToTooltip(tip, characters, instances, lockouts)
    for _, instance in pairs(instances.sorted) do
        lineNr = tip:AddLine(FormatColor(COLOR_GOLD, instance.id))
        for charNr, character in ipairs(characters.sorted) do
            local progress = FormatProgress(lockouts[instance.id][character.id], instance.encounters)

            tip:SetCell(lineNr, 1 + charNr, progress, nil, "CENTER")
        end
    end
end

function ThorLockout:UpdateTooltip()
    local characters, instances, lockouts = self:ProcessData()

    local raids = instances[true]
    local dungeons = instances[false]

    local nrCharacters = #characters.sorted
    local nrRaids = #raids.sorted
    local nrDungeons = #dungeons.sorted
    local nrColumns = 1 + nrCharacters

    self.tooltip:SetColumnLayout(nrColumns);
    self.tooltip:AddHeader()
    self.tooltip:SetCell(1, 1, ADDON_NAME .. " " .. ADDON_VERSION, nil, nil, nrColumns)
    self.tooltip:AddSeparator();

    if nrCharacters == 0 or (nrRaids == 0 and nrDungeons == 0) then
        self.tooltip:AddLine(FormatColor(COLOR_GOLD, "No lockouts known"))
        return
    end

    local lineNr = self.tooltip:AddLine()
    for characterNr, character in ipairs(characters.sorted) do
        self.tooltip:SetCell(lineNr, 1 + characterNr, character.colorName)
    end

    self.tooltip:AddSeparator();

    AddLockoutsToTooltip(self.tooltip, characters, raids, lockouts)

    if nrRaids > 0 and nrDungeons > 0 then
        self.tooltip:AddSeparator()
    end

    AddLockoutsToTooltip(self.tooltip, characters, dungeons, lockouts)
end

function ThorLockout:TriggerInstanceInfo()
    RequestRaidInfo()
end

function ThorLockout:LogCommandUsage(isError)
    if isError then
        Log("invalid command")
    end

    Log("use \"/" .. COMMAND_NAME .. " minimap enable\" to enable the minimap button")
    Log("use \"/" .. COMMAND_NAME .. " minimap disable\" to disable the minimap button")
end

function ThorLockout:OnChatCommand(str)
    LogDebug("OnChatCommand")

    local action, value, _ = self:GetArgs(str, 2)

    if action == nil then
        return self:LogCommandUsage(false)
    end

    if action ~= "minimap" then
        return self:LogCommandUsage(true)
    end

    if value == "enable" then
        self.db.char.minimap.hide = false
        self.dbicon:Show(ADDON_NAME)
        Log("minimap button enabled")
    elseif value == "disable" then
        self.db.char.minimap.hide = true
        self.dbicon:Hide(ADDON_NAME)
        Log("minimap button disabled")
    else
        return self:LogCommandUsage(true)
    end
end

function ThorLockout:OnEnable()
    LogDebug("OnEnable")

    self.charId = GetCharacterId()
    self.charClass = GetCharacterClass()
    self.db = LibStub("AceDB-3.0"):New(DATABASE_NAME, DATABASE_DEFAULTS)
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
    
    self.dbicon = LibStub("LibDBIcon-1.0")
    self.dbicon:Register(ADDON_NAME, self.ldb, self.db.char.minimap)

    self:RegisterChatCommand(COMMAND_NAME, "OnChatCommand")

    self:RegisterEvent("BOSS_KILL", "OnEventBossKill")
    self:RegisterEvent("INSTANCE_LOCK_START", "OnEventInstanceLockStart")
    self:RegisterEvent("INSTANCE_LOCK_STOP", "OnEventInstanceLockStop")
    self:RegisterEvent("INSTANCE_LOCK_WARNING", "OnEventInstanceLockWarning")
    self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnEventUpdateInstanceInfo")

    self:TriggerInstanceInfo()

    Log("version " .. ADDON_VERSION .. " by " .. FormatColorClass("HUNTER", ADDON_AUTHOR) ..  " initialized")
    Log("use \"/" .. COMMAND_NAME .. "\" to set options")
end
