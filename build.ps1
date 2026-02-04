# PersonaPlex RunPod Build Script (PowerShell)

param(
    [string]$Tag = "latest"
)

# Load environment variables from .env if it exists
if (Test-Path .env) {
    Get-Content .env | ForEach-Object {
        if ($_ -match '^([^#][^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
}

$DockerUsername = $env:DOCKER_USERNAME
$HfToken = $env:HF_TOKEN

if (-not $DockerUsername) {
    Write-Host "Error: DOCKER_USERNAME not set" -ForegroundColor Red
    Write-Host "Either set it in .env or run: `$env:DOCKER_USERNAME = 'yourusername'"
    exit 1
}

$ImageName = "${DockerUsername}/personaplex-runpod"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "PersonaPlex RunPod Build" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Image: ${ImageName}:${Tag}"
Write-Host ""

# Build options
$BuildArgs = @()
if ($HfToken) {
    Write-Host "HF_TOKEN found - model can be pre-downloaded" -ForegroundColor Yellow
    $preDownload = Read-Host "Pre-download model into image? (larger image, faster cold start) [y/N]"
    if ($preDownload -eq 'y' -or $preDownload -eq 'Y') {
        $BuildArgs += "--build-arg", "HF_TOKEN=${HfToken}"
    }
}

Write-Host ""
Write-Host "Building Docker image..." -ForegroundColor Green
docker build @BuildArgs -t "${ImageName}:${Tag}" .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Build complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Test locally (optional):"
Write-Host "   docker run --gpus all -p 8998:8998 -e HF_TOKEN=`$env:HF_TOKEN ${ImageName}:${Tag}"
Write-Host ""
Write-Host "2. Push to Docker Hub:"
Write-Host "   docker login"
Write-Host "   docker push ${ImageName}:${Tag}"
Write-Host ""
Write-Host "3. Create RunPod Endpoint at:"
Write-Host "   https://www.runpod.io/console/serverless"
Write-Host "   Container Image: ${ImageName}:${Tag}"
Write-Host ""
