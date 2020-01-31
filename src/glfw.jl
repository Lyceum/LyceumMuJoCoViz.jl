const DOUBLECLICK_THRESHOLD = 0.250

const PUNCTUATION = [
    '[',
    ']',
    '{',
    '}',
    ';',
    ':',
    '\'',
    '"',
    ',',
    '<',
    '.',
    '>',
    '/',
    '?',
    '+',
    '=',
]

@enum Mod::UInt16 begin
    MOD_ALT = GLFW.MOD_ALT
    MOD_SHIFT = GLFW.MOD_SHIFT
    MOD_CONTROL = GLFW.MOD_CONTROL
    MOD_SUPER = GLFW.MOD_SUPER
end

modbits(ms::Tuple{Vararg{Mod}}) = mapreduce(Cint, |, ms)
modbits(ms::Mod...) = modbits(ms)


function SetWindowAttrib(window::Window, attrib::Integer, value::Integer)
    ccall(
        (:glfwSetWindowAttrib, GLFW.libglfw),
        Cvoid,
        (Window, Cint, Cint),
        window,
        attrib,
        value,
    )
end

@inline function GetRefreshRate(monitor::GLFW.Monitor=GLFW.GetPrimaryMonitor())
    return GLFW.GetVideoMode(monitor).refreshrate
end

function default_windowsize()
    vmode = GLFW.GetVideoMode(GLFW.GetPrimaryMonitor())
    w, h = vmode.width, vmode.height
    return (width = trunc(Int, 2 * w / 3), height = trunc(Int, 2 * h / 3))
end

function create_window(width::Integer, height::Integer, title::String)
    GLFW.WindowHint(GLFW.SAMPLES, 4)
    GLFW.WindowHint(GLFW.VISIBLE, 0)
    window = GLFW.CreateWindow(width, height, title)
    GLFW.MakeContextCurrent(window)
    GLFW.SwapInterval(1)
    return window
end
create_window(title::String) = create_window(default_windowsize()..., title)


getalt(w::Window) = GetKey(w, GLFW.KEY_LEFT_ALT) || GetKey(w, GLFW.KEY_RIGHT_ALT)
getshift(w::Window) = GetKey(w, GLFW.KEY_LEFT_SHIFT) || GetKey(w, GLFW.KEY_RIGHT_SHIFT)
getcontrol(w::Window) = GetKey(w, GLFW.KEY_LEFT_CONTROL) || GetKey(w, GLFW.KEY_RIGHT_CONTROL)
getsuper(w::Window) = GetKey(w, GLFW.KEY_LEFT_SUPER) || GetKey(w, GLFW.KEY_RIGHT_SUPER)

isleft(b::MouseButton) = b == GLFW.MOUSE_BUTTON_LEFT
ismiddle(b::MouseButton) = b == GLFW.MOUSE_BUTTON_MIDDLE
isright(b::MouseButton) = b == GLFW.MOUSE_BUTTON_RIGHT

isrelease(action::Action) = action == GLFW.RELEASE
ispress(action::Action) = action == GLFW.PRESS
isrepeat(action::Action) = action == GLFW.REPEAT

@inline modbits(ms::Tuple{Vararg{Mod}}) = mapreduce(Cint, |, ms)
@inline modbits(ms::Mod...) = modbits(ms)

isalt(key::Key) = key == GLFW.KEY_LEFT_ALT || key == GLFW.KEY_RIGHT_ALT
isshift(key::Key) = key == GLFW.KEY_LEFT_SHIFT || key == GLFW.KEY_RIGHT_SHIFT
iscontrol(key::Key) = key == GLFW.KEY_LEFT_CONTROL || key == GLFW.KEY_RIGHT_CONTROL
issuper(key::Key) = key == GLFW.KEY_LEFT_SUPER || key == GLFW.KEY_RIGHT_SUPER


function glfw_lookup_key(x::Integer)
    for key in instances(Key)
        Int(key) == x && return key
    end
    error("Key with unicode value $x not found")
