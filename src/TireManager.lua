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

function Utils.splitByUnderscore(str)
    local result = {}
    for part in string.gmatch(str, "([^_]+)") do
        table.insert(result, part)
    end
    return result
end

local PRINT_PREFIX = "[SeasonalTiresMod] "

TireManager = {}
TireManager.surfaceConfig = {
    -- Soft, tilled, or loose soil; poor traction
    field  = 0.75,

    -- Asphalt/concrete; highest grip
    road   = 1.1,
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
        wearRate = 1.5
    },
    snow = {
        name = "Snow Tire",
        frictionModifier = 1.0,
        fieldBonus = -0.3,
        roadBonus = -0.1,
        snowBonus = 0.5,
        wearRate = 1.3
    },
    road = {
        name = "Road Tire",
        frictionModifier = 1.1,
        fieldBonus = -0.5,
        roadBonus = 0.5,
        snowBonus = -0.6,
        wearRate = 0.8
    }
}
TireManager.config = {
    mudMultiplier = 1.5,
    snowMultiplier = 2.0,
    rainPenalty = 0.8,
    frictionMin = 0.2,
    frictionMax = 2.5,
    maxDistanceForWear = 150000, -- meters
}
TireManager.tireStorage = {
    ["exampleVehicle"] = 
    {
        {
            tireType = "allSeason",
            wear = 0.5,
            setId = "set1"
        }
    }
}
TireManager.baseTirePrice = {
    allSeason = 800,
    mud = 1100,
    snow = 950,
    road = 1000
}

function TireManager.getTireType(vehicle)
    return vehicle.stTireType or "allSeason"
end

function TireManager.setTireType(vehicle, tireType)
    if TireManager.tireTypes[tireType] then
        vehicle.stTireType = tireType
        print(PRINT_PREFIX .. string.format("Tire type set to '%s' on %s", tireType, vehicle.configFileName or vehicle:getName() or tostring(vehicle)))
    else
        print(PRINT_PREFIX .. "Unknown tire type: " .. tostring(tireType))
    end
end

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
    -- print(PRINT_PREFIX .. string.format("Friction calc: base=%.2f, field=%.2f, grass=%.2f, road=%.2f, dirt=%.2f, track=%.2f, sand=%.2f, snow=%.2f, sum=%.2f, clamped=%.2f, tireType=%s, surface=%s, isSnow=%s, vehicle=%s",
    --     tireData.frictionModifier or 0, tireData.fieldBonus or 0, tireData.grassBonus or 0, tireData.roadBonus or 0, tireData.dirtBonus or 0, tireData.trackBonus or 0, tireData.sandBonus or 0, tireData.snowBonus or 0,
    --     friction, clamped, tireType, surface, tostring(isSnow), vehicle.getName and vehicle:getName() or tostring(vehicle)))
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
            name = TireManager.tireTypes[vehicle.stTireType] and TireManager.tireTypes[vehicle.stTireType].name or "All Season Tires",
            wear = TireManager.getTireWear(vehicle),
        }
        TireHUD:draw(vehicle, tireData)
    end
end

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
end
WheelPhysics.updateTireFriction = Utils.appendedFunction(WheelPhysics.updateTireFriction, TireManager.injPhysWheelUpdateTireFriction)

function TireManager.injOnLoad(vehicle, savegame)
    if not vehicle.stTireType then
        vehicle.stTireType = "allSeason"
    end
end
Vehicle.onLoad = Utils.appendedFunction(Vehicle.onLoad, TireManager.injOnLoad)

function TireManager.getTireWear(vehicle)
    if not vehicle or not vehicle.spec_wheels or not vehicle.spec_wheels.wheels then
        return 0.0 -- Default to new
    end

    local totalWear = 0

    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        if vehicle.uytHasTyres then
            -- UseYourTyres wear
            local perimeter = (6.28 * wheel.physics.radius)
	        local maxRevolutions = math.max(240000 / perimeter, 1)
	        local wear = math.clamp((wheel.uytTravelledDist / perimeter) / maxRevolutions, 0, 1)
            totalWear = totalWear + wear
        elseif wheel.stTireWear then
            -- Fallback: basic own wear system (normalized to 0..1)
            totalWear = totalWear + wheel.stTireWear
        else
            totalWear = totalWear + 0
        end
    end

    return totalWear / #vehicle.spec_wheels.wheels
