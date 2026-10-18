-- Preliminary name-based ESP. Not verified against ILP Studio's object hierarchy.
-- Execute only once per session; running again replaces the previous instance.
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService=game:GetService('UserInputService')
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
local HttpService=game:GetService('HttpService')
local prefs={dotSize=4,outlineTransparency=0.2,showSpeed=true,showDistance=true,arrows=true,alerts=true,alertMeters=200,showDirection=true,radar=true,radarMeters=300,radarSize=150,radarTransparency=0.25,positions={menu={x=0,y=0},counter={x=1,y=0},radar={x=1,y=0.2}}}
local settingsFile='uav_esp_settings_'..tostring(game.PlaceId)..'.json'
local persistenceMessage='Настройки: только текущая сессия'
local function finite(value,low,high)
    return type(value)=='number' and value==value and value>=low and value<=high
end
local function restoreSettings(data)
    if type(data)~='table' or data.version~=1 then return false end
    if type(data.prefs)=='table' then
        for key in pairs(prefs) do
            local value=data.prefs[key]
            if type(prefs[key])=='boolean' and type(value)=='boolean' then prefs[key]=value end
        end
        if finite(data.prefs.dotSize,2,8) then prefs.dotSize=math.floor(data.prefs.dotSize+0.5) end
        if finite(data.prefs.outlineTransparency,0,1) then prefs.outlineTransparency=data.prefs.outlineTransparency end
        if finite(data.prefs.alertMeters,50,1000) then prefs.alertMeters=math.floor(data.prefs.alertMeters) end
    end
    if type(data.prefs)=='table' then
        if finite(data.prefs.radarMeters,100,1000) then prefs.radarMeters=math.floor(data.prefs.radarMeters) end
        if finite(data.prefs.radarSize,120,240) then prefs.radarSize=math.floor(data.prefs.radarSize) end
        if finite(data.prefs.radarTransparency,0,0.9) then prefs.radarTransparency=data.prefs.radarTransparency end
        if type(data.prefs.positions)=='table' then
            for _,key in ipairs({'menu','counter','radar'}) do
                local pos=data.prefs.positions[key]
                if type(pos)=='table' and finite(pos.x,0,1) and finite(pos.y,0,1) then prefs.positions[key]={x=pos.x,y=pos.y} end
            end
        end
    end
    if finite(data.distance,300,5000) then distance=math.floor(data.distance) end
    if type(data.automatic)=='boolean' then automatic=data.automatic end
    if type(data.enabled)=='table' then
        for key in pairs(enabled) do if type(data.enabled[key])=='boolean' then enabled[key]=data.enabled[key] end end
    end
    return true
end
if type(readfile)=='function' then
    local ok,data=pcall(function()return HttpService:JSONDecode(readfile(settingsFile))end)
    if ok and restoreSettings(data) then persistenceMessage='Сохранённые настройки загружены' end
end
local settingsStatus
local saveQueued=false
local function saveNow()
    if type(writefile)~='function' then persistenceMessage='Запись недоступна: настройки на эту сессию'
    else
        local ok=pcall(function()
            writefile(settingsFile,HttpService:JSONEncode({version=1,prefs=prefs,enabled=enabled,distance=distance,automatic=automatic}))
        end)
        persistenceMessage=ok and 'Настройки сохранены на устройстве' or 'Не удалось сохранить настройки'
    end
    if settingsStatus and settingsStatus.Parent then settingsStatus.Text=persistenceMessage end
end
local function changed()
    if saveQueued then return end
    saveQueued=true
    task.delay(1,function()
        saveQueued=false
        if alive then saveNow() end
    end)
