local addonName = "SocialLFG"
local addon = SocialLFG

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

-- Click handler for the minimap button
function plugin.OnClick(self, button)
    if button == "RightButton" then
        -- Right click to toggle registration
        SocialLFG:ToggleLFG()
    else
        -- Left click to open/close window
        SocialLFG:ToggleWindow()
    end
end

-- Tooltip display
function plugin.OnTooltipShow(tt)
    tt:AddLine("Social LFG")
    
    if #SocialLFG.db.myStatus.categories > 0 then
        tt:AddLine("|cFF00FF00Registered|r", 1, 1, 1)
        tt:AddLine("Categories: " .. table.concat(SocialLFG.db.myStatus.categories, ", "), 0.7, 0.7, 0.7)
        tt:AddLine("Roles: " .. table.concat(SocialLFG.db.myStatus.roles, ", "), 0.7, 0.7, 0.7)
    else
        tt:AddLine("|cFFFF9900Not registered|r", 1, 1, 1)
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
