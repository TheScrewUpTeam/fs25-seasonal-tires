--
-- TireManager (injection approach)
--

source(g_currentModDirectory .. "src/TireHUD.lua")
source(g_currentModDirectory .. "src/TireManagerChangeTireEvent.lua")

if Utils == nil then Utils = {} end
---
-- Appends a function to another, calling both in order.
-- @param orig function|nil The original function.
-- @param toAdd function The function to append.
-- @return function The combined function.
function Utils.appendedFunction(orig, toAdd)
    if orig == nil then
        return toAdd
    end
    return function(...)
        orig(...)
        toAdd(...)
    end
end

local PRINT_PREFIX = "[SeasonalTiresMod] "

TireManager = {}
TireManager.surfaceConfig = {
    -- Soft, tilled, or loose soil; poor traction
    field  = 0.75,

    -- Moderate grip, can be slick when wet or with worn grass
    grass  = 0.85,

    -- Asphalt/concrete; highest grip
    road   = 1.1,

    -- Dry dirt paths; decent traction, can get dusty/slippery
    dirt   = 0.9,

    -- Compacted terrain (like tire tracks, rolled soil)
    track  = 1.0,

    -- Loose sand; very low traction, risk of getting stuck
    sand   = 0.6,
}

TireManager.tireTypes = {
    allSeason = {
        name = "All-Season",
        frictionModifier = 1.0,
        fieldBonus = -0.4,
        roadBonus = 0.0,
        snowBonus = -0.4,
        wearRate = 1.0
    },
    mud = {
        name = "Mud Tire",
        frictionModifier = 1.0,
        fieldBonus = 0.4,
        roadBonus = -0.1,
        snowBonus = -0.2,
        wearRate = 1.2
    },
    snow = {
        name = "Snow Tire",
        frictionModifier = 1.0,
        fieldBonus = -0.3,
        roadBonus = -0.1,
        snowBonus = 0.5,
        wearRate = 1.1
    },
    road = {
        name = "Road Tire",
        frictionModifier = 1.1,
        fieldBonus = -0.5,
        roadBonus = 0.5,
        snowBonus = -0.6,
        wearRate = 0.9
    },
    flotation = {
        name = "Flotation Tire",
        frictionModifier = 0.95,
        fieldBonus = 0.3,
        roadBonus = -0.2,
        snowBonus = 0.2,
        wearRate = 1.3
    }
}
TireManager.config = {
    mudMultiplier = 1.5,
    snowMultiplier = 2.0,
    rainPenalty = 0.8,
    frictionMin = 0.2,
    frictionMax = 2.5
}
TireManager.debugLogTimer = 0
TireManager.debugLogInterval = 1000 -- ms

---
-- Get the tire type for a vehicle.
-- @param vehicle table The vehicle object.
-- @return string The tire type key.
function TireManager.getTireType(vehicle)
    return vehicle.tireManagerTireType or "allSeason"
end

---
-- Set the tire type for a vehicle.
-- @param vehicle table The vehicle object.
-- @param tireType string The tire type key.
function TireManager.setTireType(vehicle, tireType)
    if TireManager.tireTypes[tireType] then
        vehicle.tireManagerTireType = tireType
        print(PRINT_PREFIX .. string.format("Tire type set to '%s' on %s", tireType, vehicle.configFileName or vehicle:getName() or tostring(vehicle)))
    else
        print(PRINT_PREFIX .. "Unknown tire type: " .. tostring(tireType))
    end
end

