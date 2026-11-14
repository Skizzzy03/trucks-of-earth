-- Trucks of Earth: the kinds of real places and what can be hauled between them.
-- Place types are searched around the home with the BeamNG.Earth geocoder (Photon / OpenStreetMap): `queries` in
-- order (the first that finds something counts at a search point), `kinds` the OSM values that confirm a hit (when the
-- geocoder reports one), `strict` keeps hits without a confirming kind out. `facility` places are not freight depots:
-- fuel, workshops, dealers, viewpoints ... with an `action` the HUD offers on site within `radius` m.
-- Cargo goes from a depot of one of its `from` types to one of its `to` types, on one of its `trailers`
-- ({model, config}: stock fifth-wheel semi trailers).
-- Add-ons: fernfahrer_career.registerDepotType{...} / registerCargo{...}. `enabled = false`: prepared, not offered yet.

local M = {}

M.DEPOT_TYPES = {
  -- freight depots
  { key = 'logistics',   name = 'Logistikzentrum',    icon = '🏭', queries = { 'Logistikzentrum', 'Spedition', 'warehouse' }, kinds = { 'warehouse', 'logistics', 'industrial', 'company' }, hub = true },
  { key = 'post',        name = 'Paketzentrum',       icon = '📮', queries = { 'Paketzentrum', 'Briefzentrum', 'post depot' }, kinds = { 'post_depot', 'post_office', 'warehouse' }, hub = true },
  { key = 'supermarket', name = 'Supermarkt',         icon = '🛒', queries = { 'Supermarkt', 'supermarket' }, kinds = { 'supermarket' } },
  { key = 'hardware',    name = 'Baumarkt',           icon = '🔨', queries = { 'Baumarkt', 'hardware store' }, kinds = { 'doityourself', 'hardware' } },
  { key = 'furniture',   name = 'Möbelhaus',          icon = '🛋️', secure = true, queries = { 'Möbelhaus', 'furniture store' }, kinds = { 'furniture' } },
  { key = 'industry',    name = 'Gewerbegebiet',      icon = '⚙️', queries = { 'Industriegebiet', 'Gewerbegebiet', 'industrial estate' }, kinds = { 'industrial', 'works', 'company' } },
  { key = 'drinks',      name = 'Getränkehersteller', icon = '🍺', queries = { 'Brauerei', 'Getränkemarkt', 'brewery' }, kinds = { 'brewery', 'beverages' } },
  { key = 'dairy',       name = 'Molkerei',           icon = '🥛', queries = { 'Molkerei', 'Käserei', 'dairy' }, kinds = { 'dairy' } },
  { key = 'timber',      name = 'Sägewerk',           icon = '🪵', queries = { 'Sägewerk', 'Holzhandel', 'sawmill' }, kinds = { 'sawmill', 'timber' } },
  { key = 'building',    name = 'Baustoffhandel',     icon = '🧱', queries = { 'Baustoffhandel', 'Baustoffe', 'builders merchant' }, kinds = { 'trade', 'building_materials' } },
  -- agricultural traders (Raiffeisen & Co. sit on proper roads; farms themselves are often down narrow lanes)
  { key = 'farm',        name = 'Agrarhandel',        icon = '🌾', queries = { 'Raiffeisen', 'Landhandel', 'Agrarhandel', 'agricultural supply' }, kinds = { 'agrarian', 'farm', 'garden_centre', 'trade' } },
  { key = 'port',        name = 'Hafen / Terminal',   icon = '🚢', queries = { 'Containerterminal', 'Hafen', 'container terminal' }, kinds = { 'port', 'harbour', 'container_terminal' } },
  -- (2026-11-07) for the dangerous goods and the steel: a fuel depot, a chemical park, a steel works
  { key = 'tankfarm',    name = 'Tanklager',          icon = '🛢️', queries = { 'Tanklager', 'Raffinerie', 'fuel depot' }, kinds = { 'fuel_depot', 'oil_terminal', 'refinery', 'industrial' } },
  { key = 'chemical',    name = 'Chemiepark',         icon = '⚗️', queries = { 'Chemiepark', 'Chemiewerk', 'chemical plant' }, kinds = { 'chemical', 'industrial', 'works' } },
  { key = 'steel',       name = 'Stahlwerk',          icon = '🏗️', queries = { 'Stahlwerk', 'Stahlhandel', 'steel works' }, kinds = { 'steel', 'metal', 'works', 'industrial' } },
  { key = 'scrap',       name = 'Autoverwertung',     icon = '♻️', queries = { 'Autoverwertung', 'Schrottplatz', 'scrap yard' }, kinds = { 'scrap_yard', 'recycling', 'car_parts', 'industrial' } },

  -- facilities (places to drive to)
  { key = 'rest',        name = 'Rastplatz',          icon = '🅿️', queries = { 'Rastplatz', 'Rastanlage', 'rest area' }, kinds = { 'rest_area', 'services', 'parking' }, strict = true, facility = true, radius = 260, action = 'sleep' },
  { key = 'fuel',        name = 'Tankstelle',         icon = '⛽', queries = { 'Tankstelle', 'Autohof', 'fuel' }, kinds = { 'fuel' }, strict = true, facility = true, radius = 70, action = 'refuel' },
  { key = 'workshop',    name = 'LKW-Werkstatt',      icon = '🔧', queries = { 'LKW Werkstatt', 'Nutzfahrzeug Service', 'Autowerkstatt', 'truck repair' }, kinds = { 'car_repair', 'truck_repair' }, facility = true, radius = 90, action = 'repair' },
  { key = 'truckdealer', name = 'LKW-Händler',        icon = '🚛', queries = { 'Nutzfahrzeuge', 'LKW Händler', 'Truck Center', 'truck dealer' }, kinds = { 'truck', 'car', 'trade' }, facility = true, radius = 120, action = 'dealerTruck' },
  { key = 'cardealer',   name = 'Autohaus',           icon = '🚗', queries = { 'Autohaus', 'car dealer' }, kinds = { 'car' }, facility = true, radius = 100, action = 'dealerCar' },
  { key = 'viewpoint',   name = 'Aussichtspunkt',     icon = '🔭', queries = { 'Aussichtspunkt', 'Aussichtsturm', 'viewpoint' }, kinds = { 'viewpoint', 'tower', 'observation' }, strict = true, facility = true, radius = 150, action = 'discover' },
}

