--[[
    SocialLFG - Core Module
    Main addon object, constants, and initialization
]]

local ADDON_NAME = "SocialLFG"

-- Create main addon namespace
local Addon = {}
_G.SocialLFG = Addon

-- Localization shortcut
local L = _G.SocialLFG_L

-- =============================================================================
-- Constants
-- =============================================================================

Addon.Constants = {
    -- Addon Messaging
    PREFIX = "SocialLFG",
    PROTOCOL_VERSION = 2,
    
    -- Timing (in seconds)
    TIMEOUT = 90,                    -- Player timeout threshold
    QUERY_INTERVAL = 15,             -- Periodic query interval
    QUERY_THROTTLE = 5,              -- Min time between queries to same target
    BROADCAST_DEBOUNCE = 1.0,        -- Debounce for status broadcasts
    LIST_UPDATE_THROTTLE = 0.3,      -- Min time between list UI updates
    MESSAGE_RATE_LIMIT = 0.1,        -- Min time between addon messages
    RIO_RETRY_DELAY = 2,             -- Delay for RaiderIO retry
    RIO_MAX_RETRIES = 3,             -- Max RaiderIO initialization retries
    
    -- UI Dimensions
    ROW_HEIGHT = 24,
    ROLE_ICON_SIZE = 14,
    CLASS_ICON_SIZE = 14,
    FRAME_WIDTH = 800,
    FRAME_HEIGHT = 600,
    
    -- UI Column Layout (X positions relative to row frame)
    -- All columns defined here for single-source-of-truth alignment
    COLUMNS = {
        NAME      = { x = 10,  width = 100, justify = "LEFT" },
        ROLES     = { x = 115, width = 55,  justify = "LEFT" },
        CATEGORIES= { x = 175, width = 110, justify = "LEFT" },
        ILVL      = { x = 290, width = 45,  justify = "CENTER" },
        RIO       = { x = 340, width = 45,  justify = "CENTER" },
        KEYSTONE  = { x = 390, width = 60,  justify = "CENTER" },
        ACTIONS   = { x = 455, width = 140, justify = "LEFT" },
    },
    
    -- Checkbox spacing
    CHECKBOX_SPACING = 90,           -- Consistent spacing between checkboxes
    CHECKBOX_LABEL_OFFSET = 2,       -- Label offset from checkbox
    
    -- Pooling
    ROW_POOL_PREALLOCATE = 50,        -- Number of rows to pre-create at init to avoid allocations during refresh
        -- UI timings
    REGISTER_COOLDOWN = 2,            -- Seconds to block the register button after click
    -- Metrics
    METRICS_ENABLED = true,          -- Enable runtime metrics collection (off by default)
    
    -- Game Data
    CATEGORIES = {"Raid", "Mythic+", "Questing", "Dungeon", "Boosting", "PVP"},
    ROLES = {"Tank", "Heal", "DPS"},
    
    -- Class Role Mapping
    CLASS_ROLES = {
        ["WARRIOR"]     = {"Tank", "DPS"},
        ["PALADIN"]     = {"Tank", "Heal", "DPS"},
        ["HUNTER"]      = {"DPS"},
        ["ROGUE"]       = {"DPS"},
        ["PRIEST"]      = {"Heal", "DPS"},
        ["DEATHKNIGHT"] = {"Tank", "DPS"},
        ["SHAMAN"]      = {"Heal", "DPS"},
        ["MAGE"]        = {"DPS"},
        ["WARLOCK"]     = {"DPS"},
        ["MONK"]        = {"Tank", "Heal", "DPS"},
        ["DRUID"]       = {"Tank", "Heal", "DPS"},
        ["DEMONHUNTER"] = {"Tank", "DPS"},
        ["EVOKER"]      = {"Heal", "DPS"},
    },
    
    -- Dungeon MapID to Short Name (universal across locales)
    DUNGEON_SHORT_NAMES = {
        [499] = "PSF",
        [542] = "ECO",
        [378] = "HOA",
        [525] = "FLO",
        [503] = "AKA",
        [392] = "GBT",
        [391] = "STR",
        [505] = "DB",
    },
}

-- =============================================================================
-- State
-- =============================================================================

-- Registration state machine
Addon.State = {
    IDLE = "IDLE",
    REGISTERED = "REGISTERED",
    IN_GROUP = "IN_GROUP",
}

-- Current addon state
Addon.currentState = Addon.State.IDLE

-- Runtime data (not persisted)
Addon.runtime = {
    -- Player data cache
    playerKeystone = nil,
    playerClass = nil,
    playerName = nil,
    playerRealm = nil,
    playerFullName = nil,
    
    -- RaiderIO
    rioInitialized = false,
    rioRetryCount = 0,
    
    -- Flags
    initialized = false,
    hasInitialQuery = false,
    
    -- Timers
    updateTimer = nil,
    pendingBroadcast = nil,

    -- Flags
}

-- =============================================================================
-- Initialization
-- =============================================================================