end
glfw_lookup_key(s::AbstractString) = glfw_lookup_key(str2unicode(s))

function describe(x::Mod)
    if x === MOD_CONTROL
        "CTRL"
    else
        String(Symbol(x))[5:end]
    end
end

function describe(x::Key)
    c = Char(Integer(x))
    if c in PUNCTUATION
        #return "$c "
        return c
    elseif x === GLFW.KEY_ESCAPE
        return "ESC"
    else
        return String(Symbol(x))[5:end]
    end
end

function describe(x::MouseButton)
    x == GLFW.MOUSE_BUTTON_LEFT && return "LEFT_CLICK"
    x == GLFW.MOUSE_BUTTON_MIDDLE && return "MIDDLE_CLICK"
    x == GLFW.MOUSE_BUTTON_RIGHT && return "RIGHT_CLICK"
    error("unknown button $x")
end

describe(desc::String, xs...) = "$(describe(xs...))   $desc"

describe(::Nothing, xs...) = nothing

function describe(xs::Union{Key,MouseButton,Mod}...)
    ms = sort!([describe(x) for x in xs if x isa Mod])
    ks = sort!([describe(x) for x in xs if x isa MouseButton])
    bs = sort!([describe(x) for x in xs if x isa Key])
    join(vcat(ms, ks, bs), "+")
end

@inline isalt(key::Key) = key === GLFW.KEY_LEFT_ALT || key === GLFW.KEY_RIGHT_ALT
@inline isshift(key::Key) = key === GLFW.KEY_LEFT_SHIFT || key === GLFW.KEY_RIGHT_SHIFT
@inline iscontrol(key::Key) = key === GLFW.KEY_LEFT_CONTROL || key === GLFW.KEY_RIGHT_CONTROL
@inline issuper(key::Key) = key === GLFW.KEY_LEFT_SUPER || key === GLFW.KEY_RIGHT_SUPER


struct KeyPress <: Event
    key::Key
    time::Float64
end
@inline glfw_lookup_key(s::AbstractString) = glfw_lookup_key(str2unicode(s))

struct KeyRelease <: Event
    key::Key
    time::Float64
end

struct KeyRepeat <: Event
    key::Key
    time::Float64
end
KeyRepeat(key) = KeyRepeat(key, time())

    if i in PUNCTUATION
        return "\"$(c)\""
    elseif i in PRINTABLE_KEYS
        return string(c)
    elseif x === GLFW.KEY_ESCAPE
        return "ESC"
    else
        s = String(Symbol(x))
        return last(split(s, "KEY_"))
    end
end

function describe(x::MouseButton)
    x === GLFW.MOUSE_BUTTON_LEFT && return "Left Click"
    x === GLFW.MOUSE_BUTTON_MIDDLE && return "Middle Click"
    x === GLFW.MOUSE_BUTTON_RIGHT && return "Right Click"
    error("unknown button $x")
end

function describe(xs::Union{Key,MouseButton,Mod}...)
    ms = sort!([describe(x) for x in xs if x isa Mod])
    ks = sort!([describe(x) for x in xs if x isa Key])
    bs = sort!([describe(x) for x in xs if x isa MouseButton])
    return join(vcat(ms, ks, bs), "+")
end


####
#### Events
####

abstract type Event end

struct KeyEvent <: Event
    key::Key
    action::Action
    time::Float64
end

struct ButtonEvent <: Event
    button::MouseButton
    action::Action
    isdoubleclick::Bool
    time::Float64
end

struct MouseMoveEvent <: Event
    dx::Float64
    dy::Float64
    isdrag::Bool
    time::Float64
end

struct GenericEvent{T} <: Event
    x::T
    time::Float64
end


####
#### Window manager
####

