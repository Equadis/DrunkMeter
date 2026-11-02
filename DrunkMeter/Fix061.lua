-- DrunkMeter 0.6.1 hotfix
-- Restores threshold/ticker visibility and hardens live decay timing on Vanilla/OctoWoW.

local DM = DrunkMeter
if not DM then return end

DM.VERSION = "0.6.1"

-- Vanilla-safe solid threshold markers. Some 1.12 clients do not reliably
-- expose Interface\Buttons\WHITE8X8, which made the DRUNK/SMASHED lines vanish.
function DM:CreateTickAtValue(v, r, g, b)
    local y = self:GetVisualOffset(v)
    local tick = self.bar:CreateTexture(nil, "OVERLAY")
    tick:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    tick:SetVertexColor(r or 0.96, g or 0.84, b or 0.48)
    tick:SetAlpha(1.0)
    tick:SetWidth(self.BAR_WIDTH)
    tick:SetHeight(2)
    tick:SetPoint("CENTER", self.bar, "BOTTOM", 0, y)
    return tick
end

-- Keep the redesigned bar, but force the decay line onto the same known-good
-- solid Vanilla texture and ensure the two threshold markers are visible.
local DM061OriginalCreateUI = DM.CreateUI
function DM:CreateUI()
    DM061OriginalCreateUI(self)

    if self.decayLine then
        self.decayLine:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        self.decayLine:SetVertexColor(1.0, 1.0, 1.0)
        self.decayLine:SetAlpha(1.0)
        self.decayLine:SetWidth(self.BAR_WIDTH)
        self.decayLine:SetHeight(2)
    end

    if self.drunkTick then self.drunkTick:Show() end
    if self.smashedTick then self.smashedTick:Show() end
end

-- The white ticker is a 10-second clock, not a marker for the red fill.
-- Sweep from the very top of the full bar to the bottom, then reset to top
-- when the next -1 decay tick occurs.
function DM:UpdateDecayTicker()
    if not self.decayLine then return end

    local v = tonumber(DrunkMeterDB and DrunkMeterDB.value) or 0
    if v <= 0 then
        self.decayLine:Hide()
        if self.decayNub then self.decayNub:Hide() end
        if self.decayGlow then self.decayGlow:Hide() end
        return
    end

    local seconds = tonumber(self.DECAY_SECONDS) or 10
    if seconds <= 0 then seconds = 10 end

    local progress = (tonumber(self.decayElapsed) or 0) / seconds
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end

    local y = self.BAR_HEIGHT * (1 - progress)

    self.decayLine:ClearAllPoints()
    self.decayLine:SetPoint("CENTER", self.bar, "BOTTOM", 0, y)
    self.decayLine:SetVertexColor(1.0, 1.0, 1.0)
    self.decayLine:SetAlpha(1.0)
    self.decayLine:Show()

    if self.decayNub then self.decayNub:Hide() end
    if self.decayGlow then self.decayGlow:Hide() end
end

-- Live decay previously depended entirely on the legacy global arg1 reaching
-- the driver's OnUpdate callback. On clients that do not populate arg1 there,
-- elapsed became nil -> 0 and decayElapsed never advanced. Keep the existing
-- core logic but provide a monotonic GetTime() fallback whenever elapsed is
-- absent or invalid. This is independent of login/VARIABLES_LOADED handling.
local DM061OriginalOnUpdate = DM.OnUpdate
function DM:OnUpdate(elapsed)
    local now = GetTime()
    local dt = tonumber(elapsed)

    if not dt or dt <= 0 then
        if self._dm061LastUpdate then
            dt = now - self._dm061LastUpdate
        else
            dt = 0
        end
    end

    self._dm061LastUpdate = now
    if dt < 0 then dt = 0 end

    return DM061OriginalOnUpdate(self, dt)
end