end

function TireManager.setTireWear(vehicle, wear)
    if not vehicle or not vehicle.spec_wheels or not vehicle.spec_wheels.wheels then
        return
    end

    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        if vehicle.uytHasTyres and wheel.physics and wheel.physics.radius then
            -- UseYourTyres method (set distance based on desired wear)
            local perimeter = 6.28 * wheel.physics.radius
            local maxRevolutions = math.max(240000 / perimeter, 1)
            local targetDistance = wear * maxRevolutions * perimeter
            wheel.uytTravelledDist = targetDistance
        else
            -- Fallback: set simple wear value (0..1)
            wheel.stTireWear = math.clamp(wear, 0, 1)
        end
    end

    -- print(PRINT_PREFIX .. string.format("Set tire wear to %.2f on vehicle '%s'", wear, vehicle.configFileName or vehicle:getName() or tostring(vehicle)))
end

function TireManager.injUpdateWheelContact(physWheel)
    local vehicle = physWheel.vehicle
    if not vehicle or not vehicle.spec_wheels or not vehicle.spec_wheels.wheels then
        return
    end
    local wheel = physWheel.wheel
    if not vehicle or not wheel then return end

    -- Detect UYT once
    if TireManager._uytDetected == nil then
        TireManager._uytDetected = (vehicle.uytHasTyres ~= nil)
        print(PRINT_PREFIX .. "UseYourTyres " .. (TireManager._uytDetected and "detected" or "not detected") .. ", adapting...")
    end

    -- Tire type
    local tireDef = TireManager.tireTypes[wheel.stTireType or "allSeason"] or TireManager.tireTypes.allSeason
    local wearRate = tireDef.wearRate

    -- Time delta
    local now = getTimeSec()
    wheel._lastUpdateTime = wheel._lastUpdateTime or now
    local dt = now - wheel._lastUpdateTime
    if dt < 0.001 then return end
    wheel._lastUpdateTime = now

    -- Only apply if in contact
    if physWheel.contact ~= WheelContactType.GROUND and physWheel.contact ~= WheelContactType.OBJECT then return end

    -- Vehicle speed in m/s
    local speed = vehicle.lastSpeed * 1000
    local dist = speed * dt

    if TireManager._uytDetected then
        -- UYT installed — adjust its internal tracked distance
        wheel.uytTravelledDist = wheel.uytTravelledDist or 0
        wheel.uytTravelledDist = wheel.uytTravelledDist + dist * (wearRate - 1)

        -- Optional debug
        -- print(PRINT_PREFIX .. ("Adjusted UYT distance by %.2fm (rate %.2f)"):format(dist * (wearRate - 1), wearRate))
    else
        -- No UYT — handle our own distance and wear
        wheel.stTireTravelled = (wheel.stTireTravelled or 0) + dist
        local wearPerMeter = 1 / TireManager.config.maxDistanceForWear
        wheel.stTireWear = math.min((wheel.stTireWear or 0) + dist * wearPerMeter * wearRate, 1.0)

        -- Optional debug
        -- print(PRINT_PREFIX .. ("Own wear logic: Distance %.1fm, Wear %.2f"):format(wheel.stTireTravelled, wheel.stTireWear))
    end
end
WheelPhysics.updateContact = Utils.appendedFunction(WheelPhysics.updateContact, TireManager.injUpdateWheelContact)


-- =================================== Console Commands =======================================================

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

-- =================================== Tire Storage =======================================================

function TireManager.getStoredByVehicle(vehicle)
   return TireManager.tireStorage[vehicle.configFileNameClean] or {} 
end

function TireManager.getStoredBySetId(vehicle, setId)
    local sets = TireManager.tireStorage[vehicle.configFileNameClean]

    for _, set in ipairs(sets) do
        if set.setId == setId then
            return set
        end
    end
end

function TireManager.getStoredByType(vehicle, tireType)
    local results = {}

    if vehicle == nil or tireType == nil then
        return results
    end

    local vehicleModelId = vehicle.configFileNameClean
    local sets = TireManager.tireStorage[vehicleModelId]

    if sets == nil then
        return results
    end

    for _, set in ipairs(sets) do
        if set.tireType == tireType then
            table.insert(results, set)
        end
    end

    return results
