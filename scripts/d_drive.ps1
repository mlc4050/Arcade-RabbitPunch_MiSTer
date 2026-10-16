# Run project tools with their scratch space on D:, retaining the shared JTAG guard.
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskTemp = Join-Path $taskRoot '.local\tmp'
New-Item -ItemType Directory -Force $taskTemp | Out-Null
$env:TEMP = $taskTemp
$env:TMP = $taskTemp
$env:TMPDIR = $taskTemp
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONPYCACHEPREFIX = Join-Path $taskTemp 'pycache'
$env:PYTHONUSERBASE = Join-Path $taskRoot '.local\python'
$env:PIP_CACHE_DIR = Join-Path $taskRoot '.local\pip-cache'
$env:MODELSIM = Join-Path $taskRoot '.local\modelsim.ini'
if (-not (Test-Path $env:MODELSIM)) {
    Copy-Item 'D:\quartus\modelsim_ase\modelsim.ini' $env:MODELSIM
}
Set-Location $taskRoot
& python -B @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