mutable struct WindowState
    x::Float64
    y::Float64
    sx::Float64
    sy::Float64

    left::Bool
    middle::Bool
    right::Bool
    lastbuttonevent::Maybe{ButtonEvent}
    lastbuttonpress::Maybe{ButtonEvent}

    alt::Bool
    shift::Bool
    control::Bool
    super::Bool
    lastkeyevent::Maybe{KeyEvent}

    width::Float64
    height::Float64
    window::Window

    function WindowState(win::Window)
        x, y = GLFW.GetCursorPos(win)
        width, height = GLFW.GetWindowSize(win)
        new(
            x,
            y,
            0,
            0,

            GLFW.GetMouseButton(win, GLFW.MOUSE_BUTTON_LEFT),
            GLFW.GetMouseButton(win, GLFW.MOUSE_BUTTON_MIDDLE),
            GLFW.GetMouseButton(win, GLFW.MOUSE_BUTTON_RIGHT),
            nothing,
            nothing,

            GetKey(win, GLFW.KEY_LEFT_ALT) || GetKey(win, GLFW.KEY_RIGHT_ALT),
            GetKey(win, GLFW.KEY_LEFT_SHIFT) || GetKey(win, GLFW.KEY_RIGHT_SHIFT),
            GetKey(win, GLFW.KEY_LEFT_CONTROL) || GetKey(win, GLFW.KEY_RIGHT_CONTROL),
            GetKey(win, GLFW.KEY_LEFT_SUPER) || GetKey(win, GLFW.KEY_RIGHT_SUPER),
            nothing,

            width,
            height,
            win,
        )
    end
end

@inline function ispressed(s::WindowState, button::MouseButton)
    button === GLFW.MOUSE_BUTTON_LEFT && return s.left
    button === GLFW.MOUSE_BUTTON_MIDDLE && return s.middle
    button === GLFW.MOUSE_BUTTON_RIGHT && return s.right
    return GLFW.GetMouseButton(s.window, button)
end

@inline function modbits(s::WindowState)
    m = Cint(0)
    s.alt && (m |= Integer(MOD_ALT))
    s.shift && (m |= Integer(MOD_SHIFT))
    s.control && (m |= Integer(MOD_CONTROL))
    s.super && (m |= Integer(MOD_SUPER))
    return m
end

@inline nomod(s::WindowState) = iszero(modbits(s))


struct ObsEntry{E<:Event}
    state::WindowState
    event::E
end

const Obs{E} = Observable{Maybe{ObsEntry{E}}}
struct WindowEvents
    keypress::Obs{KeyPress}
    keyrelease::Obs{KeyRelease}
    keyrepeat::Obs{KeyRepeat}
    doubleclick::Obs{Doubleclick}

    buttonpress::Obs{ButtonPress}
    buttonrelease::Obs{ButtonRelease}
    cursor::Obs{CursorPos}
    scroll::Obs{Scroll}
    drag::Obs{MouseDrag}

    windowresize::Obs{WindowResize}

    generic::Obs{GenericEvent}

    function WindowEvents()
        new(
            Obs{KeyPress}(nothing),
            Obs{KeyRelease}(nothing),
            Obs{KeyRepeat}(nothing),
            Obs{Doubleclick}(nothing),
            Obs{ButtonPress}(nothing),
            Obs{ButtonRelease}(nothing),
            Obs{CursorPos}(nothing),
            Obs{Scroll}(nothing),
            Obs{MouseDrag}(nothing),
            Obs{WindowResize}(nothing),
            Obs{GenericEvent}(nothing),
        )
    end
end

eventtype(x::Union{Obs{E},ObsEntry{E}}) where {E} = E

events(x::WindowEvents) = ntuple(i -> getfield(x, i), Val(fieldcount(WindowEvents)))



mutable struct WindowManager
    state::WindowState
    events::WindowEvents
    function WindowManager(window::Window)
        mngr = new(WindowState(window), WindowEvents())
        attachcallbacks!(mngr, window)
    end
end

function attachcallbacks!(mngr::WindowManager, window::Window)
    let mngr = mngr
        GLFW.SetKeyCallback(window, (w, k, s, a, m) -> keycb!(mngr, k, s, a, m))
        GLFW.SetCursorPosCallback(window, (w, x, y) -> cursorposcb!(mngr, x, y))
        GLFW.SetMouseButtonCallback(window, (w, b, a, m) -> mousebuttoncb!(mngr, b, a, m))
        GLFW.SetScrollCallback(window, (w, x, y) -> scrollcb!(mngr, x, y))
        GLFW.SetWindowSizeCallback(window, (w, x, y) -> windowsizecb!(mngr, x, y))
    end
    return mngr
