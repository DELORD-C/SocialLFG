--[[
    SocialLFG - Database Module
    SavedVariables management and persistence
]]

local Addon = _G.SocialLFG

-- Create Database module
Addon.Database = {}
local DB = Addon.Database

-- =============================================================================
-- Initialization
-- =============================================================================

function DB:Initialize()
    -- Initialize SavedVariables if not exists
    if not SocialLFGDB then
        SocialLFGDB = self:GetDefaultDB()
    end
    
    -- Ensure all fields exist (upgrade from older versions)
    self:MigrateDB()
    
    -- Store reference
    self.db = SocialLFGDB
end

function DB:GetDefaultDB()
    return {
        -- Current registration (empty = not registered)
        registration = {
            categories = {},
            roles = {},
        },
        
        -- Saved preferences (persists even when unregistered)
        savedPreferences = {
            categories = {},
            roles = {},
        },
        
        -- State preservation
        wasRegisteredBeforeGroup = false,
        
        -- UI state
        rioNoticeDismissed = false,
        
        -- Version for future migrations
        dbVersion = 2,
    }
end

function DB:MigrateDB()
    local db = SocialLFGDB
    
    -- Migrate from version 1 (old structure)
    if not db.dbVersion or db.dbVersion < 2 then
        -- Migrate old myStatus to registration
        if db.myStatus then
            db.registration = {
                categories = db.myStatus.categories or {},
                roles = db.myStatus.roles or {},
            }
            db.myStatus = nil
        end
        
        -- Migrate old saved categories/roles
        if db.savedCategories or db.savedRoles then
            db.savedPreferences = {
                categories = db.savedCategories or {},
                roles = db.savedRoles or {},
            }
            db.savedCategories = nil
            db.savedRoles = nil
        end
        
        -- Clean up old fields
        db.queriedFriends = nil
        db.lastQueryTime = nil
        
        db.dbVersion = 2
    end
    
    -- Ensure all required fields exist
    if not db.registration then
        db.registration = { categories = {}, roles = {} }
    end
    if not db.savedPreferences then
        db.savedPreferences = { categories = {}, roles = {} }
    end
    if db.wasRegisteredBeforeGroup == nil then
        db.wasRegisteredBeforeGroup = false
    end
    if db.rioNoticeDismissed == nil then
        db.rioNoticeDismissed = false
    end
end

-- =============================================================================
-- Registration Data
-- =============================================================================

function DB:IsRegistered()
    local db = self.db or SocialLFGDB
    if not db or not db.registration or not db.registration.categories then
        return false
    end
    return #db.registration.categories > 0
end

function DB:GetRegistration()
    local db = self.db or SocialLFGDB
    return db and db.registration or { categories = {}, roles = {} }
end

function DB:GetCategories()
    local db = self.db or SocialLFGDB
    return (db and db.registration and db.registration.categories) or {}
end

function DB:GetRoles()
    local db = self.db or SocialLFGDB
    return (db and db.registration and db.registration.roles) or {}
end

function DB:SetRegistration(categories, roles)
    self.db = self.db or SocialLFGDB or self:GetDefaultDB()
    self.db.registration = {
        categories = categories or {},
        roles = roles or {},
    }
    
    -- Also save as preferences
    self:SetSavedPreferences(categories, roles)
end

function DB:ClearRegistration()
    self.db.registration = {
        categories = {},
        roles = {},
    }
end

-- =============================================================================
-- Saved Preferences
-- =============================================================================

function DB:GetSavedCategories()
    local db = self.db or SocialLFGDB
    return (db and db.savedPreferences and db.savedPreferences.categories) or {}
end

function DB:GetSavedRoles()
    local db = self.db or SocialLFGDB
    return (db and db.savedPreferences and db.savedPreferences.roles) or {}
end

function DB:SetSavedPreferences(categories, roles)
    self.db = self.db or SocialLFGDB or self:GetDefaultDB()
    self.db.savedPreferences = {
        categories = categories or {},
        roles = roles or {},
    }
end

-- =============================================================================
-- Group State
-- =============================================================================

function DB:WasRegisteredBeforeGroup()
    local db = self.db or SocialLFGDB
    return (db and db.wasRegisteredBeforeGroup) or false
end

function DB:SetWasRegisteredBeforeGroup(value)
    self.db = self.db or SocialLFGDB or self:GetDefaultDB()
    self.db.wasRegisteredBeforeGroup = value
end

-- =============================================================================
-- UI State
-- =============================================================================

function DB:IsRioNoticeDismissed()
    local db = self.db or SocialLFGDB
    return (db and db.rioNoticeDismissed) or false
end

function DB:DismissRioNotice()
    self.db = self.db or SocialLFGDB or self:GetDefaultDB()
    self.db.rioNoticeDismissed = true
end
