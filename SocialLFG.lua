SocialLFG = {}

local PREFIX = "SocialLFG"

-- Logging utilities
function SocialLFG:LogDebug(msg)
    print("|cFFFF0000[SocialLFG]|r " .. msg)
end

function SocialLFG:LogInfo(msg)
    print("|cFF00FF00[SocialLFG]|r " .. msg)
end

function SocialLFG:LogWarn(msg)
    print("|cFFFF9900[SocialLFG]|r " .. msg)
end
local categories = {"Raid", "Mythic+", "Questing", "Dungeon"}
local roles = {"Tank", "Heal", "DPS"}
local classRoles = {
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
    self:LogDebug("OnLoad called")
    self:LogDebug("SocialLFGDB exists: " .. tostring(SocialLFGDB ~= nil))
    
    self.frame = SocialLFGFrame
    self.frame:RegisterEvent("ADDON_LOADED")
    self.frame:RegisterEvent("CHAT_MSG_ADDON")
    self.frame:RegisterEvent("FRIENDLIST_UPDATE")
    self.frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    self.frame:RegisterEvent("GROUP_FORMED")
    self.frame:RegisterEvent("GROUP_LEFT")
    self.frame:SetScript("OnEvent", function(self, event, ...) SocialLFG:OnEvent(event, ...) end)
    self.frame:SetScript("OnShow", function() SocialLFG:OnShow() end)
    
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
    self.frame:SetFrameStrata("DIALOG")
    self.frame:SetFrameLevel(100)
    
    local _, class = UnitClass("player")
    local allowed = classRoles[class] or roles
    if not tContains(allowed, "Tank") then SocialLFGTankCheck:Disable() end
    if not tContains(allowed, "Heal") then SocialLFGHealCheck:Disable() end
    if not tContains(allowed, "DPS") then SocialLFGDPSCheck:Disable() end
    
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    
    -- Register frame with UISpecialFrames for Escape key handling
    table.insert(UISpecialFrames, "SocialLFGFrame")
    
    self:LogDebug("OnLoad initialization complete")
end

function SocialLFG:OnEvent(event, ...)
    if event == "ADDON_LOADED" and ... == "SocialLFG" then
        self:LogDebug("ADDON_LOADED event fired")
        self:LogDebug("SocialLFGDB exists: " .. tostring(SocialLFGDB ~= nil))
        
        -- Initialize database if it doesn't exist
        if not SocialLFGDB then
            self:LogDebug("Creating new database")
            SocialLFGDB = {
                myStatus = {categories = {}, roles = {}},
                queriedFriends = {},
            }
        end
        self.db = SocialLFGDB
        self.listFrames = {}
        
        -- Single LFG members list (treats guild and friends the same)
        self.lfgMembers = {}
        
        -- Track when we last saw each player (for timeout detection)
        self.lastSeen = {}
        
        -- Timeout period in seconds (remove players not seen for this long)
        self.TIMEOUT = 60
        
        -- Ensure all required fields exist
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
        -- Saved checkbox state (for UI restoration even when not registered)
        if not self.db.savedCategories then
            self.db.savedCategories = {}
        end
        if not self.db.savedRoles then
            self.db.savedRoles = {}
        end
        -- Track if player was registered before joining a group
        if not self.db.wasRegisteredBeforeGroup then
            self.db.wasRegisteredBeforeGroup = false
        end
        
        -- DEBUG: Dump saved data
        self:LogInfo("Database loaded:")
        self:LogInfo("  Categories: " .. (table.concat(self.db.myStatus.categories, ", ") or "(none)"))
        self:LogInfo("  Roles: " .. (table.concat(self.db.myStatus.roles, ", ") or "(none)"))
        
        -- Restore checkbox states if registered
        if #self.db.myStatus.categories > 0 then
            self:LogInfo("Restoring registration state...")
            for _, cat in ipairs(self.db.myStatus.categories) do
                if cat == "Raid" then SocialLFGRaidCheck:SetChecked(true) end
                if cat == "Mythic+" then SocialLFGMythicCheck:SetChecked(true) end
                if cat == "Questing" then SocialLFGQuestingCheck:SetChecked(true) end
            end
            for _, role in ipairs(self.db.myStatus.roles) do
                if role == "Tank" then SocialLFGTankCheck:SetChecked(true) end
                if role == "Heal" then SocialLFGHealCheck:SetChecked(true) end
                if role == "DPS" then SocialLFGDPSCheck:SetChecked(true) end
            end
        else
            -- Restore last selected checkboxes even if not registered
            for _, cat in ipairs(self.db.savedCategories) do
                if cat == "Raid" then SocialLFGRaidCheck:SetChecked(true) end
                if cat == "Mythic+" then SocialLFGMythicCheck:SetChecked(true) end
                if cat == "Questing" then SocialLFGQuestingCheck:SetChecked(true) end
            end
            for _, role in ipairs(self.db.savedRoles) do
                if role == "Tank" then SocialLFGTankCheck:SetChecked(true) end
                if role == "Heal" then SocialLFGHealCheck:SetChecked(true) end
                if role == "DPS" then SocialLFGDPSCheck:SetChecked(true) end
            end
        end
        
        self:SendAddonMessage("QUERY", "GUILD")
        if #self.db.myStatus.categories > 0 then
            self:SendUpdate()
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == PREFIX then
            self:HandleAddonMessage(message, sender, channel)
        end
    elseif event == "FRIENDLIST_UPDATE" then
        self:UpdateFriends()
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Optional: query guild if needed
    elseif event == "GROUP_FORMED" or event == "GROUP_LEFT" then
        self:HandleGroupStatusChange(event)
    end
end

function SocialLFG:HandleGroupStatusChange(event)
    if event == "GROUP_FORMED" then
        -- Player joined a group
        if #self.db.myStatus.categories > 0 then
            self.db.wasRegisteredBeforeGroup = true
            self:LogWarn("Temporarily unregistered while in a group")
            self:UnregisterLFG()
        end
        -- Update button state to show "In a group"
        self:UpdateButtonState()
    elseif event == "GROUP_LEFT" then
        -- Player left group - re-register if they were registered before
        if self.db.wasRegisteredBeforeGroup then
            self:LogWarn("Re-registering after leaving group")
            -- Restore saved status and re-register
            self.db.myStatus = {
                categories = self.db.savedCategories or {},
                roles = self.db.savedRoles or {}
            }
            self:SendUpdate()
            self:UpdateButtonState()
            if self.frame:IsShown() then
                self:OnShow()
            end
            self.db.wasRegisteredBeforeGroup = false
        else
            -- Even if not re-registering, update button state
            self:UpdateButtonState()
        end
    end
end

function SocialLFG:HandleAddonMessage(message, sender, channel)
    local cmd, arg1, arg2 = strsplit("|", message)
    if cmd == "STATUS" then
        -- Update last seen timestamp
        self.lastSeen[sender] = GetTime()
        
        -- Parse categories and roles, filtering out empty strings
        local categories = {}
        local roles = {}
        if arg1 and arg1 ~= "" then
            for cat in arg1:gmatch("[^,]+") do
                table.insert(categories, cat)
            end
        end
        if arg2 and arg2 ~= "" then
            for role in arg2:gmatch("[^,]+") do
                table.insert(roles, role)
            end
        end
        -- Only update if there are actual categories
        if #categories > 0 then
            self:UpdateStatus(sender, {categories = categories, roles = roles})
        else
            -- Remove if no categories
            self:UpdateStatus(sender, nil)
        end
    elseif cmd == "QUERY" then
        -- Only respond if registered with actual categories
        if #self.db.myStatus.categories > 0 then
            self:SendAddonMessage("STATUS|" .. table.concat(self.db.myStatus.categories, ",") .. "|" .. table.concat(self.db.myStatus.roles, ","), "WHISPER", sender)
        end
    elseif cmd == "UNREGISTER" then
        self:UpdateStatus(sender, nil)
    end
end

function SocialLFG:UpdateStatus(player, status)
    -- Only store players who are actually registered (have categories)
    if status == nil or (status.categories and #status.categories == 0) then
        -- Remove from list if they're unregistered
        local wasRegistered = self.lfgMembers[player] ~= nil
        if wasRegistered then
            self.lfgMembers[player] = nil
            self.lastSeen[player] = nil
            self:LogWarn("REMOVED: " .. player .. " | Remaining: " .. tostring(self:CountMembers()))
        end
        -- Always update list to remove the unregistered player immediately
        self:UpdateList()
    elseif status and status.categories and #status.categories > 0 then
        -- Only add if they have categories
        self.lfgMembers[player] = status
        -- Always update list when adding members
        if self.frame:IsShown() then
            self:UpdateList()
        end
    end
end

function SocialLFG:CheckTimeouts()
    local currentTime = GetTime()
    local removed = false
    
    for player, lastTime in pairs(self.lastSeen) do
        if currentTime - lastTime > self.TIMEOUT then
            -- Player timed out, remove them
            self.lfgMembers[player] = nil
            self.lastSeen[player] = nil
            self:LogWarn("TIMEOUT: " .. player .. " (no response for " .. self.TIMEOUT .. "s) | Remaining: " .. tostring(self:CountMembers()))
            removed = true
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

function SocialLFG:UpdateFriends()
    local numFriends = C_FriendList.GetNumFriends()
    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfo(i)
        if not info then return end  -- Skip if info is nil
        if info.connected and not self.db.queriedFriends[info.name] then
            self:SendAddonMessage("QUERY", "WHISPER", info.name)
            self.db.queriedFriends[info.name] = true
        elseif not info.connected then
            self.db.queriedFriends[info.name] = nil
            self.lfgMembers[info.name] = nil
            if self.frame:IsShown() then
                self:UpdateList()
            end
        end
    end
end

function SocialLFG:SendAddonMessage(message, channel, target)
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

function SocialLFG:SaveCheckboxState()
    self.db.savedCategories = self:GetCheckedCategories()
    self.db.savedRoles = self:GetCheckedRoles()
end

function SocialLFG:GetCheckedCategories()
    local categories = {}
    if SocialLFGRaidCheck:GetChecked() then table.insert(categories, "Raid") end
    if SocialLFGMythicCheck:GetChecked() then table.insert(categories, "Mythic+") end
    if SocialLFGQuestingCheck:GetChecked() then table.insert(categories, "Questing") end
    return categories
end

function SocialLFG:GetCheckedRoles()
    local roles = {}
    if SocialLFGTankCheck:GetChecked() then table.insert(roles, "Tank") end
    if SocialLFGHealCheck:GetChecked() then table.insert(roles, "Heal") end
    if SocialLFGDPSCheck:GetChecked() then table.insert(roles, "DPS") end
    return roles
end

function SocialLFG:BroadcastToAll(channel, message, target)
    self:SendAddonMessage(message, channel, target)
end

function SocialLFG:BroadcastToGuildAndFriends(message)
    self:BroadcastToAll("GUILD", message)
    local numFriends = C_FriendList.GetNumFriends()
    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfo(i)
        if info and info.connected then
            self:BroadcastToAll("WHISPER", message, info.name)
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
    local categories = self:GetCheckedCategories()
    local roles = self:GetCheckedRoles()
    self.db.myStatus = {categories = categories, roles = roles}
    self.db.savedCategories = categories
    self.db.savedRoles = roles
    self:LogInfo("Registered: Categories: " .. (table.concat(categories, ", ") or "(none)") .. " | Roles: " .. (table.concat(roles, ", ") or "(none)"))
    self:SendUpdate()
    self:UpdateButtonState()
end

function SocialLFG:UnregisterLFG()
    self.db.myStatus = {categories = {}, roles = {}}
    self:BroadcastToGuildAndFriends("UNREGISTER")
    self:UpdateButtonState()
    self:UpdateList()
end

function SocialLFG:SendUpdate()
    local msg = "STATUS|" .. table.concat(self.db.myStatus.categories, ",") .. "|" .. table.concat(self.db.myStatus.roles, ",")
    self:BroadcastToGuildAndFriends(msg)
end

function SocialLFG:SetCheckboxesFromRoles(roles)
    SocialLFGTankCheck:SetChecked(tContains(roles, "Tank"))
    SocialLFGHealCheck:SetChecked(tContains(roles, "Heal"))
    SocialLFGDPSCheck:SetChecked(tContains(roles, "DPS"))
end

function SocialLFG:SetCheckboxesFromCategories(categories)
    SocialLFGRaidCheck:SetChecked(tContains(categories, "Raid"))
    SocialLFGMythicCheck:SetChecked(tContains(categories, "Mythic+"))
    SocialLFGQuestingCheck:SetChecked(tContains(categories, "Questing"))
end

function SocialLFG:OnShow()
    if #self.db.myStatus.categories > 0 then
        SocialLFGRegisterButton:SetText("Unregister")
        self:SetCheckboxesFromRoles(self.db.myStatus.roles)
        self:SetCheckboxesFromCategories(self.db.myStatus.categories)
        SocialLFGRegisterButton:Enable()
    else
        SocialLFGRegisterButton:SetText("Register LFG")
        -- Restore saved roles instead of clearing them
        self:SetCheckboxesFromRoles(self.db.savedRoles)
        self:SetCheckboxesFromCategories(self.db.savedCategories)
        SocialLFGRegisterButton:Disable()
    end
    self:UpdateButtonState()
    self:UpdateList()
    
    -- Start periodic update timer when window opens (every 5 seconds)
    if not self.updateTimer then
        self.updateTimer = C_Timer.NewTicker(5, function()
            -- Query all guild members
            SocialLFG:SendAddonMessage("QUERY", "GUILD")
            -- Query all connected friends
            local numFriends = C_FriendList.GetNumFriends()
            for i = 1, numFriends do
                local info = C_FriendList.GetFriendInfo(i)
                if info and info.connected then
                    SocialLFG:SendAddonMessage("QUERY", "WHISPER", info.name)
                end
            end
            -- Check for timeouts and update list
            SocialLFG:CheckTimeouts()
            SocialLFG:UpdateList()
        end)
    end
end

-- Initialize stats cache
if not SocialLFG.statsCache then
    SocialLFG.statsCache = {}
end

-- Cache duration in seconds (300 = 5 minutes)
SocialLFG.STATS_CACHE_DURATION = 300

function SocialLFG:GetCachedStats(playerName)
    if not playerName then return nil end
    
    local cached = self.statsCache[playerName]
    if cached and (GetTime() - cached.timestamp) < self.STATS_CACHE_DURATION then
        return cached.stats
    end
    return nil
end

function SocialLFG:CacheStats(playerName, stats)
    if not playerName or not stats then return end
    self.statsCache[playerName] = {
        stats = stats,
        timestamp = GetTime()
    }
end

function SocialLFG:GetPlayerStats(playerName)
    if not playerName then
        return {ilvl = "N/A", rio = "N/A"}
    end
    
    -- Check cache first
    local cachedStats = self:GetCachedStats(playerName)
    if cachedStats then
        return cachedStats
    end
    
    local stats = {
        ilvl = "N/A",
        rio = "N/A"
    }
    
    -- Try to get RaiderIO score first (most reliable)
    if RaiderIO then
        local success, profile = pcall(function()
            return RaiderIO.GetProfile(playerName)
        end)
        
        if success and profile then
            -- Get M+ score if available
            if profile.mythicPlusScore and profile.mythicPlusScore > 0 then
                stats.rio = tostring(math.floor(profile.mythicPlusScore))
            elseif profile.raidProgression then
                stats.rio = "Raider"
            end
            
            -- Get item level from profile if available
            if profile.gearLevel and profile.gearLevel > 0 then
                stats.ilvl = tostring(profile.gearLevel)
            end
        end
    end
    
    -- Try Blizzard API for item level as fallback
    if stats.ilvl == "N/A" then
        local success, ilvl = pcall(function()
            if C_Armory and C_Armory.GetCharacterGearSummary then
                return C_Armory.GetCharacterGearSummary(playerName)
            end
            return nil
        end)
        
        if success and ilvl then
            stats.ilvl = tostring(ilvl)
        end
    end
    
    -- Cache the result
    self:CacheStats(playerName, stats)
    return stats
end

function SocialLFG:UpdateList()
    -- Properly destroy all old list frames
    for _, frame in ipairs(self.listFrames) do
        frame:Hide()
        frame:SetParent(nil)
        frame = nil
    end
    wipe(self.listFrames)
    local previous = nil
    local playerName = UnitName("player")
    
    local function AddEntry(player, status)
        -- Skip entries with no categories or invalid status
        if not status or not status.categories or #status.categories == 0 then
            return
        end
        
        -- Skip self player
        if player == playerName then
            return
        end
        
        local frame = CreateFrame("Frame", nil, SocialLFGScrollChild)
        frame:SetSize(500, 20)
        if previous then
            frame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
        else
            frame:SetPoint("TOPLEFT", SocialLFGScrollChild, "TOPLEFT", 0, 0)
        end
        
        -- Create clickable name text with stats on hover
        local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 0, 0)
        local displayText = player .. 
            " (" .. table.concat(status.categories, ", ") .. " - " .. table.concat(status.roles, ", ") .. ")"
        nameText:SetText(displayText)
        
        -- Create a hover frame for tooltip functionality
        local hoverFrame = CreateFrame("Frame", nil, frame)
        hoverFrame:SetSize(300, 20)
        hoverFrame:SetPoint("LEFT", 0, 0)
        hoverFrame:EnableMouse(true)
        
        -- Store player name for tooltip retrieval
        hoverFrame.playerName = player
        hoverFrame.categories = status.categories
        hoverFrame.roles = status.roles
        
        -- Add tooltip on hover
        hoverFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(hoverFrame, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.playerName, 1, 1, 1)
            GameTooltip:AddLine(" ")
            
            -- Get player stats
            local stats = SocialLFG:GetPlayerStats(self.playerName)
            
            -- Display categories and roles
            GameTooltip:AddLine("LFG: " .. table.concat(self.categories, ", "), 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Roles: " .. table.concat(self.roles, ", "), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            
            -- Display stats with color coding
            local ilvlColor = stats.ilvl == "N/A" and "|cFFFF0000" or "|cFF0FFF0F"
            local rioColor = stats.rio == "N/A" and "|cFFFF0000" or "|cFF0FFF0F"
            
            GameTooltip:AddLine("Item Level: " .. ilvlColor .. stats.ilvl .. "|r", 1, 1, 1)
            GameTooltip:AddLine("Raider IO: " .. rioColor .. stats.rio .. "|r", 1, 1, 1)
            
            GameTooltip:Show()
        end)
        
        hoverFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        -- Create invite button
        local inviteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        inviteBtn:SetSize(60, 20)
        inviteBtn:SetPoint("RIGHT", 0, 0)
        inviteBtn:SetText("Invite")
        inviteBtn:SetScript("OnClick", function() C_PartyInfo.InviteUnit(player) end)
        
        table.insert(self.listFrames, frame)
        previous = frame
    end
    
    for player, status in pairs(self.lfgMembers) do
        AddEntry(player, status)
    end
    
    -- Clear scroll child and reset height
    SocialLFGScrollChild:SetHeight(math.max(1, #self.listFrames * 22))
    SocialLFGScrollFrame:UpdateScrollChildRect()
end

SLASH_SOCIALLFG1 = "/slfg"
SLASH_SOCIALLFG2 = "/sociallfg"
SlashCmdList["SOCIALLFG"] = function(msg)
    SocialLFG.frame:Show()
end