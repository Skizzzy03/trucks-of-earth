-- Made-up company names for the real places: the place and its kind stay, the real firm's name does not (a game's freight
-- jobs, smuggling and accident reports are no place for real companies). Always the same name for the same place.
-- M.make(type, real, detail, lat, lon, townFn, used) -> name; `used` a set, so that a town has no two of the same.

local M = {}

M.POOL = {
  fuel = { 'T24 Tankstelle %s', '24-Stunden-Tanke %s', 'Zapfpunkt %s', 'Blautank %s', 'Nordlicht Tankstelle %s', 'Sprit & Snack %s',
    'Freie Tanke %s', 'Tankhof %s', 'Kanister-Kalle %s', 'Diesel-Eck %s', 'Tankstopp %s', 'Autohof %s', 'Truck-Stop %s', 'Zapfhahn %s' },
  supermarket = { 'Frischemarkt %s', 'Markt am Eck %s', 'Kauf-Gut %s', 'Tagesfrisch %s', 'Korb & Kiste %s', 'Vollkorb %s', 'Sparfuchs-Markt %s',
    'Marktscheune %s', 'Wochenmarkt-Halle %s', 'Einkaufsinsel %s', 'Verbrauchermarkt %s' },
  drinks = { 'Getränke-Oase %s', 'Kistenkönig %s', 'Durstlöscher %s', 'Kiste & Kasten %s', 'Brauhaus %s', 'Quellwerk %s', 'Getränkehof %s',
    'Hopfen & Malz %s', 'Fassbrauerei %s', 'Getränkelogistik %s' },
  furniture = { 'Wohnwelt %s', 'Möbelhof %s', 'Sofa & Mehr %s', 'Holz & Heim %s', 'Einrichtungshaus %s', 'Schöner Sitzen %s', 'Möbelscheune %s', 'Wohnkontor %s' },
  hardware = { 'Schrauben-Paule %s', 'Werkzeughof %s', 'Hammer & Nagel %s', 'Baumarkt %s', 'Heimwerker-Eck %s', 'Bohrer & Co. %s', 'Selbstbau-Halle %s', 'Dübelwelt %s' },
  logistics = { 'Frachtwerk %s', 'Cargohof %s', 'Transport-Union %s', 'Logistikzentrum %s', 'Umschlaglager %s', 'Spedition Fernweh %s', 'Paletten-Kontor %s',
    'Warenstrom %s', '%s Distribution', 'Rampe 7 Logistik %s', 'Laderaum %s' },
  industry = { 'Metallwerke %s', 'Stahlbau %s', '%s Maschinenbau', 'Industriepark %s', 'Kunststofftechnik %s', 'Werkzeugbau %s', 'Gewerbepark %s', 'Anlagenbau %s',
    'Feinmechanik %s', 'Präzisionswerk %s', 'Formenbau %s' },
  dairy = { 'Molkerei %s', 'Milchhof %s', 'Landmolkerei %s', 'Käserei %s', 'Weidemilch %s', 'Butterhof %s', 'Frischmilch-Werk %s' },
  timber = { 'Sägewerk %s', 'Holzhof %s', 'Forstbetrieb %s', 'Holzkontor %s', 'Eiche & Fichte %s', 'Hobelwerk %s' },
  building = { 'Baustoffhandel %s', 'Baustoff-Zentrum %s', 'Holz & Baustoffe %s', 'Betonwerk %s', 'Stein & Mörtel %s', 'Ziegelhof %s' },
  farm = { 'Landhandel %s', 'Agrarzentrum %s', 'Saatgut & Mehr %s', 'Agrarhof %s', 'Bauernbedarf %s', 'Kornspeicher %s' },
  post = { 'Paketzentrum %s', 'Briefzentrum %s', 'Paketblitz %s', 'Sendungsstation %s', 'Kurierhof %s' },
  port = { 'Containerterminal %s', 'Binnenhafen %s', 'Hafenkontor %s', 'Umschlagkai %s' },
  tankfarm = { 'Tanklager %s', 'Mineralöl-Depot %s', 'Treibstofflager %s', 'Tankpark %s' },
  chemical = { 'Chemiepark %s', 'Chemiewerk %s', 'Farbenwerk %s', 'Laborchemie %s' },
  steel = { 'Stahlwerk %s', 'Stahlhandel %s', 'Walzwerk %s', 'Eisenhütte %s' },
  scrap = { 'Autoverwertung %s', 'Schrotthandel %s', 'Autoteile & Recycling %s', 'Blechfriedhof %s', 'Rost & Co. %s' },
  workshop = { 'Kfz-Meisterbetrieb %s', 'LKW-Service %s', 'Schrauber-Eck %s', 'Nutzfahrzeug-Werkstatt %s', 'Truck-Doktor %s', 'Motorenhof %s', 'Bremse & Achse %s' },
  truckdealer = { 'Nutzfahrzeuge %s', 'Truck-Center %s', 'Lkw-Hof %s', 'Brummi-Markt %s', 'Sattelzug-Zentrum %s' },
  cardealer = { 'Autohaus %s', 'Autopark %s', 'Wagenwelt %s', 'Fahrzeughandel %s', 'Auto-Zentrum %s', 'Blinker & Co. %s' },
  rest = { 'Rastplatz %s', 'Parkplatz %s', 'Autohof-Parkplatz %s', 'Rastplatz bei %s' },
}
M.FALLBACK_TOWN = 'Umland'

-- the town in an address: "Coesfelder Straße 10, 48653 Coesfeld" → Coesfeld
function M.townOf(detail)
  if type(detail) ~= 'string' or detail == '' then return nil end
  local last = detail:match('([^,]+)$') or ''
  last = last:gsub('^%s+', ''):gsub('%s+$', ''):gsub('^%d+%s*', '')
  -- (a street and number alone is no town)
  if last == '' or last:find('%d') or last == detail then return nil end
  return last
end

local function hash(typeKey, lat, lon)
  local s, h = string.format('%s|%d|%d', typeKey, math.floor((lat or 0) * 5000), math.floor((lon or 0) * 5000)), 2166136261
  for i = 1, #s do h = ((h * 16777619) % 4294967296 + s:byte(i)) % 4294967296 end
  return h
end

local function isPublicRest(name)
  local n = tostring(name or ''):lower()
  return n:find('rastplatz') or n:find('parkplatz') or n:find('raststätte') or n:find('rastanlage')
end

function M.make(typeKey, real, detail, lat, lon, townFn, used)
  if typeKey == 'viewpoint' then return real end
  if typeKey == 'rest' and isPublicRest(real) then return real end
  local pool = M.POOL[typeKey]
  if not pool then return real end
  local town = M.townOf(detail) or (townFn and townFn(lat, lon)) or M.FALLBACK_TOWN
  local start = hash(typeKey, lat, lon) % #pool
  for i = 0, #pool - 1 do
    local name = pool[(start + i) % #pool + 1]:gsub('%%s', function() return town end)
    if not used or not used[name] then
      if used then used[name] = true end
      return name
    end
  end
  for _, side in ipairs({ 'Nord', 'Süd', 'West', 'Ost', 'Mitte', 'II', 'III', 'IV' }) do
    local name = pool[start + 1]:gsub('%%s', function() return town end) .. ' ' .. side
    if not used[name] then used[name] = true; return name end
  end
  return pool[start + 1]:gsub('%%s', function() return town end)
end

return M
