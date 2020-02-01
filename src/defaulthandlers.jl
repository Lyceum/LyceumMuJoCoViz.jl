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

        if iszero(p.pert[].active)
            mjv_moveCamera(sim.m, action, scaled_dx, scaled_dy, ui.scn, ui.cam)
        else
            mjv_movePerturb(sim.m, sim.d, action, scaled_dx, scaled_dy, ui.scn, p.pert)
        end
    end
end

function default_buttoncb(e::Engine, s::WindowState, ev::ButtonEvent)
    p = e.phys
    pert = p.pert
    sim = getsim(p.model)
    ui = e.ui

    if isright(ev.button) || isleft(ev.button)
        # set/unset pertubation on previously selected body
        if ispress(ev.action) && s.control && pert[].select > 0
            newpert = s.right ? Int(MJCore.mjPERT_TRANSLATE) : Int(MJCore.mjPERT_ROTATE)
            # perturbation onset: reset reference
            iszero(pert[].active) && mjv_initPerturb(sim.m, sim.d, ui.scn, pert)
            pert[].active = newpert
        elseif isrelease(ev.action)
            # stop pertubation
            pert[].active = 0
        end
    end

    if ev.isdoubleclick
        # new select: find geom and 3D click point, get corresponding body

        # stop perturbation on new select
        pert[].active = 0

        # find the selected body
        selpnt = zeros(MVector{3,Float64})
        selgeom, selskin = Ref(Cint(0)), Ref(Cint(0))
        selbody = mjv_select(
            sim.m,
            sim.d,
            ui.vopt,
            s.width / s.height,
            s.x / s.width,
            (s.height - s.y) / s.height,
            ui.scn,
            selpnt,
            selgeom,
            selskin,
        )

        if isleft(ev.button) && nomod(s)
            if selbody >= 0
                # set body selection (including world body)

                # compute localpos
                tmp = selpnt - sim.d.xpos[:, selbody+1] # TODO
                res = reshape(sim.d.xmat[:, selbody+1], 3, 3)' * tmp
                pert[].localpos = SVector{3}(res)

                # record selection
                pert[].select = selbody
                pert[].skinselect = selskin[]
            else
                # no body selected, unset selection
                pert[].select = 0
                pert[].skinselect = -1
            end
        elseif isright(ev.button)
            # set camera to look at selected body (including world body)
            selbody >= 0 && (ui.cam[].lookat = selpnt)

            if s.control && selbody > 0
                # also set camera to track selected body (excluding world body)
                ui.cam[].type = Int(MJCore.mjCAMERA_TRACKING)
                ui.cam[].trackbodyid = selbody
                ui.cam[].fixedcamid = -1
            end
        end
    end
end

function default_scrollcb(e::Engine, s::WindowState, ev::ScrollEvent)
    m = getsim(e.phys.model).m
    mjv_moveCamera(m, MJCore.mjMOUSE_ZOOM, 0.0, 0.05 * ev.dy, e.ui.scn, e.ui.cam)
end

