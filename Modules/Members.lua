--[[
    SocialLFG - Members Module
    LFG members list management with differential updates and relay support
    
    MEMBER SOURCES:
    - "direct": Player communicated with us directly (whisper, guild, bnet)
    - "relay": We learned about this player through another player's relay
    
    Direct sources are preferred over relay sources. When we receive a relay
    about a player we already know directly, we ignore the relay.
]]

local Addon = _G.SocialLFG
local Utils = Addon.Utils

-- NameUtils reference (set after initialization)
local NameUtils = nil

-- Create Members module
Addon.Members = {}
local Members = Addon.Members

-- =============================================================================
-- Internal State
-- =============================================================================

local state = {
    -- Member data: [playerFullName] = { status, lastSeen, source, sourcePlayer }
    -- source: "direct" | "relay"
    -- sourcePlayer: who told us about this member (for relay)
    members = {},
    
    -- Sorted list cache (invalidated on change)
    sortedCache = nil,
    sortedCacheValid = false,
    
    -- Change tracking for differential updates
    pendingChanges = {},
    hasPendingChanges = false,
    
    -- Periodic update timer
    updateTimer = nil,
}

-- =============================================================================
-- Initialization
-- =============================================================================

function Members:Initialize()
    -- Cache NameUtils reference
    NameUtils = Addon.NameUtils
    
    wipe(state.members)
    wipe(state.pendingChanges)
    state.sortedCacheValid = false
end

-- =============================================================================
-- Member Management
-- =============================================================================

-- Update or add a member
-- source: "direct" (default) or "relay"
-- sourcePlayer: who told us about this member (required for relay)
function Members:UpdateMember(playerName, status, source, sourcePlayer)
    if not playerName then
        return
    end
    
    source = source or "direct"
    
    -- Validate and normalize player name
    local isValid = NameUtils and NameUtils:IsValidName(playerName) or Utils:IsValidPlayerName(playerName)
    if not isValid then
        return
    end
    
    -- Normalize to canonical format
    if NameUtils then
        playerName = NameUtils:ToCanonical(playerName) or playerName
    end
    
    -- Don't update local player through this method
    local isSelf = NameUtils and NameUtils:IsSamePlayer(playerName, Addon.runtime.playerFullName)
                   or playerName == Addon.runtime.playerFullName
    if isSelf then
        return
    end
    
    local now = GetTime()
    local existing = state.members[playerName]
    
    -- Handle source priority: direct > relay
    if existing then
        -- If we have direct info, ignore relay updates
        if existing.source == "direct" and source == "relay" then
            return
        end
        
        -- If upgrading from relay to direct, always update
        if existing.source == "relay" and source == "direct" then
            -- Fall through to update
        else
            -- Same source type - check if status actually changed
            local oldHash = Utils:HashStatus(existing.status)
            local newHash = Utils:HashStatus(status)
            
            if oldHash == newHash then
                -- Just refresh timestamp
                existing.lastSeen = now
                return
            end
        end
    end
    
    -- Update or add member
    state.members[playerName] = {
        status = status,
        lastSeen = now,
        source = source,
        sourcePlayer = sourcePlayer,
    }
    
    -- Mark change
    self:MarkChanged(playerName, "update")
end

function Members:RemoveMember(playerName)
    if not playerName then return end
    
    -- Normalize for lookup
    if NameUtils then
        playerName = NameUtils:ToCanonical(playerName) or playerName
    end
    
    -- Don't remove local player through this method
    local isSelf = NameUtils and NameUtils:IsSamePlayer(playerName, Addon.runtime.playerFullName)
                   or playerName == Addon.runtime.playerFullName
    if isSelf then
        return
    end
    
    if state.members[playerName] then
        state.members[playerName] = nil
        self:MarkChanged(playerName, "remove")
        
        -- Clean up communication state
        Addon.Communication:ClearPlayerData(playerName)
    end
end

function Members:RefreshTimestamp(playerName)
    if not playerName then return end
    
    local member = state.members[playerName]
    if member then
        member.lastSeen = GetTime()
    end
end

-- Get members eligible for relay (direct sources only, seen recently)
-- excludePlayer: don't include this player (the one we're relaying to)
-- Returns: array of { name, status, age } sorted by age (freshest first)
function Members:GetRelayEligibleMembers(excludePlayer)
    local eligible = {}
    local now = GetTime()
    local maxAge = Addon.Constants.RELAY_MAX_AGE
    local localPlayer = Addon.runtime.playerFullName
    
    for playerName, data in pairs(state.members) do
        -- Only relay direct sources (not relayed data - prevents loops)
        if data.source == "direct" then
            local age = now - data.lastSeen
            
            -- Skip: self, the target, and stale data
            if playerName ~= localPlayer and 
               playerName ~= excludePlayer and 
               age <= maxAge then
                table.insert(eligible, {
                    name = playerName,
                    status = data.status,
                    age = age,
                })
            end
        end
    end
    
    -- Sort by freshness (newest first)
    table.sort(eligible, function(a, b)
        return a.age < b.age
    end)
    
    return eligible
end

-- Check if a member was from relay source
function Members:IsRelayedMember(playerName)
    local member = state.members[playerName]
    return member and member.source == "relay"
end

-- =============================================================================
-- Local Player Management
-- =============================================================================

