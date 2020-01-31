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

function GetRefreshRate(monitor::GLFW.Monitor=GLFW.GetPrimaryMonitor())
    GLFW.GetVideoMode(monitor).refreshrate
end

function default_windowsize()
    vmode = GLFW.GetVideoMode(GLFW.GetPrimaryMonitor())
    (width = trunc(Int, 2 * vmode.width / 3), height = trunc(Int, 2 * vmode.height / 3))
end

function create_window(width::Integer, height::Integer, title::String)
    GLFW.WindowHint(GLFW.SAMPLES, 4)
    GLFW.WindowHint(GLFW.VISIBLE, 0)
    window = GLFW.CreateWindow(width, height, title)
    GLFW.MakeContextCurrent(window)
    GLFW.SwapInterval(1)
    window
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

isalt(mods::Cint) = (mods & GLFW.MOD_ALT) == GLFW.MOD_ALT
isshift(mods::Cint) = (mods & GLFW.MOD_SHIFT) == GLFW.MOD_SHIFT
iscontrol(mods::Cint) = (mods & GLFW.MOD_CONTROL) == GLFW.MOD_CONTROL
issuper(mods::Cint) = (mods & GLFW.MOD_SUPER) == GLFW.MOD_SUPER

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


####
#### Events
####

abstract type Event end

struct KeyPress <: Event
    key::Key
    time::Float64
end
KeyPress(key) = KeyPress(key, time())

struct KeyRelease <: Event
    key::Key
    time::Float64
end
KeyRelease(key) = KeyRelease(key, time())

struct KeyRepeat <: Event
    key::Key
    time::Float64
end
KeyRepeat(key) = KeyRepeat(key, time())

struct CursorPos <: Event
    dx::Float64
    dy::Float64
    time::Float64
end
CursorPos(dx, dy) = CursorPos(dx, dy, time())

struct ButtonPress <: Event
    button::MouseButton
    time::Float64
end
ButtonPress(button) = ButtonPress(button, time())

struct ButtonRelease <: Event
    button::MouseButton
    time::Float64
end
ButtonRelease(button) = ButtonRelease(button, time())

struct Scroll <: Event
    dx::Float64
    dy::Float64
    time::Float64
end
Scroll(dx, dy) = Scroll(dx, dy, time())

struct WindowResize <: Event
    time::Float64
end
WindowResize() = WindowResize(time())

struct Doubleclick <: Event
    button::MouseButton
    time::Float64
end
Doubleclick(button) = Doubleclick(button, time())

struct MouseDrag <: Event
    dx::Float64
    dy::Float64
    button::MouseButton
    time::Float64
end
MouseDrag(dx, dy, button) = MouseDrag(dx, dy, button, time())

struct GenericEvent{T} <: Event
    x::T
    time::Float64
end
GenericEvent(x) = GenericEvent(x, time())


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
    lastbutton::Union{Nothing,ButtonPress,ButtonRelease}

    alt::Bool
    shift::Bool
    control::Bool
    super::Bool
    lastkey::Union{Nothing,KeyPress,KeyRelease,KeyRepeat}

    width::Float64
    height::Float64
    window::Window

    function WindowState(window::Window)
        x, y = GLFW.GetCursorPos(window)
        width, height = GLFW.GetWindowSize(window)
        new(
            x,
            y,
            0,
            0,
            GLFW.GetMouseButton(window, GLFW.MOUSE_BUTTON_LEFT),
            GLFW.GetMouseButton(window, GLFW.MOUSE_BUTTON_MIDDLE),
            GLFW.GetMouseButton(window, GLFW.MOUSE_BUTTON_RIGHT),
            nothing,
            getalt(window),
            getshift(window),
            getcontrol(window),
            getsuper(window),
            nothing,
            width,
            height,
            window,
        )
    end
end

function ispressed(state::WindowState, button::MouseButton)
    button == GLFW.MOUSE_BUTTON_LEFT && return state.left
    button == GLFW.MOUSE_BUTTON_MIDDLE && return state.middle
    button == GLFW.MOUSE_BUTTON_RIGHT && return state.right
    GLFW.GetMouseButton(state.window, button)
