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

function startffmpeg(w::Integer, h::Integer, rate::Integer)
    w > 0 && h > 0 && rate > 0 || error("w, h, and rate must be > 0")

    dst = tempname()
    outrate = min(rate, 30) # max out at 30 FPS
    arg = `-y -f rawvideo -pixel_format rgb24 -video_size $(w)x$(h) -framerate $rate -use_wallclock_as_timestamps true -i pipe:0 -c:v libx264 -preset ultrafast -tune animation -crf 27 -vf "vflip" -r $outrate $(dst).mp4`

    withenv(FFMPEG.execenv) do
        in = Base.PipeEndpoint()
        p = Base._spawn(`$(FFMPEG.ffmpeg) $arg`, Any[in, devnull, devnull])
        p.in = in
        return p, dst
    end
end

function safe_unlock(lck::ReentrantLock)
    if islocked(lck) && current_task() === lck.locked_by
        unlock(lck)
    end
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

@inline function str2unicode(s::AbstractString)
    length(s) == 1 || error("s must be a single length string")
    Int(first(s))
end