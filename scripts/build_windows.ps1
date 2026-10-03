param(
    [string]$GodotPath = 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$packageDir = Join-Path $projectRoot 'build\windows'
$archivePath = Join-Path $projectRoot 'build\扫雷挖矿_外部试玩_v0.1.zip'
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

& $GodotPath --path $projectRoot --headless --import
if ($LASTEXITCODE -ne 0) { throw 'Godot 导入失败' }
& $GodotPath --path $projectRoot --headless --export-release 'Windows Desktop'
if ($LASTEXITCODE -ne 0) { throw 'Windows 导出失败' }

Copy-Item -LiteralPath (Join-Path $projectRoot 'distribution\试玩说明.txt') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $projectRoot 'distribution\第三方许可.txt') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\fonts\OFL.txt') -Destination (Join-Path $packageDir '字体许可.txt')
$fontLicenseDir = Join-Path $packageDir '字体来源许可'
if (Test-Path -LiteralPath $fontLicenseDir) {
    $resolvedLicenseDir = [System.IO.Path]::GetFullPath($fontLicenseDir)
    if ((Split-Path -Parent $resolvedLicenseDir) -ne [System.IO.Path]::GetFullPath($packageDir)) {
        throw '字体许可目录不在当前构建目录中'
    }
    Remove-Item -LiteralPath $resolvedLicenseDir -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\fonts\LICENSES') -Destination $fontLicenseDir -Recurse -Force
$packageFiles = @(
    (Join-Path $packageDir '扫雷挖矿.exe'),
    (Join-Path $packageDir '试玩说明.txt'),
    (Join-Path $packageDir '第三方许可.txt'),
    (Join-Path $packageDir '字体许可.txt'),
    (Join-Path $packageDir '字体来源许可')
)
Compress-Archive -LiteralPath $packageFiles -DestinationPath $archivePath -Force
Write-Output "试玩包：$archivePath"
