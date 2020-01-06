module LyceumMuJoCoViz

using Base: RefValue
import GLFW
using GLFW: Window, Key, Action, MouseButton
using BangBang: @set!!
using MuJoCo, MuJoCo.MJCore
using LyceumMuJoCo, LyceumBase
using StaticArrays: SVector, MVector
using Printf
using Observables
using FFMPEG
import LyceumBase: reset!

const FONTSCALE = MJCore.FONTSCALE_150 # can be 100, 150, 200
const MAXGEOM = 10000 # preallocated geom array in mjvScene
const SYNCMISALIGN = 0.1  # maximum time mis-alignment before re-sync

const MAXRUNLENGTH_SECONDS = 1 / 60
const Maybe{T} = Union{T,Nothing}

export visualize


mutable struct PhysicsState{T<:Union{MJSim,AbstractMuJoCoEnv}}
    model::T
    pert::RefValue{mjvPerturb}
    paused::Bool
    shouldexit::Bool
    lock::ReentrantLock

    function PhysicsState(model::Union{MJSim,AbstractMuJoCoEnv})
        pert = Ref(mjvPerturb())
        mjv_defaultPerturb(pert)
        new{typeof(model)}(model, pert, true, false, ReentrantLock())
    end
end

Base.@kwdef mutable struct UIState
    scn::RefValue{mjvScene} = Ref(mjvScene())
    cam::RefValue{mjvCamera} = Ref(mjvCamera())
    vopt::RefValue{mjvOption} = Ref(mjvOption())
    con::RefValue{mjrContext} = Ref(mjrContext())
    figsensor::RefValue{mjvFigure} = Ref(mjvFigure())

    showhelp::Bool = true
    showinfo::Bool = true
    showsensor::Bool = false
    speedmode::Bool = false
    speedfactor::Float64 = 1 / 10
    reversed::Bool = false

    msgbuf::IOBuffer = IOBuffer()
    miscbuf::IOBuffer = IOBuffer()
end

function alignscale!(ui::UIState, sim::MJSim)
    ui.cam[].lookat = sim.m.stat.center
    ui.cam[].distance = 1.5 * sim.m.stat.extent
    ui.cam[].type = MJCore.mjCAMERA_FREE
    ui
end

msg!(ui::UIState, msg::String, info = false) = (println(ui.msgbuf, msg); info && @info msg)

include("util.jl")
include("glfw.jl")
include("modes.jl")


####
#### Main engine
####

