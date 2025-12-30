--[[
    SocialLFG - NameUtils Module
    Comprehensive name and realm handling for cross-realm compatibility
    
    Handles:
    - Realm normalization (spaces to hyphens, case normalization)
    - Connected realm detection
    - UTF-8 aware name parsing
    - Canonical name format (Name-NormalizedRealm)
    - Display name formatting
    - Cross-realm invite validation
]]

local Addon = _G.SocialLFG

-- Create NameUtils module
Addon.NameUtils = {}
local NameUtils = Addon.NameUtils

-- =============================================================================
-- Constants
-- =============================================================================

-- Cache for realm normalization
local realmCache = {}

-- Player's home realm (cached on init)
local homeRealm = nil
local homeRealmNormalized = nil

-- =============================================================================
-- Initialization
-- =============================================================================

function NameUtils:Initialize()
    -- Cache player's home realm
    homeRealm = GetRealmName() or ""
    homeRealmNormalized = self:NormalizeRealm(homeRealm)
end

-- =============================================================================
-- Realm Utilities
-- =============================================================================

--- Normalize a realm name for consistent comparison
-- Converts spaces to nothing (Blizzard's format), handles case
-- @param realm string - The realm name to normalize
-- @return string - Normalized realm name
function NameUtils:NormalizeRealm(realm)
    if not realm or realm == "" then
        return ""
    end
    
    -- Check cache first
    if realmCache[realm] then
        return realmCache[realm]
    end
    
    -- Remove spaces (Blizzard's internal format has no spaces)
    -- e.g., "Twisting Nether" -> "TwistingNether"
    local normalized = realm:gsub("%s+", "")
    
    -- Cache the result
    realmCache[realm] = normalized
    
    return normalized
end

--- Get the player's home realm (normalized)
-- @return string - Normalized home realm
function NameUtils:GetHomeRealm()
    if not homeRealmNormalized then
        self:Initialize()
    end
    return homeRealmNormalized
end

--- Get the player's home realm (display format)
-- @return string - Home realm as displayed in-game
function NameUtils:GetHomeRealmDisplay()
    if not homeRealm then
        self:Initialize()
    end
    return homeRealm
end

--- Check if a realm is the player's home realm
-- @param realm string - Realm to check (can be normalized or display format)
-- @return boolean - True if same realm
function NameUtils:IsHomeRealm(realm)
    if not realm or realm == "" then
        return true -- No realm means same realm
    end
    
    local normalizedInput = self:NormalizeRealm(realm)
    return normalizedInput == self:GetHomeRealm()
end

-- =============================================================================
-- Name Parsing
-- =============================================================================

--- Parse a full player name into components
-- Handles: "Name", "Name-Realm", "Name-Realm Name" (space in realm)
-- @param fullName string - The full player name
-- @return string|nil, string|nil - characterName, realmName (normalized)
function NameUtils:ParseFullName(fullName)
    if not fullName or fullName == "" then
        return nil, nil
    end
    
    -- Trim whitespace
    fullName = fullName:match("^%s*(.-)%s*$") or fullName
    
    if fullName == "" then
        return nil, nil
    end
    
    -- Find the first hyphen (Name-Realm separator)
    local hyphenPos = fullName:find("-", 1, true)
    
    if not hyphenPos then
        -- No realm specified, use home realm
        return fullName, self:GetHomeRealm()
    end
    
    local charName = fullName:sub(1, hyphenPos - 1)
    local realmPart = fullName:sub(hyphenPos + 1)
    
    -- Validate character name
    if charName == "" then
        return nil, nil
    end
    
    -- Normalize the realm
    local normalizedRealm = self:NormalizeRealm(realmPart)
    
    -- If realm is empty after normalization, use home realm
    if normalizedRealm == "" then
        normalizedRealm = self:GetHomeRealm()
    end
    
    return charName, normalizedRealm
end

--- Extract just the character name from a full name
-- @param fullName string - The full player name
-- @return string|nil - Character name only
function NameUtils:ExtractCharacterName(fullName)
    local charName, _ = self:ParseFullName(fullName)
    return charName
end

--- Extract just the realm from a full name
-- @param fullName string - The full player name
-- @return string|nil - Realm name (normalized)
function NameUtils:ExtractRealm(fullName)
    local _, realm = self:ParseFullName(fullName)
    return realm
end

-- =============================================================================
-- Canonical Name Format
-- =============================================================================

--- Build a canonical full name (Name-NormalizedRealm)
-- This format should be used for all internal storage and comparison
-- @param charName string - Character name
-- @param realm string - Realm name (will be normalized)
-- @return string|nil - Canonical full name or nil if invalid
function NameUtils:BuildCanonicalName(charName, realm)
    if not charName or charName == "" then
        return nil
    end
    
    local normalizedRealm = realm and self:NormalizeRealm(realm) or self:GetHomeRealm()
    
    if not normalizedRealm or normalizedRealm == "" then
        normalizedRealm = self:GetHomeRealm()
    end
    
    return charName .. "-" .. normalizedRealm
end

--- Normalize a full name to canonical format
-- @param fullName string - Any format of player name
-- @return string|nil - Canonical full name
function NameUtils:ToCanonical(fullName)
    local charName, realm = self:ParseFullName(fullName)
    if not charName then
        return nil
    end
    return self:BuildCanonicalName(charName, realm)
end

--- Check if two names refer to the same player
-- @param name1 string - First player name
-- @param name2 string - Second player name
-- @return boolean - True if same player
function NameUtils:IsSamePlayer(name1, name2)
    local canonical1 = self:ToCanonical(name1)
    local canonical2 = self:ToCanonical(name2)
    
    if not canonical1 or not canonical2 then
        return false
    end
    
    return canonical1 == canonical2
end

-- =============================================================================
-- Display Formatting
-- =============================================================================

--- Get display name (character name only, realm in context)
-- @param fullName string - Full player name
-- @return string - Display name
function NameUtils:GetDisplayName(fullName)
    local charName = self:ExtractCharacterName(fullName)
    return charName or fullName or "Unknown"
end

--- Get full display name with realm indicator for cross-realm
-- Shows "Name*" for cross-realm, "Name" for same realm
-- @param fullName string - Full player name
-- @return string - Display name with optional cross-realm indicator
function NameUtils:GetDisplayNameWithIndicator(fullName)
    local charName, realm = self:ParseFullName(fullName)
    
    if not charName then
        return fullName or "Unknown"
    end
    
    if not self:IsHomeRealm(realm) then
        return charName .. "*"
    end
    
    return charName
end

--- Get the full display name (Name-Realm in display format)
-- @param fullName string - Full player name
-- @return string - Full display name
function NameUtils:GetFullDisplayName(fullName)
    local charName, realm = self:ParseFullName(fullName)
    
    if not charName then
        return fullName or "Unknown"
    end
    
    if not realm or realm == "" then
        return charName
    end
    
    return charName .. "-" .. realm
end

-- =============================================================================
-- Validation
-- =============================================================================

--- Validate a player name
-- @param name string - The player name to validate
-- @return boolean - Whether the name is valid
function NameUtils:IsValidName(name)
    if not name or name == "" then
        return false
    end
    
    -- Check for control characters
    for i = 1, #name do
        local byte = string.byte(name, i)
        if byte and byte < 32 then
            return false
        end
    end
    
    -- Must have at least one character
    local charName = self:ExtractCharacterName(name)
    if not charName or charName == "" then
        return false
    end
    
    return true
end

--- Check if a name is valid for inviting
-- @param name string - The player name
-- @return boolean, string - Success and the name to use for invite
function NameUtils:GetInviteName(name)
    if not self:IsValidName(name) then
        return false, nil
    end
    
    local charName, realm = self:ParseFullName(name)
    
    if not charName then
        return false, nil
    end
    
    -- For same realm, just use character name
    if self:IsHomeRealm(realm) then
        return true, charName
    end
    
    -- For cross-realm, use full canonical name
    return true, self:BuildCanonicalName(charName, realm)
end

--- Check if a name is valid for whispering
-- @param name string - The player name
-- @return boolean, string - Success and the name to use for whisper
function NameUtils:GetWhisperName(name)
    -- Same logic as invite for whispers
    return self:GetInviteName(name)
end

-- =============================================================================
-- Colored Name Utilities
-- =============================================================================

--- Get class-colored display name
-- @param fullName string - Full player name
-- @param class string - Class token (e.g., "WARRIOR")
-- @return string - Colored name string
function NameUtils:GetColoredDisplayName(fullName, class)
    local displayName = self:GetDisplayName(fullName)
    
    if not class then
        return displayName
    end
    
    local color = RAID_CLASS_COLORS[class]
    if not color then
        return displayName
    end
    
    return string.format("|c%s%s|r", color.colorStr, displayName)
end

-- =============================================================================
-- Friend/Guild Name Building
-- =============================================================================

--- Build canonical name from friend info
-- Handles missing realm gracefully
-- @param charName string - Character name
-- @param realmName string|nil - Realm name (may be nil or empty)
-- @return string - Canonical full name
function NameUtils:BuildFromFriendInfo(charName, realmName)
    if not charName or charName == "" then
        return nil
    end
    
    -- If no realm provided, assume home realm
    if not realmName or realmName == "" then
        return self:BuildCanonicalName(charName, self:GetHomeRealm())
    end
    
    return self:BuildCanonicalName(charName, realmName)
end

--- Build canonical name from BNet game account info
-- @param gameAccountInfo table - BNet game account info
-- @return string|nil - Canonical full name
function NameUtils:BuildFromBNetInfo(gameAccountInfo)
    if not gameAccountInfo then
        return nil
    end
    
    local charName = gameAccountInfo.characterName
    local realmName = gameAccountInfo.realmName
    
    if not charName or charName == "" then
        return nil
    end
    
    return self:BuildFromFriendInfo(charName, realmName)
end

