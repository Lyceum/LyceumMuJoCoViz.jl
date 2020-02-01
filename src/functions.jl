####
#### PhysicsState
####

resettime!(phys::PhysicsState) = (reset!(phys.timer); phys.elapsedsim = 0)


####
#### UIState
####

function alignscale!(ui::UIState, sim::MJSim)
    ui.cam[].lookat = sim.m.stat.center
    ui.cam[].distance = 1.5 * sim.m.stat.extent
    ui.cam[].type = MJCore.mjCAMERA_FREE
    ui
end

####
#### Engine
####

@inline mode(e::Engine, idx::Integer = e.curmodeidx) = e.modes[idx]

function switchmode!(e::Engine, idx::Integer)
    io = e.ui.miscbuf
    seekstart(io)

    teardown!(e.ui, e.phys, mode(e))
    deregister!(e.mngr, e.modehandlers...)

    e.curmodeidx = idx
    e.modehandlers = handlers(e.ui, e.phys, mode(e))
    setup!(e.ui, e.phys, mode(e))
    register!(e.mngr, e.modehandlers...)
    writedescription!(io, e.modehandlers)
    e.modehandlerdescription = String(take!(io))


    e
end

function showinfo!(rect::MJCore.mjrRect, e::Engine)
    io = e.ui.miscbuf
    ui = e.ui
    phys = e.phys
    sim = getsim(phys.model)

    seekstart(io)

    if phys.model isa AbstractMuJoCoEnvironment
        name = string(Base.nameof(typeof(phys.model)))
        @printf io "%s: Reward=%.3f  Eval=%.3f\n" name ui.reward ui.eval
    end

    if ui.paused
        print(io, "Paused")
    elseif ui.reversed
        print(io, "Reverse Simulation")
    else
        print(io, "Forward Simulation")
    end
    @printf io " Time (s): %.3f\n" time(sim)
    @printf io "Refresh Rate: %2d Hz\n" ui.refreshrate

    if ui.speedmode
        if ui.speedfactor < 1
            @printf io " (%.3fx slower than realtime)\n" 1 / ui.speedfactor
        else
            @printf io " (%.3fx faster than realtime)\n" ui.speedfactor
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
    infostr = chomp(String(take!(io)))

    mjr_overlay(
        MJCore.FONT_NORMAL,
        MJCore.GRID_BOTTOMLEFT,
        rect,
        string(chomp(infostr)),
        "",
        ui.con,
    )
    rect
end

function writedescription!(io, hs::Vector{EventHandler})
    if !isempty(hs)
        whens = String[]
        whats = String[]
        for h in hs
            if h.when !== nothing && h.what !== nothing
                push!(whens, h.when)
                push!(whats, h.what)
            elseif h.what !== nothing
                push!(whens, "----")
                push!(whats, h.what)
            end
        end
        pretty_table(io, hcat(whens, whats), ["Action", "Description"], alignment = :L)
    end

    io
end

function printdescription(e::Engine)
    println("Standard Commands:")
    print(e.handlerdescription)
    if !isempty(e.modehandlerdescription)
        println("$(nameof(mode(e))) Mode Commands:")
        print(e.modehandlerdescription)
    end
    println()
    println()
end

function startrecord!(e::Engine)
    window = e.mngr.state.window
    SetWindowAttrib(window, GLFW.RESIZABLE, 0)
    w, h = GLFW.GetFramebufferSize(window)
    resize!(e.framebuf, 3 * w * h)
    e.ffmpeghandle, dst = startffmpeg(w, h, GetRefreshRate())
    @info "Saving video to $dst. Window resizing temporarily disabled"
    e
end

function recordframe!(e::Engine, rect)
    mjr_readPixels(e.framebuf, C_NULL, rect, e.ui.con)
    write(e.ffmpeghandle, e.framebuf)
    e
end

function stoprecord!(e::Engine)
    close(e.ffmpeghandle)
    SetWindowAttrib(e.mngr.state.window, GLFW.RESIZABLE, 1)
    e.ffmpeghandle = nothing
    @info "Finished! Window resizing re-enabled."
    e
end