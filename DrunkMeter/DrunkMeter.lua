-- DrunkMeter 0.6.2
-- Vanilla WoW / Lua 5.0 compatible.
--
-- Tracks estimated drunkenness from confirmed drink use, preserves partial
-- 10-second decay phase across sessions, and corrects drunk-distorted enemy levels.

DrunkMeter = {}
local DM = DrunkMeter

DM.VERSION = "0.6.2"
DM.MAX_VALUE = 256
DM.DRUNK_AT = 50
DM.SMASHED_AT = 90
DM.DECAY_SECONDS = 10

-- Geometry: 32 px outer body, 28 px usable interior, 2 px inset each side.
DM.OUTER_BAR_WIDTH = 32
DM.BAR_WIDTH = 28
DM.BAR_HEIGHT = 196
DM.BAR_INSET = 2
DM.LINE_HEIGHT = 2

DM.WARNING_SECONDS = 3
DM.PENDING_USE_TIMEOUT = 1.5
DM.NAMEPLATE_SCAN_SECONDS = 0.15
DM.OFFLINE_HISTORY_MAX = 20
DM.MAX_LOG_ENTRIES = 200
DM.DEBUG_TIMER_LOG_SECONDS = 5
DM.MAX_SANE_DELTA = 300
DM.SOLID_TEXTURE = "Interface\\ChatFrame\\ChatFrameBackground"
DM.BAR_TEXTURE = DM.SOLID_TEXTURE
DM.BAR_RED_R = 0.42
DM.BAR_RED_G = 0.015
DM.BAR_RED_B = 0.015

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function lower(s)
    if not s then return "" end
    return string.lower(s)
end