---
-- Calculate the effective friction for a vehicle's wheel.
-- @param vehicle table The vehicle object.
-- @param physWheel table The physical wheel object.
-- @return number The clamped friction value.
function TireManager.getEffectiveFriction(vehicle, physWheel)
    local tireType = TireManager.getTireType(vehicle)
    local tireData = TireManager.tireTypes[tireType] or TireManager.tireTypes["allSeason"]
    local friction = tireData.frictionModifier or 1.0

     -- Surface detection
     local surface = "road"
     if vehicle.getIsOnField and vehicle:getIsOnField() then
         surface = "field"
     end

    local env = g_currentMission.environment
    local isSnow = false
    local isRain = false
    local snowHeight = 0
    if env.snowSystem then
        local x, y, z = getWorldTranslation(vehicle.rootNode)
        snowHeight = env.snowSystem:getSnowHeightAtWorldPos(x, y, z)
    end
    if env.weather:getIsSnowing() or snowHeight > 0.05 then
        isSnow = true
    end
    if env.weather:getIsRaining() then
        isRain = true
    end

    -- Apply bonuses/penalties (configurable, per surface)
    local bonus = 0
    if surface == "field" then bonus = tireData.fieldBonus or 0
    elseif surface == "road" then bonus = tireData.roadBonus or 0
    end
    friction = friction + bonus * (TireManager.surfaceConfig[surface] or 1.0)
    if isSnow then
        friction = friction + (tireData.snowBonus or 0) * TireManager.config.snowMultiplier
    elseif isRain then
        friction = friction * TireManager.config.rainPenalty
    end

    -- Clamp to config range
    local clamped = math.max(TireManager.config.frictionMin, math.min(TireManager.config.frictionMax, friction))
    if not TireManager.lastDebugLogTime or TireManager.debugLogTimer - TireManager.lastDebugLogTime >= TireManager.debugLogInterval then
        print(string.format("[TireManager] Friction calc: base=%.2f, field=%.2f, grass=%.2f, road=%.2f, dirt=%.2f, track=%.2f, sand=%.2f, snow=%.2f, sum=%.2f, clamped=%.2f, tireType=%s, surface=%s, isSnow=%s, vehicle=%s",
            tireData.frictionModifier or 0, tireData.fieldBonus or 0, tireData.grassBonus or 0, tireData.roadBonus or 0, tireData.dirtBonus or 0, tireData.trackBonus or 0, tireData.sandBonus or 0, tireData.snowBonus or 0,
            friction, clamped, tireType, surface, tostring(isSnow), vehicle.getName and vehicle:getName() or tostring(vehicle)))
        TireManager.lastDebugLogTime = TireManager.debugLogTimer
    end
    return clamped
end

function TireManager:onLoad(savegame)
    FSBaseMission.registerEventListener(self, "draw", TireManager)
end

function TireManager:draw()
    local vehicle = g_currentMission and g_currentMission.controlledVehicle
    if not vehicle and _G.g_activeVehicleCamera and _G.g_activeVehicleCamera.vehicle then
        vehicle = _G.g_activeVehicleCamera.vehicle
    end
    if vehicle then
        local tireData = {
            name = TireManager.tireTypes[vehicle.tireManagerTireType] and TireManager.tireTypes[vehicle.tireManagerTireType].name or "All Season Tires",
            wear = 0.15 -- Replace with actual wear if available
        }
        TireHUD:draw(vehicle, tireData)
    end
end

---
-- Injected update for physical wheel tire friction.
-- @param physWheel table The physical wheel object.
function TireManager.injPhysWheelUpdateTireFriction(physWheel)
    local vehicle = physWheel.vehicle
    if not vehicle or not vehicle.spec_wheels or not vehicle.spec_wheels.wheels then return end
    if not vehicle.isServer or not vehicle.isAddedToPhysics then return end
    local frictionMod = TireManager.getEffectiveFriction(vehicle, physWheel)
    -- Use the game's base friction scale, but modulate it with our value
    local frictionScale = (physWheel.frictionScale or 1) * (physWheel.tireGroundFrictionCoeff or 1) * frictionMod
    setWheelShapeTireFriction(
        physWheel.wheel.node,
        physWheel.wheelShape,
        physWheel.maxLongStiffness,
        physWheel.maxLatStiffness,
        physWheel.maxLatStiffnessLoad,
        frictionScale
    )
    physWheel.isFrictionDirty = false
    -- Update debug log timer for time-based logging
    TireManager.debugLogTimer = (TireManager.debugLogTimer or 0) + (g_currentDt or 0)
