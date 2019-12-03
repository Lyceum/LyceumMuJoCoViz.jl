const MODSYMS = Dict{Integer,Symbol}(
    GLFW.MOD_ALT => :MOD_ALT,
    GLFW.MOD_SHIFT => :MOD_SHIFT,
    GLFW.MOD_CONTROL => :MOD_CONTROL,
    GLFW.MOD_SUPER => :MOD_SUPER,
)


function str2vec(s::String, len::Int)
    str = zeros(UInt8, len)
    str[1:length(s)] = codeunits(s)
    return str
end

function init_figsensor!(figsensor::Ref{mjvFigure})
    figsensor[].flg_extend = 1
    figsensor[].flg_barplot = 1
    figsensor[].title = str2vec("Sensor Data", length(figsensor[].title))
    figsensor[].yformat = str2vec("%.0f", length(figsensor[].yformat))
    figsensor[].gridsize = [2, 3]
    figsensor[].range = [[0 1], [-1 1]]
    figsensor
end

inc(x, min, max) = x == max ? min : x + 1
dec(x, min, max) = x == min ? max : x - 1

mutable struct RateTimer
    tlast::Float64
    elapsed::Float64
    rate::Float64
    paused::Bool
    tpaused::Float64
    RateTimer(rate) = (t = time_ns(); new(t, 0, rate, true, t))
end
RateTimer() = RateTimer(1)

function Base.time_ns(rt::RateTimer)
    rt.paused && return rt.elapsed

    tnow = time_ns()
    elapsed = tnow - rt.tlast
    rt.tlast = tnow
    rt.elapsed += elapsed * rt.rate
    rt.elapsed
end
Base.time(rt::RateTimer) = time_ns(rt) / 1e9

stop!(rt::RateTimer) = (rt.elapsed = time_ns(rt); rt.paused = true)
start!(rt::RateTimer) = (rt.tlast = time_ns(); rt.paused = false)
setrate!(rt::RateTimer, r) = rt.rate = r
LyceumBase.reset!(rt::RateTimer) = (rt.tlast = time_ns(); rt.elapsed = 0)


function burst!(
    ui::UIState,
    phys::PhysicsState,
    states::AbstractMatrix{Float64},
    n::Integer,
    t::Integer;
    gamma = 0.9995,
    alphamin = 0.05,
    alphamax = 0.55,
)
    scn = ui.scn
    T = size(states, 2)

    reset!(getsim(phys.model), view(states, :, t))
    mjv_updateScene(
        getsim(phys.model).m,
        getsim(phys.model).d,
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
        reset!(getsim(phys.model), view(states, :, tprime))
        mjv_addGeoms(
            getsim(phys.model).m,
            getsim(phys.model).d,
            ui.vopt,
            phys.pert,
            MJCore.mjCAT_DYNAMIC,
            scn,
        )
        color!(tprime)
    end

    reset!(getsim(phys.model), view(states, :, t))
end

#include("../scratch.jl")
function startffmpeg(w, h, rate)
    dst = tempname()
    arg = `-y -f rawvideo -pixel_format rgb24 -video_size $(w)x$(h) -framerate $rate -i pipe:0 -preset fast -tune animation -threads 0 -vf "vflip" $(dst).mp4`
    withenv(FFMPEG.execenv) do
        #return open(`$(FFMPEG.ffmpeg) $arg`, write=true, read=false), dst
        in = Base.PipeEndpoint()
        p = Base._spawn(`$(FFMPEG.ffmpeg) $arg`, Any[in, devnull, devnull])
        p.in = in
        return p, dst
#        p = Base._spawn(`$(FFMPEG.ffmpeg) $arg`, Any[in, stdout, stderr])

    end
end

SetWindowAttrib(window::GLFW.Window, attrib::Integer, value::Integer) = ccall(
    (:glfwSetWindowAttrib, GLFW.libglfw),
    Cvoid,
    (GLFW.Window, Cint, Cint),
    window,
    attrib,
    value,
)
