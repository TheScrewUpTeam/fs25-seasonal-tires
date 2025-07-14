TireManager = {
    -- Define supported tire types and their behavior modifiers
    tireTypes = {
        allSeason = {
            name = "All-Season",
            frictionModifier = 1.0,
            mudBonus = 0.0,
            snowBonus = 0.0,
            roadBonus = 0.0,
            wearRate = 1.0
        },
        mud = {
            name = "Mud Tire",
            frictionModifier = 1.0,
            mudBonus = 0.4,
            snowBonus = -0.2,
            roadBonus = -0.1,
            wearRate = 1.2
        },
        snow = {
            name = "Snow Tire",
            frictionModifier = 1.0,
            mudBonus = -0.3,
            snowBonus = 0.5,
            roadBonus = -0.1,
            wearRate = 1.1
        },
        road = {
            name = "Road Tire",
            frictionModifier = 1.1,
            mudBonus = -0.5,
            snowBonus = -0.6,
            roadBonus = 0.5,
            wearRate = 0.9
        },
        flotation = {
            name = "Flotation Tire",
            frictionModifier = 0.95,
            mudBonus = 0.3,
            snowBonus = 0.2,
            roadBonus = -0.2,
            wearRate = 1.3
        }
    }
}

function TireManager.prerequisitesPresent(specializations)
    return true
end

function TireManager.initSpecialization()
    print("[TireManager] Specialization initialized.")
end

function TireManager.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", TireManager)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", TireManager)
end

function TireManager:onLoad(savegame)
    print("[TireManager] Loaded for: " .. self:getName())
    -- Add a tire type field to each vehicle using this specialization
    local spec = self.spec_tireManager or {}
    spec.tireType = "allSeason" -- default for now

    self.spec_tireManager = spec
end

function TireManager:getTireTypeData()
    local spec = self.spec_tireManager
    if spec and spec.tireType then
        return TireManager.tireTypes[spec.tireType] or TireManager.tireTypes["allSeason"]
    end
    return TireManager.tireTypes["allSeason"]
end

function TireManager:onUpdateTick(dt)
    if self.tireManagerDebugTimer == nil then
        self.tireManagerDebugTimer = 0
    end

    self.tireManagerDebugTimer = self.tireManagerDebugTimer + dt
    if self.tireManagerDebugTimer > 1000 then
        self.tireManagerDebugTimer = 0
        local tireData = self:getTireTypeData()
        print(string.format("[TireManager] Vehicle %s is using %s tires", self:getName(), tireData.name))
    end
end

local function addTireManagerToAllVehicles()
    for typeName, vehicleType in pairs(g_vehicleTypeManager.types) do
        if vehicleType ~= nil and vehicleType.specializations ~= nil then
            -- Avoid adding twice
            if not SpecializationUtil.hasSpecialization(TireManager, vehicleType.specializations) then
                g_vehicleTypeManager:addSpecialization(typeName, "tireManager")
            end
        end
    end
    print("[TireManager] Added to all vehicle types.")
end

addTireManagerToAllVehicles()