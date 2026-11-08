-- Trucks of Earth: which German state (or the Netherlands) a place is in, offline: the nearest of these towns, a good
-- many per state, so the borders come out right to within a few kilometres – quite enough for a radio station. Places
-- abroad have towns too (key false): near the border they keep a German state from reaching over it.
-- M.at(lat, lon) -> key or nil; M.STATE[key] = { name, station, url } (every stream checked: Fernfahrer-Radio.exe --probe).

local M = {}

M.STATE = {
  BW = { 'Baden-Württemberg', 'SWR1 Baden-Württemberg', 'https://liveradio.swr.de/sw282p3/swr1bw/play.mp3' },
  BY = { 'Bayern', 'Bayern 1', 'https://dispatcher.rndfnk.com/br/br1/obb/mp3/mid' },
  BE = { 'Berlin', 'rbb 88.8', 'https://dispatcher.rndfnk.com/rbb/rbb888/live/mp3/mid' },
  BB = { 'Brandenburg', 'Antenne Brandenburg', 'https://dispatcher.rndfnk.com/rbb/antennebrandenburg/live/mp3/mid' },
  HB = { 'Bremen', 'Bremen Eins', 'https://icecast.radiobremen.de/rb/bremeneins/live/mp3/128/stream.mp3' },
  HH = { 'Hamburg', 'NDR 90,3', 'https://icecast.ndr.de/ndr/ndr903/hamburg/mp3/128/stream.mp3' },
  HE = { 'Hessen', 'hr3', 'https://dispatcher.rndfnk.com/hr/hr3/live/mp3/high' },
  MV = { 'Mecklenburg-Vorpommern', 'NDR 1 Radio MV', 'https://icecast.ndr.de/ndr/ndr1radiomv/schwerin/mp3/128/stream.mp3' },
  NI = { 'Niedersachsen', 'NDR 1 Niedersachsen', 'https://icecast.ndr.de/ndr/ndr1niedersachsen/hannover/mp3/128/stream.mp3' },
  NW = { 'Nordrhein-Westfalen', 'WDR 2', 'https://wdr-wdr2-rheinland.icecastssl.wdr.de/wdr/wdr2/rheinland/mp3/128/stream.mp3' },
  RP = { 'Rheinland-Pfalz', 'SWR1 Rheinland-Pfalz', 'https://liveradio.swr.de/sw282p3/swr1rp/play.mp3' },
  SL = { 'Saarland', 'SR 1', 'https://liveradio.sr.de/sr/sr1/mp3/128/stream.mp3' },
  SN = { 'Sachsen', 'Radio PSR', 'https://streams.radiopsr.de/psr-live/mp3-192/mediaplayer' },
  ST = { 'Sachsen-Anhalt', 'Radio SAW', 'https://stream.radiosaw.de/saw/mp3-128/' },
  SH = { 'Schleswig-Holstein', 'NDR 1 Welle Nord', 'https://icecast.ndr.de/ndr/ndr1wellenord/kiel/mp3/128/stream.mp3' },
  TH = { 'Thüringen', 'Antenne Thüringen', 'https://stream.antennethueringen.de/live/mp3-128/' },
  NL = { 'Niederlande', 'NPO Radio 2', 'https://icecast.omroep.nl/radio2-bb-mp3' },
}

