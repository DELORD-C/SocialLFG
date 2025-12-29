--[[
    SocialLFG - LibDataBroker Integration
    Minimap button using LibDBIcon
]]

local ADDON_NAME = "SocialLFG"
local L = _G.SocialLFG_L

-- Check if libraries are available
local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
if not ldb then
    return
end

-- =============================================================================
-- Data Broker Object
-- =============================================================================

local plugin = ldb:NewDataObject(ADDON_NAME, {
    type = "data source",
    text = "LFG",
    icon = "Interface\\Icons\\Ability_Monk_ZenFlight",
})

-- Store globally for access from other modules
_G.SocialLFGPlugin = plugin

-- =============================================================================
-- Icon Button Reference
-- =============================================================================

local iconButton = nil

local function GetIconButton()
    if iconButton then return iconButton end
    
    local dbicon = LibStub("LibDBIcon-1.0", true)
    if not dbicon then return nil end
    
    iconButton = dbicon:GetMinimapButton(ADDON_NAME)
    return iconButton
end

-- =============================================================================
-- Icon Appearance
-- =============================================================================

function plugin:UpdateIconAppearance()
    local Addon = _G.SocialLFG
    if not Addon or not Addon.Database then return end
    
    local button = GetIconButton()
    if not button or not button.icon then return end
    
    local isRegistered = Addon.Database:IsRegistered()
    
    -- Desaturate when not registered
    button.icon:SetDesaturated(not isRegistered)
end

-- =============================================================================
-- Click Handlers
-- =============================================================================

function plugin.OnClick(self, button)
    local Addon = _G.SocialLFG
    if not Addon then return end
    
    if button == "RightButton" then
        -- Right click: Toggle registration
        if not Addon.Database:IsRegistered() then
            -- Validate before registering
            local categories = Addon.Database:GetSavedCategories()
            local roles = Addon.Database:GetSavedRoles()
            
            if #categories == 0 then
                Addon:LogWarn(L and L["ERR_SELECT_CATEGORY"] or "Please select at least one category")
                return
            end
            if #roles == 0 then
                Addon:LogWarn(L and L["ERR_SELECT_ROLE"] or "Please select at least one role")
                return
            end
        end
        
        Addon:Toggle()
        plugin:UpdateIconAppearance()
    else
        -- Left click: Toggle window
        if SocialLFGFrame then
            if SocialLFGFrame:IsShown() then
                SocialLFGFrame:Hide()
            else
                SocialLFGFrame:Show()
            end
        end
    end
end

-- =============================================================================
-- Tooltip
-- =============================================================================

function plugin.OnTooltipShow(tt)
    local Addon = _G.SocialLFG
    
    tt:AddLine(L and L["TOOLTIP_TITLE"] or "Social LFG")
    
    if not Addon or not Addon.Database then
        tt:AddLine("|cFFFF9900" .. (L and L["STATUS_LOADING"] or "Loading...") .. "|r", 1, 1, 1)
        return
    end
    
    local db = Addon.Database
    
    if db:IsRegistered() then
        tt:AddLine("|cFF00FF00" .. (L and L["STATUS_REGISTERED"] or "[REGISTERED]") .. "|r", 1, 1, 1)
        tt:AddLine(" ")
        
        local categories = db:GetCategories()
        local roles = db:GetRoles()
        
        tt:AddLine("|cFFFFFFFF" .. (L and L["TOOLTIP_CATEGORIES"] or "Categories:") .. "|r " .. table.concat(categories, ", "), 0.7, 0.7, 0.7)
        tt:AddLine("|cFFFFFFFF" .. (L and L["TOOLTIP_ROLES"] or "Roles:") .. "|r " .. table.concat(roles, ", "), 0.7, 0.7, 0.7)
        
        -- Show keystone if available
        if Addon.Player then
            local keystone = Addon.Player:FormatKeystone()
            local noKeystone = L and L["NO_KEYSTONE"] or "-"
            if keystone ~= noKeystone then
                tt:AddLine("|cFFFFFFFF" .. (L and L["TOOLTIP_KEYSTONE"] or "Keystone:") .. "|r " .. keystone, 0.7, 0.7, 0.7)
            end
        end
    else
        tt:AddLine("|cFFFF9900" .. (L and L["STATUS_NOT_REGISTERED"] or "[NOT REGISTERED]") .. "|r", 1, 1, 1)
        tt:AddLine(" ")
        tt:AddLine("|cFF999999" .. (L and L["TOOLTIP_SELECT_HINT"] or "Select categories and roles") .. "|r", 0.5, 0.5, 0.5)
        tt:AddLine("|cFF999999" .. (L and L["TOOLTIP_SELECT_HINT2"] or "to register for LFG") .. "|r", 0.5, 0.5, 0.5)
    end
    
    tt:AddLine(" ")
    tt:AddLine("|cFF00FF00" .. (L and L["TOOLTIP_LEFT_CLICK"] or "Left-click: Open/Close window") .. "|r", 0.2, 1, 0.2)
    tt:AddLine("|cFF00FF00" .. (L and L["TOOLTIP_RIGHT_CLICK"] or "Right-click: Toggle registration") .. "|r", 0.2, 1, 0.2)
end

-- =============================================================================
-- Registration
-- =============================================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    local icon = LibStub("LibDBIcon-1.0", true)
    if not icon then return end
    
    -- Initialize saved variables for icon position
    if not SocialLFGLDBIconDB then
        SocialLFGLDBIconDB = {}
    end
    
    -- Register the minimap button
    icon:Register(ADDON_NAME, plugin, SocialLFGLDBIconDB)
    
    -- Update appearance after a short delay (wait for addon init)
    C_Timer.After(1, function()
        plugin:UpdateIconAppearance()
    end)
end)
