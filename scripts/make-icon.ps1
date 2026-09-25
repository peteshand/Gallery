Add-Type -AssemblyName System.Drawing

$iconDirectory = Join-Path $PSScriptRoot '..\src-tauri\icons'
New-Item -ItemType Directory -Force -Path $iconDirectory | Out-Null
$pngPath = Join-Path $iconDirectory 'icon.png'
$icoPath = Join-Path $iconDirectory 'icon.ico'

$bitmap = [System.Drawing.Bitmap]::new(256, 256)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::White)

$petals = @(
  @{ X = 100; Y = 36; Color = '#5484F3' },
  @{ X = 156; Y = 100; Color = '#E98254' },
  @{ X = 100; Y = 156; Color = '#63B886' },
  @{ X = 36; Y = 100; Color = '#B276DA' }
)
foreach ($petal in $petals) {
  $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($petal.Color))
  $graphics.FillEllipse($brush, $petal.X, $petal.Y, 84, 84)
  $brush.Dispose()
}
$graphics.FillEllipse([System.Drawing.Brushes]::White, 99, 99, 58, 58)
$graphics.Dispose()
$bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

$png = [System.IO.File]::ReadAllBytes($pngPath)
$stream = [System.IO.File]::Create($icoPath)
$writer = [System.IO.BinaryWriter]::new($stream)
$writer.Write([uint16]0)
$writer.Write([uint16]1)
$writer.Write([uint16]1)
$writer.Write([byte]0)
$writer.Write([byte]0)
$writer.Write([byte]0)
$writer.Write([byte]0)
$writer.Write([uint16]1)
$writer.Write([uint16]32)
$writer.Write([uint32]$png.Length)
$writer.Write([uint32]22)
$writer.Write($png)
$writer.Dispose()
