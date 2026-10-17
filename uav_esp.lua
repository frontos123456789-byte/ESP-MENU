-- Preliminary name-based ESP. Not verified against ILP Studio's object hierarchy.
-- Execute only once per session; running again replaces the previous instance.
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local player = Players.LocalPlayer
local parent = player:WaitForChild('PlayerGui')
local previous = parent:FindFirstChild('UAV_ESP_Menu')
if previous then previous:Destroy() end

local gui = Instance.new('ScreenGui')
gui.Name = 'UAV_ESP_Menu'
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = parent
local alive, automatic, calibrating = true, false, false
local distance, averageDt, elapsed, adjustTime = 1500, 1/60, 0, 0
local enabled = {drone = false, missile = false, uav = false}
local candidates, marks, connections = {}, {}, {}
local colors = {drone = Color3.fromRGB(70,230,255), missile = Color3.fromRGB(255,100,90), uav = Color3.fromRGB(255,215,80)}
local names = {drone = 'Дрон', missile = 'Ракета', uav = 'БПЛА'}
-- Add exact object names here if the game uses different names.
local patterns = {
    missile = {'missile', 'rocket', 'ракет', 'Ракет', 'РАКЕТ'},
    drone = {'drone', 'fpv', 'дрон', 'Дрон', 'ДРОН'},
    uav = {'uav', 'ucav', 'shahed', 'geran', 'lancet', 'бпла', 'БПЛА', 'шахед', 'Шахед', 'Герань', 'Ланцет'},
}
local function classify(object)
    if not (object:IsA('Model') or object:IsA('BasePart')) then return end
    local name = string.lower(object.Name)
    for _, kind in ipairs({'missile', 'drone', 'uav'}) do
        for _, word in ipairs(patterns[kind]) do
            if string.find(name, word, 1, true) then return kind end
        end
    end
end
local function register(object)
    local kind = classify(object)
    if kind then candidates[object] = kind end
end
local function clearMark(object)
    if marks[object] then marks[object]:Destroy(); marks[object] = nil end
end
local function cleanup()
    if not alive then return end
    alive = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for object in pairs(marks) do clearMark(object) end
    table.clear(candidates)
end
gui.Destroying:Connect(cleanup)