end

function trigger!(mngr::WindowManager, e::Event)
    @debug e
    entry = ObsEntry(mngr.state, e)
    s, events = mngr.state, mngr.events

    if e isa KeyEvent
        events.key[] = entry
    elseif e isa ButtonEvent
        events.button[] = entry
    elseif e isa MouseMoveEvent
        events.mouse[] = entry
    elseif e isa ScrollEvent
        events.scroll[] = entry
    elseif e isa WindowResizeEvent
        events.windowresize[] = entry
    elseif e isa Doubleclick
        events.doubleclick[] = entry
    elseif e isa MouseDrag
        events.drag[] = entry
    elseif e isa GenericEvent
        events.generic[] = entry
    else
        error("Unknown event $e")
    end

function keycb!(mngr::WindowManager, key::Key, ::Cint, action::Action, mods::Cint)
    s = mngr.state
    status = ispress(action) || isrepeat(action)

    if isalt(key)
        s.alt = status
    elseif isshift(key)
        s.shift = status
    elseif iscontrol(key)
        s.control = status
    elseif issuper(key)
        s.super = status
    else
        s.alt = isalt(mods)
        s.shift = isshift(mods)
        s.control = iscontrol(mods)
        s.super = issuper(mods)
    end

    ev = KeyEvent(key, action, time())
    trigger!(mngr, ev)
    s.lastkeyevent = ev

    return
end

function cursorposcb!(mngr::WindowManager, x, y)
    s = mngr.state

    t = time()
    dx = x - s.x
    dy = y - s.y
    s.x = x
    s.y = y
    isdrag = !isnothing(s.lastbuttonevent) && ispressed(s, s.lastbuttonevent.button)

    trigger!(mngr, MouseMoveEvent(dx, dy, isdrag, t))

    return
end

function isdoubleclick(mngr::WindowManager, button, action, mods, t)
    if !isnothing(mngr.events.buttonpress[])
        lb = mngr.events.buttonpress[].event
        return ispress(action) &&
               button == lb.button && (t - lb.time) < DOUBLECLICK_THRESHOLD
    else
        return false
    end
end

function mousebuttoncb!(
    mngr::WindowManager,
    button::MouseButton,
    action::Action,
    mods::Cint,
)
    s, events = mngr.state, mngr.events
    t = time()

    lastbpress= mngr.state.lastbuttonpress
    isdoubleclick = (
        lastbpress !== nothing
        && ispress(action)
        && button === lastbpress.button
        && (t - lastbpress.time) < DOUBLECLICK_THRESHOLD
    )

    if isleft(button)
        s.left = ispress(action)
    elseif ismiddle(button)
        s.middle = ispress(action)
    elseif isright(button)
        s.right = ispress(action)
    end

    ev = ButtonEvent(button, action, isdoubleclick, t)
    trigger!(mngr, ev)
    s.lastbuttonevent = ev
    ispress(action) && (s.lastbuttonpress = ev)

    return
end

function scrollcb!(mngr::WindowManager, dx, dy)
    mngr.state.sx += dx
    mngr.state.sy += dy
    trigger!(mngr, ScrollEvent(dx, dy, time()))
    return
end

function windowsizecb!(mngr::WindowManager, width, height)
    mngr.state.width = width
    mngr.state.height = height
    trigger!(mngr, WindowResize())
    nothing
end


####
#### Event handlers
####

abstract type AbstractEventHandler end

function checksig(f)
    if !hasmethod(f, (WindowState, Event))
        error("AbstractEventHandler callbacks and conditions must have signature (WindowState, Event), got: $(methods(f))")
    end
    true
end

