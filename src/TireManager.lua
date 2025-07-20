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
        name = g_i18n:getText("item_tmsTireAllSeasons"),
        frictionModifier = 1.0,
        fieldBonus = -0.4,
        roadBonus = 0.0,
        snowBonus = -0.4,
        wearRate = 1.0
    },
    mud = {
        name = g_i18n:getText("item_tmsTireMud"),
        frictionModifier = 1.0,
        fieldBonus = 0.4,
        roadBonus = -0.1,
        snowBonus = -0.2,
        wearRate = 1.5
    },
    snow = {
        name = g_i18n:getText("item_tmsTireSnow"),
        frictionModifier = 1.0,
        fieldBonus = -0.3,
        roadBonus = -0.1,
        snowBonus = 0.5,
        wearRate = 1.3
    },
    road = {
        name = g_i18n:getText("item_tmsTireRoad"),
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
    else
        print(PRINT_PREFIX .. "Unknown tire type: " .. tostring(tireType))
    end
end

function TireManager.isWheelsVehicle(vehicle)
    if not vehicle.spec_wheels or not vehicle.spec_wheels.wheels then
        return false
    end
    if not vehicle.spec_tireTracks or vehicle.spec_tireTracks.hasTireTrackNodes == false then
        return false
    end
    local visualWheelsCount = 0
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        if #wheel.visualWheels > 0 then
            visualWheelsCount = visualWheelsCount + 1
            break
        end
    end
    return visualWheelsCount > 0
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
    friction = friction * math.min(1 - TireManager.getTireWear(vehicle), .2) -- Apply wear factor

    -- Clamp to config range
    local clamped = math.max(TireManager.config.frictionMin, math.min(TireManager.config.frictionMax, friction))
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
    if vehicle and TireManager.isWheelsVehicle(vehicle) then
        local tireData = {
            name = TireManager.tireTypes[vehicle.stTireType].name,
            wear = TireManager.getTireWear(vehicle),
            type = vehicle.stTireType
        }
        TireHUD:draw(vehicle, tireData)
        -- Additional HUD for child vehicles
        local allVehiclesWithtires = {}
        local vehicles = vehicle.rootVehicle.childVehicles
        for _, subVehicle in ipairs(vehicles) do
            if TireManager.isWheelsVehicle(subVehicle) and subVehicle ~= vehicle then
                table.insert(allVehiclesWithtires, subVehicle)
            end
        end
        -- Only one child vehicle with tires
        if #allVehiclesWithtires == 1 then
            local subVehicle = allVehiclesWithtires[1]
            local addData = {
                name = TireManager.tireTypes[subVehicle.stTireType].name,
                wear = TireManager.getTireWear(subVehicle),
                type = subVehicle.stTireType
            }
            TireHUD:drawAdditional(subVehicle, addData)
        end
        if #allVehiclesWithtires > 1 then
            -- Multiple child vehicles with tires, draw additional HUD for each
            for _, subVehicle in ipairs(allVehiclesWithtires) do
                if vehicle.getIsSelected ~= nil and subVehicle:getIsSelected() then
                    local addData = {
                        name = TireManager.tireTypes[subVehicle.stTireType].name,
                        wear = TireManager.getTireWear(subVehicle),
                    }
                    TireHUD:drawAdditional(subVehicle, addData)
                end
            end
        end
    end
end

function TireManager.injPhysWheelUpdateTireFriction(physWheel)
    local vehicle = physWheel.vehicle
    if not TireManager.isWheelsVehicle(vehicle) then return end
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
    if not vehicle or not TireManager.isWheelsVehicle(vehicle) then
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
    if not vehicle or not TireManager.isWheelsVehicle(vehicle) then
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
end

function TireManager.injUpdateWheelContact(physWheel)
    local vehicle = physWheel.vehicle
    if not vehicle or not TireManager.isWheelsVehicle(vehicle) then
        return
    end
    local wheel = physWheel.wheel
    if not vehicle or not wheel then return end

    -- Detect UYT once
    if TireManager._uytDetected == nil then
        TireManager._uytDetected = (vehicle.uytHasTyres ~= nil)
    end

    -- Tire type
    local tireDef = TireManager.tireTypes[wheel.stTireType] or TireManager.tireTypes.allSeason
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
    else
        -- No UYT — handle our own distance and wear
        wheel.stTireTravelled = (wheel.stTireTravelled or 0) + dist
        local wearPerMeter = 1 / TireManager.config.maxDistanceForWear
        wheel.stTireWear = math.min((wheel.stTireWear or 0) + dist * wearPerMeter * wearRate, 1.0)
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
    end
    if not vehicle then
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
    return totalPrice
end

function TireManager.getTireSetSellPrice(vehicle, setId)
    local storedSet = TireManager.getStoredBySetId(vehicle, setId)
    if not storedSet then
        print(PRINT_PREFIX .. "No stored tire set found with ID: " .. tostring(setId))
        return 0
    end
    local tireType = storedSet.tireType
    local wear = storedSet.wear or 0.0
    local basePrice = 0
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        basePrice = basePrice + TireManager.getTirePrice(wheel, tireType)
    end
    local sellPrice = basePrice * (1 - wear) * 0.8 -- Adjust price based on wear
    return sellPrice
end

function TireManager.removeFromStorage(vehicle, setId)
    local vehicleModelId = vehicle.configFileNameClean
    for i, set in ipairs(TireManager.tireStorage[vehicleModelId]) do
        if set.setId == setId then
            table.remove(TireManager.tireStorage[vehicleModelId], i)
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
    return setId
end

function TireManager.onReplaceTyresCallback(screen)
    if (TireManager.isWheelsVehicle(screen.vehicle) == false) then
        return false
    end

    local storedTires = TireManager.getStoredByVehicle(screen.vehicle)

    local tireKeys = {}
    local options = {}

    -- Add current set first
    local current = TireManager.tireTypes[TireManager.getTireType(screen.vehicle)]
    table.insert(options, string.format(g_i18n:getText("ui_tmsTireInstalled"), current.name))
    table.insert(tireKeys, "current")

    -- Add all stored tires
    for _, stored in pairs(storedTires) do 
        local setData = TireManager.tireTypes[stored.tireType]
        local optionName = string.format(g_i18n:getText("ui_tmsTireOwned"), setData.name, (1 - stored.wear) * 100)
        table.insert(options, optionName)
        table.insert(tireKeys, "stored_" .. stored.setId)
    end

    -- Add all new tires
    for tireKey, tireData in pairs(TireManager.tireTypes) do
        local price = TireManager.getTireSetPrice(screen.vehicle, tireKey)
        local priceStr = g_i18n:formatMoney(price, 0, true, true)
        local option = string.format(g_i18n:getText("ui_tmsTireNew"), tireData.name, priceStr)
        table.insert(tireKeys, "new_" .. tireKey)
        table.insert(options, option)
    end

	OptionDialog.show(function (result)
        if result > 0 then
            g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.YES)
            local tireType = tireKeys[result]
            
            -- Current set - do nothing
            if tireType == "current" then
                return true
            end
            local parts = Utils.splitByUnderscore(tireType)
            
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
                local dialogString = string.format(g_i18n:getText("ui_tmsBuyNewTireConfirm"), g_i18n:formatMoney(TireManager.getTireSetPrice(screen.vehicle, parts[2]), 0, true, true))
	            local dialogSound = GuiSoundPlayer.SOUND_SAMPLES.CONFIG_WRENCH
                YesNoDialog.show(onAgreedBuyTiresCallback, screen, dialogString, nil, nil, nil, nil, dialogSound)
            end
        else
            -- g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.ERROR)
        end
    end, g_i18n:getText("ui_tmsSelectTireSet"), g_i18n:getText("ui_tmsTireReplacementDalogTitle"), options, defaultIndex)
	return true
