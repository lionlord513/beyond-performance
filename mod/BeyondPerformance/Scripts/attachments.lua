-- Semantic guard and lifetime manager for the verified pure-lookup optimization.
-- No ticks, actor state, collisions, replication, saves, or other mods are patched.
return function(M)
 local A={enabled=false,applied=false,message='Waiting for attachment classes.',checked=0}
 local root=M.root:gsub('\\','/'):gsub('/$','')
 local target='/Game/BP/CarsV2/System/Actors/Master/CarItemEquipableActor.CarItemEquipableActor_C:Get Vehicle'
 local spec=dofile(root..'/Scripts/attachment_symbols.lua')
 local native={}
 local function loadNative()
  if native.apply then return true end
  for key,entry in pairs({apply='bp_attachment_apply',restore='bp_attachment_restore',status='bp_attachment_status'})do
   local fn,err=package.loadlib(root..'/native/BeyondPerformanceNative.dll',entry)
   if not fn then A.message='Native attachment helper unavailable: '..tostring(err);return false end
   native[key]=fn
  end
  native.status() -- Creates our private state directory; does not mutate game state.
  return true
 end
 local function result()
  local f=io.open(root..'/state/attachment-status.txt','r')
  if not f then A.message='Native attachment result unavailable.';A.applied=false;return false,A.message end
  local code=f:read('*l');local message=f:read('*l')or code;f:close()
  A.applied=code=='ON';A.message=message or 'Attachment result unavailable.';A.code=code
  return A.applied,A.message
 end
 local function resolve(item)
  if item.symbol=='@0'then return 0 end
  if not item.property then
   local object=StaticFindObject(item.symbol)
   if not M.valid(object)then return nil end
   return object:GetAddress()
  end
  local owner,name=item.symbol:match('^(.*):([^:]+)$')
  local object=owner and StaticFindObject(owner)
  if not M.valid(object)then return nil end
  local address
  object:ForEachProperty(function(p)if p:GetFName():ToString()==name then address=p:GetAddress()end end)
  return address
 end
 local function enableNow()
  local fn=StaticFindObject(target)
  if not M.valid(fn)then A.code='WAIT';A.message='Waiting for native attachment classes.';return false,A.message end
  if not loadNative()then A.code='ERROR';return false,A.message end
  local lines={'BP_ATTACH_1',string.format('%d',fn:GetAddress())}
  for _,item in ipairs(spec)do
   local ok,address=pcall(resolve,item)
   if not ok or address==nil then A.code='UNSUPPORTED';A.message='Attachment signature unavailable; game code unchanged.';return false,A.message end
   lines[#lines+1]=string.format('%d',address)
  end
  local f,err=io.open(root..'/state/attachment-request.txt','w')
  if not f then A.code='ERROR';A.message='Cannot write attachment request: '..tostring(err);return false,A.message end
  f:write(table.concat(lines,'\n'),'\n');f:close()
  native.apply();return result()
 end
 function A.apply(enabled)
  A.enabled=enabled==true;A.checked=0
  if A.enabled then return enableNow()end
  if not native.restore then A.applied=false;A.message='Original attachment lookup active.';return true,A.message end
  native.restore();result();return A.code=='OFF',A.message
 end
 function A.tick()
  A.checked=A.checked+1
  if A.enabled and A.code=='WAIT'then enableNow()
  elseif A.applied and A.checked%5==0 then native.status();result()end
 end
 function A.shutdown()
  -- Called before map unload while the reflected function is still valid.
  if native.restore then native.restore();result()end
  A.applied=false;A.code='WAIT';A.message='Waiting for attachment classes.';A.checked=0
 end
 function A.status()return A.message end
 return A
end
