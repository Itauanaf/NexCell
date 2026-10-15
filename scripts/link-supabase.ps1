$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$environmentPath = Join-Path $projectRoot ".env.local"
$nodeDirectory = Join-Path $projectRoot ".tools\node-v24.22.0-win-x64"
$npx = Join-Path $nodeDirectory "npx.cmd"

if (-not (Test-Path $environmentPath)) {
  throw "Execute primeiro scripts\configure-supabase.ps1"
}
if (-not (Test-Path $npx)) {
  throw "Node portátil não encontrado em $nodeDirectory"
}

$configuration = @{}
Get-Content -LiteralPath $environmentPath | ForEach-Object {
  $separator = $_.IndexOf('=')
  if ($separator -gt 0) {
    $configuration[$_.Substring(0, $separator)] = $_.Substring($separator + 1)
  }
}
$projectRef = $configuration["SUPABASE_PROJECT_REF"]
if ([string]::IsNullOrWhiteSpace($projectRef)) {
  throw "SUPABASE_PROJECT_REF não encontrado em .env.local"
}

$env:PATH = "$nodeDirectory;$env:PATH"
Push-Location $projectRoot
try {
  Write-Host "O navegador será aberto para autenticar sua conta Supabase." -ForegroundColor Cyan
  & $npx supabase@latest login
  if ($LASTEXITCODE -ne 0) { throw "Não foi possível autenticar na CLI do Supabase." }
  & $npx supabase@latest link --project-ref $projectRef
  if ($LASTEXITCODE -ne 0) { throw "Não foi possível vincular o projeto Supabase." }
  Write-Host "Projeto Supabase vinculado com sucesso." -ForegroundColor Green
}
finally {
  Pop-Location
}
