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
