param (
    [string]$AsciiDir,
    [int]$Fps = 24,
    [bool]$Loop = $true
)

if (-not $AsciiDir) {
    Write-Host "Usage: script.ps1 <ascii_txt_dir> [-Fps 24] [-Loop \$true|\$false]"
    exit 1
}

$Delay = 1 / $Fps

function Play-Once {
    Get-ChildItem "$AsciiDir" -Filter *.txt | Sort-Object Name | ForEach-Object {
        Clear-Host
        Get-Content $_.FullName
        Start-Sleep -Seconds $Delay
    }
}

if ($Loop) {
    while ($true) {
        Play-Once
    }
} else {
    Play-Once
}
