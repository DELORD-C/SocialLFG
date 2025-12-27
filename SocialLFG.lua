SocialLFG = {}

local PREFIX = "SocialLFG"
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
    print("|cFFFF0000[SocialLFG] OnLoad called|r")
    print("|cFFFF0000SocialLFGDB exists: " .. tostring(SocialLFGDB ~= nil) .. "|r")
    
    self.frame = SocialLFGFrame
    self.frame:RegisterEvent("ADDON_LOADED")
    self.frame:RegisterEvent("CHAT_MSG_ADDON")
    self.frame:RegisterEvent("FRIENDLIST_UPDATE")
    self.frame:RegisterEvent("GUILD_ROSTER_UPDATE")
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
    
    -- Create minimap button
    self.minimapButton = CreateFrame("Button", "SocialLFGMinimapButton", Minimap)
    self.minimapButton:SetSize(32, 32)
    self.minimapButton:SetFrameStrata("MEDIUM")
    self.minimapButton:SetFrameLevel(8)
    self.minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    self.minimapButton:SetMovable(true)
    self.minimapButton:RegisterForDrag("LeftButton")
    
    local icon = self.minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    
    self.minimapButton:SetScript("OnClick", function() SocialLFG:ToggleWindow() end)
    self.minimapButton:SetScript("OnDragStart", function() self.minimapButton:StartMoving() end)
    self.minimapButton:SetScript("OnDragStop", function() 
        self.minimapButton:StopMovingOrSizing()
        local x, y = self.minimapButton:GetCenter()
        local mx, my = Minimap:GetCenter()
        local angle = atan2(y - my, x - mx)
        self.db.minimapAngle = angle
        self:UpdateMinimapPosition()
    end)
    self.minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Social LFG")
        GameTooltip:AddLine("Click to open Social LFG window", 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    self.minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    print("|cFFFF0000[SocialLFG] OnLoad initialization complete|r")
end

function SocialLFG:OnEvent(event, ...)
    if event == "ADDON_LOADED" and ... == "SocialLFG" then
        print("|cFFFF0000[SocialLFG] ADDON_LOADED event fired|r")
        print("|cFFFF0000SocialLFGDB exists: " .. tostring(SocialLFGDB ~= nil) .. "|r")
        
        -- Initialize database if it doesn't exist
        if not SocialLFGDB then
            print("|cFFFF0000[SocialLFG] Creating new database|r")
            SocialLFGDB = {
                myStatus = {categories = {}, roles = {}},
                friendsLFG = {},
                guildLFG = {},
                queriedFriends = {},
                minimapAngle = 0,
            }
        end
        self.db = SocialLFGDB
        self.listFrames = {}
        
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
        if not self.db.friendsLFG then
            self.db.friendsLFG = {}
        end
        if not self.db.guildLFG then
            self.db.guildLFG = {}
        end
        if not self.db.queriedFriends then
            self.db.queriedFriends = {}
        end
        if not self.db.minimapAngle then
            self.db.minimapAngle = 0
        end
        -- Saved checkbox state (for UI restoration even when not registered)
        if not self.db.savedCategories then
            self.db.savedCategories = {}
        end
        if not self.db.savedRoles then
            self.db.savedRoles = {}
        end
        
        -- DEBUG: Dump saved data
        print("|cFF00FF00[SocialLFG] Database loaded:|r")
        print("  Categories: " .. (table.concat(self.db.myStatus.categories, ", ") or "(none)"))
        print("  Roles: " .. (table.concat(self.db.myStatus.roles, ", ") or "(none)"))
        print("  Friends LFG: " .. tostring(#self.db.friendsLFG) .. " entries")
        print("  Guild LFG: " .. tostring(#self.db.guildLFG) .. " entries")
        print("  Minimap angle: " .. tostring(self.db.minimapAngle))
        
        -- Restore checkbox states if registered
        if #self.db.myStatus.categories > 0 then
            print("|cFF00FF00[SocialLFG] Restoring registration state...|r")
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
        
        -- Start periodic update timer every 15 seconds
        if not self.updateTimer then
            self.updateTimer = C_Timer.NewTicker(15, function()
                if SocialLFG.frame:IsShown() then
                    SocialLFG:SendAddonMessage("QUERY", "GUILD")
                    SocialLFG:UpdateList()
                end
            end)
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
    end
end

function SocialLFG:HandleAddonMessage(message, sender, channel)
    local cmd, arg1, arg2 = strsplit("|", message)
    if cmd == "STATUS" then
        local source = (channel == "GUILD") and "guild" or "friend"
        self:UpdateStatus(sender, {categories = {strsplit(",", arg1)}, roles = {strsplit(",", arg2)}}, source)
    elseif cmd == "QUERY" then
        if #self.db.myStatus.categories > 0 then
            self:SendAddonMessage("STATUS|" .. table.concat(self.db.myStatus.categories, ",") .. "|" .. table.concat(self.db.myStatus.roles, ","), "WHISPER", sender)
        end
    elseif cmd == "UNREGISTER" then
        local source = (channel == "GUILD") and "guild" or "friend"
        self:UpdateStatus(sender, nil, source)
    end
end

function SocialLFG:UpdateStatus(player, status, source)
    if source == "guild" then
        if status then
            self.db.guildLFG[player] = status
        else
            self.db.guildLFG[player] = nil
        end
    else
        if status then
            self.db.friendsLFG[player] = status
        else
            self.db.friendsLFG[player] = nil
        end
    end
    if self.frame:IsShown() then
        self:UpdateList()
    end
end

function SocialLFG:UpdateFriends()
    local numFriends = C_FriendList.GetNumFriends()
    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfo(i)
        if info.connected and not self.db.queriedFriends[info.name] then
            self:SendAddonMessage("QUERY", "WHISPER", info.name)
            self.db.queriedFriends[info.name] = true
        elseif not info.connected then
            self.db.queriedFriends[info.name] = nil
            self.db.friendsLFG[info.name] = nil
        end
    end
end

function SocialLFG:SendAddonMessage(message, channel, target)
    C_ChatInfo.SendAddonMessage(PREFIX, message, channel, target)
end

function SocialLFG:UpdateMinimapPosition()
    local angle = self.db.minimapAngle or 0
    local x = cos(angle) * 80
    local y = sin(angle) * 80
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function SocialLFG:ToggleWindow()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function SocialLFG:UpdateButtonState()
    if #self.db.myStatus.categories > 0 then
        SocialLFGRegisterButton:SetText("Unregister")
        SocialLFGRegisterButton:Enable()
    else
        local categories = 0
        if SocialLFGRaidCheck:GetChecked() then categories = categories + 1 end
        if SocialLFGMythicCheck:GetChecked() then categories = categories + 1 end
        if SocialLFGQuestingCheck:GetChecked() then categories = categories + 1 end
        local roles = 0
        if SocialLFGTankCheck:GetChecked() then roles = roles + 1 end
        if SocialLFGHealCheck:GetChecked() then roles = roles + 1 end
        if SocialLFGDPSCheck:GetChecked() then roles = roles + 1 end
        if categories > 0 and roles > 0 then
            SocialLFGRegisterButton:SetText("Register LFG")
            SocialLFGRegisterButton:Enable()
        else
            SocialLFGRegisterButton:SetText("Select categories and roles")
            SocialLFGRegisterButton:Disable()
        end
    end
end

function SocialLFG:SaveCheckboxState()
    local categories = {}
    if SocialLFGRaidCheck:GetChecked() then table.insert(categories, "Raid") end
    if SocialLFGMythicCheck:GetChecked() then table.insert(categories, "Mythic+") end
    if SocialLFGQuestingCheck:GetChecked() then table.insert(categories, "Questing") end
    local roles = {}
    if SocialLFGTankCheck:GetChecked() then table.insert(roles, "Tank") end
    if SocialLFGHealCheck:GetChecked() then table.insert(roles, "Heal") end
    if SocialLFGDPSCheck:GetChecked() then table.insert(roles, "DPS") end
    self.db.savedCategories = categories
    self.db.savedRoles = roles
end

function SocialLFG:ToggleLFG()
    if #self.db.myStatus.categories > 0 then
        self:UnregisterLFG()
    else
        self:RegisterLFG()
    end
end

function SocialLFG:RegisterLFG()
    local categories = {}
    if SocialLFGRaidCheck:GetChecked() then table.insert(categories, "Raid") end
    if SocialLFGMythicCheck:GetChecked() then table.insert(categories, "Mythic+") end
    if SocialLFGQuestingCheck:GetChecked() then table.insert(categories, "Questing") end
    local roles = {}
    if SocialLFGTankCheck:GetChecked() then table.insert(roles, "Tank") end
    if SocialLFGHealCheck:GetChecked() then table.insert(roles, "Heal") end
    if SocialLFGDPSCheck:GetChecked() then table.insert(roles, "DPS") end
    self.db.myStatus = {categories = categories, roles = roles}
    self.db.savedCategories = categories
    self.db.savedRoles = roles
    print("|cFF00FF00[SocialLFG] Registered:|r Categories: " .. (table.concat(categories, ", ") or "(none)") .. " | Roles: " .. (table.concat(roles, ", ") or "(none)"))
    self:SendUpdate()
    self:UpdateButtonState()
end

function SocialLFG:UnregisterLFG()
    self.db.myStatus = {categories = {}, roles = {}}
    self:SendAddonMessage("UNREGISTER", "GUILD")
    for friend in pairs(self.db.friendsLFG) do
        self:SendAddonMessage("UNREGISTER", "WHISPER", friend)
    end
    self:UpdateButtonState()
end

function SocialLFG:SendUpdate()
    local msg = "STATUS|" .. table.concat(self.db.myStatus.categories, ",") .. "|" .. table.concat(self.db.myStatus.roles, ",")
    self:SendAddonMessage(msg, "GUILD")
    local numFriends = C_FriendList.GetNumFriends()
    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfo(i)
        if info.connected then
            self:SendAddonMessage(msg, "WHISPER", info.name)
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

function SocialLFG:InitCategoryDropDown()
    for _, cat in ipairs(categories) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = cat
        info.value = cat
        info.func = function() UIDropDownMenu_SetSelectedValue(SocialLFGCategoryDropDown, cat) end
        UIDropDownMenu_AddButton(info)
    end
end

function SocialLFG:OnShow()
    if #self.db.myStatus.categories > 0 then
        SocialLFGRegisterButton:SetText("Unregister")
        SocialLFGTankCheck:SetChecked(tContains(self.db.myStatus.roles, "Tank"))
        SocialLFGHealCheck:SetChecked(tContains(self.db.myStatus.roles, "Heal"))
        SocialLFGDPSCheck:SetChecked(tContains(self.db.myStatus.roles, "DPS"))
        SocialLFGRegisterButton:Enable()
    else
        SocialLFGRegisterButton:SetText("Register LFG")
        -- Restore saved roles instead of clearing them
        SocialLFGTankCheck:SetChecked(tContains(self.db.savedRoles, "Tank"))
        SocialLFGHealCheck:SetChecked(tContains(self.db.savedRoles, "Heal"))
        SocialLFGDPSCheck:SetChecked(tContains(self.db.savedRoles, "DPS"))
        SocialLFGRegisterButton:Disable()
    end
    self:UpdateButtonState()
    self:UpdateList()
end

function SocialLFG:UpdateList()
    for _, frame in ipairs(self.listFrames) do
        frame:Hide()
    end
    wipe(self.listFrames)
    local previous = nil
    local seen = {} -- Track seen players to avoid duplicates
    
    local function AddEntry(player, status)
        -- Skip duplicates
        if seen[player] then
            return
        end
        seen[player] = true
        
        -- Skip entries with no categories
        if not status or #status.categories == 0 then
            return
        end
        local frame = CreateFrame("Frame", nil, SocialLFGScrollChild)
        frame:SetSize(500, 20)
        if previous then
            frame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
        else
            frame:SetPoint("TOPLEFT", SocialLFGScrollChild, "TOPLEFT", 0, 0)
        end
        local rio = "N/A"
        if RaiderIO then
            local profile = RaiderIO.GetProfile(player)
            if profile and profile.mythicPlusScore then
                rio = profile.mythicPlusScore
            end
        end
        local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 0, 0)
        nameText:SetText(player .. " (" .. table.concat(status.categories, ", ") .. " - " .. table.concat(status.roles, ", ") .. ") Rio: " .. rio)
        local inviteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        inviteBtn:SetSize(60, 20)
        inviteBtn:SetPoint("RIGHT", 0, 0)
        inviteBtn:SetText("Invite")
        inviteBtn:SetScript("OnClick", function() C_PartyInfo.InviteUnit(player) end)
        table.insert(self.listFrames, frame)
        previous = frame
    end
    for player, status in pairs(self.db.guildLFG) do
        AddEntry(player, status)
    end
    for player, status in pairs(self.db.friendsLFG) do
        AddEntry(player, status)
    end
    SocialLFGScrollChild:SetHeight(#self.listFrames * 22)
    SocialLFGScrollFrame:UpdateScrollChildRect()
end

SLASH_SOCIALLFG1 = "/slfg"
SlashCmdList["SOCIALLFG"] = function() SocialLFG.frame:Show() end