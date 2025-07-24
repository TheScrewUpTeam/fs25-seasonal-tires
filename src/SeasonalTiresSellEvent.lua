StSellEvent = {}
local StSellEvent_mt = Class(StSellEvent, Event)
InitEventClass(StSellEvent, "StSellEvent")

function StSellEvent.emptyNew()
    return Event.new(StSellEvent_mt)
end

function StSellEvent.new(vehicle, setId)
    local self = StSellEvent.emptyNew()
    self.vehicle = vehicle
    self.setId = setId
    return self
end

function StSellEvent.readStream(self, streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.setId = streamReadString(streamId)
    self:run(connection)
end

function StSellEvent.writeStream(self, streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.setId)
end

function StSellEvent.run(self, connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(StSellEvent.new(self.vehicle, self.setId), nil, nil, self.vehicle)
    end
    -- Actual sell logic
    if self.vehicle.isServer then
        local price = TireManager.getTireSetSellPrice(self.vehicle, self.setId)
        g_currentMission:addMoney(price, self.vehicle:getOwnerFarmId(), MoneyType.VEHICLE_REPAIR, true, true)
    end
    TireStorage.removeFromStorage(self.vehicle, self.setId)
    -- Optionally update UI or state
end 