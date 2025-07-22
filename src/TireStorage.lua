TireStorage = {}
local TireStorage_mt = {}
TireStorage_mt.__index = TireStorage

local PRINT_PREFIX = "[SeasonalTiresMod] "

-- Static wrapper functions for TireStorage instance methods
function TireStorage.getStoredByVehicle(vehicle)
    return g_farmManager:getFarmById(vehicle:getOwnerFarmId()).storage:igetStoredByVehicle(vehicle)
end

function TireStorage.getStoredBySetId(vehicle, setId)
    return g_farmManager:getFarmById(vehicle:getOwnerFarmId()).storage:igetStoredBySetId(vehicle, setId)
end

function TireStorage.getStoredByType(vehicle, tireType)
    return g_farmManager:getFarmById(vehicle:getOwnerFarmId()).storage:igetStoredByType(vehicle, tireType)
end

function TireStorage.removeFromStorage(vehicle, setId)
    return g_farmManager:getFarmById(vehicle:getOwnerFarmId()).storage:iremoveFromStorage(vehicle, setId)
end

function TireStorage.addToStoreage(vehicle, tireType, wear)
    return g_farmManager:getFarmById(vehicle:getOwnerFarmId()).storage:iaddToStoreage(vehicle, tireType, wear)
end

function TireStorage.swapTires(vehicle, setId)
    return g_farmManager:getFarmById(vehicle:getOwnerFarmId()).storage:iswapTires(vehicle, setId)
end

function TireStorage.buyTires(vehicle, tireType)
    return g_farmManager:getFarmById(vehicle:getOwnerFarmId()).storage:ibuyTires(vehicle, tireType)
end

function TireStorage.getVehicleIndex(vehicle)
    if vehicle == nil or vehicle.configFileNameClean == nil then
        return nil
    end
    return vehicle.configFileNameClean
end

function TireStorage:igetStoredByVehicle(vehicle)
   return self.tireStorage[TireStorage.getVehicleIndex(vehicle)] or {} 
end

function TireStorage:igetStoredBySetId(vehicle, setId)
    local sets = self.tireStorage[TireStorage.getVehicleIndex(vehicle)]

    for _, set in ipairs(sets) do
        if set.setId == setId then
            return set
        end
    end
end

function TireStorage:igetStoredByType(vehicle, tireType)
    local results = {}

    if vehicle == nil or tireType == nil then
        return results
    end

    local vehicleModelId = TireStorage.getVehicleIndex(vehicle)
    local sets = self.tireStorage[vehicleModelId]

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

function TireStorage:iremoveFromStorage(vehicle, setId)
    local vehicleModelId = TireStorage.getVehicleIndex(vehicle)
    for i, set in ipairs(self.tireStorage[vehicleModelId]) do
        if set.setId == setId then
            table.remove(self.tireStorage[vehicleModelId], i)
            return
        end
    end
    print(PRINT_PREFIX .. string.format("Tire set '%s' not found in storage for vehicle '%s'", setId, vehicleModelId))
end

function TireStorage:iaddToStoreage(vehicle, tireType, wear)
    local vehicleModelId = TireStorage.getVehicleIndex(vehicle)
    -- Ensure storage table exists
    self.tireStorage[vehicleModelId] = self.tireStorage[vehicleModelId] or {}
    
    -- Create a new tire set
    local newSet = {
        tireType = tireType,
        wear = wear or 0.0,  -- Default to brand new if not specified
        setId = "set" .. #self.tireStorage[vehicleModelId] + 1  -- Simple ID generation
    }
    
    -- Add the new set to storage
    table.insert(self.tireStorage[vehicleModelId], newSet)
end

function TireStorage:iswapTires(vehicle, setId) 
    local storedSet = self:igetStoredBySetId(vehicle, setId)
    if not storedSet then
        print(PRINT_PREFIX .. "No stored tire set found with ID: " .. tostring(setId))
        return
    end

    -- Remove the set from storage
    self:iremoveFromStorage(vehicle, setId)

    -- Add the old tires to storage
    self:iaddToStoreage(vehicle, TireManager.getTireType(vehicle), TireManager.getTireWear(vehicle))

    -- Set the tire type on the vehicle
    TireManager.setTireType(vehicle, storedSet.tireType)
    TireManager.setTireWear(vehicle, storedSet.wear)
end

function TireStorage:ibuyTires(vehicle, tireType)
    local vehicleModelId = TireStorage.getVehicleIndex(vehicle)
    -- Ensure storage table exists
    if vehicleModelId ~= nil and self.tireStorage[vehicleModelId] == nil then
        self.tireStorage[vehicleModelId] = {}
    end
    -- Add the new tire set
    local setId = "set" .. (#self.tireStorage[vehicleModelId] + 1)
    table.insert(self.tireStorage[vehicleModelId], {
        tireType = tireType,
        wear = 0.0,
        setId = setId
    })
    return setId
end

-- =============================================== Save/Load/Inint ===============================================

function TireStorage.new()
    local self = {}
    setmetatable(self, TireStorage_mt)

    self.tireStorage = {}

    return self
end

function TireStorage.injectNew(isServer, superFunc, isClient, spectator, customMt, ...)
    local farm = superFunc(isServer, customMt, ...)

    farm.storage = TireStorage.new()

    return farm
end
Farm.new = Utils.overwrittenFunction(Farm.new, TireStorage.injectNew)

function TireStorage:saveToXMLFile(xmlFile, key)
    if self.storage.tireStorage == nil then self.storage.tireStorage = {} end

    local index = 0
    for vehicleId, tireList in pairs(self.storage.tireStorage) do
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
Farm.saveToXMLFile = Utils.appendedFunction(Farm.saveToXMLFile, TireStorage.saveToXMLFile)

function TireStorage:loadStorageFromXML(superFunc, xmlFile, key)
    local returnValue = superFunc(self, xmlFile, key)

    self.storage.tireStorage = {}

    xmlFile:iterate(key .. ".storedTireSets", function (_, entryKey)
        local vehicleId = xmlFile:getString(entryKey .. "#vehicleId", "")

        if vehicleId ~= nil and vehicleId ~= "" then
            local tireData = {
                tireType = xmlFile:getString(entryKey .. "#tireType", "allSeason"),
                wear = xmlFile:getFloat(entryKey .. "#wear", 0),
                setId = xmlFile:getString(entryKey .. "#setId", "set0")
            }

            if self.storage.tireStorage[vehicleId] == nil then
                    self.storage.tireStorage[vehicleId] = {}
                end

            table.insert(self.storage.tireStorage[vehicleId], tireData)
        end
    end)
    return returnValue
end
Farm.loadFromXMLFile = Utils.overwrittenFunction(Farm.loadFromXMLFile, TireStorage.loadStorageFromXML)