struct EventHandler{E<:Event} <: AbstractEventHandler
    callback
    description::Maybe{String}
    EventHandler{E}(cb, desc) where {E<:Event} = checksig(cb) && new{E}(cb, desc)
end
EventHandler{E}(callback) where {E} = EventHandler{E}(callback, nothing)

struct MultiEventHandler <: AbstractEventHandler
    handlers::Vector{EventHandler}
    description::Maybe{String}
end
MultiEventHandler(handlers) = MultiEventHandler(handlers, nothing)


eventtype(::EventHandler{E}) where {E} = E

function (h::EventHandler)(x::ObsEntry)
    s, e = x.state, x.event
    h.callback(s, e)
    nothing
end

(h::EventHandler)(x::ObsEntry) = h.callback(x.state, x.event)

function register!(mngr::WindowManager, h::EventHandler)
    for obs in events(mngr.events)
        if eventtype(h) === eventtype(obs)
            on(h, obs)
        end
    end
    return mngr
end

register!(mngr::WindowManager, h::MultiEventHandler) = register!(mngr, h.handlers...)

function register!(mngr::WindowManager, handlers::AbstractEventHandler...)
    foreach(h -> register!(mngr, h), handlers)
end


function deregister!(
    mngr::WindowManager,
    h::EventHandler,
)
    for obs in events(mngr.events)
        if eventtype(h) === eventtype(obs)
            off(obs, h)
        end
    end
    return mngr
end

deregister!(mngr::WindowManager, h::MultiEventHandler) = deregister!(mngr, h.handlers...)

function deregister!(mngr::WindowManager, handlers::AbstractEventHandler...)
    foreach(h -> deregister!(mngr, h), handlers)
end


onevent(cb, E::Type{<:Event}; desc::Maybe{String} = nothing) = EventHandler{E}(cb, desc)


function onkeypress(cb, key::Key; desc = nothing, repeat = false)
    EventHandler{KeyPress}(describe(desc, key)) do s, e
        e.key == key && iszero(modbits(s)) && cb(s, e)
    end
end

function onkeypress(cb, key::Key, mods::Mod...; desc = nothing, repeat = false)
    desc = describe(desc, key, mods...)
    mods = modbits(mods)
    EventHandler{KeyPress}(desc) do s, e
        e.key == key && modbits(s) == mods && cb(s, e)
    end
end


function onclick(cb, button::MouseButton; desc = nothing)
    EventHandler{ButtonPress}(describe(desc, button)) do s, e
        e.button == button && iszero(modbits(s)) && cb(s, e)
    end
end

function onclick(cb, button::MouseButton, mods::Mod...; desc = nothing)
    desc = describe(desc, button, mods...)
    mods = modbits(mods)
    EventHandler{ButtonPress}(desc) do s, e
        e.button == button && modbits(s) == mods && cb(s, e)
    end
end


function ondoubleclick(cb, button::MouseButton; desc = nothing)
    desc = isnothing(desc) ? desc : "$(describe(button)) (doubleclick): $desc"
    EventHandler{Doubleclick}(desc) do s, e
        e.button == button && iszero(modbits(s)) && cb(s, e)
    end
end

function ondoubleclick(cb, button::MouseButton, mods::Mod...; desc = nothing)
    desc = isnothing(desc) ? desc : "$(describe(button, mods...)) (doubleclick): $desc"
    mods = modbits(mods)
    EventHandler{Doubleclick}(desc) do s, e
        e.button == button && modbits(s) == mods && cb(s, e)
    end
end


function onscroll(cb; desc = nothing)
    desc = isnothing(desc) ? desc : "Scroll: $desc"
    EventHandler{Scroll}(desc) do s, e
        iszero(modbits(s)) && !iszero(e.dy) && cb(s, e)
    end
end

function onscroll(cb, mods::Mod...; desc = nothing)
    desc = isnothing(desc) ? desc : "$(describe(mods...)) + Scroll: $desc"
    mods = modbits(mods)
    EventHandler{Scroll}(desc) do s, e
        modbits(s) == mods && !iszero(e.dy) && cb(s, e)
    end
end