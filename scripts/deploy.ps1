# ============================================================================
# deploy.ps1 — Deploy the SQL MI Link Static IP Lab
# ============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory = $true)]
    [string]$AdminUsername,

    [Parameter(Mandatory = $true)]
    [securestring]$AdminPassword
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " SQL MI Link Static IP Lab — Deployment"     -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Create resource group ---
Write-Host "[1/2] Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location --output none

# --- Deploy Bicep ---
Write-Host "[2/2] Deploying Bicep template..." -ForegroundColor Yellow
$result = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "$PSScriptRoot\..\infra\main.bicep" `
    --parameters adminUsername=$AdminUsername adminPassword=$AdminPassword `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "Deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Deployment Complete"                         -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

$outputs = $result.properties.outputs
Write-Host "Load Balancer Static IP : $($outputs.lbStaticIp.value)" -ForegroundColor White
Write-Host "Client VM Public IP     : $($outputs.clientPublicIp.value)" -ForegroundColor White
Write-Host "SQL MI FQDN             : $($outputs.sqlmiFqdn.value)" -ForegroundColor White
Write-Host "SQL MI Name             : $($outputs.sqlmiName.value)" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. RDP into win-client using its public IP"
Write-Host "  2. Add hosts file entry: $($outputs.lbStaticIp.value)  $($outputs.sqlmiFqdn.value)"
Write-Host "  3. Open SSMS and connect to SQL MI via the static IP"
Write-Host "  4. Test MI Link creation, failover, and failback through the proxy"
Write-Host ""