mutable struct Engine{T,M<:Tuple}
    phys::PhysicsState{T}
    ui::UIState
    mngr::WindowManager

    handlerdescription::String

    modes::M
    modehandlers::Vector{AbstractEventHandler}
    modehandlerdescription::String
    curmodeidx::Int

    timer::RateTimer

    ffmpeghandle::Maybe{Base.Process}
    ffmpegdst::Maybe{String}
    vidframe::Vector{UInt8}

    function Engine(model::Union{MJSim,AbstractMuJoCoEnv}, modes::EngineMode...)
        window = create_window("LyceumMuJoCoViz")
        try
            phys = PhysicsState(model)
            ui = UIState()
            mngr = WindowManager(window)

            mjv_defaultScene(ui.scn)
            mjv_defaultCamera(ui.cam)
            mjv_defaultOption(ui.vopt)
            mjr_defaultContext(ui.con)
            mjv_defaultFigure(ui.figsensor)

            sim = getsim(model)
            mjv_makeScene(sim.m, ui.scn, MAXGEOM)
            mjr_makeContext(sim.m, ui.con, FONTSCALE)

            alignscale!(ui, sim)
            init_figsensor!(ui.figsensor)

            io = IOBuffer()

            curhandlers = handlers(ui, phys, modes[1])
            if isnothing(curhandlers)
                curhandlers = AbstractEventHandler[]
                modehandlerdesc = ""
            else
                modehandlerdesc = String(take!(writedescription!(io, curhandlers)))
            end

            engine = new{typeof(model),typeof(modes)}(
                phys,
                ui,
                mngr,
                "",
                modes,
                curhandlers,
                modehandlerdesc,
                1,
                RateTimer(),
                nothing,
                nothing,
                UInt8[],
            )

            enginehandlers = handlers(engine)
            enginehandlers = convert(Vector{<:AbstractEventHandler}, enginehandlers)
            writedescription!(io, enginehandlers)
            engine.handlerdescription = String(take!(io))

            register!(mngr, enginehandlers)
            on((_) -> render!(engine), mngr.events.windowrefresh)
            on((o) -> default_mousecb(engine, o.state, o.event), mngr.events.doubleclick)
            return engine
        catch e
            GLFW.DestroyWindow(window)
            rethrow(e)
        end
    end
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

    if phys.model isa AbstractMuJoCoEnv
        name = string(Base.nameof(typeof(phys.model)))
        reward = getreward(phys.model)
        eval = geteval(phys.model)
        @printf io "%s: Reward=%.3f  Eval=%.3f\n" name reward eval
    end

    if phys.paused
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
        MJCore.CGlobals.mjFRAMESTRING[e.ui.vopt[].frame+1],
    )
    println(
        io,
        "Label rendering mode: ",
        MJCore.CGlobals.mjLABELSTRING[e.ui.vopt[].label+1],
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

    mjr_overlay(MJCore.FONT_SHADOW, MJCore.GRID_TOPLEFT, rect, info1, info2, e.ui.con)
    rect
end



function startrecord!(e::Engine)
    window = e.mngr.state.window
    SetWindowAttrib(window, GLFW.RESIZABLE, 0)
    w, h = GLFW.GetFramebufferSize(window)
    resize!(e.vidframe, 3 * w * h)
    vmode = GLFW.GetVideoMode(GLFW.GetPrimaryMonitor())
    e.ffmpeghandle, e.ffmpegdst = startffmpeg(w, h, vmode.refreshrate)
    #msg!(e.ui, "Saving video to $(e.ffmpegdst).mp4. Window resizing temporarily disabled.", true) # TODO
    @info "Saving video to $(e.ffmpegdst).mp4. Window resizing temporarily disabled"
    e
end
function recordframe!(e::Engine, rect)
    #msg!(e.ui, "Saving video to $(e.ffmpegdst).mp4. Window resizing temporarily disabled.")
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



include("defaulthandlers.jl")



function prepare!(e::Engine)
    ui, phys = e.ui, e.phys
    mjv_updateScene(
        getsim(phys.model).m,
        getsim(phys.model).d,
        ui.vopt,
        phys.pert,
        ui.cam,
        MJCore.mjCAT_ALL,
        ui.scn,
    )
    prepare!(ui, phys, mode(e))
    e
end

function render!(e::Engine)
    w, h = GLFW.GetFramebufferSize(e.mngr.state.window)
    rect = mjrRect(Cint(0), Cint(0), Cint(w), Cint(h))
    smallrect = mjrRect(Cint(0), Cint(0), Cint(w), Cint(h))

    mjr_render(rect, e.ui.scn, e.ui.con)

    postrender!(e.ui, mode(e))
    e.ui.showhelp && showhelp!(rect, e)
    !isnothing(e.ffmpeghandle) && recordframe!(e, rect)
    e.ui.showinfo && showinfo!(rect, e)

    GLFW.SwapBuffers(e.mngr.state.window)
    e
end

# TODO remove try/catch once stable b/c perf
function runmode!(e::Engine)
    phys = e.phys
    reset!(e.timer)
    elapsedsim = 0
    while !phys.shouldexit
        lock(phys.lock)
        try
            curmode = mode(e)
            worldt = time(e.timer)
            wallt = time()
            sim = getsim(phys.model)
            dt = timestep(sim)

            # TODO yes, this is a funkly loop, and should be revisited
            # conditioning the loop/branches on e.ui.reversed results in some
            # odd deadlock
            if phys.paused
                pausestep!(phys, curmode)
            elseif elapsedsim > worldt
                while abs(elapsedsim - worldt) > SYNCMISALIGN &&
                      (time() - wallt) < MAXRUNLENGTH_SECONDS
                    reversestep!(phys, curmode)
                    worldt = time(e.timer)
                    elapsedsim -= dt
                end
            else
                while abs(elapsedsim - worldt) > SYNCMISALIGN &&
                      (time() - wallt) < MAXRUNLENGTH_SECONDS
                    forwardstep!(phys, curmode)
                    worldt = time(e.timer)
                    elapsedsim += dt
                end
            end
        catch e
            phys.shouldexit = true
            rethrow(e)
        finally
            unlock(phys.lock)
        end
        sleep(0.0001) # TODO adaptive sleep? Or a "shouldrender" flag
    end
    e
end

function runrender!(engine::Engine)
    lck = engine.phys.lock
    try
        while !(GLFW.WindowShouldClose(engine.mngr.state.window) || engine.phys.shouldexit)
            t = time()
            lock(lck)
            try
                GLFW.PollEvents()
                prepare!(engine)
                unlock(lck)
                render!(engine)
            catch e
                engine.phys.shouldexit = true
                rethrow(e)
            finally
                islocked(lck) &&
                current_task() === lck.locked_by && unlock(engine.phys.lock)
            end
            sleep(0.0001)
        end
    finally
        engine.phys.shouldexit = true
        GLFW.DestroyWindow(engine.mngr.state.window)
    end
    engine
end


function Base.run(engine::Engine)
    prepare!(engine)
    render!(engine)
    GLFW.ShowWindow(engine.mngr.state.window)
    task = Threads.@spawn runmode!(engine)
    runrender!(engine)
    wait(task)
    engine
end

function visualize(
    model::Union{MJSim,AbstractMuJoCoEnv};
    trajectories::Maybe{AbstractVector{<:AbstractMatrix}} = nothing,
    controller = nothing,
)
    modes = EngineMode[PassiveDynamics()]
    !isnothing(trajectories) && push!(modes, Playback{typeof(trajectories)}(trajectories))
    !isnothing(controller) && push!(modes, Controller(controller))
    reset!(model)
    eng = Engine(model, modes...)
    run(eng)
    nothing
end

end # module