M.CARGO = {
  { key = 'general',   name = 'Stückgut',      icon = '📦', secure = true, t = 14, mult = 1.00,
    from = { 'logistics', 'industry' }, to = { 'logistics', 'industry', 'supermarket', 'hardware' },
    trailers = { { 'dryvan', '53ft_13500kg' }, { 'eu_trailers', 'box3a' } } },
  { key = 'parcels',   name = 'Pakete',        icon = '📮', t = 9, mult = 1.05,
    from = { 'post', 'logistics' }, to = { 'post', 'logistics', 'supermarket' },
    trailers = { { 'eu_trailers', 'box3a' }, { 'dryvan', '53ft' } } },
  -- supermarkets are supplied from distribution centres, not straight from farms
  { key = 'food',      name = 'Lebensmittel',  icon = '🥫', t = 16, mult = 1.05,
    from = { 'logistics' }, to = { 'supermarket' },
    trailers = { { 'eu_trailers', 'box3a' }, { 'dryvan', '48ft_19200kg' } } },
  { key = 'drinks',    name = 'Getränke',      icon = '🥤', t = 18, mult = 1.05,
    from = { 'drinks', 'logistics' }, to = { 'supermarket', 'drinks' },
    trailers = { { 'eu_trailers', 'box3a_cola' } } },
  { key = 'chilled',   name = 'Kühlware',      icon = '🧀', t = 15, mult = 1.10, fragile = true,
    from = { 'dairy', 'logistics' }, to = { 'supermarket' },
    trailers = { { 'eu_trailers', 'box3a_muhten' } } },
  -- (2026-11-07: on – from the agricultural traders' collecting points, which sit on proper roads, in the milk tanker)
  { key = 'milk',      name = 'Rohmilch',      icon = '🥛', t = 25, mult = 1.10,
    from = { 'farm' }, to = { 'dairy' },
    trailers = { { 'tanker', 'milk_3' } } },
  -- dairy products in the milk tanker the other way: whey and cream to the food industry
  { key = 'cream',     name = 'Sahne & Molke', icon = '🍶', t = 22, mult = 1.10,
    from = { 'dairy' }, to = { 'industry', 'dairy' },
    trailers = { { 'tanker', 'milk_3' } } },
  { key = 'furniture', name = 'Möbel',         icon = '🛋️', secure = true, t = 11, mult = 1.10, fragile = true,
    from = { 'logistics', 'industry' }, to = { 'furniture' },
    trailers = { { 'eu_trailers', 'box3a' }, { 'dryvan', '53ft' } } },
  { key = 'lumber',    name = 'Schnittholz',   icon = '🪵', secure = true, t = 22, mult = 1.05,
    from = { 'timber' }, to = { 'hardware', 'building', 'furniture' },
    trailers = { { 'eu_trailers', 'flatbed3a_wood' } } },
  -- (later: a forest loading place type)
  { key = 'logs',      name = 'Rundholz',      icon = '🌲', t = 27, mult = 1.10, enabled = false,
    from = { 'farm' }, to = { 'timber' },
    trailers = { { 'log_trailer', '40ft_12logs' } } },
  { key = 'material',  name = 'Baumaterial',   icon = '🧱', secure = true, t = 24, mult = 1.05,
    from = { 'building', 'industry' }, to = { 'hardware', 'building', 'industry' },
    trailers = { { 'eu_trailers', 'flatbed3a_pipes' }, { 'flatbed', '48ft_tires' } } },
  { key = 'fertilizer', name = 'Dünger & Saatgut', icon = '🌱', t = 20, mult = 1.00,
    from = { 'industry', 'logistics' }, to = { 'farm' },
    trailers = { { 'eu_trailers', 'box3a' }, { 'dryvan', '48ft_19200kg' } } },
  { key = 'container', name = 'Container',     icon = '🚢', t = 26, mult = 1.15,
    from = { 'port', 'logistics' }, to = { 'logistics', 'industry' },
    trailers = { { 'eu_trailers', 'flatbed3a_container_40ft' }, { 'containerTrailer', '40ft_3axle_40ft' } } },
  -- (2026-11-07) dangerous goods (ADR, the orange plate): better pay, from the fuel depots and chemical parks
  { key = 'diesel',    name = 'Diesel (ADR)',  icon = '⛽', t = 30, mult = 1.45, adr = true,
    from = { 'tankfarm' }, to = { 'fuel', 'logistics' },
    trailers = { { 'tanker', 'diesel_3' } } },
  { key = 'petrol',    name = 'Benzin (ADR)',  icon = '🔥', t = 28, mult = 1.55, adr = true, fragile = true,
    from = { 'tankfarm' }, to = { 'fuel' },
    trailers = { { 'tanker', 'petroleum_3' } } },
  { key = 'chemicals', name = 'Chemikalien (ADR)', icon = '☣️', t = 24, mult = 1.60, adr = true, fragile = true,
    from = { 'chemical' }, to = { 'industry', 'chemical', 'logistics' },
    trailers = { { 'eu_trailers', 'flatbed3a_container_tank' }, { 'containerTrailer', '40ft_3axle_tank' } } },
  { key = 'water',     name = 'Trinkwasser',   icon = '💧', t = 26, mult = 1.00,
    from = { 'industry', 'drinks' }, to = { 'drinks', 'industry' },
    trailers = { { 'tanker', 'water_3' } } },
  { key = 'coils',     name = 'Stahlcoils',    icon = '🧲', secure = true, t = 26, mult = 1.20,
    from = { 'steel' }, to = { 'industry', 'building', 'logistics' },
    trailers = { { 'flatbed', '48ft_coil' }, { 'flatbed', '53ft_coils_double' } } },
  { key = 'steelpipes', name = 'Stahlrohre',   icon = '🔩', secure = true, t = 22, mult = 1.10,
    from = { 'steel' }, to = { 'building', 'industry' },
    trailers = { { 'eu_trailers', 'flatbed3a_pipes' }, { 'flatbed', '53ft_pipes' } } },
  { key = 'boxes20',   name = 'Zwei 20-Fuß-Container', icon = '📦', t = 24, mult = 1.15,
    from = { 'port' }, to = { 'logistics', 'industry' },
    trailers = { { 'eu_trailers', 'flatbed3a_container_20ftx2' }, { 'containerTrailer', '40ft_3axle_20ft_double' } } },
  -- (2026-11-08) the car transporter: the EU flatbed with three cars tied down – the load is part of the trailer
  -- (vehicles/eu_trailers/ff_cars.*, tools/build_cars.js), for every player: no mod needed, no extra vehicles to simulate
  { key = 'cars',      name = 'Neuwagen',      icon = '🚗', secure = true, t = 5, mult = 1.3, fragile = true,
    from = { 'port', 'logistics' }, to = { 'cardealer', 'logistics' },
    trailers = { { 'eu_trailers', 'ff_cars_new' }, { 'eu_trailers', 'ff_cars_new2' } } },
  { key = 'wrecks',    name = 'Autowracks',    icon = '🚙', secure = true, t = 3, mult = 1.05,
    from = { 'scrap' }, to = { 'steel', 'scrap' },
    trailers = { { 'eu_trailers', 'ff_wrecks' } } },
}

-- Standing tours: always on the offer list (career topUpOffers). (2026-11-05: none in the published mod – the one
-- there was tied to one place; every tour now comes from the places around the player's own yard.)
M.SPECIAL = {}

return M
