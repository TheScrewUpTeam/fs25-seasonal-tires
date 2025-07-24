StBuyEvent = {}
local StBuyEvent_mt = Class(StBuyEvent, Event)
InitEventClass(StBuyEvent, "StBuyEvent")

function StBuyEvent.emptyNew()
    return Event.new(StBuyEvent_mt)
end

function StBuyEvent.new(vehicle, tireType)
    local self = StBuyEvent.emptyNew()
    self.vehicle = vehicle
    self.tireType = tireType
    return self
end

function StBuyEvent.readStream(self, streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.tireType = streamReadString(streamId)
    self:run(connection)
end

function StBuyEvent.writeStream(self, streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.tireType)
end

function StBuyEvent.run(self, connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(self)
    end
    -- Actual buy logic
    if self.vehicle.isServer then
        local price = TireManager.getTireSetPrice(self.vehicle, self.tireType)
        g_currentMission:addMoney(-price, self.vehicle:getOwnerFarmId(), MoneyType.VEHICLE_REPAIR, true, true)
    end
    local setId = TireStorage.buyTires(self.vehicle, self.tireType)
    TireStorage.swapTires(self.vehicle, setId)
end 