--[[
    SocialLFG - Utils Module
    Utility functions for string manipulation, validation, and helpers
]]

local Addon = _G.SocialLFG

-- Create Utils module
Addon.Utils = {}
local Utils = Addon.Utils

-- =============================================================================
-- String Utilities
-- =============================================================================

-- Split a string by delimiter
-- @param str string - The string to split
-- @param delimiter string - The delimiter
-- @return table - Array of parts
function Utils:Split(str, delimiter)
    if not str then return {} end
    
    local parts = {}
    local start = 1
    
    while true do
        local pos = str:find(delimiter, start, true)
        if not pos then
            table.insert(parts, str:sub(start))
            break
        else
            table.insert(parts, str:sub(start, pos - 1))
            start = pos + #delimiter
        end
    end
    
    return parts
end

-- Trim whitespace from string
-- @param str string - The string to trim
-- @return string - Trimmed string
function Utils:Trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$") or ""
end

-- Join table elements with delimiter
-- @param tbl table - The table to join
-- @param delimiter string - The delimiter
-- @return string - Joined string
function Utils:Join(tbl, delimiter)
    if not tbl or #tbl == 0 then return "" end
    return table.concat(tbl, delimiter)
end

-- =============================================================================
-- Player Name Utilities
-- =============================================================================

-- Validate player name format
-- @param name string - The player name to validate
-- @return boolean - Whether the name is valid
function Utils:IsValidPlayerName(name)
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
    
    return true
end

-- Extract character name from "Name-Realm" format
-- @param fullName string - Full player name with realm
-- @return string|nil - Character name only
function Utils:ExtractCharacterName(fullName)
    if not fullName or fullName == "" then
        return nil
    end
    
    -- Find the first hyphen for Name-Realm split
    local hyphenPos = fullName:find("-", 1, true)
    if hyphenPos then
        return fullName:sub(1, hyphenPos - 1)
    end
    
    return fullName
end

-- Normalize player name
-- @param name string - The player name
-- @return string|nil - Normalized name or nil if invalid
function Utils:NormalizePlayerName(name)
    if not name or name == "" then
        return nil
    end
    
    name = self:Trim(name)
    return name ~= "" and name or nil
end

-- =============================================================================
-- Class Utilities
-- =============================================================================

-- Get class color for a class
-- @param class string - The class token (e.g., "WARRIOR")
-- @return ColorMixin - The class color
function Utils:GetClassColor(class)
    if not class then
        return NORMAL_FONT_COLOR
    end
    return RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
end

-- Get colored player name
-- @param name string - The player name
-- @param class string - The class token
-- @return string - Colored name string
function Utils:GetColoredName(name, class)
    if not name then
        return "Unknown"
    end
    
    if not class then
        return name
    end
    
    local color = self:GetClassColor(class)
    return string.format("|c%s%s|r", color.colorStr, name)
end

-- Set class icon atlas on a texture
-- @param texture Texture - The texture object
-- @param class string - The class token
function Utils:SetClassIcon(texture, class)
    if not class then
        texture:Hide()
        return
    end
    
    texture:SetAtlas("classicon-" .. class:lower(), false)
    texture:Show()
end

-- Get role atlas name
-- @param role string - The role name ("Tank", "Heal", "DPS")
-- @return string - Atlas name
function Utils:GetRoleAtlas(role)
    local ROLE_ATLASES = {
        ["Tank"] = "roleicon-tiny-tank",
        ["Heal"] = "roleicon-tiny-healer",
        ["DPS"]  = "roleicon-tiny-dps",
    }
    return ROLE_ATLASES[role] or "roleicon-tiny-dps"
end

-- Check if class can use role
-- @param class string - The class token
-- @param role string - The role name
-- @return boolean - Whether the class can use the role
function Utils:ClassCanUseRole(class, role)
    local classRoles = Addon.Constants.CLASS_ROLES[class]
    if not classRoles then
        return false
    end
    return tContains(classRoles, role)
end

-- Get allowed roles for a class
-- @param class string - The class token
-- @return table - Array of allowed roles
function Utils:GetAllowedRoles(class)
    return Addon.Constants.CLASS_ROLES[class] or Addon.Constants.ROLES
end

-- =============================================================================
-- Table Utilities
-- =============================================================================

-- Deep copy a table
-- @param orig table - The original table
-- @return table - Copy of the table
function Utils:DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[self:DeepCopy(k)] = self:DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Check if table contains value
-- @param tbl table - The table to search
-- @param value any - The value to find
-- @return boolean - Whether the value exists
function Utils:Contains(tbl, value)
    if not tbl then return false end
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

-- Count table entries
-- @param tbl table - The table to count
-- @return number - Number of entries
function Utils:TableCount(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- =============================================================================
-- Time Utilities
-- =============================================================================

-- Get current time (alias for GetTime())
-- @return number - Current time
function Utils:GetTime()
    return GetTime()
end

-- Check if enough time has passed since last action
-- @param lastTime number - The last action time
-- @param threshold number - Minimum time between actions
-- @return boolean - Whether threshold has passed
function Utils:HasTimePassed(lastTime, threshold)
    if not lastTime then return true end
    return (GetTime() - lastTime) >= threshold
end

-- =============================================================================
-- Hash Utilities
-- =============================================================================

-- Simple hash function for status data
-- @param status table - The status data
-- @return string - Hash string
function Utils:HashStatus(status)
    if not status then return "" end
    
    local parts = {
        status.categories and table.concat(status.categories, ",") or "",
        status.roles and table.concat(status.roles, ",") or "",
        tostring(status.ilvl or 0),
        tostring(status.rio or 0),
        status.class or "",
        status.keystone or "",
    }
    
    return table.concat(parts, "|")
end
