[CmdletBinding()]
param(
  [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) {
  $OutputDirectory = Join-Path $RepositoryRoot 'dist'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

foreach ($App in @('producer', 'worker')) {
  $Source = Join-Path $RepositoryRoot "functions/$App"
  $Destination = Join-Path $OutputDirectory "$App.zip"
  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Force
  }

  $Staging = Join-Path ([System.IO.Path]::GetTempPath()) ("vnetlab-{0}-{1}" -f $App, [guid]::NewGuid())
  New-Item -ItemType Directory -Path $Staging | Out-Null
  try {
    Get-ChildItem -LiteralPath $Source -Force |
      Where-Object { $_.Name -notin @('__pycache__', '.python_packages', 'local.settings.json') } |
      Copy-Item -Destination $Staging -Recurse -Force
    Compress-Archive -Path (Join-Path $Staging '*') -DestinationPath $Destination -CompressionLevel Optimal
  }
  finally {
    Remove-Item -LiteralPath $Staging -Recurse -Force
  }

  Write-Host "Created $Destination"
}
