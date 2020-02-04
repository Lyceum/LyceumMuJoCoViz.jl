####
#### EngineMode
####

# required
forwardstep!(phys, ::EngineMode) = error("must implement")
function reversestep!(phys, m::EngineMode)
    supportsreverse(m) ? error("must implement") : nothing
end

# optional
pausestep!(phys, ::EngineMode) = nothing
reset!(phys, ::EngineMode) = reset!(phys.model)
nameof(m::EngineMode) = string(Base.nameof(typeof(m)))
setup!(ui, phys, ::EngineMode) = nothing
teardown!(ui, phys, ::EngineMode) = nothing
prepare!(ui, phys, ::EngineMode) = nothing
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


####
#### PassiveDynamics
####

struct PassiveDynamics <: EngineMode end
forwardstep!(p::PhysicsState, ::PassiveDynamics) = forwardstep!(p)


####
#### Controller
####

mutable struct Controller{F} <: EngineMode
    controller::F
    realtimefactor::Float64
end
Controller(controller) = Controller(controller, 1.0)

function setup!(ui, phys, x::Controller)
    dt = @elapsed x.controller(phys.model);
    x.realtimefactor = timestep(phys.model) / dt
end
teardown!(ui, phys, x::Controller) = zerofullctrl!(getsim(phys.model))

function forwardstep!(p::PhysicsState, x::Controller)
    dt = @elapsed x.controller(p.model);
    rt = timestep(p.model) / dt
    x.realtimefactor = SIMGAMMA * x.realtimefactor + (1 - SIMGAMMA) * rt
    forwardstep!(p)
end

function modeinfo(io, ui, phys, x::Controller)
    @printf io "Realtime Factor: %.2fx\n" x.realtimefactor
end


####
#### Playback
####

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

function setup!(ui::UIState, phys::PhysicsState, p::Playback)
    traj, state, T = getcurrent(p)
    LyceumMuJoCo.setstate!(phys.model, state)
    par = burstmodeparams(phys, traj)
    p.burstfactor = par.minburst + (par.maxburst - par.minburst) / 4
end

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
        n = clamp(round(Int, p.burstfactor * T), 2, T)
        burst!(ui, phys, traj, n, p.t, gamma = p.burstgamma)
    end
end

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
            desc = "Toggle burst mode: render snapshots of entire trajectory",
        ) do state, event
            p.burstmode = !p.burstmode
        end,
        onscroll(MOD_CONTROL, desc = "Change burst factor") do state, event
            traj, state, T = getcurrent(p)
            par = burstmodeparams(phys, traj)
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
            p.t = checkbounds(Bool, p.trajectories[p.k], :, p.t) ? p.t : firstindex(p.trajectories[p.k])
            setstate!(p, phys, p.k, p.t)
        end,
        onkeypress(
            GLFW.KEY_DOWN,
            desc = "Cycle backwards through trajectories",
        ) do state, event
            p.k = dec(p.k, 1, length(p.trajectories))
            p.t = checkbounds(Bool, p.trajectories[p.k], :, p.t) ? p.t : firstindex(p.trajectories[p.k])
            setstate!(p, phys, p.k, p.t)
        end,
    ]
end

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

function setstate!(p::Playback, phys, k, t)
    LyceumMuJoCo.setstate!(phys.model, view(p.trajectories[p.k], :, p.t))
end

function getcurrent(p::Playback)
    traj = p.trajectories[p.k]
    traj, view(traj, :, p.t), size(traj, 2)
end

@inline getT(m::Playback) = size(m.trajectories[m.k], 2)

function burst!(
    ui::UIState,
    phys::PhysicsState,
    states::AbstractMatrix,
    n::Integer,
    t::Integer;
    gamma = 0.9995,
    alphamin = 0.05,
    alphamax = 0.55,
)
    scn = ui.scn
    T = size(states, 2)
    sim = getsim(phys.model)
    n = min(n, fld(MAXGEOM, sim.m.ngeom))

    LyceumMuJoCo.setstate!(phys.model, view(states, :, t))
    mjv_updateScene(
        sim.m,
        sim.d,
        ui.vopt,
        phys.pert,
        ui.cam,
        MJCore.mjCAT_ALL,
        scn,
    )

    maxdist = max(t - 1, T - t)
    from = scn[].ngeom + 1
    function color!(tprime)
        geoms = unsafe_wrap(Array, scn[].geoms, scn[].ngeom)
        for i = from:scn[].ngeom
            geom = geoms[i]
            if geom.category == Int(MJCore.mjCAT_DYNAMIC)
                dist = abs(tprime - t)
                alpha = gamma^dist
                r, g, b, _ = geom.rgba
                geom = @set!! geom.rgba = SVector{4,Cfloat}(r, g, b, alpha)
                geoms[i] = geom
            end
        end
        from = scn[].ngeom + 1
    end

    fromidx = scn[].ngeom + 1
    for tprime in Iterators.map(x -> round(Int, x), LinRange(1, T, n))
        tprime == t && continue
        LyceumMuJoCo.setstate!(phys.model, view(states, :, tprime))
        mjv_addGeoms(
            sim.m,
            sim.d,
            ui.vopt,
            phys.pert,
            MJCore.mjCAT_DYNAMIC,
            scn,
        )
        color!(tprime)
    end

    LyceumMuJoCo.setstate!(phys.model, view(states, :, t))
end