local panel = Instance.new('Frame')
panel.Size = UDim2.fromOffset(270, 350)
panel.Position = UDim2.new(0, 12, 0.18, 0)
panel.BackgroundColor3 = Color3.fromRGB(24,28,38)
panel.Parent = gui
Instance.new('UICorner', panel).CornerRadius = UDim.new(0,12)
local layout = Instance.new('UIListLayout', panel)
layout.Padding = UDim.new(0,6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
local padding = Instance.new('UIPadding', panel)
padding.PaddingTop = UDim.new(0,8)
local order = 0
local function row(text, button, height)
    order = order + 1
    local item = Instance.new(button and 'TextButton' or 'TextLabel')
    item.Size = UDim2.new(1,-16,0,height or 34)
    item.LayoutOrder = order
    item.Text = text
    item.TextSize = 15
    item.Font = Enum.Font.Gotham
    item.TextColor3 = Color3.new(1,1,1)
    item.TextWrapped = true
    item.BackgroundColor3 = Color3.fromRGB(43,49,65)
    item.BorderSizePixel = 0
    item.Parent = panel
    Instance.new('UICorner', item).CornerRadius = UDim.new(0,6)
    return item
end
row('БПЛА ESP • предварительная версия', false)
for _, kind in ipairs({'drone', 'missile', 'uav'}) do
    local button = row(names[kind] .. ': ВЫКЛ', true)
    button.Activated:Connect(function()
        enabled[kind] = not enabled[kind]
        button.Text = names[kind] .. ': ' .. (enabled[kind] and 'ВКЛ' or 'ВЫКЛ')
    end)
end
local rangeButton = row('Дальность: 1500 studs', true)
rangeButton.Activated:Connect(function()
    if calibrating then return end
    automatic = false
    distance = distance >= 5000 and 500 or math.min(5000, distance + 500)
end)
local autoButton = row('Автоподбор дальности', true)
autoButton.Activated:Connect(function()
    if calibrating then return end
    if automatic then automatic = false; return end
    calibrating = true
    autoButton.Text = 'Замер FPS: 8 секунд…'
    task.spawn(function()
        local total, frames = 0, 0
        while alive and total < 8 do
            total = total + RunService.RenderStepped:Wait()
            frames = frames + 1
        end
        if not alive then return end
        local fps = frames / math.max(total, 0.001)
        local quality = 0
        pcall(function() quality = UserSettings():GetService('UserGameSettings').SavedQualityLevel.Value end)
        distance = fps >= 55 and 3000 or (fps >= 40 and 2000 or (fps >= 28 and 1000 or 500))
        -- Automatic graphics reports 0; do not infer actual GPU quality from it.
        if quality > 0 and quality <= 3 then distance = math.min(distance, 2000) end
        automatic, calibrating = true, false
    end)
end)
local status = row('Поиск объектов…', false, 40)
row('Закрыть и удалить ESP', true).Activated:Connect(function() gui:Destroy() end)

table.insert(connections, workspace.DescendantAdded:Connect(register))
table.insert(connections, workspace.DescendantRemoving:Connect(function(object)
    candidates[object] = nil
    clearMark(object)
end))
task.spawn(function()
    for i, object in ipairs(workspace:GetDescendants()) do
        if not alive then return end
        register(object)
        if i % 400 == 0 then task.wait() end
    end
end)
local function mark(object, part, kind)
    local billboard = Instance.new('BillboardGui')
    billboard.Name = 'UAV_ESP_Marker'
    billboard.Size = UDim2.fromOffset(180,28)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.StudsOffsetWorldSpace = Vector3.new(0,3,0)
    billboard.Parent = gui
    local label = Instance.new('TextLabel')
    label.Size = UDim2.fromScale(1,1)
    label.BackgroundTransparency = 1
    label.TextColor3 = colors[kind]
    label.TextStrokeTransparency = 0.25
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard
    marks[object] = billboard
    return billboard
end
table.insert(connections, RunService.RenderStepped:Connect(function(dt)
    averageDt = averageDt + (dt-averageDt)*0.05
    elapsed, adjustTime = elapsed+dt, adjustTime+dt
    if elapsed < 0.25 then return end
    elapsed = 0
    local fps = 1/math.max(averageDt,0.001)
    if automatic and adjustTime >= 4 then
        adjustTime = 0
        if fps < 28 then distance = math.max(300, math.floor(distance*0.8))
        elseif fps > 55 then distance = math.min(5000, distance+200) end
    end
    rangeButton.Text = string.format('Дальность: %d studs • нажми +500',distance)
    if not calibrating then autoButton.Text = automatic and 'Авто: ВКЛ • нажми выключить' or 'Автоподбор дальности' end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local visible, found = {}, 0
    for object, kind in pairs(candidates) do
        if object:IsDescendantOf(workspace) then
            found = found+1
            local nested, ancestor = false, object.Parent
            while ancestor and ancestor ~= workspace do
                if candidates[ancestor] or ancestor == player.Character or ancestor:IsA('Tool') then nested = true; break end
                ancestor = ancestor.Parent
            end
            if not nested and (enabled[kind] or enabled.uav) then
                local part = object:IsA('BasePart') and object or (object.PrimaryPart or object:FindFirstChildWhichIsA('BasePart',true))
                if part then
                    local d = (camera.CFrame.Position-part.Position).Magnitude
                    if d <= distance then table.insert(visible,{object=object,part=part,kind=kind,d=d}) end
                end
            end
        end
    end
    table.sort(visible,function(a,b) return a.d < b.d end)
    local keep, count = {}, math.min(#visible,48)
    for i=1,count do
        local item = visible[i]
        keep[item.object] = true
        local billboard = marks[item.object] or mark(item.object,item.part,item.kind)
        billboard.Adornee = item.part
        billboard.MaxDistance = distance
        billboard.TextLabel.Text = string.format('%s • %d studs',names[item.kind],math.floor(item.d))
    end
    for object in pairs(marks) do if not keep[object] then clearMark(object) end end
    status.Text = string.format('FPS: %d • кандидатов: %d • меток: %d\nРаспознавание по именам',math.floor(fps),found,count)
end))
