--[[
    SocialLFG - UI List Module
    List rendering with frame pooling to prevent blinking
]]

local Addon = _G.SocialLFG
local Utils = Addon.Utils
local L = _G.SocialLFG_L

-- Create UI module
Addon.UI = Addon.UI or {}
local UI = Addon.UI

-- =============================================================================
-- Frame Pool
-- =============================================================================

local RowPool = {
    pool = {},
    active = {},
    template = nil,
}

function RowPool:Initialize(parent)
    self.parent = parent
    wipe(self.pool)
    wipe(self.active)

    -- Pre-allocate a number of rows to avoid allocations during first refresh
    local prealloc = Addon.Constants.ROW_POOL_PREALLOCATE or 0
    if prealloc > 0 then
        self:Preallocate(prealloc)
    end
end

function RowPool:Acquire()
    local frame = table.remove(self.pool)
    
    if not frame then
        frame = self:CreateRow()
    end
    
    frame:Show()
    table.insert(self.active, frame)
    
    return frame
end

function RowPool:Release(frame)
    frame:Hide()
    frame:ClearAllPoints()
    
    -- Reset data
    if frame.playerName then
        frame.playerName = nil
    end
    
    -- Move to pool
    for i, activeFrame in ipairs(self.active) do
        if activeFrame == frame then
            table.remove(self.active, i)
            break
        end
    end
    
    table.insert(self.pool, frame)
end

function RowPool:ReleaseAll()
    for i = #self.active, 1, -1 do
        local frame = self.active[i]
        frame:Hide()
        frame:ClearAllPoints()
        frame.playerName = nil
        table.insert(self.pool, frame)
    end
    wipe(self.active)
end

function RowPool:GetActive()
    return self.active
end

