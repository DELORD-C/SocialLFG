--[[
    SocialLFG - UI MainFrame Module
    Main frame setup and event handling
]]

local Addon = _G.SocialLFG
local L = _G.SocialLFG_L

-- Create UI module if not exists
Addon.UI = Addon.UI or {}
local UI = Addon.UI

-- =============================================================================
-- Frame Setup
-- =============================================================================

function UI:LocalizeTexts()
    -- Localize static UI text
    if SocialLFGTitle then SocialLFGTitle:SetText(L["ADDON_NAME"]) end
    if SocialLFGCategoryLabel then SocialLFGCategoryLabel:SetText(L["LABEL_CATEGORY"]) end
    if SocialLFGRoleLabel then SocialLFGRoleLabel:SetText(L["LABEL_ROLES"]) end
    if SocialLFGMembersLabel then SocialLFGMembersLabel:SetText(L["LABEL_MEMBERS"]) end

    -- Column headers
    if SocialLFGNameHeader then SocialLFGNameHeader:SetText(L["LABEL_NAME"]) end
    if SocialLFGRolesHeader then SocialLFGRolesHeader:SetText(L["LABEL_ROLES"]) end
    if SocialLFGCategoriesHeader then SocialLFGCategoriesHeader:SetText(L["LABEL_CATEGORIES"]) end
    if SocialLFGILVLHeader then SocialLFGILVLHeader:SetText(L["LABEL_ILVL"]) end
    if SocialLFGRioHeader then SocialLFGRioHeader:SetText(L["LABEL_RIO"]) end
    if SocialLFGKeystoneHeader then SocialLFGKeystoneHeader:SetText(L["LABEL_KEYSTONE"]) end

    -- Checkbox labels (categories)
    if SocialLFGRaidCheck and SocialLFGRaidCheck.SetText then SocialLFGRaidCheck:SetText(L["CATEGORY_RAID"]) end
    if SocialLFGMythicCheck and SocialLFGMythicCheck.SetText then SocialLFGMythicCheck:SetText(L["CATEGORY_MYTHIC"]) end
    if SocialLFGQuestingCheck and SocialLFGQuestingCheck.SetText then SocialLFGQuestingCheck:SetText(L["CATEGORY_QUESTING"]) end
    if SocialLFGBoostingCheck and SocialLFGBoostingCheck.SetText then SocialLFGBoostingCheck:SetText(L["CATEGORY_BOOSTING"]) end

    -- Also set text for explicitly named labels (covers templates using FontString children)
    if SocialLFGQuestingLabel then SocialLFGQuestingLabel:SetText(L["CATEGORY_QUESTING"]) end
    if SocialLFGBoostingLabel then SocialLFGBoostingLabel:SetText(L["CATEGORY_BOOSTING"]) end
    if SocialLFGPVPCheck and SocialLFGPVPCheck.SetText then SocialLFGPVPCheck:SetText(L["CATEGORY_PVP"]) end

    -- Role checkbox labels
    if SocialLFGTankCheck and SocialLFGTankCheck.SetText then SocialLFGTankCheck:SetText(L["ROLE_TANK"]) end
    if SocialLFGHealCheck and SocialLFGHealCheck.SetText then SocialLFGHealCheck:SetText(L["ROLE_HEAL"]) end
    if SocialLFGDPSCheck and SocialLFGDPSCheck.SetText then SocialLFGDPSCheck:SetText(L["ROLE_DPS"]) end
end


function UI:SetupMainFrame()
    local frame = SocialLFGFrame
    if not frame then return end
    
    -- Configure frame properties
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)

    -- Apply localization immediately
    self:LocalizeTexts()

    -- Set up show/hide handlers
    frame:SetScript("OnShow", function()
        UI:OnShow()
    end)
    
    frame:SetScript("OnHide", function()
        UI:OnHide()
    end)
end

-- =============================================================================
-- Show/Hide Handlers
-- =============================================================================

function UI:OnShow()
    -- Ensure localized texts are applied (in case locale changed or initialization order differed)
    self:LocalizeTexts()

    -- Initialize list if needed
    self:InitializeList()
    
    -- Restore checkbox states
    self:RestoreCheckboxStates()
    
    -- Update button state
    self:UpdateButtonState()
    
    -- Add local player to list
    if Addon:IsRegistered() then
        Addon.Members:AddLocalPlayer()
    end
    
    -- Query all players (with throttling)
    if not Addon.runtime.hasInitialQuery then
        Addon.Communication:QueryAllPlayers()
        Addon.runtime.hasInitialQuery = true
    end
    
    -- Update list
    self:UpdateList()
    
    -- Start periodic updates
    Addon.Members:StartPeriodicCleanup()
    
    -- Fire callback
    Addon:FireCallback("OnFrameShown")
