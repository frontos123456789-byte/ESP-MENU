-- Read-only inventory of client-visible weapon objects. No require(), firing or remote calls.
local Players=game:GetService('Players')
local HttpService=game:GetService('HttpService')
local player=Players.LocalPlayer
local playerGui=player:WaitForChild('PlayerGui')
local old=playerGui:FindFirstChild('WeaponReportUI')
if old then old:Destroy() end
local gui=Instance.new('ScreenGui')
gui.Name='WeaponReportUI'
gui.ResetOnSpawn=false
gui.ScreenInsets=Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder=200
gui.Parent=playerGui
local alive=true
gui.Destroying:Connect(function() alive=false end)
local panel=Instance.new('Frame')
panel.AnchorPoint=Vector2.new(0.5,0.5)
panel.Position=UDim2.fromScale(0.5,0.5)
panel.Size=UDim2.new(1,-20,1,-20)
panel.BackgroundColor3=Color3.fromRGB(24,28,38)
panel.Parent=gui
local maxSize=Instance.new('UISizeConstraint',panel)
maxSize.MaxSize=Vector2.new(760,700)
local function button(text,x,y,w,parent)
 local b=Instance.new('TextButton')
 b.Text=text; b.TextSize=14; b.TextWrapped=true
 b.TextColor3=Color3.new(1,1,1); b.BackgroundColor3=Color3.fromRGB(45,52,70)
 b.Position=x; b.Size=UDim2.new(w,-6,0,40); b.Parent=parent or panel
 return b
end
local status=Instance.new('TextLabel')
status.Size=UDim2.new(1,-64,0,48)
status.Position=UDim2.fromOffset(8,0)
status.BackgroundTransparency=1;status.TextColor3=Color3.new(1,1,1)
status.TextSize=14;status.TextWrapped=true;status.Text='Сбор сведений об оружии…';status.Parent=panel
local close=button('×',UDim2.new(1,-48,0,4),0,0,panel)
close.Size=UDim2.fromOffset(40,40)
close.Activated:Connect(function()gui:Destroy()end)
local scroll=Instance.new('ScrollingFrame')
scroll.Position=UDim2.fromOffset(8,52)
scroll.Size=UDim2.new(1,-16,1,-154)
scroll.BackgroundColor3=Color3.fromRGB(16,19,27)
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
scroll.CanvasSize=UDim2.new();scroll.ScrollBarThickness=4;scroll.Parent=panel
local box=Instance.new('TextBox')
box.Size=UDim2.new(1,-10,0,20);box.AutomaticSize=Enum.AutomaticSize.Y
box.MultiLine=true;box.ClearTextOnFocus=false;box.TextEditable=false
box.TextWrapped=true;box.TextXAlignment=Enum.TextXAlignment.Left;box.TextYAlignment=Enum.TextYAlignment.Top
box.TextSize=12;box.Font=Enum.Font.Code;box.BackgroundTransparency=1
box.TextColor3=Color3.fromRGB(225,230,240);box.Text='Подожди…';box.Parent=scroll
local prev=button('←',UDim2.new(0,8,1,-96),0,0.25)
local nextPage=button('→',UDim2.new(0.25,6,1,-96),0,0.25)
local copy=button('Копировать всё',UDim2.new(0.5,4,1,-96),0,0.5)
local save=button('Сохранить файл',UDim2.new(0,8,1,-48),0,0.5)
local rescan=button('Повторить сбор',UDim2.new(0.5,4,1,-48),0,0.5)
local reportText,pages,page,busy=nil,{},1,false
local function showPage()
 box.Text=pages[page] or 'Отчёт ещё не готов'
 scroll.CanvasPosition=Vector2.new(0,0)
