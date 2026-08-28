-- Script taken from https://xenoscripts.com website --
-- Модифицирован: добавлены Bang/Jerk, исправлен умный фарм (золото теперь засчитывается)

-- services --
local vim = game:GetService("VirtualInputManager")
local players = game:GetService("Players")
local TS = game:GetService("TweenService")
local workspace = game:GetService("Workspace")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local player = players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local HRP = character:WaitForChild("HumanoidRootPart")
local tweening = false
local index = 1

-- rayfield --
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
   Name = "Строительство лодки для сокровищ",
   Icon = 0,
   LoadingTitle = "Rayfield Interface Suite",
   LoadingSubtitle = "by Sirius",
   Theme = "Default",
   ToggleUIKeybind = "G",
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
   ConfigurationSaving = {
      Enabled = true,
      FolderName = "BABFT",
      FileName = "Build A Boat Config"
   },
})

local specialList = {"Glue"}
local blockData = player:WaitForChild("Data")
local blocksFolder = workspace:WaitForChild("Blocks")
local pastePercent = 0
local usedList = {}
local selectedBase = nil
local autofarm = false
local rescaleClick = false
local playerToBring = nil
local ignoreAnchored = true
local clipboard = nil

-- ===== ВСЕ СТАРЫЕ ФУНКЦИИ (копирование, вставка, покраска, масштабирование и т.д.) =====
local function getBlockID(name)
    return blockData:FindFirstChild(name) and blockData:FindFirstChild(name).Value or 9
end

local function setTransparency(transparencyWanted, block)
    if not block then return end
    if block.PPart.Transparency == transparencyWanted then return end
    local calls = transparencyWanted / 0.25
    local tool
    if character:FindFirstChild("PropertiesTool") then
        tool = character["PropertiesTool"]
    else
        humanoid:EquipTool(player.Backpack.PropertiesTool)
        task.wait()
        tool = character.PropertiesTool
    end
    local args = { "Transparency", { block } }
    task.spawn(function()
        for i = 1, calls do
            tool.SetPropertieRF:InvokeServer(unpack(args))
        end
    end)
end

local function setAnchored(block)
    if not block then return end
    local tool
    if character:FindFirstChild("PropertiesTool") then
        tool = character["PropertiesTool"]
    else
        humanoid:EquipTool(player.Backpack.PropertiesTool)
        task.wait()
        tool = character.PropertiesTool
    end
    local args = { "Anchored", { block } }
    task.spawn(function()
        tool.SetPropertieRF:InvokeServer(unpack(args))
    end)
end

local function rescaleBlock(block, newPos, newSize)
    if not block then return end
    local tool
    if character:FindFirstChild("ScalingTool") then
        tool = character["ScalingTool"]
    else
        humanoid:EquipTool(player.Backpack.ScalingTool)
        task.wait()
        tool = character.ScalingTool
    end
    local args = { block, newSize, newPos }
    task.spawn(function()
        tool.RF:InvokeServer(unpack(args))
    end)
end

local function getPlayerZone(playerInstance)
    local teamColor = playerInstance.TeamColor
    for _, v in pairs(workspace:GetChildren()) do
        if v:FindFirstChild("TeamColor") and v.TeamColor.Value then
            if v.TeamColor.Value == teamColor then
                return v
            end
        end
    end
    return nil
end

local function placeBlock(name, pos, relativeTo, Anchored)
    local tool
    if character:FindFirstChild("BuildingTool") then
        tool = character["BuildingTool"]
    else
        humanoid:EquipTool(player.Backpack.BuildingTool)
        task.wait()
        tool = character.BuildingTool
    end
    if not relativeTo then relativeTo = getPlayerZone(player) end
    local args = {
        name,
        getBlockID(name),
        relativeTo,
        relativeTo and relativeTo.CFrame:ToObjectSpace(pos) or CFrame.new(),
        ignoreAnchored and true or Anchored,
        pos,
        false,
    }
    task.spawn(function()
        tool.RF:InvokeServer(unpack(args))
    end)
end

local function paintBlock(block, color)
    if not block or not block:FindFirstChild("PPart") then return end
    if block.PPart.Color == color then return end
    local tool
    if character:FindFirstChild("PaintingTool") then
        tool = character["PaintingTool"]
    else
        humanoid:EquipTool(player.Backpack.PaintingTool)
        task.wait()
        tool = character.PaintingTool
    end
    local args = { { block, color } }
    task.spawn(function()
        tool.RF:InvokeServer(args)
    end)
