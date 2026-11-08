-- Trucks of Earth: the cities long-haul jobs go to (Germany and just across its borders): { name, lat, lon }.
-- The receiving depot is looked up near the city when such a job is taken. Add-ons can extend M.LIST.

local M = {}

M.LIST = {
  -- Germany
  { 'Berlin', 52.520, 13.405 }, { 'Hamburg', 53.551, 9.994 }, { 'München', 48.137, 11.575 },
  { 'Köln', 50.938, 6.960 }, { 'Frankfurt am Main', 50.110, 8.682 }, { 'Stuttgart', 48.776, 9.183 },
  { 'Düsseldorf', 51.227, 6.774 }, { 'Dortmund', 51.514, 7.468 }, { 'Essen', 51.456, 7.012 },
  { 'Leipzig', 51.340, 12.375 }, { 'Bremen', 53.079, 8.802 }, { 'Dresden', 51.050, 13.738 },
  { 'Hannover', 52.376, 9.732 }, { 'Nürnberg', 49.452, 11.077 }, { 'Duisburg', 51.434, 6.762 },
  { 'Bielefeld', 52.030, 8.532 }, { 'Münster', 51.960, 7.626 }, { 'Kassel', 51.312, 9.479 },
  { 'Erfurt', 50.978, 11.029 }, { 'Magdeburg', 52.120, 11.628 }, { 'Rostock', 54.092, 12.099 },
  { 'Kiel', 54.323, 10.123 }, { 'Osnabrück', 52.279, 8.047 }, { 'Aachen', 50.776, 6.084 },
  { 'Mannheim', 49.487, 8.466 }, { 'Karlsruhe', 49.007, 8.404 }, { 'Freiburg', 47.999, 7.842 },
  { 'Regensburg', 49.013, 12.102 }, { 'Würzburg', 49.791, 9.953 }, { 'Saarbrücken', 49.240, 6.997 },
  { 'Koblenz', 50.356, 7.594 }, { 'Braunschweig', 52.269, 10.521 }, { 'Oldenburg', 53.144, 8.214 },
  { 'Göttingen', 51.541, 9.916 }, { 'Ulm', 48.401, 9.987 }, { 'Augsburg', 48.371, 10.898 },
  { 'Chemnitz', 50.827, 12.921 }, { 'Lübeck', 53.866, 10.686 }, { 'Siegen', 50.875, 8.024 },
  -- neighbours
  { 'Amsterdam', 52.370, 4.895 }, { 'Rotterdam', 51.924, 4.478 }, { 'Venlo', 51.370, 6.172 },
  { 'Enschede', 52.221, 6.894 }, { 'Eindhoven', 51.441, 5.470 }, { 'Antwerpen', 51.219, 4.402 },
  { 'Brüssel', 50.850, 4.352 }, { 'Lüttich', 50.633, 5.567 }, { 'Luxemburg', 49.611, 6.130 },
  { 'Straßburg', 48.573, 7.752 }, { 'Basel', 47.560, 7.589 }, { 'Zürich', 47.377, 8.540 },
  { 'Salzburg', 47.809, 13.055 }, { 'Linz', 48.306, 14.286 }, { 'Innsbruck', 47.269, 11.404 },
  { 'Prag', 50.075, 14.437 }, { 'Pilsen', 49.738, 13.373 }, { 'Stettin', 53.428, 14.553 },
  { 'Posen', 52.406, 16.925 }, { 'Kopenhagen', 55.676, 12.568 }, { 'Aarhus', 56.163, 10.204 },
}

return M