function handlers(e::Engine)
    let e = e, ui = e.ui, p = e.phys
        return [
            ####
            #### Mouse
            ####

            onevent(ButtonEvent) do s, ev
                default_buttoncb(e, s, ev)
            end,

            onevent(MouseMoveEvent) do s, ev
                default_mousemovecb(e, s, ev)
            end,

            onscroll(what = "Zoom camera") do s, ev
                default_scrollcb(e, s, ev)
            end,


            ####
            #### Keys
            ####

            onkey(GLFW.KEY_F1, what = "Show help message") do s, ev
                ispress_or_repeat(ev.action) && printdescription(e)
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

            onkey(GLFW.KEY_ENTER, what = "Toggle speed mode") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.speedmode = !ui.speedmode
                    setrate!(p.timer, ui.speedmode ? ui.speedfactor : 1)
                end
            end,

            onkey(GLFW.KEY_ESCAPE, what = "Quit") do s, ev
                ispress_or_repeat(ev.action) && (ui.shouldexit = true)
            end,

            onkey(GLFW.KEY_A, MOD_CONTROL, what = "Align camera scale") do s, ev
                ispress_or_repeat(ev.action) && alignscale!(ui, getsim(p.model))
            end,

            onkey(GLFW.KEY_SPACE, what = "Pause") do s, ev
                if ispress_or_repeat(ev.action)
                    ui.paused ? start!(p.timer) : stop!(p.timer)
                    ui.paused = !ui.paused
                end
            end,

            onkey(GLFW.KEY_V, what = "Toggle video recording") do s, ev
                if ispress(ev.action)
                    isnothing(e.ffmpeghandle) ? startrecord!(e) : stoprecord!(e)
                end
            end,

            onevent(
                KeyEvent,
                what = "Step forward/back when paused (hold SHIFT for $(SHIFTSTEPSPERKEY) steps)",
                when = "$(describe(GLFW.KEY_RIGHT))/$(describe(GLFW.KEY_LEFT))"
            ) do s, ev
                if ui.paused && ispress_or_repeat(ev.action)
                    steps = s.shift ? 50 : 1
                    if ev.key == GLFW.KEY_RIGHT
                        for _ = 1:steps
                            forwardstep!(p, mode(e))
                        end
                    elseif ev.key == GLFW.KEY_LEFT
                        for _ = 1:steps
                            reversestep!(p, mode(e))
                        end
                    end
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


            onkey(GLFW.KEY_PAGE_UP, what = "Cycle engine mode forward") do s, ev
                ispress_or_repeat(ev.action) && switchmode!(e, inc(e.curmodeidx, 1, length(e.modes)))
            end,

            onkey(GLFW.KEY_PAGE_DOWN, what = "Cycle engine mode backwards") do s, ev
                ispress_or_repeat(ev.action) && switchmode!(e, dec(e.curmodeidx, 1, length(e.modes)))
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


            #gen_mjflag_handlers(ui)...
        ]
    end
end

#function gen_mjflag_handlers(ui::UIState)
#    handlers = EventHandler[]
#    vopt = ui.vopt
#    scn = ui.scn
#
#    for i=1:Int(MJCore.mjNVISFLAG)
#        key = glfw_lookup_key(MJCore.mjVISSTRING[3, i])
#        name = MJCore.mjVISSTRING[1, i]
#        h = onkey(key, what = "Toggle $name Viz Flag") do s, ev
#            ispress_or_repeat(ev.action) && (vopt[].flags = _toggleflag(vopt[].flags, i))
#        end
#        push!(handlers, h)
#    end
#
#    for i=1:Int(MJCore.mjNRNDFLAG)
#        key = glfw_lookup_key(MJCore.mjRNDSTRING[3, i])
#        name = MJCore.mjRNDSTRING[1, i]
#        h = onkey(key, what = "Toggle $name Render Flag") do s, ev
#            ispress_or_repeat(ev.action) && (scn[].flags = _toggleflag(scn[].flags, i))
#        end
#        push!(handlers, h)
#    end
#
#    h = onevent(KeyEvent, what = "Toggle Group Groups 1-$(Int(MJCore.mjNGROUP)))") do s, ev
#        i = Int(ev.key) - Int('0')
#        if ispress_or_repeat(ev.action) && iszero(modbits(s)) && checkbounds(Bool, vopt[].geomgroup, i)
#            vopt[].geomgroup = _toggleflag(vopt[].geomgroup, i)
#        end
#    end
#    push!(handlers, h)
#
#    h = onevent(KeyEvent, what = "Toggle Site Groups 1-$(Int(MJCore.mjNGROUP)))") do s, ev
#        i = Int(ev.key) - Int('0')
#        if ispress_or_repeat(ev.action) && isshift(modbits(s)) && checkbounds(Bool, vopt[].sitegroup, i)
#            vopt[].sitegroup = _toggleflag(vopt[].sitegroup, i)
#        end
#    end
#    push!(handlers, h)
#
#    handlers
#end
#
#@inline function _toggleflag(A::SVector{N,MJCore.mjtByte}, i::Integer) where {N}
#    A = MVector(A)
#    A[i] = ifelse(A[i] > 0, 0, 1)
#    SVector(A)
#end