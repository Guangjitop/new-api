Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Wait-HttpReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [int]$TimeoutSeconds = 30
    )
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) {
                return $true
            }
        }
        catch {
            Start-Sleep -Milliseconds 700
        }
    }
    return $false
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$webDir = Join-Path $repoRoot "web"
$backendLog = Join-Path $repoRoot "logs/dev-backend.log"

if (-not (Test-CommandExists "go")) {
    throw "未检测到 go，请先安装 Go（建议 >= 1.25）。"
}
if (-not (Test-CommandExists "node")) {
    throw "未检测到 node，请先安装 Node.js（建议 >= 18）。"
}
if (-not (Test-CommandExists "npm")) {
    throw "未检测到 npm，请先安装 npm。"
}

if (-not (Test-Path (Join-Path $repoRoot "logs"))) {
    New-Item -ItemType Directory -Path (Join-Path $repoRoot "logs") | Out-Null
}

Write-Host "==> 安装前端依赖（web）..." -ForegroundColor Cyan
Push-Location $webDir
npm install
Pop-Location

Write-Host "==> 启动后端（go run main.go）..." -ForegroundColor Cyan
$backendProc = Start-Process `
    -FilePath "go" `
    -ArgumentList @("run", "main.go") `
    -WorkingDirectory $repoRoot `
    -NoNewWindow `
    -RedirectStandardOutput $backendLog `
    -RedirectStandardError $backendLog `
    -PassThru

Write-Host "后端 PID: $($backendProc.Id)" -ForegroundColor Yellow
if (Wait-HttpReady -Url "http://localhost:3000/api/status" -TimeoutSeconds 40) {
    Write-Host "后端就绪: http://localhost:3000" -ForegroundColor Green
}
else {
    Write-Warning "后端 40 秒内未就绪，可查看日志: $backendLog"
}

Write-Host "==> 启动前端（npm run dev）..." -ForegroundColor Cyan
Write-Host "按 Ctrl + C 可停止前端，并自动停止后端。" -ForegroundColor Yellow

try {
    Push-Location $webDir
    npm run dev
}
finally {
    Pop-Location
    if ($backendProc -and -not $backendProc.HasExited) {
        Write-Host "==> 正在停止后端进程..." -ForegroundColor Cyan
        Stop-Process -Id $backendProc.Id -Force -ErrorAction SilentlyContinue
    }
}
