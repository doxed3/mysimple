-- ================================================================
--  CarScript  |  Fix It Up  |  v5
--  Based on SucideSquad.lua LinoriaLib patterns
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
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local MarketplaceService = game:GetService("MarketplaceService")

local Camera        = workspace.CurrentCamera
local LocalPlayer   = Players.LocalPlayer
local VehicleFolder = workspace:WaitForChild("Vehicles")
local PlayerData    = LocalPlayer:WaitForChild("PlayerData")
local Garage        = PlayerData:WaitForChild("Garage")

local RemoteLoad = ReplicatedStorage
    :WaitForChild("Events")
    :WaitForChild("Vehicles")
    :WaitForChild("RemoteLoad")

local gameName = pcall(function()
    return MarketplaceService:GetProductInfo(game.PlaceId).Name
end) and MarketplaceService:GetProductInfo(game.PlaceId).Name or "Fix It Up"

-- ── STATE ────────────────────────────────────────────────────────
local State = {
    espEnabled   = false,
    showBuyable  = false,
    showOwned    = false,
    showChances  = true,
    espDistance  = 2000,
    hlEnabled    = false,
    fillColor    = Color3.fromRGB(0, 100, 255),
    outlineColor = Color3.fromRGB(0, 170, 255),
    textColor    = Color3.fromRGB(255, 255, 255),
    showS = true, showA = true, showB = true, showC = true, showD = true,
    farmEnabled  = false,
    farmMode     = "fix",
    farmTick     = 1.0,
    watermark    = false,
}

