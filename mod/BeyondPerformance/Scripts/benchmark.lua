-- Temporary, local-player frame capture. No per-frame work when idle.
return function(M)
    local B = {lastStatus = 'No performance sample recorded yet.'}
    local functionPath = '/Game/BP/Player/PlayerBase.PlayerBase_C:ReceiveTick'
    local settleSeconds, captureSeconds, maxSamples = 3, 30, 20000
    local valid = M.valid
    local serial = 0

    local function log(message) if M.log then M.log(message) end end
    local function safe(fn, fallback)
        local ok, value = pcall(fn)
        if ok then return value end
        return fallback
    end
    local function clean(value) return tostring(value):gsub('[\r\n]', ' ') end
    local function number(value, decimals)
        if type(value) ~= 'number' then return 'n/a' end
        return ('%.' .. (decimals or 3) .. 'f'):format(value)
    end

    -- Nearest-rank percentiles; median averages the two middle values for even
    -- samples. 1% low is 1 / mean(slowest ceil(N * .01) frame durations).
    function B.summarize(samples)
        local sorted, sum, over33, over50, over100 = {}, 0, 0, 0, 0
        for index, value in ipairs(samples) do
            sorted[index] = value
            sum = sum + value
            if value > .0333 then over33 = over33 + 1 end
            if value > .050 then over50 = over50 + 1 end
            if value > .100 then over100 = over100 + 1 end
        end
        table.sort(sorted)
        local n = #sorted
        local result = {samples = n, seconds = sum, over33ms = over33, over50ms = over50, over100ms = over100}
        if n == 0 then return result end
        local middle = math.floor((n + 1) / 2)
        local median = n % 2 == 0 and (sorted[middle] + sorted[middle + 1]) / 2 or sorted[middle]
        local lowN, lowSum = math.max(1, math.ceil(n * .01)), 0
        for index = n - lowN + 1, n do lowSum = lowSum + sorted[index] end
        result.averageFPS = sum > 0 and n / sum or nil
        result.meanMs, result.medianMs = sum / n * 1000, median * 1000
        result.p95Ms, result.p99Ms = sorted[math.ceil(n * .95)] * 1000, sorted[math.ceil(n * .99)] * 1000
        result.onePercentLowFPS = lowSum > 0 and lowN / lowSum or nil
        result.onePercentFrames = lowN
        result.maxMs = sorted[n] * 1000
        return result
    end

    local function context(pc)
        local info = {}
        if not valid(pc) then return info end
        info.world = safe(function()
            local world = pc:GetWorld()
            return valid(world) and world:GetFullName() or 'unavailable'
        end, 'unavailable')
        info.player = safe(function()
            local human = pc.PlayerControlled
            return valid(human) and human:GetFullName() or 'unavailable'
        end, 'unavailable')
        info.camera = safe(function()
            local camera = pc.PlayerCameraManager
            if not valid(camera) then return 'unavailable' end
            local point = camera:GetCameraLocation()
            local rotation = camera:GetCameraRotation()
            return ('x=%.2f y=%.2f z=%.2f pitch=%.3f yaw=%.3f roll=%.3f'):format(point.X, point.Y, point.Z, rotation.Pitch, rotation.Yaw, rotation.Roll)
        end, 'unavailable')
        info.viewport = safe(function()
            local layout = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
            if not valid(layout) then return 'unavailable' end
            local size = layout:GetViewportSize(pc)
            return ('%.0fx%.0f'):format(size.X, size.Y)
        end, 'unavailable')
        return info
    end

    local function configuration()
        local rows, names = {}, {}
        for key in pairs(M.settings or {}) do names[#names + 1] = key end
        table.sort(names)
        for _, key in ipairs(names) do rows[#rows + 1] = 'option.' .. key .. '=' .. clean(M.settings[key]) end
        local system = StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
        if valid(system) then
            for _, name in ipairs({'t.MaxFPS', 'r.VSync', 'r.ScreenPercentage', 'r.OneFrameThreadLag',
                'sg.ViewDistanceQuality', 'sg.ShadowQuality', 'sg.PostProcessQuality', 'sg.FoliageQuality',
                'r.ShadowQuality', 'r.ViewDistanceScale', 'grass.DensityScale', 'foliage.DensityScale', 'r.VolumetricCloud'}) do
                rows[#rows + 1] = 'cvar.' .. name .. '=' .. clean(safe(function() return system:GetConsoleVariableFloatValue(name) end, 'unavailable'))
            end
        end
        return rows
    end

    local function removeHook(s)
        if not s.hook or s.removing then return end
        s.removing = true
        local ids = s.hook
        -- RegisterHook/UnregisterHook must run outside the game-thread state.
        -- Delaying the dispatch also lets the active ReceiveTick callback return.
        ExecuteInGameThreadWithDelay(1, function()
            ExecuteAsync(function()
                local ok, err = pcall(UnregisterHook, functionPath, ids[1], ids[2])
                if not ok then log('Benchmark hook cleanup failed: ' .. tostring(err)) end
                s.hook = nil
            end)
        end)
    end

    local function newBase()
        local base = M.root .. '/benchmark-' .. os.date('%Y%m%d-%H%M%S')
        local candidate = base
        local suffix = 0
        while true do
            local file = io.open(candidate .. '.csv', 'rb')
            if not file then return candidate end
            file:close(); suffix = suffix + 1
            candidate = base .. '-' .. suffix
        end
    end

    local function writeFile(path, data)
        local file, err = io.open(path, 'wb')
        if not file then return false, err end
        local wrote, writeErr = file:write(data)
        local flushed, flushErr = file:flush()
        local closed, closeErr = file:close()
        if not wrote or not flushed or not closed then return false, writeErr or flushErr or closeErr end
        return true
    end

    local function summaryRows(prefix, summary, rows)
        for _, key in ipairs({'samples', 'seconds', 'averageFPS', 'meanMs', 'medianMs', 'p95Ms', 'p99Ms',
            'onePercentLowFPS', 'onePercentFrames', 'maxMs', 'over33ms', 'over50ms', 'over100ms'}) do
            rows[#rows + 1] = prefix .. '.' .. key .. '=' .. number(summary[key], 6)
        end
    end

    -- Checkpoint only while the user explicitly records. A process crash can
    -- lose at most the pending two-second buffer; the sidecar remains partial.
    local function checkpoint(s)
        if #s.pending == 0 then return true end
        local file, err = io.open(s.base .. '.csv', 'ab')
        if not file then return false, err end
        local wrote, why = file:write(table.concat(s.pending, '\n') .. '\n')
        local flushed, flushErr = file:flush()
        local closed, closeErr = file:close()
        if not wrote or not flushed or not closed then return false, why or flushErr or closeErr end
        s.pending = {}
        return true
    end

    local function finish(s, reason, complete)
        if s.finished then return end
        s.finished = true
        if B.current == s then B.current = nil end
        if s.watchdog then pcall(CancelDelayedAction, s.watchdog); s.watchdog = nil end
        removeHook(s)
        local ended = safe(function() return context(s.pc) end, {})
        local engine, wall = B.summarize(s.engine), B.summarize(s.wall)
        local base = s.base
        local csv = {'frame,elapsed_clock_s,engine_dt_ms,callback_interval_ms'}
        for index = 1, #s.engine do
            csv[#csv + 1] = ('%d,%.6f,%.6f,%.6f'):format(index, s.elapsed[index], s.engine[index] * 1000, s.wall[index] * 1000)
        end
        local metadata = {
            'Beyond Performance local frame capture',
            'modVersion=' .. clean(M.version or 'unknown'),
            'started=' .. s.startedDate,
            'completed=' .. tostring(complete == true),
            'reason=' .. clean(reason),
            'settleSeconds=' .. settleSeconds,
            'targetCaptureSeconds=' .. captureSeconds,
            'sampleLimit=' .. maxSamples,
            'method=Temporary local PlayerBase.ReceiveTick hook; remote players excluded.',
            'engine_dt=Game-provided delta seconds; engine clamping/time dilation can differ from real presentation time.',
            'callback_interval=Successive os.clock() readings in the local tick callback; on Windows this uses CRT elapsed-clock time.',
            'clock_limits=Clock precision and hook scheduling affect intervals; this is not a GPU presentation trace.',
            'workload_limits=No CPU/GPU stage breakdown is supplied by this capture.',
            'percentiles=Nearest rank; no hitch/outlier filtering. Median averages the two middle values for an even count.',
            'onePercentLowFPS=Reciprocal mean duration of the slowest ceil(sample_count * 0.01) frames.',
            'thresholds=Counts strictly above 33.3ms, 50ms and 100ms.',
            'checkpoint=CSV flushed every two seconds while recording; an interrupted sidecar stays completed=false.',
            'comparison=Use the same seed/save, camera, route, graphics settings, window size, and warmed-up scene. Close other heavy workloads.',
        }
        for _, phase in ipairs({'start', 'end'}) do
            local info = phase == 'start' and s.context or ended
            for _, key in ipairs({'world', 'player', 'camera', 'viewport'}) do
                metadata[#metadata + 1] = phase .. '.' .. key .. '=' .. clean(info[key] or 'unavailable')
            end
        end
        for _, row in ipairs(s.configuration) do metadata[#metadata + 1] = row end
        for _, row in ipairs(configuration()) do metadata[#metadata + 1] = 'end.' .. row end
        summaryRows('engine', engine, metadata)
        summaryRows('callback', wall, metadata)
        local csvOK, csvError = writeFile(base .. '.csv', table.concat(csv, '\n') .. '\n')
        local metaOK, metaError = writeFile(base .. '.txt', table.concat(metadata, '\n') .. '\n')
        B.latest = {engine = engine, callback = wall, complete = complete == true, reason = reason,
            csvPath = csvOK and base .. '.csv' or nil, metadataPath = metaOK and base .. '.txt' or nil}
        if csvOK and metaOK then
            B.lastStatus = ('%s: %s FPS, p95 %s ms (%d frames). Results saved.'):format(complete and 'Sample complete' or 'Partial sample',
                number(wall.averageFPS, 1), number(wall.p95Ms, 1), wall.samples)
            log(B.lastStatus .. ' ' .. base .. '.csv; ' .. reason)
        else
            B.lastStatus = 'Sample stopped; could not save all results: ' .. clean(csvError or metaError)
            log(B.lastStatus)
        end
        -- The pinned loader leaves a disabled Blueprint hook registry entry
        -- after UnregisterHook. Its callback can retain this small session
        -- table, so explicitly release frame buffers and UObject references.
        s.engine, s.wall, s.elapsed, s.pending = nil, nil, nil, nil
        s.pc, s.player, s.context, s.configuration = nil, nil, nil, nil
    end

    function B.stop(reason)
        local s = B.current
        if not s then return false, 'No capture is running.' end
        finish(s, reason or 'Stopped by user.', false)
        return true, B.lastStatus
    end

    local function sample(s, contextParameter, deltaParameter)
        if s.finished or B.current ~= s or s.phase == 'starting' then return end
        local actor = contextParameter:get()
        if not valid(actor) or actor:GetAddress() ~= s.playerId then return end
        local now = os.clock()
        if not s.previousClock then s.previousClock = now; return end
        local wall = now - s.previousClock
        s.previousClock = now
        if now - s.installedAt < settleSeconds then return end
        if not s.captureStart then s.captureStart = now; s.phase = 'recording'; return end
        local delta = deltaParameter:get()
        if type(delta) ~= 'number' or delta ~= delta or delta < 0 or delta == math.huge or wall < 0 then
            finish(s, 'Invalid frame delta or clock discontinuity; partial results retained.', false)
            return
        end
        local index = #s.engine + 1
        s.engine[index], s.wall[index], s.elapsed[index] = delta, wall, now - s.captureStart
        s.pending[#s.pending + 1] = ('%d,%.6f,%.6f,%.6f'):format(index, s.elapsed[index], delta * 1000, wall * 1000)
        if now >= s.nextFlush then
            s.nextFlush = now + 2
            local ok, why = checkpoint(s)
            if not ok then finish(s, 'Checkpoint failed: ' .. tostring(why), false); return end
        end
        -- Include the final frame/hitch crossing the capture deadline.
        if now - s.captureStart >= captureSeconds then finish(s, '30-second capture completed.', true)
        elseif index >= maxSamples then finish(s, '20,000-sample safety limit reached before the deadline.', false) end
    end

    function B.start()
        if B.current then return 'A performance sample is already running.' end
        local pc = M.getPC()
        local human = valid(pc) and safe(function() return pc.PlayerControlled end)
        if not valid(pc) or not valid(human) or not safe(function() return human.IsLoaded and pc:IsLocalPlayerController() end, false) then
            return 'Join a game and wait for loading to finish before recording.'
        end
        local fn = StaticFindObject(functionPath)
        if not valid(fn) then return 'This game build does not expose the expected player tick; recording is unavailable.' end
        serial = serial + 1
        local s = {serial = serial, phase = 'starting', pc = pc, player = human, playerId = human:GetAddress(),
            pcId = pc:GetAddress(), context = context(pc), configuration = configuration(), startedDate = os.date('%Y-%m-%d %H:%M:%S'),
            requestedAt = os.clock(), engine = {}, wall = {}, elapsed = {}, pending = {}, base = newBase(), nextFlush = os.clock() + 2}
        local partial = {'Beyond Performance local frame capture', 'modVersion=' .. clean(M.version or 'unknown'),
            'started=' .. s.startedDate, 'completed=false', 'reason=Recording in progress or process exited before finalization.',
            'checkpoint=Frames flushed every two seconds; final pending frames may be missing after a crash.',
            'method=Local PlayerBase.ReceiveTick; engine delta and callback interval are not presentation times.'}
        for key, value in pairs(s.context) do partial[#partial + 1] = 'start.' .. key .. '=' .. clean(value) end
        for _, row in ipairs(s.configuration) do partial[#partial + 1] = row end
        local metaOK, metaErr = writeFile(s.base .. '.txt', table.concat(partial, '\n') .. '\n')
        local csvOK, csvErr = writeFile(s.base .. '.csv', 'frame,elapsed_clock_s,engine_dt_ms,callback_interval_ms\n')
        if not metaOK or not csvOK then return 'Cannot start recording: ' .. clean(metaErr or csvErr) end
        B.current = s
        B.lastStatus = 'Starting sample: 3 seconds to settle, then 30 seconds of recording.'
        ExecuteAsync(function()
            if s.finished then return end
            local ok, first, second = pcall(RegisterHook, functionPath, function(ctx, dt)
                local success, err = pcall(sample, s, ctx, dt)
                if not success and not s.finished then
                    local saved, saveErr = pcall(finish, s, 'Capture error: ' .. tostring(err), false)
                    if not saved then log('Benchmark could not finalize: ' .. tostring(saveErr)) end
                end
            end)
            if ok then s.hook = {first, second} end
            ExecuteInGameThread(function()
                if s.finished then removeHook(s); return end
                if not ok then finish(s, 'Could not install capture hook: ' .. tostring(first), false); return end
                s.installedAt, s.phase = os.clock(), 'settling'
            end)
        end)
        s.watchdog = LoopInGameThreadWithDelay(500, function()
            if s.finished then return end
            local currentPC = M.getPC()
            local currentHuman = valid(currentPC) and safe(function() return currentPC.PlayerControlled end)
            if not valid(currentPC) or currentPC:GetAddress() ~= s.pcId or not valid(currentHuman) or currentHuman:GetAddress() ~= s.playerId
                or not safe(function() return currentHuman.IsLoaded end, false) then
                finish(s, 'Player/world changed or unloaded; partial results retained.', false)
                return
            end
            local now = os.clock()
            if s.phase == 'starting' and now - s.requestedAt > 10 then
                finish(s, 'Capture-hook startup timed out.', false)
            elseif s.installedAt and not s.previousClock and now - s.installedAt > 10 then
                finish(s, 'The capture hook received no local player ticks; no frame sample was available.', false)
            elseif s.previousClock and now - s.previousClock > 5 then
                -- A timer can run before ReceiveTick when a long CPU stall
                -- ends. Do not mistake that gap for a missing callback and
                -- discard the hitch: only abort here for an actual game pause.
                local game = StaticFindObject('/Script/Engine.Default__GameplayStatics')
                local paused = valid(game) and safe(function() return game:IsGamePaused(currentPC) end, false)
                if paused then finish(s, 'Game paused; partial results retained.', false) end
            end
        end)
        log(B.lastStatus)
        return B.lastStatus
    end

    function B.status()
        local s = B.current
        if not s then return B.lastStatus end
        if s.phase == 'starting' then return 'Starting performance sample...' end
        if not s.captureStart then return 'Settling before recording...' end
        return ('Recording: %d / 30 seconds, %d frames.'):format(math.min(30, math.floor(os.clock() - s.captureStart)), #s.engine)
    end

    return B
end
