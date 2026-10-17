-- Small read-only report for phones: no decompiler, full source dumps or file exports.
local player=game:GetService('Players').LocalPlayer
local parent=player:WaitForChild('PlayerGui')
for _,name in ipairs({'WeaponReportUI','WeaponReportV2UI','WeaponReportLiteUI'}) do
 local old=parent:FindFirstChild(name)
 if old then old:Destroy() end
end
local gui=Instance.new('ScreenGui')
gui.Name='WeaponReportLiteUI';gui.ResetOnSpawn=false
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
scroll.Position=UDim2.fromOffset(8,52);scroll.Size=UDim2.new(1,-16,1,-112)
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
local function show()
 title.Text='Отчёт • страница '..page..' / '..#pages
 text.Text=pages[page] or 'Сбор…';scroll.CanvasPosition=Vector2.new()
end
prev.Activated:Connect(function()if #pages>0 then page=math.max(1,page-1);show()end end)
nextButton.Activated:Connect(function()if #pages>0 then page=math.min(#pages,page+1);show()end end)
copy.Activated:Connect(function()
 if not pages[page] then return end
 local copier=type(setclipboard)=='function' and setclipboard or (type(toclipboard)=='function' and toclipboard)
 local chunk='WEAPON LITE '..page..'/'..#pages..'\n'..pages[page]
 if copier and pcall(copier,chunk) then title.Text='Скопирована только страница '..page..' / '..#pages
 else title.Text='Буфер недоступен — сделай скриншот этой страницы' end
end)
local terms={'bullet','speed','gravity','velocity','drop','drag','ballistic','firerate','fire rate','range','spread','recoil','projectile','acceleration','hitscan'}
local function relevant(name)
 name=name:lower()
 for _,word in ipairs(terms) do if name:find(word,1,true) then return true end end
 return false
end
local function clip(value,limit)
 local s=tostring(value)
 local ok,pos=pcall(utf8.offset,s,limit+1)
 if not ok then return '[non-text]' end
 return pos and s:sub(1,pos-1)..'…' or s
end
local function pack(lines,maxChars)
 local result,current={},''
 for _,line in ipairs(lines) do
  local candidate=current=='' and line or current..'\n'..line
  if utf8.len(candidate)>maxChars and current~='' then table.insert(result,current);current=line
  else current=candidate end
 end
 if current~='' then table.insert(result,current) end
 return result
end
task.spawn(function()
 local lines={'Place '..game.PlaceId,'Числа в исходных единицах игры.',
  'World.Gravity = '..tostring(workspace.Gravity)..' (не обязательно падение пули)'}
 local total,limited,scriptCount,readable=0,false,0,0
 local function add(line)
  if #lines>=65 then limited=true;return end
  table.insert(lines,clip(line,160))
 end
 local roots={}
 local function root(node,label)if node then table.insert(roots,{node=node,label=label})end end
 root(player:FindFirstChildOfClass('Backpack'),'Рюкзак')
 root(player.Character,'В руках')
 root(game:GetService('ReplicatedStorage'),'ReplicatedStorage')
 root(player:FindFirstChild('PlayerScripts'),'PlayerScripts')
 root(game:GetService('ReplicatedFirst'),'ReplicatedFirst')
 root(game:GetService('StarterPack'),'StarterPack')
 local seen={}
 local ok,err=pcall(function()
  for _,r in ipairs(roots) do
   if not alive then return end
   local queue={{node=r.node,tool=nil,depth=0}};local index,count=1,0
   while index<=#queue and count<3000 and alive do
    local item=queue[index];queue[index]=false;index=index+1
    local node=item.node
    if not seen[node] then
     seen[node]=true;count=count+1;total=total+1
     local tool=item.tool
     if node:IsA('Tool') then tool=node.Name;add('['..r.label..'] Оружие: '..clip(tool,50)) end
     local label=(tool and tool..'/' or r.label..'/')..clip(node.Parent and node.Parent.Name or '',40)..'/'..clip(node.Name,50)
     if node:IsA('ValueBase') and relevant(node.Name) then
      local valid,value=pcall(function()return node.Value end)
      if valid and (typeof(value)=='number' or typeof(value)=='boolean' or typeof(value)=='string') then add(label..' = '..clip(value,50)) end
     end
     for key,value in pairs(node:GetAttributes()) do
      if relevant(key) then add(label..' @'..clip(key,35)..' = '..clip(value,40)) end
     end
     if node:IsA('LocalScript') or node:IsA('ModuleScript') then
      scriptCount=scriptCount+1
      local valid,source=pcall(function()return node.Source end)
      if valid and type(source)=='string' and #source>0 then
       readable=readable+1
       if #source<=64000 then
        local hits=0
        for line in (source..'\n'):gmatch('(.-)\n') do
         if relevant(line) then add(label..': '..clip(line,100));hits=hits+1 end
         if hits>=4 then break end
        end
       else limited=true end
      end
     end
     if item.depth<20 then
      -- Limit the frontier as well as visited nodes to bound memory on large folders.
      for _,child in ipairs(node:GetChildren()) do
       if #queue>=3000 then limited=true;break end
       table.insert(queue,{node=child,tool=tool,depth=item.depth+1})
      end
     elseif #node:GetChildren()>0 then limited=true end
     if count%75==0 then title.Text='Сбор: '..r.label..' • '..total;task.wait() end
    end
   end
   if index<=#queue then limited=true end
  end
 end)
 if not alive then return end
 table.insert(lines,'Просмотрено '..total..'; скриптов '..scriptCount..', читаемых '..readable)
 table.insert(lines,limited and 'Отчёт ограничен для телефона.' or 'Обход выбранных разделов завершён.')
 if not ok then table.insert(lines,'Ошибка: '..clip(err,120)) end
 pages=pack(lines,800);show()
end)
