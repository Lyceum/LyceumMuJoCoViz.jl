####
#### EngineMode
####

# required
forwardstep!(p, ::EngineMode) = error("must implement")

# optional
nameof(m::EngineMode) = string(Base.nameof(typeof(m)))
setup!(ui, p, ::EngineMode) = ui
teardown!(ui, p, ::EngineMode) = ui
reset!(p, ::EngineMode) = reset!(p.model)
pausestep!(p, ::EngineMode) = pausestep!(p)
reversestep!(p, ::EngineMode) = p
prepare!(ui, p, ::EngineMode) = ui
modeinfo(io, ui, p, ::EngineMode) = nothing
handlers(ui, p, ::EngineMode) = EventHandler[]


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

function setup!(ui::UIState, p::PhysicsState, x::Controller)
    dt = @elapsed x.controller(p.model)
    x.realtimefactor = timestep(p.model) / dt
end

teardown!(ui::UIState, p::PhysicsState, x::Controller) = zerofullctrl!(getsim(p.model))

function forwardstep!(p::PhysicsState, x::Controller)
    dt = @elapsed x.controller(p.model);
    rt = timestep(p.model) / dt
    x.realtimefactor = SIMGAMMA * x.realtimefactor + (1 - SIMGAMMA) * rt
    forwardstep!(p)
end

function modeinfo(io, ui::UIState, p::PhysicsState, x::Controller)
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
    bf_idx::Int
    bf_range::LinRange{Float64}
    bg_idx::Int
    bg_range::LinRange{Float64}
    function Playback{TR}(trajectories) where {TR<:AbstractVector{<:AbstractMatrix{<:Real}}}
        new{TR}(trajectories, 1, 1, false, 1, LinRange(0, 1, 2), 1, LinRange(0, 1, 2))
    end
end
Playback(trajectories::AbstractMatrix{<:Real}) = Playback([trajectories])


function setup!(ui::UIState, p::PhysicsState, m::Playback)
    setburstmodeparams!(m, p)
    setstate!(m, p)
end

reset!(p::PhysicsState, m::Playback) = (m.t = 1; setstate!(m, p))

function forwardstep!(p::PhysicsState, m::Playback)
    m.t = inc(m.t, 1, getT(m))
    setstate!(m, p)
end

function reversestep!(p::PhysicsState, m::Playback)
    m.t = dec(m.t, 1, getT(m))
    setstate!(m, p)
end

function prepare!(ui::UIState, p::PhysicsState, m::Playback)
    if m.burstmode
        bf = round(Int, m.bf_range[m.bf_idx])
        bg = m.bg_range[m.bg_idx]
        burst!(ui, p, gettraj(m), bf, m.t, gamma = bg)
    end
end

function modeinfo(io, ui::UIState, p::PhysicsState, m::Playback)
    println(io, "t=$(m.t)/$(getT(m))    k=$(m.k)/$(length(m.trajectories))")
    if m.burstmode
        n = length(m.bf_range)
        println(io, "Factor: $(m.bf_idx)/$n    Gamma: $(m.bg_idx)/$n")
    end
end

function handlers(ui::UIState, p::PhysicsState, m::Playback)
    let ui=ui, p=p, m=m
        [
            onscroll(MOD_CONTROL, what = "Change burst factor") do s, ev
                m.burstmode && (m.bf_idx = clamp(m.bf_idx + ev.dy, 1, length(m.bf_range)))
            end,

            onscroll(MOD_SHIFT, what = "Change burst decay rate") do s, ev
                m.burstmode && (m.bg_idx = clamp(m.bg_idx + ev.dy, 1, length(m.bg_range)))
            end,

            onkey(GLFW.KEY_B, what = "Toggle burst mode") do s, ev
                ispress_or_repeat(ev.action) && (m.burstmode = !m.burstmode)
            end,

            onkey(GLFW.KEY_UP, what = "Cycle forwards through trajectories") do s, ev
                if ispress_or_repeat(ev.action)
                    m.k = inc(m.k, 1, length(m.trajectories))
                    ax = axes(gettraj(m), 2)
                    checkbounds(Bool, ax, m.t) || (m.t = last(ax))
                    setburstmodeparams!(m, p)
                    setstate!(m, p)
                end
            end,

            onkey(GLFW.KEY_DOWN, what = "Cycle backwards through trajectories") do s, ev
                if ispress_or_repeat(ev.action)
                    m.k = dec(m.k, 1, length(m.trajectories))
                    ax = axes(gettraj(m), 2)
                    checkbounds(Bool, ax, m.t) || (m.t = last(ax))
                    setburstmodeparams!(m, p)
                    setstate!(m, p)
                end
            end,
        ]
    end
