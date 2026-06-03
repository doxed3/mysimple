getgenv().farm = true
getgenv().autosell = true
getgenv().autoboxes = true
getgenv().moneydep = true
getgenv().depmode = "auto" -- "auto" or "hold"
getgenv().depamount = 10

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
local BankFunc = Events:WaitForChild("BankFunc", 10)
local SellFunc = Events:WaitForChild("SellFunc", 10)
local ToolEvent = Events:WaitForChild("ToolEvent")

local backpack = LocalPlayer:WaitForChild("Backpack")
local isTeleporting = false
local farmSpot = nil

local function getBackpackInfo()
    local ok, c, m = pcall(function()
        local label = LocalPlayer.PlayerGui.Main.FrontUI.Backpack.TextLabel
        local c, m = label.Text:match("(%d+)/(%d+)")
        return tonumber(c), tonumber(m)
    end)
    if ok and c then return c, m end
    return 0, 86
end

local function getGroundCFrame(hrp)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    local result = workspace:Raycast(hrp.Position, Vector3.new(0, -50, 0), raycastParams)
    if result then
        return CFrame.new(result.Position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, hrp.CFrame:ToEulerAnglesYXZ())
    end
    return hrp.CFrame
end

local function getTrashItems()
    local items = {}
    local char = LocalPlayer.Character
    for _, v in pairs(backpack:GetChildren()) do
        if v:IsA("Tool") and v.Name:sub(1, 6) == "Trash_" then
            local name = v.Name:sub(7)
            items[name] = (items[name] or 0) + 1
        end
    end
    if char then
        for _, v in pairs(char:GetChildren()) do
            if v:IsA("Tool") and v.Name:sub(1, 6) == "Trash_" then
                local name = v.Name:sub(7)
                items[name] = (items[name] or 0) + 1
            end
        end
    end
    return items
end

local function fixStanding()
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp then return end
    humanoid.PlatformStand = false
    task.wait(0.1)
    humanoid.Jump = true
    task.wait(0.1)
    humanoid.Jump = false
end

-- Deposit loop
task.spawn(function()
    while task.wait(2) do
        if getgenv().moneydep == true then
            if getgenv().depmode == "auto" then
                local ok, data = pcall(function()
                    return BankFunc:InvokeServer("GetData")
                end)
                if ok and data and data.Cash and data.Cash > 0 then
                    pcall(function()
                        BankFunc:InvokeServer("Deposit", data.Cash)
                    end)
                    print("Deposited: $" .. data.Cash)
                end
            elseif getgenv().depmode == "hold" then
                local ok, data = pcall(function()
                    return BankFunc:InvokeServer("GetData")
                end)
                local threshold = getgenv().depamount or 10
                if ok and data and data.Cash and data.Cash >= threshold then
                    pcall(function()
                        BankFunc:InvokeServer("Deposit", data.Cash)
                    end)
                    print("Deposited: $" .. data.Cash .. " (threshold: $" .. threshold .. ")")
                end
            end
        end
    end
end)

-- Auto boxes loop
task.spawn(function()
    local openedBoxes = {}

    task.spawn(function()
        while task.wait(60) do
            openedBoxes = {}
            print("Cleared opened boxes cache")
        end
    end)

    while task.wait(1) do
        if getgenv().autoboxes == true then

            local current, max = getBackpackInfo()
            if current >= max then
                print("Inventory full (" .. current .. "/" .. max .. "), skipping boxes")
                continue
            end

            local char = LocalPlayer.Character
            if not char then continue end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end

            local boxes = {}
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("BasePart") and obj:FindFirstChildOfClass("ProximityPrompt") then
                    local name = obj.Name:lower()
                    local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
                    local promptText = prompt and prompt.ActionText:lower() or ""
                    if (name:find("crate") or name:find("loot") or name:find("chest"))
                    and not promptText:find("upgrade")
                    and not promptText:find("buy")
                    and not promptText:find("shop")
                    and not openedBoxes[obj] then
                        table.insert(boxes, obj)
                    end
                end
            end

            if #boxes > 0 then
                isTeleporting = true
                farmSpot = getGroundCFrame(hrp)
                print("Farm spot saved, opening " .. #boxes .. " boxes")

                for _, box in ipairs(boxes) do
                    if not getgenv().autoboxes then break end

                    local current2, max2 = getBackpackInfo()
                    if current2 >= max2 then
                        print("Inventory full, stopping box loop")
                        break
                    end

                    hrp.CFrame = box.CFrame + Vector3.new(0, 3, 0)
                    task.wait(0.2)

                    local prompt = box:FindFirstChildOfClass("ProximityPrompt")
                    if prompt then
                        pcall(function()
                            fireproximityprompt(prompt)
                        end)
                        openedBoxes[box] = true
                    end

                    task.wait(0.2)
                end

                hrp.CFrame = farmSpot
                task.wait(0.1)
                fixStanding()
                isTeleporting = false
                print("All boxes opened, returned to farm spot")
            end
        end
    end
end)

-- Sell loop
task.spawn(function()
    while task.wait() do
        if getgenv().autosell == true then
            local items = getTrashItems()
            if next(items) then
                items.Type = "Trash"
                pcall(function()
                    SellFunc:InvokeServer("Sell", items)
                end)
            end
        end
    end
end)

-- Farm loop
while task.wait(0.1) do
    if getgenv().farm == true and not isTeleporting then
        ToolEvent:FireServer("Activated", true)
    end
end