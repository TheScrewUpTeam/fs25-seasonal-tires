local HUD_X = 0.715 -- right side
local HUD_Y = 0.028 -- low on screen
local HUD_WIDTH = 0.125
local HUD_HEIGHT = 0.055

local ADD_HUD_X = 0.702 -- right side
local ADD_HUD_Y = 0.085 -- low on screen
local ADD_HUD_WIDTH = 0.125
local ADD_HUD_HEIGHT = 0.05

local ICON_SIZE = 0.015
local BAR_HEIGHT = 0.01

if not TireHUD then TireHUD = {} end
if not TireHUD.ICON_OVERLAY then
    TireHUD.ICON_OVERLAY = createImageOverlay(g_currentModDirectory .. "tire_icon.dds")
end
if not TireHUD.ICON_ALLSEASON then
    TireHUD.ICON_ALLSEASON = createImageOverlay(g_currentModDirectory .. "media/icon_allseason.dds")
end
if not TireHUD.ICON_MUD then
    TireHUD.ICON_MUD = createImageOverlay(g_currentModDirectory .. "media/icon_mud.dds")
end
if not TireHUD.ICON_SNOW then
    TireHUD.ICON_SNOW = createImageOverlay(g_currentModDirectory .. "media/icon_snow.dds")
end
if not TireHUD.ICON_ROAD then
    TireHUD.ICON_ROAD = createImageOverlay(g_currentModDirectory .. "media/icon_road.dds")
end
if not TireHUD.BAR_OVERLAY then
    TireHUD.BAR_OVERLAY = createImageOverlay("dataS/menu/base/graph_pixel.png")
end
if not TireHUD.PANEL_OVERLAY then
    TireHUD.PANEL_OVERLAY = createImageOverlay(g_currentModDirectory .. "media/main_panel_ov.png")
end
if not TireHUD.ADD_PANEL_OVERLAY then
    TireHUD.ADD_PANEL_OVERLAY = createImageOverlay(g_currentModDirectory .. "media/add_panel_ov.png")
end

function TireHUD:getIconByType(tireType)
    if tireType == "allSeason" then
        return TireHUD.ICON_ALLSEASON
    elseif tireType == "mud" then
        return TireHUD.ICON_MUD
    elseif tireType == "snow" then
        return TireHUD.ICON_SNOW
    elseif tireType == "road" then
        return TireHUD.ICON_ROAD
    else
        return TireHUD.ICON_OVERLAY -- default icon
    end
end

function TireHUD:drawAdditional(vehicle, tireData)
    local x, y = ADD_HUD_X, ADD_HUD_Y
    local iconOverlay = TireHUD:getIconByType(tireData.type) -- use type from tireData
    local barOverlay = TireHUD.BAR_OVERLAY
    local panelOverlay = TireHUD.ADD_PANEL_OVERLAY

    -- Panel background
    setOverlayColor(panelOverlay, 0.15, 0.15, 0.15, 0.5)
    renderOverlay(panelOverlay, x, y, ADD_HUD_WIDTH, ADD_HUD_HEIGHT)

    -- Tire icon (left side)
    setOverlayColor(iconOverlay, 1, 1, 1, 1)
    renderOverlay(iconOverlay, x + 0.02, y + (ADD_HUD_HEIGHT - ICON_SIZE) / 2, ICON_SIZE, ICON_SIZE * 1.77)

    -- Tire type text (right of icon bottom)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(x + ICON_SIZE + 0.025, y + ADD_HUD_HEIGHT / 2 - 0.006, 0.013, tireData.name or "Unknown Tires")
    setTextBold(false)
    
    -- Vehicle name (right of icon top)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(x + ICON_SIZE + 0.025, y + ADD_HUD_HEIGHT / 2 + 0.01, 0.013, vehicle:getName() or "Unknown Vehicle")
    setTextBold(false)

    -- Progress bar (bottom, right of icon)
    local barX = x + 0.02
    local barY = y + 0.006
    local barWidth = ADD_HUD_WIDTH - 0.04
    local barHeight = BAR_HEIGHT
    local wear = tireData.wear or 0
    local wearFill = 1.0 - wear -- full = good, empty = worn
    -- Bar background
    setOverlayColor(barOverlay, 0.3, 0.3, 0.3, 1)
    renderOverlay(barOverlay, barX, barY, barWidth, barHeight)
    -- Bar fill (green to red)
    setOverlayColor(barOverlay, 0.3 + 0.7 * wear, 0.7 * wearFill, 0.1, 1)
    renderOverlay(barOverlay, barX, barY, barWidth * wearFill, barHeight)
    
    -- Reset color
    setOverlayColor(barOverlay, 1, 1, 1, 1)
end

function TireHUD:draw(vehicle, tireData)
    local x, y = HUD_X, HUD_Y
    local iconOverlay = TireHUD:getIconByType(tireData.type) -- use type from tireData
    local barOverlay = TireHUD.BAR_OVERLAY
    local panelOverlay = TireHUD.PANEL_OVERLAY

    -- Panel background
    setOverlayColor(panelOverlay, 0.15, 0.15, 0.15, 0.5)
    renderOverlay(panelOverlay, x, y, HUD_WIDTH, HUD_HEIGHT)

    -- Tire icon (left side)
    setOverlayColor(iconOverlay, 1, 1, 1, 1)
    renderOverlay(iconOverlay, x + 0.01, y + (HUD_HEIGHT - ICON_SIZE) / 2, ICON_SIZE, ICON_SIZE * 1.77)

    -- Tire type text (right of icon bottom)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(x + ICON_SIZE + 0.015, y + HUD_HEIGHT / 2 - 0.006, 0.013, tireData.name or "Unknown Tires")
    setTextBold(false)
    
    -- Vehicle name (right of icon top)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(x + ICON_SIZE + 0.015, y + HUD_HEIGHT / 2 + 0.01, 0.013, vehicle:getName() or "Unknown Vehicle")
    setTextBold(false)

    -- Progress bar (bottom, right of icon)
    local barX = x + 0.01
    local barY = y + 0.006
    local barWidth = HUD_WIDTH - 0.02
    local barHeight = BAR_HEIGHT
    local wear = tireData.wear or 0
    local wearFill = 1.0 - wear -- full = good, empty = worn
    -- Bar background
    setOverlayColor(barOverlay, 0.3, 0.3, 0.3, 1)
    renderOverlay(barOverlay, barX, barY, barWidth, barHeight)
    -- Bar fill (green to red)
    setOverlayColor(barOverlay, 0.3 + 0.7 * wear, 0.7 * wearFill, 0.1, 1)
    renderOverlay(barOverlay, barX, barY, barWidth * wearFill, barHeight)
    -- Reset color
    setOverlayColor(barOverlay, 1, 1, 1, 1)
end