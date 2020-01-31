const STEPSPERKEY = 1
const SHIFTSTEPSPERKEY = 50

#action = Int(MJCore.mjMOUSE_MOVE_V)
#if buttonright
#    action = shift ? Int(MJCore.mjMOUSE_MOVE_H) : Int(MJCore.mjMOUSE_MOVE_V)
#elseif buttonleft
#    action = shift ? Int(MJCore.mjMOUSE_ROTATE_H) : Int(MJCore.mjMOUSE_ROTATE_V)
#else
#    action = Int(MJCore.mjMOUSE_ZOOM)
#end

#function move_pert_or_cam(ui::UIState, phys::PhysicsState, dx, dy, width, height, action::MJCore.mjtMouse)
function move_pert_or_cam(
    ui::UIState,
    phys::PhysicsState,
    state::WindowState,
    event::MouseDrag,
)
    if state.right
        action = state.shift ? MJCore.mjMOUSE_MOVE_H : MJCore.mjMOUSE_MOVE_V
    elseif state.left
        action = state.shift ? MJCore.mjMOUSE_ROTATE_H : MJCore.mjMOUSE_ROTATE_V
    else
        action = MJCore.mjMOUSE_ZOOM
    end

    # TODO width?
    sim = getsim(phys.model)
    scaled_dx, scaled_dy = event.dx / state.height, event.dy / state.height
    if iszero(phys.pert[].active)
        mjv_moveCamera(sim.m, action, scaled_dx, scaled_dy, ui.scn, ui.cam)
    else
        mjv_movePerturb(sim.m, sim.d, action, scaled_dx, scaled_dy, ui.scn, phys.pert)
    end
end

function default_mousecb(e::Engine, s::WindowState, event::Doubleclick)
    if isleft(event.button)
        selmode = 1
    elseif (ismiddle(event.button) || isright(event.button)) && s.control
        selmode = 3
    elseif isright(event.button)
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
            @warn "TRACKING"
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

function backstep_event(e)
    l1 = onkeypress(GLFW.KEY_LEFT) do state, event
        e.ui.paused && for _ = 1:STEPSPERKEY
            reversestep!(e.phys, mode(e))
        end
    end
    l2 = onevent(KeyRepeat, (s, e) -> e.key == GLFW.KEY_LEFT) do state, event
        e.ui.paused && for _ = 1:STEPSPERKEY
            reversestep!(e.phys, mode(e))
        end
    end
    l3 = onkeypress(GLFW.KEY_LEFT, MOD_SHIFT) do state, event
        e.ui.paused && for _ = 1:SHIFTSTEPSPERKEY
            reversestep!(e.phys, mode(e))
        end
    end
    l4 = onevent(KeyRepeat, (s, e) -> e.key == GLFW.KEY_LEFT && s.shift) do state, event
        e.ui.paused && for _ = 1:SHIFTSTEPSPERKEY
            reversestep!(e.phys, mode(e))
        end
    end
    MultiEventHandler(
        [l1, l2, l3, l4],
        "KEY_LEFT  Step back when paused (hold SHIFT for $(SHIFTSTEPSPERKEY) steps)",
    )
end