end

local function getJoint(model)
    for _, v in pairs(model.PPart:GetChildren()) do
        if v:IsA("Snap") or v:IsA("Weld") then
            if v.Part1 and v.Part1.Parent ~= model then
                return v.Part1
            end
        end
    end
    return getPlayerZone(player)
end

local function getNewBlockPos(hisBase, block, myBase)
    if not block or not block:FindFirstChild("PPart") then
        return CFrame.new()
    end
    if not hisBase or not myBase then
        return block.PPart.CFrame
    end
    local offset = hisBase.CFrame:ToObjectSpace(block.PPart.CFrame)
    return myBase.CFrame * offset
end

local function copyBuild(blocks)
    local t = {}
    local myBase = getPlayerZone(player)
    local hisBase = getPlayerZone(players:FindFirstChild(blocks.Name))
    for _, block in ipairs(blocks:GetChildren()) do
        if block:FindFirstChild("PPart") then
            if not (getBlockID(block.Name) == 0 or (usedList[block.Name] or 0) > getBlockID(block.Name)) then
                local relative = getJoint(block)
                relative = (relative == hisBase and myBase) or relative
                usedList[block.Name] = (usedList[block.Name] or 0) + 1
                table.insert(t, {
                    Name = block.Name,
                    Pos = getNewBlockPos(hisBase, block, myBase),
                    Relative = getPlayerZone(player),
                    Transparency = block.PPart.Transparency,
                    Anchored = block.PPart.Anchored,
                    Size = block.PPart.Size,
                    Color = block.PPart.Color
                })
            end
        end
    end
    return t
end

local function getMissingBlocks(expectedList, createdList)
    local missing = {}
    for i, v in ipairs(expectedList) do
        local found = false
        for _, b in ipairs(createdList) do
            if b and b:FindFirstChild("PPart") and b.Name == v.Name then
                found = true
                break
            end
        end
        if not found then
            table.insert(missing, { Index = i, Name = v.Name, Pos = v.Pos })
        end
    end
    return missing
end

local function getBlock(expected, createdList)
    local best, bestDist = nil, math.huge
    for _, b in ipairs(createdList) do
        if b and b:FindFirstChild("PPart") and b.Name == expected.Name then
            local dist = (b.PPart.Position - expected.Pos.Position).Magnitude
            if dist < bestDist then
                bestDist, best = dist, b
            end
        end
    end
    return best
end

local function getPlayerBase()
    for _, child in pairs(blocksFolder:GetChildren()) do
        if child.Name == player.Name then
            return child
        end
    end
end

local function pasteBuild(t, folder)
    pastePercent = 0
    local childrenDebug, c, blocks, tCount = 0, nil, {}, #t
    local lastPlaced = tick()
    c = folder.ChildAdded:Connect(function(child)
        childrenDebug = childrenDebug + 1
        lastPlaced = tick()
    end)
    for i, v in ipairs(t) do
        placeBlock(v.Name, v.Pos, v.Relative, v.Anchored)
        pastePercent = pastePercent + 50 / tCount
        if i % 20 == 0 then task.wait(0.05) end
    end
    repeat task.wait(0.1) until tick() - lastPlaced > 5
    local playerBaseList = folder:GetChildren()
    for i, v in ipairs(t) do
        local b = getBlock(v, playerBaseList)
        if b then
            rescaleBlock(b, v.Pos, v.Size)
            paintBlock(b, v.Color)
            setTransparency(v.Transparency, b)
        end
        if i % 20 == 0 then task.wait(0.05) end
        pastePercent = pastePercent + 50 / tCount
    end
    c:Disconnect()
    pastePercent = 0
end

local function getPlayers()
    local list = {}
    for _, p in pairs(game:GetService("Players"):GetChildren()) do
        table.insert(list, p.DisplayName)
    end
    return list
end

local function bringPlayer(playerToBring, firstSeat, secondSeat)
    local originalPos = character:GetPivot()
    local otherChar = playerToBring.Character
    if not otherChar then return end
    local offset = firstSeat.CFrame:Inverse() * secondSeat.CFrame
    repeat
        local torso = otherChar:FindFirstChild("LowerTorso") or otherChar:FindFirstChild("Torso")
        if torso then
            local newPivot = torso.CFrame * offset:Inverse()
            firstSeat:PivotTo(newPivot + Vector3.new(math.random(-1,1), math.random(-1,1), math.random(-1,1)))
        end
        task.wait(0.5)
    until not otherChar.Parent or otherChar.Humanoid.SeatPart
    firstSeat:PivotTo(originalPos)
