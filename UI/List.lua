--[[
    SocialLFG - UI List Module
    List rendering with frame pooling to prevent blinking
]]

local Addon = _G.SocialLFG
local Utils = Addon.Utils
local L = _G.SocialLFG_L

-- NameUtils reference (set after initialization)
local NameUtils = nil

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
    frame.playerName = nil
    frame.playerFullName = nil
    frame.charName = nil
    frame.statusInfo = nil
    frame._cache = nil
    
    -- Reset highlight
    if frame.highlight then
        frame.highlight:Hide()
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
        frame.playerFullName = nil
        frame.charName = nil
        frame.statusInfo = nil
        frame._cache = nil
        if frame.highlight then
            frame.highlight:Hide()
        end
        table.insert(self.pool, frame)
    end
    wipe(self.active)
end

-- Release rows from index onwards (for shrinking list)
function RowPool:ReleaseFrom(startIndex)
    for i = #self.active, startIndex, -1 do
        local frame = self.active[i]
        frame:Hide()
        frame:ClearAllPoints()
        frame.playerName = nil
        frame.playerFullName = nil
        frame.charName = nil
        frame.statusInfo = nil
        frame._cache = nil
        if frame.highlight then
            frame.highlight:Hide()
        end
        table.insert(self.pool, frame)
        self.active[i] = nil
    end
end

-- Get row at specific index (1-based)
function RowPool:GetAtIndex(index)
    return self.active[index]
end

-- Get count of active rows
function RowPool:GetActiveCount()
    return #self.active
end

function RowPool:GetActive()
    return self.active
end

function RowPool:CreateRow()
    local frame = CreateFrame("Frame", nil, self.parent)
    frame:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame:SetWidth(600)
    
    -- Get column definitions
    local COLS = Addon.Constants.COLUMNS
    
    -- Background texture
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(true)
    
    -- Hover highlight texture
    frame.highlight = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.highlight:SetAllPoints(true)
    frame.highlight:SetColorTexture(1, 1, 1, 0.1)
    frame.highlight:Hide()
    
    -- Enable mouse for hover effects
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        self.highlight:Show()
        -- Show tooltip with full name
        if self.playerFullName then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.playerFullName, 1, 1, 1)
            if self.statusInfo then
                if self.statusInfo.categories and #self.statusInfo.categories > 0 then
                    GameTooltip:AddLine(Addon:GetCategoryListLocalized(self.statusInfo.categories), 0.7, 0.7, 0.7)
                end
            end
            -- Show relay indicator
            if Addon.Members:IsRelayedMember(self.playerFullName) then
                GameTooltip:AddLine(L["TOOLTIP_RELAYED"] or "Via relay", 0.5, 0.8, 1)
            end
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)
    
    -- Class icon (at start of NAME column)
    frame.classIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.classIcon:SetSize(Addon.Constants.CLASS_ICON_SIZE, Addon.Constants.CLASS_ICON_SIZE)
    frame.classIcon:SetPoint("LEFT", frame, "LEFT", COLS.NAME.x, 0)
    
    -- Player name (after class icon)
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.nameText:SetPoint("LEFT", frame, "LEFT", COLS.NAME.x + 18, 0)
    frame.nameText:SetWidth(COLS.NAME.width - 18)
    frame.nameText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.nameText:SetJustifyH(COLS.NAME.justify)
    frame.nameText:SetJustifyV("MIDDLE")
    frame.nameText:SetWordWrap(false)
    
    -- Role icons (up to 3)
    frame.roleIcons = {}
    for i = 1, 3 do
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(Addon.Constants.ROLE_ICON_SIZE, Addon.Constants.ROLE_ICON_SIZE)
        icon:SetPoint("LEFT", frame, "LEFT", COLS.ROLES.x + (i - 1) * 18, 0)
        icon:Hide()
        frame.roleIcons[i] = icon
    end
    
    -- Categories text
    frame.categoriesText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.categoriesText:SetPoint("LEFT", frame, "LEFT", COLS.CATEGORIES.x, 0)
    frame.categoriesText:SetWidth(COLS.CATEGORIES.width)
    frame.categoriesText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.categoriesText:SetJustifyH(COLS.CATEGORIES.justify)
    frame.categoriesText:SetJustifyV("MIDDLE")
    
    -- iLvL text
    frame.ilvlText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.ilvlText:SetPoint("LEFT", frame, "LEFT", COLS.ILVL.x, 0)
    frame.ilvlText:SetWidth(COLS.ILVL.width)
    frame.ilvlText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.ilvlText:SetJustifyH(COLS.ILVL.justify)
    frame.ilvlText:SetJustifyV("MIDDLE")
    
    -- Rio text
    frame.rioText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.rioText:SetPoint("LEFT", frame, "LEFT", COLS.RIO.x, 0)
    frame.rioText:SetWidth(COLS.RIO.width)
    frame.rioText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.rioText:SetJustifyH(COLS.RIO.justify)
    frame.rioText:SetJustifyV("MIDDLE")
    
    -- Keystone text
    frame.keystoneText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.keystoneText:SetPoint("LEFT", frame, "LEFT", COLS.KEYSTONE.x, 0)
    frame.keystoneText:SetWidth(COLS.KEYSTONE.width)
    frame.keystoneText:SetHeight(Addon.Constants.ROW_HEIGHT)
    frame.keystoneText:SetJustifyH(COLS.KEYSTONE.justify)
    frame.keystoneText:SetJustifyV("MIDDLE")
    
    -- Invite button
    frame.inviteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.inviteBtn:SetSize(60, 20)
    frame.inviteBtn:SetPoint("LEFT", frame, "LEFT", COLS.ACTIONS.x, 0)
    frame.inviteBtn:SetText(L["BTN_INVITE"])
    frame.inviteBtn:SetNormalFontObject("GameFontNormalSmall")
    frame.inviteBtn:SetScript("OnClick", function()
        if frame.playerFullName then
            UI:InvitePlayer(frame.playerFullName, frame.charName)
        end
    end)
    
    -- Whisper button
    frame.whisperBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.whisperBtn:SetSize(60, 20)
    frame.whisperBtn:SetPoint("LEFT", frame.inviteBtn, "RIGHT", 5, 0)
    frame.whisperBtn:SetText(L["BTN_WHISPER"])
    frame.whisperBtn:SetNormalFontObject("GameFontNormalSmall")
    frame.whisperBtn:SetScript("OnClick", function()
        if frame.playerFullName then
            -- Use NameUtils for proper whisper name
            local whisperName
            if NameUtils then
                local success, name = NameUtils:GetWhisperName(frame.playerFullName)
                whisperName = success and name or frame.charName
            else
                whisperName = frame.charName
            end
            ChatFrame_OpenChat("/w " .. whisperName .. " ", ChatFrame1)
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
    lastListHash = nil,      -- Hash of entire list for change detection
    lastMemberCount = 0,     -- Track member count for structural changes
}

