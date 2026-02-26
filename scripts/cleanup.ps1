# ============================================================================
# cleanup.ps1 — Delete the lab resource group
# ============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName
)

Write-Host ""
Write-Host "Deleting resource group '$ResourceGroupName'..." -ForegroundColor Yellow
Write-Host "This will remove ALL resources in the group." -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Type 'yes' to confirm"
if ($confirm -ne "yes") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

az group delete --name $ResourceGroupName --yes --no-wait
Write-Host "Deletion initiated (running in background)." -ForegroundColor Green
Write-Host ""