-- ================================================================
--  CONFIG
-- ================================================================
local CFG = {
    TIERS = {
        { min = 0,       max = 49999,     label = "D", color = Color3.fromRGB(180, 180, 180) },
        { min = 50000,   max = 149999,    label = "C", color = Color3.fromRGB(80,  210, 80)  },
        { min = 150000,  max = 499999,    label = "B", color = Color3.fromRGB(80,  130, 235) },
        { min = 500000,  max = 1499999,   label = "A", color = Color3.fromRGB(210, 80,  235) },
        { min = 1500000, max = math.huge, label = "S", color = Color3.fromRGB(255, 215, 0)   },
    },
    BUYABLE_COLOR = Color3.fromRGB(0,   255, 80),
    OWNED_COLOR   = Color3.fromRGB(255, 60,  60),
    FONT          = Enum.Font.GothamBold,
    TEXT_SIZE     = 13,
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

local function getCarData(model)
    local owner = model:GetAttribute("Owner") or ""
    local price = parsePrice(model:GetAttribute("Price"))
    return {
        name      = model:GetAttribute("Model") or model.Name,
        price     = price,
        owner     = owner,
        chance    = model:GetAttribute("SpawnChance")      or 0,
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

-- ================================================================
--  ESP GUI
-- ================================================================
local espGui = Instance.new("ScreenGui")
espGui.Name           = "CarScriptGui"
espGui.ResetOnSpawn   = false
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
espGui.Parent         = CoreGui
_G.CarScriptGui       = espGui

local function createEntry(model)
    local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not root then return nil end

    local bb = Instance.new("BillboardGui")
    bb.Size                    = UDim2.fromOffset(220, 72)
    bb.StudsOffsetWorldSpace   = Vector3.new(0, 4.5, 0)
    bb.AlwaysOnTop             = true
    bb.Adornee                 = root
    bb.Enabled                 = false
    bb.Parent                  = espGui

    local shadow = Instance.new("TextLabel")
    shadow.BackgroundTransparency = 1
    shadow.Size       = UDim2.new(1, 2, 1, 2)
    shadow.Position   = UDim2.fromOffset(1, 1)
    shadow.TextColor3 = Color3.new(0, 0, 0)
    shadow.Font       = CFG.FONT
    shadow.TextSize   = CFG.TEXT_SIZE
    shadow.TextWrapped = true
    shadow.RichText   = false
    shadow.ZIndex     = 2
    shadow.Parent     = bb

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
    hl.FillColor          = State.fillColor
    hl.OutlineColor       = State.outlineColor
    hl.FillTransparency   = 0.5
    hl.OutlineTransparency = 0
    hl.Adornee            = model
    hl.Enabled            = false
    hl.Parent             = espGui

    return { bb=bb, shadow=shadow, label=label, hl=hl, root=root }
end

local function rgb(c)
    return ("rgb(%d,%d,%d)"):format(
        math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255))
end

local function buildRich(data, dist)
    local tc  = data.isBuyable and CFG.BUYABLE_COLOR or CFG.OWNED_COLOR
    local rc  = data.tier.color
    local tag = data.isBuyable and "[BUYABLE]" or ("[OWNED: "..data.owner.."]")
    local ch  = State.showChances and (" | "..data.chance.."%") or ""
    return (
        '<font color="%s"><b>%s</b></font>\n'
     .. '<font color="%s"><b>%s</b></font>\n'
     .. '<font color="rgb(200,200,200)">Tier: </font><font color="%s"><b>%s</b></font>'
     .. '<font color="rgb(200,200,200)">%s | $%s\nProfit: x%s | %d studs</font>'
    ):format(
        rgb(tc), tag,
        rgb(rc), data.name,
        rgb(rc), data.tier.label,
        ch, fmtNum(data.price), tostring(data.profit), math.floor(dist)
    )
end

local function buildPlain(data, dist)
    local tag = data.isBuyable and "[BUYABLE]" or ("[OWNED: "..data.owner.."]")
    local ch  = State.showChances and (" | "..data.chance.."%") or ""
    return ("%s\n%s\nTier: %s%s | $%s | %d studs"):format(
        tag, data.name, data.tier.label, ch, fmtNum(data.price), math.floor(dist))
end

-- ================================================================
--  VEHICLE SCAN
-- ================================================================
local function addEntry(model)
    if not model:IsA("Model") or _entries[model] then return end
    -- Model may have just spawned with no parts yet — wait for a BasePart
    local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not root then
        task.spawn(function()
            -- Wait up to 5s for a BasePart to appear
            local deadline = tick() + 5
            while tick() < deadline do
                task.wait(0.1)
                root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if root or not model.Parent then break end
            end
            -- Re-check after wait (model might have been removed)
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
track(VehicleFolder.ChildAdded:Connect(addEntry))
track(VehicleFolder.ChildRemoved:Connect(removeEntry))

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

-- ── GROUPS ──────────────────────────────────────────────────────
local CarGroup   = Tabs.Main:AddLeftGroupbox('Car')
local TeleGroup  = Tabs.Main:AddLeftGroupbox('Teleporting')
local SpawnGroup = Tabs.Main:AddRightGroupbox('Spawn Car')
local ShopGroup  = Tabs.Main:AddRightGroupbox('Shop')

local JunkCfg    = Tabs.Junkyard:AddLeftGroupbox('Configuration')
local TierGroup  = Tabs.Junkyard:AddRightGroupbox('Tiers')

local FarmMain   = Tabs.Farm:AddLeftGroupbox('AutoFarm')
local FarmInfo   = Tabs.Farm:AddRightGroupbox('Info')

local MenuGroup  = Tabs.UI:AddLeftGroupbox('Menu')

-- ================================================================
--  MAIN TAB – Car Info
-- ================================================================
local carNameLbl = CarGroup:AddLabel("Name: —")
local carCondLbl = CarGroup:AddLabel("Condition: —")
local carPriceLbl = CarGroup:AddLabel("Price: —")

CarGroup:AddButton({
    Text = 'Respawn Car',
    Func = function()
        -- TODO: fire Respawn remote
        print('[CarScript] Respawn fired')
        Library:Notify('Respawn sent')
    end,
    DoubleClick = false,
    Tooltip = 'Respawn your current car'
})
CarGroup:AddButton({
    Text = 'Repair Car',
    Func = function()
        -- TODO: fire Repair remote
        print('[CarScript] Repair fired')
        Library:Notify('Repair sent')
    end,
    DoubleClick = false,
    Tooltip = 'Repair your current car'
})
CarGroup:AddButton({
    Text = 'Sell Car',
    Func = function()
        -- TODO: fire Sell remote
        print('[CarScript] Sell fired')
        Library:Notify('Sell sent')
    end,
    DoubleClick = true,
    Tooltip = 'Double-click to sell your current car'
})

-- ================================================================
--  MAIN TAB – Teleport
-- ================================================================
TeleGroup:AddDropdown('TeleLocation', {
    Values  = { 'Garage', 'Junkyard', 'Spare Parts (Shop)', 'AutoShop (Repair)', 'PitWheels', 'Gas Station', 'Sell', 'Dyno Tune' },
    Default = 'Garage',
    Multi   = false,
    Text    = 'Location',
    Tooltip = 'Select teleport destination',
    Callback = function(_) end,
})

-- Teleport destination map
local TeleDestinations = {
    ['Garage'] = function()
        local part = workspace.Garages.Default.Exterior.Road
        if not part then return nil end
        if part:IsA("BasePart") then return part.CFrame end
        local bp = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
        return bp and bp.CFrame or nil
    end,
    ['Junkyard'] = function()
        local decor = workspace.Map.FirstCity.Junkyard.Decor
        if not decor then return nil end
        local part = decor:GetChildren()[53]
        if not part then return nil end
        if part:IsA("BasePart") then return part.CFrame end
        local bp = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
        return bp and bp.CFrame or nil
    end,
    ['Spare Parts (Shop)'] = function()
        local model = workspace.Map.FirstCity.SparePartsShop.SparePartsShop["Cash out area"]
        if not model then return nil end
        local bp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        return bp and bp.CFrame or nil
    end,
    ['AutoShop (Repair)'] = function()
        local building = workspace.Map.FirstCity.Buildings["PitStop(Large)"]
        if not building then return nil end
        local part = building:GetChildren()[88]
        if not part then return nil end
        if part:IsA("BasePart") then return part.CFrame end
        local bp = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
        return bp and bp.CFrame or nil
    end,
    ['PitWheels'] = function()
        local part = workspace.Map.FirstCity.Buildings:GetChildren()[124]
        if not part then return nil end
        if part:IsA("BasePart") then return part.CFrame end
        local bp = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
        return bp and bp.CFrame or nil
    end,
    ['Gas Station'] = function()
        local building = workspace.Map.FirstCity.Buildings:GetChildren()[80]
        if not building then return nil end
        local part = building:FindFirstChild("Road")
            or building.PrimaryPart
            or building:FindFirstChildWhichIsA("BasePart")
        return part and part.CFrame or nil
    end,
    ['Sell'] = function()
        local part = workspace.Map.Map.Barraca.Part
        if not part then return nil end
        if part:IsA("BasePart") then return part.CFrame end
        local bp = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
        return bp and bp.CFrame or nil
    end,
    ['Dyno Tune'] = function()
        local part = workspace.Map.Map.dynotune:GetChildren()[17]
        if not part then return nil end
        if part:IsA("BasePart") then return part.CFrame end
        local bp = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
        return bp and bp.CFrame or nil
    end,
}

TeleGroup:AddButton({
    Text = 'Teleport',
    Func = function()
        local loc = Options.TeleLocation and Options.TeleLocation.Value or 'Junkyard'
        local destFn = TeleDestinations[loc]
        local cf = destFn and destFn()

        if cf then
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = cf + Vector3.new(0, 5, 0)
                Library:Notify("Teleported to " .. loc)
            else
                Library:Notify("No character found")
            end
        else
            -- TODO: fire server Teleport remote for other locations
            print('[CarScript] Teleport →', loc, '(no CFrame set yet)')
            Library:Notify('TODO: wire ' .. loc .. ' teleport')
        end
    end,
    DoubleClick = false,
    Tooltip = 'Teleport to selected location'
})

-- ================================================================
--  MAIN TAB – Spawn Car
-- ================================================================
SpawnGroup:AddDropdown('GaragePicker', {
    Values  = { '(loading...)' },
    Default = '(loading...)',
    Multi   = false,
    Text    = 'Your Cars',
    Tooltip = 'Cars from PlayerData.Garage',
    Callback = function(_) end,
})
SpawnGroup:AddToggle('EnterOnSpawn', {
    Text    = 'Enter on Spawn',
    Default = false,
    Tooltip = 'Auto-sit in car after spawning',
    Callback = function(_) end,
})
SpawnGroup:AddButton({
    Text = 'Spawn',
    Func = spawnCar,
    DoubleClick = false,
    Tooltip = 'Spawn selected garage car'
})
SpawnGroup:AddButton({
    Text = 'Refresh List',
    Func = function()
        refreshGarage()
        Library:Notify(#garageList..' car(s) found')
    end,
    DoubleClick = false,
    Tooltip = 'Re-scan PlayerData.Garage'
})

-- ================================================================
--  MAIN TAB – Shop
-- ================================================================
ShopGroup:AddDropdown('ShopCategory', {
    Values  = { 'AirSuspension','Generic','Rot 1.3','Transmission',
                'V10 5.2','V6 3.0D','V6 3.8','V8 4.0','V8 4.2',
                'i3 1.0','i4 1.9D','i4 2.0','i4 2.0 VETC','i5 2.5','i6 3.0' },
    Default = 'i4 2.0',
    Multi   = false,
    Text    = 'Category',
    Tooltip = 'Engine / part type',
    Callback = function(_) end,
})
Options.ShopCategory:OnChanged(function()
    -- item list updates via task.spawn shop loader below
end)

ShopGroup:AddDropdown('ShopItem', {
    Values  = { '—' },
    Default = '—',
    Multi   = false,
    Text    = 'Item',
    Tooltip = 'Part to buy',
    Callback = function(_) end,
})
local PartsEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("PartsEvent")

local function buyPart()
    local cat  = Options.ShopCategory and Options.ShopCategory.Value
    local item = Options.ShopItem     and Options.ShopItem.Value
    if not cat or not item or item == "—" then
        Library:Notify("Select a category and item first!")
        return
    end

    local partModel = workspace.PartsStore
        and workspace.PartsStore.SpareParts
        and workspace.PartsStore.SpareParts.Parts
        and workspace.PartsStore.SpareParts.Parts:FindFirstChild(cat)
        and workspace.PartsStore.SpareParts.Parts[cat]:FindFirstChild(item)

    if not partModel then
        Library:Notify("Part not found: "..cat.." / "..item)
        return
    end

    -- Fire the same remote the ClickDetector fires
    local ok, err = pcall(function()
        PartsEvent:FireServer(partModel)
    end)

    if ok then
        Library:Notify("Bought: "..item.." ("..cat..")")
        print("[CarScript] Buy fired →", partModel:GetFullName())
    else
        Library:Notify("Buy failed: "..tostring(err))
        warn("[CarScript] PartsEvent error:", err)
    end
end

ShopGroup:AddButton({
    Text = 'Buy',
    Func = buyPart,
    DoubleClick = false,
    Tooltip = 'Buy selected part via PartsEvent'
})

-- ================================================================
--  JUNKYARD TAB – Configuration
-- ================================================================
local respawnLbl = JunkCfg:AddLabel('Next Respawn: —')

JunkCfg:AddToggle('ESPEnabled', {
    Text    = 'Junkyard ESP',
    Default = false,
    Tooltip = 'Show labels above junkyard cars',
    Callback = function(v)
        State.espEnabled = v
        if not v then
            for _, e in pairs(_entries) do
                e.bb.Enabled = false
                e.hl.Enabled = false
            end
        end
    end,
})

JunkCfg:AddToggle('ShowChances', {
    Text    = 'Show Chances',
    Default = true,
    Tooltip = 'Show spawn % in label',
    Callback = function(v) State.showChances = v end,
})

JunkCfg:AddToggle('HLEnabled', {
    Text    = 'Highlights (Chams)',
    Default = false,
    Tooltip = 'Blue glow outline on cars',
    Callback = function(v)
        State.hlEnabled = v
        if not v then
            for _, e in pairs(_entries) do e.hl.Enabled = false end
        end
    end,
})

JunkCfg:AddToggle('ShowBuyable', {
    Text    = 'Show Buyable',
    Default = false,
    Tooltip = 'Show green [BUYABLE] labels',
    Callback = function(v) State.showBuyable = v end,
})

JunkCfg:AddToggle('ShowOwned', {
    Text    = 'Show Owned',
    Default = false,
    Tooltip = 'Show red [OWNED] labels',
    Callback = function(v) State.showOwned = v end,
})

JunkCfg:AddToggle('FillColorEnabled', {
    Text    = 'Fill Color',
    Default = false,
    Tooltip = 'Highlight fill color',
    Callback = function(_) end,
}):AddColorPicker('FillColor', {
    Default  = Color3.fromRGB(0, 100, 255),
    Title    = 'Fill Color',
    Callback = function(v)
        State.fillColor = v
        for _, e in pairs(_entries) do e.hl.FillColor = v end
    end,
})

JunkCfg:AddToggle('OutlineColorEnabled', {
    Text    = 'Outline Color',
    Default = false,
    Tooltip = 'Highlight outline color',
    Callback = function(_) end,
}):AddColorPicker('OutlineColor', {
    Default  = Color3.fromRGB(0, 170, 255),
    Title    = 'Outline Color',
    Callback = function(v)
        State.outlineColor = v
        for _, e in pairs(_entries) do e.hl.OutlineColor = v end
    end,
})

JunkCfg:AddToggle('TextColorEnabled', {
    Text    = 'Text Color',
    Default = false,
    Tooltip = 'ESP label text color',
    Callback = function(_) end,
}):AddColorPicker('TextColor', {
    Default  = Color3.fromRGB(255, 255, 255),
    Title    = 'Text Color',
    Callback = function(v) State.textColor = v end,
})

JunkCfg:AddSlider('ESPDistance', {
    Text     = 'Max Distance (studs)',
    Default  = 2000,
    Min      = 100,
    Max      = 5000,
    Rounding = 0,
    Tooltip  = 'Hide labels beyond this distance',
    Callback = function(v) State.espDistance = v end,
})

-- ================================================================
--  JUNKYARD TAB – Tiers
-- ================================================================
TierGroup:AddToggle('ShowTierS', {
    Text = 'Tier S  (Gold)',   Default = true,
    Callback = function(v) State.showS = v end,
})
TierGroup:AddToggle('ShowTierA', {
    Text = 'Tier A  (Purple)', Default = true,
    Callback = function(v) State.showA = v end,
})
TierGroup:AddToggle('ShowTierB', {
    Text = 'Tier B  (Blue)',   Default = true,
    Callback = function(v) State.showB = v end,
})
TierGroup:AddToggle('ShowTierC', {
    Text = 'Tier C  (Green)',  Default = true,
    Callback = function(v) State.showC = v end,
})
TierGroup:AddToggle('ShowTierD', {
    Text = 'Tier D  (Gray)',   Default = true,
    Callback = function(v) State.showD = v end,
})

-- ================================================================
--  FARM TAB
-- ================================================================
FarmMain:AddToggle('FarmEnabled', {
    Text    = 'Enable AutoFarm',
    Default = false,
    Tooltip = 'Start the autofarm loop',
    Callback = function(v) State.farmEnabled = v end,
})

FarmMain:AddDropdown('FarmMode', {
    Values   = { 'fix', 'buy' },
    Default  = 'fix',
    Multi    = false,
    Text     = 'Mode',
    Tooltip  = '"fix" repairs  |  "buy" buys from junkyard',
    Callback = function(v) State.farmMode = v end,
})

FarmMain:AddSlider('FarmTick', {
    Text     = 'Tick Rate (s)',
    Default  = 1,
    Min      = 0,
    Max      = 10,
    Rounding = 1,
    Tooltip  = 'Seconds between each farm action',
    Callback = function(v) State.farmTick = v end,
})

FarmInfo:AddLabel('fix  – fires Repair remote')
FarmInfo:AddLabel('buy  – fires Buy remote')
FarmInfo:AddLabel(' ')
FarmInfo:AddLabel('Wire remotes when ready.')

-- ================================================================
--  UI SETTINGS TAB
-- ================================================================
MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', {
    Default = 'Delete',
    NoUI    = true,
    Text    = 'Menu keybind',
})
MenuGroup:AddToggle('Watermark', {
    Text    = 'Watermark',
    Default = false,
    Tooltip = 'Toggle watermark',
    Callback = function(v)
        State.watermark = v
        Library:SetWatermarkVisibility(v)
    end,
})
MenuGroup:AddToggle('KeybindList', {
    Text    = 'Keybind List',
    Default = false,
    Tooltip = 'Show keybind panel',
    Callback = function(v)
        Library.KeybindFrame.Visible = v
    end,
})

Library.ToggleKeybind      = Options.MenuKeybind
Library.KeybindFrame.Visible = false

do
    Library:SetWatermark(string.format(
        "CarScript | %s | %s | %s", gameName, LocalPlayer.Name, os.date("%H:%M:%S")))
end
Library:SetWatermarkVisibility(false)

Library:OnUnload(function()
    _G.CarScriptKill()
    print('[CarScript] Unloaded')
end)

-- ── SAVE / THEME ─────────────────────────────────────────────────
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })
ThemeManager:SetFolder('CarScript')
SaveManager:SetFolder('CarScript/config')
SaveManager:BuildConfigSection(Tabs.UI)
ThemeManager:ApplyToTab(Tabs.UI)
SaveManager:LoadAutoloadConfig()

