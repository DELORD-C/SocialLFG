--[[
    SocialLFG - Player Module
    Local player data: keystone, RaiderIO score, and character info
]]

local Addon = _G.SocialLFG
local L = _G.SocialLFG_L

-- Create Player module
Addon.Player = {}
local Player = Addon.Player

-- =============================================================================
-- Internal State
-- =============================================================================

local state = {
    keystone = nil,
    rioScore = 0,
    rioInitialized = false,
    rioRetryCount = 0,
}

-- =============================================================================
-- Initialization
-- =============================================================================

function Player:Initialize()
    -- Update keystone on init
    self:UpdateKeystone()
    
    -- Schedule RaiderIO initialization
    C_Timer.After(Addon.Constants.RIO_RETRY_DELAY, function()
        Player:InitializeRaiderIO()
    end)
end

-- =============================================================================
-- RaiderIO Integration
-- =============================================================================

function Player:InitializeRaiderIO()
    if state.rioInitialized then return end
    
    -- Check if RaiderIO is available
    if not RaiderIO then
        self:ShowRioMissingPopup()
        return
    end
    
    -- Try to get score
    local score = self:FetchRioScore()
    
    if score > 0 then
        state.rioScore = score
        state.rioInitialized = true
        
        -- If registered, rebroadcast with updated score
        if Addon:IsRegistered() then
            Addon.Communication:BroadcastStatus()
        end
    else
        -- Retry if not initialized yet
        state.rioRetryCount = state.rioRetryCount + 1
        
        if state.rioRetryCount < Addon.Constants.RIO_MAX_RETRIES then
            C_Timer.After(Addon.Constants.RIO_RETRY_DELAY, function()
                Player:InitializeRaiderIO()
            end)
        end
    end
end

function Player:FetchRioScore()
    if not RaiderIO or not RaiderIO.GetProfile then
        return 0
    end
    
    local profile = RaiderIO.GetProfile("player", "player")
    if not profile or not profile.mythicKeystoneProfile then
        return 0
    end
    
    -- Prefer warband score, fall back to character score
    local score = profile.mythicKeystoneProfile.warbandCurrentScore
    if not score or score == 0 then
        score = profile.mythicKeystoneProfile.currentScore
    end
    
    return math.floor(score or 0)
end

function Player:GetRioScore()
    -- Refresh score if RaiderIO is available
    if RaiderIO and state.rioInitialized then
        state.rioScore = self:FetchRioScore()
    end
    return state.rioScore
end

function Player:ShowRioMissingPopup()
    if Addon.Database:IsRioNoticeDismissed() then
        return
    end
    
    -- Check if RaiderIO is actually loaded (use modern API)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("RaiderIO")
    if isLoaded then
        return
    end
    if RaiderIO then
        return
    end
    
    StaticPopup_Show("SOCIALLFG_RIO_MISSING")
end

-- =============================================================================
-- Keystone Management
-- =============================================================================

function Player:UpdateKeystone()
    local oldKeystone = state.keystone
    local newKeystone = self:FetchKeystone()
    
    -- Check if keystone actually changed
    local changed = false
    if (oldKeystone == nil) ~= (newKeystone == nil) then
        changed = true
    elseif oldKeystone and newKeystone then
        if oldKeystone.mapID ~= newKeystone.mapID or oldKeystone.level ~= newKeystone.level then
            changed = true
        end
    end
    
    state.keystone = newKeystone
    
    -- If changed and registered, rebroadcast
    if changed and Addon:IsRegistered() then
        Addon.Communication:BroadcastStatus()
        Addon.Members:AddLocalPlayer()
    end
    
    -- Update UI if visible
    if SocialLFGFrame and SocialLFGFrame:IsShown() then
        Addon.Members:AddLocalPlayer()
        Addon:FireCallback("OnListChanged")
    end
end

function Player:FetchKeystone()
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()
    
    if not mapID or not level or level == 0 then
        return nil
    end
    
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    
    return {
        mapID = mapID,
        level = level,
        name = name,
    }
end

function Player:GetKeystone()
    return state.keystone
end

function Player:FormatKeystone()
    local ks = state.keystone
    if not ks then
        return L["NO_KEYSTONE"]
    end
    
    -- Get short name from map ID
    local shortName = Addon.Constants.DUNGEON_SHORT_NAMES[ks.mapID]
    if not shortName then
        shortName = L["DUNGEON_UNKNOWN"]
    end
    
    return string.format("%s+%d", shortName, ks.level)
end

-- =============================================================================
-- Player Info Helpers
-- =============================================================================

function Player:GetFullName()
    return Addon.runtime.playerFullName
end

function Player:GetName()
    return Addon.runtime.playerName
end

function Player:GetRealm()
    return Addon.runtime.playerRealm
end

function Player:GetClass()
    return Addon.runtime.playerClass
end

function Player:GetItemLevel()
    return math.floor(GetAverageItemLevel())
end

function Player:GetAllowedRoles()
    local class = self:GetClass()
    return Addon.Constants.CLASS_ROLES[class] or Addon.Constants.ROLES
end

function Player:CanUseRole(role)
    local allowedRoles = self:GetAllowedRoles()
    return tContains(allowedRoles, role)
end

-- =============================================================================
-- Build Status Object
-- =============================================================================

function Player:BuildStatus()
    local db = Addon.Database
    
    return {
        categories = db:GetCategories(),
        roles = db:GetRoles(),
        ilvl = self:GetItemLevel(),
        rio = self:GetRioScore(),
        class = self:GetClass(),
        keystone = self:FormatKeystone(),
    }
end

-- =============================================================================
-- Static Popup Definition
-- =============================================================================

StaticPopupDialogs["SOCIALLFG_RIO_MISSING"] = {
    text = L["RIO_MISSING_TEXT"],
    button1 = L["RIO_DISMISS"],
    button2 = L["RIO_CLOSE"],
    OnAccept = function()
        if Addon.Database then
            Addon.Database:DismissRioNotice()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
