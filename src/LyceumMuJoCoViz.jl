module LyceumMuJoCoViz

using Base: RefValue, @lock, @lock_nofail

import GLFW
using GLFW: Window, Key, Action, MouseButton
using BangBang: @set!!
using StaticArrays: SVector, MVector
using Printf
using DocStringExtensions
using Observables
using FFMPEG

using MuJoCo, MuJoCo.MJCore
using LyceumMuJoCo, LyceumBase
import LyceumMuJoCo: reset!

const FONTSCALE = MJCore.FONTSCALE_150 # can be 100, 150, 200
const MAXGEOM = 10000 # preallocated geom array in mjvScene
const MIN_REFRESHRATE = 30 # minimum effective refreshrate

const Maybe{T} = Union{T,Nothing}

export visualize

include("util.jl")
include("glfw.jl")
include("types.jl")
include("functions.jl")
include("modes.jl")
include("defaulthandlers.jl")


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


function run(eng::Engine)
    pausestep!(eng.phys, mode(eng))
    renderstep!(eng)

    modetask = Threads.@spawn runmode!(eng)

    GLFW.ShowWindow(eng.mngr.state.window)

    runrender!(eng)
    wait(modetask)
    eng
end


function runrender!(eng::Engine)
    lck = eng.phys.lock
    try
        while !(GLFW.WindowShouldClose(eng.mngr.state.window) || eng.ui.shouldexit)
            renderstep!(eng)
        end
    finally
        eng.ui.shouldexit = true
        safe_unlock(eng.phys.lock)
        GLFW.DestroyWindow(eng.mngr.state.window)
    end
    eng
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

    @lock e.ui.lock begin
        e.ui.lastrender = time()
    end

end

function renderstep!(e::Engine)
    @lock e.phys.lock begin
        GLFW.PollEvents()
        prepare!(e)
    end
    render!(e)
end

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


function runmode!(e::Engine)
    p = e.phys
    ui = e.ui

    reset!(p.timer)
    p.elapsedsim = 0

    try
        while true
            shouldexit, lastrender, reversed, paused = @lock_nofail ui.lock begin
                ui.shouldexit, ui.lastrender, ui.reversed, ui.paused
            end

            if shouldexit
                break
            elseif (time() - lastrender) > 1/MIN_REFRESHRATE
                # If current refresh rate less than minimum, then busy wait to give
                # render thread a chance to acquire lock
                continue
            else
                @lock p.lock begin
                    # make sure world clock moving in right direction
                    p.timer.rate = abs(p.timer.rate) * (reversed ? -1 : 1)
                    elapsedworld = time(p.timer)

                    # advance sim
                    if ui.paused
                        pausestep!(p, mode(e))
                    elseif ui.reversed && p.elapsedsim > elapsedworld
                        reversestep!(p, mode(e))
                        p.elapsedsim -= timestep(p.model)
                    elseif !ui.reversed && p.elapsedsim < elapsedworld
                        forwardstep!(p, mode(e))
                        p.elapsedsim += timestep(p.model)
                    end
                end
            end
        end
    finally
        @lock ui.lock begin
            ui.shouldexit = true
        end
    end
    e
end





end # module