end

function TireManager.getTirePrice(wheel, tireType)
    if not wheel or wheel == nil or wheel.physics.radius == nil then
        return 0
    end
    local basePrice = TireManager.baseTirePrice[tireType]
    local price = basePrice * wheel.physics.radius
    return price
end

function TireManager.getTireSetPrice(vehicle, tireType)
    if not vehicle or not vehicle.spec_wheels or not vehicle.spec_wheels.wheels then
        return 0
    end
    local totalPrice = 0
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        totalPrice = totalPrice + TireManager.getTirePrice(wheel, tireType)
    end
    print(PRINT_PREFIX .. string.format("Total tire set price for %s: %d", tireType, totalPrice))
    return totalPrice
end

function TireManager.removeFromStorage(vehicle, setId)
    local vehicleModelId = vehicle.configFileNameClean
    for i, set in ipairs(TireManager.tireStorage[vehicleModelId]) do
        if set.setId == setId then
            table.remove(TireManager.tireStorage[vehicleModelId], i)
            print(PRINT_PREFIX .. string.format("Removed tire set '%s' from storage for vehicle '%s'", setId, vehicleModelId))
            return
        end
    end
    print(PRINT_PREFIX .. string.format("Tire set '%s' not found in storage for vehicle '%s'", setId, vehicleModelId))
end

function TireManager.addToStoreage(vehicle, tireType, wear)
    local vehicleModelId = vehicle.configFileNameClean
    -- Ensure storage table exists
    TireManager.tireStorage[vehicleModelId] = TireManager.tireStorage[vehicleModelId] or {}
    
    -- Create a new tire set
    local newSet = {
        tireType = tireType,
        wear = wear or 0.0,  -- Default to brand new if not specified
        setId = "set" .. #TireManager.tireStorage[vehicleModelId] + 1  -- Simple ID generation
    }
    
    -- Add the new set to storage
    table.insert(TireManager.tireStorage[vehicleModelId], newSet)
    print(PRINT_PREFIX .. string.format("Added new tire set '%s' with wear %.2f for vehicle '%s'", tireType, wear or 0.0, vehicleModelId))
end

function TireManager.swapTires(vehicle, setId) 
    local storedSet = TireManager.getStoredBySetId(vehicle, setId)
    if not storedSet then
        print(PRINT_PREFIX .. "No stored tire set found with ID: " .. tostring(setId))
        return
    end

    -- Remove the set from storage
    TireManager.removeFromStorage(vehicle, setId)

    -- Add the old tires to storage
    TireManager.addToStoreage(vehicle, TireManager.getTireType(vehicle), TireManager.getTireWear(vehicle))

    -- Set the tire type on the vehicle
    TireManager.setTireType(vehicle, storedSet.tireType)
    TireManager.setTireWear(vehicle, storedSet.wear)

    print(PRINT_PREFIX .. string.format("Swapped tires to '%s' with wear %.2f on vehicle '%s'", storedSet.tireType, TireManager.getTireWear(vehicle), vehicle.configFileNameClean))
end

-- =================================== Change Tires =======================================================

