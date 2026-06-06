-- ================================================================
--  CarScript  |  Fix It Up  |  v7
-- ================================================================

-- ── KILL OLD INSTANCE ───────────────────────────────────────────
if _G.CarScriptKill then pcall(_G.CarScriptKill) end

local _alive   = true
local _conns   = {}
local _entries = {}

local function track(c) _conns[#_conns+1] = c; return c end

_G.CarScriptKill = function()
    _alive = false
    for _, c in ipairs(_conns) do pcall(c.Disconnect, c) end
    table.clear(_conns)
    for _, e in pairs(_entries) do
        pcall(function() if e.bb then e.bb:Destroy() end end)
        pcall(function() if e.hl then e.hl:Destroy() end end)
    end
    table.clear(_entries)
    local old = game:GetService("CoreGui"):FindFirstChild("CarScriptGui")
    if old then old:Destroy() end
end

-- ── SERVICES ────────────────────────────────────────────────────
local RunService         = game:GetService("RunService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CoreGui            = game:GetService("CoreGui")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService       = game:GetService("TweenService")

local Camera        = workspace.CurrentCamera
local LocalPlayer   = Players.LocalPlayer
local VehicleFolder = workspace:WaitForChild("Vehicles")
local PlayerData    = LocalPlayer:WaitForChild("PlayerData")
local Garage        = PlayerData:WaitForChild("Garage")

local RemoteLoad = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Vehicles"):WaitForChild("RemoteLoad")
local PartsEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("PartsEvent")

-- Car name lookup via CarNames module (brand alias mapping)
local CarNames = nil
pcall(function() CarNames = require(ReplicatedStorage.Modules.CarNames) end)

-- CarList lookup: BoolValue.Name = display name, attrs = SpawnChance + Price
-- Used to resolve UUID junkyard cars → real car name
local carListByKey = {}   -- [spawnChance.."_"..priceAttr] = displayName
local carListLoaded = false

task.spawn(function()
    local ok, CarList = pcall(function()
        return ReplicatedStorage:WaitForChild("Cache", 10):WaitForChild("CarList", 10)
    end)
    if ok and CarList then
        for _, child in ipairs(CarList:GetChildren()) do
            local sc = child:GetAttribute("SpawnChance")
            local pr = child:GetAttribute("Price")
            if sc ~= nil and pr then
                local key = tostring(sc).."_"..tostring(pr)
                carListByKey[key] = child.Name
            end
        end
        carListLoaded = true
        print(("[CarScript] CarList loaded: %d entries"):format(#CarList:GetChildren()))
    else
        print("[CarScript] CarList not found")
    end
end)

local function carListLookup(chance, priceAttr)
    if not priceAttr then return nil end
    local key = tostring(chance).."_"..tostring(priceAttr)
    return carListByKey[key]
end

local gameName = "Fix It Up"
pcall(function() gameName = MarketplaceService:GetProductInfo(game.PlaceId).Name end)

-- ── STATE ────────────────────────────────────────────────────────
local State = {
    -- ESP
    espEnabled      = false,
    showBuyable     = false,
    showOwned       = false,
    showChances     = false,
    showName        = false,
    showTier        = false,
    showPrice       = false,
    showProfit      = false,
    showDist        = false,
    espDistance     = 2000,
    -- Highlights
    hlEnabled       = false,
    useFillColor    = false,
    useOutlineColor = false,
    useTextColor    = false,
    fillColor       = Color3.fromRGB(0, 100, 255),
    outlineColor    = Color3.fromRGB(0, 170, 255),
    textColor       = Color3.fromRGB(255, 255, 255),
    -- Tiers
    showS = false, showA = false, showB = false, showC = false, showD = false,
    -- Respawn billboard notif
    respawnBillboard = false,
    respawnInterval  = 30,  -- seconds
    -- Respawn wave notif
    respawnWaveNotif = false,
    -- Farm
    farmEnabled  = false,
    farmMode     = "fix",
    farmTick     = 3.0,
    -- UI
    watermark    = false,
}

-- ================================================================
--  CONFIG
-- ================================================================
local CFG = {
    TIERS = {
        { min = 0,       max = 49999,     label = "D", color = Color3.fromRGB(160, 255, 160) },  -- light green
        { min = 50000,   max = 149999,    label = "C", color = Color3.fromRGB(0,   200, 80)  },  -- dark green
        { min = 150000,  max = 499999,    label = "B", color = Color3.fromRGB(80,  130, 235) },  -- blue
        { min = 500000,  max = 1499999,   label = "A", color = Color3.fromRGB(210, 80,  235) },  -- purple
        { min = 1500000, max = math.huge, label = "S", color = Color3.fromRGB(255, 215, 0)   },  -- gold
    },
    BUYABLE_COLOR = Color3.fromRGB(0,   230, 80),
    OWNED_COLOR   = Color3.fromRGB(255, 60,  60),
    FONT          = Enum.Font.GothamBold,
    TEXT_SIZE     = 13,
    BB_W          = 260,
}
local TIER_SHOW = { S="showS", A="showA", B="showB", C="showC", D="showD" }

-- ================================================================
--  HELPERS
-- ================================================================
local function getTier(price)
    for _, t in ipairs(CFG.TIERS) do
        if price >= t.min and price <= t.max then return t end
    end
    return CFG.TIERS[1]
end

local function parsePrice(attr)
    if not attr then return 0 end
    local s = tostring(attr)
    local a, b = s:match("(%d+)%s+(%d+)")
    if a then return math.floor((tonumber(a)+tonumber(b))/2) end
    return math.floor(tonumber(s) or 0)
end

local function isUUID(s)
    return s and #s > 20 and s:find("%-") ~= nil
end

local function shortHash(s)
    return s:sub(1,8).."…"
end

local function getCarData(model)
    local owner      = model:GetAttribute("Owner") or ""
    local priceAttr  = model:GetAttribute("Price")
    local price      = parsePrice(priceAttr)
    local rawAttr    = model:GetAttribute("Model") or model.Name
    local hash       = model.Name
    local hashStr    = isUUID(hash) and shortHash(hash) or hash
    local chance     = model:GetAttribute("SpawnChance") or 0

    -- Resolve display name
    local dispName
    if not isUUID(rawAttr) then
        -- Owned car: attr Model IS the real name → apply CarNames brand alias
        dispName = CarNames and CarNames:GetName(rawAttr) or rawAttr
    else
        -- Junkyard car: attr Model is a UUID → match via SpawnChance + Price in CarList
        local key    = tostring(chance).."_"..tostring(priceAttr or "")
        local looked = carListLookup(chance, priceAttr)
        if looked then
            dispName = looked
        else
            dispName = shortHash(rawAttr)  -- fallback to short hash
        end
    end

    return {
        name      = dispName,
        fullName  = rawAttr,
        hash      = hashStr,
        price     = price,
        owner     = owner,
        chance    = chance,
        profit    = model:GetAttribute("ProfitMultiplier") or 0,
        isBuyable = (owner == ""),
        tier      = getTier(price),
    }
end

local function fmtNum(n)
    local s = tostring(math.floor(n))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function getCondition(vehicle)
    local ok, val = pcall(function()
        return vehicle["A-Chassis Tune"]["A-Chassis Interface"].Gauges.PC.Panel.Condition.Value
    end)
    if ok and type(val) == "number" then return math.floor(val * 100) end
    local ok2, val2 = pcall(function()
        return vehicle["A-Chassis Tune"]["A-Chassis Interface"].Gauges.PC.Panel.Condition.Text
    end)
    if ok2 and val2 then return val2 end
    return "?"
end

-- Read junkyard respawn time from the billboard
local function getJunkyardRespawnTime()
    local ok, val = pcall(function()
        return workspace.Map.FirstCity.Junkyard.JunkyardRespawn.Screen.SurfaceGui.TextLabel.Text
    end)
    if ok and val then
        local n = val:match("%d+")
        return n and tonumber(n) or nil
    end
    return nil
end

-- ================================================================
--  ESP GUI
-- ================================================================
local espGui = Instance.new("ScreenGui")
espGui.Name           = "CarScriptGui"
espGui.ResetOnSpawn   = false
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
espGui.Parent         = CoreGui
_G.CarScriptGui       = espGui

local function rgb(c)
    return ("rgb(%d,%d,%d)"):format(math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255))
end

local function calcHeight()
    local lines = 1  -- tag always
    if State.showName  then lines += 1 end
    if State.showTier or State.showPrice then lines += 1 end
    if State.showProfit or State.showDist then lines += 1 end
    return math.max(28, lines * 18 + 8)
end

local function createEntry(model)
    local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not root then return nil end

    local bb = Instance.new("BillboardGui")
    bb.Size                  = UDim2.fromOffset(CFG.BB_W, 28)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
    bb.AlwaysOnTop           = true
    bb.Adornee               = root
    bb.Enabled               = false
    bb.Parent                = espGui

    local shadow = Instance.new("TextLabel")
    shadow.BackgroundTransparency = 1
    shadow.Size        = UDim2.new(1, 2, 1, 2)
    shadow.Position    = UDim2.fromOffset(1, 1)
    shadow.TextColor3  = Color3.new(0, 0, 0)
    shadow.Font        = CFG.FONT
    shadow.TextSize    = CFG.TEXT_SIZE
    shadow.TextWrapped = true
    shadow.RichText    = false
    shadow.ZIndex      = 2
    shadow.Parent      = bb

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size        = UDim2.new(1, 0, 1, 0)
    label.Font        = CFG.FONT
    label.TextSize    = CFG.TEXT_SIZE
    label.TextWrapped = true
    label.RichText    = true
    label.ZIndex      = 3
    label.Parent      = bb

    local hl = Instance.new("Highlight")
    hl.FillColor           = CFG.TIERS[1].color
    hl.OutlineColor        = CFG.TIERS[1].color
    hl.FillTransparency    = 0.5
    hl.OutlineTransparency = 0
    hl.Adornee             = model
    hl.Enabled             = false
    hl.Parent              = espGui

    return { bb=bb, shadow=shadow, label=label, hl=hl, root=root }
end

local function buildRich(data, dist)
    local tc  = data.isBuyable and CFG.BUYABLE_COLOR or CFG.OWNED_COLOR
    local rc  = data.tier.color
    -- Tag line: [BUYABLE] name(hash) or [OWNED: owner] name(hash)
    local nameHash = data.name.."("..data.hash..")"
    local tagLine
    if data.isBuyable then
        tagLine = ('<font color="%s"><b>[BUYABLE] %s</b></font>'):format(rgb(tc), nameHash)
    else
        tagLine = ('<font color="%s"><b>[OWNED: %s]</b></font> %s'):format(rgb(tc), data.owner, nameHash)
    end

    local lines = { tagLine }

    -- Line 2: detailed name if toggled
    if State.showName then
        lines[#lines+1] = data.fullName
    end

    -- Line 3: tier + price + chances (chances shows even without tier)
    local tp = {}
    if State.showTier then
        tp[#tp+1] = ('Tier:<font color="%s"><b>%s</b></font>'):format(rgb(rc), data.tier.label)
    end
    if State.showChances then
        tp[#tp+1] = tostring(data.chance).."%"
    end
    if State.showPrice then tp[#tp+1] = "$"..fmtNum(data.price) end
    if #tp > 0 then lines[#lines+1] = table.concat(tp, " | ") end

    -- Line 4: profit + dist
    local ep = {}
    if State.showProfit then ep[#ep+1] = "x"..tostring(data.profit) end
    if State.showDist   then ep[#ep+1] = math.floor(dist).." studs" end
    if #ep > 0 then lines[#lines+1] = table.concat(ep, " | ") end

    return table.concat(lines, "\n")
end

local function buildPlain(data, dist)
    local nameHash = data.name.."("..data.hash..")"
    local tag = data.isBuyable and ("[BUYABLE] "..nameHash) or ("[OWNED: "..data.owner.."] "..nameHash)
    local lines = { tag }
    if State.showName then lines[#lines+1] = data.fullName end
    local tp = {}
    if State.showTier  then tp[#tp+1] = "Tier:"..data.tier.label end
    if State.showChances then tp[#tp+1] = tostring(data.chance).."%" end
    if State.showPrice then tp[#tp+1] = "$"..fmtNum(data.price) end
    if #tp > 0 then lines[#lines+1] = table.concat(tp, " | ") end
    local ep = {}
    if State.showProfit then ep[#ep+1] = "x"..tostring(data.profit) end
    if State.showDist   then ep[#ep+1] = math.floor(dist).." studs" end
    if #ep > 0 then lines[#lines+1] = table.concat(ep, " | ") end
    return table.concat(lines, "\n")
end

-- ================================================================
--  VEHICLE SCAN
-- ================================================================
local function addEntry(model)
    if not model:IsA("Model") or _entries[model] then return end
    local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not root then
        task.spawn(function()
            local deadline = tick() + 5
            while tick() < deadline do
                task.wait(0.1)
                root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if root or not model.Parent then break end
            end
            if not model.Parent or _entries[model] then return end
            local e = createEntry(model)
            if e then _entries[model] = e end
        end)
        return
    end
    local e = createEntry(model)
    if e then _entries[model] = e end
end

local function removeEntry(model)
    local e = _entries[model]
    if not e then return end
    pcall(function() e.bb:Destroy() end)
    pcall(function() e.hl:Destroy() end)
    _entries[model] = nil
end

for _, v in ipairs(VehicleFolder:GetChildren()) do addEntry(v) end
track(VehicleFolder.ChildAdded:Connect(function(m)
    addEntry(m)
    task.wait(0.5)  -- wait for attributes to replicate
    if Options.CarTelePicker then buildVehicleDrop() end
end))
track(VehicleFolder.ChildRemoved:Connect(function(m)
    removeEntry(m)
    if Options.CarTelePicker then buildVehicleDrop() end
end))

-- ================================================================
--  RESPAWN WAVE NOTIF  (count buyable cars added in a wave)
-- ================================================================
local respawnQueue    = 0
local respawnDebounce = false

track(VehicleFolder.ChildAdded:Connect(function(model)
    if not _alive or not State.respawnWaveNotif then return end
    task.spawn(function()
        task.wait(0.4)
        if not model.Parent then return end
        local owner = model:GetAttribute("Owner") or ""
        if owner ~= "" then return end
        respawnQueue += 1
        if respawnDebounce then return end
        respawnDebounce = true
        task.wait(2.0)
        local count = respawnQueue
        respawnQueue    = 0
        respawnDebounce = false
        -- Send 6 notifs per respawn wave, with 5-6s delay between each
        task.spawn(function()
            for i = 1, 6 do
                if not _alive then return end
                Library:Notify(("🔔 Junkyard spawned! %d car(s)"):format(count), 5)
                task.wait(5.5)
            end
        end)
    end)
end))

-- ================================================================
--  GARAGE
-- ================================================================
local garageList = {}
local garageMap  = {}

local function refreshGarage()
    garageList = {}; garageMap = {}
    for _, entry in ipairs(Garage:GetChildren()) do
        local vals = entry:FindFirstChild("Values")
        local mid  = vals and vals:FindFirstChild("Model")
        local disp = entry:GetAttribute("Model")
            or (mid and tostring(mid.Value))
            or entry.Name:sub(1,12).."..."
        local lbl = disp; local n = 1
        while garageMap[lbl] do n+=1; lbl = disp.." #"..n end
        garageList[#garageList+1] = lbl
        garageMap[lbl] = entry
    end
    if Options.GaragePicker then
        Options.GaragePicker:SetValues(#garageList>0 and garageList or {"(empty)"})
    end
    if Options.MainCarPicker then
        Options.MainCarPicker:SetValues(#garageList>0 and garageList or {"(none)"})
    end
end

local function spawnCar()
    local sel = Options.GaragePicker and Options.GaragePicker.Value
    if not sel or sel == "(empty)" then Library:Notify("Select a car first!"); return end
    local entry = garageMap[sel]
    if not entry then Library:Notify("Entry missing."); return end
    local hrp = (LocalPlayer.Character or {}).HumanoidRootPart
    if not hrp then Library:Notify("Spawn in first."); return end
    local ok, err = pcall(RemoteLoad.InvokeServer, RemoteLoad, entry,
        hrp.CFrame * CFrame.new(0, 0, -10))
    Library:Notify(ok and ("Spawned: "..sel) or ("Error: "..tostring(err)))
end

track(Garage.ChildAdded:Connect(function() task.wait(0.5); refreshGarage() end))
track(Garage.ChildRemoved:Connect(function() task.wait(0.5); refreshGarage() end))

-- ================================================================
--  TELEPORT DESTINATIONS
-- ================================================================
local TeleDestinations = {
    ['Garage'] = function()
        local p = workspace.Garages.Default.Exterior.Road
        if p:IsA("BasePart") then return p.CFrame end
        return (p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")).CFrame
    end,
    ['Junkyard'] = function()
        local p = workspace.Map.FirstCity.Junkyard.Decor:GetChildren()[53]
        if p:IsA("BasePart") then return p.CFrame end
        return (p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")).CFrame
    end,
    ['Spare Parts (Shop)'] = function()
        local m = workspace.Map.FirstCity.SparePartsShop.SparePartsShop["Cash out area"]
        return (m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")).CFrame
    end,
    ['AutoShop (Repair)'] = function()
        local p = workspace.Map.FirstCity.Buildings["PitStop(Large)"]:GetChildren()[88]
        if p:IsA("BasePart") then return p.CFrame end
        return (p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")).CFrame
    end,
    ['AutoCustoms (Body)'] = function()
        local ok, result = pcall(function()
            local container = workspace.Map.Map:GetChildren()[1690]
            -- container might be a Model - find any BasePart inside it
            local p = container:FindFirstChildWhichIsA("BasePart")
            if p then return p.CFrame end
            for _, c in ipairs(container:GetChildren()) do
                local bp = c:IsA("BasePart") and c or c:FindFirstChildWhichIsA("BasePart")
                if bp then return bp.CFrame end
            end
        end)
        return ok and result or nil
    end,
    ['PitWheels'] = function()
        local ok, result = pcall(function()
            local p = workspace.Map:GetChildren()[9]["jantes pneus"].TireShop.pneus
            if p:IsA("BasePart") then return p.CFrame end
            return (p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")).CFrame
        end)
        return ok and result or nil
    end,
    ['ApexTyres'] = function()
        local ok, result = pcall(function()
            local p = workspace.Map.Map.apextyres
            if p:IsA("BasePart") then return p.CFrame end
            return (p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")).CFrame
        end)
        return ok and result or nil
    end,
    ['Gas Station'] = function()
        local ok, result = pcall(function()
            local b = workspace.Map.FirstCity.Buildings:GetChildren()[80]
            local p = b:FindFirstChild("Road") or b.PrimaryPart or b:FindFirstChildWhichIsA("BasePart")
            return p.CFrame
        end)
        return ok and result or nil
    end,
    ['Sell'] = function()
        local ok, result = pcall(function()
            local p = workspace.Map.Map.Barraca.Part
            if p:IsA("BasePart") then return p.CFrame end
            return (p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")).CFrame
        end)
        return ok and result or nil
    end,
    ['Dyno Tune'] = function()
        local ok, result = pcall(function()
            local p = workspace.Map.Map.dynotune:GetChildren()[7]
            if p:IsA("BasePart") then return p.CFrame end
            return (p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")).CFrame
        end)
        return ok and result or nil
    end,
}

-- ================================================================
--  LINORIA
-- ================================================================
local repo         = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local Library      = loadstring(game:HttpGet(repo..'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo..'addons/ThemeManager.lua'))()
local SaveManager  = loadstring(game:HttpGet(repo..'addons/SaveManager.lua'))()

-- ================================================================
--  WINDOW & TABS
-- ================================================================
local Window = Library:CreateWindow({
    Title        = string.format("CarScript | %s | %s", gameName, LocalPlayer.Name),
    Center       = true,
    AutoShow     = true,
    TabPadding   = 0,
    MenuFadeTime = 0.1,
})
local Tabs = {
    Main     = Window:AddTab('MAIN'),
    Junkyard = Window:AddTab('JUNKYARD'),
    Farm     = Window:AddTab('FARM'),
    UI       = Window:AddTab('UI Settings'),
}

local CarGroup    = Tabs.Main:AddLeftGroupbox('Car')
local TeleGroup   = Tabs.Main:AddLeftGroupbox('Teleporting')
local SpawnGroup  = Tabs.Main:AddRightGroupbox('Owned Cars')
local ShopGroup   = Tabs.Main:AddRightGroupbox('Shop')
local JunkCfg     = Tabs.Junkyard:AddLeftGroupbox('Configuration')
local LabelGroup  = Tabs.Junkyard:AddLeftGroupbox('ESP Labels')
local TierGroup   = Tabs.Junkyard:AddRightGroupbox('Tiers')
local FarmMain    = Tabs.Farm:AddLeftGroupbox('AutoFarm')
local FarmInfo    = Tabs.Farm:AddRightGroupbox('Info')
local MenuGroup   = Tabs.UI:AddLeftGroupbox('Menu')

-- ================================================================
--  MAIN TAB – Car
-- ================================================================
-- Dropdown to select which garage car to track
local carNameLbl  = CarGroup:AddLabel("Name:  —")
local carHashLbl  = CarGroup:AddLabel("Hash:  —")
local carCondLbl  = CarGroup:AddLabel("Cond:  —")
local carPriceLbl = CarGroup:AddLabel("Price: —")

CarGroup:AddDropdown('MainCarPicker', {
    Values  = { '(none)' },
    Default = '(none)',
    Multi   = false,
    Text    = 'Select Car',
    Tooltip = 'Pick a garage car to track on MAIN tab',
    Callback = function(_) end,
})
CarGroup:AddButton({ Text='Respawn Car', DoubleClick=false,
    Func=function() print('[CarScript] Respawn fired'); Library:Notify('Respawn sent') end })
CarGroup:AddButton({ Text='Repair Car', DoubleClick=false,
    Func=function() print('[CarScript] Repair fired'); Library:Notify('Repair sent') end })
CarGroup:AddButton({ Text='Sell Car', DoubleClick=true,
    Func=function() print('[CarScript] Sell fired'); Library:Notify('Sell sent') end })
CarGroup:AddButton({ Text='🔔 Test Notif', DoubleClick=false,
    Func=function()
        task.spawn(function()
            for i = 1, 6 do
                if not _alive then return end
                Library:Notify("🔔 Test Notification ["..i.."/6]", 5)
                task.wait(5.5)
            end
        end)
    end
})

-- ================================================================
--  MAIN TAB – Teleport
-- ================================================================
TeleGroup:AddDropdown('TeleLocation', {
    Values  = { 'Garage','Junkyard','Spare Parts (Shop)','AutoShop (Repair)',
                'AutoCustoms (Body)','PitWheels','ApexTyres','Gas Station','Sell','Dyno Tune' },
    Default = 'Garage', Multi=false, Text='Location', Callback=function(_) end,
})
TeleGroup:AddButton({ Text='Teleport', DoubleClick=false,
    Func=function()
        local loc    = Options.TeleLocation and Options.TeleLocation.Value or 'Garage'
        local destFn = TeleDestinations[loc]
        if not destFn then Library:Notify("No dest for: "..loc); return end
        local ok, cf = pcall(destFn)
        if ok and cf then
            local hrp = (LocalPlayer.Character or {}).HumanoidRootPart
            if hrp then hrp.CFrame = cf + Vector3.new(0,5,0); Library:Notify("→ "..loc)
            else Library:Notify("No character") end
        else
            Library:Notify("Path error: "..loc)
            warn("[CarScript] Tele:", cf)
        end
    end
})

-- ── Teleport to specific car in junkyard ─────────────────────────
-- vehicleDropMap[label] = model reference
local vehicleDropMap = {}

local function buildVehicleDrop()
    vehicleDropMap = {}
    local labels   = {}
    local seen     = {}
    for _, model in ipairs(VehicleFolder:GetChildren()) do
        if not model:IsA("Model") then continue end
        local d = getCarData(model)
        -- Only list buyable (junkyard) cars
        if not d.isBuyable then continue end
        local lbl = d.name.." ("..d.tier.label..")"
        -- Deduplicate labels
        local base = lbl; local n = 1
        while seen[lbl] do n+=1; lbl = base.." #"..n end
        seen[lbl] = true
        labels[#labels+1] = lbl
        vehicleDropMap[lbl] = model
    end
    if #labels == 0 then labels = {"(no cars)"} end
    if Options.CarTelePicker then
        Options.CarTelePicker:SetValues(labels)
    end
    return labels
end

-- Pre-populate with placeholder (UI element created below)
local carTeleLabels = { "(loading...)" }

TeleGroup:AddDropdown('CarTelePicker', {
    Values  = carTeleLabels,
    Default = carTeleLabels[1],
    Multi   = false,
    Text    = 'Car (Tier)',
    Tooltip = 'Junkyard cars — refresh to update list',
    Callback = function(_) end,
})
TeleGroup:AddButton({ Text='Teleport to Car', DoubleClick=false,
    Func=function()
        local sel = Options.CarTelePicker and Options.CarTelePicker.Value
        if not sel or sel == "(no cars)" or sel == "(loading...)" then
            Library:Notify("No car selected"); return
        end
        local model = vehicleDropMap[sel]
        if not model or not model.Parent then
            Library:Notify("Car no longer exists, refresh list"); return
        end
        local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        if not root then Library:Notify("No root part"); return end
        local hrp = (LocalPlayer.Character or {}).HumanoidRootPart
        if hrp then
            hrp.CFrame = root.CFrame + Vector3.new(0, 6, 0)
            Library:Notify("→ "..sel)
        else
            Library:Notify("No character")
        end
    end,
    Tooltip = 'Teleport to the selected junkyard car'
})
TeleGroup:AddButton({ Text='Refresh Car List', DoubleClick=false,
    Func=function()
        local labels = buildVehicleDrop()
        Library:Notify(#labels.." car(s) found")
    end,
    Tooltip = 'Rescan junkyard for current cars'
})

-- ================================================================
--  MAIN TAB – Spawn Car
-- ================================================================
SpawnGroup:AddDropdown('GaragePicker', { Values={'(loading...)'}, Default='(loading...)',
    Multi=false, Text='Your Cars', Callback=function(_) end })
SpawnGroup:AddToggle('EnterOnSpawn', { Text='Enter on Spawn', Default=false, Callback=function(_) end })
SpawnGroup:AddButton({ Text='Spawn', DoubleClick=false, Func=spawnCar })
SpawnGroup:AddButton({ Text='Refresh List', DoubleClick=false,
    Func=function() refreshGarage(); Library:Notify(#garageList..' car(s)') end })

-- ================================================================
--  MAIN TAB – Shop
-- ================================================================
ShopGroup:AddDropdown('ShopCategory', {
    Values  = { 'AirSuspension','Generic','Rot 1.3','Transmission',
                'V10 5.2','V6 3.0D','V6 3.8','V8 4.0','V8 4.2',
                'i3 1.0','i4 1.9D','i4 2.0','i4 2.0 VETC','i5 2.5','i6 3.0' },
    Default = 'i4 2.0', Multi=false, Text='Category', Callback=function(_) end,
})
Options.ShopCategory:OnChanged(function() end)
ShopGroup:AddDropdown('ShopItem', { Values={'—'}, Default='—', Multi=false, Text='Item', Callback=function(_) end })

local function buyPart()
    local cat  = Options.ShopCategory and Options.ShopCategory.Value
    local item = Options.ShopItem     and Options.ShopItem.Value
    if not cat or not item or item == "—" then Library:Notify("Select category & item!"); return end
    local pm = workspace.PartsStore and workspace.PartsStore.SpareParts
        and workspace.PartsStore.SpareParts.Parts
        and workspace.PartsStore.SpareParts.Parts:FindFirstChild(cat)
        and workspace.PartsStore.SpareParts.Parts[cat]:FindFirstChild(item)
    if not pm then Library:Notify("Part not found: "..cat.."/"..item); return end
    local ok, err = pcall(function() PartsEvent:FireServer(pm) end)
    if ok then Library:Notify("Bought: "..item)
    else Library:Notify("Buy failed: "..tostring(err)); warn("[CarScript]", err) end
end

ShopGroup:AddButton({ Text='Buy Part', DoubleClick=false, Func=buyPart, Tooltip='Buy via PartsEvent' })

-- ================================================================
--  JUNKYARD TAB – Configuration
-- ================================================================
-- Respawn billboard notif (reads the RESPAWN IN X SECONDS sign)
JunkCfg:AddToggle('RespawnBillboard', {
    Text='Respawn Timer Notif', Default=false,
    Tooltip='Notify at set intervals using the junkyard billboard timer',
    Callback=function(v) State.respawnBillboard=v end,
})
JunkCfg:AddDropdown('RespawnInterval', {
    Values  = {'5','10','15','20','30','45','60','90','180'},
    Default = '30', Multi=false,
    Text    = 'Notify every N seconds',
    Callback = function(v) State.respawnInterval = tonumber(v) or 30 end,
})
JunkCfg:AddToggle('RespawnWaveNotif', {
    Text='Respawn Wave Notif', Default=false,
    Tooltip='Send 6 notifs (5s apart) when junkyard cars actually spawn',
    Callback=function(v) State.respawnWaveNotif=v end,
})

JunkCfg:AddDivider()

-- ESP controls in logical order
JunkCfg:AddToggle('ESPEnabled', {
    Text='Junkyard ESP  ← enable first', Default=false,
    Tooltip='Master toggle — enable this before using tiers/labels',
    Callback=function(v)
        State.espEnabled=v
        if not v then for _,e in pairs(_entries) do e.bb.Enabled=false; e.hl.Enabled=false end end
    end,
})
JunkCfg:AddToggle('ShowBuyable', { Text='Show Buyable', Default=false, Callback=function(v) State.showBuyable=v end })
JunkCfg:AddToggle('ShowOwned',   { Text='Show Owned',   Default=false, Callback=function(v) State.showOwned=v   end })
JunkCfg:AddToggle('HLEnabled', {
    Text='Highlights (Chams)', Default=false,
    Callback=function(v)
        State.hlEnabled=v
        if not v then for _,e in pairs(_entries) do e.hl.Enabled=false end end
    end,
})

JunkCfg:AddDivider()

JunkCfg:AddToggle('FillColorEnabled', { Text='Fill Color (else tier)', Default=false,
    Callback=function(v) State.useFillColor=v end,
}):AddColorPicker('FillColor', { Default=Color3.fromRGB(0,100,255), Title='Fill Color',
    Callback=function(v) State.fillColor=v end })
JunkCfg:AddToggle('OutlineColorEnabled', { Text='Outline Color (else tier)', Default=false,
    Callback=function(v) State.useOutlineColor=v end,
}):AddColorPicker('OutlineColor', { Default=Color3.fromRGB(0,170,255), Title='Outline Color',
    Callback=function(v) State.outlineColor=v end })
JunkCfg:AddToggle('TextColorEnabled', { Text='Text Color', Default=false,
    Callback=function(v) State.useTextColor=v end,
}):AddColorPicker('TextColor', { Default=Color3.fromRGB(255,255,255), Title='Text Color',
    Callback=function(v) State.textColor=v end })
JunkCfg:AddSlider('ESPDistance', {
    Text='Max Distance (studs)', Default=2000, Min=100, Max=5000, Rounding=0,
    Callback=function(v) State.espDistance=v end,
})

-- ================================================================
--  JUNKYARD TAB – ESP Labels
-- ================================================================
LabelGroup:AddToggle('ShowChances', { Text='Show Chances',  Default=false, Callback=function(v) State.showChances=v end })
LabelGroup:AddToggle('ShowName',    { Text='Show Full Name',Default=false, Callback=function(v) State.showName=v    end })
LabelGroup:AddToggle('ShowTier',    { Text='Show Tier',     Default=false, Callback=function(v) State.showTier=v    end })
LabelGroup:AddToggle('ShowPrice',   { Text='Show Price',    Default=false, Callback=function(v) State.showPrice=v   end })
LabelGroup:AddToggle('ShowProfit',  { Text='Show Profit',   Default=false, Callback=function(v) State.showProfit=v  end })
LabelGroup:AddToggle('ShowDist',    { Text='Show Distance', Default=false, Callback=function(v) State.showDist=v    end })

-- ================================================================
--  JUNKYARD TAB – Tiers
-- ================================================================
TierGroup:AddLabel("Enable ESP first →")
TierGroup:AddLabel("(Junkyard ESP + Buyable/Owned)")
TierGroup:AddToggle('ShowTierS', { Text='Tier S  (Gold)',       Default=false, Callback=function(v) State.showS=v end })
TierGroup:AddToggle('ShowTierA', { Text='Tier A  (Purple)',     Default=false, Callback=function(v) State.showA=v end })
TierGroup:AddToggle('ShowTierB', { Text='Tier B  (Blue)',       Default=false, Callback=function(v) State.showB=v end })
TierGroup:AddToggle('ShowTierC', { Text='Tier C  (Dark Green)', Default=false, Callback=function(v) State.showC=v end })
TierGroup:AddToggle('ShowTierD', { Text='Tier D  (Lt. Green)',  Default=false, Callback=function(v) State.showD=v end })

-- ================================================================
--  FARM TAB
-- ================================================================
FarmMain:AddToggle('FarmEnabled', {
    Text='Enable AutoFarm', Default=false,
    Tooltip='Master switch — turns off all farm processes when disabled',
    Callback=function(v) State.farmEnabled=v end,
})
FarmMain:AddDropdown('FarmMode', {
    Values   = { 'fix', 'repair' },
    Default  = 'fix',
    Multi    = false,
    Text     = 'Mode',
    Tooltip  = 'fix = buy ALL parts needed + sell | repair = buy only broken parts + sell',
    Callback = function(v) State.farmMode=v end,
})
FarmMain:AddSlider('FarmTick', {
    Text    = 'Tick Rate (s)',
    Default = 3, Min=0.5, Max=30, Rounding=1,
    Tooltip = 'Seconds between each farm action (e.g. 3s = buy/fix every 3s)',
    Callback=function(v) State.farmTick=v end,
})
FarmMain:AddButton({ Text='⏹ Override OFF (stop all)', DoubleClick=false,
    Func=function()
        State.farmEnabled = false
        if Options.FarmEnabled then
            Options.FarmEnabled:SetValue(false)
        end
        Library:Notify('AutoFarm stopped.')
    end,
    Tooltip = 'Force-stop all farm processes immediately'
})

FarmInfo:AddLabel('fix    – buy ALL parts for car')
FarmInfo:AddLabel('         make condition 100%')
FarmInfo:AddLabel('         then auto sell')
FarmInfo:AddLabel(' ')
FarmInfo:AddLabel('repair – buy only the broken')
FarmInfo:AddLabel('         parts, then auto sell')
FarmInfo:AddLabel(' ')
FarmInfo:AddLabel('Tick = delay between actions')

-- ================================================================
--  UI SETTINGS TAB
-- ================================================================
MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default='Delete', NoUI=true, Text='Menu keybind' })
MenuGroup:AddToggle('Watermark', { Text='Watermark', Default=false,
    Callback=function(v) State.watermark=v; Library:SetWatermarkVisibility(v) end })
MenuGroup:AddToggle('KeybindList', { Text='Keybind List', Default=false,
    Callback=function(v) Library.KeybindFrame.Visible=v end })

Library.ToggleKeybind       = Options.MenuKeybind
Library.KeybindFrame.Visible = false
Library:SetWatermark(string.format("CarScript | %s", LocalPlayer.Name))
Library:SetWatermarkVisibility(false)
Library:OnUnload(function() _G.CarScriptKill(); print('[CarScript] Unloaded') end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({'MenuKeybind'})
ThemeManager:SetFolder('CarScript')
SaveManager:SetFolder('CarScript/config')
SaveManager:BuildConfigSection(Tabs.UI)
ThemeManager:ApplyToTab(Tabs.UI)
SaveManager:LoadAutoloadConfig()

-- ================================================================
--  LOOPS
-- ================================================================

-- ── ESP ──────────────────────────────────────────────────────────
local espTimer = 0
track(RunService.RenderStepped:Connect(function(dt)
    if not _alive or not State.espEnabled then return end
    espTimer += dt
    if espTimer < 0.05 then return end
    espTimer = 0

    local char   = LocalPlayer.Character
    local hrp    = char and char:FindFirstChild("HumanoidRootPart")
    local origin = hrp and hrp.Position or Camera.CFrame.Position

    for model, entry in pairs(_entries) do
        if not _alive then return end
        if not model or not model.Parent then removeEntry(model); continue end
        local root = entry.root
        if not root or not root.Parent then entry.bb.Enabled=false; entry.hl.Enabled=false; continue end

        local dist = (root.Position - origin).Magnitude
        if dist > State.espDistance then entry.bb.Enabled=false; entry.hl.Enabled=false; continue end

        local data    = getCarData(model)
        local tierKey = TIER_SHOW[data.tier.label]
        if tierKey and not State[tierKey] then entry.bb.Enabled=false; entry.hl.Enabled=false; continue end
        if (data.isBuyable and not State.showBuyable) or (not data.isBuyable and not State.showOwned) then
            entry.bb.Enabled=false; entry.hl.Enabled=false; continue
        end

        entry.bb.Size        = UDim2.fromOffset(CFG.BB_W, calcHeight())
        entry.label.Text     = buildRich(data, dist)
        entry.label.TextColor3 = State.useTextColor and State.textColor or Color3.new(1,1,1)
        entry.shadow.Text    = buildPlain(data, dist)
        entry.bb.Enabled     = true

        if State.hlEnabled then
            local tierCol = data.tier.color
            entry.hl.FillColor    = State.useFillColor    and State.fillColor    or tierCol
            entry.hl.OutlineColor = State.useOutlineColor and State.outlineColor or tierCol
            entry.hl.Enabled      = true
        else
            entry.hl.Enabled = false
        end
    end
end))

-- ── RESPAWN BILLBOARD NOTIF ───────────────────────────────────────
local cycleStartTime = nil
local lastBillboard  = nil
local lastBucket     = -1

track(RunService.Heartbeat:Connect(function()
    if not _alive or not State.respawnBillboard then return end
    local t = getJunkyardRespawnTime()
    if not t then return end

    -- Detect new cycle: t jumped UP (timer reset to ~180)
    if lastBillboard and t > lastBillboard + 5 then
        cycleStartTime = tick() - (180 - t)
        lastBucket     = -1
    end
    if not cycleStartTime then
        cycleStartTime = tick() - (180 - t)
    end
    lastBillboard = t

    local elapsed    = math.floor(tick() - cycleStartTime)
    local interval   = State.respawnInterval
    local currBucket = math.floor(elapsed / interval)

    -- Only notify when bucket number INCREASES (once per interval period)
    if currBucket > lastBucket and currBucket > 0 then
        lastBucket = currBucket
        Library:Notify(("⏱ Spawn in %ds | elapsed %ds"):format(t, elapsed), 4)
    end
end))

-- ── FARM ─────────────────────────────────────────────────────────
local farmTimer = 0
track(RunService.Heartbeat:Connect(function(dt)
    if not _alive or not State.farmEnabled then return end
    farmTimer += dt
    if farmTimer < State.farmTick then return end
    farmTimer = 0

    if State.farmMode == 'fix' then
        -- TODO: buy ALL parts for car → sell
        -- Needs: parts list remote, buy remote, sell remote
        print('[AutoFarm] FIX tick – buy all parts + sell (TODO: wire remotes)')
        Library:Notify('Farm: FIX tick', 1)
    elseif State.farmMode == 'repair' then
        -- TODO: buy only broken parts → sell
        -- Needs: condition check, parts event, sell remote
        print('[AutoFarm] REPAIR tick – buy broken parts + sell (TODO: wire remotes)')
        Library:Notify('Farm: REPAIR tick', 1)
    end
end))

-- ── WATERMARK ────────────────────────────────────────────────────
local FrameTimer=tick(); local FrameCounter=0; local FPS=60
track(RunService.RenderStepped:Connect(function()
    if not _alive then return end
    FrameCounter+=1
    if (tick()-FrameTimer)>=1 then FPS=FrameCounter; FrameTimer=tick(); FrameCounter=0 end
    if State.watermark then
        Library:SetWatermark(string.format("CarScript | %s | %s | %d FPS",
            LocalPlayer.Name, os.date("%H:%M:%S"), FPS))
    end
end))

-- ── CAR INFO (seated car) ─────────────────────────────────────────
track(RunService.Heartbeat:Connect(function()
    if not _alive then return end
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    local veh  = seat and seat:FindFirstAncestorWhichIsA("Model")
    if veh and veh ~= workspace and VehicleFolder:FindFirstChild(veh.Name) then
        local data = getCarData(veh)
        local cond = getCondition(veh)
        pcall(function() carNameLbl:SetText("Name:  "..data.name) end)
        pcall(function() carHashLbl:SetText("Hash:  "..data.hash) end)
        pcall(function() carCondLbl:SetText("Cond:  "..tostring(cond).."%") end)
        pcall(function() carPriceLbl:SetText("Price: $"..fmtNum(data.price)) end)
    else
        -- Show selected garage car info
        local sel = Options.MainCarPicker and Options.MainCarPicker.Value
        local entry = sel and garageMap[sel]
        if entry then
            local vals = entry:FindFirstChild("Values")
            local rawName = entry:GetAttribute("Model") or entry.Name
            local hash = isUUID(entry.Name) and shortHash(entry.Name) or entry.Name
            local price = parsePrice(entry:GetAttribute("Price"))
            pcall(function() carNameLbl:SetText("Name:  "..rawName) end)
            pcall(function() carHashLbl:SetText("Hash:  "..hash) end)
            pcall(function() carCondLbl:SetText("Cond:  (not driving)") end)
            pcall(function() carPriceLbl:SetText("Price: $"..fmtNum(price)) end)
        else
            pcall(function() carNameLbl:SetText("Name:  —") end)
            pcall(function() carHashLbl:SetText("Hash:  —") end)
            pcall(function() carCondLbl:SetText("Cond:  —") end)
            pcall(function() carPriceLbl:SetText("Price: —") end)
        end
    end
end))

-- ================================================================
--  STARTUP
-- ================================================================
task.spawn(function()
    task.wait(1)
    refreshGarage()
    buildVehicleDrop()

    -- Load shop parts
    local ok, spareParts = pcall(function()
        return workspace:WaitForChild("PartsStore", 10).SpareParts.Parts
    end)
    if ok and spareParts then
        local cats={}; local items={}
        for _, cat in ipairs(spareParts:GetChildren()) do
            cats[#cats+1] = cat.Name
            local list={}
            for _, it in ipairs(cat:GetChildren()) do list[#list+1]=it.Name end
            items[cat.Name]=list
        end
        if #cats>0 and Options.ShopCategory then
            Options.ShopCategory:SetValues(cats)
            Options.ShopCategory:SetValue(cats[1])
            if Options.ShopItem and items[cats[1]] then
                Options.ShopItem:SetValues(items[cats[1]])
            end
            Options.ShopCategory:OnChanged(function()
                local cat=Options.ShopCategory.Value
                if Options.ShopItem then Options.ShopItem:SetValues(items[cat] or {"—"}) end
            end)
        end
    end

    Library:Notify(string.format("CarScript loaded | Garage: %d | Vehicles: %d",
        #garageList, #VehicleFolder:GetChildren()), 4)
end)

print("[CarScript] Ready.")