end

function TireManager.onManageTiresCallback(screen)
    if (TireManager.isWheelsVehicle(screen.vehicle) == false) then
        return false
    end

    local storedTires = TireManager.getStoredByVehicle(screen.vehicle)
    if #storedTires == 0 then
        return false
    end

    local tireKeys = {}
    local options = {}
    -- Add all stored tires
    for _, stored in pairs(storedTires) do 
        local setData = TireManager.tireTypes[stored.tireType]
        local price = TireManager.getTireSetSellPrice(screen.vehicle, stored.setId)
        local priceStr = g_i18n:formatMoney(price, 0, true, true)
        local optionName = string.format(g_i18n:getText("ui_tmsSelectTireSetForSell"), setData.name, (1 - stored.wear) * 100, priceStr)
        table.insert(options, optionName)
        table.insert(tireKeys, stored.setId)
    end

    OptionDialog.show(function (result)
        if result > 0 then
            g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.YES)
            local setId = tireKeys[result]
            
            local stored = TireManager.getStoredBySetId(screen.vehicle, setId)
            local setData = TireManager.tireTypes[stored.tireType]

            local function onAgreedSellTiresCallback(screen, isYes)
                if isYes then
                    local tiresPrice =  TireManager.getTireSetSellPrice(screen.vehicle, setId)
                    
                    g_currentMission:addMoney(tiresPrice, screen.vehicle:getOwnerFarmId(), MoneyType.VEHICLE_REPAIR, true, true)
                    TireManager.removeFromStorage(screen.vehicle, setId)
                    g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.YES)
                    TireManager.injWokshopScreenSetVehicle(screen, screen.vehicle)
                    -- g_client:getServerConnection():sendEvent(UytReplaceEvent.new(screen.vehicle, tyresPrice))
                end
            end
            
            local price = TireManager.getTireSetSellPrice(screen.vehicle, setId)
            local dialogString = string.format(g_i18n:getText("ui_tmsTireSellConfirmation"), setData.name, g_i18n:formatMoney(price, 0, true, true))
            local dialogSound = GuiSoundPlayer.SOUND_SAMPLES.CONFIG_WRENCH
            YesNoDialog.show(onAgreedSellTiresCallback, screen, dialogString, nil, nil, nil, nil, dialogSound)
        else
            -- g_shopConfigScreen:playSample(GuiSoundPlayer.SOUND_SAMPLES.ERROR)
        end
    end, g_i18n:getText("ui_tmsSelectTireSetForSellDescription"), g_i18n:getText("ui_tmsSellTireSetDialogTitle"), options, defaultIndex)
	return true