function forwardstep_event(e)
    r1 = onkeypress(GLFW.KEY_RIGHT) do state, event
        e.ui.paused && for _ = 1:STEPSPERKEY
            forwardstep!(e.phys, mode(e))
        end
    end
    r2 = onevent(KeyRepeat, (s, e) -> e.key == GLFW.KEY_RIGHT) do state, event
        e.ui.paused && for _ = 1:STEPSPERKEY
            forwardstep!(e.phys, mode(e))
        end
    end
    r3 = onkeypress(GLFW.KEY_RIGHT, MOD_SHIFT) do state, event
        e.ui.paused && for _ = 1:SHIFTSTEPSPERKEY
            forwardstep!(e.phys, mode(e))
        end
    end
    r4 = onevent(KeyRepeat, (s, e) -> e.key == GLFW.KEY_RIGHT && s.shift) do state, event
        e.ui.paused && for _ = 1:SHIFTSTEPSPERKEY
            forwardstep!(e.phys, mode(e))
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
            onkeypress(GLFW.KEY_F1, desc = "Toggle help") do state, event
                ui.showhelp = !ui.showhelp
            end,
            onkeypress(GLFW.KEY_F2, desc = "Toggle simulation info") do state, event
                ui.showinfo = !ui.showinfo
            end,
            onkeypress(GLFW.KEY_F11, desc = "Toggle fullscreen") do state, event
                ismax = GLFW.GetWindowAttrib(state.window, GLFW.MAXIMIZED)
                iszero(ismax) ? GLFW.MaximizeWindow(state.window) :
                GLFW.RestoreWindow(state.window)
            end,
            onkeypress(GLFW.KEY_BACKSPACE, desc = "Reset model") do _, _
                reset!(phys, mode(e))
            end,
            onkeypress(GLFW.KEY_R, desc = "Toggle reverse") do state, event
                ui.reversed = !ui.reversed
                phys.timer.rate *= -1
                resettime!(phys)
            end,
            onkeypress(GLFW.KEY_ENTER, desc = "Toggle speed mode") do state, event
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
            ) do state, event
                alignscale!(ui, sim)
            end,

            forwardstep_event(e),
            backstep_event(e),





            onkeypress(GLFW.KEY_SEMICOLON, desc = "Cycle frame mode backwards") do _, _
                ui.vopt[].frame = dec(ui.vopt[].frame, 0, Integer(MJCore.mjNFRAME) - 1)
            end,
            onkeypress(GLFW.KEY_APOSTROPHE, desc = "Cycle frame mode forward") do _, _
                ui.vopt[].frame = inc(ui.vopt[].frame, 0, Integer(MJCore.mjNFRAME) - 1)
            end,

            onkeypress(GLFW.KEY_PERIOD, desc = "Cycle label mode backwards") do _, _
                ui.vopt[].label = dec(ui.vopt[].label, 0, Integer(MJCore.mjNLABEL) - 1)
            end,
            onkeypress(GLFW.KEY_SLASH, desc = "Cycle label mode forward") do _, _
                ui.vopt[].label = inc(ui.vopt[].label, 0, Integer(MJCore.mjNLABEL) - 1)
            end,



            onkeypress(
                GLFW.KEY_PAGE_UP,
                desc = "Cycle engine mode forward",
            ) do state, event
                switchmode!(e, inc(e.curmodeidx, 1, length(e.modes)))
            end,
            onkeypress(
                GLFW.KEY_PAGE_DOWN,
                desc = "Cycle engine mode backwards",
            ) do state, event
                switchmode!(e, dec(e.curmodeidx, 1, length(e.modes)))
            end,


            onkeypress(GLFW.KEY_SPACE, desc = "Pause") do state, event
                if ui.paused
                    start!(phys.timer)
                    ui.paused = false
                else
                    stop!(phys.timer)
                    ui.paused = true
                end
            end,

            onkeypress(GLFW.KEY_V, desc = "Toggle video recording") do state, event
                isnothing(e.ffmpeghandle) ? startrecord!(e) : finishrecord!(e)
            end,

            onevent(
                ButtonPress,
                (s, e) -> !ismiddle(e.button) && s.control && pert[].select > 0,
            ) do state, event
                newperturb = state.right ? Int(MJCore.mjPERT_TRANSLATE) :
                             Int(MJCore.mjPERT_ROTATE)
                # perturbation onset: reset reference
                iszero(pert[].active) && mjv_initPerturb(sim.m, sim.d, ui.scn, pert)
                pert[].active = newperturb
            end,

            onevent(
                ButtonRelease,
                (s, e) -> isright(e.button) || isleft(e.button),
            ) do state, event
                pert[].active = 0
            end,

            onscroll(desc = "Zoom camera") do state, event
                mjv_moveCamera(
                    sim.m,
                    MJCore.mjMOUSE_ZOOM,
                    0.0,
                    0.05 * event.dy,
                    ui.scn,
                    ui.cam,
                )
            end,

            onkeypress(
                GLFW.KEY_UP,
                MOD_SHIFT,
                desc = "Increase sim rate in speedmode",
            ) do state, event
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
            ) do state, event
                if ui.speedmode
                    ui.speedfactor /= 2
                    setrate!(phys.timer, ui.speedfactor)
                else
                    setrate!(phys.timer, 1)
                end
            end,

            onevent(MouseDrag) do state, event
                move_pert_or_cam(ui, phys, state, event)
            end,
        ]
    end
end
