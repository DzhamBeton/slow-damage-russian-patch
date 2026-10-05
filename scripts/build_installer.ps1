param([string]$ReleaseDirectory)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $ReleaseDirectory) { $ReleaseDirectory = Join-Path $projectRoot 'dist/SlowDamage-Rus-v0.1.0' }
$ReleaseDirectory = [IO.Path]::GetFullPath($ReleaseDirectory)
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The .NET Framework C# compiler was not found.' }
if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDirectory 'payload')) -or
    -not (Test-Path -LiteralPath (Join-Path $ReleaseDirectory 'manifest.json'))) {
    throw 'Extract SlowDamage-Rus-v0.1.0.zip into dist/SlowDamage-Rus-v0.1.0 first, or pass -ReleaseDirectory.'
}
$executable = Join-Path $ReleaseDirectory 'SlowDamage-Rus-Patcher.exe'
& $compiler /nologo /target:winexe /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /codepage:65001 "/out:$executable" (Join-Path $projectRoot 'installer/Program.cs')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'installer/install.ps1') -Destination (Join-Path $ReleaseDirectory 'install.ps1') -Force
$lines = Get-ChildItem -LiteralPath $ReleaseDirectory -Recurse -File |
    Where-Object { $_.Name -notin @('SHA256SUMS.txt','operation.log') } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($ReleaseDirectory.TrimEnd('\').Length + 1).Replace('\','/')
        (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $relative
    }
$lines | Set-Content -LiteralPath (Join-Path $ReleaseDirectory 'SHA256SUMS.txt') -Encoding UTF8
Write-Output "Built $executable"