function TireManager.buyTires(vehicle, tireType)
    local vehicleModelId = vehicle.configFileNameClean
    -- Ensure storage table exists
    if TireManager.tireStorage[vehicleModelId] == nil then
        TireManager.tireStorage[vehicleModelId] = {}
    end
    -- Add the new tire set
    local setId = "set" .. (#TireManager.tireStorage[vehicleModelId] + 1)
    table.insert(TireManager.tireStorage[vehicleModelId], {
        tireType = tireType,
        wear = 0.0,
        setId = setId
    })
    print(PRINT_PREFIX .. string.format("Bought new set of '%s' tires for vehicle model '%s'", tireType, vehicleModelId))
    return setId
end

function TireManager.onReplaceTyresCallback(screen)
    print(PRINT_PREFIX .. "onReplaceTyresCallback called")

    local storedTires = TireManager.getStoredByVehicle(screen.vehicle)

    local tireKeys = {}
    local options = {}

    -- Add current set first
    local current = TireManager.tireTypes[TireManager.getTireType(screen.vehicle)]
    table.insert(options, string.format("%s (Installed)", current.name))
    table.insert(tireKeys, "current")

    -- Add all stored tires
    for _, stored in pairs(storedTires) do 
        local setData = TireManager.tireTypes[stored.tireType]
        local optionName = string.format("%s (Owned %d%%)", setData.name, (1 - stored.wear) * 100)
        table.insert(options, optionName)
        table.insert(tireKeys, "stored_" .. stored.setId)
    end

    -- Add all new tires
    for tireKey, tireData in pairs(TireManager.tireTypes) do
        local price = TireManager.getTireSetPrice(screen.vehicle, tireKey)
        local priceStr = g_i18n:formatMoney(price, 0, true, true)
        local option = string.format("%s (Buy for %s)", tireData.name, priceStr)
        table.insert(tireKeys, "new_" .. tireKey)
        table.insert(options, option)
    end

	OptionDialog.show(function (result)
        if result > 0 then
            g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.YES)
            local tireType = tireKeys[result]
            print(PRINT_PREFIX ..  string.format(" Selected tire: %d, %s", result, tireType))
            
            -- Current set - do nothing
            if tireType == "current" then
                return true
            end
            local parts = Utils.splitByUnderscore(tireType)
            print(PRINT_PREFIX ..  string.format("Need to: %s, %s", parts[1], parts[2]))
            
            -- Ownded set - just swap
            if parts[1] == "stored" then
                -- Use existing stored tire set
                local setId = parts[2]
                TireManager.swapTires(screen.vehicle, setId)
            end

            local function onAgreedBuyTiresCallback(screen, isYes)
                if isYes then
                    local tyresPrice =  TireManager.getTireSetPrice(screen.vehicle, parts[2])
                    if g_currentMission:getMoney() < tyresPrice then
                        InfoDialog.show(g_i18n:getText("shop_messageNotEnoughMoneyToBuy"))
                        return
                    end

                    g_currentMission:addMoney(-tyresPrice, screen.vehicle:getOwnerFarmId(), MoneyType.VEHICLE_REPAIR, true, true)
                    local setId = TireManager.buyTires(screen.vehicle, parts[2])
                    TireManager.swapTires(screen.vehicle, setId)
                    -- g_client:getServerConnection():sendEvent(UytReplaceEvent.new(screen.vehicle, tyresPrice))
                end
            end
            
            -- New tire - buy and set
            if parts[1] == "new" then
                local dialogString = string.format("Buy new set of tires for %s", g_i18n:formatMoney(TireManager.getTireSetPrice(screen.vehicle, parts[2]), 0, true, true))
	            local dialogSound = GuiSoundPlayer.SOUND_SAMPLES.CONFIG_WRENCH
                YesNoDialog.show(onAgreedBuyTiresCallback, screen, dialogString, nil, nil, nil, nil, dialogSound)
            end
        else
            -- g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.ERROR)
        end
    end, "Wisely select the most appropriate tire set for current weather conditions and planned work", "Select tires set", options, defaultIndex)
	return true
end

function TireManager.injWokshopScreenSetVehicle(screen, vehicle)
	if screen.tmsButton == nil then
		return
	end

	screen.tmsButton:setVisible(vehicle ~= nil and vehicle.tmsTireType == true)
	
	if vehicle == nil then
		screen.tmsButton:setText("Change tires")
		screen.tmsButton:setDisabled(true)
	else
		screen.tmsButton:setText(string.format("%s", "Change tires"))
		screen.tmsButton:setDisabled(false)
	end