-- =============================================================================
-- List Initialization
-- =============================================================================

function UI:InitializeList()
    if listState.initialized then return end
    
    -- Cache NameUtils reference
    NameUtils = Addon.NameUtils
    
    listState.scrollChild = SocialLFGScrollChild
    if not listState.scrollChild then
        Addon:LogError("SocialLFGScrollChild not found")
        return
    end
    
    -- Create empty state frame
    self:CreateEmptyStateFrame()
    
    RowPool:Initialize(listState.scrollChild)
    
    -- Register for list changes
    Addon:RegisterCallback("OnListChanged", function()
        UI:UpdateList()
    end)
    
    listState.initialized = true
end

-- =============================================================================
-- Empty State
-- =============================================================================

function UI:CreateEmptyStateFrame()
    if listState.emptyFrame then return end
    
    local frame = CreateFrame("Frame", nil, listState.scrollChild)
    frame:SetAllPoints()
    frame:Hide()
    
    -- Main message
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.text:SetPoint("CENTER", 0, 20)
    frame.text:SetText(L["EMPTY_LIST_TITLE"] or "No players registered")
    frame.text:SetTextColor(0.5, 0.5, 0.5, 1)
    
    -- Sub message
    frame.subText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.subText:SetPoint("TOP", frame.text, "BOTTOM", 0, -10)
    frame.subText:SetText(L["EMPTY_LIST_HINT"] or "Register yourself or wait for friends/guild members")
    frame.subText:SetTextColor(0.4, 0.4, 0.4, 1)
    
    listState.emptyFrame = frame
end