end

function UI:OnHide()
    -- Stop periodic updates
    Addon.Members:StopPeriodicCleanup()
    
    -- Fire callback
    Addon:FireCallback("OnFrameHidden")
end

-- =============================================================================
-- Button State
-- =============================================================================

function UI:UpdateButtonState()
    local btn = SocialLFGRegisterButton
    if not btn then return end

    local now = GetTime()
    if btn._cooldownUntil and now < btn._cooldownUntil then
        -- Visually and functionally disable the button during cooldown
        btn:SetText(L["BTN_WORKING"])
        btn:Disable()
        btn:EnableMouse(false)
        btn:SetAlpha(0.6)
        return
    end

    -- Restore appearance if out of cooldown
    btn:EnableMouse(true)
    btn:SetAlpha(1)

    local inGroup = IsInGroup()

    if inGroup then
        btn:SetText(L["BTN_IN_GROUP"])
        btn:Disable()
        btn:EnableMouse(false)
    elseif Addon:IsRegistered() then
        btn:SetText(L["BTN_UNREGISTER"])
        btn:Enable()
    else
        local categories = self:GetCheckedCategories()
        local roles = self:GetCheckedRoles()

        if #categories > 0 and #roles > 0 then
            btn:SetText(L["BTN_REGISTER"])
            btn:Enable()
        else
            btn:SetText(L["BTN_SELECT_FIRST"])
            btn:Disable()
        end
    end
end

-- =============================================================================
-- Checkbox Management
-- =============================================================================

function UI:GetCheckedCategories()
    local categories = {}
    
    if SocialLFGRaidCheck and SocialLFGRaidCheck:GetChecked() then
        table.insert(categories, "Raid")
    end
    if SocialLFGMythicCheck and SocialLFGMythicCheck:GetChecked() then
        table.insert(categories, "Mythic+")
    end
    if SocialLFGQuestingCheck and SocialLFGQuestingCheck:GetChecked() then
        table.insert(categories, "Questing")
    end
    if SocialLFGBoostingCheck and SocialLFGBoostingCheck:GetChecked() then
        table.insert(categories, "Boosting")
    end
    if SocialLFGPVPCheck and SocialLFGPVPCheck:GetChecked() then
        table.insert(categories, "PVP")
    end
    
    return categories
end

function UI:GetCheckedRoles()
    local roles = {}
    
    -- Only check visible checkboxes (respects class restrictions)
    if SocialLFGTankCheck and SocialLFGTankCheck:IsVisible() and SocialLFGTankCheck:GetChecked() then
        table.insert(roles, "Tank")
    end
    if SocialLFGHealCheck and SocialLFGHealCheck:IsVisible() and SocialLFGHealCheck:GetChecked() then
        table.insert(roles, "Heal")
    end
    if SocialLFGDPSCheck and SocialLFGDPSCheck:IsVisible() and SocialLFGDPSCheck:GetChecked() then
        table.insert(roles, "DPS")
    end
    
    return roles
end

function UI:SaveCheckboxState()
    local categories = self:GetCheckedCategories()
    local roles = self:GetCheckedRoles()
    
    Addon.Database:SetSavedPreferences(categories, roles)
end

function UI:RestoreCheckboxStates()
    local db = Addon.Database
    local categories, roles
    
    if db:IsRegistered() then
        categories = db:GetCategories()
        roles = db:GetRoles()
    else
        categories = db:GetSavedCategories()
        roles = db:GetSavedRoles()
    end
    
    -- Set category checkboxes
    if SocialLFGRaidCheck then
        SocialLFGRaidCheck:SetChecked(tContains(categories, "Raid"))
    end
    if SocialLFGMythicCheck then
        SocialLFGMythicCheck:SetChecked(tContains(categories, "Mythic+"))
    end
    if SocialLFGQuestingCheck then
        SocialLFGQuestingCheck:SetChecked(tContains(categories, "Questing"))
    end
    if SocialLFGBoostingCheck then
        SocialLFGBoostingCheck:SetChecked(tContains(categories, "Boosting"))
    end
    if SocialLFGPVPCheck then
        SocialLFGPVPCheck:SetChecked(tContains(categories, "PVP"))
    end
    
    -- Set role checkboxes (only visible ones)
    if SocialLFGTankCheck and SocialLFGTankCheck:IsVisible() then
        SocialLFGTankCheck:SetChecked(tContains(roles, "Tank"))
    end
    if SocialLFGHealCheck and SocialLFGHealCheck:IsVisible() then
        SocialLFGHealCheck:SetChecked(tContains(roles, "Heal"))
    end
    if SocialLFGDPSCheck and SocialLFGDPSCheck:IsVisible() then
        SocialLFGDPSCheck:SetChecked(tContains(roles, "DPS"))
    end
