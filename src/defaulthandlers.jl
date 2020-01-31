const STEPSPERKEY = 1
const SHIFTSTEPSPERKEY = 50


function default_mousemovecb(e::Engine, s::WindowState, ev::MouseMoveEvent)
    p = e.phys
    sim = getsim(p.model)
    ui = e.ui

    if ev.isdrag
        # Move free camera

        scaled_dx = ev.dx / s.width
        scaled_dy = ev.dy / s.height

        if s.right
            action = s.shift ? MJCore.mjMOUSE_MOVE_H : MJCore.mjMOUSE_MOVE_V
        elseif s.left
            action = s.shift ? MJCore.mjMOUSE_ROTATE_H : MJCore.mjMOUSE_ROTATE_V
        else
            action = MJCore.mjMOUSE_ZOOM
        end

function gen_backstep_event(e::Engine)
    l1 = onkeypress(GLFW.KEY_LEFT) do state, event
        if e.ui.paused
            for _ = 1:STEPSPERKEY
                reversestep!(e.phys, mode(e))
            end
        end
    end
    l2 = onevent(KeyRepeat) do state, event
        if event.key == GLFW.KEY_LEFT && e.ui.paused
            for _ = 1:STEPSPERKEY
                reversestep!(e.phys, mode(e))
            end
        end
    end
    l3 = onkeypress(GLFW.KEY_LEFT, MOD_SHIFT) do state, event
        if e.ui.paused
            for _ = 1:SHIFTSTEPSPERKEY
                reversestep!(e.phys, mode(e))
            end
        end
    end
    l4 = onevent(KeyRepeat) do state, event
        if event.key == GLFW.KEY_LEFT && state.shift && e.ui.paused
            for _ = 1:SHIFTSTEPSPERKEY
                reversestep!(e.phys, mode(e))
            end
        end
    end

    return
end

function gen_forwardstep_event(e::Engine)
    r1 = onkeypress(GLFW.KEY_RIGHT) do state, event
        if e.ui.paused
            for _ = 1:STEPSPERKEY
                forwardstep!(e.phys, mode(e))
            end
        end
    end
    r2 = onevent(KeyRepeat) do state, event
        if event.key == GLFW.KEY_RIGHT && e.ui.paused
            for _ = 1:STEPSPERKEY
                forwardstep!(e.phys, mode(e))
            end
        end
    end
    r3 = onkeypress(GLFW.KEY_RIGHT, MOD_SHIFT) do state, event
        if e.ui.paused
            for _ = 1:SHIFTSTEPSPERKEY
                forwardstep!(e.phys, mode(e))
            end
        end
    end
    r4 = onevent(KeyRepeat) do state, event
        if event.key == GLFW.KEY_RIGHT && state.shift && e.ui.paused
            for _ = 1:SHIFTSTEPSPERKEY
                forwardstep!(e.phys, mode(e))
            end
        end
    end

