-- Targeted read-only weapon report; optional decompilation of one script per explicit tap.
local player=game:GetService('Players').LocalPlayer
local parent=player:WaitForChild('PlayerGui')
for _,name in ipairs({'WeaponReportUI','WeaponReportV2UI','WeaponReportLiteUI','WeaponReportSurgicalUI','WeaponCodeExactUI'}) do
 local old=parent:FindFirstChild(name)
 if old then old:Destroy() end
end
local gui=Instance.new('ScreenGui')
gui.Name='WeaponCodeExactUI';gui.ResetOnSpawn=false
gui.ScreenInsets=Enum.ScreenInsets.DeviceSafeInsets;gui.DisplayOrder=210;gui.Parent=parent
local alive=true
gui.Destroying:Connect(function()alive=false end)
local panel=Instance.new('Frame')
panel.Position=UDim2.fromOffset(8,8);panel.Size=UDim2.new(1,-16,1,-16)
panel.BackgroundColor3=Color3.fromRGB(24,28,38);panel.Parent=gui
local title=Instance.new('TextLabel')
title.Position=UDim2.fromOffset(8,4);title.Size=UDim2.new(1,-64,0,44)
title.BackgroundTransparency=1;title.TextColor3=Color3.new(1,1,1)
title.TextWrapped=true;title.TextSize=15;title.Text='Короткий отчёт • сбор…';title.Parent=panel
local function button(text,pos,size)
 local b=Instance.new('TextButton');b.Text=text;b.Position=pos;b.Size=size
 b.TextColor3=Color3.new(1,1,1);b.TextSize=14;b.TextWrapped=true
 b.BackgroundColor3=Color3.fromRGB(45,52,70);b.Parent=panel
 return b
end
button('×',UDim2.new(1,-48,0,4),UDim2.fromOffset(40,40)).Activated:Connect(function()gui:Destroy()end)
local scroll=Instance.new('ScrollingFrame')
scroll.Position=UDim2.fromOffset(8,52);scroll.Size=UDim2.new(1,-16,1,-162)
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.CanvasSize=UDim2.new()
scroll.ScrollBarThickness=3;scroll.BackgroundColor3=Color3.fromRGB(16,19,27);scroll.Parent=panel
local text=Instance.new('TextLabel')
text.Size=UDim2.new(1,-10,0,0);text.AutomaticSize=Enum.AutomaticSize.Y
text.BackgroundTransparency=1;text.TextColor3=Color3.fromRGB(230,233,240)
text.TextSize=15;text.TextWrapped=true;text.Font=Enum.Font.Code
text.TextXAlignment=Enum.TextXAlignment.Left;text.TextYAlignment=Enum.TextYAlignment.Top
text.Text='Подожди…';text.Parent=scroll
local prev=button('←',UDim2.new(0,8,1,-52),UDim2.new(0.2,-6,0,44))
local nextButton=button('→',UDim2.new(0.2,6,1,-52),UDim2.new(0.2,-6,0,44))
local copy=button('Копировать страницу',UDim2.new(0.4,4,1,-52),UDim2.new(0.6,-12,0,44))
local pages,page={},1
local documentName='Инструкция'
local documentId='-'
local busy=false
local function show()
 title.Text=documentName..' • '..page..' / '..#pages
 text.Text=pages[page] or 'Сбор…';scroll.CanvasPosition=Vector2.new()