end

local function getCar()
    return humanoid.SeatPart and humanoid.SeatPart.Parent or nil
end

-- ===== СТАРЫЕ ВКЛАДКИ =====
local autoBuildTab = Window:CreateTab("Строительство", "rewind")
autoBuildTab:CreateButton({
    Name = "Поставить деревянный блок",
    Callback = function()
        placeBlock("WoodBlock", HRP.CFrame, nil, true)
    end,
})
autoBuildTab:CreateToggle({
    Name = "Изменить размер блока (клик по блоку)",
    Callback = function(Value)
        rescaleClick = Value
    end,
})
local mouse = player:GetMouse()
mouse.Button1Down:Connect(function()
    if rescaleClick and mouse.Target then
        local ppart = mouse.Target
        rescaleBlock(ppart.Parent, ppart.CFrame, Vector3.new(4, 4, 4))
    end
end)

local function getRealName(displayName)
    for _, p in pairs(players:GetChildren()) do
        if p.DisplayName == displayName then return p.Name end
    end
    return nil
end

local dd = autoBuildTab:CreateDropdown({
    Name = "Выберите базу игрока для копирования",
    Options = getPlayers(),
    CurrentOption = { "Ничего не выбрано" },
    MultipleOptions = false,
    Callback = function(Options)
        local realName = getRealName(Options[1])
        for _, folder in pairs(blocksFolder:GetChildren()) do
            if folder.Name == realName then
                selectedBase = folder
                break
            end
        end
    end,
})
players.PlayerAdded:Connect(function()
    dd:Refresh(getPlayers())
end)

autoBuildTab:CreateButton({
    Name = "Копировать базу",
    Callback = function()
        if selectedBase then
            clipboard = copyBuild(selectedBase)
        else
            Rayfield:Notify({
                Title = "Пожалуйста, выберите действующего игрока",
                Content = "Либо игрок не выбран, либо он вышел",
                Duration = 10,
                Image = "alert-triangle"
            })
        end
    end,
})
autoBuildTab:CreateButton({
    Name = "Вставить базу",
    Callback = function()
        if clipboard then
            pasteBuild(clipboard, getPlayerBase())
        end
    end,
})
local pasteStatus = autoBuildTab:CreateParagraph({
    Title = "Прогресс автопостройки",
    Content = "0%"
})
task.spawn(function()
    while task.wait(0.2) do
        pasteStatus:Set({ Title = "Прогресс автопостройки", Content = tostring(pastePercent) .. "%" })
    end
end)
autoBuildTab:CreateSection("Настройки автопостройки")
autoBuildTab:CreateToggle({
    Name = "Игнорировать закрепление",
    CurrentValue = true,
    Callback = function(Value)
        ignoreAnchored = Value
    end,
})

-- Обычный автофарм (до сундука)
local autoFarmTab = Window:CreateTab("Автофарм", "rewind")
autoFarmTab:CreateToggle({
    Name = "Вкл/выкл автоФарм (до сундука)",
    CurrentValue = false,
    Callback = function(value)
        autofarm = value
    end,
})

-- Развлечения (старые + новые)
local funTab = Window:CreateTab("Развлечения", "rewind")
local firstSeat, secondSeat = nil, nil
funTab:CreateSection("Притянуть игрока")
local dd2 = funTab:CreateDropdown({
    Name = "Выберите игрока для действий",
    Options = getPlayers(),
    CurrentOption = { "Ничего не выбрано" },
    MultipleOptions = false,
    Callback = function(Options)
        local realName = getRealName(Options[1])
        playerToBring = players:FindFirstChild(realName)
    end,
})
players.PlayerAdded:Connect(function()
    dd2:Refresh(getPlayers())
end)

