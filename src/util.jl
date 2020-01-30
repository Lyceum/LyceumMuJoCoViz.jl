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

function startffmpeg(w, h, rate)
    dst = tempname()
    outrate = min(rate, 30) # max out at 30 FPS
    arg = `-y -f rawvideo -pixel_format rgb24 -video_size $(w)x$(h) -framerate $rate -use_wallclock_as_timestamps true -i pipe:0 -preset veryfast -tune animation -crf 27 -vf "vflip" -r $outrate $(dst).mp4`

    withenv(FFMPEG.execenv) do
        in = Base.PipeEndpoint()
        p = Base._spawn(`$(FFMPEG.ffmpeg) $arg`, Any[in, devnull, devnull])
        p.in = in
        return p, dst
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

function safe_unlock(lck::ReentrantLock)
    if islocked(lck) && current_task() === lck.locked_by
        unlock(lck)
    end
end

function safe_unlock(lck::Threads.SpinLock)
    # TODO doesn't check which thread locked it
    unlock(lck)
end

"""
    spinwait(delay)

Spin in a tight loop for at least `delay` seconds.

Note this function is only accurate on the order of approximately `@elapsed time()`
seconds.
"""
@inline function spinwait(dt::Real)
    dt > 0 || error("dt must be > 0")
    t0 = time()
    while time() - t0 < dt end
    nothing
end