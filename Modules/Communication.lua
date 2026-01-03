--[[
    SocialLFG - Communication Module
    Message protocol, throttling, queuing, and rate limiting
    
    This module handles all addon communication with:
    - Message queuing and rate limiting
    - Query throttling per target
    - Broadcast debouncing
    - Deduplication of incoming messages
    - Community (Club) support for same/connected realm members
    - BNet cross-realm communication for Battle.net friends
    
    COMMUNICATION CHANNELS:
    - GUILD: For guild members (uses SendAddonMessage with "GUILD" channel)
    - WHISPER: For same/connected realm friends and community members
    - BNET: For Battle.net friends (uses BNSendGameData, works cross-realm)
    
    LIMITATIONS:
    - Community members who are NOT on same/connected realm AND are NOT BNet friends
      cannot receive addon messages. This is a WoW API limitation.
    - The addon will still show these players in the member list if they broadcast
      to us (e.g., via guild or if they're in a community with shared BNet friends),
      but we cannot initiate communication with them directly.
]]

local Addon = _G.SocialLFG
local Utils = Addon.Utils
local L = _G.SocialLFG_L

-- NameUtils reference (set after initialization)
local NameUtils = nil

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
    -- Cache NameUtils reference
    NameUtils = Addon.NameUtils
    
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

-- Check if we can send an addon whisper to a target player
-- Returns true if the player is on the same or connected realm
function Comm:CanWhisperPlayer(target)
    if not target then return false end
    
    -- Extract realm from target name
    local targetRealm = nil
    if NameUtils then
        targetRealm = NameUtils:ExtractRealm(target)
    else
        local hyphenPos = target:find("-", 1, true)
        if hyphenPos then
            targetRealm = target:sub(hyphenPos + 1)
        end
    end
    
    if not targetRealm or targetRealm == "" then
        -- No realm means same realm
        return true
    end
    
    -- Get player's realm (normalized)
    local playerRealm = NameUtils and NameUtils:GetHomeRealm() or 
                        (Addon.runtime.playerRealm or GetRealmName()):gsub("%s+", "")
    
    -- Same realm check (case-insensitive)
    if targetRealm:lower() == playerRealm:lower() then
        return true
    end
    
    -- Connected realm check using GetAutoCompleteRealms
    local connectedRealms = GetAutoCompleteRealms and GetAutoCompleteRealms() or {}
    for _, connectedRealm in ipairs(connectedRealms) do
        if targetRealm:lower() == connectedRealm:lower() then
            return true
        end
    end
    
    return false
end

function Comm:SendToPlayer(message, target)
    if not target then return end
    
    -- Use NameUtils for validation if available
    local isValid = NameUtils and NameUtils:IsValidName(target) or Utils:IsValidPlayerName(target)
    if not isValid then return end
    
    -- Don't send to self
    if target == Addon.runtime.playerFullName then return end
    
    -- Normalize target name for consistency
    if NameUtils then
        target = NameUtils:ToCanonical(target) or target
    end
    
    -- Check if we can actually whisper this player
    if not self:CanWhisperPlayer(target) then
        return -- Silently skip cross-realm players we can't whisper
    end
    
    QueueMessage(message, "WHISPER", target)
end

function Comm:SendToAllFriends(message)
    -- Send to all reachable players (deduplicated)
    for _, playerInfo in ipairs(self:GetAllReachablePlayers()) do
        if playerInfo.method == "BNET" and playerInfo.gameAccountID then
            self:SendToBNetFriend(message, playerInfo.gameAccountID)
        elseif playerInfo.method == "WHISPER" then
            self:SendToPlayer(message, playerInfo.name)
        end
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
    
    -- Query all reachable players (unified, deduplicated)
    for _, playerInfo in ipairs(self:GetAllReachablePlayers()) do
        self:QueryPlayerByInfo(playerInfo)
    end
end

function Comm:QueryPlayerByInfo(playerInfo)
    if not playerInfo or not playerInfo.name then return end
    
    local now = GetTime()
    local lastQuery = state.lastQueryTime[playerInfo.name] or 0
    
    -- Only query if enough time has passed
    if now - lastQuery >= Addon.Constants.QUERY_THROTTLE then
        if playerInfo.method == "BNET" and playerInfo.gameAccountID then
            self:SendToBNetFriend("QUERY", playerInfo.gameAccountID)
        elseif playerInfo.method == "WHISPER" then
            self:SendToPlayer("QUERY", playerInfo.name)
        end
        state.lastQueryTime[playerInfo.name] = now
    end
end

function Comm:QueryPlayer(target)
    if not target then return end
    
    local isValid = NameUtils and NameUtils:IsValidName(target) or Utils:IsValidPlayerName(target)
    if not isValid then return end
    
    -- Normalize for comparison
    local normalizedTarget = NameUtils and NameUtils:ToCanonical(target) or target
    
    -- Check if this is self
    local isSelf = NameUtils and NameUtils:IsSamePlayer(target, Addon.runtime.playerFullName)
                   or target == Addon.runtime.playerFullName
    if isSelf then return end
    
    local now = GetTime()
    local lastQuery = state.lastQueryTime[normalizedTarget] or 0
    
    -- Only query if enough time has passed
    if now - lastQuery >= Addon.Constants.QUERY_THROTTLE then
        self:SendToPlayer("QUERY", normalizedTarget)
        state.lastQueryTime[normalizedTarget] = now
    end
end

-- =============================================================================
-- Incoming Message Handling
-- =============================================================================

function Comm:HandleMessage(message, sender, channel)
    if not message or not sender then return end
    
    -- Validate and normalize sender
    local isValid = NameUtils and NameUtils:IsValidName(sender) or Utils:IsValidPlayerName(sender)
    if not isValid then return end
    
    -- Normalize sender name for consistent storage
    if NameUtils then
        sender = NameUtils:ToCanonical(sender) or sender
    end
    
    -- Don't process own messages (compare canonical names)
    local isSelf = NameUtils and NameUtils:IsSamePlayer(sender, Addon.runtime.playerFullName)
                   or sender == Addon.runtime.playerFullName
    if isSelf then return end
    
    -- Parse message
    local parts = ParseMessage(message)
    if not parts or #parts == 0 then return end
    
    local command = parts[1]
    
    if command == "STATUS" then
        self:HandleStatusMessage(sender, parts)
    elseif command == "QUERY" then
        self:HandleQueryMessage(sender, channel)
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

function Comm:HandleQueryMessage(sender, channel)
    -- Respond with our status if registered
    if Addon.Database:IsRegistered() then
        local message = BuildStatusMessage()
        
        -- If we can whisper them directly, do so
        if self:CanWhisperPlayer(sender) then
            self:SendToPlayer(message, sender)
        else
            -- Check if they're a BNet friend and respond via BNet
            local gameAccountID = self:FindBNetGameAccountForPlayer(sender)
            if gameAccountID then
                self:SendToBNetFriend(message, gameAccountID)
            end
            -- If neither whisper nor BNet works, we can't respond (cross-realm non-friend)
        end
    end
end

-- Find the BNet game account ID for a given player name
function Comm:FindBNetGameAccountForPlayer(playerName)
    if not playerName then return nil end
    
    local num = BNGetNumFriends()
    if not num then return nil end
    
    for i = 1, num do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
            local game = accountInfo.gameAccountInfo
            if game.clientProgram == "WoW" and game.characterName then
                local fullName
                if NameUtils then
                    fullName = NameUtils:BuildFromBNetInfo(game)
                else
                    local realm = game.realmName or ""
                    if realm ~= "" then
                        fullName = game.characterName .. "-" .. realm:gsub("%s+", "")
                    else
                        local playerRealm = Addon.runtime.playerRealm or GetRealmName()
                        fullName = game.characterName .. "-" .. playerRealm:gsub("%s+", "")
                    end
                end
                
                -- Compare names (case-insensitive)
                if fullName and fullName:lower() == playerName:lower() then
                    return game.gameAccountID
                end
            end
        end
    end
    
    return nil
end

function Comm:HandleUnregisterMessage(sender)
    -- Remove player from member list
    Addon.Members:RemoveMember(sender)
    
    -- Clear their status hash
    state.recentStatusHashes[sender] = nil
end

-- =============================================================================
-- Player Data Retrieval (Unified & Deduplicated)
-- =============================================================================

-- Get online regular friends (same realm, always whisperable)
-- Returns array of names
function Comm:GetOnlineFriends()
    local friends = {}
    local num = C_FriendList.GetNumOnlineFriends()
    if not num then return friends end
    
    for i = 1, num do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected and info.name then
            local fullName
            
            if NameUtils then
                fullName = NameUtils:BuildFromFriendInfo(info.name, info.realmName)
            else
                if info.realmName and info.realmName ~= "" then
                    fullName = info.name .. "-" .. info.realmName
                else
                    local playerRealm = Addon.runtime.playerRealm or GetRealmName()
                    fullName = info.name .. "-" .. playerRealm:gsub("%s+", "")
                end
            end
            
            if fullName then
                table.insert(friends, fullName)
            end
        end
    end
    
    return friends
end

-- Get online BNet friends with their game account IDs
-- Returns array of { name, gameAccountID }
function Comm:GetOnlineBNFriends()
    local friends = {}
    local num = BNGetNumFriends()
    if not num then return friends end
    
    for i = 1, num do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
            local game = accountInfo.gameAccountInfo
            if game.clientProgram == "WoW" and game.characterName and game.gameAccountID then
                local fullName
                
                if NameUtils then
                    fullName = NameUtils:BuildFromBNetInfo(game)
                else
                    if game.realmName and game.realmName ~= "" then
                        fullName = game.characterName .. "-" .. game.realmName:gsub("%s+", "")
                    else
                        local playerRealm = Addon.runtime.playerRealm or GetRealmName()
                        fullName = game.characterName .. "-" .. playerRealm:gsub("%s+", "")
                    end
                end
                
                if fullName then
                    table.insert(friends, {
                        name = fullName,
                        gameAccountID = game.gameAccountID,
                    })
                end
            end
        end
    end
    
    return friends
end

-- Send message to a BNet friend using BNSendGameData (works cross-realm)
function Comm:SendToBNetFriend(message, gameAccountID)
    if not gameAccountID then return end
    if not BNSendGameData then return end
    
    BNSendGameData(gameAccountID, Addon.Constants.PREFIX, message)
end

-- Get online community members who are on same/connected realm (reachable via whisper)
-- Excludes those already seen (to avoid duplicating with friends/bnet friends)
-- Returns array of names
function Comm:GetOnlineCommunityMembers(excludeSet)
    local members = {}
    local seen = excludeSet or {}

    if not C_Club or not C_Club.GetSubscribedClubs then
        return members
    end

    local clubs = C_Club.GetSubscribedClubs() or {}
    local playerRealm = Addon.runtime.playerRealm or GetRealmName()
    local normalizedPlayerRealm = playerRealm:gsub("%s+", "")

    for _, club in ipairs(clubs) do
        local clubId = club.clubId
        -- Only process Character communities, not guilds (handled via GUILD channel) or BNet communities
        -- ClubType: 0=BattleNet, 1=Character (community), 2=Guild
        if clubId and club.clubType == Enum.ClubType.Character then
            local memberIds = C_Club.GetClubMembers(clubId) or {}

            for _, memberId in ipairs(memberIds) do
                local info = C_Club.GetMemberInfo(clubId, memberId)
                if info and not info.isSelf then
                    local isOnline = info.presence and (
                        info.presence == Enum.ClubMemberPresence.Online or
                        info.presence == Enum.ClubMemberPresence.OnlineMobile or
                        info.presence == Enum.ClubMemberPresence.Away or
                        info.presence == Enum.ClubMemberPresence.Busy
                    )

                    if isOnline and info.name then
                        -- Try to get realm from GUID
                        local realm = nil
                        if info.guid then
                            local _, _, _, memberRealm = GetPlayerInfoByGUID(info.guid)
                            if memberRealm and memberRealm ~= "" then
                                realm = memberRealm
                            end
                        end

                        local fullName
                        if NameUtils then
                            fullName = NameUtils:BuildFromFriendInfo(info.name, realm)
                        else
                            local normalizedRealm = realm and realm:gsub("%s+", "") or nil
                            if normalizedRealm and normalizedRealm ~= "" then
                                fullName = info.name .. "-" .. normalizedRealm
                            else
                                fullName = info.name .. "-" .. normalizedPlayerRealm
                            end
                        end

                        -- Only include if not already seen AND we can whisper them
                        if fullName and not seen[fullName] and self:CanWhisperPlayer(fullName) then
                            table.insert(members, fullName)
                            seen[fullName] = true
                        end
                    end
                end
            end
        end
    end

    return members
end

-- MAIN UNIFIED FUNCTION: Get all reachable online players
-- Returns array of { name = "Name-Realm", method = "WHISPER"|"BNET", gameAccountID = ... }
-- Each player appears only ONCE with their preferred communication method
function Comm:GetAllReachablePlayers()
    local players = {}
    local seen = {}
    
    -- 1. BNet friends first (highest priority - can reach cross-realm)
    for _, friendInfo in ipairs(self:GetOnlineBNFriends()) do
        if not seen[friendInfo.name] then
            table.insert(players, {
                name = friendInfo.name,
                method = "BNET",
                gameAccountID = friendInfo.gameAccountID,
            })
            seen[friendInfo.name] = true
        end
    end
    
    -- 2. Regular friends (same realm, whisperable)
    for _, name in ipairs(self:GetOnlineFriends()) do
        if not seen[name] then
            table.insert(players, {
                name = name,
                method = "WHISPER",
            })
            seen[name] = true
        end
    end
    
    -- 3. Community members (same/connected realm only, excluding already added)
    -- Pass seen set to avoid duplicates
    for _, name in ipairs(self:GetOnlineCommunityMembers(seen)) do
        if not seen[name] then
            table.insert(players, {
                name = name,
                method = "WHISPER",
            })
            seen[name] = true
        end
    end
    
    return players
end

-- For backward compatibility: returns just names of all reachable players
function Comm:GetAllOnlineFriends()
    local names = {}
    for _, info in ipairs(self:GetAllReachablePlayers()) do
        table.insert(names, info.name)
    end
    return names
end

-- =============================================================================
-- Cleanup
-- =============================================================================

function Comm:ClearPlayerData(playerName)
    state.lastQueryTime[playerName] = nil
    state.recentStatusHashes[playerName] = nil
end
