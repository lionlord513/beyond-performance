-- Run through tests/run.py. Isolated mocks never load inside the game.
assert(scriptdir and testpath, 'Use tests/run.py')

do
    local S = assert(loadfile(scriptdir .. '/settings.lua'))()
    local defaults = {foo = true, bar = false, count = 10, mode = 'balanced', frame_smoothing = false}
    local schema = {count = {min = 1, max = 60, integer = true}, mode = {values = {'balanced', 'fast'}}}
    local values, notes = S.parse('foo=off\nbar=1\ncount=61\nmode=unknown\nignored=42\nbroken\n', defaults, schema)
    assert(not values.foo and values.bar and values.count == 10 and values.mode == 'balanced')
    assert(values.ignored == nil and #notes == 3)
    assert(values.frame_smoothing == false)
    local duplicate = S.parse('count=30\ncount=nan\nfoo=TRUE\nbar=0\nmode=fast', defaults, schema)
    assert(duplicate.count == 30 and duplicate.foo and not duplicate.bar and duplicate.mode == 'fast')
    assert(S.parse(string.rep('a', 65537), defaults, schema).foo)
    local decoded = S.parse(assert(S.encode(duplicate, defaults, schema)), defaults, schema)
    for key, value in pairs(duplicate) do assert(decoded[key] == value) end
    assert(S.save(testpath, duplicate, defaults, schema))
    duplicate.foo, duplicate.count = false, 44
    assert(S.save(testpath, duplicate, defaults, schema))
    local loaded = S.load(testpath, defaults, schema)
    assert(not loaded.foo and loaded.count == 44)
    loaded.frame_smoothing = true
    assert(S.save(testpath, loaded, defaults, schema))
    assert(S.load(testpath, defaults, schema).frame_smoothing == true)
    duplicate.count = 61
    assert(S.save(testpath, duplicate, defaults, schema) == false)
    assert(S.load(testpath, defaults, schema).count == 44)
    assert(os.rename(testpath, testpath .. '.bak'))
    local recovered, recoveryNotes = S.load(testpath, defaults, schema)
    assert(recovered.count == 44 and #recoveryNotes == 1)
    assert(S.save(testpath, recovered, defaults, schema))
    assert(io.open(testpath .. '.bak', 'rb') == nil)
    os.remove(testpath)
    print('PASS settings: types/ranges, malformed and unknown values, round trip, replacement, rejected-save retention, interrupted-save recovery')
end

do
    local B = assert(loadfile(scriptdir .. '/benchmark.lua'))()({})
    local samples = {}
    for i = 1, 100 do samples[i] = i / 1000 end
    local metrics = B.summarize(samples)
    assert(metrics.samples == 100 and math.abs(metrics.averageFPS - 100 / 5.05) < 1e-8)
    assert(math.abs(metrics.medianMs - 50.5) < 1e-8 and metrics.p95Ms == 95 and metrics.p99Ms == 99)
    assert(metrics.onePercentLowFPS == 10 and metrics.onePercentFrames == 1)
    assert(metrics.over33ms == 67 and metrics.over50ms == 50)
    assert(samples[1] == .001 and samples[100] == .1)
    local hitch = B.summarize({.01, .02, 2})
    assert(hitch.samples == 3 and hitch.maxMs == 2000 and hitch.p95Ms == 2000 and hitch.p99Ms == 2000)
    assert(hitch.onePercentLowFPS == .5 and hitch.medianMs == 20 and hitch.over50ms == 1)
    local zeros = B.summarize({0, 0})
    assert(zeros.averageFPS == nil and zeros.onePercentLowFPS == nil and zeros.samples == 2)
    assert(B.summarize({}).samples == 0)
    print('PASS frame statistics: mean FPS, median, nearest-rank percentiles, defined 1% low, two-second hitch, zero/empty data')
end

do
    local address, mode, bindings = 0, 'game', {}
    local function object()
        address = address + 1
        local o = {id = address, Font = {Size = 12}, children = {}}
        function o:IsValid() return not self.invalid end
        function o:GetAddress() return self.id end
        function o:SetPosition(v) self.position = v end
        function o:SetSize(v) self.size = v end
        function o:SetVisibility(v) self.visibility = v end
        function o:SetColorAndOpacity(v) self.color = v end
        function o:SetText(v) self.text = v end
        function o:SetFont(v) self.Font = v end
        function o:SetAutoWrapText(v) self.wrap = v end
        function o:AddToViewport(v) self.z = v end
        function o:RemoveFromParent() self.removed = true end
        function o:AddChildToCanvas(v) table.insert(self.children, v); return object() end
        function o:ClearChildren() self.children = {} end
        return o
    end
    local lib, layout = object(), object()
    function lib:Create() return object() end
    function lib:SetInputMode_UIOnlyEx() mode = 'ui' end
    function lib:SetInputMode_GameOnly() mode = 'game' end
    function layout:GetViewportSize() return {X = 1280, Y = 720} end
    function layout:GetViewportScale() return 1 end
    function StaticFindObject(path)
        if path:find('Default__WidgetBlueprintLibrary', 1, true) then return lib end
        if path:find('Default__WidgetLayoutLibrary', 1, true) then return layout end
        return object()
    end
    function StaticConstructObject() return object() end
    function FText(text) return text end
    function ExecuteInGameThread(callback) callback() end
    Key = {UP_ARROW = 1, DOWN_ARROW = 2, RETURN = 3, ESCAPE = 4}
    function RegisterKeyBind(key, callback) bindings[key] = callback end
    local pc, human = object(), object()
    pc.bShowMouseCursor, pc.look, pc.move = false, 2, 3
    pc.HUD = {ChatUI = {TypeInChat = false}}
    human.IsLoaded, human.BP_PlayerStats = true, {IsDead = false}
    pc.PlayerControlled = human
    function pc:SetIgnoreLookInput(v) self.look = self.look + (v and 1 or -1) end
    function pc:SetIgnoreMoveInput(v) self.move = self.move + (v and 1 or -1) end
    local M = {
        valid = function(o) return o ~= nil and o:IsValid() end,
        getPC = function() return pc end,
        log = function() end,
        options = {{key = 'test', label = 'Test option', description = 'A performance option.'}},
        settings = {test = false}, getStatus = function() return 'Ready' end,
        resetDefaults = function() return true end, startBenchmark = function() return 'Recording' end,
    }
    M.setOption = function(key, value) M.settings[key] = value; return true, 'saved' end
    local U = assert(loadfile(scriptdir .. '/ui.lua'))()(M)
    assert(#bindings == 4 and U.open())
    assert(mode == 'ui' and pc.look == 3 and pc.move == 4 and not pc.bShowMouseCursor)
    bindings[3](); assert(M.settings.test)
    bindings[1](); assert(U.selected == 3)
    bindings[2](); assert(U.selected == 1)
    U.tick(); U.close()
    assert(mode == 'game' and pc.look == 2 and pc.move == 3)
    pc.bShowMouseCursor = true; assert(U.open() == false); pc.bShowMouseCursor = false
    assert(U.open()); mode = 'foreign'; pc.bShowMouseCursor = true; U.tick()
    assert(not U.opened and mode == 'foreign' and pc.look == 2 and pc.move == 3)
    pc.bShowMouseCursor = false; assert(U.open()); human.invalid = true; U.tick()
    assert(not U.opened and mode == 'game' and pc.look == 2 and pc.move == 3)
    print('PASS menu: four navigation bindings, toggle/wrap, balanced input state, busy-menu refusal, foreign-overlay ownership, invalid-player cleanup')
end

do
    -- Exercise cleanup and partial-default failures in the actual integration
    -- module, replacing engine-facing modules with explicit faulting doubles.
    local calls, saved, preTravel, cancelled = {}, nil, nil, false
    local function record(key, value) calls[key] = value == nil and true or value end
    local storage = {
        load = function(_, defaults) local t = {}; for k, v in pairs(defaults) do t[k] = v end; return t end,
        save = function(_, values) saved = {}; for k, v in pairs(values) do saved[k] = v end; return true end,
    }
    local render = {
        apply = function(key, value) record('apply.' .. key, value); return true end,
        reset = function() record('render.reset') end, tick = function() end,
        status = function() return '' end, optionState = function() end,
    }
    local attachments = {
        apply = function() return false, 'Unsupported test build' end,
        shutdown = function() record('attachments.shutdown') end,
        status = function() return 'Unavailable' end, tick = function() end,
    }
    local benchmark = {start = function() end, status = function() return '' end,
        stop = function() error('Injected benchmark finalization failure') end}
    local ui = {close = function(ownershipLost) record('ui.close', ownershipLost) end, tick = function() end}
    local env = setmetatable({
        _G = {}, Key = {F10 = 121}, print = function() end,
        StaticFindObject = function() return {} end,
        RegisterLoadMapPreHook = function(callback) preTravel = callback end,
        RegisterLoadMapPostHook = function() end, RegisterKeyBind = function() end,
        LoopInGameThreadWithDelay = function() return 42 end,
        CancelDelayedAction = function() cancelled = true end,
        dofile = function(path)
            if path:match('/settings.lua$') then return storage end
            if path:match('/render.lua$') then return function() return render end end
            if path:match('/attachments.lua$') then return function() return attachments end end
            if path:match('/benchmark.lua$') then return function() return benchmark end end
            if path:match('/ui.lua$') then return function() return ui end end
            error('Unexpected module: ' .. path)
        end,
    }, {__index = _G})
    local M = assert(loadfile(scriptdir .. '/main.lua', 't', env))()
    M.settings.raw_mouse, M.settings.clouds = false, true
    local ok, message = M.resetDefaults()
    assert(not ok and message:find('Unavailable', 1, true))
    assert(saved.raw_mouse == true and saved.clouds == false)
    assert(calls['apply.frame_cap'] == false) -- Reached final option after attachment failure.
    preTravel()
    assert(calls['ui.close'] == true and calls['render.reset'] and calls['attachments.shutdown'])
    M.shutdown()
    assert(calls['ui.close'] == false and cancelled)
    print('PASS integration failures: partial defaults persist successful preferences, benchmark failure cannot block cleanup, travel/shutdown preserve input ownership')
end

do
    local consoleCalls = 0
    local engine = {bSmoothFrameRate = true, bUseFixedFrameRate = false, FixedFrameRate = 30}
    function engine:IsValid() return not self.invalid end
    local variables = {['t.MaxFPS'] = 45, ['r.VSync'] = 1}
    local system = {
        IsValid = function() return true end,
        GetConsoleVariableFloatValue = function(_, name) return variables[name] or 0 end,
        ExecuteConsoleCommand = function() consoleCalls = consoleCalls + 1; error('Unexpected CVar write') end,
    }
    local env = setmetatable({
        StaticFindObject = function() return system end,
        FindFirstOf = function(name) assert(name == 'GameEngine'); return engine end,
    }, {__index = _G})
    local R = assert(loadfile(scriptdir .. '/render.lua', 't', env))()({valid = function(o) return o and o:IsValid() end})
    assert(R.apply('frame_smoothing', true) and engine.bSmoothFrameRate == false)
    assert(R.apply('frame_smoothing', false) and engine.bSmoothFrameRate == true)
    engine.bSmoothFrameRate = false
    assert(R.apply('frame_smoothing', true))
    R.restore('frame_smoothing'); assert(engine.bSmoothFrameRate == false)
    engine.bSmoothFrameRate = true
    assert(R.apply('frame_smoothing', true))
    engine.bSmoothFrameRate = true -- External owner changed the flag.
    R.tick()
    assert(R.engineSmoothing == nil and R.yielded.frame_smoothing and engine.bSmoothFrameRate == true)
    R.restore('frame_smoothing'); assert(engine.bSmoothFrameRate == true)
    assert(R.apply('frame_smoothing', true)); engine.invalid = true; R.tick()
    assert(R.engineSmoothing == nil and R.apply('frame_smoothing', true) == false)
    engine.invalid, engine.bSmoothFrameRate = false, true
    assert(R.apply('frame_smoothing', true)); R.reset(); assert(engine.bSmoothFrameRate == true)
    assert(consoleCalls == 0 and variables['t.MaxFPS'] == 45 and variables['r.VSync'] == 1)
    assert(engine.bUseFixedFrameRate == false and engine.FixedFrameRate == 30)
    print('PASS engine frame smoothing: snapshot/restore, original false preserved, external-owner yield, invalid-engine guard, reset, explicit cap/VSync/fixed-frame settings untouched')
end

do
    local writes=0
    local variables={['r.NGX.DLSS.Enable']=1,['r.DynamicRes.OperationMode']=0,['r.ScreenPercentage']=80}
    local pc={IsValid=function()return true end}
    local system={
        IsValid=function()return true end,
        GetConsoleVariableFloatValue=function(_,name)return variables[name]or 0 end,
        ExecuteConsoleCommand=function(_,controller,command)
            assert(controller==pc)
            local name,value=command:match('^(%S+)%s+(%S+)$')
            assert(name=='r.ScreenPercentage')
            writes=writes+1;variables[name]=assert(tonumber(value))
        end,
    }
    local env=setmetatable({StaticFindObject=function()return system end},{__index=_G})
    local R=assert(loadfile(scriptdir..'/render.lua','t',env))()({valid=function(o)return o and o:IsValid()end,getPC=function()return pc end})
    local ok,message=R.apply('gpu_budget',true)
    assert(not ok and message:find('Use DLSS quality controls',1,true))
    assert(writes==0 and R.owned.gpu_budget==nil and variables['r.ScreenPercentage']==80)
    variables['r.NGX.DLSS.Enable']=0
    assert(R.apply('gpu_budget',true));assert(writes==1 and variables['r.ScreenPercentage']==60)
    variables['r.NGX.DLSS.Enable']=1
    R.tick();assert(writes==2 and variables['r.ScreenPercentage']==80 and R.owned.gpu_budget==nil and R.yielded.gpu_budget)
    R.tick();assert(writes==2 and variables['r.NGX.DLSS.Enable']==1)
    variables['r.NGX.DLSS.Enable']=0
    assert(R.apply('gpu_budget',false));assert(R.apply('gpu_budget',true))
    variables['r.NGX.DLSS.Enable'],variables['r.ScreenPercentage']=1,66
    R.tick();assert(writes==3 and variables['r.ScreenPercentage']==66 and R.owned.gpu_budget==nil)
    variables['r.NGX.DLSS.Enable']=0
    assert(R.apply('gpu_budget',true));assert(variables['r.ScreenPercentage']==49.5)
    variables['r.DynamicRes.OperationMode']=1
    R.tick();assert(variables['r.ScreenPercentage']==66 and R.owned.gpu_budget==nil and R.yielded.gpu_budget)
    assert(R.messages.gpu_budget:find('Dynamic resolution',1,true))
    assert(not R.apply('gpu_budget',true))
    variables['r.DynamicRes.OperationMode']=0
    assert(R.apply('gpu_budget',true))
    variables['r.DynamicRes.OperationMode'],variables['r.ScreenPercentage']=1,70
    R.tick();assert(variables['r.ScreenPercentage']==70 and R.owned.gpu_budget==nil)
    print('PASS DLSS ownership: initial rejection has no writes/state, disabled-DLSS budget works, newly enabled DLSS yields, changed upscaler scale survives, DLSS setting untouched')
    print('PASS dynamic resolution ownership: newly enabled mode yields/restores only owned scale, rejects reapply, preserves external scale')
end