end

function modbits(state::WindowState)
    m = Cint(0)
    state.alt && (m |= Integer(MOD_ALT))
    state.shift && (m |= Integer(MOD_SHIFT))
    state.control && (m |= Integer(MOD_CONTROL))
    state.super && (m |= Integer(MOD_SUPER))
    m
end


struct ObsEntry{T<:Event}
    state::WindowState
    event::T
end

const Obs{T} = Observable{Union{ObsEntry{T},Nothing}}
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

eventtype(x::ObsEntry{T}) where {T} = T
eventtype(x::Obs{T}) where {T} = T

function events(we::WindowEvents)
    Tuple(getfield(we, name) for (T, name) in zip(
        fieldtypes(WindowEvents),
        fieldnames(WindowEvents),
    ) if T <: AbstractObservable)
end


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
    mngr
end

function trigger!(mngr::WindowManager, e::Event)
    @debug e
    entry = ObsEntry(mngr.state, e)
    state, events = mngr.state, mngr.events
    if e isa KeyPress
        events.keypress[] = entry
        state.lastkey = e
    elseif e isa KeyRelease
        events.keyrelease[] = entry
        state.lastkey = e
    elseif e isa KeyRepeat
        events.keyrepeat[] = entry
        state.lastkey = e
    elseif e isa ButtonPress
        events.buttonpress[] = entry
        state.lastbutton = e
    elseif e isa ButtonRelease
        events.buttonrelease[] = entry
        state.lastbutton = e
    elseif e isa CursorPos
        events.cursor[] = entry
    elseif e isa Scroll
        events.scroll[] = entry
    elseif e isa WindowResize
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
    mngr
end

function keycb!(mngr::WindowManager, key::Key, ::Cint, action::Action, mods::Cint)
    status = ispress(action) || isrepeat(action)
    state = mngr.state
    if isalt(key)
        state.alt = status
    elseif isshift(key)
        state.shift = status
    elseif iscontrol(key)
        state.control = status
    elseif issuper(key)
        state.super = status
    else
        state.alt = isalt(mods)
        state.shift = isshift(mods)
        state.control = iscontrol(mods)
        state.super = issuper(mods)
    end

    if ispress(action)
        e = KeyPress(key)
    elseif isrelease(action)
        e = KeyRelease(key)
    else
        e = KeyRepeat(key)
    end
    trigger!(mngr, e)

    nothing
end

function cursorposcb!(mngr::WindowManager, x, y)
    state, events = mngr.state, mngr.events
    t = time()

    dx = x - state.x
    dy = y - state.y
    state.x = x
    state.y = y

    trigger!(mngr, CursorPos(x, y, t))
    if !isnothing(state.lastbutton) && ispressed(mngr.state, state.lastbutton.button)
        trigger!(mngr, MouseDrag(dx, dy, state.lastbutton.button, t))
    end

    nothing
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
    state, events = mngr.state, mngr.events
    t = time()
    # doubleclick must be checked before triggering button event
    doubleclick = isdoubleclick(mngr, button, action, mods, t)

    if isleft(button)
        state.left = ispress(action)
    elseif ismiddle(button)
        state.middle = ispress(action)
    elseif isright(button)
        state.right = ispress(action)
    end

    ispress(action) ? trigger!(mngr, ButtonPress(button, t)) :
    trigger!(mngr, ButtonRelease(button, t))
    doubleclick && trigger!(mngr, Doubleclick(button, t))

    nothing
end

function scrollcb!(mngr::WindowManager, dx, dy)
    state = mngr.state
    state.sx += dx
    state.sy += dy
    trigger!(mngr, Scroll(dx, dy))
    nothing
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


function register!(mngr::WindowManager, h::EventHandler)
    for obs in events(mngr.events)
        if eventtype(h) === eventtype(obs)
            on(h, obs)
        end
    end
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