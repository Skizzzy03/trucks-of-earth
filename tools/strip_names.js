// Takes the real company names out of the shipped place data: the game gives every place a made-up name (lua/.../names.lua),
// so only the kind, the position and the address stay. Public names (viewpoints, rest areas) stay.
// node tools/strip_names.js <mod folder>
const fs = require('fs'), path = require('path')
const dir = path.join(process.argv[2], 'fernfahrer', 'places')
let files = 0, cleared = 0, kept = 0
for (const f of fs.readdirSync(dir).filter(x => x.endsWith('.json'))) {
  const file = path.join(dir, f), d = JSON.parse(fs.readFileSync(file, 'utf8'))
  for (const p of d.places || []) {
    const publicName = p[0] === 'viewpoint' || (p[0] === 'rest' && /rastplatz|parkplatz|raststätte|rastanlage/i.test(p[1] || ''))
    if (publicName) kept++
    else if (p[1] !== '') { p[1] = ''; cleared++ }
  }
  fs.writeFileSync(file, JSON.stringify(d))
  files++
}
console.log(`${files} Dateien, ${cleared} Namen entfernt, ${kept} öffentliche behalten`)
