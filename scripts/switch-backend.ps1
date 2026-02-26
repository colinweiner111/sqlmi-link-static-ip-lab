# ============================================================================
# switch-backend.ps1 — Simulate SQL MI IP change by updating DNS A record
# ============================================================================
# This updates the private DNS A record to point to a different backend VM,
# simulating SQL MI changing its IP within the subnet.
# HAProxy re-resolves the FQDN within ~10 seconds (hold valid 10s).
# ============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$TargetIp = "10.0.2.5",

    [Parameter(Mandatory = $false)]
    [string]$DnsZoneName = "fake-sqlmi.database.windows.net",

    [Parameter(Mandatory = $false)]
    [string]$RecordName = "sqlmi-test"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Switching SQL MI backend to $TargetIp"      -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Update the A record
Write-Host "Updating DNS: $RecordName.$DnsZoneName -> $TargetIp ..." -ForegroundColor Yellow

az network private-dns record-set a update `
    --resource-group $ResourceGroupName `
    --zone-name $DnsZoneName `
    --name $RecordName `
    --set "aRecords[0].ipv4Address=$TargetIp" `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "DNS update failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "DNS updated successfully." -ForegroundColor Green
Write-Host "HAProxy will re-resolve within ~10 seconds." -ForegroundColor Yellow
Write-Host ""
Write-Host "Test from client VM:" -ForegroundColor Cyan
Write-Host "  nc 10.0.1.10 5022"
Write-Host ""

if ($TargetIp -eq "10.0.2.5") {
    Write-Host "Expected response: 'Connected to vm-sql-b'" -ForegroundColor White
} else {
    Write-Host "Expected response: 'Connected to vm-sql-a'" -ForegroundColor White
}
Write-Host ""
