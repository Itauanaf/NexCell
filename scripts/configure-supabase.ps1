$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$projectRoot = Split-Path -Parent $PSScriptRoot
$environmentPath = Join-Path $projectRoot ".env.local"

$supabaseUrl = (Read-Host "Cole a Project URL do Supabase").Trim().Trim('"').Trim("'")
$publishableKey = (Read-Host "Cole a Publishable key (ou anon public)").Trim().Trim('"').Trim("'")
$projectRef = (Read-Host "Cole o Project Ref").Trim().Trim('"').Trim("'").ToLowerInvariant()

$parsedUrl = $null
if (-not [Uri]::TryCreate($supabaseUrl, [UriKind]::Absolute, [ref]$parsedUrl)) {
  throw "Project URL invalida. Copie a URL completa exibida em Data API."
}
$hostName = $parsedUrl.Host.ToLowerInvariant()
$hostMatch = [regex]::Match($hostName, '^([a-z0-9-]+)\.supabase\.co$')
if ($parsedUrl.Scheme -ne "https" -or -not $hostMatch.Success) {
  throw "Project URL invalida. O dominio deve terminar em .supabase.co"
}
if ([string]::IsNullOrWhiteSpace($publishableKey)) {
  throw "A Publishable key e obrigatoria."
}
if ($projectRef -notmatch '^[a-z0-9-]+$') {
  throw "Project Ref invalido."
}
$urlProjectRef = $hostMatch.Groups[1].Value
if ($urlProjectRef -ne $projectRef) {
  throw "A Project URL e o Project Ref nao correspondem. URL: $urlProjectRef"
}
$normalizedUrl = "https://$hostName"

$content = @(
  "SUPABASE_URL=$normalizedUrl"
  "SUPABASE_PUBLISHABLE_KEY=$publishableKey"
  "SUPABASE_PROJECT_REF=$projectRef"
) -join [Environment]::NewLine

[System.IO.File]::WriteAllText($environmentPath, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "Configuracao salva em .env.local (ignorado pelo Git)." -ForegroundColor Green
Write-Host "Nao compartilhe esse arquivo e nao o adicione ao repositorio." -ForegroundColor Yellow