end
WheelPhysics.updateTireFriction = Utils.appendedFunction(WheelPhysics.updateTireFriction, TireManager.injPhysWheelUpdateTireFriction)

---
-- Injected onLoad for vehicle to set default tire type.
-- @param vehicle table The vehicle object.
-- @param savegame table|nil The savegame data (optional).
function TireManager.injOnLoad(vehicle, savegame)
    if not vehicle.tireManagerTireType then
        vehicle.tireManagerTireType = "allSeason"
    end
end
Vehicle.onLoad = Utils.appendedFunction(Vehicle.onLoad, TireManager.injOnLoad)

---
-- Console command to set tire type on selected vehicle.
-- @param self table|string The context or tire type string.
-- @param tireType string|nil The tire type key (optional).
function TireManager.consoleSetTireType(self, tireType)
    -- Handle both static and method call signatures
    if type(self) == "string" and tireType == nil then
        tireType = self
        self = nil
    end
    local vehicle = g_currentMission.controlledVehicle
    if not vehicle and _G.g_activeVehicleCamera and _G.g_activeVehicleCamera.vehicle then
        vehicle = _G.g_activeVehicleCamera.vehicle
        print(PRINT_PREFIX .. "Using g_activeVehicleCamera.vehicle: " .. tostring(vehicle and vehicle.configFileName or vehicle))
    end
    if not vehicle then
        print(PRINT_PREFIX .. "No vehicle selected for this player.")
        return
    end
    TireManager.setTireType(vehicle, tireType)
end
addConsoleCommand("tmSetTireType", "Set tire type on selected vehicle", "consoleSetTireType", TireManager)

-- =================================== Change Tires =======================================================


function TireManager.injWokshopScreenSetVehicle(screen, vehicle)
	if screen.tmsButton == nil then
		return
	end

	screen.tmsButton:setVisible(vehicle ~= nil and vehicle.uytHasTyres == true)
	
	if vehicle == nil then
		screen.tmsButton:setText("Change tires")
		screen.tmsButton:setDisabled(true)
	else
		screen.tmsButton:setText(string.format("%s (%s)", "Change tires", g_i18n:formatMoney(100, 0, true, true)))
		screen.tmsButton:setDisabled(false)
	end
end
WorkshopScreen.setVehicle = Utils.appendedFunction(WorkshopScreen.setVehicle, TireManager.injWokshopScreenSetVehicle)

function TireManager.onReplaceTyresCallback(screen)
    print(PRINT_PREFIX .. "onReplaceTyresCallback called")

    local function getFormattedOption(index)
        print(PRINT_PREFIX .. "getFormattedOption", index, TireManager.tireTypes[index].name)
        local name = TireManager.tireTypes[index].name
        local feeString = g_i18n:formatMoney(100, 0, true, true)
        return string.format("%s (%s)", name, feeString)
    end

    local tireKeys = {}
    local options = {}
    local defaultIndex = 1
    local i = 1
    for tireKey, tireData in pairs(TireManager.tireTypes) do
        print(PRINT_PREFIX .. "processing options", tireKey)
        table.insert(tireKeys, tireKey)
        table.insert(options, getFormattedOption(tireKey))
        if tireKey == screen.vehicle.tireManagerTireType then
            defaultIndex = i
        end
        i = i + 1
    end

	OptionDialog.show(function(result)
        if result > 0 then
            local selectedKey = tireKeys[result]
            print(PRINT_PREFIX .. " Selected tire", result, selectedKey)
            TireManager.setTireType(screen.vehicle, selectedKey)
            g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.YES)
        else
            -- g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.ERROR)
        end

    end, "Desctiption", "Title", options, defaultIndex)
	return true
