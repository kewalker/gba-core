$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content "$root/docs/candidate-manifest.json" -Raw | ConvertFrom-Json
foreach ($row in $manifest.files) {
    $file = Join-Path $root $row.path
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing $($row.path)" }
    if ((Get-FileHash -LiteralPath $file).Hash -ne $row.sha256) { throw "Hash mismatch: $($row.path)" }
}
$menu = Get-Content "$root/pocket/Cores/BitBird.GBA/interact.json" -Raw | ConvertFrom-Json
$toggle = @($menu.interact.variables | Where-Object id -eq 260)
if ($toggle.Count -ne 1 -or $toggle[0].persist -ne $true) { throw 'Fast-forward persistence missing' }
$qsf = "$root/src/fpga/ap_core.qsf"
$refs = 0
foreach ($line in Get-Content $qsf) {
    if ($line -match '^set_global_assignment -name (?:SYSTEMVERILOG_FILE|VERILOG_FILE|SDC_FILE|QIP_FILE|MIF_FILE|HEX_FILE)\s+(.+?)\s*$') {
        $ref = $Matches[1].Trim('"')
        if (-not (Test-Path -LiteralPath (Join-Path (Split-Path $qsf) $ref))) { throw "Missing project dependency: $ref" }
        $refs++
    }
}
Write-Output "PASS: $($manifest.files.Count) source/package file hashes, $refs project references, fast-forward persistence."
$core = Get-Content "$root/pocket/Cores/BitBird.GBA/core.json" -Raw | ConvertFrom-Json
if ($core.core.metadata.version -ne $manifest.release_version.version) { throw 'Release version mismatch' }
