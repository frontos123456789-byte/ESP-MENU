-- Второй скрипт от Codex | FPV Drone Game | v1.1.0
-- Independent companion: keep this file separate from other ESP scripts.
-- No existing repository files or other scripts' interfaces are modified.
-- Drone status uses replicated boolean flags only; unknown is NEVER treated as false.
-- Roblox standard scale: 1 stud = 0.28 m (adjustable in this menu).
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UIS = game:GetService('UserInputService')
local Http = game:GetService('HttpService')
local Workspace = game:GetService('Workspace')
local me = Players.LocalPlayer
if not me then return end
local playerGui = me:WaitForChild('PlayerGui')
local env = (getgenv and getgenv()) or _G
local KEY = '__CodexSecondPlayerESP_v1'
if type(env[KEY]) == 'function' then pcall(env[KEY]) end
local alive, connections, records = true, {}, {}
local defaults = {enabled=true, boxes=true, names=true, distance=true, status=true,
    tracers=false, arrows=true, health=false, teamFilter=false, teamColor=false,
    visibleOnly=false, visibility=true, maxDistance=1500, maxPlayers=24,
    fps=5, textSize=14, thickness=1, opacity=0.85, scale=0.28,
    color=1, origin=1, font=1, statusKey='', menuX=0.03, menuY=0.12}
local cfg = {}
for k,v in pairs(defaults) do cfg[k]=v end
local limits = {maxDistance={50,10000},maxPlayers={1,64},fps={2,10},textSize={10,22},
    thickness={1,3},opacity={0.2,1},scale={0.01,10},color={1,5},origin={1,3},font={1,3},menuX={0,1},menuY={0,1}}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function validate(k,v)
    local d=defaults[k]
    if type(d)=='boolean' then return type(v)=='boolean' and v or (v~=false and d) end
    if limits[k] and finite(v) then
        local n=math.clamp(v,limits[k][1],limits[k][2])
        if k=='color' or k=='origin' or k=='font' or k=='maxPlayers' or k=='fps' then n=math.floor(n) end
        return n
    end
    if k=='statusKey' and type(v)=='string' and #v<=80 then return v end
    return d
end
local savePath='codex_second_esp_'..tostring(game.PlaceId)..'.json'
if type(readfile)=='function' then
    pcall(function()
        local raw=readfile(savePath)
        if #raw>16384 then return end
        local data=Http:JSONDecode(raw)
        if type(data)~='table' then return end
        for k in pairs(defaults) do if data[k]~=nil then cfg[k]=validate(k,data[k]) end end
    end)
end
local dirtyAt
local function dirty() dirtyAt=os.clock() end
local function save()
    if type(writefile)~='function' then return false end
    return pcall(function() writefile(savePath,Http:JSONEncode(cfg)) end)
