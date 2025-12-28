SocialLFG = {}
local PREFIX = "SocialLFG"

-- Constants
local CONSTANTS = {
    TIMEOUT = 60,
    QUERY_INTERVAL = 5,
    ROW_HEIGHT = 24,
    ROLE_ICON_SIZE = 12,
    CATEGORIES = {"Raid", "Mythic+", "Questing", "Dungeon"},
    ROLES = {"Tank", "Heal", "DPS"},
}

-- Logging utilities with consistent formatting
local function Log(level, msg)
    local colorMap = {
        DEBUG = "|cFFFF0000",
        INFO = "|cFF00FF00",
        WARN = "|cFFFF9900",
    }
    print((colorMap[level] or "|cFFFFFFFF") .. "[SocialLFG]|r " .. msg)
end

function SocialLFG:LogDebug(msg) Log("DEBUG", msg) end
function SocialLFG:LogInfo(msg) Log("INFO", msg) end
function SocialLFG:LogWarn(msg) Log("WARN", msg) end
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
    self:LogDebug("OnLoad called")
    
    self.frame = SocialLFGFrame
    self:RegisterFrameEvents()
    self:ConfigureFrameProperties()
    self:RestrictRolesByClass()
    self:RegisterAddonMessagePrefix()
    self:RegisterSpecialFrames()
    
    self:LogDebug("OnLoad initialization complete")
end

function SocialLFG:RegisterFrameEvents()
    self.frame:RegisterEvent("ADDON_LOADED")
    self.frame:RegisterEvent("CHAT_MSG_ADDON")
    self.frame:RegisterEvent("FRIENDLIST_UPDATE")
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
    if not tContains(allowedRoles, "Tank") then SocialLFGTankCheck:Disable() end
    if not tContains(allowedRoles, "Heal") then SocialLFGHealCheck:Disable() end
    if not tContains(allowedRoles, "DPS") then SocialLFGDPSCheck:Disable() end
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
        -- Guild roster updated
    elseif event == "GROUP_FORMED" or event == "GROUP_LEFT" then
        self:HandleGroupStatusChange(event)
    end
end

function SocialLFG:InitializeDatabase()
    self:LogDebug("ADDON_LOADED event fired")
    
    if not SocialLFGDB then
        self:LogDebug("Creating new database")
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
    
    self:EnsureDatabaseFields()
    self:LogDatabaseStatus()
    self:RestoreCheckboxStates()
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
    self:LogInfo("Database loaded:")
    self:LogInfo("  Categories: " .. (table.concat(self.db.myStatus.categories, ", ") or "(none)"))
    self:LogInfo("  Roles: " .. (table.concat(self.db.myStatus.roles, ", ") or "(none)"))
end

function SocialLFG:RestoreCheckboxStates()
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
        self:HandleStatusMessage(sender, arg1, arg2)
    elseif cmd == "QUERY" then
        self:HandleQueryMessage(sender)
    elseif cmd == "UNREGISTER" then
        self:UpdateStatus(sender, nil)
    end
end

function SocialLFG:HandleStatusMessage(sender, arg1, arg2)
    self.lastSeen[sender] = GetTime()
    
    local categories = self:ParseCategories(arg1)
    local roles = self:ParseRoles(arg2)
    
    if #categories > 0 then
        self:UpdateStatus(sender, {categories = categories, roles = roles})
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
        self:SendAddonMessage("STATUS|" .. table.concat(self.db.myStatus.categories, ",") .. "|" .. table.concat(self.db.myStatus.roles, ","), "WHISPER", sender)
    end
end

function SocialLFG:UpdateStatus(player, status)
    if status == nil or (status.categories and #status.categories == 0) then
        if self.lfgMembers[player] ~= nil then
            self.lfgMembers[player] = nil
            self.lastSeen[player] = nil
            self:LogWarn("REMOVED: " .. player .. " | Remaining: " .. self:CountMembers())
        end
        self:UpdateListIfShown()
    elseif status and status.categories and #status.categories > 0 then
        self.lfgMembers[player] = status
        self:UpdateListIfShown()
    end
end

function SocialLFG:UpdateListIfShown()
    if self.frame:IsShown() then
        self:UpdateList()
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
        if not info then return end
        
        if info.connected then
            if not self.db.queriedFriends[info.name] then
                self:SendAddonMessage("QUERY", "WHISPER", info.name)
                self.db.queriedFriends[info.name] = true
            end
        else
            self.db.queriedFriends[info.name] = nil
            self.lfgMembers[info.name] = nil
            self:UpdateListIfShown()
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
    self:RestoreUIState()
    self:UpdateButtonState()
    self:UpdateList()
    self:StartPeriodicUpdates()
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
            self:QueryAllPlayers()
            self:CheckTimeouts()
            self:UpdateList()
        end)
    end
end

function SocialLFG:QueryAllPlayers()
    self:SendAddonMessage("QUERY", "GUILD")
    local numFriends = C_FriendList.GetNumFriends()
    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfo(i)
        if info and info.connected then
            self:SendAddonMessage("QUERY", "WHISPER", info.name)
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
    table.sort(sortedPlayers)
    return sortedPlayers
end

function SocialLFG:CreateListRow(player, status, rowIndex, currentPlayerName)
    local rowFrame = CreateFrame("Frame", nil, SocialLFGScrollChild)
    rowFrame:SetHeight(CONSTANTS.ROW_HEIGHT)
    rowFrame:SetWidth(500)
    
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
    
    -- Player name (left side)
    local name = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", rowFrame, "LEFT", 10, 0)
    name:SetWidth(120)
    name:SetHeight(CONSTANTS.ROW_HEIGHT)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("MIDDLE")
    name:SetText(player)
    
    -- Role icons
    local roleStartX = 145
    for idx, role in ipairs(status.roles) do
        local icon = rowFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", rowFrame, "LEFT", roleStartX + (idx - 1) * 18, 0)
        icon:SetAtlas(self:GetRoleAtlas(role), true)
    end
    
    -- Categories
    local categories = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    categories:SetPoint("LEFT", rowFrame, "LEFT", 220, 0)
    categories:SetWidth(140)
    categories:SetHeight(CONSTANTS.ROW_HEIGHT)
    categories:SetJustifyH("LEFT")
    categories:SetJustifyV("MIDDLE")
    categories:SetText(table.concat(status.categories, ", "))
    
    -- Invite button (right side) - only if not the current player
    local charName = strsplit("-", player) or player
    if charName ~= currentPlayerName then
        local inviteBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        inviteBtn:SetSize(70, 22)
        inviteBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -5, 0)
        inviteBtn:SetText("Invite")
        inviteBtn:SetNormalFontObject("GameFontNormalSmall")
        inviteBtn:SetScript("OnClick", function() C_PartyInfo.InviteUnit(player) end)
    end
    
    table.insert(self.listFrames, rowFrame)
end

SLASH_SOCIALLFG1 = "/slfg"
SLASH_SOCIALLFG2 = "/sociallfg"
SlashCmdList["SOCIALLFG"] = function(msg)
    SocialLFG.frame:Show()
end