-- ================================================================
--  LOOPS  (after all UI, read State only)
-- ================================================================

-- ── ESP ──────────────────────────────────────────────────────────
local espTimer = 0
track(RunService.RenderStepped:Connect(function(dt)
    if not _alive then return end
    if not State.espEnabled then return end
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
        if not root or not root.Parent then
            entry.bb.Enabled = false; entry.hl.Enabled = false; continue
        end

        local dist = (root.Position - origin).Magnitude
        if dist > State.espDistance then
            entry.bb.Enabled = false; entry.hl.Enabled = false; continue
        end

        local data   = getCarData(model)
        local tierKey = TIER_SHOW[data.tier.label]
        if tierKey and not State[tierKey] then
            entry.bb.Enabled = false; entry.hl.Enabled = false; continue
        end

        if (data.isBuyable and not State.showBuyable)
        or (not data.isBuyable and not State.showOwned) then
            entry.bb.Enabled = false; entry.hl.Enabled = false; continue
        end

        entry.label.Text        = buildRich(data, dist)
        entry.label.TextColor3  = State.textColor
        entry.shadow.Text       = buildPlain(data, dist)
        entry.bb.Enabled        = true
        entry.hl.Enabled        = State.hlEnabled
    end
end))

-- ── FARM ─────────────────────────────────────────────────────────
local farmTimer = 0
track(RunService.Heartbeat:Connect(function(dt)
    if not _alive then return end
    if not State.farmEnabled then return end
    farmTimer += dt
    if farmTimer < State.farmTick then return end
    farmTimer = 0

    if State.farmMode == 'fix' then
        -- TODO: fire Repair remote (need RemoteRepair event)
        print('[AutoFarm] FIX tick')
        Library:Notify('AutoFarm: FIX', 1)
    elseif State.farmMode == 'buy' then
        -- Fire PartsEvent with currently selected shop item
        local cat  = Options.ShopCategory and Options.ShopCategory.Value
        local item = Options.ShopItem     and Options.ShopItem.Value
        if cat and item and item ~= "—" then
            local partModel = workspace.PartsStore
                and workspace.PartsStore.SpareParts
                and workspace.PartsStore.SpareParts.Parts
                and workspace.PartsStore.SpareParts.Parts:FindFirstChild(cat)
                and workspace.PartsStore.SpareParts.Parts[cat]:FindFirstChild(item)
            if partModel then
                pcall(function() PartsEvent:FireServer(partModel) end)
                print('[AutoFarm] BUY tick →', cat, item)
                Library:Notify('AutoFarm: BUY '..item, 1)
            else
                print('[AutoFarm] BUY tick – part not found:', cat, item)
            end
        else
            print('[AutoFarm] BUY tick – no item selected in Shop tab')
        end
    end
end))

