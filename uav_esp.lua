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
local outlines, speedLabels, motion = {}, {}, {}
local METERS_PER_STUD = 0.28
local clearColor = Color3.fromRGB(70,220,105)
local blockedColor = Color3.fromRGB(245,75,75)
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
    if outlines[object] then outlines[object]:Destroy(); outlines[object] = nil end
    if speedLabels[object] then speedLabels[object]:Destroy(); speedLabels[object] = nil end
    motion[object] = nil
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

-- Safe-area root automatically follows rotation, viewport size and device insets.
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
local root = Instance.new('Frame')
root.Size = UDim2.fromScale(1,1)
root.BackgroundTransparency = 1
root.Parent = gui
local panel = Instance.new('Frame')
panel.Position = UDim2.fromOffset(8,8)
panel.BackgroundColor3 = Color3.fromRGB(24,28,38)
panel.Parent = root
Instance.new('UICorner', panel).CornerRadius = UDim.new(0,12)
local toggle = Instance.new('TextButton')
toggle.Size = UDim2.fromOffset(64,44)
toggle.Position = UDim2.fromOffset(8,8)
toggle.Text = 'ESP'
toggle.TextSize = 16
toggle.TextColor3 = Color3.new(1,1,1)
toggle.BackgroundColor3 = Color3.fromRGB(43,49,65)
toggle.Visible = false
toggle.Parent = root
Instance.new('UICorner',toggle).CornerRadius = UDim.new(0,10)
local close = Instance.new('TextButton')
close.Size = UDim2.new(1,-16,0,44)
close.Position = UDim2.fromOffset(8,4)
close.Text = 'БПЛА ESP     × Скрыть'
close.TextSize = 16
close.TextColor3 = Color3.new(1,1,1)
close.BackgroundTransparency = 1
close.Parent = panel
close.Activated:Connect(function()
    panel.Visible = false
    toggle.Visible = true
end)
toggle.Activated:Connect(function()
    panel.Visible = true
    toggle.Visible = false
end)
local body = Instance.new('ScrollingFrame')
body.Position = UDim2.fromOffset(0,52)
body.Size = UDim2.new(1,0,1,-60)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 3
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.CanvasSize = UDim2.new()
body.Parent = panel
local function fitPanel()
    panel.Size = UDim2.fromOffset(math.min(290,math.max(1,root.AbsoluteSize.X-16)),
        math.min(470,math.max(1,root.AbsoluteSize.Y-16)))
