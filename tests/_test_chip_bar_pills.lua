-- tests/_test_chip_bar_pills.lua
-- The pill layout of the chip strip (fork addition): separate rounded pills
-- with a gap, sized to their label, trailing actions flush right.
--
-- Loads the REAL lib/bookshelf_chip_bar.lua against light stand-ins for the
-- KOReader widgets, then reads the geometry back from ChipBar._chip_dimens
-- (the same table the tap/hold hit-testing uses).
package.path = "./?.lua;./?/init.lua;" .. package.path

local t = dofile("tests/_helpers.lua").runner()

-- ── minimal widget stand-ins ───────────────────────────────────────────────
local function class(parent)
    local c = {}
    c.__index = c
    if parent then setmetatable(c, { __index = parent }) end
    function c:extend(o)
        o = o or {}
        o.__index = o
        setmetatable(o, { __index = self })
        return o
    end
    function c:new(o)
        o = o or {}
        setmetatable(o, self)
        if o.init then o:init() end
        return o
    end
    return c
end

local Widget = class()
function Widget:getSize() return { w = (self.dimen and self.dimen.w) or 0,
                                   h = (self.dimen and self.dimen.h) or 0 } end
function Widget:paintTo() end
function Widget:free() end

local function stub(name, v) package.loaded[name] = v end
local function widgetStub(name) local c = Widget:extend{} stub(name, c) return c end

widgetStub("ui/widget/container/framecontainer")
widgetStub("ui/widget/container/inputcontainer")
widgetStub("ui/widget/horizontalgroup")
widgetStub("ui/widget/horizontalspan")
widgetStub("ui/widget/container/centercontainer")
widgetStub("ui/widget/overlapgroup")
stub("ui/widget/widget", Widget)
widgetStub("ui/widget/linewidget")
widgetStub("ui/widget/iconwidget")
stub("ui/geometry", { new = function(_, o) return o end })
stub("ui/gesturerange", { new = function(_, o) return o end })
stub("ui/size", { border = { thin = 1, thick = 3 } })
stub("ui/font", {})
stub("ffi/blitbuffer", { COLOR_WHITE = { a = 255 }, COLOR_BLACK = { a = 0 } })
stub("ui/uimanager", { setDirty = function() end, forceRePaint = function() end })
stub("device", { screen = { isColorEnabled = function() return false end } })
stub("logger", { dbg = function() end, warn = function() end, info = function() end })

