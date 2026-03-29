-- @version 1.0.0
-- @location /libs

local PI = 3.14

--- All functions return a polygon table compatible with imgui.dl.renderPolygon.
--- Outline functions build a filled donut polygon so thickness is geometry, not a renderer hint.
local irender = {}

--- @class Color
--- @field r number Red channel (0–255)
--- @field g number Green channel (0–255)
--- @field b number Blue channel (0–255)
--- @field a number|nil Alpha channel (0–255), defaults to 255

--- @class Opts
--- @field rotation number|nil Clockwise rotation in degrees around the shape's centre
--- @field thickness number|nil Stroke width in pixels for outline functions (default: 1)

--- @class Point
--- @field x number
--- @field y number

--- @class Polygon
--- @field points Point[] Ordered list of vertices
--- @field red   number
--- @field green number
--- @field blue  number
--- @field alpha number

--- Rotates a list of points around an origin by an angle given in degrees.
--- @param points Point[]
--- @param ox number Origin X
--- @param oy number Origin Y
--- @param angle number Degrees
--- @return Point[]
local function rotatePoints(points, ox, oy, angle)
    local rad = math.rad(angle)
    local cos, sin = math.cos(rad), math.sin(rad)
    local rotated = {}
    for _, p in ipairs(points) do
        local dx, dy = p.x - ox, p.y - oy
        table.insert(rotated, {
            x = ox + dx * cos - dy * sin,
            y = oy + dx * sin + dy * cos
        })
    end
    return rotated
end

--- Builds a single flat polygon that traces the outer ring forward then the
--- inner ring backward, forming a closed donut shape a filled renderer can draw.
--- Both rings must already have their first point appended at the end to close the seam.
--- @param outer Point[]
--- @param inner Point[]
--- @return Point[]
local function buildDonut(outer, inner)
    local points = {}
    for _, p in ipairs(outer) do
        table.insert(points, p)
    end
    for i = #inner, 1, -1 do
        table.insert(points, inner[i])
    end
    return points
end

--- Offsets every point in a ring outward (delta > 0) or inward (delta < 0)
--- relative to the given centre by pushing along the point's normal from centre.
--- @param points Point[]
--- @param cx number Centre X
--- @param cy number Centre Y
--- @param delta number Pixel offset, positive = outward
--- @return Point[]
local function scaleRing(points, cx, cy, delta)
    local scaled = {}
    for _, p in ipairs(points) do
        local dx, dy = p.x - cx, p.y - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len == 0 then
            table.insert(scaled, { x = p.x, y = p.y })
        else
            table.insert(scaled, {
                x = p.x + (dx / len) * delta,
                y = p.y + (dy / len) * delta
            })
        end
    end
    return scaled
end

--- Returns a filled circle polygon approximated by `sides` vertices.
--- @param x      number Centre X
--- @param y      number Centre Y
--- @param radius number Radius in pixels
--- @param sides  number Number of vertices (higher = smoother)
--- @param color  Color
--- @param opts   Opts|nil  Supports: rotation
--- @return Polygon
function irender.renderCircle(x, y, radius, sides, color, opts)
    local r, g, b, a = color.r, color.g, color.b, color.a or 255
    opts = opts or {}

    local points = {}
    for i = 1, sides do
        local angle = (i - 1) * (2 * PI / sides)
        table.insert(points, {
            x = x + radius * math.cos(angle),
            y = y + radius * math.sin(angle)
        })
    end

    if opts.rotation then
        points = rotatePoints(points, x, y, opts.rotation)
    end

    return { points = points, red = r, green = g, blue = b, alpha = a }
end

--- Returns a circle outline as a filled donut polygon.
--- The stroke is centred on `radius`, extending `thickness/2` inward and outward.
--- @param x      number Centre X
--- @param y      number Centre Y
--- @param radius number Radius in pixels (measured to stroke centreline)
--- @param sides  number Number of vertices per ring (higher = smoother)
--- @param color  Color
--- @param opts   Opts|nil  Supports: rotation, thickness
--- @return Polygon
function irender.renderCircleOutline(x, y, radius, sides, color, opts)
    local r, g, b, a = color.r, color.g, color.b, color.a or 255
    opts = opts or {}
    local half = (opts.thickness or 1) / 2

    local outer, inner = {}, {}
    for i = 1, sides do
        local angle = (i - 1) * (2 * PI / sides)
        local cos, sin = math.cos(angle), math.sin(angle)
        table.insert(outer, { x = x + (radius + half) * cos, y = y + (radius + half) * sin })
        table.insert(inner, { x = x + (radius - half) * cos, y = y + (radius - half) * sin })
    end

    table.insert(outer, outer[1])
    table.insert(inner, inner[1])

    if opts.rotation then
        outer = rotatePoints(outer, x, y, opts.rotation)
        inner = rotatePoints(inner, x, y, opts.rotation)
    end

    return { points = buildDonut(outer, inner), red = r, green = g, blue = b, alpha = a }
end

