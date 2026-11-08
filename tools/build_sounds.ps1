# The tuning noise of the radio. Usage: tools/build_sounds.ps1 <mod folder>
param([string]$Mod)

# the tuning noise: 1.1 s of band-limited hiss with a whistle sliding through it and a soft end
$rate = 22050; $n = [int]($rate * 1.1)
$r = New-Object System.Random 7
$pcm = New-Object 'byte[]' ($n * 2)
$lp = 0.0; $hp = 0.0; $phase = 0.0
for ($i = 0; $i -lt $n; $i++) {
  $t = $i / $rate
  $x = $r.NextDouble() * 2 - 1
  $lp += 0.45 * ($x - $lp); $hp += 0.02 * ($lp - $hp)
  $noise = ($lp - $hp) * (0.72 + 0.28 * [Math]::Sin($t * 67))
  $phase += 2 * [Math]::PI * (1500 + 1900 * [Math]::Sin($t * 3.4)) / $rate
  $env = [Math]::Min(1.0, $t / 0.03) * [Math]::Min(1.0, (1.1 - $t) / 0.22)
  $v = [Math]::Max(-1.0, [Math]::Min(1.0, ($noise * 0.8 + 0.06 * [Math]::Sin($phase)) * $env))
  $b = [BitConverter]::GetBytes([int16]($v * 26000))
  $pcm[$i * 2] = $b[0]; $pcm[$i * 2 + 1] = $b[1]
}
$out = Join-Path $Mod 'art\sound\fernfahrer\radio_tune.wav'
$fs = [IO.File]::Create($out); $w = New-Object IO.BinaryWriter $fs
$w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $pcm.Length)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
$w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
$w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$pcm.Length); $w.Write($pcm); $w.Close()
