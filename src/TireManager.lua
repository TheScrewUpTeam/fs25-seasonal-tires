--
-- TireManager (injection approach)
--

source(g_currentModDirectory .. "src/TireHUD.lua")
source(g_currentModDirectory .. "src/TireStorage.lua")
source(g_currentModDirectory .. "src/SeasonalTiresSwapEvent.lua")
source(g_currentModDirectory .. "src/SeasonalTiresBuyEvent.lua")
source(g_currentModDirectory .. "src/SeasonalTiresSellEvent.lua")

if Utils == nil then Utils = {} end

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
        rainBonus = -0.1,
        snowBonus = -0.3,
        softnessBonus = -0.3,
        mudCluggPenalty = 0.2,

        fieldBonus = -0.4,
        roadBonus = 0.0,
        wearRate = 1.0,
    },
    mud = {
        name = g_i18n:getText("item_tmsTireMud"),
        frictionModifier = 1.0,
        rainBonus = 0,
        snowBonus = -0.2,
        softnessBonus = 1,
        tempPenalty = {
            suitableMin = 0,
            suitableMax = 50,
            penaltyFactor = 0.01,
        },

        fieldBonus = 0.4,
        roadBonus = -0.1,
        wearRate = 1.5,
    },
    snow = {
        name = g_i18n:getText("item_tmsTireSnow"),
        frictionModifier = 1.0,
        rainBonus = -0.1,
        snowBonus = -0.05,
        softnessBonus = 0.0,
        mudCluggPenalty = 0.1,
        tempPenalty = {
            suitableMin = -50,
            suitableMax = 2,
            penaltyFactor = 0.02,
        },

        fieldBonus = -0.3,
        roadBonus = -0.1,
        wearRate = 1.3,
    },
    road = {
        name = g_i18n:getText("item_tmsTireRoad"),
        frictionModifier = 1.0,
        rainBonus = -0.1,
        snowBonus = -0.6,
        softnessBonus = -0.7,
        mudCluggPenalty = 0.3,
        tempPenalty = {
            suitableMin = -10,
            suitableMax = 20,
            penaltyFactor = 0.01,
        }, 

        fieldBonus = -0.5,
        roadBonus = 0.5,
        wearRate = 0.8,
    }
}
TireManager.config = {
    mudMultiplier = 1.5,
    snowMultiplier = 2.0,
    rainPenalty = 0.8,
    frictionMin = 0.2,
    frictionMax = 1.6,
    maxDistanceForWear = 150000, -- meters
}
TireManager.baseTirePrice = {
    allSeason = 800,
    mud = 1100,
    snow = 950,
    road = 1000
}

-- ================================== Network Integration ==================================

function TireManager.injOnReadStream(vehicle, streamId, connection)
    if connection.isServer or not TireManager.isWheelsVehicle(vehicle) then
        return
    end

    -- Read tire type
    local tireType = streamReadString(streamId)
    if tireType and TireManager.tireTypes[tireType] then
        vehicle.stTireType = tireType
    else
        vehicle.stTireType = "allSeason" -- Default to all-season if unknown
    end

    -- Read wheel distances and wear
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        wheel.stTireTravelled = streamReadFloat32(streamId) or 0.0
        wheel.stTireWear = streamReadFloat32(streamId) or 0.0
    end
end
Wheels.onReadStream = Utils.appendedFunction(Wheels.onReadStream, TireManager.injOnReadStream)

function TireManager.injOnWriteStream(vehicle, streamId, connection)
    if not connection.isServer or not TireManager.isWheelsVehicle(vehicle) then
        return
    end

    -- Write tire type
    streamWriteString(streamId, vehicle.stTireType or "allSeason")

    -- Write wheel distances and wear
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        streamWriteFloat32(streamId, wheel.stTireTravelled or 0.0)
        streamWriteFloat32(streamId, wheel.stTireWear or 0.0)
    end
end
Wheels.onWriteStream = Utils.appendedFunction(Wheels.onWriteStream, TireManager.injOnWriteStream)