function handlers(e::Engine)
    let e = e,
        sim = getsim(e.phys.model),
        pert = e.phys.pert,
        ui = e.ui,
        phys = e.phys
        return [
            onkeypress(GLFW.KEY_F1, desc = "Show help message") do state, event
                print(e.handlerdescription)
            end,

            onevent(MouseMoveEvent) do s, ev
                default_mousemovecb(e, s, ev)
            end,


            onkey(GLFW.KEY_F1, what = "Show help message") do s, ev
                ispress_or_repeat(ev.action) && printhelp(e)
            end,

            onkey(GLFW.KEY_F2, what = "Toggle simulation info") do s, ev
                ispress_or_repeat(ev.action) && (ui.showinfo = !ui.showinfo)
            end,

            onkey(GLFW.KEY_F11, what = "Toggle fullscreen") do s, ev
                if ispress_or_repeat(ev.action)
                    ismin = iszero(GLFW.GetWindowAttrib(s.window, GLFW.MAXIMIZED))
                    ismin ? GLFW.MaximizeWindow(s.window) : GLFW.RestoreWindow(s.window)
                end
            end,

            onkey(GLFW.KEY_ESCAPE, what = "Quit") do s, ev
                ispress_or_repeat(ev.action) && (ui.shouldexit = true)
            end,

            gen_forwardstep_event(e),
            gen_backstep_event(e),

            onkeypress(GLFW.KEY_SEMICOLON, desc = "Cycle frame mode backwards") do _, _
                ui.vopt[].frame = dec(ui.vopt[].frame, 0, Integer(MJCore.mjNFRAME) - 1)
            end,
            onkeypress(GLFW.KEY_APOSTROPHE, desc = "Cycle frame mode forward") do _, _
                ui.vopt[].frame = inc(ui.vopt[].frame, 0, Integer(MJCore.mjNFRAME) - 1)
            end,

            onkey(GLFW.KEY_A, MOD_CONTROL, what = "Align camera scale") do s, ev
                ispress_or_repeat(ev.action) && alignscale!(ui, getsim(p.model))
            end,

            onkey(GLFW.KEY_V, what = "Toggle video recording") do s, ev
                if ispress(ev.action)
                    e.ffmpeghandle === nothing ? startrecord!(e) : stoprecord!(e)
                end
            end,

            onkey(GLFW.KEY_BACKSPACE, what = "Reset model") do s, ev
                ispress_or_repeat(ev.action) && reset!(p, mode(e))
            end,

            onkey(GLFW.KEY_R, what = "Toggle reverse") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.reversed = !ui.reversed
                    p.timer.rate *= -1
                    resettime!(p)
                end
            end,


            onkey(GLFW.KEY_SPACE, what = "Pause") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.paused ? start!(p.timer) : stop!(p.timer)
                    ui.paused = !ui.paused
                end
            end,

            onevent(ButtonPress) do state, event
                if !ismiddle(event.button) && state.control && pert[].select > 0
                    newperturb = state.right ? Int(MJCore.mjPERT_TRANSLATE) : Int(MJCore.mjPERT_ROTATE)
                    # perturbation onset: reset reference
                    iszero(pert[].active) && mjv_initPerturb(sim.m, sim.d, ui.scn, pert)
                    pert[].active = newperturb
                end
            end,

            onevent(ButtonRelease) do state, event
                isright(event.button) || isleft(event.button) && (pert[].active = 0)
            end,


            onkey(GLFW.KEY_ENTER, what = "Toggle speed mode") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.speedmode = !ui.speedmode
                    setrate!(p.timer, ui.speedmode ? ui.speedfactor : 1)
                end
            end,

            onkey(GLFW.KEY_UP, MOD_SHIFT, what = "Increase sim rate in speedmode") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.speedfactor *= 2
                    setrate!(p.timer, ui.speedfactor)
                end
            end,

            onkey(GLFW.KEY_DOWN, MOD_SHIFT, what = "Decrease sim rate in speedmode") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.speedfactor /= 2
                    setrate!(p.timer, ui.speedfactor)
                end
            end,


            onkey(GLFW.KEY_PAGE_UP, what = "Cycle engine mode forward") do s, ev
                if ispress_or_repeat(ev.action)
                    switchmode!(e, inc(e.curmodeidx, 1, length(e.modes)))
                end
            end,

            onkey(GLFW.KEY_PAGE_DOWN, what = "Cycle engine mode backwards") do s, ev
                if ispress_or_repeat(ev.action)
                    switchmode!(e, dec(e.curmodeidx, 1, length(e.modes)))
                end
            end,


            onkey(GLFW.KEY_MINUS, what = "Cycle label mode backwards") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.vopt[].label = dec(ui.vopt[].label, 0, Int(MJCore.mjNLABEL) - 1)
                end
            end,

            onkey(GLFW.KEY_EQUAL, what = "Cycle label mode forward") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.vopt[].label = inc(ui.vopt[].label, 0, Int(MJCore.mjNLABEL) - 1)
                end
            end,


            onkey(GLFW.KEY_LEFT_BRACKET, what = "Cycle frame mode backwards") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.vopt[].frame = dec(ui.vopt[].frame, 0, Int(MJCore.mjNFRAME) - 1)
                end
            end,

            onkey(GLFW.KEY_RIGHT_BRACKET, what = "Cycle frame mode forward") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.vopt[].frame = inc(ui.vopt[].frame, 0, Int(MJCore.mjNFRAME) - 1)
                end
            end,

            gen_mjflag_events(ui)...
        ]
    end
end

function gen_mjflag_events(ui::UIState)
    handlers = AbstractEventHandler[]

    for i=1:Int(MJCore.mjNVISFLAG)
        key = glfw_lookup_key(MJCore.mjVISSTRING[3, i])
        name = MJCore.mjVISSTRING[1, i]
        h = onkeypress(key, desc = "Toggle $name Viz Flag") do _, _
            ui.vopt[].flags = _toggleflag(ui.vopt[].flags, i)
        end
        push!(handlers, h)
    end

    for i=1:Int(MJCore.mjNRNDFLAG)
        key = glfw_lookup_key(MJCore.mjRNDSTRING[3, i])
        name = MJCore.mjRNDSTRING[1, i]
        h = onkeypress(key, desc = "Toggle $name Render Flag") do _, _
            ui.scn[].flags = _toggleflag(ui.scn[].flags, i)
        end
        push!(handlers, h)
    end

    n = Int(MJCore.mjNGROUP)
    h = onevent(KeyPress, desc = "Toggle Group Groups 1-$n") do s, e
        iszero(modbits(s)) || return
        for i=1:n
            if Int(e.key) == i + Int('0')
                ui.vopt[].geomgroup = _toggleflag(ui.vopt[].geomgroup, i)
                return
            end
        end
    end
    push!(handlers, h)

    n = Int(MJCore.mjNGROUP)
    h = onevent(KeyPress, desc = "Toggle Site Groups 1-$n") do s, e
        isshift(modbits(s)) || return
        for i=1:n
            if Int(e.key) == i + Int('0')
                ui.vopt[].sitegroup = _toggleflag(ui.vopt[].sitegroup, i)
                return
            end
        end
    end
    push!(handlers, h)

    handlers
end

@inline function _toggleflag(A::SVector{N,MJCore.mjtByte}, i::Integer) where {N}
    A = MVector(A)
    A[i] = ifelse(A[i] > 0, 0, 1)
    SVector(A)
end