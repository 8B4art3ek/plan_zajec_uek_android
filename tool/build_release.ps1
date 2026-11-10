$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build/releases'

Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    & flutter build apk --release --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'ARM64 APK build failed.' }
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination (Join-Path $outputDirectory 'uek-plan-arm64-v8a.apk')

    Get-Item -LiteralPath (Join-Path $outputDirectory 'uek-plan-arm64-v8a.apk') | Select-Object Name, Length
} finally {
    Pop-Location
}
