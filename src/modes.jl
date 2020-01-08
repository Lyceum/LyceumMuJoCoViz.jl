abstract type EngineMode end

pausestep!(phys, ::EngineMode) = error("must implement")
forwardstep!(phys, ::EngineMode) = error("must implement")
reversestep!(phys, ::EngineMode) = error("must implement")
reset!(phys, ::EngineMode) = error("must implement")

nameof(::EngineMode) = error("must implement")

setup!(ui, phys, ::EngineMode) = nothing
teardown!(ui, phys, ::EngineMode) = nothing
prepare!(ui, phys, ::EngineMode) = nothing
postrender!(ui, ::EngineMode) = nothing
handlers(ui, phys, ::EngineMode) = nothing
modeinfo(io, ui, phys, ::EngineMode) = nothing
supportsreverse(::EngineMode) = false

function pausestep!(p::PhysicsState)
    sim = getsim(p.model)
    mjv_applyPerturbPose(sim.m, sim.d, p.pert, 1)
    forward!(sim)
end
function forwardstep!(p::PhysicsState)
    sim = getsim(p.model)
    fill!(sim.d.xfrc_applied, 0)
    mjv_applyPerturbPose(sim.m, sim.d, p.pert, 0)
    mjv_applyPerturbForce(sim.m, sim.d, p.pert)
    step!(p.model)
end
reversestep!(p::PhysicsState) = nothing



struct PassiveDynamics <: EngineMode end
pausestep!(p::PhysicsState, ::PassiveDynamics) = pausestep!(p)
forwardstep!(p::PhysicsState, ::PassiveDynamics) = forwardstep!(p)
reversestep!(p::PhysicsState, ::PassiveDynamics) = reversestep!(p)
reset!(p, ::PassiveDynamics) = reset!(p.model)
nameof(::PassiveDynamics) = "Passive Dynamics"



struct Controller{F} <: EngineMode
    controller::F
end

reset!(p, ::Controller) = reset!(p.model)
nameof(::Controller) = "Controller"
teardown!(ui, phys, x::Controller) = zerofullctrl!(getsim(phys.model))
pausestep!(p::PhysicsState, x::Controller) = pausestep!(p)
forwardstep!(p::PhysicsState, x::Controller) = (x.controller(p.model); forwardstep!(p))
reversestep!(p::PhysicsState, ::Controller) = nothing



mutable struct Playback{TR<:AbstractVector{<:AbstractMatrix{<:Real}}} <: EngineMode
    trajectories::TR
    k::Int
    t::Int

    burstmode::Bool
    burstfactor::Float64
    burstgamma::Float64
    function Playback{TR}(trajectories) where {TR<:AbstractVector{<:AbstractMatrix{<:Real}}}
        new{TR}(trajectories, 1, 1, false, -1, 0.9995)
    end
end
Playback(trajectories::AbstractMatrix{<:Real}) = Playback([trajectories])

supportsreverse(::Playback) = true

function getcurrent(p::Playback)
    traj = p.trajectories[p.k]
    traj, view(traj, :, p.t), size(traj, 2)
end

getT(m::Playback) = size(m.trajectories[m.k], 2)

setstate!(p::Playback, phys, k, t) = LyceumMuJoCo.setstate!(phys.model, view(p.trajectories[p.k], :, p.t))

function burstmodeparams(phys, trajectories)
    sim = getsim(phys.model)
    (
     scrollfactor = abs(sim.m.opt.timestep) * 10,
     minburst = 2 / size(trajectories, 2),
     maxburst = min(size(trajectories, 2), MAXGEOM / (sim.m.ngeom * size(trajectories, 2))),
     mingamma = 1 - 50 * sim.m.opt.timestep,
     gammascrollfactor = abs(sim.m.opt.timestep),
    )
end

function setup!(ui::UIState, phys::PhysicsState, p::Playback)
    traj, state, T = getcurrent(p)
    LyceumMuJoCo.setstate!(phys.model, state)
    par = burstmodeparams(phys, traj)
    p.burstfactor = par.minburst + (par.maxburst - par.minburst) / 4
end

pausestep!(phys::PhysicsState, p::Playback) = nothing
function forwardstep!(phys::PhysicsState, p::Playback)
    p.t = inc(p.t, 1, getT(p))
    setstate!(p, phys, p.k, p.t)
end
function reversestep!(phys::PhysicsState, p::Playback)
    p.t = dec(p.t, 1, getT(p))
    setstate!(p, phys, p.k, p.t)