end

-- =============================================================================
-- Role Restriction by Class
-- =============================================================================

function UI:RestrictRolesByClass()
    local allowedRoles = Addon.Player:GetAllowedRoles()
    
    -- Hide checkboxes for roles not available to this class
    if SocialLFGTankCheck and not tContains(allowedRoles, "Tank") then
        SocialLFGTankCheck:Hide()
    end
    if SocialLFGHealCheck and not tContains(allowedRoles, "Heal") then
        SocialLFGHealCheck:Hide()
    end
    if SocialLFGDPSCheck and not tContains(allowedRoles, "DPS") then
        SocialLFGDPSCheck:Hide()
    end
    
    -- Reposition remaining checkboxes
    self:RepositionRoleCheckboxes(allowedRoles)
end

function UI:RepositionRoleCheckboxes(allowedRoles)
    local roleCheckboxes = {
        {name = "Tank", frame = SocialLFGTankCheck},
        {name = "Heal", frame = SocialLFGHealCheck},
        {name = "DPS", frame = SocialLFGDPSCheck},
    }
    
    local firstVisibleRole = nil
    local previousRole = nil
    
    for _, roleData in ipairs(roleCheckboxes) do
        if roleData.frame and tContains(allowedRoles, roleData.name) then
            if not firstVisibleRole then
                firstVisibleRole = roleData.frame
                roleData.frame:ClearAllPoints()
                roleData.frame:SetPoint("TOPLEFT", SocialLFGFrame, "TOPLEFT", 20, -110)
            else
                roleData.frame:ClearAllPoints()
                roleData.frame:SetPoint("LEFT", previousRole, "RIGHT", 60, 0)
            end
            previousRole = roleData.frame
        end
    end
end

-- =============================================================================
-- Checkbox Click Handler
-- =============================================================================

function UI:OnCheckboxClick()
    -- Save current state
    self:SaveCheckboxState()
    
    local categories = self:GetCheckedCategories()
    local roles = self:GetCheckedRoles()
    
    if Addon:IsRegistered() then
        -- If registered, update or unregister
        if #categories > 0 and #roles > 0 then
            -- Update registration
            Addon.Database:SetRegistration(categories, roles)
            Addon.Communication:BroadcastStatus()
            Addon.Members:AddLocalPlayer()
        else
            -- Unregister (missing categories or roles)
            Addon:Unregister()
        end
    end
    
    -- Always update button state
    self:UpdateButtonState()
end

-- =============================================================================
-- Register Button Click Handler
-- =============================================================================

function UI:OnRegisterClick()
    local btn = SocialLFGRegisterButton
    if not btn or not btn:IsEnabled() then return end

    -- Set a cooldown on the button to prevent spamming
    local cooldown = Addon.Constants.REGISTER_COOLDOWN or 2
    btn._cooldownUntil = GetTime() + cooldown

    -- Visually and functionally disable the button
    btn:SetText(L["BTN_WORKING"])
    btn:Disable()
    btn:EnableMouse(false)
    btn:SetAlpha(0.6)

    -- Remove click handler to be extra-safe, store original
    if not btn._origOnClick then
        btn._origOnClick = btn:GetScript("OnClick")
    end
    btn:SetScript("OnClick", function() end)

    Addon:Toggle()

    -- Restore after cooldown
    C_Timer.After(cooldown, function()
        if not btn then return end
        btn._cooldownUntil = nil

        -- Restore click handler
        if btn._origOnClick then
            btn:SetScript("OnClick", btn._origOnClick)
            btn._origOnClick = nil
        end

        btn:EnableMouse(true)
        btn:SetAlpha(1)
        UI:UpdateButtonState()
    end)
end

-- =============================================================================
-- Callbacks Setup
-- =============================================================================

function UI:RegisterCallbacks()
    Addon:RegisterCallback("OnRegistrationChanged", function()
        UI:UpdateButtonState()
        UI:RestoreCheckboxStates()
        UI:UpdateMinimapIcon()
    end)
    
    Addon:RegisterCallback("OnGroupStatusChanged", function()
        UI:UpdateButtonState()
        UI:UpdateMinimapIcon()
    end)
end

-- =============================================================================
-- Minimap Icon Update
-- =============================================================================

function UI:UpdateMinimapIcon()
    if _G.SocialLFGPlugin and _G.SocialLFGPlugin.UpdateIconAppearance then
        _G.SocialLFGPlugin:UpdateIconAppearance()
    end
end