function UI:ShowEmptyState(show)
    if not listState.emptyFrame then return end
    
    if show then
        listState.emptyFrame:Show()
    else
        listState.emptyFrame:Hide()
    end
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

    local Metrics = Addon.Metrics
    if Metrics and Metrics.enabled then Metrics:RecordStart("UI:DoUpdateList") end
    
    -- Get sorted member list
    local members = Addon.Members:GetSortedList()
    local memberCount = #members
    local currentPlayerName = Addon.runtime.playerName
    local currentPlayerFullName = Addon.runtime.playerFullName
    
    -- Show empty state if no members
    if memberCount == 0 then
        RowPool:ReleaseAll()
        self:ShowEmptyState(true)
        listState.scrollChild:SetHeight(200)
        SocialLFGScrollFrame:UpdateScrollChildRect()
        listState.lastMemberCount = 0
        listState.lastListHash = nil
        if Metrics and Metrics.enabled then Metrics:RecordEnd("UI:DoUpdateList") end
        return
    end
    
    self:ShowEmptyState(false)
    
    -- Compute list hash to detect changes
    local listHash = self:ComputeListHash(members)
    
    -- Fast path: nothing changed at all
    if listHash == listState.lastListHash and memberCount == listState.lastMemberCount then
        if Metrics and Metrics.enabled then Metrics:RecordEnd("UI:DoUpdateList") end
        return
    end
    
    local activeCount = RowPool:GetActiveCount()
    
    -- If list shrunk, release extra rows
    if memberCount < activeCount then
        RowPool:ReleaseFrom(memberCount + 1)
    end
    
    -- Update or create rows
    local previousRow = nil
    local needsReposition = (memberCount ~= listState.lastMemberCount) or 
                            (listHash ~= listState.lastListHash)
    
    for index, memberData in ipairs(members) do
        local row = RowPool:GetAtIndex(index)
        local isNewRow = false
        
        -- Acquire new row if needed
        if not row then
            row = RowPool:Acquire()
            isNewRow = true
        end
        
        -- Reposition if structure changed or new row
        if isNewRow or needsReposition then
            row:ClearAllPoints()
            if index == 1 then
                row:SetPoint("TOPLEFT", listState.scrollChild, "TOPLEFT", 0, 0)
            else
                row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, 0)
            end
        end
        
        -- Update row content (UpdateRow handles caching internally)
        self:UpdateRow(row, memberData, index, currentPlayerName, currentPlayerFullName)
        
        previousRow = row
    end
    
    -- Update state
    listState.lastListHash = listHash
    listState.lastMemberCount = memberCount
    
    -- Update scroll frame
    local childHeight = memberCount * Addon.Constants.ROW_HEIGHT
    listState.scrollChild:SetHeight(math.max(1, childHeight))
    SocialLFGScrollFrame:UpdateScrollChildRect()

    if Metrics and Metrics.enabled then Metrics:RecordEnd("UI:DoUpdateList") end
end

-- Compute a hash of the entire list for quick change detection
function UI:ComputeListHash(members)
    local parts = {}
    for i, memberData in ipairs(members) do
        -- Include name and status hash
        local statusHash = Utils:HashStatus(memberData.status)
        parts[i] = memberData.name .. ":" .. statusHash
    end
    return table.concat(parts, "|")
end