funTab:CreateButton({
    Name = "Сядьте на первое сиденье и нажмите",
    Callback = function()
        firstSeat = humanoid.SeatPart
        print("firstSeat:", firstSeat:GetFullName())
    end,
})
funTab:CreateButton({
    Name = "Сядьте на второе сиденье и нажмите",
    Callback = function()
        secondSeat = humanoid.SeatPart
        print("secondSeat:", secondSeat:GetFullName())
    end,
})
funTab:CreateButton({
    Name = "Притянуть игрока после выбора",
    Callback = function()
        if secondSeat and firstSeat and secondSeat ~= firstSeat then
            if playerToBring then
                bringPlayer(playerToBring, firstSeat, secondSeat)
            else
                Rayfield:Notify({ Name = "Выберите игрока", Content = "Игрок не выбран", Duration = 5, Image = "alert-triangle" })
            end
        else
            Rayfield:Notify({ Name = "Ошибка", Content = "Выберите два разных сиденья", Duration = 5, Image = "alert-triangle" })
        end
    end,
})

funTab:CreateButton({
    Name = "Полет на машине",
    Callback = function()
        local Players = game:GetService("Players")
        local RunService = game:GetService("RunService")
        local UserInputService = game:GetService("UserInputService")
        local localPlayer = Players.LocalPlayer
        local localHumanoid = localPlayer.Character and localPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        local flying = false
        local flySpeed = 50
        local flyConnection, bv
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "CarFlyGUI"
        screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
        screenGui.ResetOnSpawn = false
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 220, 0, 120)
        frame.Position = UDim2.new(0.05, 0, 0.4, 0)
        frame.BackgroundColor3 = Color3.fromRGB(163, 255, 137)
        frame.Parent = screenGui
        local toggleButton = Instance.new("TextButton")
        toggleButton.Size = UDim2.new(0, 100, 0, 30)
        toggleButton.Position = UDim2.new(0, 10, 0, 10)
        toggleButton.Text = "Вкл/выкл полёт"
        toggleButton.Parent = frame
        local speedLabel = Instance.new("TextLabel")
        speedLabel.Size = UDim2.new(0, 50, 0, 30)
        speedLabel.Position = UDim2.new(0, 120, 0, 10)
        speedLabel.Text = tostring(flySpeed)
        speedLabel.Parent = frame
        local plusButton = Instance.new("TextButton")
        plusButton.Size = UDim2.new(0, 30, 0, 30)
        plusButton.Position = UDim2.new(0, 180, 0, 10)
        plusButton.Text = "+"
        plusButton.Parent = frame
        local minusButton = Instance.new("TextButton")
        minusButton.Size = UDim2.new(0, 30, 0, 30)
        minusButton.Position = UDim2.new(0, 180, 0, 50)
        minusButton.Text = "-"
        minusButton.Parent = frame
        local destroyButton = Instance.new("TextButton")
        destroyButton.Size = UDim2.new(0, 100, 0, 30)
        destroyButton.Position = UDim2.new(0, 10, 0, 80)
        destroyButton.Text = "Удалить GUI"
        destroyButton.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
        destroyButton.Parent = frame
        local ctrl = { f = 0, b = 0, l = 0, r = 0 }
        UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.KeyCode == Enum.KeyCode.W then ctrl.f = 1 end
            if input.KeyCode == Enum.KeyCode.S then ctrl.b = -1 end
            if input.KeyCode == Enum.KeyCode.A then ctrl.l = -1 end
            if input.KeyCode == Enum.KeyCode.D then ctrl.r = 1 end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.W then ctrl.f = 0 end
            if input.KeyCode == Enum.KeyCode.S then ctrl.b = 0 end
            if input.KeyCode == Enum.KeyCode.A then ctrl.l = 0 end
            if input.KeyCode == Enum.KeyCode.D then ctrl.r = 0 end
        end)
        toggleButton.MouseButton1Click:Connect(function()
            flying = not flying
            local car = getCar()
            if car then
                local primaryPart = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
                if primaryPart then
                    if flying then
                        if not bv or not bv.Parent then
                            bv = Instance.new("BodyVelocity")
                            bv.Name = "FlyBV"
                            bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                            bv.Parent = primaryPart
                        end
                        if not flyConnection then
                            flyConnection = RunService.RenderStepped:Connect(function()
                                if not flying then return end
                                local cam = workspace.CurrentCamera
                                local moveDir = (cam.CFrame.LookVector * (ctrl.f + ctrl.b)) +
                                                ((cam.CFrame * CFrame.new(ctrl.l + ctrl.r, 0, 0)).p - cam.CFrame.p)
                                if moveDir.Magnitude > 0 then
                                    bv.Velocity = moveDir.Unit * flySpeed
                                else
                                    bv.Velocity = Vector3.zero
                                end
                                primaryPart.CFrame = CFrame.new(primaryPart.Position, primaryPart.Position + cam.CFrame.LookVector)
                            end)
                        end
                    else
                        if bv then bv:Destroy(); bv = nil end
                        if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
                    end
                end
            end
        end)
        plusButton.MouseButton1Click:Connect(function()
            flySpeed = flySpeed + 10
            speedLabel.Text = tostring(flySpeed)
        end)
        minusButton.MouseButton1Click:Connect(function()
            flySpeed = math.max(10, flySpeed - 10)
            speedLabel.Text = tostring(flySpeed)
        end)
        destroyButton.MouseButton1Click:Connect(function()
            flying = false
            if bv then bv:Destroy(); bv = nil end
            if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
            screenGui:Destroy()
        end)
    end,
})

