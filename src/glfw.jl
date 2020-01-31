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

function SetWindowAttrib(window::GLFW.Window, attrib::Integer, value::Integer)
    ccall(
        (:glfwSetWindowAttrib, GLFW.libglfw),
        Cvoid,
        (GLFW.Window, Cint, Cint),
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

isrelease(action::GLFW.Action) = action == GLFW.RELEASE
ispress(action::GLFW.Action) = action == GLFW.PRESS
isrepeat(action::GLFW.Action) = action == GLFW.REPEAT

isalt(mods::Cint) = (mods & GLFW.MOD_ALT) == GLFW.MOD_ALT
isshift(mods::Cint) = (mods & GLFW.MOD_SHIFT) == GLFW.MOD_SHIFT
iscontrol(mods::Cint) = (mods & GLFW.MOD_CONTROL) == GLFW.MOD_CONTROL
issuper(mods::Cint) = (mods & GLFW.MOD_SUPER) == GLFW.MOD_SUPER

isalt(key::GLFW.Key) = key == GLFW.KEY_LEFT_ALT || key == GLFW.KEY_RIGHT_ALT
isshift(key::GLFW.Key) = key == GLFW.KEY_LEFT_SHIFT || key == GLFW.KEY_RIGHT_SHIFT
iscontrol(key::GLFW.Key) = key == GLFW.KEY_LEFT_CONTROL || key == GLFW.KEY_RIGHT_CONTROL
issuper(key::GLFW.Key) = key == GLFW.KEY_LEFT_SUPER || key == GLFW.KEY_RIGHT_SUPER

getalt(w::GLFW.Window) =
    GLFW.GetKey(w, GLFW.KEY_LEFT_ALT) || GLFW.GetKey(w, GLFW.KEY_RIGHT_ALT)
getshift(w::GLFW.Window) =
    GLFW.GetKey(w, GLFW.KEY_LEFT_SHIFT) || GLFW.GetKey(w, GLFW.KEY_RIGHT_SHIFT)
getcontrol(w::GLFW.Window) =
    GLFW.GetKey(w, GLFW.KEY_LEFT_CONTROL) || GLFW.GetKey(w, GLFW.KEY_RIGHT_CONTROL)
getsuper(w::GLFW.Window) =
    GLFW.GetKey(w, GLFW.KEY_LEFT_SUPER) || GLFW.GetKey(w, GLFW.KEY_RIGHT_SUPER)

isleft(b::GLFW.MouseButton) = b == GLFW.MOUSE_BUTTON_LEFT
ismiddle(b::GLFW.MouseButton) = b == GLFW.MOUSE_BUTTON_MIDDLE
isright(b::GLFW.MouseButton) = b == GLFW.MOUSE_BUTTON_RIGHT


####
#### Events
####

abstract type Event end

struct KeyPress <: Event
    key::GLFW.Key
    time::Float64
end
KeyPress(key) = KeyPress(key, time())

struct KeyRelease <: Event
    key::GLFW.Key
    time::Float64
end
KeyRelease(key) = KeyRelease(key, time())

struct KeyRepeat <: Event
    key::GLFW.Key
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

struct WindowRefresh <: Event
    time::Float64
end
WindowRefresh() = WindowRefresh(time())

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
    windowrefresh::Obs{WindowRefresh}

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
            Obs{WindowRefresh}(nothing),
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
        GLFW.SetWindowRefreshCallback(window, w -> windowrefreshcb!(mngr))
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
    elseif e isa WindowRefresh
        events.windowrefresh[] = entry
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

function windowrefreshcb!(mngr::WindowManager)
    trigger!(mngr, WindowRefresh())
    nothing
end



abstract type AbstractEventHandler end

function checksig(f)
    if !hasmethod(f, (WindowState, Event))
        error("AbstractEventHandler callbacks and conditions must have signature (WindowState, Event), got: $(methods(f))")
    end
    true
end

struct EventHandler{E<:Event} <: AbstractEventHandler
    callback
    description::Union{Nothing,String}
    EventHandler{E}(cb, desc) where {E<:Event} = checksig(cb) && new{E}(cb, desc)
end
EventHandler{E}(callback) where {E} = EventHandler{E}(callback, nothing)
eventtype(::EventHandler{E}) where {E} = E

struct ConditionalEventHandler{E<:Event} <: AbstractEventHandler
    callback
    predicate
    description::Union{Nothing,String}
    function ConditionalEventHandler{E}(cb, pred, desc) where {E<:Event}
        checksig(cb) && checksig(pred) && new{E}(cb, pred, desc)
    end
end
ConditionalEventHandler{E}(callback, pred) where {E} =
    ConditionalEventHandler{E}(callback, pred, nothing)
eventtype(::ConditionalEventHandler{E}) where {E} = E

struct MultiEventHandler <: AbstractEventHandler
    handlers::Vector{Union{EventHandler,ConditionalEventHandler}}
    description::Maybe{String}
end
MultiEventHandler(handlers) = MultiEventHandler(handlers, nothing)


function (h::ConditionalEventHandler)(val)
    isnothing(val) && return false
    s, e = val.state, val.event
    h.predicate(s, e) && h.callback(s, e)
    true
end

function (h::EventHandler)(val)
    isnothing(val) && return false
    s, e = val.state, val.event
    h.callback(s, e)
    true
end


register!(mngr::WindowManager, single::EventHandler) = _register!(mngr, single)
register!(mngr::WindowManager, single::ConditionalEventHandler) = _register!(mngr, single)
function _register!(mngr::WindowManager, single)
    for obs in events(mngr.events)
        if eventtype(single) === eventtype(obs)
            on(single, obs)
        end
    end
end

deregister!(mngr::WindowManager, single::EventHandler) = _deregister!(mngr, single)
deregister!(mngr::WindowManager, single::ConditionalEventHandler) =
    _deregister!(mngr, single)
function _deregister!(
    mngr::WindowManager,
    single::Union{EventHandler,ConditionalEventHandler},
)
    for obs in events(mngr.events)
        if eventtype(single) === eventtype(obs)
            off(obs, single)
        end
    end
end

register!(mngr::WindowManager, multi::MultiEventHandler) =
    foreach(h -> register!(mngr, h), multi.handlers)
deregister!(mngr::WindowManager, multi::MultiEventHandler) =
    foreach(h -> deregister!(mngr, h), multi.handlers)

register!(mngr::WindowManager, handlers::AbstractVector{<:AbstractEventHandler}) =
    foreach(h -> register!(mngr, h), handlers)
deregister!(mngr::WindowManager, handlers::AbstractVector{<:AbstractEventHandler}) =
    foreach(h -> deregister!(mngr, h), handlers)



function describe(x::Mod)
    if x === MOD_CONTROL
        "CTRL"
    else
        String(Symbol(x))[5:end]
    end
end
#describe(x::GLFW.Key) = String(Symbol(x))[5:end]
function describe(x::GLFW.Key)
    c = Char(Integer(x))
    if c in PUNCTUATION
        return "$c "
    elseif x === GLFW.KEY_ESCAPE
        return "ESC"
    else
        return String(Symbol(x))[5:end]
    end
end

function describe(x::GLFW.MouseButton)
    x == GLFW.MOUSE_BUTTON_LEFT && return "LEFT_CLICK"
    x == GLFW.MOUSE_BUTTON_MIDDLE && return "MIDDLE_CLICK"
    x == GLFW.MOUSE_BUTTON_RIGHT && return "RIGHT_CLICK"
    error("unknown button $x")
end

describe(desc::String, xs...) = "$(describe(xs...))   $desc"

describe(::Nothing, xs...) = nothing

function describe(xs::Union{GLFW.Key,GLFW.MouseButton,Mod}...)
    ms = sort!([describe(x) for x in xs if x isa Mod])
    ks = sort!([describe(x) for x in xs if x isa GLFW.MouseButton])
    bs = sort!([describe(x) for x in xs if x isa GLFW.Key])
    join(vcat(ms, ks, bs), "+")
end

modbits(ms::Tuple{Vararg{Mod}}) = mapreduce(Cint, |, ms)
modbits(ms::Mod...) = modbits(ms)


onevent(cb, E::Type{<:Event}, desc::Union{Nothing,String} = nothing) =
    EventHandler{E}(cb, desc)
onevent(cb, E::Type{<:Event}, pred, desc::Union{Nothing,String} = nothing) =
    ConditionalEventHandler{E}(cb, pred, desc)

function onkeypress(cb, key::GLFW.Key; desc = nothing, repeat = false)
    pred(s, e) = e.key == key && iszero(modbits(s))
    ConditionalEventHandler{KeyPress}(cb, pred, describe(desc, key))
end
function onkeypress(cb, key::GLFW.Key, mods::Mod...; desc = nothing, repeat = false)
    desc = describe(desc, key, mods...)
    mods = modbits(mods)
    pred(s, e) = e.key == key && modbits(s) == mods
    ConditionalEventHandler{KeyPress}(cb, pred, desc)
end

function onclick(cb, button::MouseButton; desc = nothing)
    pred(s, e) = e.button == button && iszero(modbits(s))
    ConditionalEventHandler{ButtonPress}(cb, pred, describe(desc, button))
end
function onclick(cb, button::MouseButton, mods::Mod...; desc = nothing)
    desc = describe(desc, button, mods...)
    mods = modbits(mods)
    pred(s, e) = e.button == button && modbits(s) == mods
    ConditionalEventHandler{ButtonPress}(cb, pred, desc)
end

function ondoubleclick(cb, button::MouseButton; desc = nothing)
    desc = isnothing(desc) ? desc : "$(describe(button)) (doubleclick): $desc"
    pred(s, e) = e.button == button && iszero(modbits(s))
    ConditionalEventHandler{Doubleclick}(cb, pred, desc)
end
function ondoubleclick(cb, button::MouseButton, mods::Mod...; desc = nothing)
    desc = isnothing(desc) ? desc : "$(describe(button, mods...)) (doubleclick): $desc"
    mods = modbits(mods)
    pred(s, e) = e.button == button && modbits(s) == mods
    ConditionalEventHandler{Doubleclick}(cb, pred, desc)
end

function onscroll(cb; desc = nothing)
    desc = isnothing(desc) ? desc : "Scroll: $desc"
    pred(s, e) = iszero(modbits(s)) && !iszero(e.dy)
    ConditionalEventHandler{Scroll}(cb, pred, desc)
end
function onscroll(cb, mods::Mod...; desc = nothing)
    desc = isnothing(desc) ? desc : "$(describe(mods...)) + Scroll: $desc"
    mods = modbits(mods)
    pred(s, e) = modbits(s) == mods && !iszero(e.dy)
    ConditionalEventHandler{Scroll}(cb, pred, desc)
end

function ondrag(cb, button::MouseButton; desc = nothing)
    desc = isnothing(desc) ? desc : "$(describe(button)) + Drag: $desc"
    pred(s, e) = e.button == button && iszero(modbits(s))
    ConditionalEventHandler{MouseDrag}(cb, pred, desc)
end
function ondrag(cb, button::MouseButton, mods::Mod...; desc = nothing)
    desc = isnothing(desc) ? desc : "$(describe(button, mods...)) + drag: $desc"
    mods = modbits(mods)
    pred(s, e) = e.button == button && modbits(s) == mods
    ConditionalEventHandler{MouseDrag}(cb, pred, desc)
end
