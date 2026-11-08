-- Trucks of Earth: priority roads on BeamNG.Earth's road graph ("Vorfahrtsstraße", automatically).
-- BeamNG's traffic AI gives way at a junction when it turns, or when the road it comes from has a lower drivability
-- than another one there (ai.lua, uncontrolled intersections); and Earth turns an OpenStreetMap stop sign at a
-- junction into a stop for every approach. So cars on a main road braked at side streets: where the main road's
-- class changes at a junction (its next piece rated lower), where a side street was rated the same, at stop signs.
-- Every graph Earth sends (navgraph.onMessage) is fixed up before it is used: at each junction the through pair (the
-- two best-rated roads going straight on) becomes the priority road – both of its pieces get the pair's rating, every
-- other road there a lower one – and stop / give-way signs stay only on the side roads. Crossings of two equal
-- roads stay as they are (right before left). Traffic lights are not touched.
-- Graph format (beamngEarth/navgraph.lua): nodes[name] = {x, y, z, radius, ...}; edges[i] = {a, b, oneWay, lanesOut,
-- lanesBack, speed m/s, drivability, radius}; signals[i] = {j = node, kind, app = {{node, x, y, z, dx, dy, phase}}}.

local M = {}

M.STRAIGHT = -0.6           -- the through pair: their directions out of the junction at least this opposite (~127°)
M.SIDE_DROP = 0.1           -- a side road as good as the main road is rated this much lower at the junction
-- Oncoming room: the AI brakes for an oncoming vehicle whose line comes within half their two widths of its own
-- (ai.lua awareness: 0.505 * (ego + other width)) – a car (1.9 m) meeting a truck (2.55 m) at 2.22 m. Earth's
-- ordinary streets are 2.75 m a lane (radius 2.75): lane centres 2.75 m apart, so a truck a few decimetres off its
-- lane centre made every oncoming car stop. Two-way streets of that kind get MIN_RADIUS for the AI: its lane centre
-- moves out to 1.75 m from the centre line (the car's right side at 2.7 m: still on the 2.75 m of asphalt), so the
-- AI brakes only once a truck's centre comes within 2.25 m of that line, i.e. less than 0.5 m right of the centre
-- line: a truck (2.55 m) can ride with its left side up to ~0.75 m over the centre line before an oncoming car
-- brakes (with its left side on the line itself: 0.75 m to spare).
M.MIN_RADIUS = 3.5
M.WIDEN_BY = 0.75           -- narrower two-way roads: this much more (2.5 -> 3.25), at most MIN_RADIUS
M.WIDEN_FROM = 2.3          -- (narrower still: single-track lanes, left alone)
M.stats = { graphs = 0, junctions = 0, promoted = 0, demoted = 0, signsDropped = 0, widened = 0 }

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
  local raise, lower = {}, {}      -- edge index -> new drivability (raises win over lowers)
  local mainAt = {}                -- junction node -> { [edge index] = true } of its priority pair
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
        local sideMax = -math.huge
        for k, l in ipairs(list) do
          if k ~= bi and k ~= bj then sideMax = math.max(sideMax, score(edges[l.i])) end
        end
        -- a real main road: not worse than any side road (two equal roads crossing: left alone)
        if mainMin > sideMax + 0.05 then
          M.stats.junctions = M.stats.junctions + 1
          local drv = math.max(ei[7] or 0, ej[7] or 0)
          raise[list[bi].i] = math.max(raise[list[bi].i] or 0, drv)
          raise[list[bj].i] = math.max(raise[list[bj].i] or 0, drv)
          mainAt[name] = { [list[bi].i] = true, [list[bj].i] = true }
          for k, l in ipairs(list) do
            if k ~= bi and k ~= bj then
              local d = edges[l.i][7] or 0
              if d > drv - M.SIDE_DROP then lower[l.i] = math.min(lower[l.i] or d, math.max(0.05, drv - M.SIDE_DROP)) end
            end
          end
        end
      end
    end
  end
  for i, d in pairs(lower) do
    if not raise[i] and (edges[i][7] or 0) > d then edges[i][7] = d; M.stats.demoted = M.stats.demoted + 1 end
  end
  for i, d in pairs(raise) do
    if (edges[i][7] or 0) < d then edges[i][7] = d; M.stats.promoted = M.stats.promoted + 1 end
  end
  -- stop / give-way signs: only on the side roads of a priority junction
  if type(g.signals) == 'table' then
    local edgeOf = {}
    for i, e in ipairs(edges) do
      if e[1] and e[2] then edgeOf[e[1] .. '\0' .. e[2]] = i; edgeOf[e[2] .. '\0' .. e[1]] = i end
    end
    for _, s in ipairs(g.signals) do
      local main = s.j and mainAt[s.j]
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
