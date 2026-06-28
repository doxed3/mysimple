-- ================================================================
--  Universal Loader  |  doxed3
--  One loadstring → checks game → runs correct script from GitHub
-- ================================================================

local GITHUB_RAW = "https://raw.githubusercontent.com/doxed3/mysimple/main/"

-- ── GAME MAP ────────────────────────────────────────────────────
-- Add more games here as you build scripts for them
local SCRIPTS = {
    -- [PlaceId] = "filename.lua"
    [72712036210947] = "CarESP.lua",          -- Fix It Up
    [111862336710239] = "Backstreet Survival [Beta].lua", -- Backstreet Survival [Beta]
    -- [12345678]  = "AnotherGame.lua",   -- another game
}

-- ── GAME CHECK ──────────────────────────────────────────────────
local placeId  = game.PlaceId
local gameName = "Unknown"
pcall(function()
    gameName = game:GetService("MarketplaceService")
        :GetProductInfo(placeId).Name
end)

local scriptFile = SCRIPTS[placeId]

if not scriptFile then
    -- Not a supported game
    local msg = string.format(
        "[Loader] Unsupported game: %s (PlaceId: %d)\n"..
        "Supported games:\n",
        gameName, placeId
    )
    for id, file in pairs(SCRIPTS) do
        msg = msg .. string.format("  PlaceId %d → %s\n", id, file)
    end
    warn(msg)
    return  -- stop execution, don't run anything
end

-- ── RUN SCRIPT ──────────────────────────────────────────────────
print(string.format("[Loader] Game: %s | Loading: %s", gameName, scriptFile))

local url = GITHUB_RAW .. scriptFile

local ok, err = pcall(function()
    loadstring(game:HttpGet(url))()
end)

if not ok then
    warn("[Loader] Failed to load script: " .. tostring(err))
else
    print("[Loader] Done.")
end