end
prev.Activated:Connect(function()if #pages>0 then page=math.max(1,page-1);show()end end)
nextButton.Activated:Connect(function()if #pages>0 then page=math.min(#pages,page+1);show()end end)
copy.Activated:Connect(function()
 if busy or not pages[page] then return end
 local copier=type(setclipboard)=='function' and setclipboard or (type(toclipboard)=='function' and toclipboard)
 local chunk='CODE '..documentName..' '..documentId..' '..page..'/'..#pages..'\n'..pages[page]
 if copier and pcall(copier,chunk) then title.Text='Скопирована только страница '..page..' / '..#pages
 else title.Text='Буфер недоступен — сделай скриншот этой страницы' end
end)
-- Two explicit targets only. Never require modules, invoke remotes or execute recovered code.
local bulletButton=button('1. BulletShoot',UDim2.new(0,8,1,-102),UDim2.new(0.5,-8,0,44))
local shootButton=button('2. AV-47 / Shoot',UDim2.new(0.5,4,1,-102),UDim2.new(0.5,-12,0,44))
local cache={}
local function splitSource(source)
 local chunks={};local start,count=1,0
 for offset in utf8.codes(source) do
  count=count+1
  if count>700 then
   table.insert(chunks,source:sub(start,offset-1));start=offset;count=1
  end
 end
 table.insert(chunks,source:sub(start))
 return chunks
end
local function checksum(source)
 local a,b=1,0
 for i=1,#source do a=(a+source:byte(i))%65521;b=(b+a)%65521 end
 return string.format('%08x',b*65536+a)
end
local function target(name)
 if name=='BulletShoot' then
  local modules=game:GetService('ReplicatedStorage'):FindFirstChild('Modules')
  local weapons=modules and modules:FindFirstChild('Weapons')
  return weapons and weapons:FindFirstChild('BulletShoot'),'ReplicatedStorage.Modules.Weapons.BulletShoot не найден'
 end
 local character=player.Character
 local backpack=player:FindFirstChildOfClass('Backpack')
 local weapon=character and character:FindFirstChild('AV-47')
 if not weapon and backpack then weapon=backpack:FindFirstChild('AV-47') end
 if not weapon or not weapon:IsA('Tool') then return nil,'AV-47 не найден. Возьми AV-47 и нажми кнопку ещё раз.' end
 local scripts=weapon:FindFirstChild('Scripts')
 local shoot=scripts and scripts:FindFirstChild('Shoot')
 if not shoot then shoot=weapon:FindFirstChild('Shoot',true) end
 return shoot,'Shoot внутри AV-47 не найден'
end
local function read(name)
 if busy then return end
 if cache[name] then
  documentName=name;pages=cache[name].pages;documentId=cache[name].id;page=1;show();return
 end
 busy=true;documentName=name;documentId='-';pages={};page=1
 title.Text='Чтение '..name..'…';text.Text='Один скрипт. Остальные объекты игры не сканируются.'
 task.spawn(function()
  local ok,errorMessage=pcall(function()
   local node,reason=target(name)
   if not node then error(reason,0) end
   if not (node:IsA('LocalScript') or node:IsA('ModuleScript')) then
    error('Это не клиентский LocalScript/ModuleScript; серверный код недоступен.',0)
   end
   local valid,source=pcall(function()return node.Source end)
   local method='Source'
   if not valid or type(source)~='string' or #source==0 then
    if type(decompile)~='function' then error('Delta не предоставляет decompile; исходник недоступен.',0) end
    method='decompile (может содержать неточности)'
    source=nil
    local done=false
    local worker=task.spawn(function()
     local success,result=pcall(decompile,node)
     if success and type(result)=='string' then source=result end
     done=true
    end)
    local deadline=os.clock()+4
    while alive and not done and os.clock()<deadline do task.wait() end
    if not done then pcall(task.cancel,worker);error('Чтение превысило 4 секунды. Можно повторить отдельно.',0) end
    if not source or #source==0 then error('Декомпилятор не вернул код.',0) end
   end
   if not alive then return end
   if #source>131072 then error('Скрипт больше 128 КБ: остановлено для защиты памяти; код не обрезан и не выдан.',0) end
   if not utf8.len(source) then error('Код содержит некорректный UTF-8; копирование отменено.',0) end
   local id=checksum(source)
   local header='-- DOCUMENT: '..name..'\n-- METHOD: '..method..'\n-- SOURCE_BYTES: '..#source..'\n-- SOURCE_ADLER32: '..id..'\n'
   pages=splitSource(header..source);documentId=id
   cache[name]={pages=pages,id=id}
  end)
  if not alive then return end
  busy=false
  if not ok then
   pages={'Не удалось прочитать '..name..':\n'..tostring(errorMessage)}
   documentId='ERROR'
  end
  show()
 end)
end
bulletButton.Activated:Connect(function()read('BulletShoot')end)
shootButton.Activated:Connect(function()read('AV47-Shoot')end)
pages={'Возьми AV-47 в руки.\n\n1. Нажми «1. BulletShoot».\n2. Скопируй его страницы по очереди.\n3. Нажми «2. AV-47 / Shoot» и скопируй его страницы.\n\nКод не обрезается: длинные строки продолжаются на следующей странице. Кнопки документов сохраняют уже прочитанный результат. Нет кнопки копирования всего большого текста.'}
show()