end
reset!(phys, p::Playback) = (p.t = 1; setstate!(p, phys, p.k, p.t))

function prepare!(ui::UIState, phys::PhysicsState, p::Playback)
    if p.burstmode
        traj, state, T = getcurrent(p)
        n = max(1, round(Int, p.burstfactor * T))
        burst!(ui, phys, traj, n, p.t, gamma = p.burstgamma)
    end
end

postrender!(::UIState, ::Playback) = nothing
nameof(::Playback) = "Playback"

function modeinfo(io, ui, phys, m::Playback)
    println(io, "t=$(m.t)/$(getT(m))    k=$(m.k)/$(length(m.trajectories))")
    if m.burstmode
        println(io, "Factor: $(m.burstfactor)    Gamma: $(m.burstgamma)")
    end
end

function handlers(ui::UIState, phys::PhysicsState, p::Playback)
    return [
        onkeypress(
            GLFW.KEY_B,
            desc = "Toggle burst mode (when paused): render snapshots of entire trajectory",
        ) do state, event
            p.burstmode = !p.burstmode
        end,
        onscroll(MOD_CONTROL, desc = "Change burst factor") do state, event
            traj, state, T = getcurrent(p)
            par = burstmodeparams(phys, traj)
            n = clamp(
                round(Int, p.burstfactor * size(traj, 2)),
                2,
                floor(Int, MAXGEOM / (getsim(phys.model).m.ngeom * size(traj, 2))),
            )
            p.burstfactor = clamp(
                p.burstfactor + Float64(sign(event.dy)) * par.scrollfactor,
                par.minburst,
                par.maxburst,
            )
        end,
        onscroll(MOD_SHIFT, desc = "Change burst decay rate") do state, event
            traj, state, T = getcurrent(p)
            par = burstmodeparams(phys, traj)
            p.burstgamma = clamp(
                p.burstgamma + event.dy * par.gammascrollfactor,
                par.mingamma,
                1,
            )
        end,

        onkeypress(
            GLFW.KEY_UP,
            desc = "Cycle forwards through trajectories",
        ) do state, event
            p.k = inc(p.k, 1, length(p.trajectories))
            setstate!(p, phys, p.k, p.t)
        end,
        onkeypress(
            GLFW.KEY_DOWN,
            desc = "Cycle backwards through trajectories",
        ) do state, event
            p.k = dec(p.k, 1, length(p.trajectories))
            setstate!(p, phys, p.k, p.t)
        end,


    ]
end




#struct Controller{F} <: EngineMode
#    setcontrols!::F
#    ctrl::Vector{MJCore.mjtNum}
#    qfrc_applied::Vector{MJCore.mjtNum}
#    xfrc_applied::Matrix{MJCore.mjtNum}
#    thread::Union{Nothing, Task}
#    lock::ReentrantLock
#    function Controller(setcontrols!, ctrl, qfrc_applied, xfrc_applied)
#        new(setcontrols!, ctrl, qfrc_applied, xfrc_applied, nothing, ReentrantLock())
#    end
#end
#
#reset!(p, ::Controller) = reset!(getsim(p.model))
#nameof(::Controller) = "Controller"
#
#function runcontroller!(x::Controller, phys::PhysicsState)
#    while !phys.shouldexit
#        lock(x.lock)
#        x.setcontrols!(ctrl, qfrc_applied, xfrc_applied, getsim(phys.model))
#
#        lock(phys.lock)
#        sync!(phys, x)
#        unlock(phys.lock)
#
#        unlock(x.lock)
#
#        sleep(0.001)
#    end
#end
#
#function setup!(ui::UIState, phys::PhysicsState, x::Controller)
#    x.thread = Threads.@spawn runcontroller!(x, phys)
#end
#
#function teardown!(ui::UIState, phys::PhysicsState, x::Controller)
#    wait(x.thread)
#    x.thread = nothing
#end
#
#function sync!(p::PhysicsState, x::Controller)
#    copyto!(getsim(p.model).d.ctrl, x.ctrl)
#    copyto!(getsim(p.model).d.qfrc_applied, x.qfrc_applied)
#    copyto!(getsim(p.model).d.xfrc_applied, x.xfrc_applied)
#end
#
#pausestep!(p::PhysicsState, x::Controller) = pausestep!(p)
#forwardstep!(p::PhysicsState, x::Controller) = forwardstep!(p)
#reversestep!(p::PhysicsState, ::Controller) = nothing
