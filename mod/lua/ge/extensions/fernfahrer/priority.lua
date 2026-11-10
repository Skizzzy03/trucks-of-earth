-- Trucks of Earth: priority roads on BeamNG.Earth's road graph ("Vorfahrtsstraße", automatically).
-- BeamNG's traffic AI gives way at a junction when it turns, or when the road it comes from has a lower drivability
-- than another one there (ai.lua, uncontrolled intersections); and Earth turns an OpenStreetMap stop sign at a
-- junction into a stop for every approach. So cars on a main road braked at side streets: where the main road's
-- class changes at a junction (its next piece rated lower), where a side street was rated the same, at stop signs.
-- Every graph Earth sends (navgraph.onMessage) is fixed up before it is used: at each junction the through pair (the
-- two best-rated roads going straight on) becomes the priority road – the road gets one rating along its whole length,
-- every other road there a clearly lower one (the AI also picks its way by that rating: traffic stays on the main
-- road) – and stop / give-way signs stay only on the side roads. Two equal roads crossing keep their ratings.
-- Traffic lights are not touched.
-- Graph format (beamngEarth/navgraph.lua): nodes[name] = {x, y, z, radius, ...}; edges[i] = {a, b, oneWay, lanesOut,
-- lanesBack, speed m/s, drivability, radius}; signals[i] = {j = node, kind, app = {{node, x, y, z, dx, dy, phase}}}.

local M = {}

