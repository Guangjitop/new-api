param(
    [ValidateSet("compose", "docker")]
    [string]$Mode = "compose",
    [string]$EnvFile = "",
    [string]$ImageName = "new-api:local",
    [string]$ContainerName = "new-api",
    [int]$HostPort = 3000,
    [switch]$ReplaceExisting,
    [switch]$Help
)

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

function Show-Usage {
    @"
用法：
  powershell -ExecutionPolicy Bypass -File "./scripts/deploy.windows.ps1" [[-Mode] compose|docker] [选项]

选项：
  -EnvFile <path>         指定环境变量文件
  -ImageName <name>       docker 模式下的镜像名，默认 new-api:local
  -ContainerName <name>   docker 模式下的容器名，默认 new-api
  -HostPort <port>        映射到宿主机的端口，默认 3000
  -ReplaceExisting        docker 模式下若同名容器存在，先删除再重建
  -Help                   显示帮助

示例：
  powershell -ExecutionPolicy Bypass -File "./scripts/deploy.windows.ps1"
  powershell -ExecutionPolicy Bypass -File "./scripts/deploy.windows.ps1" -Mode compose -EnvFile ".env.prod"
  powershell -ExecutionPolicy Bypass -File "./scripts/deploy.windows.ps1" -Mode docker -ContainerName "new-api-prod" -HostPort 3001
  powershell -ExecutionPolicy Bypass -File "./scripts/deploy.windows.ps1" -Mode docker -EnvFile ".env.prod" -ContainerName "new-api-prod"
"@
}

if ($Help) {
    Show-Usage
    exit 0
}

$script:EnvFileWasExplicitlyProvided = $PSBoundParameters.ContainsKey("EnvFile")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Wait-ComposeServiceReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HealthUrl,
        [int]$TimeoutSeconds = 90
    )
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $resp = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 3
            if ($resp.StatusCode -eq 200 -and $resp.Content -match '"success"\s*:\s*true') {
                return $true
            }
        }
        catch {
            Start-Sleep -Milliseconds 800
        }
    }
    return $false
}

function Resolve-ExistingEnvFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$RequestedPath
    )

    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        return $null
    }

    $repoCandidate = Join-Path $RepoRoot $RequestedPath
    if (Test-Path $repoCandidate) {
        return (Resolve-Path $repoCandidate).Path
    }

    if (Test-Path $RequestedPath) {
        return (Resolve-Path $RequestedPath).Path
    }

    return $null
}

function Resolve-EnvFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$DeploymentMode,
        [string]$RequestedPath,
        [Parameter(Mandatory = $true)]
        [bool]$SpecifiedByUser
    )

    if ($SpecifiedByUser) {
        $explicitFile = Resolve-ExistingEnvFilePath -RepoRoot $RepoRoot -RequestedPath $RequestedPath
        if (-not $explicitFile) {
            throw "未找到环境变量文件：$RequestedPath"
        }
        return $explicitFile
    }

    if ($DeploymentMode -eq "compose") {
        $composeEnv = Resolve-ExistingEnvFilePath -RepoRoot $RepoRoot -RequestedPath ".env.prod"
        if ($composeEnv) {
            return $composeEnv
        }
        return (Resolve-ExistingEnvFilePath -RepoRoot $RepoRoot -RequestedPath ".env")
    }

    return (Resolve-ExistingEnvFilePath -RepoRoot $RepoRoot -RequestedPath ".env")
}

function Test-ContainerExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $existing = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $Name }
    return [bool]$existing
}

function Invoke-ComposeDeploy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [string]$EnvFilePath
    )

    $composeArgs = @("compose")
    if ($EnvFilePath) {
        $composeArgs += @("--env-file", $EnvFilePath)
    }
    else {
        Write-Host "==> 未找到环境变量文件，将使用 docker-compose.yml 内默认值" -ForegroundColor Yellow
    }
    $composeArgs += @("-f", "docker-compose.yml")

    Write-Host "==> 检查 Docker Compose 插件..." -ForegroundColor Cyan
    docker compose version | Out-Null

    Write-Host "==> 开始部署（docker compose up -d --build）..." -ForegroundColor Cyan
    & docker @composeArgs up -d --build

    Write-Host "==> 服务状态：" -ForegroundColor Cyan
    & docker @composeArgs ps
}