-- ===== НОВЫЕ ФУНКЦИИ В РАЗВЛЕЧЕНИЯХ =====
funTab:CreateSection("Взрыв и рывок")

-- Bang (подбросить игрока)
funTab:CreateButton({
    Name = "Взрыв (Bang)",
    Callback = function()
        if not playerToBring then
            Rayfield:Notify({ Title = "Ошибка", Content = "Сначала выберите игрока", Duration = 5, Image = "alert-triangle" })
            return
        end
        local otherChar = playerToBring.Character
        if not otherChar then
            Rayfield:Notify({ Title = "Ошибка", Content = "У игрока нет персонажа", Duration = 5, Image = "alert-triangle" })
            return
        end
        local root = otherChar:FindFirstChild("HumanoidRootPart") or otherChar:FindFirstChild("Torso")
        if root then
            root:PivotTo(root.CFrame + Vector3.new(0, 100, 0))
            Rayfield:Notify({ Title = "Bang!", Content = "Игрок взлетел", Duration = 3, Image = "info" })
        end
    end,
})

-- Jerk (рывок вперёд)
funTab:CreateButton({
    Name = "Рывок (Jerk)",
    Callback = function()
        if not playerToBring then
            Rayfield:Notify({ Title = "Ошибка", Content = "Сначала выберите игрока", Duration = 5, Image = "alert-triangle" })
            return
        end
        local otherChar = playerToBring.Character
        if not otherChar then
            Rayfield:Notify({ Title = "Ошибка", Content = "У игрока нет персонажа", Duration = 5, Image = "alert-triangle" })
            return
        end
        local root = otherChar:FindFirstChild("HumanoidRootPart") or otherChar:FindFirstChild("Torso")
        if root then
            local direction = otherChar:FindFirstChild("Humanoid") and otherChar.Humanoid.MoveDirection or Vector3.new(1,0,0)
            if direction.Magnitude == 0 then
                direction = workspace.CurrentCamera.CFrame.LookVector
            end
            root:PivotTo(root.CFrame + direction * 20)
            Rayfield:Notify({ Title = "Jerk!", Content = "Игрок дёрнут", Duration = 3, Image = "info" })
        end
    end,
})

-- ===== УМНЫЙ ФАРМ (ИСПРАВЛЕННЫЙ) =====
local smartFarmEnabled = false
local stagesToFarm = 2
local smartFarmConnection = nil

local function smartFarmCycle()
    if not HRP then return end
    local stages = workspace:FindFirstChild("BoatStages")
    if not stages then return end
    local normalStages = stages:FindFirstChild("NormalStages")
    if not normalStages then return end

    -- Если текущий индекс превысил заданное количество этапов, идём к сундуку, забираем награду, затем ресет
    if index > stagesToFarm then
        -- Телепорт к сундуку
        local endpoint = normalStages:FindFirstChild("TheEnd")
        if endpoint and endpoint:FindFirstChild("GoldenChest") then
            local chest = endpoint.GoldenChest
            HRP:PivotTo(chest:GetPivot() + Vector3.new(0,0,-10))
            task.wait(1.5) -- ждём, чтобы золото засчиталось
            -- Сброс на первый этап
            local firstStage = normalStages:FindFirstChild("CaveStage1")
            if firstStage and firstStage:FindFirstChild("DarknessPart") then
                character:PivotTo(firstStage.DarknessPart.CFrame + Vector3.new(0,0,15))
                index = 1
            end
        else
            -- Если сундука нет, просто сбрасываем
            index = 1
        end
        return
    end

    -- Проходим текущий этап
    local roomName = "CaveStage" .. index
    local stage = normalStages:FindFirstChild(roomName)
    if not stage then return end
    local darkPart = stage:FindFirstChild("DarknessPart")
    if not darkPart then return end
    character:PivotTo(darkPart.CFrame - Vector3.new(0,0,15))
    local tween2 = TS:Create(HRP, TweenInfo.new(2, Enum.EasingStyle.Linear), { CFrame = darkPart.CFrame + Vector3.new(0,0,20) })
    tweening = true
    tween2:Play()
    tween2.Completed:Wait()
    tweening = false
    task.wait(0.5) -- даём игре время начислить золото за этап
    index = index + 1