-- { key, lat, lon, lat, lon, ... }
M.TOWNS = {
  { 'BW', 48.78,9.18, 49.01,8.40, 49.49,8.47, 47.99,7.85, 48.40,9.99, 49.14,9.22, 47.66,9.18, 47.98,8.82, 48.47,7.94, 47.78,9.61, 48.84,10.09, 49.62,9.66, 47.61,7.66, 48.89,8.70 },
  { 'BY', 48.14,11.58, 49.45,11.08, 48.37,10.90, 49.01,12.10, 49.79,9.95, 49.95,11.58, 48.57,13.43, 47.73,10.31, 50.31,11.92, 49.98,9.15, 48.54,12.15, 47.86,12.12, 50.26,10.96, 49.68,12.16, 49.30,10.57, 47.98,10.18, 47.72,12.88, 50.20,10.08, 48.83,12.96, 49.22,12.67, 47.49,11.10 },
  { 'BE', 52.52,13.40, 52.54,13.20, 52.44,13.58 },
  { 'BB', 52.40,13.06, 51.76,14.33, 52.34,14.55, 52.41,12.55, 52.83,13.82, 52.93,12.80, 53.32,13.86, 53.00,11.75, 51.63,13.71, 52.68,13.59, 52.30,13.63, 53.06,14.28, 52.09,13.17 },
  { 'HB', 53.08,8.80, 53.55,8.58 },
  { 'HH', 53.55,10.00, 53.46,9.98 },
  { 'HE', 50.11,8.68, 51.31,9.48, 50.08,8.24, 49.87,8.65, 50.55,9.68, 50.58,8.68, 50.81,8.77, 50.39,8.06, 50.87,9.71, 51.27,8.87, 49.65,8.99, 51.19,9.97 },
  { 'MV', 53.63,11.41, 54.09,12.14, 54.31,13.09, 53.56,13.26, 54.09,13.38, 53.89,11.46, 53.79,12.17, 53.52,12.68, 53.33,11.50, 54.42,13.43, 53.83,13.68 },
  { 'NI', 52.37,9.73, 52.27,10.52, 52.28,8.05, 53.14,8.21, 51.53,9.93, 53.25,10.41, 52.42,10.79, 53.37,7.21, 53.87,8.69, 52.62,10.08, 53.60,9.48, 52.52,7.32, 52.64,9.21, 52.96,10.56, 51.91,10.43, 52.10,9.36, 52.73,8.29, 53.53,8.11, 53.08,7.39, 52.92,9.23, 53.14,10.90, 52.43,7.07 },
  { 'NW', 50.94,6.96, 51.23,6.78, 51.51,7.47, 51.46,7.01, 51.96,7.63, 52.02,8.53, 50.78,6.08, 50.73,7.10, 50.88,8.02, 51.72,8.75, 51.40,8.06, 51.66,6.62, 52.29,8.92, 52.28,7.44, 51.66,6.96, 51.84,6.61, 51.33,6.56, 50.66,6.79, 51.03,7.56, 51.77,9.38, 51.39,8.57, 51.79,6.14, 51.08,6.46, 50.57,6.36 },
  { 'RP', 50.00,8.27, 50.36,7.59, 49.76,6.64, 49.48,8.44, 49.44,7.77, 49.84,7.87, 49.20,7.60, 49.20,8.12, 50.69,7.65, 49.97,6.52, 49.97,7.90, 50.15,7.17, 49.71,7.31, 49.63,8.36, 50.54,7.10, 50.44,7.83 },
  { 'SL', 49.24,6.99, 49.31,6.75, 49.35,7.18, 49.44,6.64, 49.47,7.17 },
  { 'SN', 51.05,13.74, 51.34,12.37, 50.83,12.92, 50.72,12.49, 51.15,14.99, 50.50,12.14, 51.18,14.43, 51.31,13.29, 51.56,13.00, 51.44,14.25, 50.91,13.34 },
  { 'ST', 52.13,11.63, 51.48,11.97, 51.84,12.24, 52.61,11.86, 51.90,11.05, 51.87,12.65, 52.85,11.15, 51.15,11.81, 51.47,11.30 },
  { 'SH', 54.32,10.13, 53.87,10.69, 54.79,9.44, 54.07,9.98, 54.48,9.05, 53.92,9.52, 54.20,9.10, 53.71,10.00, 54.50,11.22, 54.30,9.66, 53.70,10.77, 53.62,10.30 },
  { 'TH', 50.98,11.03, 50.93,11.59, 50.88,12.08, 50.97,10.32, 50.61,10.69, 51.50,10.79, 50.65,11.36, 50.99,12.44, 51.21,10.45, 50.36,11.17 },
  { 'NL', 52.37,4.90, 51.92,4.48, 52.09,5.12, 51.44,5.48, 53.22,6.57, 52.51,6.09, 52.22,6.89, 51.37,6.17, 50.85,5.69, 51.98,5.91, 51.84,5.86, 51.59,4.78 },
  -- abroad, without a station of its own: { false, ... }
  { false, 50.63,5.57, 50.63,6.04, 50.85,4.35, 51.22,4.40, 49.61,6.13, 48.58,7.75, 49.12,6.18, 49.19,6.90, 48.82,7.79, 47.75,7.34, 47.56,7.59, 47.38,8.54,
    47.42,9.37, 47.70,8.63, 47.27,11.39, 47.80,13.04, 48.31,14.29, 47.50,9.75, 47.49,10.72, 48.46,13.43, 47.58,12.17, 49.75,13.38, 50.08,12.37, 50.66,14.03,
    50.77,15.06, 50.23,12.87, 49.44,12.93, 48.97,14.47, 53.43,14.55, 52.35,14.60, 51.94,15.51, 51.15,15.05, 54.93,8.86, 55.04,9.42, 54.91,9.79 },
}

function M.at(lat, lon)
  local k = math.cos(math.rad(lat))
  local best, bd
  for _, g in ipairs(M.TOWNS) do
    for i = 2, #g, 2 do
      local dx, dy = (g[i + 1] - lon) * k, g[i] - lat
      local d = dx * dx + dy * dy
      if not bd or d < bd then best, bd = g[1], d end
    end
  end
  return best or nil
end

return M
