--[[
    SocialLFG - Communication Module
    Message protocol, throttling, queuing, and rate limiting
    
    This module handles all addon communication with:
    - Message queuing and rate limiting
    - Query throttling per target
    - Broadcast debouncing
    - Deduplication of incoming messages
]]

local Addon = _G.SocialLFG
local Utils = Addon.Utils
local L = _G.SocialLFG_L

-- Create Communication module
Addon.Communication = {}
local Comm = Addon.Communication

-- =============================================================================
-- Internal State
-- =============================================================================

local state = {
    -- Message queue for rate limiting
    messageQueue = {},
    isProcessingQueue = false,
    lastMessageTime = 0,
    
    -- Query throttling
    lastQueryTime = {},      -- [targetName] = timestamp
    lastGuildQueryTime = 0,
    pendingQueryTimer = nil,
    
    -- Broadcast debouncing
    pendingBroadcast = nil,
    lastBroadcastTime = 0,
    
    -- Deduplication
    recentStatusHashes = {}, -- [playerName] = hash
}

-- =============================================================================
-- Initialization
-- =============================================================================

function Comm:Initialize()
    -- Reset state
    wipe(state.messageQueue)
    wipe(state.lastQueryTime)
    wipe(state.recentStatusHashes)
end

-- =============================================================================
-- Message Protocol
-- =============================================================================

-- Message format: COMMAND|arg1|arg2|...
-- Commands:
--   STATUS|categories|roles|ilvl|rio|class|keystone
--   QUERY
--   UNREGISTER

local function ParseMessage(message)
    if not message then return nil end
    return Utils:Split(message, "|")
end

local function BuildStatusMessage()
    local db = Addon.Database
    local player = Addon.Player
    
    local categories = table.concat(db:GetCategories(), ",")
    local roles = table.concat(db:GetRoles(), ",")
    local ilvl = math.floor(GetAverageItemLevel())
    local rio = player:GetRioScore()
    local class = Addon.runtime.playerClass or ""
    local keystone = player:FormatKeystone()
    
    return string.format("STATUS|%s|%s|%d|%d|%s|%s",
        categories, roles, ilvl, rio, class, keystone)
end

-- =============================================================================
-- Message Queue (Rate Limiting)
-- =============================================================================

local function ProcessMessageQueue()
    if state.isProcessingQueue then return end
    if #state.messageQueue == 0 then return end
    
    state.isProcessingQueue = true
    
    -- Process next message if rate limit allows
    local now = GetTime()
    local timeSinceLast = now - state.lastMessageTime
    
    if timeSinceLast >= Addon.Constants.MESSAGE_RATE_LIMIT then
        local msg = table.remove(state.messageQueue, 1)
        if msg then
            C_ChatInfo.SendAddonMessage(
                Addon.Constants.PREFIX,
                msg.message,
                msg.channel,
                msg.target
            )
            state.lastMessageTime = now
        end
    end
    
    state.isProcessingQueue = false
    
    -- Schedule next processing if queue not empty
    if #state.messageQueue > 0 then
        C_Timer.After(Addon.Constants.MESSAGE_RATE_LIMIT, ProcessMessageQueue)
    end
end

local function QueueMessage(message, channel, target)
    -- Validate parameters
    if not message or message == "" then return end
    if not channel then return end
    
    if channel == "WHISPER" then
        if not target or target == "" then return end
        if not Utils:IsValidPlayerName(target) then return end
    end
    
    -- Add to queue
    table.insert(state.messageQueue, {
        message = message,
        channel = channel,
        target = target,
    })
    
    -- Start processing
    ProcessMessageQueue()
end

-- =============================================================================
-- Outgoing Messages
-- =============================================================================

function Comm:SendToGuild(message)
    if IsInGuild() then
        QueueMessage(message, "GUILD")
    end
end

function Comm:SendToPlayer(message, target)
    if not target or not Utils:IsValidPlayerName(target) then return end
    
    -- Don't send to self
    if target == Addon.runtime.playerFullName then return end
    
    QueueMessage(message, "WHISPER", target)
end

function Comm:SendToAllFriends(message)
    local friends = self:GetAllOnlineFriends()
    for _, fullName in ipairs(friends) do
        self:SendToPlayer(message, fullName)
    end
end

function Comm:BroadcastToAll(message)
    self:SendToGuild(message)
    self:SendToAllFriends(message)
end

-- =============================================================================
-- Status Broadcasting (with Debouncing)
-- =============================================================================

function Comm:BroadcastStatus()
    if not Addon.Database:IsRegistered() then return end
    
    -- Cancel any pending broadcast
    if state.pendingBroadcast then
        state.pendingBroadcast:Cancel()
        state.pendingBroadcast = nil
    end
    
    -- Check debounce
    local now = GetTime()
    local timeSinceLast = now - state.lastBroadcastTime
    
    if timeSinceLast < Addon.Constants.BROADCAST_DEBOUNCE then
        -- Schedule debounced broadcast
        local delay = Addon.Constants.BROADCAST_DEBOUNCE - timeSinceLast
        state.pendingBroadcast = C_Timer.NewTimer(delay, function()
            state.pendingBroadcast = nil
            Comm:DoBroadcastStatus()
        end)
    else
        self:DoBroadcastStatus()
    end
end

function Comm:DoBroadcastStatus()
    state.lastBroadcastTime = GetTime()
    local message = BuildStatusMessage()
    self:BroadcastToAll(message)
end

function Comm:BroadcastUnregister()
    self:BroadcastToAll("UNREGISTER")
end