function Addon:Initialize()
    if self.runtime.initialized then return end
    
    -- Cache player info
    self.runtime.playerName = UnitName("player")
    self.runtime.playerRealm = GetRealmName()
    
    -- Initialize NameUtils first (needed for canonical name)
    if self.NameUtils then
        self.NameUtils:Initialize()
    end
    
    -- Build canonical player name using NameUtils if available
    if self.NameUtils then
        self.runtime.playerFullName = self.NameUtils:BuildCanonicalName(
            self.runtime.playerName,
            self.runtime.playerRealm
        )
    else
        -- Fallback: manual construction with normalized realm
        local normalizedRealm = self.runtime.playerRealm:gsub("%s+", "")
        self.runtime.playerFullName = self.runtime.playerName .. "-" .. normalizedRealm
    end
    
    _, self.runtime.playerClass = UnitClass("player")
    
    -- Initialize modules
    self.Database:Initialize()
    self.Communication:Initialize()
    self.Player:Initialize()
    self.Members:Initialize()

    -- Optional: initialize metrics module (separate file, opt-in)
    if self.Metrics and type(self.Metrics.Initialize) == "function" then
        self.Metrics:Initialize()
    end
    
    -- Register addon message prefix
    C_ChatInfo.RegisterAddonMessagePrefix(self.Constants.PREFIX)
    
    -- Register special frames (ESC to close)
    table.insert(UISpecialFrames, "SocialLFGFrame")
    
    -- Determine initial state
    self:UpdateState()
    
    self.runtime.initialized = true
    
    -- If already registered, send initial update after delay (for RaiderIO)
    if self.currentState == self.State.REGISTERED then
        C_Timer.After(self.Constants.RIO_RETRY_DELAY, function()
            self:OnRegistrationRestored()
        end)
    end
end

function Addon:OnRegistrationRestored()
    self.Communication:BroadcastStatus()
    self.Members:AddLocalPlayer()
end

-- =============================================================================
-- State Management
-- =============================================================================

function Addon:UpdateState()
    local inGroup = IsInGroup()
    local hasRegistration = self.Database:IsRegistered()
    
    if inGroup then
        self.currentState = self.State.IN_GROUP
    elseif hasRegistration then
        self.currentState = self.State.REGISTERED
    else
        self.currentState = self.State.IDLE
    end
end

function Addon:GetState()
    return self.currentState
end

function Addon:IsRegistered()
    return self.currentState == self.State.REGISTERED
end

function Addon:CanRegister()
    return self.currentState == self.State.IDLE
end

-- =============================================================================
-- Registration Actions
-- =============================================================================

function Addon:Register(categories, roles)
    if not self:CanRegister() then
        self:LogWarn(L["ERR_CANNOT_REGISTER"]) 
        return false
    end

    -- Validate input
    if not categories or #categories == 0 then
        self:LogWarn(L["ERR_SELECT_CATEGORY"])
        return false
    end
    
    if not roles or #roles == 0 then
        self:LogWarn(L["ERR_SELECT_ROLE"])
        return false
    end
    
    -- Save registration
    self.Database:SetRegistration(categories, roles)
    self:UpdateState()
    
    -- Broadcast to others
    self.Communication:BroadcastStatus()
    
    -- Add self to list
    self.Members:AddLocalPlayer()
    
    -- Update UI
    self:FireCallback("OnRegistrationChanged")
    
    return true
end

function Addon:Unregister()
    -- Clear registration
    self.Database:ClearRegistration()
    self:UpdateState()
    
    -- Remove self from list
    self.Members:RemoveLocalPlayer()
    
    -- Broadcast unregister
    self.Communication:BroadcastUnregister()
    
    -- Update UI
    self:FireCallback("OnRegistrationChanged")
end

function Addon:Toggle()
    if self:IsRegistered() then
        self:Unregister()
    else
        -- Use saved preferences
        local categories = self.Database:GetSavedCategories()
        local roles = self.Database:GetSavedRoles()
        self:Register(categories, roles)
    end
end

-- =============================================================================
-- Callbacks
-- =============================================================================

Addon.callbacks = {}

function Addon:RegisterCallback(event, callback)
    if not self.callbacks[event] then
        self.callbacks[event] = {}
    end
    table.insert(self.callbacks[event], callback)
end

function Addon:FireCallback(event, ...)
    local callbacks = self.callbacks[event]
    if callbacks then
        for _, callback in ipairs(callbacks) do
            callback(...)
        end
    end
end

-- =============================================================================
-- Logging
-- =============================================================================

local function FormatLog(level, msg)
    if not msg or msg == "" then return end
    
    local prefix = "|cFF4DA6FFSocialLFG|r"
    local levelColors = {
        DEBUG = "|cFF888888",
        INFO  = "|cFF00FF00",
        WARN  = "|cFFFF9900",
        ERROR = "|cFFFF6B6B",
    }
    
    local color = levelColors[level] or "|cFFFFFFFF"
    print(string.format("%s %s[%s]|r %s", prefix, color, level, msg))
end

function Addon:LogDebug(msg)
    -- Disabled by default, enable for development
    -- FormatLog("DEBUG", msg)
end

function Addon:LogInfo(msg)
    FormatLog("INFO", msg)
end

function Addon:LogWarn(msg)
    FormatLog("WARN", msg)
end

function Addon:LogError(msg)
    FormatLog("ERROR", msg)
end

-- =============================================================================
-- Slash Commands
-- =============================================================================

SLASH_SOCIALLFG1 = "/slfg"
SLASH_SOCIALLFG2 = "/sociallfg"
SlashCmdList["SOCIALLFG"] = function(msg)
    if SocialLFGFrame then
        if SocialLFGFrame:IsShown() then
            SocialLFGFrame:Hide()
        else
            SocialLFGFrame:Show()
        end
    end
end
