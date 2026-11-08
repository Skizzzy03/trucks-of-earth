# The navi's phrases, spoken by a free voice: Piper (MIT, github.com/rhasspy/piper) with de_DE-thorsten-high
# (recordings CC0, github.com/thorstenMueller/Thorsten-Voice). Afterwards run tools/level_wavs.js on the folder.
# Usage: tools/build_voice.ps1 -Piper <piper.exe> -Model <de_DE-thorsten-high.onnx> -Mod <mod folder>
param([string]$Piper, [string]$Model, [string]$Mod)
$nav = Join-Path $Mod 'art\sound\fernfahrer\nav'
$acts = @{ HL = 'halb links halten'; HR = 'halb rechts halten'; L = 'links abbiegen'; R = 'rechts abbiegen'; U = 'bitte wenden'; K = 'in den Kreisverkehr' }
$lines = New-Object System.Collections.ArrayList
function add($name, $text) {
  $file = (Join-Path $nav "$name.wav").Replace('\', '\\')
  [void]$lines.Add('{"text":"' + $text + '","output_file":"' + $file + '"}')
}
foreach ($k in $acts.Keys) {
  foreach ($m in 50, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600) { add "d${m}_$k" "In $m Metern $($acts[$k])." }
  add "now_$k" "Jetzt $($acts[$k])."
}
add 'end' 'Sie haben Ihr Ziel erreicht.'
add 'on' 'Navi-Ansagen an.'
$list = Join-Path $env:TEMP 'ff_voice_lines.jsonl'
[IO.File]::WriteAllLines($list, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
cmd /c "`"$Piper`" --model `"$Model`" --json-input --quiet < `"$list`""
Remove-Item $list
"$($lines.Count) Ansagen"