end

function TireManager.injWokshopScreenSetVehicle(screen, vehicle)
    if screen.tmsBtn == nil or screen.tmsManageBtn == nil then
		return
	end

	screen.tmsBtn:setVisible(vehicle ~= nil)
    screen.tmsManageBtn:setVisible(vehicle ~= nil)

	if vehicle == nil or not TireManager.isWheelsVehicle(vehicle) then
		screen.tmsBtn:setDisabled(true)
        screen.tmsManageBtn:setDisabled(true)
	else
		screen.tmsBtn:setDisabled(false)
        local stored = TireManager.getStoredByVehicle(vehicle)
        if #stored > 0 then
            screen.tmsManageBtn:setText(string.format(g_i18n:getText("ui_tmsManageTiresButtonTrue"), #stored))
            screen.tmsManageBtn:setDisabled(false)
        else
            screen.tmsManageBtn:setText(g_i18n:getText("ui_tmsManageTiresButtonFalse"))
            screen.tmsManageBtn:setDisabled(true)
        end
	end
end
WorkshopScreen.setVehicle = Utils.appendedFunction(WorkshopScreen.setVehicle, TireManager.injWokshopScreenSetVehicle)

function TireManager.injWokshopScreenOnOpen(screen)
	if screen.tmsWorkshopInited == nil then

		-- Button
		local tmsButton = ButtonElement.new(screen.buttonsBox)
		tmsButton.name = "tmsChange"
		screen.buttonsBox:addElement(tmsButton)
		tmsButton:applyProfile("buttonActivate")
		tmsButton:setInputAction("TMS_CHANGE_TIRES")
		tmsButton.onClickCallback = function()
			TireManager.onReplaceTyresCallback(screen)
		end
		tmsButton:setText(g_i18n:getText("ui_tmsChangeTiresButton"))
		screen.tmsBtn = tmsButton

		-- Separator
		local tmsSep = BitmapElement.new(tmsButton)
		tmsSep.name = "separator"
		tmsButton:addElement(tmsSep)
		tmsSep:applyProfile("fs25_buttonBoxSeparator")

		-- Button
		local tmsManageButton = ButtonElement.new(screen.buttonsBox)
		tmsManageButton.name = "tmsManage"
		screen.buttonsBox:addElement(tmsManageButton)
		tmsManageButton:applyProfile("buttonActivate")
		tmsManageButton:setInputAction("TMS_MANAGE_TIRES")
		tmsManageButton.onClickCallback = function()
			TireManager.onManageTiresCallback(screen)
		end
		tmsManageButton:setText(string.format("%s", g_i18n:getText("ui_tmsManageTiresButtonFalse")))
		screen.tmsManageBtn = tmsManageButton

		-- Separator
		local tmsSep2 = BitmapElement.new(tmsManageButton)
		tmsSep2.name = "separator"
		tmsManageButton:addElement(tmsSep2)
		tmsSep2:applyProfile("fs25_buttonBoxSeparator")

		screen.tmsWorkshopInited = true
    end

	local _, eventId = g_inputBinding:registerActionEvent("TMS_CHANGE_TIRES", screen, TireManager.onReplaceTyresCallback, false, true, false, true)
	local _, manageEventId = g_inputBinding:registerActionEvent("TMS_MANAGE_TIRES", screen, TireManager.onManageTiresCallback, false, true, false, true)
	screen.tmsEventId = eventId
    screen.tmsManageEventId = manageEventId
    TireManager.injWokshopScreenSetVehicle(screen, screen.vehicle)
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
	if not TireManager.isWheelsVehicle(vehicle) then
		return
	end
	
    local vehicleKey = string.format("%s#tmsTireType", saveKey)
    xmlFile:setValue(vehicleKey, vehicle.stTireType)

	for wheelIdx, wheel in ipairs(vehicle.spec_wheels.wheels) do
		local wheelDistanceKey = string.format("%s.wheel(%d)#stTireTravelled", saveKey, wheelIdx - 1)
		xmlFile:setValue(wheelDistanceKey, wheel.stTireTravelled or 0)
        local wheelWearKey = string.format("%s.wheel(%d)#stTireWear", saveKey, wheelIdx - 1)
        xmlFile:setValue(wheelWearKey, wheel.stTireWear or 0)
	end

end
Wheels.saveToXMLFile = Utils.appendedFunction(Wheels.saveToXMLFile, TireManager.injWheelsSaveToXMLFile)

function TireManager.injWheelsOnLoadFinished(vehicle, savegame)
	if not TireManager.isWheelsVehicle(vehicle) then
		return
	end

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
	Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?).wheels#tmsTireType", "Season Tires Mod Tire Type")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).wheels.wheel(?)#stTireTravelled", "Wheel travelled distance")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).wheels.wheel(?)#stTireWear", "Wheel wear level (0..1)")
end
Vehicle.init = Utils.appendedFunction(Vehicle.init, TireManager.injVehicleInit)

g_workshopScreen = WorkshopScreen.createFromExistingGui(g_workshopScreen, "WorkshopScreen")

addModEventListener(TireManager)