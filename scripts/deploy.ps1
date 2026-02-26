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
Write-Host "Backend VM-A Private IP : $($outputs.backendVmAIp.value)" -ForegroundColor White
Write-Host "Backend VM-B Private IP : $($outputs.backendVmBIp.value)" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. SSH into the client VM:  ssh $AdminUsername@$($outputs.clientPublicIp.value)"
Write-Host "  2. Test port 5022:          nc -zv $($outputs.lbStaticIp.value) 5022"
Write-Host "  3. Test port 1433:          nc -zv $($outputs.lbStaticIp.value) 1433"
Write-Host "  4. Expected: Connection succeeded (HAProxy -> real SQL MI)"
Write-Host ""
Write-Host "  For fallback testing (socat VMs + DNS failover):" -ForegroundColor Cyan
Write-Host "  1. SSH into vm-haproxy and edit /etc/haproxy/haproxy.cfg"
Write-Host "  2. Change backend FQDN to: sqlmi-test.fake-sqlmi.database.windows.net"
Write-Host "  3. sudo systemctl restart haproxy"
Write-Host "  4. From client: nc $($outputs.lbStaticIp.value) 5022  -> 'Connected to vm-sql-a'"
Write-Host "  5. Switch backend: .\scripts\switch-backend.ps1 -ResourceGroupName $ResourceGroupName -TargetIp 10.0.2.5"
Write-Host "  6. Wait ~15s, retry:  nc $($outputs.lbStaticIp.value) 5022  -> 'Connected to vm-sql-b'"
Write-Host ""