end

local superFarmTab = Window:CreateTab("Супер Фарм", "rewind")
superFarmTab:CreateParagraph({
    Title = "Умный фарм по этапам",
    Content = "Проходит N этапов, затем идёт к сундуку за наградой, после чего ресетится. Золото гарантированно засчитывается."
})
superFarmTab:CreateInput({
    Name = "Количество этапов до ресета",
    PlaceholderText = "2",
    Callback = function(text)
        local num = tonumber(text)
        if num and num > 0 then
            stagesToFarm = math.floor(num)
        else
            stagesToFarm = 2
        end
    end,
})
superFarmTab:CreateToggle({
    Name = "Вкл/выкл умный фарм",
    CurrentValue = false,
    Callback = function(value)
        smartFarmEnabled = value
        if smartFarmEnabled then
            if not smartFarmConnection then
                smartFarmConnection = runService.Heartbeat:Connect(function()
                    if smartFarmEnabled then
                        smartFarmCycle()
                    end
                end)
            end
        else
            if smartFarmConnection then
                smartFarmConnection:Disconnect()
                smartFarmConnection = nil
            end
        end
    end,
})
superFarmTab:CreateButton({
    Name = "Сбросить на первый этап",
    Callback = function()
        index = 1
        local stages = workspace:FindFirstChild("BoatStages")
        if stages and stages:FindFirstChild("NormalStages") then
            local first = stages.NormalStages:FindFirstChild("CaveStage1")
            if first and first:FindFirstChild("DarknessPart") then
                character:PivotTo(first.DarknessPart.CFrame + Vector3.new(0,0,15))
            end
        end
    end,
})

-- ===== ТЕЛЕПОРТЫ НА КОМАНДЫ =====
local teleportTab = Window:CreateTab("Телепорты", "rewind")

local function getTeamBaseByColor(colorName)
    local colorMap = {
        ["Красная"] = BrickColor.Red(),
        ["Синяя"] = BrickColor.Blue(),
        ["Зелёная"] = BrickColor.Green(),
        ["Белая"] = BrickColor.White(),
        ["Чёрная"] = BrickColor.Black()
    }
    local targetColor = colorMap[colorName]
    if not targetColor then return nil end
    for _, v in pairs(workspace:GetChildren()) do
        if v:FindFirstChild("TeamColor") and v.TeamColor.Value == targetColor then
            return v
        end
    end
    return nil
end

local locations = {
    "Старт (зона 1)",
    "Финиш (сундук)",
    "Магазин",
    "Зона крафта",
    "Арена",
    "Красная команда",
    "Синяя команда",
    "Зелёная команда",
    "Белая команда",
    "Чёрная команда",
    "Пользовательская"
}
local selectedLocation = "Старт (зона 1)"
local customCoords = { X = 0, Y = 0, Z = 0 }

local locDropdown = teleportTab:CreateDropdown({
    Name = "Выберите локацию",
    Options = locations,
    CurrentOption = { selectedLocation },
    MultipleOptions = false,
    Callback = function(Options)
        selectedLocation = Options[1]
    end,
})