end

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
    if saveQueued then saveNow() end
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
close.Size = UDim2.fromOffset(74,44)
close.Position = UDim2.new(1,-78,0,4)
close.Text = '× Скрыть'
close.TextSize = 16
close.TextColor3 = Color3.new(1,1,1)
close.BackgroundTransparency = 1
close.Parent = panel
local dragHeader=Instance.new('TextLabel')
dragHeader.Size=UDim2.new(1,-86,0,44)
dragHeader.Position=UDim2.fromOffset(8,4)
dragHeader.BackgroundTransparency=1
dragHeader.Text='БПЛА ESP • перетащи'
dragHeader.TextColor3=Color3.new(1,1,1)
dragHeader.TextSize=13;dragHeader.Parent=panel
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
    local button = row((kind == 'uav' and 'Все БПЛА' or names[kind]) .. ': ' .. (enabled[kind] and 'ВКЛ' or 'ВЫКЛ'), true)
    button.Activated:Connect(function()
        enabled[kind] = not enabled[kind]
        changed()
        button.Text = (kind == 'uav' and 'Все БПЛА' or names[kind]) .. ': ' .. (enabled[kind] and 'ВКЛ' or 'ВЫКЛ')
    end)
end
local rangeButton = row('Дальность: 420 м • +140 м', true)
rangeButton.Activated:Connect(function()
    if calibrating then return end
    automatic = false
    distance = distance >= 5000 and 500 or math.min(5000, distance + 500)
    changed()
end)
local autoButton = row('Автоподбор дальности', true)
autoButton.Activated:Connect(function()
    if calibrating then return end
    if automatic then automatic = false; changed(); return end
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
        changed()
    end)
end)
local function preferenceToggle(key,title)
    local button=row('',true)
    local function refresh()button.Text=title..': '..(prefs[key] and 'ВКЛ' or 'ВЫКЛ')end
    refresh()
    button.Activated:Connect(function()prefs[key]=not prefs[key];refresh();changed()end)
end
preferenceToggle('alerts','Предупреждение о приближении')
local alertRange=row('',true)
local function alertRangeText()alertRange.Text='Порог тревоги: '..prefs.alertMeters..' м • +50'end
alertRangeText()
alertRange.Activated:Connect(function()
    prefs.alertMeters=prefs.alertMeters>=1000 and 50 or math.min(1000,prefs.alertMeters+50)
    alertRangeText();changed()
end)
preferenceToggle('arrows','Стрелки вне экрана • 4 ближайших')
local dotButton=row('',true)
local function dotText()dotButton.Text='Размер точки: '..prefs.dotSize..' px'end
dotText()
dotButton.Activated:Connect(function()prefs.dotSize=prefs.dotSize>=8 and 2 or prefs.dotSize+1;dotText();changed()end)
local outlineButton=row('',true)
local function outlineText()outlineButton.Text='Прозрачность обводки: '..math.floor(prefs.outlineTransparency*100+0.5)..'%'end
outlineText()
outlineButton.Activated:Connect(function()
    prefs.outlineTransparency=prefs.outlineTransparency>=0.99 and 0 or math.min(1,math.floor(prefs.outlineTransparency*10+1.5)/10)
    outlineText();changed()
end)
preferenceToggle('showSpeed','Показывать скорость')
preferenceToggle('showDistance','Показывать расстояние')
preferenceToggle('showDirection','Приближается / удаляется')
preferenceToggle('radar','Мини-радар')
local radarRangeButton=row('',true)
local function radarRangeText()radarRangeButton.Text='Радиус радара: '..prefs.radarMeters..' м • +100'end
radarRangeText()
radarRangeButton.Activated:Connect(function()
    prefs.radarMeters=prefs.radarMeters>=1000 and 100 or math.min(1000,prefs.radarMeters+100)
    radarRangeText();changed()
end)
local radarSizeButton=row('',true)
local function radarSizeText()radarSizeButton.Text='Размер радара: '..prefs.radarSize..' px • +30'end
radarSizeText()
radarSizeButton.Activated:Connect(function()
    prefs.radarSize=prefs.radarSize>=240 and 120 or math.min(240,prefs.radarSize+30)
    radarSizeText();changed()
end)
local radarOpacityButton=row('',true)
local function radarOpacityText()radarOpacityButton.Text='Прозрачность фона радара: '..math.floor(prefs.radarTransparency*100+0.5)..'%'end
radarOpacityText()
radarOpacityButton.Activated:Connect(function()
    prefs.radarTransparency=prefs.radarTransparency>=0.89 and 0 or math.min(0.9,math.floor(prefs.radarTransparency*10+1.5)/10)
    radarOpacityText();changed()
end)
row('Сохранить настройки сейчас',true).Activated:Connect(saveNow)
settingsStatus=row(persistenceMessage,false,44)
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
    dot.Size = UDim2.fromOffset(prefs.dotSize,prefs.dotSize)
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
    outline.OutlineTransparency = prefs.outlineTransparency
    outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    outline.Parent = object
    outlines[object] = outline
    local speed = Instance.new('TextLabel')
    speed.Name = 'ESP_Speed'
    speed.AnchorPoint = Vector2.new(0.5,1)
    speed.Size = UDim2.fromOffset(190,30)
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
        local character=player.Character
        local viewer=character and (character:FindFirstChild('HumanoidRootPart') or character:FindFirstChild('Head'))
        local trend='нет замера'
        if viewer then
            local currentRange=(item.part.Position-viewer.Position).Magnitude
            local dtRange=sample.rangeTime and now-sample.rangeTime or 0
            if sample.viewer==viewer and sample.previousRange and dtRange>0 and dtRange<=2 then
                local closing=(sample.previousRange-currentRange)/dtRange
                if math.abs(closing)<2000 then
                    sample.closing=sample.closing and sample.closing*0.5+closing*0.5 or closing
                    trend=sample.closing>2 and 'приближается' or (sample.closing < -2 and 'удаляется' or 'дистанция стабильна')
                else sample.closing=nil end
            else sample.closing=nil end
            sample.previousRange,sample.rangeTime,sample.viewer=currentRange,now,viewer
        end
        local lines={}
        if prefs.showSpeed then table.insert(lines,sample.speed and string.format('%d км/ч',math.floor(sample.speed*METERS_PER_STUD*3.6+0.5)) or '— км/ч') end
        if prefs.showDirection then table.insert(lines,trend) end
        speedLabels[item.object].Text=table.concat(lines,'\n')
        billboard.Adornee = item.part
        billboard.MaxDistance = distance
        billboard.Dot.Size=UDim2.fromOffset(prefs.dotSize,prefs.dotSize)
        billboard.Distance.Visible=prefs.showDistance
        outlines[item.object].OutlineTransparency=prefs.outlineTransparency
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
            outline.OutlineTransparency=prefs.outlineTransparency
            if onScreen and (prefs.showSpeed or prefs.showDirection) then
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

