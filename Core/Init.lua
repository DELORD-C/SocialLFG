--[[
    SocialLFG - Init Module
    Final initialization after all modules are loaded
]]

local Addon = _G.SocialLFG

-- This runs after all modules are loaded but the frame exists
-- We hook into PLAYER_LOGIN to do final setup

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Ensure addon is initialized
        if not Addon.runtime.initialized then
            return
        end
        
        -- Setup main frame
        if Addon.UI and Addon.UI.SetupMainFrame then
            Addon.UI:SetupMainFrame()
        end
        
        -- Restrict roles by class
        if Addon.UI and Addon.UI.RestrictRolesByClass then
            Addon.UI:RestrictRolesByClass()
        end
        
        -- Register UI callbacks
        if Addon.UI and Addon.UI.RegisterCallbacks then
            Addon.UI:RegisterCallbacks()
        end
        
        -- Unregister - only needed once
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
