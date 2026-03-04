$ScriptDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$sourcePath = Join-Path $ScriptDir "QuizDatLogo.jpg"
$destPath = Join-Path $ScriptDir "windows\runner\resources\app_icon.ico"

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $sourcePath)) {
    Write-Warning "Source logo not found at $sourcePath. Using default icon."
    exit 0
}

try {
    $bitmap = [System.Drawing.Bitmap]::FromFile($sourcePath)
    
    # Standard sizes for high compatibility
    $size = 48
    $resized = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($resized)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($bitmap, 0, 0, $size, $size)
    
    $hIcon = $resized.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    
    $fileStream = New-Object System.IO.FileStream($destPath, [System.IO.FileMode]::Create)
    $icon.Save($fileStream)
    $fileStream.Close()
    
    $icon.Dispose()
    $graphics.Dispose()
    $resized.Dispose()
    $bitmap.Dispose()
    
    Write-Host "Icon converted successfully to $destPath"
}
catch {
    Write-Warning "Failed to convert icon: $_. Using default icon."
    exit 0 # Exit 0 to not break the main build process
}