end
table.insert(connections,root:GetPropertyChangedSignal('AbsoluteSize'):Connect(fitPanel))
fitPanel()
local layout = Instance.new('UIListLayout', body)
layout.Padding = UDim.new(0,6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
local order = 0
local function row(text, button, height)
    order = order + 1
    local item = Instance.new(button and 'TextButton' or 'TextLabel')
    item.Size = UDim2.new(1,-16,0,height or 44)
    item.LayoutOrder = order
    item.Text = text
    item.TextSize = 15
    item.Font = Enum.Font.Gotham
    item.TextColor3 = Color3.new(1,1,1)
    item.TextWrapped = true
    item.BackgroundColor3 = Color3.fromRGB(43,49,65)
    item.BorderSizePixel = 0
    item.Parent = body
    Instance.new('UICorner', item).CornerRadius = UDim.new(0,6)
    return item
end
-- Header remains accessible while the settings scroll.
for _, kind in ipairs({'drone', 'missile', 'uav'}) do
    local button = row(names[kind] .. ': ВЫКЛ', true)
    button.Activated:Connect(function()
        enabled[kind] = not enabled[kind]
        button.Text = (kind == 'uav' and 'Все БПЛА' or names[kind]) .. ': ' .. (enabled[kind] and 'ВКЛ' or 'ВЫКЛ')
    end)
end
local rangeButton = row('Дальность: 420 м • +140 м', true)
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
row('Выключить и удалить ESP', true).Activated:Connect(function() gui:Destroy() end)

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
local function mark(object, part)
    local billboard = Instance.new('BillboardGui')
    billboard.Name = 'UAV_ESP_Marker'
    billboard.Size = UDim2.fromOffset(64,32)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.Parent = gui
    local dot = Instance.new('Frame')
    dot.Name = 'Dot'
    dot.AnchorPoint = Vector2.new(0.5,0.5)
    dot.Position = UDim2.fromScale(0.5,0.5)
    dot.Size = UDim2.fromOffset(4,4)
    dot.BorderSizePixel = 0
    dot.BackgroundTransparency = 0.15
    dot.Parent = billboard
    Instance.new('UICorner',dot).CornerRadius = UDim.new(1,0)
    local label = Instance.new('TextLabel')
    label.Name = 'Distance'
    label.Position = UDim2.new(0,0,0.5,4)
    label.Size = UDim2.new(1,0,0,12)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(220,220,220)
    label.TextTransparency = 0.3
    label.TextStrokeTransparency = 0.65
    label.TextSize = 10
    label.Font = Enum.Font.Gotham
    label.Parent = billboard
    local outline = Instance.new('Highlight')
    outline.Name = 'ESP_Outline'
    outline.Adornee = object
    outline.FillTransparency = 1
    outline.OutlineColor = Color3.new(1,1,1)
    outline.OutlineTransparency = 0.2
    outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    outline.Parent = object
    outlines[object] = outline
    local speed = Instance.new('TextLabel')
    speed.Name = 'ESP_Speed'
    speed.AnchorPoint = Vector2.new(0.5,1)
    speed.Size = UDim2.fromOffset(100,16)
    speed.BackgroundTransparency = 1
    speed.TextColor3 = Color3.new(1,1,1)
    speed.TextTransparency = 0.15
    speed.TextStrokeTransparency = 0.65
    speed.TextSize = 11
    speed.Font = Enum.Font.Gotham
    speed.Visible = false
    speed.Parent = root
    speedLabels[object] = speed
    motion[object] = {part = part, position = part.Position, time = os.clock()}
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
    rangeButton.Text = string.format('Дальность: %d м • +140 м',math.floor(distance*METERS_PER_STUD+0.5))
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
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = player.Character and {player.Character,camera} or {camera}
    local keep, count = {}, math.min(#visible,48)
    for i=1,count do
        local item = visible[i]
        keep[item.object] = true
        local billboard = marks[item.object] or mark(item.object,item.part)
        local sample = motion[item.object]
        local now = os.clock()
        local delta = now-sample.time
        if sample.part ~= item.part then
            sample.speed, sample.velocity = nil,nil
        elseif delta >= 0.15 then
            -- Position samples also cover anchored objects moved with PivotTo/CFrame.
            local velocity = (item.part.Position-sample.position)/delta
            sample.velocity = sample.velocity and sample.velocity:Lerp(velocity,0.5) or velocity
            local measured = velocity.Magnitude
            sample.speed = sample.speed and (sample.speed*0.5+measured*0.5) or measured
        end
        if delta >= 0.15 or sample.part ~= item.part then
            sample.position, sample.time, sample.part = item.part.Position, now, item.part
        end
        speedLabels[item.object].Text = sample.speed and string.format('%d км/ч',math.floor(sample.speed*METERS_PER_STUD*3.6+0.5)) or '— км/ч'
        billboard.Adornee = item.part
        billboard.MaxDistance = distance
        local _, onScreen = camera:WorldToViewportPoint(item.part.Position)
        billboard.Enabled = onScreen
        if onScreen then
            local hit = workspace:Raycast(camera.CFrame.Position,
                item.part.Position-camera.CFrame.Position,rayParams)
            local unobstructed = not hit or hit.Instance == item.object or hit.Instance:IsDescendantOf(item.object)
            billboard.Dot.BackgroundColor3 = unobstructed and clearColor or blockedColor
            billboard.Distance.Text = string.format('%d м',math.floor(item.d*METERS_PER_STUD+0.5))
        end
    end
    for object in pairs(marks) do if not keep[object] then clearMark(object) end end
    status.Text = string.format('FPS: %d • кандидатов: %d • меток: %d\nРаспознавание по именам',math.floor(fps),found,count)
end))

-- Reproject the top of the object's bounds every frame so the caption follows the camera.
table.insert(connections, RunService.RenderStepped:Connect(function()
    local camera = workspace.CurrentCamera
    for object, label in pairs(speedLabels) do
        label.Visible = false
        local outline = outlines[object]
        outline.Enabled = false
        if camera and object:IsDescendantOf(workspace) then
            local cf, size
            if object:IsA('Model') then cf, size = object:GetBoundingBox()
            else cf, size = object.CFrame, object.Size end
            local center, onScreen = camera:WorldToViewportPoint(cf.Position)
            outline.Enabled = onScreen
            if onScreen then
                local top, inFront = math.huge, true
                for x=-1,1,2 do
                    for y=-1,1,2 do
                        for z=-1,1,2 do
                            local corner = cf:PointToWorldSpace(Vector3.new(x*size.X/2,y*size.Y/2,z*size.Z/2))
                            local point = camera:WorldToViewportPoint(corner)
                            if point.Z <= 0 then inFront = false end
                            top = math.min(top,point.Y)
                        end
                    end
                end
                if inFront then
                    -- WorldToScreenPoint includes the top-bar inset, matching GUI AbsolutePosition.
                    local screen = camera:WorldToScreenPoint(cf.Position)
                    local inset = screen.Y-center.Y
                    label.Position = UDim2.fromOffset(screen.X-root.AbsolutePosition.X,top+inset-root.AbsolutePosition.Y-4)
                    label.Visible = true
                end
            end
        end
    end
end))