-- =============================================================================
-- Query System (with Throttling)
-- =============================================================================

function Comm:ScheduleQuery()
    -- Debounce query scheduling
    if state.pendingQueryTimer then return end
    
    state.pendingQueryTimer = C_Timer.NewTimer(0.5, function()
        state.pendingQueryTimer = nil
        Comm:QueryAllPlayers()
    end)
end

function Comm:QueryAllPlayers()
    local now = GetTime()
    
    -- Query guild (with throttle)
    if now - state.lastGuildQueryTime >= Addon.Constants.QUERY_THROTTLE then
        self:SendToGuild("QUERY")
        state.lastGuildQueryTime = now
    end
    
    -- Query friends (with per-target throttle)
    local friends = self:GetAllOnlineFriends()
    for _, fullName in ipairs(friends) do
        self:QueryPlayer(fullName)
    end
end

function Comm:QueryPlayer(target)
    if not target or not Utils:IsValidPlayerName(target) then return end
    if target == Addon.runtime.playerFullName then return end
    
    local now = GetTime()
    local lastQuery = state.lastQueryTime[target] or 0
    
    -- Only query if enough time has passed
    if now - lastQuery >= Addon.Constants.QUERY_THROTTLE then
        self:SendToPlayer("QUERY", target)
        state.lastQueryTime[target] = now
    end
end

-- =============================================================================
-- Incoming Message Handling
-- =============================================================================

function Comm:HandleMessage(message, sender, channel)
    if not message or not sender then return end
    
    -- Validate sender
    if not Utils:IsValidPlayerName(sender) then return end
    
    -- Don't process own messages
    if sender == Addon.runtime.playerFullName then return end
    
    -- Parse message
    local parts = ParseMessage(message)
    if not parts or #parts == 0 then return end
    
    local command = parts[1]
    
    if command == "STATUS" then
        self:HandleStatusMessage(sender, parts)
    elseif command == "QUERY" then
        self:HandleQueryMessage(sender)
    elseif command == "UNREGISTER" then
        self:HandleUnregisterMessage(sender)
    end
end

function Comm:HandleStatusMessage(sender, parts)
    -- Parse status data
    local categoryStr = parts[2] or ""
    local roleStr = parts[3] or ""
    local ilvl = tonumber(parts[4]) or 0
    local rio = tonumber(parts[5]) or 0
    local class = parts[6] ~= "" and parts[6] or nil
    local keystone = parts[7] or "-"
    
    -- Parse categories and roles
    local categories = {}
    if categoryStr ~= "" then
        for cat in categoryStr:gmatch("[^,]+") do
            table.insert(categories, cat)
        end
    end
    
    local roles = {}
    if roleStr ~= "" then
        for role in roleStr:gmatch("[^,]+") do
            table.insert(roles, role)
        end
    end
    
    -- Build status object
    local status = {
        categories = categories,
        roles = roles,
        ilvl = ilvl,
        rio = rio,
        class = class,
        keystone = keystone,
    }
    
    -- Deduplication: check if status actually changed
    local newHash = Utils:HashStatus(status)
    local oldHash = state.recentStatusHashes[sender]
    
    if newHash == oldHash then
        -- Status unchanged, just update timestamp
        Addon.Members:RefreshTimestamp(sender)
        return
    end
    
    -- Store new hash
    state.recentStatusHashes[sender] = newHash
    
    -- Update member list
    if #categories > 0 then
        Addon.Members:UpdateMember(sender, status)
    else
        Addon.Members:RemoveMember(sender)
    end
end

function Comm:HandleQueryMessage(sender)
    -- Respond with our status if registered
    if Addon.Database:IsRegistered() then
        local message = BuildStatusMessage()
        self:SendToPlayer(message, sender)
    end
end

function Comm:HandleUnregisterMessage(sender)
    -- Remove player from member list
    Addon.Members:RemoveMember(sender)
    
    -- Clear their status hash
    state.recentStatusHashes[sender] = nil
end

-- =============================================================================
-- Friends List Helpers
-- =============================================================================

function Comm:GetOnlineFriends()
    local friends = {}
    local num = C_FriendList.GetNumOnlineFriends()
    if not num then return friends end
    
    for i = 1, num do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected then
            local fullName = info.name
            if info.realmName and info.realmName ~= "" then
                fullName = info.name .. "-" .. info.realmName
            end
            table.insert(friends, fullName)
        end
    end
    
    return friends
end

function Comm:GetOnlineBNFriends()
    local friends = {}
    local num = BNGetNumFriends()
    if not num then return friends end
    
    for i = 1, num do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
            local game = accountInfo.gameAccountInfo
            if game.clientProgram == "WoW" and game.characterName then
                local fullName = game.characterName
                if game.realmName and game.realmName ~= "" then
                    fullName = game.characterName .. "-" .. game.realmName
                end
                table.insert(friends, fullName)
            end
        end
    end
    
    return friends
end

function Comm:GetAllOnlineFriends()
    local friends = {}
    local seen = {}
    
    for _, name in ipairs(self:GetOnlineFriends()) do
        if not seen[name] then
            table.insert(friends, name)
            seen[name] = true
        end
    end
    
    for _, name in ipairs(self:GetOnlineBNFriends()) do
        if not seen[name] then
            table.insert(friends, name)
            seen[name] = true
        end
    end
    
    return friends
end

-- =============================================================================
-- Cleanup
-- =============================================================================

function Comm:ClearPlayerData(playerName)
    state.lastQueryTime[playerName] = nil
    state.recentStatusHashes[playerName] = nil
end
