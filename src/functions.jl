function alignscale!(ui::UIState, sim::MJSim)
    ui.cam[].lookat = sim.m.stat.center
    ui.cam[].distance = 1.5 * sim.m.stat.extent
    ui.cam[].type = MJCore.mjCAMERA_FREE
    ui
end

mode(e::Engine, idx = e.curmodeidx) = e.modes[idx]

function switchmode!(e::Engine, idx::Integer)
    io = e.ui.miscbuf

    teardown!(e.ui, e.phys, mode(e))
    deregister!(e.mngr, e.modehandlers)

    newhandlers = handlers(e.ui, e.phys, mode(e, idx))
    if isnothing(newhandlers)
        e.modehandlerdescription = ""
        e.modehandlers = AbstractEventHandler[]
    else
        seekstart(io)
        writedescription!(io, newhandlers)
        e.modehandlerdescription = String(take!(io))
        register!(e.mngr, newhandlers)
        e.modehandlers = newhandlers
    end
    e.curmodeidx = idx
    setup!(e.ui, e.phys, mode(e))

    e
end

function showinfo!(rect::MJCore.mjrRect, e::Engine)
    io, ui, phys = e.ui.miscbuf, e.ui, e.phys
    sim = getsim(phys.model)
    seekstart(io)

    if phys.model isa AbstractMuJoCoEnvironment
        name = string(Base.nameof(typeof(phys.model)))
        reward = getreward(phys.model)
        eval = geteval(phys.model)
        @printf io "%s: Reward=%.3f  Eval=%.3f\n" name reward eval
    end

    if ui.paused
        print(io, "Paused")
    elseif ui.reversed
        print(io, "Reverse Simulation")
    else
        print(io, "Forward Simulation")
    end
    @printf io " Time (s): %.3f\n" time(sim)

    if ui.speedmode
        if ui.speedfactor < 1
            @printf io " (%.2fx slower than realtime)\n" 1 / ui.speedfactor
        else
            @printf io " (%.2fx faster than realtime)\n" ui.speedfactor
        end
    end

    println(
        io,
        "Frame rendering mode: ",
        MJCore.mjFRAMESTRING[e.ui.vopt[].frame+1],
    )
    println(
        io,
        "Label rendering mode: ",
        MJCore.mjLABELSTRING[e.ui.vopt[].label+1],
    )
    println(io)


    println(io, "Engine Mode: $(nameof(mode(e))).")
    modeinfo(io, ui, phys, mode(e))
    println(io, "Options:")
    write(io, e.modehandlerdescription)
    infostr = chomp(String(take!(io)))

    # TODO revist this
    #if e.ui.msgbuf.size > 0
    #    println(io, "Messages:")
    #    write(io, take!(e.ui.msgbuf))
    #    msgstr = chomp(String(take!(io)))
    #else
    #    msgstr = ""
    #end
    msgstr = ""

    mjr_overlay(
        MJCore.FONT_NORMAL,
        MJCore.GRID_BOTTOMLEFT,
        rect,
        string(chomp(infostr)),
        string(chomp(msgstr)),
        ui.con,
    )
    rect
end

function writedescription!(io, handlers::Vector{<:AbstractEventHandler})
    for handler in handlers
        !isnothing(handler.description) && println(io, handler.description)
    end
end

function showhelp!(rect::MJCore.mjrRect, e::Engine)
    io = e.ui.miscbuf
    seekstart(io)
    write(io, e.handlerdescription)
    helparr = split(String(take!(io)), '\n')
    n = i = 0
    l = length(helparr)
    while n < 450
        i += 1
        s = helparr[i]
        n += length(s)
    end
    i = max(1, i - 1)
    info1 = join(view(helparr, 1:i), '\n')
    info2 = join(view(helparr, min(l, (i + 1)):l), '\n')

    mjr_overlay(MJCore.FONT_NORMAL, MJCore.GRID_TOPLEFT, rect, info1, info2, e.ui.con)
    rect
end



function startrecord!(e::Engine)
    window = e.mngr.state.window
    SetWindowAttrib(window, GLFW.RESIZABLE, 0)
    w, h = GLFW.GetFramebufferSize(window)
    resize!(e.vidframe, 3 * w * h)
    vmode = GLFW.GetVideoMode(GLFW.GetPrimaryMonitor())
    e.ffmpeghandle, e.ffmpegdst = startffmpeg(w, h, vmode.refreshrate)
    @info "Saving video to $(e.ffmpegdst).mp4. Window resizing temporarily disabled"
    e
end

function recordframe!(e::Engine, rect)
    mjr_readPixels(e.vidframe, C_NULL, rect, e.ui.con)
    write(e.ffmpeghandle, e.vidframe)
    e
end

function finishrecord!(e::Engine)
    close(e.ffmpeghandle)
    SetWindowAttrib(e.mngr.state.window, GLFW.RESIZABLE, 1)
    e.ffmpeghandle = e.ffmpegdst = nothing
    @info "Finished! Window resizing re-enabled."
    e
end