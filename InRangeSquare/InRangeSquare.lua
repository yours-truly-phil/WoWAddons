local addonName = "InRangeSquare"
local frame = CreateFrame("Frame", "InRangeSquareFrame", UIParent)
local texture = frame:CreateTexture(nil, "BACKGROUND")
texture:SetAllPoints(frame)

-- Spec-specific melee spells (from MeleeRangeIndicator)
-- NOTE for Survival Hunter (255): The filler ability can transform.
-- - 186270 = Raptor Strike (baseline)
-- - 259387 = Mongoose Bite (older talent replacement)
-- - 1259003 = Raptor Swipe (current Apex talent upgrade — "Raptor Strike has a 25%+ chance to become Raptor Swipe")
-- When it transforms into Raptor Swipe the old IDs return nil from IsSpellInRange.
-- We now prioritize the active form + have strong fallbacks.
local SPEC_SPELLS = {
	[66] = 96231, [70] = 96231,                      		-- Pala
	[250] = 316239, [251] = 316239, [252] = 316239,  		-- DK
	[577] = 162794, [581] = 344859, [1480] = 473662,       	-- DH
	[255] = 186270,                                   		-- Hunter Survival (see note above)
	[102] = 5221, [103] = 5221, [104] = 5221, [105] = 5221,	-- Druid
	[268] = 205523, [269] = 205523, [270] = 205523,  		-- Monk
	[71] = 1464, [72] = 1464, [73] = 23922,          		-- Warrior
	[263] = 17364,                                   		-- Shaman
	[259] = 1752, [260] = 1752, [261] = 1752,        		-- Rogue
	[1467] = 362969, [1468] = 362969, [1473] = 362969,		-- Evoker
}

local defaults = {
	enabled = true,
	size = 48,
	alpha = 0.85,
	point = "CENTER",
	relativePoint = "CENTER",
	x = 0,
	y = -140,
}

InRangeSquareDB = InRangeSquareDB or {}

local cachedSpellID = nil

-- Additional safe fallback spells that almost always return a valid range result.
-- Order matters: tried after the primary if it returns nil.
-- Includes Raptor Swipe because it is the active form of the Survival filler when the Apex talent procs.
local SAFE_FALLBACK_SPELLS = { 1259003, 6603, 2974 }  -- Raptor Swipe, Attack (auto), Wing Clip (hunter baseline melee)