local function targetPart(object)
    if not object or not object:IsDescendantOf(workspace) then return end
    if object:IsA('Model') then
        if object:FindFirstChildOfClass('Humanoid') then return end
        return object.PrimaryPart or object:FindFirstChildWhichIsA('BasePart',true)
    elseif object:IsA('BasePart') then return object end
end
local function blockedAncestor(object,character)
    local ancestor=object.Parent
    while ancestor and ancestor~=workspace do
        if ancestor==character or ancestor:IsA('Tool') then return true end
        if ancestor:IsA('Model') and ancestor:FindFirstChildOfClass('Humanoid') then return true end
        ancestor=ancestor.Parent
    end
    return false
end
local counter=Instance.new('TextLabel')
counter.Name='SkyCounter'
counter.AnchorPoint=Vector2.new(1,0)
counter.Position=UDim2.new(1,-12,0,12)
counter.Size=UDim2.fromOffset(200,38)
counter.BackgroundColor3=Color3.fromRGB(24,28,38)
counter.BackgroundTransparency=0.2
counter.TextColor3=Color3.new(1,1,1)
counter.TextSize=15;counter.Text='БПЛА в небе: …'
counter.Parent=root
Instance.new('UICorner',counter).CornerRadius=UDim.new(0,8)
local ownerKeys={'shooter','Shooter','owner','Owner','player','Player','creator','Creator','OwnerUserId','ShooterUserId','UserId','userId'}
local function metadata(object,keys)
    local current=object
    for _=1,3 do
        if typeof(current)~='Instance' or current==workspace then return end
        for _,key in ipairs(keys) do
            local attr=current:GetAttribute(key)
            if attr~=nil then return attr end
            local child=current:FindFirstChild(key)
            if child and child:IsA('ValueBase') then
                local ok,value=pcall(function()return child.Value end)
                if ok and value~=nil then return value end
            end
        end
        current=current.Parent
    end
end
local function isPlayerOwner(value)
    if typeof(value)=='Instance' then
        return value:IsA('Player') or (value:IsA('Model') and Players:GetPlayerFromCharacter(value)~=nil)
    end
    for _,p in ipairs(Players:GetPlayers()) do
        if value==p.UserId or value==tostring(p.UserId) or value==p.Name then return true end
    end
    return false
end
local function rocketLike(object)
    local name=string.lower(object.Name)
    local parentName=object.Parent and string.lower(object.Parent.Name) or ''
    return name:find('rocket',1,true) or name:find('missile',1,true) or name:find('stinger',1,true)
        or parentName:find('rocket',1,true) or parentName:find('missile',1,true)
        or name:find('Ракет',1,true) or name:find('ракет',1,true)
end
local function interceptor(object)
    local name=string.lower(object.Name)
    if name:find('stinger',1,true) or name:find('interceptor',1,true) then return true end
    return rocketLike(object) and isPlayerOwner(metadata(object,ownerKeys))
end
local roster={}
local function rebuildRoster()
    roster={}
    local seen={}
    local character=player.Character
    local function add(object)
        if seen[object] or interceptor(object) or blockedAncestor(object,character) then return end
        if targetPart(object) then seen[object]=true;table.insert(roster,object) end
    end
    local droneFolder=workspace:FindFirstChild('Drones')
    if droneFolder then
        local queue={droneFolder};local index=1
        while index<=#queue and index<=1024 do
            local folder=queue[index];index=index+1
            for _,object in ipairs(folder:GetChildren()) do
                if object:IsA('Folder') and #queue<1024 then table.insert(queue,object)
                else add(object) end
            end
        end
    else
        -- Without the game's target container, count only name-recognized UAVs.
        for object,kind in pairs(candidates) do
            if kind~='missile' then
                local ancestor,nested=object.Parent,false
                while ancestor and ancestor~=workspace do
                    if candidates[ancestor] then nested=true;break end
                    ancestor=ancestor.Parent
                end
                if not nested then add(object) end
            end
        end
    end
    counter.Text=(droneFolder and 'БПЛА в небе: ' or 'БПЛА найдено: ')..#roster
end
local rosterTime=1
table.insert(connections,RunService.Heartbeat:Connect(function(dt)
    rosterTime=rosterTime+dt
    if rosterTime>=0.5 then rosterTime=0;rebuildRoster() end
end))
