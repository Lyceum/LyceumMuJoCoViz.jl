const STEPSPERKEY = 1
const SHIFTSTEPSPERKEY = 50

function move_pert_or_cam(
    ui::UIState,
    phys::PhysicsState,
    s::WindowState,
    ev::MouseDrag,
)
    sim = getsim(phys.model)
    scaled_dx, scaled_dy = ev.dx / s.width, ev.dy / s.height

    if s.right
        action = s.shift ? MJCore.mjMOUSE_MOVE_H : MJCore.mjMOUSE_MOVE_V
    elseif s.left
        action = s.shift ? MJCore.mjMOUSE_ROTATE_H : MJCore.mjMOUSE_ROTATE_V
    else
        action = MJCore.mjMOUSE_ZOOM
    end

    if iszero(phys.pert[].active)
        mjv_moveCamera(sim.m, action, scaled_dx, scaled_dy, ui.scn, ui.cam)
    else
        mjv_movePerturb(sim.m, sim.d, action, scaled_dx, scaled_dy, ui.scn, phys.pert)
    end
end

function default_mousecb(e::Engine, s::WindowState, ev::Doubleclick)
    if isleft(ev.button)
        selmode = 1
    elseif (ismiddle(ev.button) || isright(ev.button)) && s.control
        selmode = 3
    elseif isright(ev.button)
        selmode = 2
    end

    # get current window size & cursor pos
    width, height = s.width, s.height
    x, y = s.x, s.y
    sim = getsim(e.phys.model)

    # find geom and 3D click point, get corresponding body
    selpnt = zeros(MVector{3,Float64})
    selgeom, selskin = Ref(Cint(0)), Ref(Cint(0))
    selbody = mjv_select(
        sim.m,
        sim.d,
        e.ui.vopt,
        width / height,
        x / width,
        (height - y) / height,
        e.ui.scn,
        selpnt,
        selgeom,
        selskin,
    )

    # stop perturbation on select
    e.phys.pert[].active = 0

    # set lookat point, start tracking is requested
    if selmode == 2 || selmode == 3
        # copy selpnt if anything clicked
        selbody >= 0 && (e.ui.cam[].lookat = selpnt)

        # switch to tracking camera
        if selmode == 3 && selbody >= 0
            e.ui.cam[].type = Int(MJCore.mjCAMERA_TRACKING)
            e.ui.cam[].trackbodyid = selbody
            e.ui.cam[].fixedcamid = -1
        end
    else # set body selection
        if selbody >= 0
            # compute localpos
            tmp = selpnt - sim.d.xpos[:, selbody+1]
            res = reshape(sim.d.xmat[:, selbody+1], 3, 3)' * tmp
            e.phys.pert[].localpos = SVector{3}(res)

            # record selection
            e.phys.pert[].select = selbody
            e.phys.pert[].skinselect = selskin[]
        else
            e.phys.pert[].select = 0
            e.phys.pert[].skinselect = -1
        end
    end
end

function gen_backstep_event(e::Engine)
    l1 = onkeypress(GLFW.KEY_LEFT) do s, ev
        if e.ui.paused
            for _ = 1:STEPSPERKEY
                reversestep!(e.phys, mode(e))
            end
        end
    end
    l2 = onevent(KeyRepeat) do s, ev
        if ev.key == GLFW.KEY_LEFT && e.ui.paused
            for _ = 1:STEPSPERKEY
                reversestep!(e.phys, mode(e))
            end
        end
    end
    l3 = onkeypress(GLFW.KEY_LEFT, MOD_SHIFT) do s, ev
        if e.ui.paused
            for _ = 1:SHIFTSTEPSPERKEY
                reversestep!(e.phys, mode(e))
            end
        end
    end
    l4 = onevent(KeyRepeat) do s, ev
        if ev.key == GLFW.KEY_LEFT && s.shift && e.ui.paused
            for _ = 1:SHIFTSTEPSPERKEY
                reversestep!(e.phys, mode(e))
            end
        end
    end
    MultiEventHandler(
        [l1, l2, l3, l4],
        "KEY_LEFT  Step back when paused (hold SHIFT for $(SHIFTSTEPSPERKEY) steps)",
    )
end

function gen_forwardstep_event(e::Engine)
    r1 = onkeypress(GLFW.KEY_RIGHT) do s, ev
        if e.ui.paused
            for _ = 1:STEPSPERKEY
                forwardstep!(e.phys, mode(e))
            end
        end
    end
    r2 = onevent(KeyRepeat) do s, ev
        if ev.key == GLFW.KEY_RIGHT && e.ui.paused
            for _ = 1:STEPSPERKEY
                forwardstep!(e.phys, mode(e))
            end
        end
    end
    r3 = onkeypress(GLFW.KEY_RIGHT, MOD_SHIFT) do s, ev
        if e.ui.paused
            for _ = 1:SHIFTSTEPSPERKEY
                forwardstep!(e.phys, mode(e))
            end
        end
    end
    r4 = onevent(KeyRepeat) do s, ev
        if ev.key == GLFW.KEY_RIGHT && s.shift && e.ui.paused
            for _ = 1:SHIFTSTEPSPERKEY
                forwardstep!(e.phys, mode(e))
            end
        end
    end
    MultiEventHandler(
        [r1, r2, r3, r4],
        "KEY_RIGHT  Step forward when paused (hold SHIFT for $(SHIFTSTEPSPERKEY) steps)",
    )