-- Approach alerts are based on target motion and closing distance, not camera motion.
local warning=Instance.new('TextLabel')
warning.AnchorPoint=Vector2.new(0.5,1)
warning.Position=UDim2.new(0.5,0,1,-12)
warning.Size=UDim2.new(1,-24,0,44)
warning.BackgroundColor3=Color3.fromRGB(105,35,30)
warning.BackgroundTransparency=0.12
warning.TextColor3=Color3.new(1,1,1)
warning.TextSize=15;warning.TextWrapped=true;warning.Visible=false;warning.Parent=root
Instance.new('UICorner',warning).CornerRadius=UDim.new(0,8)
local arrowSlots={}
for i=1,4 do
    local frame=Instance.new('Frame')
    frame.AnchorPoint=Vector2.new(0.5,0.5);frame.Size=UDim2.fromOffset(64,40)
    frame.BackgroundTransparency=1;frame.Visible=false;frame.Parent=root
    local arrow=Instance.new('TextLabel')
    arrow.AnchorPoint=Vector2.new(0.5,0.5);arrow.Position=UDim2.fromScale(0.5,0.3)
    arrow.Size=UDim2.fromOffset(24,24);arrow.BackgroundTransparency=1
    arrow.Text='▲';arrow.TextSize=19;arrow.TextColor3=Color3.fromRGB(255,220,100)
    arrow.TextStrokeTransparency=0.5;arrow.Parent=frame
    local label=Instance.new('TextLabel')
    label.Position=UDim2.new(0,0,0,26);label.Size=UDim2.new(1,0,0,12)
    label.BackgroundTransparency=1;label.TextSize=10;label.TextColor3=Color3.new(1,1,1)
    label.TextStrokeTransparency=0.5;label.Parent=frame
    arrowSlots[i]={frame=frame,arrow=arrow,label=label}