end
WorkshopScreen.setVehicle = Utils.appendedFunction(WorkshopScreen.setVehicle, TireManager.injWokshopScreenSetVehicle)

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
		tmsButton:setText(string.format("%s", "Change tires"))
		screen.tmsBtn = tmsButton
		
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
	if vehicle.spec_wheels == nil or vehicle.stTireType == nil then
		return
	end
    print(PRINT_PREFIX .. "Save injection...")
	
    local vehicleKey = string.format("%s#tmsTireType", saveKey)
    xmlFile:setValue(vehicleKey, vehicle.stTireType)

	for wheelIdx, wheel in ipairs(vehicle.spec_wheels.wheels) do
		local wheelDistanceKey = string.format("%s.wheel(%d)#stTireTravelled", saveKey, wheelIdx - 1)
		xmlFile:setValue(wheelDistanceKey, wheel.stTireTravelled or 0)
        local wheelWearKey = string.format("%s.wheel(%d)#stTireWear", saveKey, wheelIdx - 1)
        xmlFile:setValue(wheelWearKey, wheel.stTireWear or 0)
	end

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

    if vehicle.isServer then
		local isSavegameLoad = (savegame.xmlFile.filename ~= "")
		for wheelIdx, wheel in ipairs(vehicle.spec_wheels.wheels) do
			local wheelDistanceKey = string.format("%s.wheels.wheel(%d)#stTireTravelled", savegame.key, wheelIdx - 1)
			local travelDist = savegame.xmlFile:getValue(wheelDistanceKey)
			if travelDist ~= nil and isSavegameLoad then
				wheel.stTireTravelled = travelDist
			else
				wheel.stTireTravelled = 0
			end
			local wheelWearKey = string.format("%s.wheels.wheel(%d)#stTireWear", savegame.key, wheelIdx - 1)
			local wear = savegame.xmlFile:getValue(wheelWearKey)
			if wear ~= nil and isSavegameLoad then
				wheel.stTireWear = wear
			else
				wheel.stTireWear = 0
			end
		end
	end

    print(PRINT_PREFIX .. "Loaded from ", vehicleKey)
end
Wheels.onLoadFinished = Utils.appendedFunction(Wheels.onLoadFinished, TireManager.injWheelsOnLoadFinished)

function TireManager:saveStorageToXml(xmlFile, key)
    if TireManager.tireStorage == nil then TireManager.tireStorage = {} end

    local index = 0
    for vehicleId, tireList in pairs(TireManager.tireStorage) do
        for _, data in ipairs(tireList) do
            local entryKey = string.format("%s.storedTireSets(%d)", key, index)
            xmlFile:setString(entryKey .. "#vehicleId", vehicleId)
            xmlFile:setString(entryKey .. "#tireType", data.tireType)
            xmlFile:setFloat(entryKey .. "#wear", data.wear)
            xmlFile:setString(entryKey .. "#setId", data.setId)
            index = index + 1
        end
    end
end
Farm.saveToXMLFile = Utils.appendedFunction(Farm.saveToXMLFile, TireManager.saveStorageToXml)

function TireManager:loadStorageFromXML(superFunc, xmlFile, key)
    print(PRINT_PREFIX .. "TireManager:loadStorageFromXML")

    local returnValue = superFunc(self, xmlFile, key)

    TireManager.tireStorage = {}

    xmlFile:iterate(key .. ".storedTireSets", function (_, entryKey)
        local vehicleId = xmlFile:getString(entryKey .. "#vehicleId", "")

        if vehicleId ~= nil and vehicleId ~= "" then
            local tireData = {
                tireType = xmlFile:getString(entryKey .. "#tireType", "allSeason"),
                wear = xmlFile:getFloat(entryKey .. "#wear", 0),
                setId = xmlFile:getString(entryKey .. "#setId", "set0")
            }

            if TireManager.tireStorage[vehicleId] == nil then
                    TireManager.tireStorage[vehicleId] = {}
                end

            table.insert(TireManager.tireStorage[vehicleId], tireData)
        end
    end)
    return returnValue
end
Farm.loadFromXMLFile = Utils.overwrittenFunction(Farm.loadFromXMLFile, TireManager.loadStorageFromXML)

function TireManager.injVehicleInit()
    print(PRINT_PREFIX .. "Register save path")
	Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?).wheels#tmsTireType", "Season Tires Mod Tire Type")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).wheels.wheel(?)#stTireTravelled", "Wheel travelled distance")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).wheels.wheel(?)#stTireWear", "Wheel wear level (0..1)")
end
Vehicle.init = Utils.appendedFunction(Vehicle.init, TireManager.injVehicleInit)

g_workshopScreen = WorkshopScreen.createFromExistingGui(g_workshopScreen, "WorkshopScreen")

addModEventListener(TireManager)