function Members:AddLocalPlayer()
    if not Addon:IsRegistered() then
        return
    end
    
    local playerName = Addon.runtime.playerFullName
    local status = Addon.Player:BuildStatus()
    
    state.members[playerName] = {
        status = status,
        lastSeen = GetTime(),
        source = "direct",
        sourcePlayer = nil,
    }
    
    self:MarkChanged(playerName, "update")
end

function Members:RemoveLocalPlayer()
    local playerName = Addon.runtime.playerFullName
    
    if state.members[playerName] then
        state.members[playerName] = nil
        self:MarkChanged(playerName, "remove")
    end
end

-- =============================================================================
-- Change Tracking
-- =============================================================================

function Members:MarkChanged(playerName, changeType)
    state.pendingChanges[playerName] = changeType
    state.hasPendingChanges = true
    state.sortedCacheValid = false
    
    -- Schedule UI update
    self:ScheduleListUpdate()
end

function Members:GetPendingChanges()
    if not state.hasPendingChanges then
        return nil
    end
    
    local changes = state.pendingChanges
    state.pendingChanges = {}
    state.hasPendingChanges = false
    
    return changes
end

function Members:HasChanges()
    return state.hasPendingChanges
end

-- =============================================================================
-- List Update Scheduling
-- =============================================================================

local lastScheduledUpdate = 0

function Members:ScheduleListUpdate()
    local now = GetTime()
    
    -- Throttle update scheduling
    if now - lastScheduledUpdate < Addon.Constants.LIST_UPDATE_THROTTLE then
        return
    end
    
    lastScheduledUpdate = now
    
    -- Fire callback for UI update
    C_Timer.After(0.01, function()
        Addon:FireCallback("OnListChanged")
    end)
end

-- =============================================================================
-- Query Methods
-- =============================================================================

function Members:GetMember(playerName)
    local member = state.members[playerName]
    if member then
        return member.status
    end
    return nil
end

function Members:GetAllMembers()
    return state.members
end

function Members:GetMemberCount()
    return Utils:TableCount(state.members)
end

function Members:GetSortedList()
    -- Return cached list if valid
    if state.sortedCacheValid and state.sortedCache then
        return state.sortedCache
    end
    
    -- Build sorted list
    local sorted = {}
    for playerName, data in pairs(state.members) do
        table.insert(sorted, {
            name = playerName,
            status = data.status,
            lastSeen = data.lastSeen,
        })
    end
    
    -- Sort by Rio (desc), then by name (asc)
    table.sort(sorted, function(a, b)
        local rioA = (a.status and a.status.rio) or 0
        local rioB = (b.status and b.status.rio) or 0
        
        if rioA ~= rioB then
            return rioA > rioB
        end
        
        return a.name < b.name
    end)
    
    -- Cache the result
    state.sortedCache = sorted
    state.sortedCacheValid = true
    
    return sorted
end

-- =============================================================================
-- Timeout Management
-- =============================================================================

function Members:StartPeriodicCleanup()
    if state.updateTimer then return end
    
    state.updateTimer = C_Timer.NewTicker(Addon.Constants.QUERY_INTERVAL, function()
        Members:CheckTimeouts()
        
        -- Also trigger periodic query if window is open
        if SocialLFGFrame and SocialLFGFrame:IsShown() then
            Addon.Communication:QueryAllPlayers()
        end
    end)
end

function Members:StopPeriodicCleanup()
    if state.updateTimer then
        state.updateTimer:Cancel()
        state.updateTimer = nil
    end
end

function Members:CheckTimeouts()
    local now = GetTime()
    local localPlayer = Addon.runtime.playerFullName
    local removed = false
    
    -- Get current online friends for reference
    local onlineFriends = {}
    for _, name in ipairs(Addon.Communication:GetAllOnlineFriends()) do
        onlineFriends[name] = true
    end
    
    for playerName, data in pairs(state.members) do
        -- Never timeout local player
        if playerName == localPlayer then
            data.lastSeen = now
        else
            local timeSinceLastSeen = now - data.lastSeen
            local isOnline = onlineFriends[playerName] == true
            
            -- Remove if:
            -- 1. Offline and exceeded timeout
            -- 2. Extended timeout exceeded (safety net)
            if (not isOnline and timeSinceLastSeen > Addon.Constants.TIMEOUT) or
               (timeSinceLastSeen > Addon.Constants.TIMEOUT * 3) then
                self:RemoveMember(playerName)
                removed = true
            end
        end
    end
    
    return removed
end

function Members:CleanupOfflinePlayers()
    -- Called when a friend goes offline
    local onlineFriends = {}
    for _, name in ipairs(Addon.Communication:GetAllOnlineFriends()) do
        onlineFriends[name] = true
    end
    
    local localPlayer = Addon.runtime.playerFullName
    
    for playerName in pairs(state.members) do
        if playerName ~= localPlayer and not onlineFriends[playerName] then
            -- Give them a grace period by setting lastSeen to a bit ago
            -- This will cause them to be removed on next timeout check
            if state.members[playerName] then
                state.members[playerName].lastSeen = GetTime() - (Addon.Constants.TIMEOUT - 10)
            end
        end
    end
end

-- =============================================================================
-- Iteration
-- =============================================================================

function Members:Iterate()
    return pairs(state.members)
end