-- ── WATERMARK ────────────────────────────────────────────────────
local FrameTimer   = tick()
local FrameCounter = 0
local FPS          = 60

track(RunService.RenderStepped:Connect(function()
    if not _alive then return end
    FrameCounter += 1
    if (tick() - FrameTimer) >= 1 then
        FPS = FrameCounter; FrameTimer = tick(); FrameCounter = 0
    end
    if State.watermark then
        Library:SetWatermark(string.format(
            "CarScript | %s | %s | %d FPS",
            LocalPlayer.Name, os.date("%H:%M:%S"), FPS))
    end
end))

-- ── CAR INFO ─────────────────────────────────────────────────────
track(RunService.Heartbeat:Connect(function()
    if not _alive then return end
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    local veh  = seat and seat:FindFirstAncestorWhichIsA("Model")

    if veh and veh ~= workspace and VehicleFolder:FindFirstChild(veh.Name) then
        local data = getCarData(veh)
        local cond = getCondition(veh)
        pcall(function() carNameLbl:SetText("Name: "..data.name) end)
        pcall(function() carCondLbl:SetText("Condition: "..tostring(cond).."%") end)
        pcall(function() carPriceLbl:SetText("Price: $"..fmtNum(data.price)) end)
    else
        pcall(function() carNameLbl:SetText("Name: —") end)
        pcall(function() carCondLbl:SetText("Condition: —") end)
        pcall(function() carPriceLbl:SetText("Price: —") end)
    end
end))

