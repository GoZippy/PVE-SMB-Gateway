Write-Host "PVE SMB Gateway - Project Validation" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Check key files
$files = @(
    "README.md",
    "PVE/Storage/Custom/SMBGateway.pm", 
    "sbin/pve-smbgateway",
    "www/ext6/pvemanager6/smb-gateway.js",
    "Makefile",
    "LICENSE"
)

$passed = 0
$total = $files.Count

foreach ($file in $files) {
    if (Test-Path $file) {
        Write-Host "✅ $file" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "❌ $file" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Results: $passed/$total files found" -ForegroundColor Yellow

if ($passed -eq $total) {
    Write-Host "🎉 Project structure is valid!" -ForegroundColor Green
} else {
    Write-Host "⚠️  Some files are missing" -ForegroundColor Yellow
} 