end
prev.Activated:Connect(function()page=math.max(1,page-1);showPage()end)
nextPage.Activated:Connect(function()page=math.min(math.max(1,#pages),page+1);showPage()end)
copy.Activated:Connect(function()
 if not reportText then return end
 local copier=type(setclipboard)=='function' and setclipboard or (type(toclipboard)=='function' and toclipboard)
 if copier and pcall(copier,reportText) then status.Text='Полный JSON-отчёт скопирован'
 else box.TextEditable=true;status.Text='Буфер недоступен. Выдели текст страницы или сохрани файл.' end
end)
save.Activated:Connect(function()
 if not reportText then return end
 local filename='weapon_report_'..tostring(game.PlaceId)..'.json'
 if type(writefile)=='function' and pcall(writefile,filename,reportText) then status.Text='Сохранён файл: '..filename
 else status.Text='Инжектор не предоставляет запись файлов. Нажми «Копировать всё».' end
end)
local keywords={'weapon','gun','rifle','pistol','shotgun','bullet','ballistic','ammo','projectile','firearm','sniper','carbine','оруж','Оруж','автомат','Автомат','патрон','Патрон'}
local function relevant(name)
 name=string.lower(name)
 for _,word in ipairs(keywords) do if string.find(name,word,1,true) then return true end end
 return false
end
local function safeValue(value)
 local kind=typeof(value)
 if kind=='number' then return (value==value and math.abs(value)<math.huge) and value or tostring(value) end
 if kind=='boolean' then return value end
 if kind=='string' then return #value>512 and value:sub(1,512)..' [truncated]' or value end
 if kind=='Instance' then return value:GetFullName() end
 return tostring(value)
end
local function attributes(object)
 local result={}
 for key,value in pairs(object:GetAttributes()) do result[key]=safeValue(value) end
 return result
end
local function collect(object)
 local entry={name=object.Name,class=object.ClassName,path=object:GetFullName(),attributes=attributes(object),details={}}
 local stack={object};local count=0
 while #stack>0 and count<500 and alive do
  local node=table.remove(stack);count=count+1
  local detail={path=node:GetFullName(),class=node.ClassName,attributes=attributes(node)}
  local keep=next(detail.attributes)~=nil
  if node:IsA('ValueBase') then
   local ok,value=pcall(function()return node.Value end)
   if ok then detail.value=safeValue(value);keep=true end
  end
  if node:IsA('ModuleScript') then
   keep=true;detail.source='unavailable; module was not executed'
   local ok,source=pcall(function()return node.Source end)
   if ok and type(source)=='string' and #source>0 then
    detail.source='readable; literal numbers only; expressions not evaluated'
    detail.numericLiterals={}
    local n=0
    for key,value in source:gmatch('([%a_][%w_]*)%s*=%s*([+-]?%d+%.?%d*)%s*[,;\n}]') do
     local number=tonumber(value)
     if number then detail.numericLiterals[key]=number;n=n+1 end
     if n>=128 then detail.literalsTruncated=true;break end
    end
   end
  end
  if node:IsA('Attachment') and (node.Name:lower():find('muzzle',1,true) or node.Name:lower():find('fire',1,true)) then
   detail.position=tostring(node.Position);keep=true
  end
  if keep then table.insert(entry.details,detail) end
  for _,child in ipairs(node:GetChildren()) do table.insert(stack,child) end
  if count%100==0 then task.wait() end
 end
 entry.detailsTruncated=#stack>0
 return entry
end
local function scan()
 if busy then return end
 busy=true;reportText=nil;pages={};page=1;box.Text='Сбор доступных клиенту данных…'
 task.spawn(function()
  local ok,err=pcall(function()
   local roots={game:GetService('ReplicatedStorage'),game:GetService('ReplicatedFirst'),game:GetService('StarterPack'),game:GetService('StarterPlayer'),workspace}
   local backpack=player:FindFirstChildOfClass('Backpack')
   if backpack then table.insert(roots,backpack) end
   local report={schema=1,placeId=game.PlaceId,universeId=game.GameId,generatedAt=os.date('!%Y-%m-%dT%H:%M:%SZ'),
    scope='Client-visible candidates only. Not a complete server inventory. No modules executed.',
    units='Numbers are reported as stored. Units and live runtime behavior are not inferred.',
    weapons={},configs={},scannedNodes=0,truncated=false,errors={}}
   local stack={};for _,root in ipairs(roots) do table.insert(stack,{node=root,inWeapon=false}) end
   local seen={};local records=0
   while #stack>0 and alive do
    if report.scannedNodes>=50000 or records>=300 then report.truncated=true;break end
    local item=table.remove(stack);local node=item.node
    if not seen[node] then
     seen[node]=true;report.scannedNodes=report.scannedNodes+1
     local isTool=node:IsA('Tool')
     local named=relevant(node.Name)
     local candidate=isTool or (not item.inWeapon and named and (node:IsA('Model') or node:IsA('Folder') or node:IsA('Configuration') or node:IsA('ModuleScript')))
     if candidate then
      local success,entry=pcall(collect,node)
      if success then
       table.insert(isTool and report.weapons or report.configs,entry);records=records+1
      else table.insert(report.errors,tostring(entry):sub(1,300)) end
     end
     for _,child in ipairs(node:GetChildren()) do table.insert(stack,{node=child,inWeapon=item.inWeapon or isTool}) end
     if report.scannedNodes%200==0 then
      status.Text='Просмотрено: '..report.scannedNodes..' • записей: '..records
      task.wait()
     end
    end
   end
   if not alive then return end
   reportText=HttpService:JSONEncode(report)
   -- Split at UTF-8 character boundaries; export always contains the whole report.
   local start,count=1,0
   for offset in utf8.codes(reportText) do
    count=count+1
    if count>5000 then table.insert(pages,reportText:sub(start,offset-1));start=offset;count=1 end
   end
   table.insert(pages,reportText:sub(start))
   showPage()
   status.Text='Готово: Tool '..#report.weapons..' • конфигов/кандидатов '..#report.configs..' • страниц '..#pages..(report.truncated and ' • достигнут лимит' or '')
  end)
  busy=false
  if not ok and alive then status.Text='Ошибка сбора: '..tostring(err):sub(1,180) end
 end)
end
rescan.Activated:Connect(scan)
scan()
