--[[
    SocialLFG - Localization System
    Provides multi-language support with fallback to English
]]

local ADDON_NAME = "SocialLFG"

-- Create the localization table
local L = {}
_G.SocialLFG_L = L

-- Locale metatable for fallback to English
local LocaleMT = {
    __index = function(t, key)
        -- Fallback to key itself if not found (useful for debugging)
        return key
    end
}

setmetatable(L, LocaleMT)

-- Get current game locale
local function GetGameLocale()
    return GetLocale() or "enUS"
end

-- Register locale strings
-- @param locale string - Locale code (e.g., "enUS", "frFR")
-- @param strings table - Table of localized strings
function SocialLFG_RegisterLocale(locale, strings)
    local gameLocale = GetGameLocale()
    
    -- Always load enUS as base (first call)
    -- Then override with matching locale
    if locale == "enUS" or locale == gameLocale then
        for key, value in pairs(strings) do
            L[key] = value
        end
    end

    -- Notify addon code to refresh localization caches if present
    if _G.SocialLFG and type(_G.SocialLFG.RefreshLocalizationCaches) == "function" then
        pcall(function() _G.SocialLFG:RefreshLocalizationCaches() end)
    end
end

-- Convenience function to get localized string
-- @param key string - The string key
-- @param ... - Optional format arguments
-- @return string - The localized string
function SocialLFG_GetString(key, ...)
    local str = L[key] or key
    if select("#", ...) > 0 then
        return string.format(str, ...)
    end
    return str
end