end

function handlers(e::Engine)
    let e = e,
        sim = getsim(e.phys.model),
        pert = e.phys.pert,
        ui = e.ui,
        phys = e.phys
        return [
            onkeypress(GLFW.KEY_F1, desc = "Show help message") do s, ev
                print(e.handlerdescription)
            end,
            onkeypress(GLFW.KEY_F2, desc = "Toggle simulation info") do s, ev
                ui.showinfo = !ui.showinfo
            end,
            onkeypress(GLFW.KEY_F11, desc = "Toggle fullscreen") do s, ev
                ismax = GLFW.GetWindowAttrib(s.window, GLFW.MAXIMIZED)
                iszero(ismax) ? GLFW.MaximizeWindow(s.window) :
                GLFW.RestoreWindow(s.window)
            end,
            onkeypress(GLFW.KEY_BACKSPACE, desc = "Reset model") do _, _
                reset!(phys, mode(e))
            end,
            onkeypress(GLFW.KEY_R, desc = "Toggle reverse") do s, ev
                ui.reversed = !ui.reversed
                phys.timer.rate *= -1
                resettime!(phys)
            end,
            onkeypress(GLFW.KEY_ENTER, desc = "Toggle speed mode") do s, ev
                if ui.speedmode
                    ui.speedmode = false
                    setrate!(phys.timer, 1)
                else
                    ui.speedmode = true
                    setrate!(phys.timer, ui.speedfactor)
                end
            end,
            onkeypress(GLFW.KEY_ESCAPE, desc = "Quit") do _, _
                ui.shouldexit = true
            end,

            onkeypress(
                GLFW.KEY_A,
                MOD_CONTROL,
                desc = "Align camera scale",
            ) do s, ev
                alignscale!(ui, sim)
            end,

            gen_forwardstep_event(e),
            gen_backstep_event(e),

            onkeypress(GLFW.KEY_LEFT_BRACKET, desc = "Cycle frame mode backwards") do _, _
                ui.vopt[].frame = dec(ui.vopt[].frame, 0, Int(MJCore.mjNFRAME) - 1)
            end,
            onkeypress(GLFW.KEY_RIGHT_BRACKET, desc = "Cycle frame mode forward") do _, _
                ui.vopt[].frame = inc(ui.vopt[].frame, 0, Int(MJCore.mjNFRAME) - 1)
            end,

            onkeypress(GLFW.KEY_MINUS, desc = "Cycle label mode backwards") do _, _
                ui.vopt[].label = dec(ui.vopt[].label, 0, Int(MJCore.mjNLABEL) - 1)
            end,
            onkeypress(GLFW.KEY_EQUAL, desc = "Cycle label mode forward") do _, _
                ui.vopt[].label = inc(ui.vopt[].label, 0, Int(MJCore.mjNLABEL) - 1)
            end,

            onkeypress(
                GLFW.KEY_PAGE_UP,
                desc = "Cycle engine mode forward",
            ) do s, ev
                switchmode!(e, inc(e.curmodeidx, 1, length(e.modes)))
            end,
            onkeypress(
                GLFW.KEY_PAGE_DOWN,
                desc = "Cycle engine mode backwards",
            ) do s, ev
                switchmode!(e, dec(e.curmodeidx, 1, length(e.modes)))
            end,

            onkeypress(GLFW.KEY_SPACE, desc = "Pause") do s, ev
                if ui.paused
                    start!(phys.timer)
                    ui.paused = false
                else
                    stop!(phys.timer)
                    ui.paused = true
                end
            end,

            onkeypress(GLFW.KEY_V, desc = "Toggle video recording") do s, ev
                isnothing(e.ffmpeghandle) ? startrecord!(e) : finishrecord!(e)
            end,

            onevent(ButtonPress) do s, ev
                if !ismiddle(ev.button) && s.control && pert[].select > 0
                    newperturb = s.right ? Int(MJCore.mjPERT_TRANSLATE) : Int(MJCore.mjPERT_ROTATE)
                    # perturbation onset: reset reference
                    iszero(pert[].active) && mjv_initPerturb(sim.m, sim.d, ui.scn, pert)
                    pert[].active = newperturb
                end
            end,

            onevent(ButtonRelease) do s, ev
                isright(ev.button) || isleft(ev.button) && (pert[].active = 0)
            end,

            onscroll(desc = "Zoom camera") do s, ev
                mjv_moveCamera(
                    sim.m,
                    MJCore.mjMOUSE_ZOOM,
                    0.0,
                    0.05 * ev.dy,
                    ui.scn,
                    ui.cam,
                )
            end,

            onkeypress(
                GLFW.KEY_UP,
                MOD_SHIFT,
                desc = "Increase sim rate in speedmode",
            ) do s, ev
                if ui.speedmode
                    ui.speedfactor *= 2
                    setrate!(phys.timer, ui.speedfactor)
                else
                    setrate!(phys.timer, 1)
                end
            end,
            onkeypress(
                GLFW.KEY_DOWN,
                MOD_SHIFT,
                desc = "Decrease sim rate in speedmode",
            ) do s, ev
                if ui.speedmode
                    ui.speedfactor /= 2
                    setrate!(phys.timer, ui.speedfactor)
                else
                    setrate!(phys.timer, 1)
                end
            end,

            onevent(MouseDrag) do s, ev
                move_pert_or_cam(ui, phys, s, ev)
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