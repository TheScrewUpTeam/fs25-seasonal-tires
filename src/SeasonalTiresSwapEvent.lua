StSwapEvent = {}
local StSwapEvent_mt = Class(StSwapEvent, Event)
InitEventClass(StSwapEvent, "StSwapEvent")

function StSwapEvent.emptyNew()
	return Event.new(StSwapEvent_mt)
end

function StSwapEvent.new(vehicle, setId)
	local self = StSwapEvent.emptyNew()
	self.vehicle = vehicle
    self.setId = setId
	return self
end

function StSwapEvent.readStream(self, streamId, connection)
	self.vehicle = NetworkUtil.readNodeObject(streamId)
	self.setId = streamReadFloat32(streamId)

    self:run(connection)
end

function StSwapEvent.writeStream(self, streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.vehicle)
	streamWriteFloat32(streamId, self.setId)
end

function StSwapEvent.run(self, connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(StSwapEvent.new(self.vehicle, self.setId), nil, nil, self.vehicle)
    end

    TireStorage.swapTires(self.vehicle, self.setId)
end
