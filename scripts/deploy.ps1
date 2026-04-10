# ============================================================================
# deploy.ps1 — SQL MI — Static IP Gateway
# ============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory = $true)]
    [string]$AdminUsername,

    [Parameter(Mandatory = $true)]
    [securestring]$AdminPassword,

    [Parameter(Mandatory = $false)]
    [ValidateSet('lab', 'existing')]
    [string]$DeployMode = 'lab',

    # --- existing mode only ---
    [Parameter(Mandatory = $false)]
    [string]$ExistingProxySubnetId = '',

    [Parameter(Mandatory = $false)]
    [string]$ExistingMiFqdn = '',

    [Parameter(Mandatory = $false)]
    [string]$LbFrontendIp = '',

    [Parameter(Mandatory = $false)]
    [bool]$DeployNatGateway = $true,

    [Parameter(Mandatory = $false)]
    [bool]$DeployClientVm = $true,

    [Parameter(Mandatory = $false)]
    [string]$VmSize = 'Standard_D2s_v5'
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " SQL MI — Static IP Gateway — Deployment"     -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Validate existing-mode params ---
if ($DeployMode -eq 'existing') {
    if (-not $ExistingProxySubnetId) { throw "-ExistingProxySubnetId is required when -DeployMode is 'existing'" }
    if (-not $ExistingMiFqdn)   { throw "-ExistingMiFqdn is required when -DeployMode is 'existing'" }
    if (-not $LbFrontendIp)     { throw "-LbFrontendIp is required when -DeployMode is 'existing'" }
}

Write-Host "Mode: $DeployMode" -ForegroundColor DarkCyan
Write-Host ""

# --- Create resource group ---
Write-Host "[1/2] Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location --output none

# --- Deploy Bicep ---
Write-Host "[2/2] Deploying Bicep template (mode: $DeployMode)..." -ForegroundColor Yellow

$paramList = @("adminUsername=$AdminUsername", "deployMode=$DeployMode", "deployNatGateway=$($DeployNatGateway.ToString().ToLower())", "deployClientVm=$($DeployClientVm.ToString().ToLower())", "vmSize=$VmSize")
if ($DeployMode -eq 'existing') {
    $paramList += "existingProxySubnetId=$ExistingProxySubnetId"
    $paramList += "existingMiFqdn=$ExistingMiFqdn"
    $paramList += "existingLbFrontendIp=$LbFrontendIp"
}

$result = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "$PSScriptRoot\..\infra\main.bicep" `
    --parameters @paramList adminPassword=$AdminPassword `
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
if ($DeployClientVm) {
    Write-Host "Client VM Public IP     : $($outputs.clientPublicIp.value)" -ForegroundColor White
}
Write-Host "SQL MI FQDN             : $($outputs.sqlmiFqdn.value)" -ForegroundColor White
if ($DeployMode -eq 'lab') {
    Write-Host "SQL MI Name             : $($outputs.sqlmiName.value)" -ForegroundColor White
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
if ($DeployMode -eq 'lab') {
    Write-Host "  1. RDP into win-client using its public IP"
    Write-Host "  2. Add hosts file entry: $($outputs.lbStaticIp.value)  $($outputs.sqlmiFqdn.value)"
    Write-Host "  3. Open SSMS and connect to SQL MI via the static IP"
    Write-Host "  4. Test MI Link creation, failover, and failback through the proxy"
} else {
    Write-Host "  1. Ensure your SQL Server can reach the LB IP on ports 5022, 1433, and 11000-11999"
    Write-Host "  2. Add a hosts file entry on your SQL Server: $($outputs.lbStaticIp.value)  $($outputs.sqlmiFqdn.value)"
    Write-Host "  3. Add $($outputs.lbStaticIp.value) to your VPN/firewall allow-list"
    Write-Host "  4. Test MI Link creation from SSMS using the static LB IP"
}
Write-Host ""