--- Returns a rectangle outline as a filled donut polygon.
--- The stroke is centred on the rectangle's edges, extending `thickness/2` inward and outward.
--- @param x      number Left edge X
--- @param y      number Top edge Y
--- @param width  number
--- @param height number
--- @param color  Color
--- @param opts   Opts|nil  Supports: rotation (around rect centre), thickness
--- @return Polygon
function irender.renderRectOutline(x, y, width, height, color, opts)
    local r, g, b, a = color.r, color.g, color.b, color.a or 1
    opts = opts or {}
    local half = (opts.thickness or 1) / 2

    local cx, cy = x + width / 2, y + height / 2

    local outer = {
        { x = x - half,         y = y - half          },
        { x = x + width + half, y = y - half          },
        { x = x + width + half, y = y + height + half },
        { x = x - half,         y = y + height + half }
    }
    local inner = {
        { x = x + half,         y = y + half          },
        { x = x + width - half, y = y + half          },
        { x = x + width - half, y = y + height - half },
        { x = x + half,         y = y + height - half }
    }

    table.insert(outer, outer[1])
    table.insert(inner, inner[1])

    if opts.rotation then
        outer = rotatePoints(outer, cx, cy, opts.rotation)
        inner = rotatePoints(inner, cx, cy, opts.rotation)
    end

    return { points = buildDonut(outer, inner), red = r, green = g, blue = b, alpha = a }
end

--- Returns a rounded rectangle outline as a filled donut polygon.
--- Corner arcs are approximated with 8 steps per corner.
--- The stroke is centred on the shape's edges, extending `thickness/2` inward and outward.
--- @param x      number Left edge X
--- @param y      number Top edge Y
--- @param width  number
--- @param height number
--- @param round  number Corner radius in pixels (clamped to min(width,height)/2)
--- @param color  Color
--- @param opts   Opts|nil  Supports: rotation (around rect centre), thickness
--- @return Polygon
function irender.renderRoundedRectOutline(x, y, width, height, round, color, opts)
    local r, g, b, a = color.r, color.g, color.b, color.a or 1
    opts = opts or {}
    local half = (opts.thickness or 1) / 2

    local maxRound = math.min(width / 2, height / 2)
    round = math.min(round, maxRound)

    local cornerSteps = 8
    local cx, cy = x + width / 2, y + height / 2
    local centreline = {}

    local function addArcPoints(acx, acy, startAngle, endAngle)
        for i = 0, cornerSteps do
            local angle = math.rad(startAngle + (endAngle - startAngle) * (i / cornerSteps))
            table.insert(centreline, {
                x = acx + round * math.cos(angle),
                y = acy + round * math.sin(angle)
            })
        end
    end

    addArcPoints(x + width - round, y + round,          270, 360)
    addArcPoints(x + width - round, y + height - round, 0,   90)
    addArcPoints(x + round,         y + height - round, 90,  180)
    addArcPoints(x + round,         y + round,          180, 270)

    local outer = scaleRing(centreline, cx, cy,  half)
    local inner = scaleRing(centreline, cx, cy, -half)

    table.insert(outer, outer[1])
    table.insert(inner, inner[1])

    if opts.rotation then
        outer = rotatePoints(outer, cx, cy, opts.rotation)
        inner = rotatePoints(inner, cx, cy, opts.rotation)
    end

    return { points = buildDonut(outer, inner), red = r, green = g, blue = b, alpha = a }
end

--- Returns a filled rounded rectangle polygon.
--- Corner arcs are approximated with 10 steps per corner.
--- @param x      number Left edge X
--- @param y      number Top edge Y
--- @param width  number
--- @param height number
--- @param round  number Corner radius in pixels (clamped to min(width,height)/2)
--- @param color  Color
--- @param opts   Opts|nil  Supports: rotation (around rect centre)
--- @return Polygon
function irender.renderRoundedRect(x, y, width, height, round, color, opts)
    local r, g, b, a = color.r, color.g, color.b, color.a or 1
    opts = opts or {}

    local points = {}
    local maxRound = math.min(width / 2, height / 2)
    round = math.min(round, maxRound)

    local cornerSteps = 10
    local cx, cy = x + width / 2, y + height / 2

    local function addCorner(acx, acy, startAngle, endAngle)
        for i = 0, cornerSteps do
            local angle = startAngle + (endAngle - startAngle) * (i / cornerSteps)
            table.insert(points, {
                x = acx + round * math.cos(angle),
                y = acy + round * math.sin(angle)
            })
        end
    end

    addCorner(x + width - round, y + round,          math.rad(270), math.rad(360))
    addCorner(x + width - round, y + height - round, math.rad(0),   math.rad(90))
    addCorner(x + round,         y + height - round, math.rad(90),  math.rad(180))
    addCorner(x + round,         y + round,          math.rad(180), math.rad(270))

    if opts.rotation then
        points = rotatePoints(points, cx, cy, opts.rotation)
    end

    return { points = points, red = r, green = g, blue = b, alpha = a }
end

return irender