function Invoke-DockerDeploy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [string]$EnvFilePath,
        [Parameter(Mandatory = $true)]
        [string]$ResolvedImageName,
        [Parameter(Mandatory = $true)]
        [string]$ResolvedContainerName,
        [Parameter(Mandatory = $true)]
        [int]$ResolvedHostPort,
        [Parameter(Mandatory = $true)]
        [bool]$ShouldReplaceExisting
    )

    $dataDir = Join-Path $RepoRoot "data"
    $logsDir = Join-Path $RepoRoot "logs"
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir | Out-Null
    }
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir | Out-Null
    }

    Write-Host "==> 构建镜像：$ResolvedImageName" -ForegroundColor Cyan
    docker build -t $ResolvedImageName $RepoRoot

    if (Test-ContainerExists -Name $ResolvedContainerName) {
        if ($ShouldReplaceExisting) {
            Write-Host "==> 删除已存在容器：$ResolvedContainerName" -ForegroundColor Yellow
            docker rm -f $ResolvedContainerName | Out-Null
        }
        else {
            throw "检测到已存在同名容器：$ResolvedContainerName。请显式添加 -ReplaceExisting，或者改用 -ContainerName 指定新名称。"
        }
    }

    $runArgs = @()
    $runArgs += "run"
    $runArgs += "--name"
    $runArgs += $ResolvedContainerName
    $runArgs += "-d"
    $runArgs += "--restart"
    $runArgs += "always"
    $runArgs += "-p"
    $runArgs += ("{0}:3000" -f $ResolvedHostPort)
    $runArgs += "-v"
    $runArgs += ("{0}:/data" -f $dataDir)
    $runArgs += "-v"
    $runArgs += ("{0}:/app/logs" -f $logsDir)
    $runArgs += "-e"
    $runArgs += "TZ=Asia/Shanghai"

    if (-not $script:EnvFileWasExplicitlyProvided) {
        $runArgs += "-e"
        $runArgs += "SQL_DSN="
        $runArgs += "-e"
        $runArgs += "REDIS_CONN_STRING="
        $runArgs += "-e"
        $runArgs += "SQLITE_PATH=/data/new-api.db?_busy_timeout=30000"
    }

    if ($EnvFilePath) {
        $runArgs += @("--env-file", $EnvFilePath)
    }
    else {
        Write-Host "==> 未找到环境变量文件，将使用镜像内默认值" -ForegroundColor Yellow
    }

    $runArgs += @($ResolvedImageName, "--log-dir", "/app/logs")

    Write-Host "==> 开始部署（docker run）..." -ForegroundColor Cyan
    & docker @runArgs

    Write-Host "==> 当前容器状态：" -ForegroundColor Cyan
    docker ps --filter "name=^$ResolvedContainerName$"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path

if (-not (Test-CommandExists "docker")) {
    throw "未检测到 docker，请先安装 Docker Desktop。"
}

$resolvedEnvFile = Resolve-EnvFilePath -RepoRoot $repoRoot -DeploymentMode $Mode -RequestedPath $EnvFile -SpecifiedByUser $script:EnvFileWasExplicitlyProvided
$healthUrl = "http://localhost:$HostPort/api/status"

Push-Location $repoRoot
try {
    if ($Mode -eq "compose") {
        Invoke-ComposeDeploy -RepoRoot $repoRoot -EnvFilePath $resolvedEnvFile
    }
    else {
        Invoke-DockerDeploy `
            -RepoRoot $repoRoot `
            -EnvFilePath $resolvedEnvFile `
            -ResolvedImageName $ImageName `
            -ResolvedContainerName $ContainerName `
            -ResolvedHostPort $HostPort `
            -ShouldReplaceExisting $ReplaceExisting.IsPresent
    }

    if (Wait-ComposeServiceReady -HealthUrl $healthUrl -TimeoutSeconds 120) {
        Write-Host "部署成功，服务可用: http://localhost:$HostPort" -ForegroundColor Green
    }
    elseif ($Mode -eq "compose") {
        Write-Warning "健康检查超时，建议执行：docker compose logs -f new-api"
    }
    else {
        Write-Warning "健康检查超时，建议执行：docker logs -f $ContainerName"
    }
}
finally {
    Pop-Location
}