end

function TireManager.injWokshopScreenOnOpen(screen)
	if screen.tmsWorkshopInited == nil then
        print(PRINT_PREFIX .. "Workshop button injection...")

		-- Button
		local tmsButton = ButtonElement.new(screen.buttonsBox)
		tmsButton.name = "tmsChange"
		screen.buttonsBox:addElement(tmsButton)
		tmsButton:applyProfile("buttonActivate")
		tmsButton:setInputAction("TMS_CHANGE_TIRES")
		tmsButton.onClickCallback = function()
			TireManager.onReplaceTyresCallback(screen)
		end
		tmsButton:setText(string.format("%s (%s)", "Change tires", g_i18n:formatMoney(100, 0, true, true)))
		screen.uytBtn = tmsButton
		
		-- Separator
		local tmsSep = BitmapElement.new(tmsButton)
		tmsSep.name = "separator"
		tmsButton:addElement(tmsSep)
		tmsSep:applyProfile("fs25_buttonBoxSeparator")

		screen.tmsWorkshopInited = true
        print(PRINT_PREFIX .. "Workshop button injected...")
	end

	local _, eventId = g_inputBinding:registerActionEvent("TMS_CHANGE_TIRES", screen, TireManager.onReplaceTyresCallback, false, true, false, true)
	screen.tmsEventId = eventId
end
WorkshopScreen.onOpen = Utils.appendedFunction(WorkshopScreen.onOpen, TireManager.injWokshopScreenOnOpen)

function TireManager.injWokshopScreenOnClose(screen)
	if screen.tmsEventId ~= nil then
		g_inputBinding:removeActionEvent(screen.tmsEventId)
		screen.tmsEventId = nil
	end
end
WorkshopScreen.onClose = Utils.appendedFunction(WorkshopScreen.onClose, TireManager.injWokshopScreenOnClose)

-- ======================================= Save / Load =========================================================
function TireManager.injWheelsSaveToXMLFile(vehicle, xmlFile, saveKey)
	if vehicle.spec_wheels == nil or vehicle.tireManagerTireType == nil then
		return
	end
    print(PRINT_PREFIX .. "Save injection...")
	
    local vehicleKey = string.format("%s#tmsTireType", saveKey)
    xmlFile:setValue(vehicleKey, vehicle.tireManagerTireType)

	-- local tyreDistanceKey = string.format("%s#uytDistanceMultiplier", wheelsKey)
	-- xmlFile:setValue(tyreDistanceKey, UseYourTyres.tyreDistanceMultiplier)
    print(PRINT_PREFIX .. "Saved as ", vehicleKey)
end
Wheels.saveToXMLFile = Utils.appendedFunction(Wheels.saveToXMLFile, TireManager.injWheelsSaveToXMLFile)

function TireManager.injWheelsOnLoadFinished(vehicle, savegame)
	if vehicle.spec_wheels == nil or savegame == nil then
		return
	end
    print(PRINT_PREFIX .. "Load injection...")

	local vehicleKey = string.format("%s.wheels#tmsTireType", savegame.key)
	local tireType = savegame.xmlFile:getValue(vehicleKey)
	TireManager.setTireType(vehicle, tireType or 'allSeason')
    print(PRINT_PREFIX .. "Loaded from ", vehicleKey)
end
Wheels.onLoadFinished = Utils.appendedFunction(Wheels.onLoadFinished, TireManager.injWheelsOnLoadFinished)

function TireManager.injVehicleInit()
    print(PRINT_PREFIX .. "Register save path")
	Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?).wheels#tmsTireType", "Season Tires Mod Tire Type")
end
Vehicle.init = Utils.appendedFunction(Vehicle.init, TireManager.injVehicleInit)

g_workshopScreen = WorkshopScreen.createFromExistingGui(g_workshopScreen, "WorkshopScreen")

addModEventListener(TireManager)