local function chat(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00DrunkMeter:|r " .. tostring(msg))
    end
end

local function timestamp()
    if type(date) == "function" then
        return date("%Y-%m-%d %H:%M:%S")
    end
    if type(GetTime) == "function" then
        return tostring(math.floor(GetTime()))
    end
    return "0"
end

local function itemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    if id then return tonumber(id) end
    return nil
end

local function itemNameFromLink(link)
    if type(link) ~= "string" then return "Unknown item" end
    local _, _, name = string.find(link, "%[(.-)%]")
    if name and name ~= "" then return name end
    return "Unknown item"
end

function DM:EnsureDB()
    if type(DrunkMeterDB) ~= "table" then DrunkMeterDB = {} end
    if type(DrunkMeterLog) ~= "table" then DrunkMeterLog = {} end

    if DrunkMeterDB.value == nil then DrunkMeterDB.value = 0 end
    if DrunkMeterDB.locked == nil then DrunkMeterDB.locked = false end
    if DrunkMeterDB.debug == nil then DrunkMeterDB.debug = false end
    if DrunkMeterDB.point == nil then DrunkMeterDB.point = "CENTER" end
    if DrunkMeterDB.relPoint == nil then DrunkMeterDB.relPoint = "CENTER" end
    if DrunkMeterDB.x == nil then DrunkMeterDB.x = 0 end
    if DrunkMeterDB.y == nil then DrunkMeterDB.y = -120 end
    if type(DrunkMeterDB.itemValues) ~= "table" then DrunkMeterDB.itemValues = {} end
    if DrunkMeterDB.totalDrinks == nil then DrunkMeterDB.totalDrinks = 0 end
    if DrunkMeterDB.totalGain == nil then DrunkMeterDB.totalGain = 0 end
    if DrunkMeterDB.lastGain == nil then DrunkMeterDB.lastGain = 0 end
    if DrunkMeterDB.lastDrinkName == nil then DrunkMeterDB.lastDrinkName = "" end
    if DrunkMeterDB.lastDrinkTime == nil then DrunkMeterDB.lastDrinkTime = 0 end
    if type(DrunkMeterDB.offlineHistory) ~= "table" then DrunkMeterDB.offlineHistory = {} end

    DrunkMeterDB.value = clamp(tonumber(DrunkMeterDB.value) or 0, 0, self.MAX_VALUE)
end

function DM:TrimList(list, maxEntries)
    if type(list) ~= "table" then return end
    maxEntries = tonumber(maxEntries) or 0
    if maxEntries < 1 then return end
    while table.getn(list) > maxEntries do
        table.remove(list, 1)
    end
end

function DM:Log(text)
    if type(DrunkMeterLog) ~= "table" then DrunkMeterLog = {} end
    table.insert(DrunkMeterLog, timestamp() .. " | " .. text)
    self:TrimList(DrunkMeterLog, self.MAX_LOG_ENTRIES)
    if DrunkMeterDB and DrunkMeterDB.debug then
        chat(text)
    end
end

function DM:GetEpochTime()
    if type(time) ~= "function" then return nil end
    local ok, value = pcall(time)
    if ok and tonumber(value) then return tonumber(value) end
    return nil
end

function DM:GetServerClock()
    if type(GetGameTime) ~= "function" then return nil, nil end
    local ok, hour, minute = pcall(GetGameTime)
    if not ok then return nil, nil end
    return tonumber(hour), tonumber(minute)
end

function DM:NormalisePhase(phase)
    phase = tonumber(phase) or 0
    if phase < 0 then phase = 0 end
    if phase >= self.DECAY_SECONDS then
        phase = phase - math.floor(phase / self.DECAY_SECONDS) * self.DECAY_SECONDS
    end
    return phase
end

function DM:ResetDecayPhase(reason)
    local before = tonumber(self.decayElapsed) or 0
    self.decayElapsed = 0
    self.warningState = nil
    if DrunkMeterDB and DrunkMeterDB.debug then
        self:Log("timer reset | reason=" .. tostring(reason or "unspecified")
            .. " | phase=" .. string.format("%.3f", before) .. " -> 0")
    end
end

function DM:SaveOfflineSnapshot(reason, addHistory)
    self:EnsureDB()
    local epoch = self:GetEpochTime()
    if not epoch then return false end

    local phase = self:NormalisePhase(self.decayElapsed)
    local serverHour, serverMinute = self:GetServerClock()
    local entry = {
        epoch = epoch,
        value = clamp(tonumber(DrunkMeterDB.value) or 0, 0, self.MAX_VALUE),
        decayElapsed = phase,
        reason = tostring(reason or "snapshot"),
        serverHour = serverHour,
        serverMinute = serverMinute
    }

    DrunkMeterDB.offlineSnapshot = entry

    if addHistory then
        table.insert(DrunkMeterDB.offlineHistory, {
            epoch = entry.epoch,
            value = entry.value,
            decayElapsed = entry.decayElapsed,
            reason = entry.reason,
            serverHour = entry.serverHour,
            serverMinute = entry.serverMinute
        })
        self:TrimList(DrunkMeterDB.offlineHistory, self.OFFLINE_HISTORY_MAX)
    end

    return true
end

function DM:FormatDuration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 0 then seconds = 0 end
    local minutes = math.floor(seconds / 60)
    local secs = seconds - minutes * 60
    local hours = math.floor(minutes / 60)
    minutes = minutes - hours * 60
    if hours > 0 then
        return hours .. "h " .. minutes .. "m " .. secs .. "s"
    end
    if minutes > 0 then
        return minutes .. "m " .. secs .. "s"
    end
    return secs .. "s"
end

function DM:RestoreOfflineDecay()
    if self.offlineRecoveryApplied then return end
    self.offlineRecoveryApplied = true

    self:EnsureDB()
    self.decayElapsed = 0

    local snap = DrunkMeterDB.offlineSnapshot
    if type(snap) ~= "table" then
        self:Log("offline recovery | no snapshot | phase=0")
        return
    end

    local savedEpoch = tonumber(snap.epoch)
    local savedValue = tonumber(snap.value)
    local now = self:GetEpochTime()
    if not savedEpoch or not savedValue or not now then
        self:Log("offline recovery | incomplete snapshot/time data")
        return
    end

    savedValue = clamp(savedValue, 0, self.MAX_VALUE)
    local savedPhase = self:NormalisePhase(snap.decayElapsed)
    local offlineSeconds = math.floor(now - savedEpoch)

    if offlineSeconds < 0 then
        DrunkMeterDB.value = savedValue
        self.decayElapsed = savedPhase
        self:Log("offline recovery | clock moved backwards=" .. math.abs(offlineSeconds)
            .. "s | before=" .. savedValue
            .. " | after=" .. savedValue
            .. " | phase=" .. string.format("%.2f", savedPhase))
        return
    end

    local totalElapsed = savedPhase + offlineSeconds
    local ticks = math.floor(totalElapsed / self.DECAY_SECONDS)
    local after = savedValue - ticks
    if after < 0 then after = 0 end

    local remainingPhase = totalElapsed - ticks * self.DECAY_SECONDS
    if after <= 0 then remainingPhase = 0 end

    DrunkMeterDB.value = after
    self.decayElapsed = remainingPhase
    DrunkMeterDB.lastOfflineSeconds = offlineSeconds
    DrunkMeterDB.lastOfflineBefore = savedValue
    DrunkMeterDB.lastOfflineAfter = after
    DrunkMeterDB.lastOfflineTicks = ticks

    if offlineSeconds > 0 then
        table.insert(DrunkMeterDB.offlineHistory, {
            epoch = now,
            value = after,
            decayElapsed = remainingPhase,
            reason = "login-recovery",
            offlineSeconds = offlineSeconds,
            before = savedValue,
            ticks = ticks
        })
        self:TrimList(DrunkMeterDB.offlineHistory, self.OFFLINE_HISTORY_MAX)
    end

    self:Log("offline recovery | before=" .. math.floor(savedValue + 0.5)
        .. " | offline=" .. offlineSeconds .. "s"
        .. " | ticks=" .. ticks
        .. " | after=" .. math.floor(after + 0.5)
        .. " | phase=" .. string.format("%.2f", remainingPhase))

    if ticks > 0 and savedValue > after then
        chat("offline " .. self:FormatDuration(offlineSeconds) .. " | estimated "
            .. math.floor(savedValue + 0.5) .. " -> " .. math.floor(after + 0.5))
    end
end

function DM:GetState(v)
    v = tonumber(v) or 0
    if v <= 0 then return "SOBER" end
    if v < self.DRUNK_AT then return "TIPSY" end
    if v < self.SMASHED_AT then return "DRUNK" end
    return "SMASHED"
end

-- Preserve the established visual scaling: 0..SMASHED uses the lower half,
-- then SMASHED..MAX uses the upper half.
function DM:GetVisualFraction(v)
    v = clamp(tonumber(v) or 0, 0, self.MAX_VALUE)
    if v <= 0 then return 0 end
    if v <= self.SMASHED_AT then
        return 0.5 * (v / self.SMASHED_AT)
    end
    return 0.5 + 0.5 * ((v - self.SMASHED_AT) / (self.MAX_VALUE - self.SMASHED_AT))
end

function DM:GetVisualOffset(v)
    return self:GetVisualFraction(v) * self.BAR_HEIGHT
end

function DM:GetLineY(y)
    local half = self.LINE_HEIGHT / 2
    return clamp(tonumber(y) or half, half, self.BAR_HEIGHT - half)
end

function DM:UpdateBar()
    if not self.bar or not DrunkMeterDB then return end

    local v = clamp(tonumber(DrunkMeterDB.value) or 0, 0, self.MAX_VALUE)
    local visual = self:GetVisualOffset(v)
    self.bar:SetValue(visual)
    self.valueText:SetText(math.floor(v + 0.5) .. "/" .. self.MAX_VALUE)

    local state = self:GetState(v)
    if self.stateText then
        self.stateText:SetText(state)
        if state == "SMASHED" then
            self.stateText:SetTextColor(1.0, 0.38, 0.18)
        elseif state == "DRUNK" then
            self.stateText:SetTextColor(1.0, 0.62, 0.18)
        elseif state == "TIPSY" then
            self.stateText:SetTextColor(1.0, 0.82, 0.28)
        else
            self.stateText:SetTextColor(0.92, 0.88, 0.76)
        end
    end

    self.bar:SetStatusBarColor(self.BAR_RED_R, self.BAR_RED_G, self.BAR_RED_B)
    self:UpdateDecayTicker()
end

function DM:SetValue(v, reason)
    self:EnsureDB()
    local old = DrunkMeterDB.value
    local oldState = self:GetState(old)
    local new = clamp(tonumber(v) or 0, 0, self.MAX_VALUE)
    DrunkMeterDB.value = new
    self:UpdateBar()
    if self.initialized then self:SaveOfflineSnapshot(reason or "set-value", true) end
    if self.initialized then self:RefreshLevelDisplays() end

    local newState = self:GetState(new)
    if oldState ~= newState then
        self:Log("state " .. oldState .. " -> " .. newState .. " at " .. math.floor(new + 0.5) .. "/" .. self.MAX_VALUE)
    end

    if reason and DrunkMeterDB.debug then
        chat(reason .. ": " .. math.floor(old + 0.5) .. " -> " .. math.floor(new + 0.5))
    end
end

function DM:DetectAlcoholText(text)
    local s = lower(text)
    if s == "" then return nil end

    if string.find(s, "extremely potent alcoholic beverage", 1, true) then return 50 end
    if string.find(s, "strong alcoholic beverage", 1, true) then return 20 end
    if string.find(s, "fairly weak alcoholic beverage", 1, true) then return 5 end
    if string.find(s, "typical alcoholic beverage", 1, true) then return 10 end

    return nil
end

function DM:ReadTooltipAlcohol(tip)
    if not tip or not tip.GetName then return nil end
    local tipName = tip:GetName()
    if not tipName then return nil end

    local i
    for i = 1, 30 do
        local left = getglobal(tipName .. "TextLeft" .. i)
        if left and left.GetText then
            local text = left:GetText()
            local value = self:DetectAlcoholText(text)
            if value then return value end
        end

        local right = getglobal(tipName .. "TextRight" .. i)
        if right and right.GetText then
            local text = right:GetText()
            local value = self:DetectAlcoholText(text)
            if value then return value end
        end
    end

    return nil
end

function DM:CacheItemValue(itemId, value)
    if not itemId or not value then return end
    self:EnsureDB()
    DrunkMeterDB.itemValues[itemId] = value
end

function DM:GetCachedItemValue(itemId)
    if not itemId then return nil end
    self:EnsureDB()
    return tonumber(DrunkMeterDB.itemValues[itemId])
end

function DM:PrepareScanner()
    if self.scan then return end
    self.scan = CreateFrame("GameTooltip", "DrunkMeterScanTooltip", UIParent, "GameTooltipTemplate")
    self.scan:SetOwner(UIParent, "ANCHOR_NONE")
end

function DM:ScanBagItem(bag, slot)
    self:PrepareScanner()
    local link = GetContainerItemLink(bag, slot)
    if not link then return nil, nil, nil end

    local itemId = itemIdFromLink(link)
    local cached = self:GetCachedItemValue(itemId)
    if cached then
        return cached, itemNameFromLink(link), itemId
    end

    self.scan:ClearLines()
    self.scan:SetOwner(UIParent, "ANCHOR_NONE")

    local ok = pcall(self.scan.SetBagItem, self.scan, bag, slot)
    if not ok then
        self.scan:Hide()
        return nil, itemNameFromLink(link), itemId
    end

    local value = self:ReadTooltipAlcohol(self.scan)
    self.scan:Hide()

    if value then self:CacheItemValue(itemId, value) end
    return value, itemNameFromLink(link), itemId
end

function DM:ScanAction(slot)
    self:PrepareScanner()
    if not self.scan.SetAction then return nil, nil end

    self.scan:ClearLines()
    self.scan:SetOwner(UIParent, "ANCHOR_NONE")

    local ok = pcall(self.scan.SetAction, self.scan, slot)
    if not ok then
        self.scan:Hide()
        return nil, nil
    end

    local value = self:ReadTooltipAlcohol(self.scan)
    local first = getglobal("DrunkMeterScanTooltipTextLeft1")
    local name = first and first:GetText() or "Action " .. tostring(slot)
    self.scan:Hide()
    return value, name
end

function DM:CountItemById(itemId)
    if not itemId then return nil end
    local total = 0
    local bag, slot
    for bag = 0, 4 do
        local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link and itemIdFromLink(link) == itemId then
                local _, count = GetContainerItemInfo(bag, slot)
                total = total + (tonumber(count) or 1)
            end
        end
    end
    return total
end

function DM:CountItemByName(name)
    if not name or name == "" then return nil end
    local total = 0
    local found = false
    local bag, slot
    for bag = 0, 4 do
        local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link and itemNameFromLink(link) == name then
                local _, count = GetContainerItemInfo(bag, slot)
                total = total + (tonumber(count) or 1)
                found = true
            end
        end
    end
    if not found then return 0 end
    return total
end

function DM:QueuePendingDrink(value, name, source, itemId, countBefore)
    if not value or countBefore == nil then return end
    self.pendingDrink = {
        value = value,
        name = name or "Unknown drink",
        source = source or "unknown",
        itemId = itemId,
        countBefore = countBefore,
        queuedAt = GetTime()
    }
end

function DM:ConfirmPendingDrink()
    local p = self.pendingDrink
    if not p then return end

    if GetTime() - (p.queuedAt or 0) > self.PENDING_USE_TIMEOUT then
        self.pendingDrink = nil
        return
    end

    local current
    if p.itemId then
        current = self:CountItemById(p.itemId)
    else
        current = self:CountItemByName(p.name)
    end

    if current ~= nil and current < (p.countBefore or 0) then
        self.pendingDrink = nil
        self:ApplyDrink(p.value, p.name, p.source .. "-confirmed")
    end
end

function DM:IsDuplicateUse(name, value)
    local now = GetTime()
    if self.lastUseTime and self.lastUseName == name and self.lastUseValue == value then
        if now - self.lastUseTime < 0.40 then
            return true
        end
    end
    self.lastUseTime = now
    self.lastUseName = name
    self.lastUseValue = value
    return false
end

function DM:ApplyDrink(value, name, source)
    if not value then return end
    name = name or "Unknown drink"
    source = source or "unknown"

    if self:IsDuplicateUse(name, value) then return end

    self:EnsureDB()
    local before = DrunkMeterDB.value
    local after = clamp(before + value, 0, self.MAX_VALUE)
    DrunkMeterDB.value = after
    DrunkMeterDB.totalDrinks = (tonumber(DrunkMeterDB.totalDrinks) or 0) + 1
    DrunkMeterDB.totalGain = (tonumber(DrunkMeterDB.totalGain) or 0) + value
    DrunkMeterDB.lastGain = value
    DrunkMeterDB.lastDrinkName = name
    DrunkMeterDB.lastDrinkTime = GetTime()
    self.warningState = nil
    self:UpdateBar()
    if self.initialized then
        self:RefreshLevelDisplays()
        self:SaveOfflineSnapshot("drink", true)
    end

    self:Log("drink | " .. name .. " | +" .. value .. " | " .. math.floor(before + 0.5)
        .. " -> " .. math.floor(after + 0.5) .. " | phase="
        .. string.format("%.2f", tonumber(self.decayElapsed) or 0) .. " | source=" .. source)

    local oldState = self:GetState(before)
    local newState = self:GetState(after)
    if oldState ~= newState then
        self:Log("state " .. oldState .. " -> " .. newState .. " at " .. math.floor(after + 0.5) .. "/" .. self.MAX_VALUE)
    end
end

function DM:ObserveBagUse(bag, slot)
    if not self.initialized then return end
    local value, name, itemId = self:ScanBagItem(bag, slot)
    if value and itemId then
        self:QueuePendingDrink(value, name, "bag", itemId, self:CountItemById(itemId))
    end
end

function DM:ObserveActionUse(slot)
    if not self.initialized then return end
    local value, name = self:ScanAction(slot)
    if value and name then
        self:QueuePendingDrink(value, name, "action", nil, self:CountItemByName(name))
    end
end

function DM:AddBagTooltip(bag, slot)
    if not self.initialized then return end
    local link = GetContainerItemLink(bag, slot)
    if not link then return end

    local itemId = itemIdFromLink(link)
    local value = self:GetCachedItemValue(itemId)

    if not value then
        value = self:ReadTooltipAlcohol(GameTooltip)
        if value then self:CacheItemValue(itemId, value) end
    end

    if value then
        GameTooltip:AddLine("Drunk value: +" .. value .. " / " .. self.MAX_VALUE, 1.0, 0.82, 0.15)
        GameTooltip:Show()
    end
end

function DM:DecayOne()
    self:EnsureDB()
    if DrunkMeterDB.value <= 0 then return end

    local before = DrunkMeterDB.value
    local after = clamp(before - 1, 0, self.MAX_VALUE)
    DrunkMeterDB.value = after
    self:UpdateBar()
    if self.initialized then
        self:RefreshLevelDisplays()
        self:SaveOfflineSnapshot("decay", true)
    end
    self:Log("decay tick | -1 | " .. math.floor(before + 0.5) .. " -> " .. math.floor(after + 0.5)
        .. " | next-phase=" .. string.format("%.3f", tonumber(self.decayElapsed) or 0))

    local oldState = self:GetState(before)
    local newState = self:GetState(after)
    if oldState ~= newState then
        self:Log("state " .. oldState .. " -> " .. newState .. " at " .. math.floor(after + 0.5) .. "/" .. self.MAX_VALUE)
    end
end

-- WoW deliberately lowers the apparent level of hostile units while drunk.
-- DrunkMeter restores the displayed/API level using the same intoxication bands.
function DM:GetEnemyLevelCorrection(v)
    v = tonumber(v or (DrunkMeterDB and DrunkMeterDB.value) or 0) or 0
    if v <= 0 then return 0 end
    if v < 25 then return 1 end
    if v < self.DRUNK_AT then return 2 end
    if v < 70 then return 3 end
    if v < self.SMASHED_AT then return 4 end
    return 5
end

function DM:IsHostileUnit(unit)
    if not unit or unit == "player" then return false end

    if type(UnitCanAttack) == "function" then
        local ok, hostile = pcall(UnitCanAttack, "player", unit)
        if ok and hostile then return true end
    end

    if type(UnitReaction) == "function" then
        local ok, reaction = pcall(UnitReaction, unit, "player")
        if ok and reaction and reaction <= 4 then return true end
    end

    return false
end

function DM:InstallTrueLevelHook()
    if self.trueLevelHookInstalled then return end
    if type(UnitLevel) ~= "function" then return end

    self.trueLevelHookInstalled = true
    self.originalUnitLevel = UnitLevel

    UnitLevel = function(unit)
        local level = DM.originalUnitLevel(unit)
        if not DM.initialized or not level or level <= 0 then
            return level
        end

        local correction = DM:GetEnemyLevelCorrection()
        if correction > 0 and DM:IsHostileUnit(unit) then
            return level + correction
        end

        return level
    end
end

function DM:IsFontStringObject(obj)
    if not obj then return false end
    if obj.GetObjectType then
        local ok, kind = pcall(obj.GetObjectType, obj)
        if ok and kind == "FontString" then return true end
    end
    return type(obj.GetText) == "function" and type(obj.SetText) == "function"
end

function DM:IsStatusBarObject(obj)
    if not obj then return false end
    if obj.GetObjectType then
        local ok, kind = pcall(obj.GetObjectType, obj)
        if ok and kind == "StatusBar" then return true end
    end
    return type(obj.GetStatusBarColor) == "function" and type(obj.GetValue) == "function"
end

function DM:GetFrameFontStrings(frame)
    local out = {}
    local seen = {}
    if not frame then return out end

    local function addRegions(owner)
        if not owner or not owner.GetRegions then return end
        local regions = { owner:GetRegions() }
        local i
        for i = 1, table.getn(regions) do
            local region = regions[i]
            if region and not seen[region] and DM:IsFontStringObject(region) then
                seen[region] = true
                table.insert(out, region)
            end
        end
    end

    addRegions(frame)
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        local i
        for i = 1, table.getn(children) do
            addRegions(children[i])
        end
    end
    return out
end

function DM:FindNameplateHealthBar(frame)
    if not frame then return nil end
    if self:IsStatusBarObject(frame) then
        local width = 0
        if frame.GetWidth then width = tonumber(frame:GetWidth()) or 0 end
        if width >= 45 then return frame end
    end
    if not frame.GetChildren then return nil end
    local children = { frame:GetChildren() }
    local i
    for i = 1, table.getn(children) do
        local child = children[i]
        if self:IsStatusBarObject(child) then
            local width = 0
            if child.GetWidth then width = tonumber(child:GetWidth()) or 0 end
            if width >= 45 then return child end
        end
    end
    return nil
end

function DM:GetNameplateName(frame)
    local fonts = self:GetFrameFontStrings(frame)
    local best = nil
    local bestLen = 0
    local i
    for i = 1, table.getn(fonts) do
        local text = fonts[i]:GetText()
        if type(text) == "string" and text ~= "" then
            local _, _, onlyNumber = string.find(text, "^%s*(%d+)%s*$")
            if not onlyNumber and text ~= "??" then
                local n = string.len(text)
                if n > bestLen and n <= 80 then
                    best = text
                    bestLen = n
                end
            end
        end
    end
    return best
end

function DM:IsEnemyNameplate(frame, healthBar)
    local plateName = self:GetNameplateName(frame)
    local units = { "target", "mouseover" }
    local i
    for i = 1, table.getn(units) do
        local unit = units[i]
        if type(UnitExists) == "function" and UnitExists(unit) and type(UnitName) == "function" then
            local unitName = UnitName(unit)
            if plateName and unitName and plateName == unitName then
                return self:IsHostileUnit(unit)
            end
        end
    end

    if not healthBar or not healthBar.GetStatusBarColor then return false end
    local r, g, b = healthBar:GetStatusBarColor()
    r = tonumber(r) or 0
    g = tonumber(g) or 0
    b = tonumber(b) or 0

    if r >= 0.62 and b <= 0.45 then
        if g <= 0.48 then return true end
        if r >= 0.78 and g >= 0.48 then return true end
    end
    return false
end

function DM:ParseNameplateLevelText(text)
    if type(text) ~= "string" then return nil end

    local _, _, prefix, digits, suffix = string.find(text, "^(%s*)(%d+)(%s*)$")
    if digits then
        return tonumber(digits), prefix or "", suffix or "", false
    end

    local _, _, p2, d2, s2 = string.find(text, "^(.-)(%d+)(.-)$")
    if not d2 then return nil end
    local lp = lower(p2)
    if string.find(lp, "level", 1, true)
        or string.find(lp, "lvl", 1, true)
        or string.find(lp, "lv", 1, true) then
        return tonumber(d2), p2 or "", s2 or "", true
    end

    return nil
end

function DM:GetRawPlayerLevel()
    local fn = self.originalUnitLevel or UnitLevel
    if type(fn) ~= "function" then return 60 end
    local ok, level = pcall(fn, "player")
    if ok and tonumber(level) and tonumber(level) > 0 then
        return tonumber(level)
    end
    return 60
end

function DM:RestoreNameplateFrame(frame)
    if not self.nameplateFrameFonts or not self.nameplateFrameFonts[frame] then return end
    local list = self.nameplateFrameFonts[frame]
    local i
    for i = 1, table.getn(list) do
        local font = list[i]
        local entry = self.nameplateFontCache and self.nameplateFontCache[font]
        if entry and font and font.GetText and font.SetText then
            local current = font:GetText()
            if current == entry.renderedText then
                font:SetText(entry.rawText)
            end
            self.nameplateFontCache[font] = nil
        end
    end
    self.nameplateFrameFonts[frame] = nil
end

function DM:ApplyNameplateLevelFont(frame, font, rawText, rawLevel, prefix, suffix, correction)
    if not font or not rawLevel then return end
    self.nameplateFontCache = self.nameplateFontCache or {}
    self.nameplateFrameFonts = self.nameplateFrameFonts or {}

    local rendered = (prefix or "") .. tostring(rawLevel + correction) .. (suffix or "")
    font:SetText(rendered)
    self.nameplateFontCache[font] = {
        frame = frame,
        rawText = rawText,
        rawLevel = rawLevel,
        prefix = prefix or "",
        suffix = suffix or "",
        renderedText = rendered
    }

    if not self.nameplateFrameFonts[frame] then self.nameplateFrameFonts[frame] = {} end
    local list = self.nameplateFrameFonts[frame]
    local i
    for i = 1, table.getn(list) do
        if list[i] == font then return end
    end
    table.insert(list, font)
end

function DM:CorrectNameplateFrame(frame, correction)
    if correction <= 0 then
        self:RestoreNameplateFrame(frame)
        return
    end

    self.nameplateFontCache = self.nameplateFontCache or {}
    self.nameplateFrameFonts = self.nameplateFrameFonts or {}

    local existing = self.nameplateFrameFonts[frame]
    if existing then
        local i
        for i = 1, table.getn(existing) do
            local font = existing[i]
            local entry = self.nameplateFontCache[font]
            if entry and font and font.GetText and font.SetText then
                local current = font:GetText()
                if current == entry.renderedText or current == entry.rawText then
                    local rendered = entry.prefix .. tostring(entry.rawLevel + correction) .. entry.suffix
                    font:SetText(rendered)
                    entry.renderedText = rendered
                    return
                end
            end
        end
        self:RestoreNameplateFrame(frame)
    end

    local fonts = self:GetFrameFontStrings(frame)
    local playerLevel = self:GetRawPlayerLevel()
    local pureLimit = playerLevel + 10
    if pureLimit < 10 then pureLimit = 10 end
    if pureLimit > 255 then pureLimit = 255 end

    local bestFont, bestText, bestLevel, bestPrefix, bestSuffix
    local bestExplicit = false
    local i
    for i = 1, table.getn(fonts) do
        local font = fonts[i]
        local text = font:GetText()
        local level, prefix, suffix, explicit = self:ParseNameplateLevelText(text)
        if level and level > 0 and level <= 255 then
            local plausible = explicit or level <= pureLimit
            if plausible then
                if explicit and not bestExplicit then
                    bestFont, bestText, bestLevel = font, text, level
                    bestPrefix, bestSuffix, bestExplicit = prefix, suffix, true
                elseif explicit == bestExplicit then
                    if not bestLevel or level < bestLevel then
                        bestFont, bestText, bestLevel = font, text, level
                        bestPrefix, bestSuffix = prefix, suffix
                    end
                end
            end
        end
    end

    if bestFont then
        self:ApplyNameplateLevelFont(frame, bestFont, bestText, bestLevel, bestPrefix, bestSuffix, correction)
    end
end

function DM:RestoreAllNameplateLevels()
    if not self.nameplateFrameFonts then return end
    local frames = {}
    local frame
    for frame in pairs(self.nameplateFrameFonts) do
        table.insert(frames, frame)
    end
    local i
    for i = 1, table.getn(frames) do
        self:RestoreNameplateFrame(frames[i])
    end
end

function DM:RefreshNameplateLevels()
    local correction = self:GetEnemyLevelCorrection()
    if correction <= 0 then
        self:RestoreAllNameplateLevels()
        return
    end
    if not WorldFrame or not WorldFrame.GetChildren then return end

    local frames = { WorldFrame:GetChildren() }
    local i
    for i = 1, table.getn(frames) do
        local frame = frames[i]
        if frame and frame ~= self.frame and frame.IsShown then
            if frame:IsShown() then
                local healthBar = self:FindNameplateHealthBar(frame)
                if healthBar and self:IsEnemyNameplate(frame, healthBar) then
                    self:CorrectNameplateFrame(frame, correction)
                else
                    self:RestoreNameplateFrame(frame)
                end
            else
                self:RestoreNameplateFrame(frame)
            end
        end
    end
end

-- Optional nameplate work is failure-isolated and can never gate the decay scheduler.
function DM:SafeRefreshNameplateLevels()
    if self.nameplateCorrectionDisabled then return end
    local ok, err = pcall(self.RefreshNameplateLevels, self)
    if not ok then
        self.nameplateCorrectionDisabled = true
        self:Log("nameplate correction disabled for session | " .. tostring(err))
        if DrunkMeterDB and DrunkMeterDB.debug then
            chat("nameplate correction disabled after a client UI error; meter tracking continues")
        end
    end
end

function DM:SafeRestoreNameplateLevels()
    if not self.nameplateFrameFonts then return end
    local ok, err = pcall(self.RestoreAllNameplateLevels, self)
    if not ok and not self.nameplateRestoreErrorLogged then
        self.nameplateRestoreErrorLogged = true
        self:Log("nameplate restore error | " .. tostring(err))
    end
end

function DM:RefreshLevelDisplays()
    if type(TargetFrame_Update) == "function" then
        pcall(TargetFrame_Update)
    elseif type(TargetFrame_UpdateLevel) == "function" then
        pcall(TargetFrame_UpdateLevel)
    end
    self:SafeRefreshNameplateLevels()
end

function DM:SavePosition()
    if not self.frame or not DrunkMeterDB then return end
    local point, _, relPoint, x, y = self.frame:GetPoint()
    if point then DrunkMeterDB.point = point end
    if relPoint then DrunkMeterDB.relPoint = relPoint end
    DrunkMeterDB.x = x or 0
    DrunkMeterDB.y = y or 0
end

function DM:ApplyPosition()
    self:EnsureDB()
    self.frame:ClearAllPoints()
    self.frame:SetPoint(DrunkMeterDB.point, UIParent, DrunkMeterDB.relPoint, DrunkMeterDB.x, DrunkMeterDB.y)
end

function DM:CreateSolidTexture(parent, layer, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer or "OVERLAY")
    tex:SetTexture(self.SOLID_TEXTURE)
    tex:SetVertexColor(r or 1, g or 1, b or 1)
    tex:SetAlpha(a or 1)
    return tex
end

function DM:CreateTickAtValue(v, r, g, b)
    local y = self:GetLineY(self:GetVisualOffset(v))
    local tick = self:CreateSolidTexture(self.bar, "OVERLAY", r or 0.62, g or 0.62, b or 0.62, 1)
    tick:SetWidth(self.BAR_WIDTH)
    tick:SetHeight(self.LINE_HEIGHT)
    tick:SetPoint("CENTER", self.bar, "BOTTOM", 0, y)
    return tick
end

function DM:PlayThresholdWarning(state)
    if type(PlaySound) ~= "function" then return end
    if state == "SMASHED" then
        pcall(PlaySound, "RaidWarning")
    elseif state == "DRUNK" then
        pcall(PlaySound, "TellMessage")
    elseif state == "TIPSY" then
        pcall(PlaySound, "igMainMenuOptionCheckBoxOn")
    end
end

function DM:UpdateThresholdWarning()
    local v = tonumber(DrunkMeterDB and DrunkMeterDB.value) or 0
    local remaining = self.DECAY_SECONDS - (tonumber(self.decayElapsed) or 0)
    local state = nil

    if v == self.SMASHED_AT then
        state = "SMASHED"
    elseif v == self.DRUNK_AT then
        state = "DRUNK"
    elseif v == 1 then
        state = "TIPSY"
    end

    if not state or remaining > self.WARNING_SECONDS then
        if self.warningState ~= state then self.warningState = nil end
        return
    end

    if self.warningState ~= state then
        self.warningState = state
        self:PlayThresholdWarning(state)
        self:Log("warning | " .. state .. " expires in " .. math.ceil(remaining) .. "s")
    end
end

function DM:UpdateDecayTicker()
    if not self.decayLine then return end

    local v = tonumber(DrunkMeterDB and DrunkMeterDB.value) or 0
    if v <= 0 then
        self.decayLine:Hide()
        return
    end

    local progress = self:NormalisePhase(self.decayElapsed) / self.DECAY_SECONDS
    progress = clamp(progress, 0, 1)

    -- Independent of fill height: one 10-second phase sweeps the complete interior.
    local half = self.LINE_HEIGHT / 2
    local travel = self.BAR_HEIGHT - self.LINE_HEIGHT
    local y = half + travel * (1 - progress)

    self.decayLine:ClearAllPoints()
    self.decayLine:SetPoint("CENTER", self.bar, "BOTTOM", 0, y)
    self.decayLine:Show()
end

function DM:ShowTrackingTooltip()
    if not GameTooltip or not self.frame then return end
    self:EnsureDB()

    GameTooltip:SetOwner(self.frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("DrunkMeter " .. self.VERSION, 1.0, 0.82, 0.28)
    GameTooltip:AddDoubleLine("Current", math.floor(DrunkMeterDB.value + 0.5) .. " / " .. self.MAX_VALUE, 0.9, 0.9, 0.9, 1.0, 0.94, 0.78)
    GameTooltip:AddDoubleLine("State", self:GetState(DrunkMeterDB.value), 0.9, 0.9, 0.9, 1.0, 0.82, 0.28)
    GameTooltip:AddDoubleLine("Next -1 in", tostring(math.ceil(self.DECAY_SECONDS - (self.decayElapsed or 0))) .. "s", 0.9, 0.9, 0.9, 1.0, 1.0, 1.0)
    GameTooltip:AddDoubleLine("Tracked drinks", tostring(DrunkMeterDB.totalDrinks or 0), 0.9, 0.9, 0.9, 1.0, 1.0, 1.0)
    GameTooltip:AddDoubleLine("Tracked gain", "+" .. tostring(DrunkMeterDB.totalGain or 0), 0.9, 0.9, 0.9, 1.0, 1.0, 1.0)

    if DrunkMeterDB.lastDrinkName and DrunkMeterDB.lastDrinkName ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Last drink", 1.0, 0.82, 0.28)
        GameTooltip:AddLine(DrunkMeterDB.lastDrinkName .. "  (+" .. tostring(DrunkMeterDB.lastGain or 0) .. ")", 1.0, 1.0, 1.0)
        local ago = math.floor(GetTime() - (tonumber(DrunkMeterDB.lastDrinkTime) or GetTime()))
        if ago < 0 then ago = 0 end
        GameTooltip:AddLine(tostring(ago) .. "s ago", 0.65, 0.65, 0.65)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-drag to move  |  /drunk lock", 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

function DM:ApplyNativeBarTexture()
    if not self.bar then return end
    -- ChatFrameBackground is a Vanilla-safe solid texture. Tinting it produces
    -- a genuinely flat dark-red fill with no gradient or retail-only asset.
    self.bar:SetStatusBarTexture(self.BAR_TEXTURE)
end

function DM:CreateBorderTexture(parent, point1, relPoint1, x1, y1, point2, relPoint2, x2, y2, width, height)
    local tex = self:CreateSolidTexture(parent, "OVERLAY", 0.30, 0.30, 0.30, 1)
    tex:SetPoint(point1, parent, relPoint1, x1, y1)
    if point2 then tex:SetPoint(point2, parent, relPoint2, x2, y2) end
    if width then tex:SetWidth(width) end
    if height then tex:SetHeight(height) end
    return tex
end

function DM:CreateUI()
    if self.frame then return end

    local f = CreateFrame("Frame", "DrunkMeterFrame", UIParent)
    self.frame = f
    f:SetWidth(48)
    f:SetHeight(236)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(1)
    f:EnableMouse(1)
    f:RegisterForDrag("LeftButton")

    f:SetScript("OnDragStart", function()
        if DrunkMeterDB and not DrunkMeterDB.locked then
            this:StartMoving()
        end
    end)

    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        DM:SavePosition()
    end)

    f:SetScript("OnEnter", function() DM:ShowTrackingTooltip() end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local outer = CreateFrame("Frame", "DrunkMeterBarBody", f)
    self.barOuter = outer
    outer:SetWidth(self.OUTER_BAR_WIDTH)
    outer:SetHeight(self.BAR_HEIGHT + self.BAR_INSET * 2)
    outer:SetPoint("TOP", f, "TOP", 0, -6)

    local outerBg = self:CreateSolidTexture(outer, "BACKGROUND", 0.015, 0.015, 0.015, 1)
    outerBg:SetAllPoints(outer)
    self.barOuterBackground = outerBg

    -- Thin deterministic one-pixel border; no status fill can cover it because
    -- the actual StatusBar is inset by two pixels on all sides.
    self.borderTop = self:CreateBorderTexture(outer, "TOPLEFT", "TOPLEFT", 0, 0, "TOPRIGHT", "TOPRIGHT", 0, 0, nil, 1)
    self.borderBottom = self:CreateBorderTexture(outer, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, nil, 1)
    self.borderLeft = self:CreateBorderTexture(outer, "TOPLEFT", "TOPLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, 1, nil)
    self.borderRight = self:CreateBorderTexture(outer, "TOPRIGHT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, 1, nil)

    local bar = CreateFrame("StatusBar", "DrunkMeterStatusBar", outer)
    self.bar = bar
    bar:SetWidth(self.BAR_WIDTH)
    bar:SetHeight(self.BAR_HEIGHT)
    bar:SetPoint("CENTER", outer, "CENTER", 0, 0)
    bar:SetMinMaxValues(0, self.BAR_HEIGHT)
    bar:SetValue(0)
    if bar.SetOrientation then bar:SetOrientation("VERTICAL") end

    local empty = self:CreateSolidTexture(bar, "BACKGROUND", 0.01, 0.01, 0.01, 1)
    empty:SetAllPoints(bar)
    self.barBackground = empty

    self:ApplyNativeBarTexture()
    bar:SetStatusBarColor(self.BAR_RED_R, self.BAR_RED_G, self.BAR_RED_B)

    -- Exactly two static markers: grey DRUNK and gold SMASHED.
    self.drunkTick = self:CreateTickAtValue(self.DRUNK_AT, 0.68, 0.68, 0.68)
    self.smashedTick = self:CreateTickAtValue(self.SMASHED_AT, 0.96, 0.78, 0.18)

    -- Created after static markers so the white moving ticker is always front-most.
    local decayLine = self:CreateSolidTexture(bar, "OVERLAY", 1.0, 1.0, 1.0, 1)
    self.decayLine = decayLine
    decayLine:SetWidth(self.BAR_WIDTH)
    decayLine:SetHeight(self.LINE_HEIGHT)
    decayLine:Hide()

    local valueText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.valueText = valueText
    valueText:SetPoint("TOP", outer, "BOTTOM", 0, -5)
    valueText:SetText("0/256")
    valueText:SetTextColor(1.0, 0.94, 0.78)
    if valueText.SetJustifyH then valueText:SetJustifyH("CENTER") end
    if valueText.SetShadowOffset then valueText:SetShadowOffset(1, -1) end

    local stateText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.stateText = stateText
    stateText:SetPoint("TOP", valueText, "BOTTOM", 0, -1)
    stateText:SetText("SOBER")
    stateText:SetTextColor(0.92, 0.88, 0.76)
    if stateText.SetJustifyH then stateText:SetJustifyH("CENTER") end
    if stateText.SetShadowOffset then stateText:SetShadowOffset(1, -1) end
end

function DM:InitHooks()
    if self.hooksInstalled then return end
    self.hooksInstalled = true

    if type(UseContainerItem) == "function" then
        self.originalUseContainerItem = UseContainerItem
        UseContainerItem = function(bag, slot)
            DM:ObserveBagUse(bag, slot)
            DM.originalUseContainerItem(bag, slot)
        end
    end

    if type(UseAction) == "function" then
        self.originalUseAction = UseAction
        UseAction = function(slot, checkCursor, onSelf)
            DM:ObserveActionUse(slot)
            DM.originalUseAction(slot, checkCursor, onSelf)
        end
    end

    if type(ContainerFrameItemButton_OnEnter) == "function" then
        self.originalContainerOnEnter = ContainerFrameItemButton_OnEnter
        ContainerFrameItemButton_OnEnter = function()
            DM.originalContainerOnEnter()
            if this and this.GetID and this.GetParent then
                local parent = this:GetParent()
                local slot = this:GetID()
                local bag = parent and parent.GetID and parent:GetID()
                if bag ~= nil and slot ~= nil then
                    DM:AddBagTooltip(bag, slot)
                end
            end
        end
    end
end

function DM:MatchesGlobalMessage(msg, globalName)
    local template = getglobal(globalName)
    if type(template) ~= "string" or template == "" then return false end
    if msg == template then return true end

    local startPos = string.find(template, "%s", 1, true)
    if not startPos then return false end
    local before = string.sub(template, 1, startPos - 1)
    local after = string.sub(template, startPos + 2)
    if string.sub(msg, 1, string.len(before)) ~= before then return false end
    if after ~= "" and string.sub(msg, -string.len(after)) ~= after then return false end
    return string.len(msg) >= string.len(before) + string.len(after)
end

function DM:DetectDrunkStateMessage(msg)
    if not msg then return nil, nil end

    if self:MatchesGlobalMessage(msg, "DRUNK_MESSAGE_SELF1") then return "SOBER", "state" end
    if self:MatchesGlobalMessage(msg, "DRUNK_MESSAGE_SELF2") then return "TIPSY", "state" end
    if self:MatchesGlobalMessage(msg, "DRUNK_MESSAGE_SELF3") then return "DRUNK", "state" end
    if self:MatchesGlobalMessage(msg, "DRUNK_MESSAGE_SELF4") then return "SMASHED", "state" end

    if self:MatchesGlobalMessage(msg, "DRUNK_MESSAGE_ITEM_SELF2") then return "TIPSY", "item" end
    if self:MatchesGlobalMessage(msg, "DRUNK_MESSAGE_ITEM_SELF3") then return "DRUNK", "item" end
    if self:MatchesGlobalMessage(msg, "DRUNK_MESSAGE_ITEM_SELF4") then return "SMASHED", "item" end

    local s = lower(msg)
    if string.find(s, "you feel sober again", 1, true) then return "SOBER", "state" end
    if string.find(s, "you feel completely smashed", 1, true) then return "SMASHED", "state" end
    if string.find(s, "you're feeling drunk", 1, true)
        or string.find(s, "you feel drunk", 1, true) then return "DRUNK", "state" end
    if string.find(s, "you feel a little tipsy", 1, true)
        or string.find(s, "you feel tipsy", 1, true) then return "TIPSY", "state" end

    return nil, nil
end

function DM:GetSyncedValueForState(state, current)
    current = clamp(tonumber(current) or 0, 0, self.MAX_VALUE)
    if state == "SOBER" then return 0 end

    if state == "TIPSY" then
        if current > 0 and current < self.DRUNK_AT then return current end
        if current >= self.DRUNK_AT then return self.DRUNK_AT - 1 end
        return 1
    end

    if state == "DRUNK" then
        if current >= self.DRUNK_AT and current < self.SMASHED_AT then return current end
        if current >= self.SMASHED_AT then return self.SMASHED_AT - 1 end
        return self.DRUNK_AT
    end

    if state == "SMASHED" then
        if current >= self.SMASHED_AT then return current end
        return self.SMASHED_AT
    end

    return current
end

function DM:SyncFromDrunkMessage(state, msg, kind)
    self:EnsureDB()
    local before = tonumber(DrunkMeterDB.value) or 0
    local after = self:GetSyncedValueForState(state, before)
    local phaseBefore = tonumber(self.decayElapsed) or 0

    self.warningState = nil
    if after ~= before then
        -- System/chat synchronisation corrects the value only. It is not a new
        -- decay clock and must not restart the live 10-second phase.
        self:SetValue(after, "chat sync " .. state)
    else
        self:UpdateBar()
        self:RefreshLevelDisplays()
    end

    self:Log("chat sync | " .. tostring(kind or "state") .. " | " .. state .. " | "
        .. math.floor(before + 0.5) .. " -> " .. math.floor(after + 0.5)
        .. " | phase-preserved=" .. string.format("%.2f", phaseBefore)
        .. " | " .. tostring(msg))
end

function DM:HandleSystemMessage(msg)
    if not msg then return end
    local state, kind = self:DetectDrunkStateMessage(msg)
    if state then
        self:SyncFromDrunkMessage(state, msg, kind)
        return
    end

    local s = lower(msg)
    if string.find(s, "tipsy", 1, true)
        or string.find(s, "drunk", 1, true)
        or string.find(s, "smashed", 1, true)
        or string.find(s, "sober", 1, true) then
        self:Log("system-unmatched | " .. msg)
    end
end

function DM:Slash(msg)
    self:EnsureDB()
    msg = msg or ""
    local s = lower(msg)

    local _, _, n = string.find(s, "^set%s+(%d+)")
    if n then
        n = clamp(tonumber(n) or 0, 0, self.MAX_VALUE)
        self:ResetDecayPhase("manual /drunk set")
        self:SetValue(n, "set")
        self:Log("set | value=" .. n)
        chat("set to " .. n .. " / " .. self.MAX_VALUE)
        return
    end

    if s == "debug" then
        DrunkMeterDB.debug = not DrunkMeterDB.debug
        self.debugTimerElapsed = 0
        chat("debug " .. (DrunkMeterDB.debug and "ON" or "OFF"))
        if DrunkMeterDB.debug then
            self:Log("timer debug enabled | phase=" .. string.format("%.3f", tonumber(self.decayElapsed) or 0)
                .. " | value=" .. math.floor((DrunkMeterDB.value or 0) + 0.5))
        end
        return
    end

    if s == "lock" then
        DrunkMeterDB.locked = true
        chat("bar locked")
        return
    end

    if s == "unlock" then
        DrunkMeterDB.locked = false
        chat("bar unlocked; drag with left mouse")
        return
    end

    if s == "reset" then
        self:ResetDecayPhase("manual /drunk reset")
        self:SetValue(0, "reset")
        self:Log("manual reset")
        chat("reset to 0 / " .. self.MAX_VALUE)
        return
    end

    if s == "clearlog" then
        DrunkMeterLog = {}
        chat("SavedVariables log cleared")
        return
    end

    if s == "show" then
        self.frame:Show()
        return
    end

    if s == "hide" then
        self.frame:Hide()
        return
    end

    chat(math.floor(DrunkMeterDB.value + 0.5) .. " / " .. self.MAX_VALUE .. " (" .. self:GetState(DrunkMeterDB.value) .. ")")
    chat("/drunk set <0-256>, debug, lock, unlock, reset, clearlog, show, hide")
end

function DM:Initialize()
    if self.initialized then return end

    self:EnsureDB()
    self:RestoreOfflineDecay()
    self:CreateUI()
    self:ApplyPosition()
    self:InitHooks()
    self:InstallTrueLevelHook()
    self.nameplateElapsed = 0
    self.nameplateFontCache = {}
    self.nameplateFrameFonts = {}
    self.nameplateCorrectionDisabled = false
    self.nameplateRestoreErrorLogged = false
    self.pendingDrinkErrorLogged = false
    self.debugTimerElapsed = 0
    self.lastUpdateTime = type(GetTime) == "function" and GetTime() or nil
    self.initialized = true
    self:UpdateBar()
    self:RefreshLevelDisplays()
    self:SaveOfflineSnapshot("session-start", false)

    self:Log("session start | DrunkMeter " .. self.VERSION .. " | value="
        .. math.floor(DrunkMeterDB.value + 0.5) .. " | phase="
        .. string.format("%.2f", tonumber(self.decayElapsed) or 0))
end

function DM:OnEvent(ev)
    if ev == "VARIABLES_LOADED" then
        self:Initialize()
    elseif ev == "PLAYER_LOGOUT" then
        if self.initialized then
            self:SaveOfflineSnapshot("logout", true)
            self:Log("session end | value=" .. math.floor((DrunkMeterDB.value or 0) + 0.5)
                .. " | phase=" .. string.format("%.2f", tonumber(self.decayElapsed) or 0))
        end
    elseif ev == "PLAYER_DEAD" then
        if self.initialized then
            self:ResetDecayPhase("death")
            self:SetValue(0, "death")
            self:Log("death | reset to sober")
        end
    elseif ev == "CHAT_MSG_SYSTEM" then
        if self.initialized then self:HandleSystemMessage(arg1) end
    end
end

function DM:GetFrameDelta(elapsed)
    local raw = tonumber(elapsed)
    local now = nil
    local fallback = nil

    if type(GetTime) == "function" then
        local ok, t = pcall(GetTime)
        if ok then now = tonumber(t) end
    end

    if now and self.lastUpdateTime then
        fallback = now - self.lastUpdateTime
    end
    if now then self.lastUpdateTime = now end

    local dt = raw
    local source = "callback"

    if not dt or dt <= 0 then
        dt = fallback
        source = "GetTime"
    elseif fallback and fallback > 0 then
        -- A supplied value that differs wildly from the monotonic clock is
        -- probably not an elapsed-seconds value on this client signature.
        local ratio = dt / fallback
        if ratio < 0 then ratio = -ratio end
        if dt > 2 and (ratio > 4 or ratio < 0.25) then
            dt = fallback
            source = "GetTime-sanity"
        end
    end

    if not dt or dt <= 0 then
        dt = 0
        source = "none"
    end

    if dt > self.MAX_SANE_DELTA then
        if fallback and fallback > 0 and fallback <= self.MAX_SANE_DELTA then
            dt = fallback
            source = "GetTime-large-fallback"
        else
            -- Protect against clock/callback corruption without allowing an
            -- absurd single frame to run hundreds of expensive UI updates.
            dt = self.MAX_SANE_DELTA
            source = source .. "-capped"
        end
    end

    return dt, raw, fallback, source
end

function DM:DebugTimerSample(dt, raw, fallback, source)
    if not DrunkMeterDB or not DrunkMeterDB.debug then return end

    self.debugTimerElapsed = (tonumber(self.debugTimerElapsed) or 0) + (tonumber(dt) or 0)
    if self.debugTimerElapsed < self.DEBUG_TIMER_LOG_SECONDS then return end
    self.debugTimerElapsed = self.debugTimerElapsed - math.floor(self.debugTimerElapsed / self.DEBUG_TIMER_LOG_SECONDS) * self.DEBUG_TIMER_LOG_SECONDS

    local rawText = raw and string.format("%.4f", raw) or "nil"
    local fallbackText = fallback and string.format("%.4f", fallback) or "nil"
    self:Log("timer sample | raw=" .. rawText
        .. " | fallback=" .. fallbackText
        .. " | used=" .. string.format("%.4f", tonumber(dt) or 0)
        .. " | source=" .. tostring(source)
        .. " | phase=" .. string.format("%.3f", tonumber(self.decayElapsed) or 0)
        .. " | value=" .. math.floor((DrunkMeterDB.value or 0) + 0.5))
end

function DM:AdvanceDecay(dt)
    if DrunkMeterDB.value <= 0 then
        if (tonumber(self.decayElapsed) or 0) ~= 0 then
            self:ResetDecayPhase("value is sober")
        end
        return
    end

    self.decayElapsed = (tonumber(self.decayElapsed) or 0) + (tonumber(dt) or 0)
    while self.decayElapsed >= self.DECAY_SECONDS do
        self.decayElapsed = self.decayElapsed - self.DECAY_SECONDS
        self:DecayOne()
        if DrunkMeterDB.value <= 0 then
            self:ResetDecayPhase("decay reached zero")
            break
        end
    end
end

function DM:OnUpdate(elapsed)
    if not self.initialized then return end
    self:EnsureDB()

    -- One authoritative live clock. Optional systems only read its result.
    local dt, raw, fallback, source = self:GetFrameDelta(elapsed)

    local pendingOK, pendingErr = pcall(self.ConfirmPendingDrink, self)
    if not pendingOK and not self.pendingDrinkErrorLogged then
        self.pendingDrinkErrorLogged = true
        self:Log("pending drink confirmation error | " .. tostring(pendingErr))
    end

    self:AdvanceDecay(dt)
    self:UpdateThresholdWarning()
    self:UpdateDecayTicker()
    self:DebugTimerSample(dt, raw, fallback, source)

    -- Optional nameplate work is last and failure-isolated.
    self.nameplateElapsed = (tonumber(self.nameplateElapsed) or 0) + dt
    if self.nameplateElapsed >= self.NAMEPLATE_SCAN_SECONDS then
        self.nameplateElapsed = self.nameplateElapsed - self.NAMEPLATE_SCAN_SECONDS
        if self.nameplateElapsed > self.NAMEPLATE_SCAN_SECONDS then
            self.nameplateElapsed = 0
        end
        if DrunkMeterDB.value > 0 then
            self:SafeRefreshNameplateLevels()
        elseif self.nameplateFrameFonts then
            self:SafeRestoreNameplateLevels()
        end
    end
end

local driver = CreateFrame("Frame", "DrunkMeterDriver", UIParent)
driver:RegisterEvent("VARIABLES_LOADED")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:RegisterEvent("PLAYER_DEAD")
driver:RegisterEvent("CHAT_MSG_SYSTEM")
driver:SetScript("OnEvent", function()
    DM:OnEvent(event)
end)
driver:SetScript("OnUpdate", function(a, b)
    -- 1.12 normally exposes elapsed through global arg1. Some OctoWoW-derived
    -- clients also pass (frame, elapsed) or a single elapsed argument.
    local elapsed = nil
    if type(b) == "number" then
        elapsed = b
    elseif type(a) == "number" then
        elapsed = a
    elseif type(arg1) == "number" then
        elapsed = arg1
    end
    DM:OnUpdate(elapsed)
end)

SLASH_DRUNKMETER1 = "/drunk"
SlashCmdList["DRUNKMETER"] = function(msg)
    DM:Slash(msg)
end
