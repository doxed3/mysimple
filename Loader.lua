-- ================================================================
--  Universal Loader  |  doxed3
--  One loadstring → checks game → runs correct script from GitHub
-- ================================================================

local GITHUB_RAW = "https://raw.githubusercontent.com/doxed3/YOURREPO/main/"

-- ── GAME MAP ────────────────────────────────────────────────────
-- Add more games here as you build scripts for them
local SCRIPTS = {
    [72712036210947]   = "CarESP.lua",                          -- Fix It Up
    [111862336710239]  = "Backstreet%20Survival%20%5BBeta%5D.lua", -- Backstreet Survival [Beta]
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
print("[Loader] URL: " .. url)

local ok, err = pcall(function()
    loadstring(game:HttpGet(url))()
end)

if not ok then
    warn("[Loader] Failed to load script: " .. tostring(err))
else
    print("[Loader] Done.")
end
