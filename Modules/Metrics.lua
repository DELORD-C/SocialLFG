--[[
    SocialLFG - Metrics Module
    Lightweight, opt-in metrics collection for measuring hotspots.
    Disabled by default (set Addon.Constants.METRICS_ENABLED = true to enable).
]]

local Addon = _G.SocialLFG
local Metrics = {}
Addon.Metrics = Metrics

function Metrics:Initialize()
    self.enabled = Addon.Constants.METRICS_ENABLED or false
    self.timers = {}
    self.stats = {}

    -- Register simple slash commands for quick control
    SLASH_SOCIALLFG_METRICS1 = "/slfgmetrics"
    SlashCmdList["SOCIALLFG_METRICS"] = function(msg)
        local cmd = (msg or ""):lower():match("^(%S*)") or ""
        if cmd == "" or cmd == "print" then
            self:Report()
        elseif cmd == "reset" then
            self:Reset()
            Addon:LogInfo("Metrics reset")
        elseif cmd == "enable" then
            self:Enable(true)
            Addon:LogInfo("Metrics enabled")
        elseif cmd == "disable" then
            self:Enable(false)
            Addon:LogInfo("Metrics disabled")
        else
            Addon:LogInfo("Usage: /slfgmetrics [print|reset|enable|disable]")
        end
    end
end

function Metrics:Enable(val)
    self.enabled = not not val
end

function Metrics:RecordStart(key)
    if not self.enabled then return end
    self.timers[key] = GetTime()
end

function Metrics:RecordEnd(key)
    if not self.enabled then return end
    local start = self.timers[key]
    if not start then return end
    local dt = GetTime() - start
    local s = self.stats[key] or {count = 0, total = 0, max = 0}
    s.count = s.count + 1
    s.total = s.total + dt
    if dt > s.max then s.max = dt end
    self.stats[key] = s
    self.timers[key] = nil
end

-- Measure a function call (optional wrapper)
function Metrics:Measure(key, func, ...)
    if not self.enabled then
        return func(...)
    end
    self:RecordStart(key)
    local ok, a, b, c = pcall(func, ...)
    self:RecordEnd(key)
    if not ok then error(a) end
    return a, b, c
end

function Metrics:Report()
    if not self.enabled then
        Addon:LogInfo("Metrics disabled")
        return
    end
    Addon:LogInfo("--- Metrics report ---")
    for key, s in pairs(self.stats) do
        local avg = s.total / math.max(s.count, 1)
        Addon:LogInfo(string.format("%s: count=%d avg=%.6f max=%.6f total=%.6f", key, s.count, avg, s.max, s.total))
    end
    Addon:LogInfo("--- End report ---")
end

function Metrics:Reset()
    self.timers = {}
    self.stats = {}
end

return Metrics
