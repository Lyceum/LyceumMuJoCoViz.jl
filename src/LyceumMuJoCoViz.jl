module LyceumMuJoCoViz

using Base: RefValue
import GLFW
using GLFW: Window, Key, Action, MouseButton
using BangBang: @set!!
using MuJoCo, MuJoCo.MJCore
using LyceumMuJoCo, LyceumBase
import LyceumMuJoCo: reset!
using StaticArrays: SVector, MVector
using Printf
using DocStringExtensions
using Observables
using FFMPEG

const FONTSCALE = MJCore.FONTSCALE_150 # can be 100, 150, 200
const MAXGEOM = 10000 # preallocated geom array in mjvScene
const MIN_REFRESHRATE = 30 # minimum effective refreshrate

const Maybe{T} = Union{T,Nothing}

export visualize


mutable struct PhysicsState{T<:Union{MJSim,AbstractMuJoCoEnvironment}}
    model::T
    pert::RefValue{mjvPerturb}
    paused::Bool
    shouldexit::Bool
    lock::Threads.SpinLock

    function PhysicsState(model::Union{MJSim,AbstractMuJoCoEnvironment})
        pert = Ref(mjvPerturb())
        mjv_defaultPerturb(pert)
        new{typeof(model)}(model, pert, true, false, Threads.SpinLock())
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

    lastrender::Float64 = time()
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

    function Engine(model::Union{MJSim,AbstractMuJoCoEnvironment}, modes::EngineMode...)
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

    if phys.model isa AbstractMuJoCoEnvironment
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



function runmode!(e::Engine)
    phys = e.phys
    reset!(e.timer)
    dt = timestep(phys.model)
    elapsedsim = zero(typeof(dt))

    try
        while !phys.shouldexit
            # TODO atomic?
            if (time() - e.ui.lastrender) > 1/MIN_REFRESHRATE
                # If current refresh rate less than minimum, then busy wait to give
                # render thread a chance to acquire lock
                continue
            else
                lock(phys.lock)

                # make sure world clock moving in right direction
                e.timer.rate = abs(e.timer.rate) * (e.ui.reversed ? -1 : 1)
                elapsedworld = time(e.timer)

                # advance sim
                if phys.paused
                    pausestep!(phys, mode(e))
                elseif e.ui.reversed && elapsedsim > elapsedworld
                    reversestep!(phys, mode(e))
                    elapsedsim -= dt
                elseif !e.ui.reversed && elapsedsim < elapsedworld
                    forwardstep!(phys, mode(e))
                    elapsedsim += dt
                end

                unlock(phys.lock)
            end
        end
    finally
        e.phys.shouldexit = true
        safe_unlock(phys.lock)
    end
    e
end


function renderstep!(e::Engine)
    lock(e.phys.lock)
    GLFW.PollEvents()
    prepare!(e)
    e.ui.lastrender = time()
    unlock(e.phys.lock)

    render!(e)
end

function runrender!(engine::Engine)
    lck = engine.phys.lock
    try
        while !(GLFW.WindowShouldClose(engine.mngr.state.window) || engine.phys.shouldexit)
            renderstep!(engine)
        end
    finally
        engine.phys.shouldexit = true
        safe_unlock(engine.phys.lock)
        GLFW.DestroyWindow(engine.mngr.state.window)
    end
    engine
end


function run(engine::Engine)
    renderstep!(engine) # Render initial state before showing window
    modetask = Threads.@spawn runmode!(engine)
    GLFW.ShowWindow(engine.mngr.state.window)
    runrender!(engine)
    wait(modetask)
    engine
end

"""
    $(TYPEDSIGNATURES)

Starts an interactive visualization of `model`, which can be either a valid subtype of
`AbstractMuJoCoEnvironment` or just a `MJSim` simulation. The visualizer has several
"modes" that allow you to visualize passive dynamics, play back recorded trajectories, and
run a controller interactively. The passive dynamics mode depends only on `model` and is
always available, while the other modes are specified by the keyword arguments below.

For more information, see the on-screen help menu.

# Keywords

- `trajectories::AbstractVector{<:AbstractMatrix}`: a vector of trajectories, where each
    trajectory is an AbstractMatrix of states with size `(length(statespace(model)), T)` and
    `T` is the length of the trajectory. Note that each trajectory can have different length.
- `controller`: a callback function with the signature `controller(model)`, called at each
    timestep, that that applys a control input to the system.

# Examples
```julia
using LyceumMuJoCo, LyceumMuJoCoViz
env = LyceumMuJoCo.HopperV2()
T = 100
states = Array(undef, statespace(env), T)
for t = 1:T
    step!(env)
    states[:, t] .= getstate(env)
end
visualize(
    env,
    trajectories=[states],
    controller = env -> setaction!(env, rand(actionspace(env)))
)
```
"""
function visualize(
    model::Union{MJSim,AbstractMuJoCoEnvironment};
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