-- ================================================================
--  STARTUP
-- ================================================================
task.spawn(function()
    -- Garage
    task.wait(1)
    refreshGarage()

    -- Shop parts from PartsStore
    local ok, spareParts = pcall(function()
        return workspace:WaitForChild("PartsStore", 10).SpareParts.Parts
    end)
    if ok and spareParts then
        local cats  = {}
        local items = {}
        for _, cat in ipairs(spareParts:GetChildren()) do
            cats[#cats+1] = cat.Name
            local list = {}
            for _, it in ipairs(cat:GetChildren()) do list[#list+1] = it.Name end
            items[cat.Name] = list
        end
        if #cats > 0 and Options.ShopCategory then
            Options.ShopCategory:SetValues(cats)
            Options.ShopCategory:SetValue(cats[1])
            if Options.ShopItem and items[cats[1]] then
                Options.ShopItem:SetValues(items[cats[1]])
            end
            Options.ShopCategory:OnChanged(function()
                local cat = Options.ShopCategory.Value
                if Options.ShopItem then
                    Options.ShopItem:SetValues(items[cat] or {"—"})
                end
            end)
        end
    end

    Library:Notify(string.format(
        "CarScript loaded | Garage: %d | Vehicles: %d",
        #garageList, #VehicleFolder:GetChildren()), 4)
end)

print("[CarScript] Ready.")