TmsReplaceEvent = {}
local TmsReplaceEvent_mt = Class(TmsReplaceEvent, Event)
InitEventClass(TmsReplaceEvent, "UytReplaceEvent")

function TmsReplaceEvent.emptyNew()
	return Event.new(TmsReplaceEvent_mt)
end

function TmsReplaceEvent.new(vehicle, tyresPrice)
	local self = TmsReplaceEvent.emptyNew()
	self.vehicle = vehicle
    self.tyresPrice = tyresPrice
	return self
end

function TmsReplaceEvent.readStream(self, streamId, connection)
	self.vehicle = NetworkUtil.readNodeObject(streamId)
	self.tyresPrice = streamReadFloat32(streamId)

    self:run(connection)
end

function TmsReplaceEvent.writeStream(self, streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.vehicle)
	streamWriteFloat32(streamId, self.tyresPrice)
end

function TmsReplaceEvent.run(self, connection)
	if self.vehicle ~= nil and self.vehicle.spec_wheels ~= nil then
        
        -- for _, wheel in ipairs(self.vehicle.spec_wheels.wheels) do
        --     -- Reset travelled distance to simulate new tyre
        --     wheel.uytTravelledDist = 0
            
        --     -- Now trigger update
        --     for _, visualWheel in ipairs(wheel.visualWheels) do
        --         for _, visualPart in ipairs(visualWheel.visualParts) do
        --             if visualPart:isa(WheelVisualPartTire) and visualPart.node ~= nil and visualPart.uytEnabled ~= nil then
        --                 UseYourTyres.updateWheelRadius(visualPart, false)
        --             end
        --         end
        --     end
        -- end

        -- if self.vehicle.isServer then
        --     g_currentMission:addMoney(-self.tyresPrice, self.vehicle:getOwnerFarmId(), MoneyType.VEHICLE_REPAIR, true, true)
        -- end
		
		if not connection:getIsServer() then
			g_server:broadcastEvent(self)
		end
	end
end