teleportTab:CreateButton({
    Name = "Телепортироваться",
    Callback = function()
        local targetPos = nil
        if selectedLocation == "Старт (зона 1)" then
            local Stages = workspace:FindFirstChild("BoatStages")
            if Stages and Stages:FindFirstChild("NormalStages") then
                local first = Stages.NormalStages:FindFirstChild("CaveStage1")
                if first and first:FindFirstChild("DarknessPart") then
                    targetPos = first.DarknessPart.CFrame + Vector3.new(0,0,15)
                end
            end
        elseif selectedLocation == "Финиш (сундук)" then
            local Stages = workspace:FindFirstChild("BoatStages")
            if Stages and Stages:FindFirstChild("NormalStages") then
                local endp = Stages.NormalStages:FindFirstChild("TheEnd")
                if endp and endp:FindFirstChild("GoldenChest") then
                    targetPos = endp.GoldenChest.CFrame + Vector3.new(0,0,-5)
                end
            end
        elseif selectedLocation == "Магазин" then
            targetPos = CFrame.new(0, 5, 0)  -- замени на реальные координаты
        elseif selectedLocation == "Зона крафта" then
            targetPos = CFrame.new(0, 5, 0)
        elseif selectedLocation == "Арена" then
            targetPos = CFrame.new(0, 5, 0)
        elseif selectedLocation:find("команда") then
            local colorName = string.match(selectedLocation, "^(%S+)")
            local base = getTeamBaseByColor(colorName)
            if base then
                targetPos = base.CFrame + Vector3.new(0, 5, 0)
            else
                Rayfield:Notify({ Title = "Ошибка", Content = "База команды не найдена", Duration = 5, Image = "alert-triangle" })
            end
        elseif selectedLocation == "Пользовательская" then
            targetPos = CFrame.new(customCoords.X, customCoords.Y, customCoords.Z)
        end
        if targetPos then
            HRP:PivotTo(targetPos)
        elseif selectedLocation ~= "Пользовательская" then
            Rayfield:Notify({ Title = "Ошибка", Content = "Локация не найдена", Duration = 5, Image = "alert-triangle" })
        end
    end,
})

teleportTab:CreateSection("Пользовательские координаты")
teleportTab:CreateInput({ Name = "X", PlaceholderText = "0", Callback = function(t) customCoords.X = tonumber(t) or 0 end })
teleportTab:CreateInput({ Name = "Y", PlaceholderText = "0", Callback = function(t) customCoords.Y = tonumber(t) or 0 end })
teleportTab:CreateInput({ Name = "Z", PlaceholderText = "0", Callback = function(t) customCoords.Z = tonumber(t) or 0 end })

-- ===== СТРОИТЕЛЬСТВО ПО СХЕМЕ (JSON) =====
local buildFromSchemeTab = Window:CreateTab("Строительство по схеме", "rewind")

local function buildFromJSON(jsonText)
    local success, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(jsonText)
    end)
    if not success or not data then
        Rayfield:Notify({ Title = "Ошибка", Content = "Неверный формат JSON", Duration = 5, Image = "alert-triangle" })
        return
    end
    local totalBlocks = 0
    for _, blockList in pairs(data) do
        if type(blockList) == "table" then
            for _ in pairs(blockList) do totalBlocks = totalBlocks + 1 end
        end
    end
    if totalBlocks == 0 then
        Rayfield:Notify({ Title = "Ошибка", Content = "В схеме нет блоков", Duration = 5, Image = "alert-triangle" })
        return
    end
    local placed = 0
    local myBase = getPlayerZone(player)
    for blockName, blockList in pairs(data) do
        if type(blockList) == "table" then
            for _, props in ipairs(blockList) do
                if props.Position and props.Rotation and props.Size then
                    local posParts = {}
                    for part in string.gmatch(props.Position, "[^, ]+") do
                        table.insert(posParts, tonumber(part) or 0)
                    end
                    local pos = CFrame.new(posParts[1] or 0, posParts[2] or 0, posParts[3] or 0)
                    local rotParts = {}
                    for part in string.gmatch(props.Rotation, "[^, ]+") do
                        table.insert(rotParts, tonumber(part) or 0)
                    end
                    local rot = CFrame.Angles(math.rad(rotParts[1] or 0), math.rad(rotParts[2] or 0), math.rad(rotParts[3] or 0))
                    local sizeParts = {}
                    for part in string.gmatch(props.Size, "[^, ]+") do
                        table.insert(sizeParts, tonumber(part) or 1)
                    end
                    local size = Vector3.new(sizeParts[1] or 1, sizeParts[2] or 1, sizeParts[3] or 1)
                    local anchored = props.Anchored == true
                    local color = nil
                    if props.Color then
                        local cParts = {}
                        for part in string.gmatch(props.Color, "[^, ]+") do
                            table.insert(cParts, tonumber(part) or 0)
                        end
                        if #cParts >= 3 then
                            color = Color3.new(cParts[1], cParts[2], cParts[3])
                        end
                    end
                    local transparency = props.Transparency or 0
                    placeBlock(blockName, myBase.CFrame * pos, myBase, anchored)
                    task.wait(0.01)
                    placed = placed + 1
                    pastePercent = (placed / totalBlocks) * 100
                end
            end
        end
    end
    Rayfield:Notify({ Title = "Готово", Content = "Построено " .. placed .. " блоков", Duration = 5, Image = "check-circle" })
    pastePercent = 0