M.STRAIGHT = -0.6           -- the through pair: their directions out of the junction at least this opposite (~127°)
-- a side road is rated at most this share of the main road. (0.9 of it: a car still turned off at one junction in four or so.
-- The AI weighs a turn by the square of this, and by the angle.)
M.SIDE_SHARE = 0.65
-- Oncoming room: the AI brakes for an oncoming vehicle whose line comes within half their two widths of its own
-- (ai.lua awareness: 0.505 * (ego + other width)) – a car (1.9 m) meeting a truck (2.55 m) at 2.22 m. Earth's
-- ordinary streets are 2.75 m a lane (radius 2.75): lane centres 2.75 m apart, so a truck a few decimetres off its
-- lane centre made every oncoming car stop. Two-way streets of that kind get MIN_RADIUS for the AI: its lane centre
-- moves out to 1.75 m from the centre line (the car's right side at 2.7 m: still on the 2.75 m of asphalt), so the
-- AI brakes only once a truck's centre comes within 2.25 m of that line, i.e. less than 0.5 m right of the centre
-- line: a truck (2.55 m) can ride with its left side up to ~0.75 m over the centre line before an oncoming car
-- brakes (with its left side on the line itself: 0.75 m to spare).
-- (2026-11-10: 0.75 was too much. The lane centre moved so far out that a car's right wheels ran on the very edge of the asphalt, on
-- narrow roads beside it, and the verge took it into the ditch. 0.35: right side at least 0.25 m inside the real edge. The meeting
-- itself is seen to in trafficai.lua.)
M.MIN_RADIUS = 3.5
M.WIDEN_BY = 0.35           -- narrower two-way roads: this much more (2.75 -> 3.1), at most MIN_RADIUS
M.WIDEN_FROM = 2.3          -- (narrower still: single-track lanes, left alone)
M.stats = { graphs = 0, junctions = 0, promoted = 0, demoted = 0, signsDropped = 0, widened = 0, lanesAdded = 0, twoWayFixed = 0 }

M.real = {}                 -- 'a\0b' -> the edge's real half width (before the widening)

-- the real half width of the road between graph nodes a and b (nil: not known)
function M.realHalf(a, b) return a and b and M.real[a .. '\0' .. b] or nil end

local function score(e)
  -- class first (drivability), then width, then the speed
  return (e[7] or 0.5) * 10 + (e[8] or 2.5) + (e[6] or 10) / 20
end

function M.process(g)
  if type(g) ~= 'table' or type(g.nodes) ~= 'table' or type(g.edges) ~= 'table' then return end
  M.real = {}
  local nodes, edges = g.nodes, g.edges
  for _, e in ipairs(edges) do
    local r = e[8]
    -- (2026-11-10: a carriageway of its own as wide as two lanes, with one lane on the map because OpenStreetMap has no lane count for it: its
    -- "lane" is the whole width, and the cars drove down the middle of it, on the line. Fast roads only: a one-way street in town stays one lane.)
    if e[3] == 1 and r and (e[6] or 0) >= 19.4 then
      local n = math.min(4, math.floor(2 * r / 3.2))
      if n > (e[4] or 1) then e[4] = n; M.stats.lanesAdded = M.stats.lanesAdded + 1 end
    end
    -- (a road for both ways with no lane for one of them: the AI would use its whole width)
    if e[3] ~= 1 and ((e[4] or 1) < 1 or (e[5] or 1) < 1) then
      e[4], e[5] = math.max(1, e[4] or 1), math.max(1, e[5] or 1)
      M.stats.twoWayFixed = M.stats.twoWayFixed + 1
    end
    -- (the real half width of the asphalt, for whoever puts things beside the road: M.realHalf)
    if r and e[1] and e[2] then M.real[e[1] .. '\0' .. e[2]] = r; M.real[e[2] .. '\0' .. e[1]] = r end
    if e[3] ~= 1 and r and r >= M.WIDEN_FROM and r < M.MIN_RADIUS and (e[4] or 1) <= 1 and (e[5] or 1) >= 1 then
      e[8] = math.min(M.MIN_RADIUS, r + M.WIDEN_BY)
      M.stats.widened = M.stats.widened + 1
    end
  end
  local adj = {}
  for i, e in ipairs(edges) do
    local a, b = e[1], e[2]
    if a and b and a ~= b then
      adj[a] = adj[a] or {}; table.insert(adj[a], { i = i, other = b })
      adj[b] = adj[b] or {}; table.insert(adj[b], { i = i, other = a })
    end
  end
  local mainAt = {}                -- junction node -> { pair = { edge, edge }, sides = { edge, ... } }: a real priority road
  local throughAt = {}             -- junction node -> { [edge index] = true }: the road going straight on, for the signs
  for name, list in pairs(adj) do
    local n = nodes[name]
    if #list >= 3 and n then
      -- the directions out of the junction
      local dirs = {}
      for k, l in ipairs(list) do
        local o = nodes[l.other]
        if o then
          local dx, dy = o[1] - n[1], o[2] - n[2]
          local len = math.sqrt(dx * dx + dy * dy)
          dirs[k] = len > 0.1 and { dx / len, dy / len } or nil
        end
      end
      -- the best straight-through pair
      local bi, bj, bs
      for x = 1, #list - 1 do
        for y = x + 1, #list do
          local dx, dy = dirs[x], dirs[y]
          if dx and dy then
            local dot = dx[1] * dy[1] + dx[2] * dy[2]
            if dot <= M.STRAIGHT then
              local s = math.min(score(edges[list[x].i]), score(edges[list[y].i])) * 2 - dot
              if not bs or s > bs then bi, bj, bs = x, y, s end
            end
          end
        end
      end
      if bi then
        local ei, ej = edges[list[bi].i], edges[list[bj].i]
        local mainMin = math.min(score(ei), score(ej))
        local mainMax = math.max(score(ei), score(ej))
        local sideMax, sides = -math.huge, {}
        for k, l in ipairs(list) do
          if k ~= bi and k ~= bj then sideMax = math.max(sideMax, score(edges[l.i])); sides[#sides + 1] = l.i end
        end
        throughAt[name] = { [list[bi].i] = true, [list[bj].i] = true }
        -- a real main road: at least as good as any side road, and better at one end (two equal roads crossing: left alone).
        -- (2026-11-09: "better at both ends" missed the commonest place: the road's class changes where a street as good as its
        -- lower piece joins. Cars coming along the lower piece gave way there, on the main road.)
        if mainMin >= sideMax - 0.05 and mainMax > sideMax + 0.05 then
          M.stats.junctions = M.stats.junctions + 1
          mainAt[name] = { pair = { list[bi].i, list[bj].i }, sides = sides }
        end
      end
    end
  end
  -- one rating along the whole main road. (2026-11-09: each junction on its own raised a piece to its neighbour's rating, and that piece
  -- then stood higher than its next neighbour: the next junction along became a give-way. Passed on until nothing changes.)
  local val, isMain = {}, {}
  for _, m in pairs(mainAt) do
    for _, i in ipairs(m.pair) do isMain[i] = true; val[i] = edges[i][7] or 0 end
  end
  for _ = 1, 60 do
    local changed = false
    for _, m in pairs(mainAt) do
      local a, b = m.pair[1], m.pair[2]
      local top = math.max(val[a], val[b])
      for _, s in ipairs(m.sides) do if isMain[s] then top = math.max(top, val[s]) end end
      if val[a] < top then val[a] = top; changed = true end
      if val[b] < top then val[b] = top; changed = true end
    end
    if not changed then break end
  end
  local lower = {}
  for _, m in pairs(mainAt) do
    local ceil = math.max(0.05, val[m.pair[1]] * M.SIDE_SHARE)
    for _, s in ipairs(m.sides) do
      if not isMain[s] and (edges[s][7] or 0) > ceil then lower[s] = math.min(lower[s] or ceil, ceil) end
    end
  end
  for i, d in pairs(lower) do edges[i][7] = d; M.stats.demoted = M.stats.demoted + 1 end
  for i, d in pairs(val) do
    if (edges[i][7] or 0) < d then edges[i][7] = d; M.stats.promoted = M.stats.promoted + 1 end
  end
  -- stop / give-way signs: only on the roads that do not go straight on (no four-way stops here: one road always has the right of way)
  if type(g.signals) == 'table' then
    local edgeOf = {}
    for i, e in ipairs(edges) do
      if e[1] and e[2] then edgeOf[e[1] .. '\0' .. e[2]] = i; edgeOf[e[2] .. '\0' .. e[1]] = i end
    end
    for _, s in ipairs(g.signals) do
      local main = s.j and throughAt[s.j]
      if main and s.kind ~= 'signal' and type(s.app) == 'table' then
        local keep = {}
        for _, a in ipairs(s.app) do
          local ei = a[1] and edgeOf[a[1] .. '\0' .. s.j]
          if ei and main[ei] then M.stats.signsDropped = M.stats.signsDropped + 1 else keep[#keep + 1] = a end
        end
        s.app = keep
      end
    end
  end
  M.stats.graphs = M.stats.graphs + 1
  if M.stats.graphs % 20 == 1 then
    local st = M.stats
    log('I', 'fernfahrer', string.format('priority roads: graph %d: %d junctions, %d pieces raised, %d side roads lowered, %d signs dropped, %d widened, %d carriageways given their lanes, %d two-way roads repaired', st.graphs, st.junctions, st.promoted, st.demoted, st.signsDropped, st.widened, st.lanesAdded, st.twoWayFixed))
  end
end

-- hooks into BeamNG.Earth's navgraph (once): every graph it receives is fixed up first
function M.install()
  local ok, ng = pcall(require, 'beamngEarth/navgraph')
  if not ok or type(ng) ~= 'table' or not ng.onMessage then return false end
  if ng.__fernfahrerPriority then return true end
  local orig = ng.onMessage
  ng.onMessage = function(msg, anchor)
    local r = orig(msg, anchor)
    if r and ng.currentGraph and M.enabled ~= false then
      local okP, err = pcall(M.process, ng.currentGraph())
      if not okP then log('W', 'fernfahrer', 'priority roads: ' .. tostring(err)) end
    end
    return r
  end
  ng.__fernfahrerPriority = true
  log('I', 'fernfahrer', 'priority roads: hooked into the BeamNG.Earth road graph')
  return true
end

return M