end

function setburstmodeparams!(m::Playback, p::PhysicsState)
    steps = 40 # n scroll increments

    # Params calibrated on cartpole and scaled accordingly
    # Rendering up to bf0_max states for a len0 length trajectory
    # with a timestep of dt0 and gamma0 looks reasonalbe.
    len0 = 100
    bf0_max = 50
    gamma0 = 0.9
    dt0 = 0.01

    dt = timestep(p.model)
    len = size(gettraj(m), 2)

    bf_max = round(Int, bf0_max * (len / len0) * (dt / dt0))
    gamma = gamma0^(dt / dt0)

    m.bf_range = LinRange{Float64}(1, bf_max, steps) # render between 1 and bf_max states
    m.bg_range = LinRange{Float64}(gamma, 1, steps)

    m.bf_idx = round(Int, round(Int, steps / 2))
    m.bg_idx = round(Int, round(Int, steps / 2))

    m
end

@inline function setstate!(m::Playback, p::PhysicsState)
    LyceumMuJoCo.setstate!(p.model, view(gettraj(m), :, m.t))
end

getT(m::Playback) = size(m.trajectories[m.k], 2)
gettraj(m::Playback) = m.trajectories[m.k]


####
#### Util
####

function burst!(
    ui::UIState,
    p::PhysicsState,
    states::AbstractMatrix,
    n::Integer,
    t::Integer;
    gamma::Real = 0.9995,
    alphamin::Real = 0.05,
    alphamax::Real = 0.55,
)
    T = size(states, 2)

    T >= n > 0 || error("n must be in range [1, size(states, 2)]")
    0 < t || error("t must be > 0")
    0 < gamma <= 1|| error("gamma must be in range (0, 1)")
    0 < alphamin <= 1 || error("alphamin must be in range (0, 1]")
    0 < alphamax <= 1 || error("alphamin must be in range (0, 1]")

    # not an error, but only the current state can be rendered so nothing to "burst"
    n == 1 && return

    scn = ui.scn
    sim = getsim(p.model)
    n = min(n, fld(MAXGEOM, sim.m.ngeom))

    LyceumMuJoCo.setstate!(p.model, view(states, :, t))
    mjv_updateScene(
        sim.m,
        sim.d,
        ui.vopt,
        p.pert,
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
                r, g, b, alpha0 = geom.rgba
                alpha = alpha0 * gamma^dist
                geom = @set!! geom.rgba = SVector{4,Cfloat}(r, g, b, alpha)
                geoms[i] = geom
            end
        end
        from = scn[].ngeom + 1
    end

    fromidx = scn[].ngeom + 1
    for tprime in Iterators.map(x -> round(Int, x), LinRange(1, T, n))
        tprime == t && continue
        LyceumMuJoCo.setstate!(p.model, view(states, :, tprime))
        mjv_addGeoms(
            sim.m,
            sim.d,
            ui.vopt,
            p.pert,
            MJCore.mjCAT_DYNAMIC,
            scn,
        )
        color!(tprime)
    end

    LyceumMuJoCo.setstate!(p.model, view(states, :, t))
end

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