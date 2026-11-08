-- Trucks of Earth: travel where BeamNG.Earth has no road: ferries (and the Channel Tunnel shuttle) take the
-- truck with its trailer across; flights take the driver alone (the vehicle stays behind, a rental car waits at
-- the arrival airport). Real terminals and crossing times (rounded); prices in the style of Euro Truck Simulator.
-- career.lua: hubsNear, routesFrom, flightsFrom, byId. Add-ons: table.insert(M.HUBS, {...}) and M.ROUTES.

local M = {}

-- kind: 'ferry' (a port or the tunnel terminal) | 'airport'
M.HUBS = {
  -- the Channel
  { id = 'f_calais', kind = 'ferry', name = 'Fährhafen Calais', lat = 50.9655, lon = 1.8720, cc = 'FR' },
  { id = 'f_coquelles', kind = 'ferry', name = 'Eurotunnel Calais (Coquelles)', lat = 50.9265, lon = 1.8160, cc = 'FR', train = true },
  { id = 'f_dunkerque', kind = 'ferry', name = 'Fährhafen Dunkerque', lat = 51.0200, lon = 2.2010, cc = 'FR' },
  { id = 'f_dover', kind = 'ferry', name = 'Port of Dover', lat = 51.1265, lon = 1.3290, cc = 'GB' },
  { id = 'f_folkestone', kind = 'ferry', name = 'Eurotunnel Folkestone', lat = 51.0960, lon = 1.1380, cc = 'GB', train = true },
  { id = 'f_caen', kind = 'ferry', name = 'Fährhafen Caen-Ouistreham', lat = 49.2850, lon = -0.2490, cc = 'FR' },
  { id = 'f_portsmouth', kind = 'ferry', name = 'Portsmouth International Port', lat = 50.8130, lon = -1.0930, cc = 'GB' },
  { id = 'f_cherbourg', kind = 'ferry', name = 'Fährhafen Cherbourg', lat = 49.6500, lon = -1.6160, cc = 'FR' },
  -- the North Sea
  { id = 'f_hoek', kind = 'ferry', name = 'Hoek van Holland Stena Terminal', lat = 51.9780, lon = 4.1300, cc = 'NL' },
  { id = 'f_europoort', kind = 'ferry', name = 'Europoort P&O Terminal', lat = 51.9550, lon = 4.1250, cc = 'NL' },
  { id = 'f_ijmuiden', kind = 'ferry', name = 'IJmuiden DFDS Terminal', lat = 52.4650, lon = 4.5990, cc = 'NL' },
  { id = 'f_harwich', kind = 'ferry', name = 'Harwich International Port', lat = 51.9470, lon = 1.2560, cc = 'GB' },
  { id = 'f_hull', kind = 'ferry', name = 'Hull King George Dock', lat = 53.7390, lon = -0.2760, cc = 'GB' },
  { id = 'f_newcastle', kind = 'ferry', name = 'Newcastle International Ferry Terminal', lat = 55.0060, lon = -1.4560, cc = 'GB' },
  { id = 'f_holyhead', kind = 'ferry', name = 'Holyhead Port', lat = 53.3100, lon = -4.6290, cc = 'GB' },
  { id = 'f_dublin', kind = 'ferry', name = 'Dublin Port', lat = 53.3480, lon = -6.2010, cc = 'IE' },
  { id = 'f_rosslare', kind = 'ferry', name = 'Rosslare Europort', lat = 52.2520, lon = -6.3380, cc = 'IE' },
  -- Scandinavia and the Baltic
  { id = 'f_kiel_oslo', kind = 'ferry', name = 'Kiel Norwegenkai', lat = 54.3160, lon = 10.1360, cc = 'DE' },
  { id = 'f_kiel_sweden', kind = 'ferry', name = 'Kiel Schwedenkai', lat = 54.3170, lon = 10.1440, cc = 'DE' },
  { id = 'f_travemunde', kind = 'ferry', name = 'Travemünde Skandinavienkai', lat = 53.9440, lon = 10.8490, cc = 'DE' },
  { id = 'f_puttgarden', kind = 'ferry', name = 'Fährhafen Puttgarden', lat = 54.5000, lon = 11.2250, cc = 'DE' },
  { id = 'f_rostock', kind = 'ferry', name = 'Rostock Überseehafen', lat = 54.1520, lon = 12.1020, cc = 'DE' },
  { id = 'f_sassnitz', kind = 'ferry', name = 'Fährhafen Sassnitz-Mukran', lat = 54.4810, lon = 13.6040, cc = 'DE' },
  { id = 'f_rodby', kind = 'ferry', name = 'Rødby Færgehavn', lat = 54.6560, lon = 11.3530, cc = 'DK' },
  { id = 'f_gedser', kind = 'ferry', name = 'Gedser Færgehavn', lat = 54.5740, lon = 11.9280, cc = 'DK' },
  { id = 'f_ronne', kind = 'ferry', name = 'Rønne Havn', lat = 55.0960, lon = 14.6930, cc = 'DK' },
  { id = 'f_hirtshals', kind = 'ferry', name = 'Hirtshals Havn', lat = 57.5940, lon = 9.9690, cc = 'DK' },
  { id = 'f_frederikshavn', kind = 'ferry', name = 'Frederikshavn Havn', lat = 57.4400, lon = 10.5440, cc = 'DK' },
  { id = 'f_oslo', kind = 'ferry', name = 'Oslo Color Line Terminal', lat = 59.9030, lon = 10.7390, cc = 'NO' },
  { id = 'f_kristiansand', kind = 'ferry', name = 'Kristiansand Ferjeterminal', lat = 58.1450, lon = 7.9960, cc = 'NO' },
  { id = 'f_goteborg', kind = 'ferry', name = 'Göteborg Stena Terminal', lat = 57.7010, lon = 11.9450, cc = 'SE' },
  { id = 'f_trelleborg', kind = 'ferry', name = 'Trelleborgs Hamn', lat = 55.3720, lon = 13.1550, cc = 'SE' },
  { id = 'f_malmo', kind = 'ferry', name = 'Malmö Hamn (Finnlines)', lat = 55.6300, lon = 12.9930, cc = 'SE' },
  { id = 'f_helsinki', kind = 'ferry', name = 'Helsinki Vuosaari', lat = 60.2060, lon = 25.1910, cc = 'FI' },
  { id = 'f_tallinn', kind = 'ferry', name = 'Tallinn Muuga / Vanasadam', lat = 59.4430, lon = 24.7680, cc = 'EE' },
  -- the Mediterranean
  { id = 'f_genova', kind = 'ferry', name = 'Porto di Genova', lat = 44.4110, lon = 8.9080, cc = 'IT' },
  { id = 'f_ancona', kind = 'ferry', name = 'Porto di Ancona', lat = 43.6190, lon = 13.5050, cc = 'IT' },
  { id = 'f_palermo', kind = 'ferry', name = 'Porto di Palermo', lat = 38.1270, lon = 13.3660, cc = 'IT' },
  { id = 'f_barcelona', kind = 'ferry', name = 'Port de Barcelona', lat = 41.3680, lon = 2.1820, cc = 'ES' },
  { id = 'f_igoumenitsa', kind = 'ferry', name = 'Hafen Igoumenitsa', lat = 39.5050, lon = 20.2600, cc = 'GR' },

  -- airports (the terminals' landside)
  { id = 'a_fra', kind = 'airport', iata = 'FRA', name = 'Flughafen Frankfurt', lat = 50.0510, lon = 8.5710, cc = 'DE' },
  { id = 'a_muc', kind = 'airport', iata = 'MUC', name = 'Flughafen München', lat = 48.3530, lon = 11.7860, cc = 'DE' },
  { id = 'a_ber', kind = 'airport', iata = 'BER', name = 'Flughafen Berlin Brandenburg', lat = 52.3640, lon = 13.5090, cc = 'DE' },
  { id = 'a_dus', kind = 'airport', iata = 'DUS', name = 'Flughafen Düsseldorf', lat = 51.2790, lon = 6.7660, cc = 'DE' },
  { id = 'a_ham', kind = 'airport', iata = 'HAM', name = 'Flughafen Hamburg', lat = 53.6320, lon = 10.0060, cc = 'DE' },
  { id = 'a_cgn', kind = 'airport', iata = 'CGN', name = 'Flughafen Köln/Bonn', lat = 50.8790, lon = 7.1220, cc = 'DE' },
  { id = 'a_str', kind = 'airport', iata = 'STR', name = 'Flughafen Stuttgart', lat = 48.6900, lon = 9.1930, cc = 'DE' },
  { id = 'a_lhr', kind = 'airport', iata = 'LHR', name = 'London Heathrow', lat = 51.4720, lon = -0.4880, cc = 'GB' },
  { id = 'a_cdg', kind = 'airport', iata = 'CDG', name = 'Paris Charles de Gaulle', lat = 49.0040, lon = 2.5710, cc = 'FR' },
  { id = 'a_ams', kind = 'airport', iata = 'AMS', name = 'Amsterdam Schiphol', lat = 52.3090, lon = 4.7630, cc = 'NL' },
  { id = 'a_bru', kind = 'airport', iata = 'BRU', name = 'Brussels Airport', lat = 50.8980, lon = 4.4840, cc = 'BE' },
  { id = 'a_zrh', kind = 'airport', iata = 'ZRH', name = 'Flughafen Zürich', lat = 47.4510, lon = 8.5620, cc = 'CH' },
  { id = 'a_vie', kind = 'airport', iata = 'VIE', name = 'Flughafen Wien', lat = 48.1200, lon = 16.5630, cc = 'AT' },
  { id = 'a_prg', kind = 'airport', iata = 'PRG', name = 'Letiště Praha', lat = 50.1070, lon = 14.2700, cc = 'CZ' },
  { id = 'a_waw', kind = 'airport', iata = 'WAW', name = 'Lotnisko Chopina Warszawa', lat = 52.1700, lon = 20.9730, cc = 'PL' },
  { id = 'a_cph', kind = 'airport', iata = 'CPH', name = 'Københavns Lufthavn', lat = 55.6290, lon = 12.6470, cc = 'DK' },
  { id = 'a_osl', kind = 'airport', iata = 'OSL', name = 'Oslo Gardermoen', lat = 60.1940, lon = 11.1000, cc = 'NO' },
  { id = 'a_arn', kind = 'airport', iata = 'ARN', name = 'Stockholm Arlanda', lat = 59.6500, lon = 17.9300, cc = 'SE' },
  { id = 'a_dub', kind = 'airport', iata = 'DUB', name = 'Dublin Airport', lat = 53.4270, lon = -6.2440, cc = 'IE' },
  { id = 'a_mad', kind = 'airport', iata = 'MAD', name = 'Madrid-Barajas', lat = 40.4720, lon = -3.5630, cc = 'ES' },
  { id = 'a_bcn', kind = 'airport', iata = 'BCN', name = 'Barcelona-El Prat', lat = 41.2890, lon = 2.0730, cc = 'ES' },
  { id = 'a_fco', kind = 'airport', iata = 'FCO', name = 'Roma Fiumicino', lat = 41.7930, lon = 12.2510, cc = 'IT' },
  { id = 'a_mxp', kind = 'airport', iata = 'MXP', name = 'Milano Malpensa', lat = 45.6270, lon = 8.7110, cc = 'IT' },
  { id = 'a_ist', kind = 'airport', iata = 'IST', name = 'İstanbul Havalimanı', lat = 41.2620, lon = 28.7420, cc = 'TR' },
  { id = 'a_jfk', kind = 'airport', iata = 'JFK', name = 'New York JFK', lat = 40.6440, lon = -73.7820, cc = 'US' },
  { id = 'a_ord', kind = 'airport', iata = 'ORD', name = "Chicago O'Hare", lat = 41.9770, lon = -87.9040, cc = 'US' },
  { id = 'a_atl', kind = 'airport', iata = 'ATL', name = 'Atlanta Hartsfield-Jackson', lat = 33.6400, lon = -84.4440, cc = 'US' },
  { id = 'a_dfw', kind = 'airport', iata = 'DFW', name = 'Dallas/Fort Worth', lat = 32.8970, lon = -97.0380, cc = 'US' },
  { id = 'a_lax', kind = 'airport', iata = 'LAX', name = 'Los Angeles International', lat = 33.9440, lon = -118.4020, cc = 'US' },
  { id = 'a_yyz', kind = 'airport', iata = 'YYZ', name = 'Toronto Pearson', lat = 43.6810, lon = -79.6110, cc = 'CA' },
  { id = 'a_gru', kind = 'airport', iata = 'GRU', name = 'São Paulo Guarulhos', lat = -23.4320, lon = -46.4690, cc = 'BR' },
  { id = 'a_dxb', kind = 'airport', iata = 'DXB', name = 'Dubai International', lat = 25.2490, lon = 55.3530, cc = 'AE' },
  { id = 'a_nrt', kind = 'airport', iata = 'NRT', name = 'Tokyo Narita', lat = 35.7700, lon = 140.3860, cc = 'JP' },
  { id = 'a_syd', kind = 'airport', iata = 'SYD', name = 'Sydney Kingsford Smith', lat = -33.9350, lon = 151.1660, cc = 'AU' },
}

-- crossings both ways: a, b, hours, operator
M.ROUTES = {
  { 'f_calais', 'f_dover', 1.5, 'P&O Ferries / DFDS' },
  { 'f_dunkerque', 'f_dover', 2.0, 'DFDS' },
  { 'f_coquelles', 'f_folkestone', 0.6, 'Eurotunnel Le Shuttle Freight' },
  { 'f_caen', 'f_portsmouth', 6.0, 'Brittany Ferries' },
  { 'f_cherbourg', 'f_rosslare', 17.0, 'Stena Line' },
  { 'f_hoek', 'f_harwich', 7.0, 'Stena Line' },
  { 'f_europoort', 'f_hull', 11.0, 'P&O Ferries' },
  { 'f_ijmuiden', 'f_newcastle', 16.0, 'DFDS' },
  { 'f_holyhead', 'f_dublin', 3.25, 'Irish Ferries / Stena Line' },
  { 'f_kiel_oslo', 'f_oslo', 20.0, 'Color Line' },
  { 'f_kiel_sweden', 'f_goteborg', 14.0, 'Stena Line' },
  { 'f_travemunde', 'f_trelleborg', 8.0, 'TT-Line' },
  { 'f_travemunde', 'f_malmo', 9.0, 'Finnlines' },
  { 'f_travemunde', 'f_helsinki', 29.0, 'Finnlines' },
  { 'f_rostock', 'f_trelleborg', 6.0, 'TT-Line / Stena Line' },
  { 'f_rostock', 'f_gedser', 2.0, 'Scandlines' },
  { 'f_puttgarden', 'f_rodby', 0.75, 'Scandlines' },
  { 'f_sassnitz', 'f_ronne', 3.5, 'Bornholmslinjen' },
  { 'f_hirtshals', 'f_kristiansand', 3.25, 'Color Line' },
  { 'f_frederikshavn', 'f_goteborg', 3.5, 'Stena Line' },
  { 'f_helsinki', 'f_tallinn', 2.0, 'Tallink / Eckerö Line' },
  { 'f_genova', 'f_barcelona', 19.0, 'Grandi Navi Veloci' },
  { 'f_genova', 'f_palermo', 20.0, 'Grandi Navi Veloci' },
  { 'f_ancona', 'f_igoumenitsa', 16.0, 'Minoan Lines / Superfast' },
}

M.FERRY = { truckBase = 140, truckPerH = 48, carBase = 45, carPerH = 16 }
M.FLIGHT = { base = 89, perKm = 0.085, kmh = 820, extraH = 2.5 }     -- (check-in, taxi, baggage)
M.RENTAL = { fee = 95 }

local BY_ID = {}
for _, h in ipairs(M.HUBS) do BY_ID[h.id] = h end
function M.byId(id) return BY_ID[id] end

local function haversine(a, b)
  local p1, p2 = math.rad(a.lat), math.rad(b.lat)
  local dp, dl = p2 - p1, math.rad(b.lon - a.lon)
  local x = math.sin(dp / 2) ^ 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ^ 2
  return 2 * 6371000 * math.asin(math.min(1, math.sqrt(x)))
end
M.haversine = haversine

-- the hubs within km of p, nearest first, with their distance
function M.hubsNear(p, km, kind)
  local out = {}
  if not p then return out end
  for _, h in ipairs(M.HUBS) do
    if not kind or h.kind == kind then
      local d = haversine(p, h)
      if d <= km * 1000 then table.insert(out, { hub = h, dist = d }) end
    end
  end
  table.sort(out, function(a, b) return a.dist < b.dist end)
  return out
end

-- the ferry crossings from a hub: {to, hours, operator, km, price(truck/car)}
function M.routesFrom(id)
  local out = {}
  for _, r in ipairs(M.ROUTES) do
    local other = (r[1] == id and r[2]) or (r[2] == id and r[1]) or nil
    local to = other and BY_ID[other]
    if to then
      local from = BY_ID[id]
      table.insert(out, { to = to, hours = r[3], operator = r[4], km = haversine(from, to) / 1000,
        truck = math.floor(M.FERRY.truckBase + r[3] * M.FERRY.truckPerH + 0.5),
        car = math.floor(M.FERRY.carBase + r[3] * M.FERRY.carPerH + 0.5) })
    end
  end
  table.sort(out, function(a, b) return a.hours < b.hours end)
  return out
end

-- the flights from an airport to every other: {to, km, hours, price}
function M.flightsFrom(id)
  local from = BY_ID[id]
  local out = {}
  if not from or from.kind ~= 'airport' then return out end
  for _, h in ipairs(M.HUBS) do
    if h.kind == 'airport' and h.id ~= id then
      local km = haversine(from, h) / 1000
      table.insert(out, { to = h, km = km, hours = km / M.FLIGHT.kmh + M.FLIGHT.extraH,
        price = math.floor((M.FLIGHT.base + km * M.FLIGHT.perKm) / 5 + 0.5) * 5 })
    end
  end
  table.sort(out, function(a, b) return a.km < b.km end)
  return out
end

return M