function TireManager.injOnWriteStreamUpdate(vehicle, streamId, connection)
    if not connection.isServer or not TireManager.isWheelsVehicle(vehicle) then
        return
    end

    -- Write wheel distances and wear
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        streamWriteFloat32(streamId, wheel.stTireTravelled or 0.0)
        streamWriteFloat32(streamId, wheel.stTireWear or 0.0)
    end
end
Wheels.onWriteUpdateStream = Utils.appendedFunction(Wheels.onWriteUpdateStream, TireManager.injOnWriteStreamUpdate)

function TireManager.injOnReadStreamUpdate(vehicle, streamId, _, connection)
    if connection.isServer or not TireManager.isWheelsVehicle(vehicle) then
        return
    end

    -- Read wheel distances and wear
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        wheel.stTireTravelled = streamReadFloat32(streamId) or 0.0
        wheel.stTireWear = streamReadFloat32(streamId) or 0.0
    end
end
Wheels.onReadUpdateStream = Utils.appendedFunction(Wheels.onReadUpdateStream, TireManager.injOnReadStreamUpdate)

-- ================================================= Main Features ==================================

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
    local storedSet = TireStorage.getStoredBySetId(vehicle, setId)
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
            name = TireManager.tireTypes[vehicle.stTireType or "allSeason"].name,
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

function TireManager.calculateFrictionByDepth(tireData, depth)
    local base = tireData.frictionModifier
    local slope = tireData.softnessBonus
    return base + slope * depth
end

function TireManager.getTemperaturePenalty(temperature, tempPenalty)
    if not tempPenalty then
        return 0
    end

    local penalty = 0

    if temperature < tempPenalty.suitableMin then
        penalty = tempPenalty.suitableMin - temperature
    elseif temperature > tempPenalty.suitableMax then
        penalty = temperature - tempPenalty.suitableMax
    end

    if penalty > 0 then
        local factor = penalty * tempPenalty.penaltyFactor
        return math.abs(factor)
    end

    return 0
end

function TireManager.getEffectiveFriction(vehicle, physWheel)
    local tireType = TireManager.getTireType(vehicle)
    local tireData = TireManager.tireTypes[tireType]
    if not tireData then
        return 1.0 -- Default friction if unknown type
    end
    local groundDepth = physWheel.groundDepth or 0
    local env = g_currentMission.environment
    local temperature = env.weather.temperatureUpdater:getTemperatureAtTime(
        g_currentMission.environment.dayTime
    )

    -- Base friction depending on tire and softness
    local baseFriction = TireManager.calculateFrictionByDepth(tireData, groundDepth)
    local snowBonus = 0
    local tempPenalty = 0
    local rainPenalty = 0
    local mudCluggPenalty = 0
    local wearFactor = math.min(TireManager.getTireWear(vehicle) * 3, 3)

    -- Apply snow bonus if applicable
    if physWheel.hasSnowContact then
        snowBonus = (tireData.snowBonus or 0)
    end

    if env.weather:getIsRaining() then
        rainPenalty = tireData.rainBonus
    end

     -- Apply temperature penalty if defined
    if tireData.tempPenalty then
        tempPenalty = TireManager.getTemperaturePenalty(temperature, tireData.tempPenalty)
    end

    -- Apply mud clugg pennalty if applicable
    if tireData.mudCluggPenalty then 
        mudCluggPenalty = tireData.mudCluggPenalty * physWheel.dirtAmount
    end

    local resultFriction = baseFriction + (snowBonus + rainPenalty - tempPenalty - mudCluggPenalty) * wearFactor

    -- Clamp to config range
    local clamped = math.max(TireManager.config.frictionMin, math.min(TireManager.config.frictionMax, resultFriction))

    return clamped
end

function TireManager.injPhysWheelUpdateTireFriction(physWheel)
    local vehicle = physWheel.vehicle
    if not TireManager.isWheelsVehicle(vehicle) then return end
    if not vehicle.isServer or not vehicle.isAddedToPhysics then return end
    local frictionMod = TireManager.getEffectiveFriction(vehicle, physWheel)
    -- Use the game's base friction scale, but modulate it with our value
    local frictionScale = frictionMod --(physWheel.frictionScale or 1) * (physWheel.tireGroundFrictionCoeff or 1) * frictionMod
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