function RowPool:CreateRow()
    local frame = CreateFrame("Frame", nil, self.parent)
    frame:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame:SetWidth(580)
    
    -- Background texture
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(true)
    
    -- Class icon
    frame.classIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.classIcon:SetSize(Addon.Constants.CLASS_ICON_SIZE, Addon.Constants.CLASS_ICON_SIZE)
    frame.classIcon:SetPoint("LEFT", frame, "LEFT", 5, 0)
    
    -- Player name
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.nameText:SetPoint("LEFT", frame, "LEFT", 28, 0)
    frame.nameText:SetWidth(90)
    frame.nameText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.nameText:SetJustifyH("LEFT")
    frame.nameText:SetJustifyV("MIDDLE")
    
    -- Enable tooltip on name
    frame.nameHitbox = CreateFrame("Frame", nil, frame)
    frame.nameHitbox:SetPoint("LEFT", frame, "LEFT", 5, 0)
    frame.nameHitbox:SetSize(115, Addon.Constants.ROW_HEIGHT)
    frame.nameHitbox:EnableMouse(true)
    frame.nameHitbox:SetScript("OnEnter", function(self)
        if frame.playerFullName then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(frame.playerFullName, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.nameHitbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Role icons (up to 3)
    frame.roleIcons = {}
    for i = 1, 3 do
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(Addon.Constants.ROLE_ICON_SIZE, Addon.Constants.ROLE_ICON_SIZE)
        icon:SetPoint("LEFT", frame, "LEFT", 125 + (i - 1) * 18, 0)
        icon:Hide()
        frame.roleIcons[i] = icon
    end
    
    -- Categories text
    frame.categoriesText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.categoriesText:SetPoint("LEFT", frame, "LEFT", 190, 0)
    frame.categoriesText:SetWidth(100)
    frame.categoriesText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.categoriesText:SetJustifyH("LEFT")
    frame.categoriesText:SetJustifyV("MIDDLE")
    
    -- iLvL text
    frame.ilvlText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.ilvlText:SetPoint("LEFT", frame, "LEFT", 295, 0)
    frame.ilvlText:SetWidth(40)
    frame.ilvlText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.ilvlText:SetJustifyH("CENTER")
    frame.ilvlText:SetJustifyV("MIDDLE")
    
    -- Rio text
    frame.rioText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.rioText:SetPoint("LEFT", frame, "LEFT", 340, 0)
    frame.rioText:SetWidth(50)
    frame.rioText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.rioText:SetJustifyH("CENTER")
    frame.rioText:SetJustifyV("MIDDLE")
    
    -- Keystone text
    frame.keystoneText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.keystoneText:SetPoint("LEFT", frame, "LEFT", 395, 0)
    frame.keystoneText:SetWidth(50)
    frame.keystoneText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.keystoneText:SetJustifyH("CENTER")
    frame.keystoneText:SetJustifyV("MIDDLE")
    
    -- Invite button
    frame.inviteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.inviteBtn:SetSize(65, 22)
    frame.inviteBtn:SetPoint("LEFT", frame, "LEFT", 465, 0)
    frame.inviteBtn:SetText(L["BTN_INVITE"])
    frame.inviteBtn:SetNormalFontObject("GameFontNormalSmall")
    frame.inviteBtn:SetScript("OnClick", function()
        if frame.playerFullName then
            UI:InvitePlayer(frame.playerFullName, frame.charName)
        end
    end)
    
    -- Whisper button
    frame.whisperBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.whisperBtn:SetSize(65, 22)
    frame.whisperBtn:SetPoint("LEFT", frame, "LEFT", 535, 0)
    frame.whisperBtn:SetText(L["BTN_WHISPER"])
    frame.whisperBtn:SetNormalFontObject("GameFontNormalSmall")
    frame.whisperBtn:SetScript("OnClick", function()
        if frame.charName then
            ChatFrame_OpenChat("/w " .. frame.charName .. " ", ChatFrame1)
        end
    end)
    
    return frame
end

function RowPool:Preallocate(n)
    n = n or 0
    for i = 1, n do
        local f = self:CreateRow()
        f:Hide()
        table.insert(self.pool, f)
    end
end

-- =============================================================================
-- List State
-- =============================================================================

local listState = {
    initialized = false,
    lastUpdateTime = 0,
    scrollChild = nil,
}

-- =============================================================================
-- List Initialization
-- =============================================================================

function UI:InitializeList()
    if listState.initialized then return end
    
    listState.scrollChild = SocialLFGScrollChild
    if not listState.scrollChild then
        Addon:LogError("SocialLFGScrollChild not found")
        return
    end
    
    RowPool:Initialize(listState.scrollChild)
    
    -- Register for list changes
    Addon:RegisterCallback("OnListChanged", function()
        UI:UpdateList()
    end)
    
    listState.initialized = true
end

-- =============================================================================
-- List Update
-- =============================================================================

function UI:UpdateList()
    if not listState.initialized then
        self:InitializeList()
    end
    
    if not SocialLFGFrame or not SocialLFGFrame:IsShown() then
        return
    end
    
    -- Throttle updates
    local now = GetTime()
    if now - listState.lastUpdateTime < Addon.Constants.LIST_UPDATE_THROTTLE then
        -- Schedule a delayed update
        C_Timer.After(Addon.Constants.LIST_UPDATE_THROTTLE, function()
            if SocialLFGFrame and SocialLFGFrame:IsShown() then
                UI:DoUpdateList()
            end
        end)
        return
    end
    
    self:DoUpdateList()
end

function UI:DoUpdateList()
    listState.lastUpdateTime = GetTime()
    
    -- Release all current rows
    RowPool:ReleaseAll()
    
    -- Get sorted member list
    local members = Addon.Members:GetSortedList()
    local currentPlayerName = Addon.runtime.playerName
    
    -- Create rows
    local previousRow = nil
    for index, memberData in ipairs(members) do
        local row = RowPool:Acquire()
        
        -- Position
        if index == 1 then
            row:SetPoint("TOPLEFT", listState.scrollChild, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, 0)
        end
        
        -- Update row content
        self:UpdateRow(row, memberData, index, currentPlayerName)
        
        previousRow = row
    end
    
    -- Update scroll frame
    local childHeight = #members * Addon.Constants.ROW_HEIGHT
    listState.scrollChild:SetHeight(math.max(1, childHeight))
    SocialLFGScrollFrame:UpdateScrollChildRect()
end

function UI:UpdateRow(row, memberData, index, currentPlayerName)
    local playerName = memberData.name
    local status = memberData.status
    local charName = Utils:ExtractCharacterName(playerName) or playerName
    
    -- Store data on row
    row.playerName = charName
    row.playerFullName = playerName
    row.charName = charName
    
    -- Alternating background
    if index % 2 == 0 then
        row.bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
    else
        row.bg:SetColorTexture(0.1, 0.1, 0.1, 0.1)
    end
    
    -- Class icon
    if status.class then
        Utils:SetClassIcon(row.classIcon, status.class)
    else
        row.classIcon:Hide()
    end
    
    -- Name with class color
    if status.class then
        row.nameText:SetText(Utils:GetColoredName(charName, status.class))
    else
        row.nameText:SetText(charName)
    end
    
    -- Role icons
    for i, icon in ipairs(row.roleIcons) do
        icon:Hide()
    end
    
    if status.roles then
        for i, role in ipairs(status.roles) do
            if row.roleIcons[i] then
                row.roleIcons[i]:SetAtlas(Utils:GetRoleAtlas(role), true)
                row.roleIcons[i]:Show()
            end
        end
    end
    
    -- Categories
    if status.categories then
        row.categoriesText:SetText(table.concat(status.categories, ", "))
    else
        row.categoriesText:SetText("")
    end
    
    -- iLvL
    row.ilvlText:SetText(tostring(status.ilvl or 0))
    
    -- Rio
    row.rioText:SetText(tostring(status.rio or 0))
    
    -- Keystone
    row.keystoneText:SetText(status.keystone or L["NO_KEYSTONE"])
    
    -- Show/hide action buttons (hide for self)
    local isSelf = charName == currentPlayerName
    if isSelf then
        row.inviteBtn:Hide()
        row.whisperBtn:Hide()
    else
        row.inviteBtn:Show()
        row.whisperBtn:Show()
    end
end

-- =============================================================================
-- Player Actions
-- =============================================================================

function UI:InvitePlayer(fullName, charName)
    if not fullName or fullName == "" then
        Addon:LogError(L["ERR_INVALID_PLAYER"])
        return
    end
    
    charName = charName or Utils:ExtractCharacterName(fullName) or fullName
    
    -- Try standard invite
    local success = pcall(function()
        C_PartyInfo.InviteUnit(fullName)
    end)
    
    if success then
        Addon:LogInfo(L["INFO_INVITED"]:format(charName))
        return
    end
    
    -- Fallback: try with character name only
    success = pcall(function()
        C_PartyInfo.InviteUnit(charName)
    end)
    
    if success then
        Addon:LogInfo(L["INFO_INVITED"]:format(charName))
        return
    end
    
    -- Last resort: use chat command
    ChatFrame_OpenChat("/invite " .. charName, ChatFrame1)
    Addon:LogWarn(L["INFO_INVITED_ALT"]:format(charName))
end

-- =============================================================================
-- Cleanup
-- =============================================================================

function UI:CleanupList()
    RowPool:ReleaseAll()
end
