abstract type EngineMode end

mutable struct PhysicsState{T<:Union{MJSim,AbstractMuJoCoEnvironment}}
    model::T
    pert::RefValue{mjvPerturb}
    elapsedsim::Float64
    timer::RateTimer
    lock::ReentrantLock

    function PhysicsState(model::Union{MJSim,AbstractMuJoCoEnvironment})
        pert = Ref(mjvPerturb())
        mjv_defaultPerturb(pert)
        new{typeof(model)}(model, pert, 0, RateTimer(), ReentrantLock())
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
    paused::Bool = true
    shouldexit::Bool = false

    reward::Float64 = 0
    eval::Float64 = 0

    lastrender::Float64 = 0
    refreshrate::Float64 = 0
    realtimerate::Float64 = 0
    msgbuf::IOBuffer = IOBuffer()
    miscbuf::IOBuffer = IOBuffer()

    lock::ReentrantLock = ReentrantLock()
end

mutable struct Engine{T,M<:Tuple}
    phys::PhysicsState{T}
    ui::UIState
    mngr::WindowManager

    handlerdescription::String

    modes::M
    modehandlers::Vector{AbstractEventHandler}
    modehandlerdescription::String
    curmodeidx::Int

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

            e = new{typeof(model),typeof(modes)}(
                phys,
                ui,
                mngr,

                "",

                modes,
                curhandlers,
                modehandlerdesc,
                1,

                nothing,
                nothing,
                UInt8[],
            )

            enginehandlers = handlers(e)
            enginehandlers = convert(Vector{<:AbstractEventHandler}, enginehandlers)
            writedescription!(io, enginehandlers)
            e.handlerdescription = String(take!(io))

            register!(mngr, enginehandlers)
            on((o) -> default_mousecb(e, o.state, o.event), mngr.events.doubleclick)
            return e
        catch e
            GLFW.DestroyWindow(window)
            rethrow(e)
        end
    end
end
