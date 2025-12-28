local addonName = "SocialLFG"

-- Check if libraries are available
local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
if not ldb then
    return
end

-- Create the data broker plugin
local plugin = ldb:NewDataObject(addonName, {
    type = "data source",
    text = "LFG",
    icon = "Interface\\Icons\\Ability_Monk_ZenFlight",
})

-- Store plugin globally so SocialLFG addon can access it
_G.SocialLFGPlugin = plugin

-- Store reference to icon button for visual updates
local iconButton = nil

-- Helper function to get the icon button (created by LibDBIcon)
local function GetIconButton()
    if iconButton then return iconButton end
    
    -- LibDBIcon creates a button with this naming convention
    local dbicon = LibStub("LibDBIcon-1.0", true)
    if not dbicon then return nil end
    iconButton = dbicon:GetMinimapButton(addonName)
    return iconButton
end

-- Update minimap icon appearance based on registration status
function plugin:UpdateIconAppearance()
    if not SocialLFG or not SocialLFG.db then return end
    
    local button = GetIconButton()
    if not button or not button.icon then return end
    
    local isRegistered = #SocialLFG.db.myStatus.categories > 0
    
    if isRegistered then
        -- Resaturate when registered
        button.icon:SetDesaturated(false)
    else
        -- Desaturate when not registered
        button.icon:SetDesaturated(true)
    end
end

-- Click handler for the minimap button
function plugin.OnClick(self, button)
    if not SocialLFG then return end
    
    if button == "RightButton" then
        -- Right click to toggle registration
        -- Validate before attempting to register
        if #SocialLFG.db.myStatus.categories == 0 then
            -- Not registered, check if we can register
            -- Use saved preferences (which persist even when window is closed)
            local categories = SocialLFG.db.savedCategories or {}
            local roles = SocialLFG.db.savedRoles or {}
            
            if #categories == 0 then
                print("|cFFFF6B6BError: Please select at least one category to register|r")
                return
            end
            if #roles == 0 then
                print("|cFFFF6B6BError: Please select at least one role to register|r")
                return
            end
        end
        SocialLFG:ToggleLFG()
        -- Update icon appearance after toggle
        plugin:UpdateIconAppearance()
    else
        -- Left click to open/close window
        SocialLFG:ToggleWindow()
    end
end

-- Tooltip display with registration status
function plugin.OnTooltipShow(tt)
    tt:AddLine("Social LFG")
    
    -- Check if SocialLFG and its database are initialized
    if not SocialLFG or not SocialLFG.db then
        tt:AddLine("|cFFFF9900Loading...|r", 1, 1, 1)
        return
    end
    
    if #SocialLFG.db.myStatus.categories > 0 then
        tt:AddLine("|cFF00FF00[REGISTERED]|r", 1, 1, 1)
        tt:AddLine(" ")
        tt:AddLine("|cFFFFFFFFCategories:|r " .. table.concat(SocialLFG.db.myStatus.categories, ", "), 0.7, 0.7, 0.7)
        tt:AddLine("|cFFFFFFFFRoles:|r " .. table.concat(SocialLFG.db.myStatus.roles, ", "), 0.7, 0.7, 0.7)
        
        -- Show keystone if available
        if SocialLFG.playerKeystone then
            local keystoneStr = SocialLFG:FormatKeystoneString(SocialLFG.playerKeystone)
            tt:AddLine("|cFFFFFFFFKeystone:|r " .. keystoneStr, 0.7, 0.7, 0.7)
        end
    else
        tt:AddLine("|cFFFF9900[NOT REGISTERED]|r", 1, 1, 1)
        tt:AddLine(" ")
        tt:AddLine("|cFF999999Select categories and roles|r", 0.5, 0.5, 0.5)
        tt:AddLine("|cFF999999to register for LFG|r", 0.5, 0.5, 0.5)
    end
    
    tt:AddLine(" ")
    tt:AddLine("|cFF00FF00Left-click:|r Open/Close window", 0.2, 1, 0.2)
    tt:AddLine("|cFF00FF00Right-click:|r Toggle registration", 0.2, 1, 0.2)
end

-- Register with LibDBIcon on player login
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function()
    local icon = LibStub("LibDBIcon-1.0", true)
    if not icon then
        return
    end
    
    if not SocialLFGLDBIconDB then
        SocialLFGLDBIconDB = {}
    end
    
    icon:Register(addonName, plugin, SocialLFGLDBIconDB)
end)
frame:RegisterEvent("PLAYER_LOGIN")