function UI:UpdateRow(row, memberData, index, currentPlayerName, currentPlayerFullName)
    local Metrics = Addon.Metrics
    if Metrics and Metrics.enabled then Metrics:RecordStart("UI:UpdateRow") end

    local playerFullName = memberData.name
    local status = memberData.status or {}
    
    -- Use NameUtils for display name (character name only)
    local charName
    if NameUtils then
        charName = NameUtils:GetDisplayName(playerFullName)
    else
        charName = Utils:ExtractCharacterName(playerFullName) or playerFullName
    end

    -- Determine if this is the current player using NameUtils
    local isSelf
    if NameUtils then
        isSelf = NameUtils:IsSamePlayer(playerFullName, currentPlayerFullName)
    else
        isSelf = (charName == currentPlayerName)
    end
    
    local class = status.class
    local rolesString = status.roles and table.concat(status.roles, ",") or ""
    local categoriesString = Addon:GetCategoryListLocalized(status.categories)
    local ilvlStr = tostring(status.ilvl or 0)
    local rioStr = tostring(status.rio or 0)
    local keystoneStr = status.keystone or L["NO_KEYSTONE"]
    
    -- Use NameUtils for colored name display
    local nameTextStr
    if NameUtils and class then
        nameTextStr = NameUtils:GetColoredDisplayName(playerFullName, class)
    elseif class then
        nameTextStr = Utils:GetColoredName(charName, class)
    else
        nameTextStr = charName
    end
    
    local bgIsEven = (index % 2 == 0)

    local cache = row._cache

    -- Fast path: nothing changed
    if cache
       and cache.playerFullName == playerFullName
       and cache.nameTextStr == nameTextStr
       and cache.class == class
       and cache.rolesString == rolesString
       and cache.categoriesString == categoriesString
       and cache.ilvlStr == ilvlStr
       and cache.rioStr == rioStr
       and cache.keystoneStr == keystoneStr
       and cache.isSelf == isSelf
       and cache.bgIsEven == bgIsEven then
        if Metrics and Metrics.enabled then Metrics:RecordEnd("UI:UpdateRow") end
        return
    end

    -- Store basic data on row
    row.playerName = charName
    row.playerFullName = playerFullName
    row.charName = charName
    row.statusInfo = status  -- Store for tooltip

    -- Background: update only if parity changed
    if not cache or cache.bgIsEven ~= bgIsEven then
        if bgIsEven then
            row.bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
        else
            row.bg:SetColorTexture(0.1, 0.1, 0.1, 0.1)
        end
    end

    -- Class icon: update only if changed
    if not cache or cache.class ~= class then
        if class then
            Utils:SetClassIcon(row.classIcon, class)
            row.classIcon:Show()
        else
            row.classIcon:Hide()
        end
    end

    -- Name text
    if (row.nameText:GetText() or "") ~= nameTextStr then
        row.nameText:SetText(nameTextStr)
    end

    -- Role icons
    if not cache or cache.rolesString ~= rolesString then
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
    end

    -- Categories
    if (row.categoriesText:GetText() or "") ~= categoriesString then
        row.categoriesText:SetText(categoriesString)
    end

    -- iLvL / Rio / Keystone
    if (row.ilvlText:GetText() or "") ~= ilvlStr then
        row.ilvlText:SetText(ilvlStr)
    end
    if (row.rioText:GetText() or "") ~= rioStr then
        row.rioText:SetText(rioStr)
    end
    if (row.keystoneText:GetText() or "") ~= keystoneStr then
        row.keystoneText:SetText(keystoneStr)
    end

    -- Action buttons
    if not cache or cache.isSelf ~= isSelf then
        if isSelf then
            row.inviteBtn:Hide()
            row.whisperBtn:Hide()
        else
            row.inviteBtn:Show()
            row.whisperBtn:Show()
        end
    end

    -- Update cache
    row._cache = {
        playerFullName = playerFullName,
        nameTextStr = nameTextStr,
        class = class,
        rolesString = rolesString,
        categoriesString = categoriesString,
        ilvlStr = ilvlStr,
        rioStr = rioStr,
        keystoneStr = keystoneStr,
        isSelf = isSelf,
        bgIsEven = bgIsEven,
    }

    if Metrics and Metrics.enabled then Metrics:RecordEnd("UI:UpdateRow") end
end

-- =============================================================================
-- Player Actions
-- =============================================================================

function UI:InvitePlayer(fullName, charName)
    if not fullName or fullName == "" then
        Addon:LogError(L["ERR_INVALID_PLAYER"])
        return
    end
    
    -- Use NameUtils to get proper invite name
    local inviteName
    local displayName
    
    if NameUtils then
        local success, name = NameUtils:GetInviteName(fullName)
        if success then
            inviteName = name
            displayName = NameUtils:GetDisplayName(fullName)
        else
            Addon:LogError(L["ERR_INVALID_PLAYER"])
            return
        end
    else
        inviteName = fullName
        displayName = charName or Utils:ExtractCharacterName(fullName) or fullName
    end
    
    -- Try standard invite
    local success = pcall(function()
        C_PartyInfo.InviteUnit(inviteName)
    end)
    
    if success then
        Addon:LogInfo(L["INFO_INVITED"]:format(displayName))
        return
    end
    
    -- Fallback: try with character name only (same realm)
    if NameUtils then
        local charOnly = NameUtils:ExtractCharacterName(fullName)
        success = pcall(function()
            C_PartyInfo.InviteUnit(charOnly)
        end)
        
        if success then
            Addon:LogInfo(L["INFO_INVITED"]:format(displayName))
            return
        end
    end
    
    -- Last resort: use chat command
    ChatFrame_OpenChat("/invite " .. inviteName, ChatFrame1)
    Addon:LogWarn(L["INFO_INVITED_ALT"]:format(displayName))
end

-- =============================================================================
-- Cleanup
-- =============================================================================

function UI:CleanupList()
    RowPool:ReleaseAll()
end