end
local function approaching(previous,position,range,dt,origin)
    if not previous or dt<=0 or dt>2 or range<0.001 then return false end
    local velocity=(position-previous.position)/dt
    if velocity.Magnitude>2000 then return false end -- discontinuity/teleport
    local radial=velocity:Dot((origin-position).Unit)
    local closing=(previous.range-range)/dt
    return radial>2 and closing>2
end
local function edgePoint(dx,dy,width,height)
    if math.abs(dx)+math.abs(dy)<0.001 then dx,dy=0,1 end -- directly behind
    local halfWidth=math.max(1,width/2-36)
    local halfHeight=math.max(1,height/2-54)
    local factor=1/math.max(math.abs(dx)/halfWidth,math.abs(dy)/halfHeight)
    return width/2+dx*factor,height/2+dy*factor,math.deg(math.atan2(dy,dx))+90
end
local approachSamples={}
local previousCharacter
local extraElapsed=0
local warningUntil,lastWarning=0,-math.huge
local offscreenTargets={}
table.insert(connections,RunService.Heartbeat:Connect(function(dt)
    extraElapsed=extraElapsed+dt
    if extraElapsed<0.25 then return end
    extraElapsed=0
    local camera=workspace.CurrentCamera
    local character=player.Character
    local head=character and (character:FindFirstChild('HumanoidRootPart') or character:FindFirstChild('Head'))
    local humanoid=character and character:FindFirstChildOfClass('Humanoid')
    if character~=previousCharacter then
        approachSamples={};previousCharacter=character;warningUntil=0
    end
    if not camera or not head or (humanoid and humanoid.Health<=0) then
        offscreenTargets={};approachSamples={};warning.Visible=false;return
    end
    local now=os.clock()
    local found,keep={},{}
    local nearestAlert,nearestRange
    for _,object in ipairs(roster) do
        local part=targetPart(object)
        if part then
            local position=part.Position
            local range=(position-head.Position).Magnitude
            local previous=approachSamples[object]
            local sampleDt=previous and now-previous.time or 0
            local threshold=prefs.alertMeters/METERS_PER_STUD
            local alerted=previous and previous.alerted or false
            if range>threshold*1.2 then alerted=false end
            if prefs.alerts and range<=threshold and not alerted and approaching(previous,position,range,sampleDt,head.Position) then
                if not nearestRange or range<nearestRange then nearestAlert,nearestRange=object,range end
            end
            keep[object]={position=position,range=range,time=now,alerted=alerted}
            if prefs.arrows and range<=distance then
                local _,onScreen=camera:WorldToViewportPoint(position)
                if not onScreen then table.insert(found,{object=object,part=part,range=range}) end
            end
        end
    end
    approachSamples=keep
    if nearestAlert and now-lastWarning>=4 then
        approachSamples[nearestAlert].alerted=true
        lastWarning=now;warningUntil=now+3
        warning.Text=string.format('БПЛА приближается • %d м',math.floor(nearestRange*METERS_PER_STUD+0.5))
    end
    warning.Visible=prefs.alerts and now<warningUntil
    table.sort(found,function(a,b)return a.range<b.range end)
    offscreenTargets={}
    for i=1,math.min(4,#found) do offscreenTargets[i]=found[i] end
end))
table.insert(connections,RunService.RenderStepped:Connect(function()
    local camera=workspace.CurrentCamera
    for i,slot in ipairs(arrowSlots) do
        slot.frame.Visible=false
        local target=offscreenTargets[i]
        if prefs.arrows and camera and target and target.part:IsDescendantOf(workspace) then
            local _,onScreen=camera:WorldToViewportPoint(target.part.Position)
            if not onScreen then
                local localPosition=camera.CFrame:PointToObjectSpace(target.part.Position)
                local x,y,rotation=edgePoint(localPosition.X,-localPosition.Y,root.AbsoluteSize.X,root.AbsoluteSize.Y)
                slot.frame.Position=UDim2.fromOffset(x,y)
                slot.arrow.Rotation=rotation
                slot.label.Visible=prefs.showDistance
                slot.label.Text=string.format('%d м',math.floor(target.range*METERS_PER_STUD+0.5))
                slot.frame.Visible=true
            end
        end
    end
end))

-- Store top-left positions as fractions of usable space; preserve them on rotation.
local function widgetPoint(pos,width,height,widgetWidth,widgetHeight)
    local spanX=math.max(0,width-widgetWidth-16)
    local spanY=math.max(0,height-widgetHeight-16)
    return math.min(8,math.max(0,width-widgetWidth))+pos.x*spanX,
        math.min(8,math.max(0,height-widgetHeight))+pos.y*spanY,spanX,spanY
end
local function draggable(widget,handle,key)
    widget.AnchorPoint=Vector2.new(0,0)
    local handles=type(handle)=='table' and handle or {handle}
    for _,surface in ipairs(handles) do surface.Active=true end
    local activeInput,startPointer,startPosition
    local function place()
        if activeInput then return end
        local x,y=widgetPoint(prefs.positions[key],root.AbsoluteSize.X,root.AbsoluteSize.Y,widget.AbsoluteSize.X,widget.AbsoluteSize.Y)
        widget.Position=UDim2.fromOffset(x,y)
        if key=='menu' then toggle.Position=widget.Position end
    end
    for _,surface in ipairs(handles) do
    table.insert(connections,surface.InputBegan:Connect(function(input)
        if activeInput or not (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1) then return end
        activeInput=input;startPointer=Vector2.new(input.Position.X,input.Position.Y)
        startPosition=widget.AbsolutePosition-root.AbsolutePosition
    end))
    end
    table.insert(connections,UserInputService.InputChanged:Connect(function(input)
        if not activeInput then return end
        if input~=activeInput and not (activeInput.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then return end
        local pointer=Vector2.new(input.Position.X,input.Position.Y)
        local point=startPosition+pointer-startPointer
        local x,y,spanX,spanY=widgetPoint({x=0,y=0},root.AbsoluteSize.X,root.AbsoluteSize.Y,widget.AbsoluteSize.X,widget.AbsoluteSize.Y)
        local px=math.clamp(point.X,x,x+spanX)
        local py=math.clamp(point.Y,y,y+spanY)
        prefs.positions[key]={x=spanX>0 and (px-x)/spanX or 0,y=spanY>0 and (py-y)/spanY or 0}
        widget.Position=UDim2.fromOffset(px,py)
        if key=='menu' then toggle.Position=widget.Position end
    end))
    local function finish()
        if activeInput then activeInput=nil;changed();place() end
    end
    table.insert(connections,UserInputService.InputEnded:Connect(function(input)if input==activeInput then finish() end end))
    table.insert(connections,UserInputService.WindowFocusReleased:Connect(finish))
    table.insert(connections,root:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()finish();place()end))
    table.insert(connections,widget:GetPropertyChangedSignal('AbsoluteSize'):Connect(place))
    place()
end
draggable(panel,dragHeader,'menu')
draggable(counter,counter,'counter')

local radar=Instance.new('Frame')
radar.Name='MiniRadar'
radar.AnchorPoint=Vector2.new(1,0)
radar.Position=UDim2.new(1,-12,0,58)
radar.Size=UDim2.fromOffset(150,174)
radar.BackgroundTransparency=1;radar.Parent=root
local radarTitle=Instance.new('TextLabel')
radarTitle.Size=UDim2.new(1,0,0,24)
radarTitle.BackgroundTransparency=1;radarTitle.TextSize=12
radarTitle.TextColor3=Color3.new(1,1,1);radarTitle.Parent=radar
local disc=Instance.new('Frame')
disc.Position=UDim2.fromOffset(0,24);disc.Size=UDim2.fromOffset(150,150)
disc.BackgroundColor3=Color3.fromRGB(18,26,35);disc.BackgroundTransparency=0.25
disc.BorderSizePixel=0;disc.Parent=radar
Instance.new('UICorner',disc).CornerRadius=UDim.new(1,0)
local stroke=Instance.new('UIStroke',disc)
stroke.Color=Color3.fromRGB(110,130,145);stroke.Transparency=0.4;stroke.Thickness=1
for _,vertical in ipairs({true,false}) do
    local line=Instance.new('Frame')
    line.AnchorPoint=Vector2.new(0.5,0.5);line.Position=UDim2.fromScale(0.5,0.5)
    line.Size=vertical and UDim2.new(0,1,1,-12) or UDim2.new(1,-12,0,1)
    line.BackgroundColor3=Color3.fromRGB(110,130,145);line.BackgroundTransparency=0.65
    line.BorderSizePixel=0;line.Parent=disc
end
local selfMarker=Instance.new('TextLabel')
selfMarker.AnchorPoint=Vector2.new(0.5,0.5);selfMarker.Position=UDim2.fromScale(0.5,0.5)
selfMarker.Size=UDim2.fromOffset(14,16);selfMarker.BackgroundTransparency=1
selfMarker.Text='▲';selfMarker.TextSize=12;selfMarker.TextColor3=Color3.fromRGB(90,220,255)
selfMarker.ZIndex=3;selfMarker.Parent=disc
local radarDots={}
for i=1,24 do
    local dot=Instance.new('Frame')
    dot.AnchorPoint=Vector2.new(0.5,0.5);dot.Size=UDim2.fromOffset(4,4)
    dot.BackgroundColor3=Color3.new(1,1,1);dot.BorderSizePixel=0;dot.Visible=false
    dot.ZIndex=2;dot.Parent=disc;Instance.new('UICorner',dot).CornerRadius=UDim.new(1,0)
    radarDots[i]=dot
end
local function radarPoint(dx,dz,fx,fz,range,radius)
    local length=math.sqrt(fx*fx+fz*fz)
    if length<0.001 then fx,fz=0,-1 else fx,fz=fx/length,fz/length end
    local right=dx*(-fz)+dz*fx
    local forward=dx*fx+dz*fz
    return right/range*radius,-forward/range*radius
end
local function radarDiameter(requested,width,height)
    return math.max(1,math.min(requested,width-16,height-40))
end
local function radarStyle()
    local size=radarDiameter(prefs.radarSize,root.AbsoluteSize.X,root.AbsoluteSize.Y)
    radar.Size=UDim2.fromOffset(size,size+24)
    disc.Size=UDim2.fromOffset(size,size)
    disc.BackgroundTransparency=prefs.radarTransparency
end
radarStyle()
table.insert(connections,root:GetPropertyChangedSignal('AbsoluteSize'):Connect(radarStyle))
draggable(radar,{radarTitle,disc},'radar')
local radarElapsed=1
local lastForward=Vector3.new(0,0,-1)
table.insert(connections,RunService.Heartbeat:Connect(function(dt)
    radarElapsed=radarElapsed+dt
    if radarElapsed<0.2 then return end
    radarElapsed=0
    radarStyle()
    radar.Visible=prefs.radar
    if not prefs.radar then return end
    for _,dot in ipairs(radarDots) do dot.Visible=false end
    local camera=workspace.CurrentCamera
    local character=player.Character
    local originPart=character and (character:FindFirstChild('HumanoidRootPart') or character:FindFirstChild('Head'))
    if not camera or not originPart then radarTitle.Text='Радар • нет персонажа';return end
    local forward=camera.CFrame.LookVector
    if forward.X*forward.X+forward.Z*forward.Z>0.0001 then lastForward=forward end
    local range=prefs.radarMeters/METERS_PER_STUD
    local nearby={}
    for _,object in ipairs(roster) do
        local part=targetPart(object)
        if part then
            local delta=part.Position-originPart.Position
            local horizontal=math.sqrt(delta.X*delta.X+delta.Z*delta.Z)
            if horizontal<=range then table.insert(nearby,{delta=delta,distance=horizontal}) end
        end
    end
    table.sort(nearby,function(a,b)return a.distance<b.distance end)
    local count=math.min(24,#nearby)
    for i=1,count do
        local entry=nearby[i]
        local x,y=radarPoint(entry.delta.X,entry.delta.Z,lastForward.X,lastForward.Z,range,math.max(1,disc.AbsoluteSize.X/2-7))
        radarDots[i].Position=UDim2.fromOffset(disc.AbsoluteSize.X/2+x,disc.AbsoluteSize.Y/2+y)
        radarDots[i].Visible=true
    end
    radarTitle.Text=string.format('Радар %d м • %d/%d',prefs.radarMeters,count,#nearby)
end))