end
local function connect(event,fn)
    local c=event:Connect(fn); connections[#connections+1]=c; return c
end
local function make(class,props,parent)
    local o=Instance.new(class)
    for k,v in pairs(props or {}) do o[k]=v end
    o.Parent=parent; return o
end
local function round(o,r) make('UICorner',{CornerRadius=UDim.new(0,r or 8)},o) end
local colors={Color3.fromRGB(225,236,255),Color3.fromRGB(110,210,255),Color3.fromRGB(190,155,255),Color3.fromRGB(255,195,100),Color3.fromRGB(115,245,185)}
local fonts={Enum.Font.GothamMedium,Enum.Font.GothamBold,Enum.Font.Code}
local green,red,gray=Color3.fromRGB(93,235,145),Color3.fromRGB(255,102,120),Color3.fromRGB(167,178,195)
local overlay=make('ScreenGui',{Name='CodexSecondESP_Overlay',ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=50,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
pcall(function() overlay.ScreenInsets=Enum.ScreenInsets.None;overlay.ClipToDeviceSafeArea=false end)
local ui=make('ScreenGui',{Name='CodexSecondESP_Menu',ResetOnSpawn=false,DisplayOrder=60,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
pcall(function() ui.ScreenInsets=Enum.ScreenInsets.DeviceSafeInsets end)
local safe=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1},ui)
local bg=Color3.fromRGB(12,17,24)
local panelColor=Color3.fromRGB(17,23,32)
local accent=Color3.fromRGB(127,143,255)
local menu=make('Frame',{BackgroundColor3=bg,BorderSizePixel=0,ClipsDescendants=true},safe);round(menu,10)
make('UIStroke',{Color=Color3.fromRGB(48,61,78),Thickness=1},menu)
local function button(parent,text,pos,size)
    local b=make('TextButton',{Text=text,Position=pos,Size=size,BackgroundColor3=Color3.fromRGB(27,36,49),TextColor3=colors[1],TextSize=12,Font=Enum.Font.GothamMedium,BorderSizePixel=0,AutoButtonColor=true},parent);round(b,5);return b
end
local title=make('TextLabel',{Size=UDim2.new(1,-62,0,44),Position=UDim2.fromOffset(14,0),BackgroundTransparency=1,Text='CODEX  /  PLAYER ESP',TextColor3=colors[1],TextSize=14,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,Active=true},menu)
local collapse=button(menu,'×',UDim2.new(1,-40,0,6),UDim2.fromOffset(32,32))
local opener=button(safe,'CODEX  ESP',UDim2.fromOffset(12,12),UDim2.fromOffset(112,42));opener.Visible=false
local nav=make('Frame',{BackgroundColor3=Color3.fromRGB(14,20,28),BorderSizePixel=0},menu);round(nav,6)
local brand=make('TextLabel',{Size=UDim2.new(1,0,0,60),BackgroundTransparency=1,Text='C / X\nCODEX',TextColor3=accent,TextSize=16,Font=Enum.Font.GothamBold},nav)
local footer=make('TextLabel',{Size=UDim2.new(1,-24,0,24),Position=UDim2.new(0,12,1,-26),BackgroundTransparency=1,Text='Второй скрипт от Codex  •  × скрывает только меню',TextColor3=gray,TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left},menu)
local content=make('Frame',{BackgroundTransparency=1},menu)
local pages,tabs,groups={},{},{}
local activePage='VISUALS'
local function page(name)
    local sc=make('ScrollingFrame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=accent,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollingDirection=Enum.ScrollingDirection.Y,Visible=name==activePage},content)
    make('UIPadding',{PaddingRight=UDim.new(0,6),PaddingBottom=UDim.new(0,8)},sc)
    local flow=make('UIListLayout',{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder},sc)
    pages[name]={root=sc,flow=flow,groups={}}
    local b=button(nav,name,UDim2.new(),UDim2.new());tabs[name]=b
    connect(b.Activated,function()
        activePage=name
        for key,p in pairs(pages) do p.root.Visible=key==name;tabs[key].BackgroundColor3=key==name and Color3.fromRGB(39,54,77) or panelColor;tabs[key].TextColor3=key==name and accent or gray end
    end)
end
page('VISUALS');page('STYLE');page('SETTINGS')
local list,order
local function group(pageName,heading)
    local p=pages[pageName]
    list=make('Frame',{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=panelColor,BorderSizePixel=0,LayoutOrder=#p.groups+1},p.root);round(list,6)
    p.groups[#p.groups+1]=list;groups[#groups+1]=list
    make('UIPadding',{PaddingLeft=UDim.new(0,9),PaddingRight=UDim.new(0,9),PaddingTop=UDim.new(0,9),PaddingBottom=UDim.new(0,9)},list)
    make('UIListLayout',{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder},list)
    order=0
    local head=make('TextLabel',{Size=UDim2.new(1,0,0,26),BackgroundColor3=Color3.fromRGB(26,35,47),BorderSizePixel=0,Text='  '..heading,TextColor3=gray,TextSize=11,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left},list);round(head,4)
end
local function row(o) order=order+1;o.LayoutOrder=order;return o end
local function note(text,height)
    return row(make('TextLabel',{Size=UDim2.new(1,0,0,height or 44),BackgroundTransparency=1,Text=text,TextWrapped=true,TextColor3=gray,TextSize=11,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left},list))
end
local refreshers={}
local function toggle(k,label)
    local b=row(button(list,'',UDim2.new(),UDim2.new(1,0,0,36)))
    b.BackgroundColor3=Color3.fromRGB(13,19,27)
    local track=make('Frame',{Position=UDim2.fromOffset(8,11),Size=UDim2.fromOffset(28,14),BorderSizePixel=0},b);round(track,9)
    local knob=make('Frame',{Size=UDim2.fromOffset(10,10),BackgroundColor3=colors[1],BorderSizePixel=0},track);round(knob,9)
    make('TextLabel',{Position=UDim2.fromOffset(44,0),Size=UDim2.new(1,-48,1,0),BackgroundTransparency=1,Text=label,TextSize=12,TextColor3=colors[1],Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left},b)
    local function refresh() track.BackgroundColor3=cfg[k] and accent or Color3.fromRGB(54,63,77);knob.Position=UDim2.fromOffset(cfg[k] and 16 or 2,2) end
    refreshers[#refreshers+1]=refresh;refresh()
    connect(b.Activated,function() cfg[k]=not cfg[k];dirty();for _,f in ipairs(refreshers) do f() end end)
end
local function cycle(k,label,values,labels)
    local b=row(button(list,'',UDim2.new(),UDim2.new(1,0,0,43)))
    b.TextXAlignment=Enum.TextXAlignment.Left
    local function refresh()
        local display=tostring(cfg[k]);for i,v in ipairs(values) do if v==cfg[k] then display=labels and labels[i] or tostring(v) end end
        b.Text='  '..label..'\n  '..display..'  ›'
    end
    refreshers[#refreshers+1]=refresh;refresh()
    connect(b.Activated,function()
        local idx=0;for i,v in ipairs(values) do if v==cfg[k] then idx=i;break end end
        cfg[k]=values[idx % #values+1];dirty();for _,f in ipairs(refreshers) do f() end
    end)
end
group('VISUALS','PLAYER / Игроки')
for _,r in ipairs({{'enabled','Включить ESP'},{'boxes','3D Box'},{'names','Никнейм'},{'distance','Расстояние'},{'status','Статус дрона'},{'health','Здоровье'}}) do toggle(r[1],r[2]) end
group('VISUALS','WORLD / Видимость')
for _,r in ipairs({{'arrows','Стрелки вне экрана'},{'tracers','Трассеры'},{'teamFilter','Скрыть союзников'},{'teamColor','Цвет команды'},{'visibility','Затемнять за стенами'},{'visibleOnly','Только видимые'}}) do toggle(r[1],r[2]) end
cycle('maxDistance','Дальность, м',{100,250,500,1000,1500,3000,10000})
group('STYLE','APPEARANCE / Оформление')
local swatches=row(make('Frame',{Size=UDim2.new(1,0,0,38),BackgroundTransparency=1},list))
for i,c in ipairs(colors) do
    local b=button(swatches,'',UDim2.new((i-1)/5,3,0,5),UDim2.fromOffset(27,27));b.BackgroundColor3=c;round(b,20)
    local border=make('UIStroke',{Color=colors[1],Thickness=2,Enabled=cfg.color==i},b)
    refreshers[#refreshers+1]=function() border.Enabled=cfg.color==i end
    connect(b.Activated,function() cfg.color=i;dirty();for _,f in ipairs(refreshers) do f() end end)
end
cycle('textSize','Размер подписей',{12,14,16,18,20})
cycle('thickness','Толщина линий',{1,2,3})
cycle('opacity','Яркость',{0.4,0.6,0.85,1},{'40%','60%','85%','100%'})
cycle('origin','Начало трассеров',{1,2,3},{'Снизу','Центр','Сверху'})
cycle('font','Шрифт',{1,2,3},{'Gotham','Gotham Bold','Code'})
group('STYLE','PREVIEW / Пример')
local preview=row(make('Frame',{Size=UDim2.new(1,0,0,270),BackgroundColor3=Color3.fromRGB(10,16,23),BorderSizePixel=0},list));round(preview,6)
local silhouette=make('Frame',{Size=UDim2.fromOffset(92,150),Position=UDim2.new(0.5,-46,0,74),BackgroundTransparency=1},preview)
for _,p in ipairs({{34,0,24,26},{23,30,46,56},{3,31,16,62},{73,31,16,62},{24,90,20,60},{48,90,20,60}}) do
    local limb=make('Frame',{Position=UDim2.fromOffset(p[1],p[2]),Size=UDim2.fromOffset(p[3],p[4]),BackgroundColor3=Color3.fromRGB(43,56,72),BorderSizePixel=0},silhouette);round(limb,5)
end
local previewBox=make('Frame',{Position=UDim2.new(0.5,-55,0,66),Size=UDim2.fromOffset(110,167),BackgroundTransparency=1},preview)
local previewStroke=make('UIStroke',{Color=colors[cfg.color],Thickness=cfg.thickness},previewBox)
local previewText=make('TextLabel',{Position=UDim2.fromOffset(0,29),Size=UDim2.new(1,0,0,34),BackgroundTransparency=1,Text='Player\n125 м',TextSize=14,Font=fonts[1],TextColor3=colors[1]},preview)
local previewStatus=make('TextLabel',{Position=UDim2.fromOffset(0,6),Size=UDim2.new(1,0,0,20),BackgroundTransparency=1,Text='●  НЕ В РЕЖИМЕ ДРОНА',TextSize=10,Font=fonts[1],TextColor3=green},preview)
local previewHealth=make('Frame',{Position=UDim2.new(0.5,-62,0,66),Size=UDim2.fromOffset(3,167),BackgroundColor3=green,BorderSizePixel=0},preview)
refreshers[#refreshers+1]=function()
    previewBox.Visible=cfg.enabled and cfg.boxes;previewStroke.Color=colors[cfg.color];previewStroke.Thickness=cfg.thickness;previewStroke.Transparency=1-cfg.opacity
    previewText.Text=(cfg.names and 'Player' or '')..(cfg.distance and '\n125 м' or '');previewText.TextSize=cfg.textSize;previewText.Font=fonts[cfg.font];previewText.TextColor3=colors[cfg.color];previewText.Visible=cfg.enabled
    previewStatus.Visible=cfg.enabled and cfg.status;previewHealth.Visible=cfg.enabled and cfg.health
end
note('Схематичный пример оформления. В игре бокс объёмный.',34)
group('SETTINGS','PERFORMANCE / Настройки')
local summary=note('FPV Drone Game • v1.1\nБоксы синхронизированы с кадрами камеры.',38)
cycle('maxPlayers','Максимум игроков',{8,16,24,32,64})
cycle('fps','Проверок данных / с',{2,5,10})
cycle('scale','Метров в stud',{0.28,1},{'0.28 — стандарт','1 — масштаб режима'})
local saveButton=row(button(list,'Сохранить настройки',UDim2.new(),UDim2.new(1,0,0,38)))
connect(saveButton.Activated,function() summary.Text=save() and 'Настройки сохранены.' or 'Delta не предоставила запись файлов.' end)
local reset=row(button(list,'Сбросить настройки',UDim2.new(),UDim2.new(1,0,0,38)))
local stop=row(button(list,'Выключить этот скрипт',UDim2.new(),UDim2.new(1,0,0,38)))
group('SETTINGS','DRONE / Диагностика')
note('Зелёный — не в дроне; красный — в дроне; серый — нет данных. Автопоиск флагов не подтверждён для этой игры.',66)
note('Имя Boolean-атрибута / BoolValue:',30)
local statusInput=row(make('TextBox',{Size=UDim2.new(1,0,0,38),BackgroundColor3=Color3.fromRGB(30,39,55),TextColor3=colors[1],PlaceholderText='Автопоиск',Text=cfg.statusKey,ClearTextOnFocus=false,TextSize=12,Font=Enum.Font.Gotham,BorderSizePixel=0},list));round(statusInput)
connect(statusInput.FocusLost,function() cfg.statusKey=validate('statusKey',statusInput.Text);statusInput.Text=cfg.statusKey;dirty() end)
local info=note('Определяются только доступные клиенту Boolean-флаги.',42)
local inspect=row(button(list,'Источники статуса игроков',UDim2.new(),UDim2.new(1,0,0,38)))
connect(inspect.Activated,function()
    local lines={};for p,r in pairs(records) do lines[#lines+1]=p.Name..': '..(r.source or 'нет данных') end
    table.sort(lines);info.Text=table.concat(lines,'\n');info.Size=UDim2.new(1,0,0,math.max(60,#lines*42))
end)
local function menuMetrics(x,y)
    local w,h=math.max(1,math.min(850,x-16)),math.max(1,math.min(540,y-16))
    local compact=w<620
    local left=compact and 10 or 126
    local top=compact and 86 or 50
    local contentWidth=math.max(1,w-left-10)
    return w,h,compact,left,top,contentWidth,contentWidth>=460
end
local function layout()
    local s=safe.AbsoluteSize
    local w,h,compact,left,top,cw,two=menuMetrics(s.X,s.Y)
    menu.Size=UDim2.fromOffset(w,h)
    menu.Position=UDim2.fromOffset(8+cfg.menuX*math.max(0,s.X-w-16),8+cfg.menuY*math.max(0,s.Y-h-16))
    nav.Position=UDim2.fromOffset(10,compact and 45 or 50);nav.Size=compact and UDim2.fromOffset(w-20,33) or UDim2.fromOffset(106,h-84)
    brand.Visible=not compact
    for i,name in ipairs({'VISUALS','STYLE','SETTINGS'}) do
        tabs[name].Position=compact and UDim2.new((i-1)/3,2,0,0) or UDim2.fromOffset(5,65+(i-1)*44)
        tabs[name].Size=compact and UDim2.new(1/3,-4,1,0) or UDim2.new(1,-10,0,38)
        tabs[name].BackgroundColor3=name==activePage and Color3.fromRGB(39,54,77) or panelColor
    end
    content.Position=UDim2.fromOffset(left,top);content.Size=UDim2.fromOffset(cw,math.max(1,h-top-32))
    for _,p in pairs(pages) do
        p.flow.FillDirection=two and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
        for _,g in ipairs(p.groups) do g.Size=two and UDim2.new(0.5,-8,0,0) or UDim2.new(1,0,0,0) end
    end
    opener.Position=UDim2.fromOffset(math.clamp(menu.Position.X.Offset,0,math.max(0,s.X-112)),math.clamp(menu.Position.Y.Offset,0,math.max(0,s.Y-42)))
end
connect(reset.Activated,function() for k,v in pairs(defaults) do cfg[k]=v end;for _,f in ipairs(refreshers) do f() end;statusInput.Text='';layout();dirty() end)
for _,f in ipairs(refreshers) do f() end
connect(safe:GetPropertyChangedSignal('AbsoluteSize'),layout);layout()
connect(collapse.Activated,function() menu.Visible=false;opener.Visible=true;layout() end)
connect(opener.Activated,function() menu.Visible=true;opener.Visible=false end)
local dragging,dragStart,startPosition
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=input;dragStart=input.Position;startPosition=menu.Position end
end)
connect(UIS.InputChanged,function(input)
    if not dragging then return end
    if input~=dragging and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local delta=input.Position-dragStart;local s=safe.AbsoluteSize;local m=menu.AbsoluteSize
    cfg.menuX=math.clamp((startPosition.X.Offset+delta.X-8)/math.max(1,s.X-m.X-16),0,1)
    cfg.menuY=math.clamp((startPosition.Y.Offset+delta.Y-8)/math.max(1,s.Y-m.Y-16),0,1);layout()
end)
connect(UIS.InputEnded,function(input) if input==dragging then dragging=nil;dirty() end end)
local RENDER_KEY='CodexSecondPlayerESP_Render'
local function cleanup()
    if not alive then return end;alive=false;save();RunService:UnbindFromRenderStep(RENDER_KEY)
    for _,c in ipairs(connections) do c:Disconnect() end
    overlay:Destroy();ui:Destroy();table.clear(records)
    env[KEY]=nil
end
env[KEY]=cleanup
connect(stop.Activated,cleanup)
-- Returns only explicit booleans. Conflicting replicated values remain unknown.
local statusAliases={'InDrone','IsInDrone','DroneMode','IsDroneMode','ControllingDrone','IsControllingDrone','PilotingDrone','IsPilotingDrone','UsingDrone'}
local function mergeStatus(a,b)
    if b==nil then return a end
    if a==nil then return b end
    if a~=b then return 'conflict' end
    return a
end
local function droneStatus(player,character)
    local result,source=nil,nil
    local keys=cfg.statusKey~='' and {cfg.statusKey} or statusAliases
    local containers={player}
    if character then containers[#containers+1]=character end
    -- Only bounded, shallow containers; never scan Workspace or execute modules.
    for _,root in ipairs({player,character}) do
        if root then for _,name in ipairs({'Settings','Status','State','Data'}) do
            local f=root:FindFirstChild(name);if f then containers[#containers+1]=f end
        end end
    end
    for _,container in ipairs(containers) do for _,key in ipairs(keys) do
        local a=container:GetAttribute(key)
        if type(a)=='boolean' then result=mergeStatus(result,a);source=container.Name..'.@'..key end
        local v=container:FindFirstChild(key)
        if v and v:IsA('BoolValue') then result=mergeStatus(result,v.Value);source=container.Name..'.'..key end
    end end
    if result=='conflict' then return nil,'конфликт флагов' end
    return result,source
end
local function newLine(parent)
    return make('Frame',{AnchorPoint=Vector2.new(0.5,0.5),BorderSizePixel=0,BackgroundColor3=colors[1],Visible=false},parent)
end
local function add(player)
    if player==me or records[player] then return end
    local root=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false},overlay)
    local r={root=root,edges={}}
    for i=1,12 do r.edges[i]=newLine(root) end
    r.tracer=newLine(root)
    r.card=make('Frame',{AnchorPoint=Vector2.new(0.5,1),Size=UDim2.fromOffset(160,78),BackgroundTransparency=1},root)
    r.badge=make('Frame',{Size=UDim2.new(1,0,0,22),BackgroundColor3=Color3.fromRGB(15,20,30),BackgroundTransparency=0.15,BorderSizePixel=0},r.card);round(r.badge,6)
    r.dot=make('Frame',{Position=UDim2.fromOffset(8,7),Size=UDim2.fromOffset(7,7),BackgroundColor3=gray,BorderSizePixel=0},r.badge);round(r.dot,8)
    r.state=make('TextLabel',{Position=UDim2.fromOffset(20,0),Size=UDim2.new(1,-22,1,0),BackgroundTransparency=1,Text='НЕТ ДАННЫХ',TextSize=11,TextColor3=gray,Font=Enum.Font.GothamMedium},r.badge)
    r.label=make('TextLabel',{Position=UDim2.fromOffset(0,25),Size=UDim2.new(1,0,0,46),BackgroundTransparency=1,Text='',TextColor3=colors[1],TextStrokeTransparency=0.35,TextStrokeColor3=Color3.new(),TextSize=14,Font=fonts[1]},r.card)
    r.healthBack=make('Frame',{Position=UDim2.new(0.15,0,1,-4),Size=UDim2.new(0.7,0,0,3),BorderSizePixel=0,BackgroundColor3=Color3.fromRGB(35,35,40)},r.card)
    r.health=make('Frame',{Size=UDim2.fromScale(1,1),BorderSizePixel=0,BackgroundColor3=green},r.healthBack)
    r.arrow=make('TextLabel',{AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(24,24),BackgroundTransparency=1,Text='▲',TextSize=22,Font=Enum.Font.GothamBold,TextColor3=colors[1],TextStrokeTransparency=0.3,Visible=false},root)
    records[player]=r
end
local function remove(player) local r=records[player];if r then r.root:Destroy();records[player]=nil end end
connect(Players.PlayerAdded,add);connect(Players.PlayerRemoving,remove)
for _,p in ipairs(Players:GetPlayers()) do add(p) end
-- Liang-Barsky viewport clipping prevents huge rotated GUI frames near the camera.
local function clipLine(x1,y1,x2,y2,w,h)
    local dx,dy=x2-x1,y2-y1;local lo,hi=0,1
    local p={-dx,dx,-dy,dy};local q={x1,w-x1,y1,h-y1}
    for i=1,4 do
        if math.abs(p[i])<1e-9 then if q[i]<0 then return nil end
        else
            local t=q[i]/p[i]
            if p[i]<0 then lo=math.max(lo,t) else hi=math.min(hi,t) end
            if lo>hi then return nil end
        end
    end
    return x1+lo*dx,y1+lo*dy,x1+hi*dx,y1+hi*dy
end
local function edgePoint(dx,dy,w,h)
    if math.abs(dx)+math.abs(dy)<0.001 then dx,dy=0,1 end
    local scale=1/math.max(math.abs(dx)/math.max(1,w/2-28),math.abs(dy)/math.max(1,h/2-40))
    return w/2+dx*scale,h/2+dy*scale,math.deg(math.atan2(dy,dx))+90
end
local function drawLine(frame,a,b,color,alpha,viewport)
    local x1,y1,x2,y2=clipLine(a.X,a.Y,b.X,b.Y,viewport.X,viewport.Y)
    if not x1 then frame.Visible=false;return end
    local dx,dy=x2-x1,y2-y1;local len=math.sqrt(dx*dx+dy*dy)
    frame.Visible=len>0.1
    if not frame.Visible then return end
    frame.Position=UDim2.fromOffset((x1+x2)/2,(y1+y2)/2);frame.Size=UDim2.fromOffset(len,cfg.thickness)
    frame.Rotation=math.deg(math.atan2(dy,dx));frame.BackgroundColor3=color;frame.BackgroundTransparency=1-alpha
end
local corners={Vector3.new(-1,-1,-1),Vector3.new(1,-1,-1),Vector3.new(1,1,-1),Vector3.new(-1,1,-1),Vector3.new(-1,-1,1),Vector3.new(1,-1,1),Vector3.new(1,1,1),Vector3.new(-1,1,1)}
local edges={{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}
-- Only actual R6/R15 rig parts: tools and extra drone parts cannot pull the box away.
local bodyNames={'Head','Torso','Left Arm','Right Arm','Left Leg','Right Leg',
    'UpperTorso','LowerTorso','LeftUpperArm','LeftLowerArm','LeftHand',
    'RightUpperArm','RightLowerArm','RightHand','LeftUpperLeg','LeftLowerLeg',
    'LeftFoot','RightUpperLeg','RightLowerLeg','RightFoot'}
local function bodyBounds(character,root,rootCF)
    local low,high=-root.Size*0.5,root.Size*0.5
    for _,name in ipairs(bodyNames) do
        local part=character:FindFirstChild(name)
        if part and part:IsA('BasePart') then
            local cf=rootCF:ToObjectSpace(part:GetRenderCFrame())
            local center,half=cf.Position,part.Size*0.5
            local x,y,z=cf.RightVector,cf.UpVector,cf.LookVector
            local extent=Vector3.new(
                math.abs(x.X)*half.X+math.abs(y.X)*half.Y+math.abs(z.X)*half.Z,
                math.abs(x.Y)*half.X+math.abs(y.Y)*half.Y+math.abs(z.Y)*half.Z,
                math.abs(x.Z)*half.X+math.abs(y.Z)*half.Y+math.abs(z.Z)*half.Z)
            local a,b=center-extent,center+extent
            low=Vector3.new(math.min(low.X,a.X),math.min(low.Y,a.Y),math.min(low.Z,a.Z))
            high=Vector3.new(math.max(high.X,b.X),math.max(high.Y,b.Y),math.max(high.Z,b.Z))
        end
    end
    return (low+high)*0.5,(high-low)*0.5+Vector3.new(0.1,0.1,0.1)
end
local function nearClip(a,b)
    local z=-0.1
    if a.Z>z and b.Z>z then return nil end
    if a.Z>z then a=a:Lerp(b,(z-a.Z)/(b.Z-a.Z))
    elseif b.Z>z then b=b:Lerp(a,(z-b.Z)/(a.Z-b.Z)) end
    return a,b
end
local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Exclude;ray.IgnoreWater=true
local selected={}
local function refresh(camera)
    selected={}
    local own=me.Character and me.Character:FindFirstChild('HumanoidRootPart')
    local from=own and own.Position or camera.CFrame.Position
    for p,r in pairs(records) do
        r.root.Visible=false
        local char=p.Character;local hum=char and char:FindFirstChildOfClass('Humanoid')
        local root=char and char:FindFirstChild('HumanoidRootPart')
        local teammate=not me.Neutral and not p.Neutral and me.Team~=nil and me.Team==p.Team
        if root and root:IsA('BasePart') and hum and hum.Health>0 and not (cfg.teamFilter and teammate) then
            local distance=(root.Position-from).Magnitude*cfg.scale
            if distance<=cfg.maxDistance then
                r.player=p;r.character=char;r.part=root;r.humanoid=hum;r.distance=distance
                selected[#selected+1]=r
            end
        end
    end
    table.sort(selected,function(a,b) return a.distance<b.distance end)
    for i=#selected,cfg.maxPlayers+1,-1 do selected[i]=nil end
    for _,r in ipairs(selected) do
        r.drone,r.source=droneStatus(r.player,r.character)
        r.visible=true
        if cfg.visibility or cfg.visibleOnly then
            ray.FilterDescendantsInstances=me.Character and {me.Character} or {}
            local head=r.character:FindFirstChild('Head')
            local points={r.part.Position};if head and head:IsA('BasePart') then points[#points+1]=head.Position end
            r.visible=false
            for _,pos in ipairs(points) do
                local hit=Workspace:Raycast(camera.CFrame.Position,pos-camera.CFrame.Position,ray)
                if not hit or hit.Instance:IsDescendantOf(r.character) then r.visible=true;break end
            end
        end
    end
end
local function render(camera)
    local size=camera.ViewportSize
    for _,r in ipairs(selected) do
        local root=r.part
        r.root.Visible=cfg.enabled and root.Parent~=nil and r.player.Character==r.character and r.humanoid.Health>0 and (not cfg.visibleOnly or r.visible)
        if r.root.Visible then
            -- Read the interpolated pose once, after the camera has finished updating.
            local rootCF=root:GetRenderCFrame()
            r.offset,r.extent=bodyBounds(r.character,root,rootCF)
            r.root.Position=UDim2.fromOffset(0,0)
            -- Match viewport pixels explicitly, including devices with display cutouts.
            r.root.Size=UDim2.fromOffset(size.X,size.Y)
            local color=cfg.teamColor and not r.player.Neutral and r.player.TeamColor.Color or colors[cfg.color]
            local alpha=cfg.opacity*((cfg.visibility and not r.visible) and 0.4 or 1)
            local point,onScreen=camera:WorldToViewportPoint(rootCF.Position)
            local front=point.Z>0.1
            local inView=front and onScreen
            r.card.Visible=inView and (cfg.names or cfg.distance or cfg.status or cfg.health)
            r.arrow.Visible=cfg.arrows and not inView
            if r.arrow.Visible then
                local localPoint=camera.CFrame:PointToObjectSpace(rootCF.Position)
                local x,y,angle=edgePoint(localPoint.X,-localPoint.Y,size.X,size.Y)
                r.arrow.Position=UDim2.fromOffset(x,y);r.arrow.Rotation=angle;r.arrow.TextColor3=color;r.arrow.TextTransparency=1-alpha
            end
            if r.card.Visible then
                local top=camera:WorldToViewportPoint(rootCF:PointToWorldSpace(r.offset+Vector3.new(0,r.extent.Y+0.45,0)))
                local width=math.min(size.X,math.max(160,cfg.textSize*12))
                r.card.Size=UDim2.fromOffset(width,78)
                r.card.Position=UDim2.fromOffset(math.clamp(top.X,width/2,math.max(width/2,size.X-width/2)),math.clamp(top.Y,78,math.max(78,size.Y)))
                r.badge.Visible=cfg.status
                r.dot.BackgroundColor3=r.drone==true and red or r.drone==false and green or gray
                r.state.Text=r.drone==true and 'В РЕЖИМЕ ДРОНА' or r.drone==false and 'НЕ В РЕЖИМЕ ДРОНА' or 'НЕТ ДАННЫХ'
                r.state.TextColor3=r.dot.BackgroundColor3
                local lines={};if cfg.names then lines[#lines+1]=r.player.Name end
                if cfg.distance then lines[#lines+1]=string.format('%.0f м',r.distance) end
                r.label.Text=table.concat(lines,'\n');r.label.TextColor3=color;r.label.TextTransparency=1-alpha;r.label.TextSize=cfg.textSize;r.label.Font=fonts[cfg.font]
                r.healthBack.Visible=cfg.health
                local hp=math.clamp(r.humanoid.Health/math.max(1,r.humanoid.MaxHealth),0,1)
                r.health.Size=UDim2.fromScale(hp,1);r.health.BackgroundColor3=red:Lerp(green,hp)
            end
            r.tracer.Visible=false
            if cfg.tracers and inView then
                local y=cfg.origin==1 and size.Y-8 or cfg.origin==2 and size.Y/2 or 8
                drawLine(r.tracer,Vector2.new(size.X/2,y),Vector2.new(point.X,point.Y),color,alpha*0.65,size)
            end
            for _,edge in ipairs(r.edges) do edge.Visible=false end
            if cfg.boxes then
                local pts={}
                for i,sign in ipairs(corners) do pts[i]=camera.CFrame:PointToObjectSpace(rootCF:PointToWorldSpace(r.offset+sign*r.extent)) end
                for i,pair in ipairs(edges) do
                    local a,b=nearClip(pts[pair[1]],pts[pair[2]])
                    if a then
                        local pa=camera:WorldToViewportPoint(camera.CFrame:PointToWorldSpace(a))
                        local pb=camera:WorldToViewportPoint(camera.CFrame:PointToWorldSpace(b))
                        drawLine(r.edges[i],pa,pb,color,alpha,size)
                    end
                end
            end
        end
    end
end
local lastRefresh,lastSaveAttempt,lastError=-math.huge,0,0
RunService:BindToRenderStep(RENDER_KEY,Enum.RenderPriority.Last.Value,function()
    if not alive then return end
    local now=os.clock()
    if dirtyAt and now-dirtyAt>1 and now-lastSaveAttempt>5 then
        lastSaveAttempt=now;if save() then dirtyAt=nil end
    end
    if not cfg.enabled then for _,r in pairs(records) do r.root.Visible=false end;return end
    local camera=Workspace.CurrentCamera
    if not camera then for _,r in pairs(records) do r.root.Visible=false end;return end
    local ok,err=pcall(function()
        if now-lastRefresh>1/cfg.fps then refresh(camera);lastRefresh=now end
        render(camera)
    end)
    if not ok then
        for _,r in pairs(records) do r.root.Visible=false end
        summary.Text='Ошибка ESP: '..string.sub(tostring(err),1,110)
        if now-lastError>10 then lastError=now;warn('[Codex second ESP] '..tostring(err)) end
    end
end)
