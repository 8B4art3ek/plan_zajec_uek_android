param(
    [string]$Source = (Join-Path $PSScriptRoot '../assets/branding/app_icon_foreground.png')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$image = [Drawing.Image]::FromFile([IO.Path]::GetFullPath($Source))

function Export-Icon([string]$Path, [int]$Size, [bool]$Foreground) {
    $bitmap = [Drawing.Bitmap]::new($Size, $Size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $target = [Drawing.Rectangle]::new(0, 0, $Size, $Size)
        if ($Foreground) {
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.DrawImage($image, $target)
        } else {
            $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#17171C'))
            $crop = [Drawing.Rectangle]::new(
                $image.Width * 0.13, $image.Height * 0.13,
                $image.Width * 0.74, $image.Height * 0.74)
            $graphics.DrawImage($image, $target, $crop, [Drawing.GraphicsUnit]::Pixel)
        }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    $densities = @{ mdpi = 1; hdpi = 1.5; xhdpi = 2; xxhdpi = 3; xxxhdpi = 4 }
    foreach ($density in $densities.GetEnumerator()) {
        $folder = Join-Path $root "android/app/src/main/res/mipmap-$($density.Key)"
        Export-Icon (Join-Path $folder 'ic_launcher.png') (48 * $density.Value) $false
        Export-Icon (Join-Path $folder 'ic_launcher_foreground.png') (108 * $density.Value) $true
    }
    Export-Icon (Join-Path $root 'assets/branding/app_icon.png') 256 $false
} finally {
    $image.Dispose()
}