local function RefreshSpellCache()
	local specID = PlayerUtil.GetCurrentSpecID()
	cachedSpellID = SPEC_SPELLS[specID]

	-- Survival Hunter special handling.
	-- The main melee filler transforms between these forms:
	--   1259003 = Raptor Swipe (Apex talent proc / upgrade — this is what you're seeing as "Raptor Swipe")
	--   259387  = Mongoose Bite (older replacement)
	--   186270  = Raptor Strike (baseline)
	-- We check in priority order for whichever version is currently known/active.
	-- This prevents the yellow state when the ability upgrades to Raptor Swipe.
	if specID == 255 then
		local survivalStrikes = {1259003, 259387, 186270}  -- Swipe > Mongoose > Raptor Strike
		local found = false
		for _, spellID in ipairs(survivalStrikes) do
			if IsPlayerSpell(spellID) then
				cachedSpellID = spellID
				found = true
				break
			end
		end
		if not found then
			cachedSpellID = 6603
		end
	end

	if not cachedSpellID then
		cachedSpellID = 6603  -- fallback to Attack
	end
end

-- Returns true/false if we can determine range, or nil if even fallbacks fail.
-- This prevents spurious yellow "unknown" flashes when the spec spell temporarily
-- returns nil (common with replaced talents like Mongoose Bite over Raptor Strike,
-- hero talents, or certain rotation states in current Survival).
local function GetReliableRangeResult(spellID, unit)
	if not spellID then
		return nil
	end

	local result = C_Spell.IsSpellInRange(spellID, unit)
	if result ~= nil then
		return result
	end

	-- Primary spell gave nil. For Survival, first try the other possible strike forms
	-- (Raptor Swipe / Mongoose / Raptor Strike) because one of them is almost certainly the active button.
	local specID = PlayerUtil.GetCurrentSpecID()
	if specID == 255 then
		local survivalStrikes = {1259003, 259387, 186270}
		for _, altID in ipairs(survivalStrikes) do
			if altID ~= spellID then
				local altResult = C_Spell.IsSpellInRange(altID, unit)
				if altResult ~= nil then
					return altResult
				end
			end
		end
	end

	-- Then the generic safe fallbacks (Attack + Wing Clip, plus Swipe already in the list).
	for _, fbID in ipairs(SAFE_FALLBACK_SPELLS) do
		if fbID ~= spellID then
			local fbResult = C_Spell.IsSpellInRange(fbID, unit)
			if fbResult ~= nil then
				return fbResult
			end
		end
	end

	return nil  -- still can't determine (very rare)
end

local function UpdateIndicator()
	if not InRangeSquareDB.enabled then
		frame:Hide()
		return
	end

	frame:Show()

	if not UnitExists("target") or not UnitCanAttack("player", "target") then
		texture:SetColorTexture(0.4, 0.4, 0.4, InRangeSquareDB.alpha)  -- Grey
		return
	end

	if not cachedSpellID then
		texture:SetColorTexture(0.6, 0.6, 0.0, InRangeSquareDB.alpha)  -- Yellow = error
		return
	end

	local inRange = GetReliableRangeResult(cachedSpellID, "target")

	if inRange == true then
		texture:SetColorTexture(0.0, 1.0, 0.0, InRangeSquareDB.alpha)  -- Bright Green
	elseif inRange == false then
		texture:SetColorTexture(1.0, 0.0, 0.0, InRangeSquareDB.alpha)  -- Bright Red
	else
		texture:SetColorTexture(0.6, 0.6, 0.0, InRangeSquareDB.alpha)  -- Yellow (cannot determine)
	end
end

local ticker = nil
local function StartTicker()
	if ticker then ticker:Cancel() end
	ticker = C_Timer.NewTicker(0.1, UpdateIndicator)
end

-- Slash commands
SLASH_INRANGESQUARE1 = "/irs"
SlashCmdList["INRANGESQUARE"] = function(msg)
	msg = msg:lower()
	if msg == "toggle" or msg == "" then
		InRangeSquareDB.enabled = not InRangeSquareDB.enabled
		if InRangeSquareDB.enabled then
			print("|cff00ff00InRangeSquare ENABLED|r (Green = in melee, Red = out)")
			StartTicker()
		else
			print("|cffff0000InRangeSquare DISABLED|r")
			frame:Hide()
		end
	elseif msg == "reset" then
		InRangeSquareDB.x, InRangeSquareDB.y = defaults.x, defaults.y
		frame:ClearAllPoints()
		frame:SetPoint(defaults.point, UIParent, defaults.relativePoint, defaults.x, defaults.y)
		print("Position reset - drag again with right-click")
	else
		print("InRangeSquare: /irs toggle | /irs reset")
	end
end

-- Frame setup
frame:SetSize(defaults.size, defaults.size)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("RightButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relativePoint, x, y = self:GetPoint()
	InRangeSquareDB.point, InRangeSquareDB.relativePoint, InRangeSquareDB.x, InRangeSquareDB.y = point, relativePoint, x, y
end)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)

-- Load settings
local function OnLoad()
	for k, v in pairs(defaults) do
		if InRangeSquareDB[k] == nil then InRangeSquareDB[k] = v end
	end
	frame:SetSize(InRangeSquareDB.size, InRangeSquareDB.size)
	frame:ClearAllPoints()
	frame:SetPoint(InRangeSquareDB.point, UIParent, InRangeSquareDB.relativePoint, InRangeSquareDB.x, InRangeSquareDB.y)
	texture:SetColorTexture(0.5, 0.5, 0.5, 0.5)

	RefreshSpellCache()

	if InRangeSquareDB.enabled then
		StartTicker()
		UpdateIndicator()
	end

	print("|cff00ccffInRangeSquare loaded!|r Right-click + drag the square over your character. Use /irs toggle")
end

-- Events
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")

frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		OnLoad()
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LOGIN"
		or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
		RefreshSpellCache()
		UpdateIndicator()
	elseif event == "PLAYER_TARGET_CHANGED" then
		UpdateIndicator()
	end
end)