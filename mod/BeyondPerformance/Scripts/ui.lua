-- Standalone UMG utility. Uses no game assets or other mod's state.
-- Construction/viewport scaling follows the user's proven Beyond utility UI.
return function(M)
    local U = {opened = false, selected = 1, pageSize = 6}
    local valid = M.valid
    local lib, layout
    local colors = {
        bg = {R = .012, G = .018, B = .022, A = .985},
        row = {R = .035, G = .047, B = .052, A = 1},
        selected = {R = .06, G = .16, B = .18, A = 1},
        accent = {R = .22, G = .80, B = .70, A = 1},
        text = {R = .91, G = .94, B = .94, A = 1},
        muted = {R = .58, G = .65, B = .66, A = 1},
    }

    local function safeRead(fn, fallback)
        local ok, value = pcall(fn)
        if ok then return value end
        return fallback
    end
    local function same(a, b)
        return valid(a) and valid(b) and a:GetAddress() == b:GetAddress()
    end
    local function nativeOverlay(pc)
        if not valid(pc) then return true end
        if safeRead(function() return pc.bShowMouseCursor end, true) then return true end
        if safeRead(function() return pc.HUD.ChatUI.TypeInChat end, false) then return true end
        local menu = safeRead(function() return pc['BP Menu Component'] end)
        if not valid(menu) then menu = safeRead(function() return pc.BP_MenuComponent end) end
        return valid(menu) and safeRead(function() return menu:GetIsPauseMenu() end, true) or false
    end
    local function player(pc) return safeRead(function() return pc.PlayerControlled end) end
    local function ready(pc)
        local p = player(pc)
        return valid(pc) and valid(p) and safeRead(function() return p.IsLoaded end, false)
            and not safeRead(function() return p.BP_PlayerStats.IsDead end, false)
    end
    local function log(text) if M.log then M.log(text) end end
    local function new(kind, outer)
        local class = StaticFindObject('/Script/UMG.' .. kind)
        assert(valid(class), 'UMG class unavailable: ' .. kind)
        return StaticConstructObject(class, outer)
    end
    local function place(object, x, y, width, height)
        local slot = U.canvas:AddChildToCanvas(object)
        slot:SetPosition({X = U.x + x * U.scale, Y = U.y + y * U.scale})
        slot:SetSize({X = width * U.scale, Y = height * U.scale})
        object:SetVisibility(3) -- HitTestInvisible; controls use keyboard input.
        return object
    end
    local function rect(x, y, width, height, color)
        local object = new('Image', U.tree)
        object:SetColorAndOpacity(colors[color])
        return place(object, x, y, width, height)
    end
    local function text(value, x, y, width, height, size, color)
        local object = new('TextBlock', U.tree)
        object:SetText(FText(tostring(value)))
        local font = object.Font
        font.Size = math.max(9, math.floor(size * U.scale))
        object:SetFont(font)
        object:SetColorAndOpacity({SpecifiedColor = colors[color or 'text'], ColorUseRule = 0})
        return place(object, x, y, width, height)
    end
    local function rows()
        local result = {}
        for _, option in ipairs(M.options) do result[#result + 1] = option end
        result[#result + 1] = {action = 'benchmark', label = 'Record a performance sample', description = 'Close the menu and record the same view or route before and after changing options.'}
        result[#result + 1] = {action = 'defaults', label = 'Restore Beyond Performance defaults', description = 'Restore only this mod\'s preferences. Your game settings and saves stay separate.'}
        return result
    end

    function U.render()
        if not valid(U.canvas) then return end
        U.canvas:ClearChildren()
        local vp, dpi = layout:GetViewportSize(U.pc), layout:GetViewportScale(U.pc)
        dpi = math.max(.1, dpi)
        U.scale = math.min(vp.X / 1180, vp.Y / 760) / dpi
        U.x, U.y = (vp.X / dpi - 1120 * U.scale) / 2, (vp.Y / dpi - 700 * U.scale) / 2
        rect(0, 0, 1120, 700, 'bg')
        rect(0, 0, 1120, 4, 'accent')
        text('BEYOND PERFORMANCE', 32, 24, 900, 44, 28)
        text('LOCAL PERFORMANCE OPTIONS  /  F10 TO CLOSE', 34, 70, 1050, 28, 14, 'muted')
        local list = rows()
        U.selected = math.max(1, math.min(#list, U.selected))
        local first = math.floor((U.selected - 1) / U.pageSize) * U.pageSize + 1
        for index = first, math.min(#list, first + U.pageSize - 1) do
            local option, y = list[index], 116 + (index - first) * 65
            rect(28, y, 1064, 57, index == U.selected and 'selected' or 'row')
            local state = option.key and M.optionState and M.optionState(option.key)
            local mark = option.key and ('[' .. (state or (M.settings[option.key] and 'ON' or 'OFF')) .. ']  ') or '>  '
            text(mark .. option.label, 45, y + 10, 1028, 38, 19, index == U.selected and 'accent' or 'text')
        end
        local selected = list[U.selected]
        U.description = text(selected.description or '', 34, 516, 1050, 62, 16, 'muted')
        U.description:SetAutoWrapText(true)
        U.status = text(M.getStatus and M.getStatus() or '', 34, 584, 1050, 42, 14, 'muted')
        U.status:SetAutoWrapText(true)
        U.messageText = text(U.message or '', 34, 628, 1050, 28, 14, 'accent')
        text(('UP / DOWN: SELECT     ENTER: CHANGE     ESC / F10: CLOSE                 %d / %d'):format(U.selected, #list), 34, 666, 1050, 25, 13, 'muted')
        U.width, U.height = vp.X, vp.Y
    end

    function U.close(ownershipLost)
        U.opened = false
        if valid(U.widget) then pcall(function() U.widget:RemoveFromParent() end) end
        if valid(U.pc) then
            -- Balance only this menu's pushes, preserving other input blockers.
            if U.lookPushed then pcall(function() U.pc:SetIgnoreLookInput(false) end) end
            if U.movePushed then pcall(function() U.pc:SetIgnoreMoveInput(false) end) end
            if U.inputOwned and not ownershipLost and not nativeOverlay(U.pc) and same(M.getPC(), U.pc) then
                pcall(function() lib:SetInputMode_GameOnly(U.pc, true) end)
            end
        end
        U.lookPushed, U.movePushed, U.inputOwned = false, false, false
        U.widget, U.tree, U.canvas, U.status, U.description, U.messageText = nil, nil, nil, nil, nil, nil
        U.pc, U.player = nil, nil
    end

    function U.open()
        if U.opened then return true end
        local pc = M.getPC()
        if not ready(pc) then return false, 'Join a game before opening Beyond Performance.' end
        if nativeOverlay(pc) then return false, 'Close the current menu or chat, then press F10.' end
        U.pc, U.player = pc, player(pc)
        lib = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
        layout = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
        assert(valid(lib) and valid(layout), 'UMG libraries unavailable.')
        U.widget = lib:Create(pc, StaticFindObject('/Script/UMG.UserWidget'), pc)
        assert(valid(U.widget), 'Could not create the performance menu.')
        U.tree = U.widget.WidgetTree
        if not valid(U.tree) then U.tree = new('WidgetTree', U.widget); U.widget.WidgetTree = U.tree end
        U.canvas = new('CanvasPanel', U.tree)
        U.tree.RootWidget = U.canvas
        U.widget:AddToViewport(10010)
        U.message = ''
        U.render()
        pc:SetIgnoreLookInput(true); U.lookPushed = true
        pc:SetIgnoreMoveInput(true); U.movePushed = true
        -- No cursor mutation and no Pawn DisableInput/EnableInput pair. Native
        -- actions are suppressed by UIOnly while UE4SS handles navigation keys.
        lib:SetInputMode_UIOnlyEx(pc, U.widget, 0, true); U.inputOwned = true
        U.opened = true
        return true
    end

    function U.toggle()
        if U.opened then U.close(); return true end
        local ok, result, message = pcall(U.open)
        if not ok then U.close(); log('Menu failed: ' .. tostring(result)); return false, tostring(result) end
        if not result then log(message) end
        return result, message
    end

    function U.key(key)
        if not U.opened then return end
        if key == 'Escape' then U.close(); return end
        local list = rows()
        if key == 'Up' then U.selected = (U.selected - 2) % #list + 1
        elseif key == 'Down' then U.selected = U.selected % #list + 1
        elseif key == 'Return' then
            local option = list[U.selected]
            if option.key then
                local ok, message = M.setOption(option.key, not M.settings[option.key])
                U.message = message or (ok and 'Preference saved.' or 'Could not change this option.')
            elseif option.action == 'defaults' then
                local ok, message = M.resetDefaults()
                U.message = message or (ok == false and 'Could not restore defaults.' or 'Defaults restored.')
            elseif option.action == 'benchmark' then
                U.close()
                local status = M.startBenchmark()
                if status then log(tostring(status)) end
                return
            end
        end
        if U.opened then U.render() end
    end

    function U.tick()
        if not U.opened then return end
        local pc = M.getPC()
        if not same(pc, U.pc) or not ready(pc) or not same(player(pc), U.player) or not valid(U.widget) then
            -- A respawn or a removed widget can retain the same controller.
            -- Release our UIOnly mode there; close() still preserves another
            -- menu's ownership if its cursor/chat/pause state has taken over.
            U.close(not same(pc, U.pc)); return
        end
        if nativeOverlay(pc) then U.close(true); return end
        local vp = layout:GetViewportSize(pc)
        if vp.X ~= U.width or vp.Y ~= U.height then U.render(); return end
        local status = M.getStatus and M.getStatus() or ''
        if status ~= U.lastStatus and valid(U.status) then U.status:SetText(FText(status)); U.lastStatus = status end
    end

    -- RegisterKeyBind runs outside the game thread. Only queue work here.
    for _, name in ipairs({'Up', 'Down', 'Return', 'Escape'}) do
        local keyName = name
        local codes={Up=Key.UP_ARROW,Down=Key.DOWN_ARROW,Return=Key.RETURN,Escape=Key.ESCAPE}
        local code = assert(codes[name], 'Missing UE4SS navigation key: '..name)
        RegisterKeyBind(code, function()
            if not U.opened then return end
            ExecuteInGameThread(function()
                local ok, err = pcall(U.key, keyName)
                if not ok then U.close(); log('Menu action failed: ' .. tostring(err)) end
            end)
        end)
    end
    return U
end