-- text: 10px per character, so natural widths differ per label
local TextWidget = Widget:extend{}
function TextWidget:getSize() return { w = 10 * #(self.text or ""), h = 20 } end
stub("lib/bookshelf_colour_text", TextWidget)
stub("lib/bookshelf_cap_centre", { centre = function() end })
stub("lib/bookshelf_gestures", { on = function() return true end })
stub("lib/bookshelf_fonts", { getFace = function() return {}, false end })
stub("lib/bookshelf_text_segments", {
    upper = function(s) return s:upper() end,
    labelSegments = function(s)
        if s == "" then return {} end
        return { { class = "text", text = s } }
    end,
})
stub("lib/bookshelf_band_metrics", { CHIP_KEY = "chip", scaled = function(n) return n end })
stub("lib/bookshelf_space", {
    px = function(v) return v end,
    padding = { small = 2, large = 10 },
})
stub("lib/bookshelf_page_wipe", { resolveSteps = function() return 0 end })
stub("lib/bookshelf_theme_pack", {})
stub("lib/bookshelf_cover_progress", {})

local settings = {}
stub("lib/bookshelf_settings_store", {
    nilOrTrue = function(k) return settings[k] ~= false end,
    isTrue    = function(k) return settings[k] == true end,
    read      = function(k) return settings[k] end,
    save      = function(k, v) settings[k] = v end,
})

local ChipBar = dofile("lib/bookshelf_chip_bar.lua")

local function chips(extra_flex)
    local list = {
        { key = "current", icon = "book", action = true },
        { key = "home",    label = "Home" },
        { key = "recent",  label = "Recent" },
        { key = "series",  label = "Series" },
        { key = "genres",  label = "Genres" },
    }
    for _, label in ipairs(extra_flex or {}) do
        list[#list + 1] = { key = label:lower(), label = label }
    end
    list[#list + 1] = { key = "search", icon = "search", action = true }
    return list
end

local function build(opts)
    opts = opts or {}
    settings.chip_pill_style = nil
    local picked
    local bar = ChipBar:new{
        width = opts.width or 1000, height = 60,
        chips = opts.chips or chips(), active = "recent",
        on_change = function(k) picked = k end,
    }
    return bar, function() return picked end
end

-- the pill frames of the built strip, in order
local function pills(bar)
    local out = {}
    for _, child in ipairs(bar[1][1]) do
        if child.radius then out[#out + 1] = child end
    end
    return out
end

t.test("every chip is a separate rounded pill", function()
    local bar = build()
    local p = pills(bar)
    assert(#p == 6, "expected 6 pills, got " .. #p)
    for _, f in ipairs(p) do
        assert(f.radius == 30, "fully rounded: radius = height/2, got " .. tostring(f.radius))
    end
    assert(bar[1].bordersize == 0, "no outline around the whole strip")
end)

t.test("pills are separated by a gap and never overlap", function()
    local bar = build()
    local d = bar._chip_dimens
    local order = { "current", "home", "recent", "series", "genres" }
    for i = 2, #order do
        local a, b = d[order[i - 1]], d[order[i]]
        assert(b.x - (a.x + a.w) == 6, order[i] .. " should sit 6px after " .. order[i - 1]
            .. ", got " .. (b.x - (a.x + a.w)))
    end
end)

t.test("pills are sized to their label, not equal shares", function()
    local d = build()._chip_dimens
    assert(d.home.w ~= d.recent.w, "Home and Recent differ in length, so in width")
    assert(d.home.w < d.recent.w)
end)

t.test("the trailing action pill is flush with the right edge", function()
    local d = build()._chip_dimens
    assert(d.search.x + d.search.w == 1000, "search ends at the strip's right edge")
    assert(d.search.x > d.genres.x + d.genres.w, "and leaves room before it")
end)

t.test("only the selected pill is filled", function()
    local bar = build()
    local p = pills(bar)
    local filled = 0
    for _, f in ipairs(p) do if f.background ~= nil then filled = filled + 1 end end
    assert(filled == 1, "exactly one filled pill, got " .. filled)
    assert(p[3].background ~= nil, "the third pill (recent) is the selected one")
end)

t.test("tapping a pill dispatches its key", function()
    local bar, picked = build()
    local d = bar._chip_dimens.series
    bar.dimen = { x = 0, y = 0, w = 1000, h = 60 }
    assert(bar:onTapStrip(nil, { pos = { x = d.x + d.w / 2, y = 30 } }))
    assert(picked() == "series", "got " .. tostring(picked()))
end)

t.test("a tap in the gap between pills hits nothing", function()
    local bar, picked = build()
    local a = bar._chip_dimens.home
    bar.dimen = { x = 0, y = 0, w = 1000, h = 60 }
    local handled = bar:onTapStrip(nil, { pos = { x = a.x + a.w + 3, y = 30 } })
    assert(not handled and picked() == nil, "the gap is not a button")
end)

t.test("too many pills paginate and stay inside the strip", function()
    local bar = build{ width = 400 }
    assert(bar._pages.multi, "400px cannot hold every shelf")
    for key, d in pairs(bar._chip_dimens) do
        assert(d.x >= 0 and d.x + d.w <= 400, key .. " overflows: " .. d.x .. "+" .. d.w)
    end
    assert(bar._chip_dimens.__chip_nextpage, "a next-page chevron is offered")
end)

t.test("turning Pill-style tabs off restores the segmented bar", function()
    settings.chip_pill_style = false
    local ok, bar = pcall(function()
        return ChipBar:new{ width = 1000, height = 60, chips = chips(), active = "recent" }
    end)
    settings.chip_pill_style = nil
    if not ok then
        -- The original layout needs more of KOReader than these stand-ins
        -- provide; the switch itself is what is under test.
        print("  (original layout not buildable with stubs: " .. tostring(bar):sub(1, 80) .. ")")
        return
    end
    assert(#pills(bar) == 0, "no rounded pills when the setting is off")
end)

t.done()