function TireManager.getTireWearRate(wheel)
    local tireDef = TireManager.tireTypes[TireManager.getTireType(wheel.vehicle)]
    local baseWearRate = tireDef.wearRate
    local groundDepth = wheel.physics.groundDepth or 0
    local softnessBonus = tireDef.softnessBonus
    local temperature = g_currentMission.environment.weather.temperatureUpdater:getTemperatureAtTime(
        g_currentMission.environment.dayTime
    )

    local hardnessPenalty = 0
    local tempPenalty = 0
    if tireDef.tempPenalty then
        tempPenalty = TireManager.getTemperaturePenalty(temperature, tireDef.tempPenalty)
    end
    if softnessBonus > 0 then
        hardnessPenalty = math.abs((1 - groundDepth) * softnessBonus)
    end

    return baseWearRate + hardnessPenalty + tempPenalty
end

function TireManager.injUpdateWheelContact(physWheel)
    local vehicle = physWheel.vehicle
    if not vehicle or not TireManager.isWheelsVehicle(vehicle) then
        return
    end
    local wheel = physWheel.wheel
    if not vehicle or not wheel then return end

    TireManager.injPhysWheelUpdateTireFriction(physWheel)

    -- Detect UYT once
    if TireManager._uytDetected == nil then
        TireManager._uytDetected = (vehicle.uytHasTyres ~= nil)
    end

    local wearRate = TireManager.getTireWearRate(wheel)
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

-- =================================== Change Tires =======================================================

function TireManager.onReplaceTyresCallback(screen)
    if (TireManager.isWheelsVehicle(screen.vehicle) == false) then
        return false
    end

    local storedTires = TireStorage.getStoredByVehicle(screen.vehicle)

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
                -- TireManager.swapTires(screen.vehicle, setId)
                g_client:getServerConnection():sendEvent(StSwapEvent.new(screen.vehicle, setId))
            end

            local function onAgreedBuyTiresCallback(screen, isYes)
                if isYes then
                    local tyresPrice =  TireManager.getTireSetPrice(screen.vehicle, parts[2])
                    if g_currentMission:getMoney() < tyresPrice then
                        InfoDialog.show(g_i18n:getText("shop_messageNotEnoughMoneyToBuy"))
                        return
                    end

                    g_client:getServerConnection():sendEvent(StBuyEvent.new(screen.vehicle, parts[2]))
                    TireManager.injWokshopScreenSetVehicle(screen, screen.vehicle) -- Refresh the vehicle state
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

    local storedTires = TireStorage.getStoredByVehicle(screen.vehicle)
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
            
            local stored = TireStorage.getStoredBySetId(screen.vehicle, setId)
            local setData = TireManager.tireTypes[stored.tireType]

            local function onAgreedSellTiresCallback(screen, isYes)
                if isYes then
                    
                    g_client:getServerConnection():sendEvent(StSellEvent.new(screen.vehicle, setId))
                    TireManager.injWokshopScreenSetVehicle(screen, screen.vehicle) -- Refresh the vehicle state
                end
            end
            
            local price = TireManager.getTireSetSellPrice(screen.vehicle, setId)
            local dialogString = string.format(g_i18n:getText("ui_tmsTireSellConfirmation"), setData.name, g_i18n:formatMoney(price, 0, true, true))
            local dialogSound = GuiSoundPlayer.SOUND_SAMPLES.CONFIG_WRENCH
            YesNoDialog.show(onAgreedSellTiresCallback, screen, dialogString, nil, nil, nil, nil, dialogSound)
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
        local stored = TireStorage.getStoredByVehicle(vehicle)
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
	if vehicle.spec_wheels == nil or savegame == nil then
		return
	end
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

function TireManager.injVehicleInit()
	Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?).wheels#tmsTireType", "Season Tires Mod Tire Type")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).wheels.wheel(?)#stTireTravelled", "Wheel travelled distance")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).wheels.wheel(?)#stTireWear", "Wheel wear level (0..1)")
end
Vehicle.init = Utils.appendedFunction(Vehicle.init, TireManager.injVehicleInit)

g_workshopScreen = WorkshopScreen.createFromExistingGui(g_workshopScreen, "WorkshopScreen")

addModEventListener(TireManager)