print("[TireHUD] file loaded")

local HUD_X = 0.85 -- right side
local HUD_Y = 0.25 -- low on screen
local HUD_WIDTH = 0.12
local HUD_HEIGHT = 0.05

local ICON_SIZE = 0.02
local BAR_HEIGHT = 0.01

if not TireHUD then TireHUD = {} end
if not TireHUD.ICON_OVERLAY then
    TireHUD.ICON_OVERLAY = createImageOverlay(g_currentModDirectory .. "tire_icon.dds")
end
if not TireHUD.BAR_OVERLAY then
    TireHUD.BAR_OVERLAY = createImageOverlay("dataS/menu/base/graph_pixel.png")
end
if not TireHUD.PANEL_OVERLAY then
    TireHUD.PANEL_OVERLAY = createImageOverlay("dataS/menu/black.png")
end

function TireHUD:draw(vehicle, tireData)
    local x, y = HUD_X, HUD_Y
    local iconOverlay = TireHUD.ICON_OVERLAY
    local barOverlay = TireHUD.BAR_OVERLAY
    local panelOverlay = TireHUD.PANEL_OVERLAY

    -- Panel background
    setOverlayColor(panelOverlay, 0.15, 0.15, 0.15, 0.6)
    renderOverlay(panelOverlay, x, y, HUD_WIDTH, HUD_HEIGHT)

    -- Tire icon (left side)
    setOverlayColor(iconOverlay, 1, 1, 1, 1)
    renderOverlay(iconOverlay, x + 0.005, y + (HUD_HEIGHT - ICON_SIZE) / 2, ICON_SIZE, ICON_SIZE)

    -- Tire type text (right of icon)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(x + ICON_SIZE + 0.012, y + HUD_HEIGHT / 2 - 0.005, 0.015, tireData.name or "Unknown Tires")
    setTextBold(false)

    -- Progress bar (bottom, right of icon)
    local barX = x + ICON_SIZE + 0.012
    local barY = y + 0.005
    local barWidth = HUD_WIDTH - ICON_SIZE - 0.02
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