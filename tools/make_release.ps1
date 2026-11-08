# Builds what goes to GitHub, without publishing anything:
#   github/   the repository: README, notices, the mod's files, the radio app's source, the build tools
#   release/  the two downloads: trucks_of_earth.zip (the mod) and Fernfahrer-Radio.zip (the radio app)
# Usage: tools/make_release.ps1 <mod folder>
param([string]$Mod)
$root = Split-Path -Parent $PSScriptRoot
$gh = Join-Path $root 'github'; $rel = Join-Path $root 'release'
foreach ($d in $gh, $rel) { if (Test-Path $d) { Remove-Item $d -Recurse -Force }; New-Item -ItemType Directory $d | Out-Null }
Add-Type -AssemblyName System.IO.Compression.FileSystem

# the repository
Copy-Item (Join-Path $root 'github_src\*') $gh -Recurse
$mg = Join-Path $gh 'mod'; New-Item -ItemType Directory $mg | Out-Null
Get-ChildItem $Mod -Force | Where-Object { $_.Name -ne 'tools' } | ForEach-Object { Copy-Item $_.FullName $mg -Recurse }
Remove-Item (Join-Path $mg 'lua\ge\extensions\fernfahrer\photos.lua') -Force -ErrorAction SilentlyContinue   # (only for the project page's pictures)
Copy-Item (Join-Path $gh 'LICENSE'), (Join-Path $gh 'THIRD_PARTY.md') $mg   # (the notices travel with the download)
$rh = Join-Path $gh 'radio-helper'; New-Item -ItemType Directory $rh | Out-Null
Copy-Item (Join-Path $Mod 'tools\radio\FernfahrerRadio.cs'), (Join-Path $Mod 'tools\radio\LIESMICH.txt') $rh
$tg = Join-Path $gh 'tools'; New-Item -ItemType Directory $tg | Out-Null
Get-ChildItem (Join-Path $root 'tools') -File | Where-Object { $_.Name -match '^(build_|level_wavs|strip_names|dump_events|sim_|ereignisse\.template|make_release)' } | ForEach-Object { Copy-Item $_.FullName $tg }
Set-Content -Path (Join-Path $gh '.gitignore') -Encoding ascii -Value "release/`r`n*.old`r`n*.part`r`nyt-dlp.exe`r`n"

# the downloads
$tmp = Join-Path $root 'release_tmp'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory $tmp | Out-Null
Copy-Item (Join-Path $Mod 'tools\radio\Fernfahrer-Radio.exe'), (Join-Path $Mod 'tools\radio\FernfahrerRadio.cs'), (Join-Path $Mod 'tools\radio\LIESMICH.txt') $tmp
# (entries with forward slashes: .NET's CreateFromDirectory writes backslashes here, which is no valid zip path for the game)
function Zip-Folder($src, $zip) {
  $base = (Resolve-Path $src).Path.TrimEnd('\')
  $a = [IO.Compression.ZipFile]::Open($zip, 'Create')
  Get-ChildItem $src -Recurse -File -Force | ForEach-Object {
    $name = $_.FullName.Substring($base.Length + 1).Replace('\', '/')
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($a, $_.FullName, $name, 'Optimal')
  }
  $a.Dispose()
}
Zip-Folder $mg (Join-Path $rel 'trucks_of_earth.zip')
Zip-Folder $tmp (Join-Path $rel 'Fernfahrer-Radio.zip')
Remove-Item $tmp -Recurse -Force
Get-ChildItem $rel | ForEach-Object { '{0}: {1:N1} MB' -f $_.Name, ($_.Length / 1MB) }
$files = Get-ChildItem $gh -Recurse -File -Force
'github: {0} Dateien, {1:N1} MB, groesste {2:N1} MB' -f $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB), (($files | Measure-Object Length -Maximum).Maximum / 1MB)