end

buildFromSchemeTab:CreateParagraph({
    Title = "Вставьте JSON-схему ниже",
    Content = "Скопируйте содержимое файла .Build.html"
})
local jsonInput = buildFromSchemeTab:CreateInput({
    Name = "JSON схема",
    PlaceholderText = '{"MetalBlock":[...]}',
    Callback = function(text)
        _G.schemeJSON = text
    end,
})
buildFromSchemeTab:CreateButton({
    Name = "Построить из схемы",
    Callback = function()
        if _G.schemeJSON and #_G.schemeJSON > 0 then
            buildFromJSON(_G.schemeJSON)
        else
            Rayfield:Notify({ Title = "Ошибка", Content = "Сначала введите JSON-схему", Duration = 5, Image = "alert-triangle" })
        end
    end,
})
buildFromSchemeTab:CreateButton({
    Name = "Загрузить пример (Ту-160)",
    Callback = function()
        local example = '{"MetalBlock":[{"Position":"8.5, 18.1, 67.237","Rotation":"-180, 0, -180","Size":"1.2, 0.2, 2.475","Anchored":true,"Color":"0.8, 0.8, 0.8","Transparency":0}]}'
        _G.schemeJSON = example
        jsonInput:Set(example)
        Rayfield:Notify({ Title = "Пример загружен", Content = "Вставьте свой JSON поверх", Duration = 3, Image = "info" })
    end,
})

-- ===== ОБЫЧНЫЙ АВТОФАРМ (полный цикл до сундука) и АНТИ-AFK =====
task.spawn(function()
    while true do
        task.wait()
        if autofarm then
            if not HRP then continue end
            if index == 11 then
                local Stages = workspace:FindFirstChild("BoatStages")
                if not Stages then continue end
                local normalStages = Stages:FindFirstChild("NormalStages")
                if not normalStages then continue end
                local endpoint = normalStages:FindFirstChild("TheEnd")
                if not endpoint then continue end
                local chest = endpoint:FindFirstChild("GoldenChest")
                if not chest then continue end
                HRP:PivotTo(chest:GetPivot() + Vector3.new(0,0,-10))
                local ii = 0
                repeat
                    task.wait(1)
                    ii = ii + 1
                    if ii % 20 == 0 then
                        HRP:PivotTo(chest:GetPivot() + Vector3.new(0,0,-10))
                    end
                    if not HRP then break end
                until (HRP.Position - chest:GetPivot().Position).Magnitude > 500
                index = 1
            else
                local stages = workspace:FindFirstChild("BoatStages")
                if not stages then continue end
                local normalStages = stages:FindFirstChild("NormalStages")
                if not normalStages then continue end
                local roomName = "CaveStage" .. index
                local stage = normalStages:FindFirstChild(roomName)
                if not stage then continue end
                local darkPart = stage:FindFirstChild("DarknessPart")
                if not darkPart then continue end
                character:PivotTo(darkPart.CFrame - Vector3.new(0,0,15))
                local tween2 = TS:Create(HRP, TweenInfo.new(2, Enum.EasingStyle.Linear), { CFrame = darkPart.CFrame + Vector3.new(0,0,20) })
                tweening = true
                tween2:Play()
                tween2.Completed:Wait()
                tweening = false
                index = index + 1
            end
        end
    end
end)

runService.Heartbeat:Connect(function()
    if tweening then
        HRP.Velocity = Vector3.zero
    end
end)

player.CharacterAdded:Connect(function(charactery)
    character = charactery
    HRP = character:WaitForChild("HumanoidRootPart")
    humanoid = character:WaitForChild("Humanoid")
end)

task.spawn(function()
    while task.wait(100) do
        vim:SendKeyEvent(true, Enum.KeyCode.Tilde, false, nil)
        task.wait(0.1)
        vim:SendKeyEvent(false, Enum.KeyCode.Tilde, false, nil)
    end
end)

Rayfield:LoadConfiguration()