--[[
    SocialLFG - Events Module
    Event handling and dispatching
]]

local Addon = _G.SocialLFG

-- Create Events module
Addon.Events = {}
local Events = Addon.Events

-- Event frame
local eventFrame = CreateFrame("Frame")

-- =============================================================================
-- Event Handlers
-- =============================================================================

local handlers = {}

handlers["ADDON_LOADED"] = function(addonName)
    if addonName ~= "SocialLFG" then return end
    
    -- Initialize the addon
    Addon:Initialize()
    
    -- Unregister this event - only needed once
    eventFrame:UnregisterEvent("ADDON_LOADED")
end

handlers["CHAT_MSG_ADDON"] = function(prefix, message, channel, sender)
    if prefix ~= Addon.Constants.PREFIX then return end
    Addon.Communication:HandleMessage(message, sender, channel)
end

-- Handle BNet addon messages (cross-realm communication)
handlers["BN_CHAT_MSG_ADDON"] = function(prefix, message, _, senderID)
    if prefix ~= Addon.Constants.PREFIX then return end
    
    -- Get the sender's character name from the BNet account info
    if not senderID then return end
    
    local accountInfo = C_BattleNet.GetAccountInfoByID(senderID)
    if not accountInfo or not accountInfo.gameAccountInfo then return end
    
    local game = accountInfo.gameAccountInfo
    if not game.characterName then return end
    
    -- Build full sender name
    local senderName
    if Addon.NameUtils then
        senderName = Addon.NameUtils:BuildFromBNetInfo(game)
    else
        local realm = game.realmName or ""
        if realm ~= "" then
            senderName = game.characterName .. "-" .. realm:gsub("%s+", "")
        else
            local playerRealm = Addon.runtime.playerRealm or GetRealmName()
            senderName = game.characterName .. "-" .. playerRealm:gsub("%s+", "")
        end
    end
    
    if senderName then
        Addon.Communication:HandleMessage(message, senderName, "BNET")
    end
end

handlers["FRIENDLIST_UPDATE"] = function()
    -- Friends list updated, trigger refresh if visible
    if Addon.runtime.initialized and SocialLFGFrame and SocialLFGFrame:IsShown() then
        Addon.Communication:ScheduleQuery()
    end
end

handlers["BN_FRIEND_ACCOUNT_ONLINE"] = function()
    -- Battle.net friend came online
    if Addon.runtime.initialized and SocialLFGFrame and SocialLFGFrame:IsShown() then
        Addon.Communication:ScheduleQuery()
    end
end

handlers["BN_FRIEND_ACCOUNT_OFFLINE"] = function()
    -- Battle.net friend went offline
    if Addon.runtime.initialized then
        Addon.Members:CleanupOfflinePlayers()
    end
end

handlers["GUILD_ROSTER_UPDATE"] = function()
    -- Guild roster updated
    if Addon.runtime.initialized and SocialLFGFrame and SocialLFGFrame:IsShown() then
        Addon.Communication:ScheduleQuery()
    end
end

handlers["INITIAL_CLUBS_LOADED"] = function()
    if not Addon.runtime.initialized then return end

    -- Clubs list refreshed; update UI or clean up
    if SocialLFGFrame and SocialLFGFrame:IsShown() then
        Addon.Communication:ScheduleQuery()
    else
        Addon.Members:CleanupOfflinePlayers()
    end
end

handlers["CLUB_ADDED"] = function(...)
    if not Addon.runtime.initialized then return end
    
    Addon.Communication:ScheduleQuery()
end

handlers["CLUB_REMOVED"] = function(...)
    if not Addon.runtime.initialized then return end
    
    Addon.Communication:ScheduleQuery()
end

handlers["CLUB_MEMBER_UPDATED"] = function(...)
    if not Addon.runtime.initialized then return end
    -- Member details changed; refresh our queries
    Addon.Communication:ScheduleQuery()
end

handlers["CLUB_MEMBER_PRESENCE_UPDATED"] = function(...)
    if not Addon.runtime.initialized then return end

    -- Presence changed; if UI visible, query now, otherwise perform cleanup
    if SocialLFGFrame and SocialLFGFrame:IsShown() then
        Addon.Communication:ScheduleQuery()
    else
        Addon.Members:CleanupOfflinePlayers()
    end
end

handlers["GROUP_FORMED"] = function()
    if not Addon.runtime.initialized then return end
    
    -- Player joined a group
    if Addon:IsRegistered() then
        -- Save that we were registered before joining group
        Addon.Database:SetWasRegisteredBeforeGroup(true)
        
        -- Unregister (can't be LFG while in group)
        Addon:Unregister()
    end
    
    Addon:UpdateState()
    Addon:FireCallback("OnGroupStatusChanged")
end

handlers["GROUP_LEFT"] = function()
    if not Addon.runtime.initialized then return end
    
    -- Player left group
    if Addon.Database:WasRegisteredBeforeGroup() then
        -- Re-register with previous preferences
        local categories = Addon.Database:GetSavedCategories()
        local roles = Addon.Database:GetSavedRoles()
        
        if #categories > 0 and #roles > 0 then
            Addon:Register(categories, roles)
        end
        
        Addon.Database:SetWasRegisteredBeforeGroup(false)
    end
    
    Addon:UpdateState()
    Addon:FireCallback("OnGroupStatusChanged")
end

handlers["BAG_UPDATE_DELAYED"] = function()
    if not Addon.runtime.initialized then return end
    Addon.Player:UpdateKeystone()
end

handlers["CHALLENGE_MODE_MAPS_UPDATE"] = function()
    if not Addon.runtime.initialized then return end
    Addon.Player:UpdateKeystone()
end

-- =============================================================================
-- Event Registration
-- =============================================================================

function Events:Initialize()
    -- Register all events
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("BN_CHAT_MSG_ADDON")  -- BNet addon messages for cross-realm
    eventFrame:RegisterEvent("FRIENDLIST_UPDATE")
    eventFrame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
    eventFrame:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
    eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
    -- Register club events only on clients that expose the Club API
    if C_Club and C_Club.GetSubscribedClubs then
        eventFrame:RegisterEvent("INITIAL_CLUBS_LOADED")
        eventFrame:RegisterEvent("CLUB_MEMBER_UPDATED")
        eventFrame:RegisterEvent("CLUB_MEMBER_PRESENCE_UPDATED")
        eventFrame:RegisterEvent("CLUB_ADDED")
        eventFrame:RegisterEvent("CLUB_REMOVED")
    end
    eventFrame:RegisterEvent("GROUP_FORMED")
    eventFrame:RegisterEvent("GROUP_LEFT")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    
    -- Set up event dispatcher
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        local handler = handlers[event]
        if handler then
            handler(...)
        end
    end)
end

-- Initialize event system immediately (before ADDON_LOADED)
Events:Initialize()
