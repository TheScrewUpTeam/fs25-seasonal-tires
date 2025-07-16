-- Main registration script for SeasonalTiresMod
if Utils == nil then Utils = {} end
if Utils.getFilename == nil then
    function Utils.getFilename(filename, baseDir)
        if string.sub(filename, 1, 1) == "/" or string.sub(filename, 2, 2) == ":" then
            return filename
        end
        return (baseDir or "") .. filename
    end
end

source(Utils.getFilename("src/TireManager.lua", g_currentModDirectory))