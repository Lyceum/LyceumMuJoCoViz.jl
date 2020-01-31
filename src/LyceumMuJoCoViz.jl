module LyceumMuJoCoViz

using Base: RefValue, @lock, @lock_nofail

import GLFW
using GLFW: Window, Key, Action, MouseButton
using BangBang: @set!!
using StaticArrays: SVector, MVector
using Printf: @printf
using DocStringExtensions
using Observables: AbstractObservable, Observable, on, off
import FFMPEG
using MuJoCo
using MuJoCo.MJCore
using LyceumMuJoCo
import LyceumMuJoCo: reset!
using LyceumBase
using LyceumBase: Maybe, AbsVec, AbsMat


export visualize


const FONTSCALE = MJCore.FONTSCALE_150 # can be 100, 150, 200
const MAXGEOM = 10000 # preallocated geom array in mjvScene
const MIN_REFRESHRATE = 20 # minimum effective refreshrate
const RENDERGAMMA = 0.9
const SIMGAMMA = 0.99


include("util.jl")
include("glfw.jl")
include("ratetimer.jl")
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
    e = Engine(model, modes...)
    run(e)
    nothing
end


function run(e::Engine)
    if e.phys.model isa AbstractMuJoCoEnvironment
        e.ui.reward = getreward(e.phys.model)
        e.ui.eval = geteval(e.phys.model)
    end

    # render first frame before opening window
    prepare!(e)
    render!(e)
    e.ui.refreshrate = GetRefreshRate()
    e.ui.lastrender = time()
    GLFW.ShowWindow(e.mngr.state.window)

    # run the simulation/mode in second thread
    modetask = Threads.@spawn runmode!(e)
    runrender(e)
    wait(modetask)

    nothing
end


function runrender(e::Engine)
    try
        shouldexit = false
        while !shouldexit
            @lock e.phys.lock begin
                GLFW.PollEvents()
                prepare!(e)
            end

            yield()

            render!(e)
            trender = time()

            @lock e.ui.lock begin
                e.ui.refreshrate = RENDERGAMMA * e.ui.refreshrate + (1 - RENDERGAMMA) * (1 / (trender - e.ui.lastrender))
                e.ui.lastrender = trender
                shouldexit = e.ui.shouldexit |= GLFW.WindowShouldClose(e.mngr.state.window)
            end
        end
    finally
        @lock e.ui.lock begin
            e.ui.shouldexit = true
        end
        GLFW.DestroyWindow(e.mngr.state.window)
    end

    nothing
end

function render!(e::Engine)
    w, h = GLFW.GetFramebufferSize(e.mngr.state.window)
    rect = mjrRect(Cint(0), Cint(0), Cint(w), Cint(h))
    smallrect = mjrRect(Cint(0), Cint(0), Cint(w), Cint(h))

    mjr_render(rect, e.ui.scn, e.ui.con)

    e.ui.showhelp && showhelp!(rect, e)
    e.ui.showinfo && showinfo!(rect, e)

    # should happen last to include all overlays
    !isnothing(e.ffmpeghandle) && recordframe!(e, rect)

    GLFW.SwapBuffers(e.mngr.state.window)

    e
end

function prepare!(e::Engine)
    ui, phys = e.ui, e.phys
    _maybe_reweval!(ui, phys.model)
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

_maybe_reweval!(ui, ::MJSim) = nothing
function _maybe_reweval!(ui, env::AbstractMuJoCoEnvironment)
    ui.reward = RENDERGAMMA * ui.reward + (1 - RENDERGAMMA) * getreward(env)
    ui.eval = RENDERGAMMA * ui.eval + (1 - RENDERGAMMA) * geteval(env)
    nothing
end

function runmode!(e::Engine)
    p = e.phys
    ui = e.ui

    resettime!(p) # reset sim and world clocks to 0

    try
        while true
            shouldexit, lastrender, reversed, paused = @lock_nofail ui.lock begin
                ui.shouldexit, ui.lastrender, ui.reversed, ui.paused
            end

            if shouldexit
                break
            elseif (time() - lastrender) > 1/MIN_REFRESHRATE
                # If current refresh rate less than minimum, then yield to give
                # render thread a chance to acquire lock
                yield()
                continue
            else
                @lock p.lock begin
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

    nothing
end

end # module
