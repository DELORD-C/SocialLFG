SocialLFG = {}
local PREFIX = "SocialLFG"

-- Constants
local CONSTANTS = {
    TIMEOUT = 60,
    QUERY_INTERVAL = 10,  -- Increased from 5s to 10s for better performance
    ROW_HEIGHT = 24,
    ROLE_ICON_SIZE = 12,
    CLASS_ICON_SIZE = 16,
    CATEGORIES = {"Raid", "Mythic+", "Questing", "Dungeon", "Boosting", "PVP"},
    ROLES = {"Tank", "Heal", "DPS"},
}

-- StaticPopup to notify missing RaiderIO
StaticPopupDialogs["SOCIALLFG_RIO_MISSING"] = {
    text = "Avec l'add-on RaiderIO, vous aurez des informations plus précises.",
    button1 = "Ne plus afficher",
    button2 = "Fermer",
    OnAccept = function()
        if SocialLFG and SocialLFG.db then
            SocialLFG.db.rioNoticeDismissed = true
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function SocialLFG:ShowRioMissingPopup()
    if not self.db or self.db.rioNoticeDismissed then
        return
    end
    if IsAddOnLoaded and (IsAddOnLoaded("RaiderIO") or RaiderIO) then
        return
    end
    StaticPopup_Show("SOCIALLFG_RIO_MISSING")
end


-- Logging utilities with consistent formatting
local function Log(level, msg)
    if msg and msg ~= "" then
        local timestamp = date("%H:%M:%S")
        local prefix = "|cFF4DA6FFSocialLFG|r"
        local levelStr = ""
        
        if level == "WARN" then
            levelStr = "|cFFFF9900[WARN]|r"
        elseif level == "ERROR" then
            levelStr = "|cFFFF6B6B[ERROR]|r"
        elseif level == "INFO" then
            levelStr = "|cFF00FF00[INFO]|r"
        end
        
        print(string.format("%s %s %s", prefix, levelStr, msg))
    end
end

function SocialLFG:LogDebug(msg) 
    -- Debug logging disabled by default for clean UI
    -- Uncomment below to enable during development
    -- Log("DEBUG", msg)
end

function SocialLFG:LogInfo(msg) Log("INFO", msg) end
function SocialLFG:LogWarn(msg) Log("WARN", msg) end
function SocialLFG:LogError(msg) Log("ERROR", msg) end
-- Class role mapping
local CLASS_ROLES = {
    ["WARRIOR"] = {"Tank", "DPS"},
    ["PALADIN"] = {"Tank", "Heal", "DPS"},
    ["HUNTER"] = {"DPS"},
    ["ROGUE"] = {"DPS"},
    ["PRIEST"] = {"Heal", "DPS"},
    ["DEATHKNIGHT"] = {"Tank", "DPS"},
    ["SHAMAN"] = {"Heal", "DPS"},
    ["MAGE"] = {"DPS"},
    ["WARLOCK"] = {"DPS"},
    ["MONK"] = {"Tank", "Heal", "DPS"},
    ["DRUID"] = {"Tank", "Heal", "DPS"},
    ["DEMONHUNTER"] = {"Tank", "DPS"},
    ["EVOKER"] = {"Heal", "DPS"},
}

function SocialLFG:OnLoad()
    self.frame = SocialLFGFrame
    self:RegisterFrameEvents()
    self:ConfigureFrameProperties()
    self:RestrictRolesByClass()
    self:RegisterAddonMessagePrefix()
    self:RegisterSpecialFrames()
    self:InitializeUpdateTimer()
    self:RegisterKeystoneEvents()
end

function SocialLFG:InitializeUpdateTimer()
    -- Initialize throttle timer for performance optimization
    self.lastUpdateTime = 0
    self.lastQueryTime = 0
    self.playerKeystone = nil
    self.lastListUpdateTime = 0
    self.listUpdateThrottle = 0.5  -- Throttle list updates to max 0.5 seconds
end

-- ============================================================================
-- Keystone Management
-- ============================================================================

function SocialLFG:RegisterKeystoneEvents()
    -- Listen for keystone changes (bag updates and challenge mode map updates)
    self.keystoneFrame = CreateFrame("Frame")
    self.keystoneFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    self.keystoneFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    self.keystoneFrame:SetScript("OnEvent", function(frame, event, ...)
        SocialLFG:UpdatePlayerKeystone()
    end)
end

function SocialLFG:GetPlayerKeystone()
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()
    
    if not mapID or not level or level == 0 then
        return nil -- No keystone in inventory
    end
    
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    
    return {
        mapID = mapID,
        level = level,
        name = name,
    }
end

function SocialLFG:UpdatePlayerKeystone()
    local ks = self:GetPlayerKeystone()
    
    -- Check if keystone actually changed
    local keystoneChanged = false
    if (self.playerKeystone == nil) ~= (ks == nil) then
        keystoneChanged = true
    elseif ks and self.playerKeystone then
        if ks.mapID ~= self.playerKeystone.mapID or ks.level ~= self.playerKeystone.level then
            keystoneChanged = true
        end
    end
    
    -- Update the cached keystone
    self.playerKeystone = ks
    
    -- If keystone changed and we're registered, resend our status
    if keystoneChanged and #self.db.myStatus.categories > 0 then
        self:SendUpdate()
    end
    
    -- Update the list if shown
    if self.frame:IsShown() then
        self:AddPlayerToOwnList()
        self:UpdateList()
    end
end

-- Mythic+ Dungeon ID to English Short Name mapping (universal across all locales)
-- Maps challengeModeID to dungeon abbreviation
local DUNGEON_ID_TO_SHORT_NAME = {
    [499] = "PSF",
    [542] = "ECO",
    [378] = "HOA",
    [525] = "FLO",
    [503] = "AKA",
    [392] = "GBT",
    [391] = "STR",
    [505] = "DB",
}

function SocialLFG:FormatKeystoneString(keystone)
    if not keystone then
        return "-"
    end
    
    -- For local player, format the keystone table object
    if keystone.mapID and keystone.level then
        return self:FormatKeystoneFromMapIDAndLevel(keystone.mapID, keystone.level)
    end
    
    return "-"
end

function SocialLFG:FormatKeystoneFromMapIDAndLevel(mapID, level)
    -- Get English short name from mapID (universal across all locales)
    local shortName = DUNGEON_ID_TO_SHORT_NAME[mapID]
    
    if not shortName then
        -- Fallback: unknown mapID
        shortName = "UNK"
    end
    
    return string.format("%s+%d", shortName, level)
end

-- Class color and icon helpers
function SocialLFG:GetClassColor(class)
    if not class then
        return NORMAL_FONT_COLOR
    end
    return RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
end

function SocialLFG:GetColoredPlayerName(name, class)
    if not name or not class then
        return name or "Unknown"
    end
    local color = self:GetClassColor(class)
    return ("|c%s%s|r"):format(color.colorStr, name)
end

function SocialLFG:SetClassIcon(texture, class)
    if not class then
        texture:Hide()
        return
    end
    
    -- Set atlas without auto-scale to maintain proper size
    texture:SetAtlas("classicon-"..class:lower(), false)
    texture:Show()
end

function SocialLFG:RegisterFrameEvents()
    self.frame:RegisterEvent("ADDON_LOADED")
    self.frame:RegisterEvent("CHAT_MSG_ADDON")
    self.frame:RegisterEvent("FRIENDLIST_UPDATE")
    self.frame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
    self.frame:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
    self.frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    self.frame:RegisterEvent("GROUP_FORMED")
    self.frame:RegisterEvent("GROUP_LEFT")
    self.frame:SetScript("OnEvent", function(_, event, ...) SocialLFG:OnEvent(event, ...) end)
    self.frame:SetScript("OnShow", function() SocialLFG:OnShow() end)
end

function SocialLFG:ConfigureFrameProperties()
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
    self.frame:SetFrameStrata("DIALOG")
    self.frame:SetFrameLevel(100)
end

function SocialLFG:RestrictRolesByClass()
    local _, class = UnitClass("player")
    local allowedRoles = CLASS_ROLES[class] or CONSTANTS.ROLES
    
    -- Hide checkboxes for roles not available to this class
    if not tContains(allowedRoles, "Tank") then 
        SocialLFGTankCheck:Hide()
    end
    if not tContains(allowedRoles, "Heal") then 
        SocialLFGHealCheck:Hide()
    end
    if not tContains(allowedRoles, "DPS") then 
        SocialLFGDPSCheck:Hide()
    end
    
    -- Reposition remaining role checkboxes
    self:RepositionRoleCheckboxes(allowedRoles)
end

function SocialLFG:RepositionRoleCheckboxes(allowedRoles)
    local roleCheckboxes = {
        {name = "Tank", frame = SocialLFGTankCheck},
        {name = "Heal", frame = SocialLFGHealCheck},
        {name = "DPS", frame = SocialLFGDPSCheck},
    }
    
    local firstVisibleRole = nil
    local previousRole = nil
    
    for _, roleData in ipairs(roleCheckboxes) do
        if tContains(allowedRoles, roleData.name) then
            if not firstVisibleRole then
                -- First visible role stays anchored to original position
                firstVisibleRole = roleData.frame
                roleData.frame:ClearAllPoints()
                roleData.frame:SetPoint("TOPLEFT", SocialLFGFrame, "TOPLEFT", 20, -110)
            else
                -- Reposition subsequent roles relative to previous visible role
                roleData.frame:ClearAllPoints()
                roleData.frame:SetPoint("LEFT", previousRole, "RIGHT", 60, 0)
            end
            previousRole = roleData.frame
        end
    end
end

function SocialLFG:RegisterAddonMessagePrefix()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

function SocialLFG:RegisterSpecialFrames()
    table.insert(UISpecialFrames, "SocialLFGFrame")
end

function SocialLFG:OnEvent(event, ...)
    if event == "ADDON_LOADED" and ... == "SocialLFG" then
        self:InitializeDatabase()
        -- Only query on addon load if registered
        if #self.db.myStatus.categories > 0 then
            self:QueryAllPlayers()
        end
        if #self.db.myStatus.categories > 0 then
            -- Delay SendUpdate to allow RaiderIO to initialize
            C_Timer.After(2, function()
                if SocialLFG then
                    SocialLFG:SendUpdate()
                    -- Add player to their own list on reload if registered
                    SocialLFG:AddPlayerToOwnList()
                end
            end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == PREFIX then
            self:HandleAddonMessage(message, sender, channel)
        end
    elseif event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_ACCOUNT_ONLINE" or event == "BN_FRIEND_ACCOUNT_OFFLINE" then
        self:UpdateFriends()
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Guild roster updated
    elseif event == "GROUP_FORMED" or event == "GROUP_LEFT" then
        self:HandleGroupStatusChange(event)
    end
end

function SocialLFG:InitializeDatabase()
    if not SocialLFGDB then
        SocialLFGDB = {
            myStatus = {categories = {}, roles = {}},
            queriedFriends = {},
        }
    end
    
    self.db = SocialLFGDB
    self.listFrames = {}
    self.lfgMembers = {}
    self.lastSeen = {}
    self.TIMEOUT = CONSTANTS.TIMEOUT
    self.rioInitialized = false
    self.hasInitialQuery = false
    
    self:EnsureDatabaseFields()
    self:LogDatabaseStatus()
    self:RestoreCheckboxStates()
    self:UpdatePlayerKeystone()  -- Initialize keystone on load
    self:UpdateMinimapIcon()  -- Update icon appearance on load
end

function SocialLFG:EnsureDatabaseFields()
    if not self.db.myStatus then
        self.db.myStatus = {categories = {}, roles = {}}
    end
    if not self.db.myStatus.categories then
        self.db.myStatus.categories = {}
    end
    if not self.db.myStatus.roles then
        self.db.myStatus.roles = {}
    end
    if not self.db.queriedFriends then
        self.db.queriedFriends = {}
    end
    if not self.db.savedCategories then
        self.db.savedCategories = {}
    end
    if not self.db.savedRoles then
        self.db.savedRoles = {}
    end
    if not self.db.wasRegisteredBeforeGroup then
        self.db.wasRegisteredBeforeGroup = false
    end
end

function SocialLFG:LogDatabaseStatus()
end

function SocialLFG:RestoreCheckboxStates()
    if #self.db.myStatus.categories > 0 then
        for _, cat in ipairs(self.db.myStatus.categories) do
            if cat == "Raid" then SocialLFGRaidCheck:SetChecked(true) end
            if cat == "Mythic+" then SocialLFGMythicCheck:SetChecked(true) end
            if cat == "Questing" then SocialLFGQuestingCheck:SetChecked(true) end
            if cat == "Boosting" then SocialLFGBoostingCheck:SetChecked(true) end
            if cat == "PVP" then SocialLFGPVPCheck:SetChecked(true) end
        end
        for _, role in ipairs(self.db.myStatus.roles) do
            if role == "Tank" then SocialLFGTankCheck:SetChecked(true) end
            if role == "Heal" then SocialLFGHealCheck:SetChecked(true) end
            if role == "DPS" then SocialLFGDPSCheck:SetChecked(true) end
        end
    else
        for _, cat in ipairs(self.db.savedCategories) do
            if cat == "Raid" then SocialLFGRaidCheck:SetChecked(true) end
            if cat == "Mythic+" then SocialLFGMythicCheck:SetChecked(true) end
            if cat == "Questing" then SocialLFGQuestingCheck:SetChecked(true) end
            if cat == "Boosting" then SocialLFGBoostingCheck:SetChecked(true) end
            if cat == "PVP" then SocialLFGPVPCheck:SetChecked(true) end
        end
        for _, role in ipairs(self.db.savedRoles) do
            if role == "Tank" then SocialLFGTankCheck:SetChecked(true) end
            if role == "Heal" then SocialLFGHealCheck:SetChecked(true) end
            if role == "DPS" then SocialLFGDPSCheck:SetChecked(true) end
        end
    end
end

function SocialLFG:HandleGroupStatusChange(event)
    if event == "GROUP_FORMED" then
        -- Player joined a group
        if #self.db.myStatus.categories > 0 then
            self.db.wasRegisteredBeforeGroup = true
            self:UnregisterLFG()
        end
        -- Update button state to show "In a group"
        self:UpdateButtonState()
    elseif event == "GROUP_LEFT" then
        -- Player left group - re-register if they were registered before
        if self.db.wasRegisteredBeforeGroup then
            -- Restore saved status and re-register
            self.db.myStatus = {
                categories = self.db.savedCategories or {},
                roles = self.db.savedRoles or {}
            }
            self:SendUpdate()
            self:UpdateButtonState()
            self:UpdateMinimapIcon()
            if self.frame:IsShown() then
                self:OnShow()
            end
            self.db.wasRegisteredBeforeGroup = false
        else
            -- Even if not re-registering, update button state and icon
            self:UpdateButtonState()
            self:UpdateMinimapIcon()
        end
    end
end

function SocialLFG:HandleAddonMessage(message, sender, channel)
    if not message or not sender then
        return
    end
    
    -- Safely parse message with delimiter
    local parts = self:SplitMessage(message, "|")
    if not parts or #parts < 1 then
        return
    end
    
    local cmd = parts[1]
    
    if cmd == "STATUS" then
        self:HandleStatusMessage(sender, parts[2], parts[3], parts[4], parts[5], parts[6], parts[7])
    elseif cmd == "QUERY" then
        self:HandleQueryMessage(sender)
    elseif cmd == "UNREGISTER" then
        self:UpdateStatus(sender, nil)
    end
end

function SocialLFG:SplitMessage(message, delimiter)
    if not message then return {} end
    
    local parts = {}
    local start = 1
    
    while true do
        local pos = message:find(delimiter, start, true)
        if not pos then
            -- Last part
            table.insert(parts, message:sub(start))
            break
        else
            table.insert(parts, message:sub(start, pos - 1))
            start = pos + #delimiter
        end
    end
    
    return parts
end

function SocialLFG:IsValidPlayerName(name)
    if not name or name == "" then
        return false
    end
    
    -- Player names should have format "Name-Realm" or just "Name"
    -- Names should not contain certain control characters, but can contain Unicode
    local hasControlChars = false
    for i = 1, #name do
        local byte = string.byte(name, i)
        if byte and byte < 32 then
            hasControlChars = true
            break
        end
    end
    
    return not hasControlChars
end

function SocialLFG:NormalizePlayerName(playerString)
    -- Normalize player names by handling edge cases
    if not playerString or playerString == "" then
        return nil
    end
    
    -- Remove any leading/trailing whitespace
    playerString = playerString:match("^%s*(.-)%s*$")
    
    -- Return the normalized name
    return playerString ~= "" and playerString or nil
end

function SocialLFG:ExtractCharacterName(fullName)
    -- Safely extract character name from "Name-Realm" format
    -- This handles realms with special characters like apostrophes
    if not fullName or fullName == "" then
        return nil
    end
    
    -- Find the last hyphen (realm names can have hyphens too)
    local lastHyphen = fullName:match("^(.+)%-([^%-]+)$")
    if lastHyphen then
        return lastHyphen
    end
    
    -- If no hyphen found, the entire string is the character name
    return fullName
end

function SocialLFG:HandleStatusMessage(sender, arg1, arg2, arg3, arg4, arg5, arg6)
    -- Never update local player data from incoming messages
    -- Local player data should ONLY be updated via AddPlayerToOwnList() from local events
    
    -- Validate sender name
    if not self:IsValidPlayerName(sender) then
        return
    end
    
    local myName = self:GetLocalPlayerFullName()
    if sender == myName then
        return
    end
    
    self.lastSeen[sender] = GetTime()
    
    local categories = self:ParseCategories(arg1)
    local roles = self:ParseRoles(arg2)
    local ilvl = tonumber(arg3) or 0
    local rio = tonumber(arg4) or 0
    local class = arg5 or nil
    local keystoneStr = arg6 or "-"  -- Format: "DUNGEON+level" or "-" (already formatted)
    
    if #categories > 0 then
        self:UpdateStatus(sender, {
            categories = categories,
            roles = roles,
            ilvl = ilvl,
            rio = rio,
            class = class,
            keystone = keystoneStr
        })
    else
        self:UpdateStatus(sender, nil)
    end
end

function SocialLFG:ParseCategories(categoryString)
    local categories = {}
    if categoryString and categoryString ~= "" then
        for cat in categoryString:gmatch("[^,]+") do
            table.insert(categories, cat)
        end
    end
    return categories
end

function SocialLFG:ParseRoles(roleString)
    local roles = {}
    if roleString and roleString ~= "" then
        for role in roleString:gmatch("[^,]+") do
            table.insert(roles, role)
        end
    end
    return roles
end

function SocialLFG:HandleQueryMessage(sender)
    if #self.db.myStatus.categories > 0 then
        local ilvl = math.floor(GetAverageItemLevel())
        local rio = self:GetRioScore()
        local _, class = UnitClass("player")
        
        -- Send keystone as formatted string (already formatted)
        local keystoneStr = self:FormatKeystoneString(self.playerKeystone)
        
        self:SendAddonMessage("STATUS|" .. table.concat(self.db.myStatus.categories, ",") .. "|" .. table.concat(self.db.myStatus.roles, ",") .. "|" .. ilvl .. "|" .. rio .. "|" .. (class or "") .. "|" .. keystoneStr, "WHISPER", sender)
    end
end

function SocialLFG:UpdateStatus(player, status)
    if not self:IsValidPlayerName(player) then
        self:LogError("Attempted to update status for invalid player name: " .. tostring(player))
        return
    end
    
    local localPlayer = self:GetLocalPlayerFullName()
    
    -- Never remove local player via UpdateStatus - only via explicit UnregisterLFG
    if player == localPlayer then
        return
    end
    
    if status == nil or (status.categories and #status.categories == 0) then
        if self.lfgMembers[player] ~= nil then
            self.lfgMembers[player] = nil
            self.lastSeen[player] = nil
        end
        self:UpdateListIfShown()
    elseif status and status.categories and #status.categories > 0 then
        self.lfgMembers[player] = status
        self:UpdateListIfShown()
    end
end

function SocialLFG:UpdateListIfShown()
    -- Update immediately when messages are received; throttle only applies to periodic queries
    if self.frame:IsShown() then
        self:UpdateList()
    end
end

function SocialLFG:CheckTimeouts()
    local currentTime = GetTime()
    local removed = false
    local localPlayer = self:GetLocalPlayerFullName()
    
    -- Get current online friends to detect disconnects
    local onlineFriends = {}
    for _, name in ipairs(self:GetAllOnlineFriends()) do
        onlineFriends[name] = true
    end
    
    for player, lastTime in pairs(self.lastSeen) do
        -- Never timeout the local player
        if player == localPlayer then
            -- Keep local player's timeout current
            self.lastSeen[player] = currentTime
        else
            local isOnline = onlineFriends[player] == true
            local timeSinceLastSeen = currentTime - lastTime
            
            -- Remove if offline (no longer in friends list) AND timeout threshold exceeded
            if not isOnline and timeSinceLastSeen > self.TIMEOUT then
                self.lfgMembers[player] = nil
                self.lastSeen[player] = nil
                removed = true
            -- Remove if only regular timeout exceeded (shouldn't happen if receiving updates, but safety net)
            elseif timeSinceLastSeen > (self.TIMEOUT * 3) then
                self.lfgMembers[player] = nil
                self.lastSeen[player] = nil
                removed = true
            end
        end
    end
    
    if removed and self.frame:IsShown() then
        self:UpdateList()
    end
end

function SocialLFG:CountMembers()
    local count = 0
    for _ in pairs(self.lfgMembers) do count = count + 1 end
    return count
end

function SocialLFG:GetOnlineFriends()
    local friends = {}
    local num = C_FriendList.GetNumOnlineFriends()
    if not num then return friends end
    
    for i = 1, num do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected then
            local fullName = info.name
            if info.realmName and info.realmName ~= "" then
                fullName = info.name .. "-" .. info.realmName
            end
            table.insert(friends, fullName)
        end
    end
    
    return friends
end

function SocialLFG:GetOnlineBNFriends()
    local friends = {}
    local num = BNGetNumFriends()
    if not num then return friends end
    
    for i = 1, num do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
            local game = accountInfo.gameAccountInfo
            if game.clientProgram == "WoW" then
                local fullName = game.characterName
                if game.realmName and game.realmName ~= "" then
                    fullName = game.characterName .. "-" .. game.realmName
                end
                table.insert(friends, fullName)
            end
        end
    end
    
    return friends
end

function SocialLFG:GetAllOnlineFriends()
    local friends = {}
    
    for _, name in ipairs(self:GetOnlineFriends()) do
        table.insert(friends, name)
    end
    
    for _, name in ipairs(self:GetOnlineBNFriends()) do
        table.insert(friends, name)
    end
    
    return friends
end

function SocialLFG:GetLocalPlayerFullName()
    return UnitName("player") .. "-" .. GetRealmName()
end

function SocialLFG:UpdateFriends()
    local friends = self:GetAllOnlineFriends()
    
    for _, fullName in ipairs(friends) do
        if self:IsValidPlayerName(fullName) then
            self:SendAddonMessage("QUERY", "WHISPER", fullName)
            self.db.queriedFriends[fullName] = true
        else
            self:LogWarn("Skipping friend query for invalid name: " .. tostring(fullName))
        end
    end
end

function SocialLFG:SendAddonMessage(message, channel, target)
    if not message or message == "" then
        self:LogError("Attempted to send empty addon message")
        return
    end
    
    -- Validate parameters
    if channel ~= "GUILD" and channel ~= "WHISPER" and channel ~= "PARTY" and channel ~= "RAID" then
        self:LogError("Invalid channel: " .. tostring(channel))
        return
    end
    
    if channel == "WHISPER" and (not target or target == "") then
        self:LogError("WHISPER channel requires a valid target")
        return
    end
    
    if channel == "WHISPER" and not self:IsValidPlayerName(target) then
        self:LogError("Invalid target player name: " .. tostring(target))
        return
    end
    
    C_ChatInfo.SendAddonMessage(PREFIX, message, channel, target)
end

function SocialLFG:ToggleWindow()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function SocialLFG:UpdateButtonState()
    -- Check if player is in a group
    local inGroup = IsInGroup()
    
    if inGroup then
        -- Disable button when in a group
        SocialLFGRegisterButton:SetText("In a group")
        SocialLFGRegisterButton:Disable()
    elseif #self.db.myStatus.categories > 0 then
        SocialLFGRegisterButton:SetText("Unregister")
        SocialLFGRegisterButton:Enable()
    else
        local categories = self:GetCheckedCategories()
        local roles = self:GetCheckedRoles()
        if #categories > 0 and #roles > 0 then
            SocialLFGRegisterButton:SetText("Register LFG")
            SocialLFGRegisterButton:Enable()
        else
            SocialLFGRegisterButton:SetText("Select categories and roles")
            SocialLFGRegisterButton:Disable()
        end
    end
end

function SocialLFG:UpdateMinimapIcon()
    -- Update the minimap icon appearance and tooltip
    -- The plugin is made available globally by ldb.lua
    if _G.SocialLFGPlugin and _G.SocialLFGPlugin.UpdateIconAppearance then
        _G.SocialLFGPlugin:UpdateIconAppearance()
    end
end

function SocialLFG:SaveCheckboxState()
    self.db.savedCategories = self:GetCheckedCategories()
    self.db.savedRoles = self:GetCheckedRoles()
end

function SocialLFG:GetCheckedCategories()
    local categories = {}
    if SocialLFGRaidCheck:GetChecked() then table.insert(categories, "Raid") end
    if SocialLFGMythicCheck:GetChecked() then table.insert(categories, "Mythic+") end
    if SocialLFGQuestingCheck:GetChecked() then table.insert(categories, "Questing") end
    if SocialLFGBoostingCheck:GetChecked() then table.insert(categories, "Boosting") end
    if SocialLFGPVPCheck:GetChecked() then table.insert(categories, "PVP") end
    return categories
end

function SocialLFG:GetCheckedRoles()
    local roles = {}
    -- Only check visible (non-hidden) role checkboxes
    if SocialLFGTankCheck:IsVisible() and SocialLFGTankCheck:GetChecked() then table.insert(roles, "Tank") end
    if SocialLFGHealCheck:IsVisible() and SocialLFGHealCheck:GetChecked() then table.insert(roles, "Heal") end
    if SocialLFGDPSCheck:IsVisible() and SocialLFGDPSCheck:GetChecked() then table.insert(roles, "DPS") end
    return roles
end

function SocialLFG:BroadcastToAll(channel, message, target)
    self:SendAddonMessage(message, channel, target)
end

function SocialLFG:SafeInvitePlayer(player, charName)
    if not player or player == "" then
        self:LogError("Cannot invite: invalid player name")
        return
    end
    
    if not charName or charName == "" then
        charName = strsplit("-", player) or player
    end
    
    -- Try multiple invite methods in order of preference
    -- Method 1: Try with full name (Name-Realm format)
    if pcall(function() C_PartyInfo.InviteUnit(player) end) then
        self:LogInfo("Invited: " .. player)
        return
    end
    
    -- Method 2: Try with character name only
    if pcall(function() C_PartyInfo.InviteUnit(charName) end) then
        self:LogInfo("Invited: " .. charName)
        return
    end
    
    -- Method 3: Use chat command as fallback (safest for special characters)
    ChatFrame_SendTell(charName, true)
    if ChatFrame1 and ChatFrame1:IsVisible() then
        -- Chat window is open, will invite via command
        ChatFrame_OpenChat("/invite " .. charName, ChatFrame1)
    else
        -- Fallback to using the invite command directly
        SlashCmdList["INVITE"](charName)
    end
    
    self:LogWarn("Invited " .. charName .. " using alternative method")
end

function SocialLFG:BroadcastToGuildAndFriends(message)
    if not message or message == "" then
        self:LogError("Attempted to broadcast empty message")
        return
    end
    
    self:BroadcastToAll("GUILD", message)
    local friends = self:GetAllOnlineFriends()
    for _, fullName in ipairs(friends) do
        if self:IsValidPlayerName(fullName) then
            self:BroadcastToAll("WHISPER", message, fullName)
        end
    end
end

function SocialLFG:ToggleLFG()
    if #self.db.myStatus.categories > 0 then
        self:UnregisterLFG()
    else
        self:RegisterLFG()
    end
end

function SocialLFG:RegisterLFG()
    -- Try to get checked categories from UI, fall back to saved if window is closed
    local categories = self:GetCheckedCategories()
    if #categories == 0 then
        categories = self.db.savedCategories or {}
    end
    
    -- Try to get checked roles from UI, fall back to saved if window is closed
    local roles = self:GetCheckedRoles()
    if #roles == 0 then
        roles = self.db.savedRoles or {}
    end
    
    -- Validate that both categories and roles are selected
    if #categories == 0 then
        self:LogWarn("Cannot register: Please select at least one category")
        return
    end
    if #roles == 0 then
        self:LogWarn("Cannot register: Please select at least one role")
        return
    end
    
    self.db.myStatus = {categories = categories, roles = roles}
    self.db.savedCategories = categories
    self.db.savedRoles = roles
    self:SendUpdate()
    self:AddPlayerToOwnList()
    self:UpdateButtonState()
    self:UpdateMinimapIcon()
end

function SocialLFG:UnregisterLFG()
    local playerFullName = self:GetLocalPlayerFullName()
    self.db.myStatus = {categories = {}, roles = {}}
    -- Only the explicit unregister should remove the local player
    self.lfgMembers[playerFullName] = nil
    self.lastSeen[playerFullName] = nil
    self:BroadcastToGuildAndFriends("UNREGISTER")
    self:UpdateButtonState()
    self:UpdateMinimapIcon()
    self:UpdateList()
end

function SocialLFG:GetRioScore()
    -- Verify RaiderIO addon is available
    if not RaiderIO then
        self:ShowRioMissingPopup()
        return 0
    end
    
    if not RaiderIO.GetProfile then
        return 0
    end
    
    -- Get the current player's profile
    -- The second parameter "player" indicates we want the local player's data
    local profile = RaiderIO.GetProfile("player", "player")
    
    if not profile then
        return 0
    end
    
    if not profile.mythicKeystoneProfile then
        return 0
    end
    
    -- Prefer warbandCurrentScore (account-wide) but fall back to currentScore if it's 0
    local score = profile.mythicKeystoneProfile.warbandCurrentScore
    if not score or score == 0 then
        score = profile.mythicKeystoneProfile.currentScore
    end
    
    if not score or score == 0 then
        return 0
    end
    
    return math.floor(score)
end

function SocialLFG:GetTableKeys(tbl)
    local keys = {}
    if tbl then
        for k in pairs(tbl) do
            table.insert(keys, tostring(k))
        end
    end
    return keys
end

function SocialLFG:SendUpdate()
    local ilvl = math.floor(GetAverageItemLevel())
    local rio = self:GetRioScore()
    local _, class = UnitClass("player")
    
    -- Send keystone as formatted string (already formatted)
    local keystoneStr = self:FormatKeystoneString(self.playerKeystone)
    
    -- Retry if RaiderIO exists but Rio is still 0 (means it's not loaded yet)
    if rio == 0 and RaiderIO then
        C_Timer.After(1, function()
            if SocialLFG and #SocialLFG.db.myStatus.categories > 0 then
                SocialLFG:SendUpdate()
            end
        end)
        return
    end
    
    local msg = "STATUS|" .. table.concat(self.db.myStatus.categories, ",") .. "|" .. table.concat(self.db.myStatus.roles, ",") .. "|" .. ilvl .. "|" .. rio .. "|" .. (class or "") .. "|" .. keystoneStr
    self:BroadcastToGuildAndFriends(msg)
    -- Always add player to their own list when sending update
    self:AddPlayerToOwnList()
end

function SocialLFG:SetCheckboxesFromRoles(roles)
    -- Only set visible checkboxes
    if SocialLFGTankCheck:IsVisible() then
        SocialLFGTankCheck:SetChecked(tContains(roles, "Tank"))
    end
    if SocialLFGHealCheck:IsVisible() then
        SocialLFGHealCheck:SetChecked(tContains(roles, "Heal"))
    end
    if SocialLFGDPSCheck:IsVisible() then
        SocialLFGDPSCheck:SetChecked(tContains(roles, "DPS"))
    end
end

function SocialLFG:SetCheckboxesFromCategories(categories)
    SocialLFGRaidCheck:SetChecked(tContains(categories, "Raid"))
    SocialLFGMythicCheck:SetChecked(tContains(categories, "Mythic+"))
    SocialLFGBoostingCheck:SetChecked(tContains(categories, "Boosting"))
    SocialLFGQuestingCheck:SetChecked(tContains(categories, "Questing"))
    SocialLFGPVPCheck:SetChecked(tContains(categories, "PVP"))
end

function SocialLFG:OnShow()
    self:RestoreUIState()
    self:UpdateButtonState()
    self:UpdateMinimapIcon()
    -- Ensure player is in their own list with current data
    self:AddPlayerToOwnList()
    -- Query all players only on first show per session, or periodically via StartPeriodicUpdates
    -- to prevent redundant queries
    if not self.hasInitialQuery then
        self:QueryAllPlayers()
        self.hasInitialQuery = true
    end
    self:UpdateList()
    self:StartPeriodicUpdates()
end

function SocialLFG:OnHide()
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
end

function SocialLFG:RestoreUIState()
    if #self.db.myStatus.categories > 0 then
        SocialLFGRegisterButton:SetText("Unregister")
        self:SetCheckboxesFromRoles(self.db.myStatus.roles)
        self:SetCheckboxesFromCategories(self.db.myStatus.categories)
        SocialLFGRegisterButton:Enable()
    else
        SocialLFGRegisterButton:SetText("Register LFG")
        self:SetCheckboxesFromRoles(self.db.savedRoles)
        self:SetCheckboxesFromCategories(self.db.savedCategories)
        SocialLFGRegisterButton:Disable()
    end
end

function SocialLFG:StartPeriodicUpdates()
    if not self.updateTimer then
        self.updateTimer = C_Timer.NewTicker(CONSTANTS.QUERY_INTERVAL, function()
            if SocialLFG and SocialLFG.frame:IsShown() then
                -- Periodic check for timeouts and query
                SocialLFG:CheckTimeouts()
                SocialLFG:QueryAllPlayers()
                -- UpdateList is only called when data actually changes (via UpdateStatus)
            end
        end)
    end
end

function SocialLFG:QueryAllPlayers()
    -- Send query to guild members
    self:SendAddonMessage("QUERY", "GUILD")
    
    -- Send query to all online friends
    local friends = self:GetAllOnlineFriends()
    for _, fullName in ipairs(friends) do
        if self:IsValidPlayerName(fullName) then
            self:SendAddonMessage("QUERY", "WHISPER", fullName)
        else
            self:LogWarn("Skipping query for invalid player name: " .. tostring(fullName))
        end
    end
end



function SocialLFG:GetRoleAtlas(role)
    -- Return atlas names for role icons (Dragonflight/TWW compatible)
    local ROLE_ATLASES = {
        ["Tank"] = "roleicon-tiny-tank",
        ["Heal"] = "roleicon-tiny-healer",
        ["DPS"] = "roleicon-tiny-dps",
    }
    return ROLE_ATLASES[role] or "roleicon-tiny-dps"
end

function SocialLFG:UpdateList()
    -- Throttle list updates to prevent excessive frame recreation causing blinking
    local currentTime = GetTime()
    if currentTime - self.lastListUpdateTime < self.listUpdateThrottle then
        return
    end
    self.lastListUpdateTime = currentTime
    
    self:DestroyListFrames()
    
    local playerName = UnitName("player")
    local rowIndex = 0
    local sortedPlayers = self:GetSortedPlayers()
    
    for _, player in ipairs(sortedPlayers) do
        if self.lfgMembers[player] then
            self:CreateListRow(player, self.lfgMembers[player], rowIndex, playerName)
            rowIndex = rowIndex + 1
        end
    end
    
    -- Update scroll frame height
    local childHeight = rowIndex * CONSTANTS.ROW_HEIGHT
    SocialLFGScrollChild:SetHeight(math.max(1, childHeight))
    SocialLFGScrollFrame:UpdateScrollChildRect()
end

function SocialLFG:DestroyListFrames()
    for _, frame in ipairs(self.listFrames) do
        frame:Hide()
        frame:ClearAllPoints()
        frame:SetParent(nil)
    end
    wipe(self.listFrames)
end

function SocialLFG:GetSortedPlayers()
    local sortedPlayers = {}
    for player in pairs(self.lfgMembers) do
        table.insert(sortedPlayers, player)
    end
    -- Sort by Rio score (highest to lowest), then by name for players with same Rio
    table.sort(sortedPlayers, function(a, b)
        local rioA = (self.lfgMembers[a] and self.lfgMembers[a].rio) or 0
        local rioB = (self.lfgMembers[b] and self.lfgMembers[b].rio) or 0
        
        if rioA ~= rioB then
            return rioA > rioB  -- Higher rio first
        end
        return a < b  -- Alphabetical fallback
    end)
    return sortedPlayers
end

function SocialLFG:CreateListRow(player, status, rowIndex, currentPlayerName)
    local rowFrame = CreateFrame("Frame", nil, SocialLFGScrollChild)
    rowFrame:SetHeight(CONSTANTS.ROW_HEIGHT)
    rowFrame:SetWidth(580)  -- Increased width to accommodate keystone column
    
    if rowIndex == 0 then
        rowFrame:SetPoint("TOPLEFT", SocialLFGScrollChild, "TOPLEFT", 0, 0)
    else
        rowFrame:SetPoint("TOPLEFT", self.listFrames[rowIndex], "BOTTOMLEFT", 0, 0)
    end
    
    -- Background for alternating rows
    local bg = rowFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    if rowIndex % 2 == 0 then
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
    else
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.1)
    end
    
    -- Get class information for the player (stored in status during message handling)
    local playerClass = status.class
    
    -- Class icon: X=5, W=20
    local classIcon = rowFrame:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(14, 14)  -- Fixed size for class icons
    classIcon:SetPoint("LEFT", rowFrame, "LEFT", 5, 0)
    if playerClass then
        self:SetClassIcon(classIcon, playerClass)
    else
        classIcon:Hide()
    end
    
    -- Player name with class color: X=28, W=90
    local name = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", rowFrame, "LEFT", 28, 0)
    name:SetWidth(90)
    name:SetHeight(CONSTANTS.ROW_HEIGHT)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("MIDDLE")
    
    -- Extract character name without realm (handles realms with special characters like apostrophes)
    local charName = self:ExtractCharacterName(player) or player
    
    -- Apply class color to name if we have class info
    if playerClass then
        name:SetText(self:GetColoredPlayerName(charName, playerClass))
    else
        name:SetText(charName)
    end
    
    -- Add tooltip to show full name with realm
    name:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(player, 1, 1, 1)
        GameTooltip:Show()
    end)
    name:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Role icons: X=125, W=60
    local roleStartX = 125
    for idx, role in ipairs(status.roles) do
        local icon = rowFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", rowFrame, "LEFT", roleStartX + (idx - 1) * 18, 0)
        icon:SetAtlas(self:GetRoleAtlas(role), true)
    end
    
    -- Categories: X=190, W=100
    local categories = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    categories:SetPoint("LEFT", rowFrame, "LEFT", 190, 0)
    categories:SetWidth(100)
    categories:SetHeight(CONSTANTS.ROW_HEIGHT)
    categories:SetJustifyH("LEFT")
    categories:SetJustifyV("MIDDLE")
    categories:SetText(table.concat(status.categories, ", "))
    
    -- iLvL column: X=295, W=40
    local ilvl = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvl:SetPoint("LEFT", rowFrame, "LEFT", 295, 0)
    ilvl:SetWidth(40)
    ilvl:SetHeight(CONSTANTS.ROW_HEIGHT)
    ilvl:SetJustifyH("CENTER")
    ilvl:SetJustifyV("MIDDLE")
    ilvl:SetText(status.ilvl or "0")
    
    -- Rio score column: X=340, W=50
    local rio = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rio:SetPoint("LEFT", rowFrame, "LEFT", 340, 0)
    rio:SetWidth(50)
    rio:SetHeight(CONSTANTS.ROW_HEIGHT)
    rio:SetJustifyH("CENTER")
    rio:SetJustifyV("MIDDLE")
    rio:SetText(status.rio or "0")
    
    -- Keystone column: X=395, W=50
    local keystone = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keystone:SetPoint("LEFT", rowFrame, "LEFT", 395, 0)
    keystone:SetWidth(50)
    keystone:SetHeight(CONSTANTS.ROW_HEIGHT)
    keystone:SetJustifyH("CENTER")
    keystone:SetJustifyV("MIDDLE")
    keystone:SetText(status.keystone or "-")
    
    -- Invite button: X=450, W=65
    if charName ~= currentPlayerName then
        local inviteBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        inviteBtn:SetSize(65, 22)
        inviteBtn:SetPoint("LEFT", rowFrame, "LEFT", 465, 0)
        inviteBtn:SetText("Invite")
        inviteBtn:SetNormalFontObject("GameFontNormalSmall")
        
        -- Use safe invite function that handles special characters in player names
        inviteBtn:SetScript("OnClick", function() 
            if player and player ~= "" then
                SocialLFG:SafeInvitePlayer(player, charName)
            end
        end)
        
        -- Whisper button: X=520, W=65
        local whisperBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        whisperBtn:SetSize(65, 22)
        whisperBtn:SetPoint("LEFT", rowFrame, "LEFT", 535, 0)
        whisperBtn:SetText("Whisper")
        whisperBtn:SetNormalFontObject("GameFontNormalSmall")
        whisperBtn:SetScript("OnClick", function() 
            if charName and charName ~= "" then
                ChatFrame_OpenChat("/w " .. charName .. " ", ChatFrame1)
            end
        end)
    end
    
    table.insert(self.listFrames, rowFrame)
end

function SocialLFG:AddPlayerToOwnList()
    -- Add the current player to their own LFG members list
    -- This is the ONLY way local player data should be updated
    -- This is needed because the player won't receive their own addon messages
    local playerFullName = self:GetLocalPlayerFullName()
    
    -- Only add if registered
    if #self.db.myStatus.categories == 0 then
        return
    end
    
    local ilvl = math.floor(GetAverageItemLevel())
    local rio = self:GetRioScore()
    local _, class = UnitClass("player")
    local keystoneStr = self:FormatKeystoneString(self.playerKeystone)
    
    self.lfgMembers[playerFullName] = {
        categories = self.db.myStatus.categories,
        roles = self.db.myStatus.roles,
        ilvl = ilvl,
        rio = rio,
        class = class,
        keystone = keystoneStr
    }
    self.lastSeen[playerFullName] = GetTime()
    
    if self.frame:IsShown() then
        self:UpdateList()
    end
end

SLASH_SOCIALLFG1 = "/slfg"
SLASH_SOCIALLFG2 = "/sociallfg"
SlashCmdList["SOCIALLFG"] = function(msg)
    SocialLFG.frame:Show()
end