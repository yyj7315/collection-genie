Add-Type -AssemblyName System.Drawing

function New-Color([string]$hex, [int]$alpha = 255) {
  $base = [System.Drawing.ColorTranslator]::FromHtml($hex)
  return [System.Drawing.Color]::FromArgb($alpha, $base.R, $base.G, $base.B)
}

function New-RoundedPath([float]$x, [float]$y, [float]$width, [float]$height, [float]$radius) {
  $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $diameter = $radius * 2
  $path.AddArc($x, $y, $diameter, $diameter, 180, 90)
  $path.AddArc($x + $width - $diameter, $y, $diameter, $diameter, 270, 90)
  $path.AddArc($x + $width - $diameter, $y + $height - $diameter, $diameter, $diameter, 0, 90)
  $path.AddArc($x, $y + $height - $diameter, $diameter, $diameter, 90, 90)
  $path.CloseFigure()
  return $path
}

function Add-Star($graphics, [float]$centerX, [float]$centerY, [float]$radius, [System.Drawing.Brush]$brush) {
  $points = [System.Drawing.PointF[]]::new(10)
  for ($index = 0; $index -lt 10; $index++) {
    $angle = -90 + $index * 36
    $currentRadius = if ($index % 2 -eq 0) { $radius } else { $radius * 0.42 }
    $radians = $angle * [Math]::PI / 180
    $points[$index] = [System.Drawing.PointF]::new(
      $centerX + [Math]::Cos($radians) * $currentRadius,
      $centerY + [Math]::Sin($radians) * $currentRadius
    )
  }
  $graphics.FillPolygon($brush, $points)
}

function Render-AppIcon([int]$size, [string]$outputPath) {
  $bitmap = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

  $backgroundRect = [System.Drawing.Rectangle]::new(0, 0, 1024, 1024)
  $background = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    $backgroundRect,
    (New-Color '#063B36'),
    (New-Color '#45C99A'),
    48
  )
  $graphics.FillRectangle($background, $backgroundRect)

  foreach ($glow in @(
    @{ X = 512; Y = 420; W = 860; H = 760; A = 62 },
    @{ X = 220; Y = 770; W = 680; H = 380; A = 26 },
    @{ X = 835; Y = 235; W = 430; H = 430; A = 30 }
  )) {
    $brush = [System.Drawing.SolidBrush]::new((New-Color '#C7FFE9' $glow.A))
    $graphics.FillEllipse($brush, $glow.X - $glow.W / 2, $glow.Y - $glow.H / 2, $glow.W, $glow.H)
    $brush.Dispose()
  }

  $groundBrush = [System.Drawing.SolidBrush]::new((New-Color '#E9FFF7' 26))
  $graphics.FillEllipse($groundBrush, 190, 790, 644, 170)
  $groundBrush.Dispose()

  $shadowBrush = [System.Drawing.SolidBrush]::new((New-Color '#002F29' 82))
  $graphics.FillEllipse($shadowBrush, 304, 802, 416, 90)
  $shadowBrush.Dispose()

  $hoodPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $hoodPath.StartFigure()
  $hoodPath.AddBezier(512, 168, 365, 168, 278, 289, 278, 432)
  $hoodPath.AddBezier(278, 432, 278, 531, 328, 619, 412, 676)
  $hoodPath.AddLine(412, 676, 512, 752)
  $hoodPath.AddLine(512, 752, 612, 676)
  $hoodPath.AddBezier(612, 676, 696, 619, 746, 531, 746, 432)
  $hoodPath.AddBezier(746, 432, 746, 289, 659, 168, 512, 168)
  $hoodPath.CloseFigure()
  $hoodBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Rectangle]::new(278, 168, 468, 584),
    (New-Color '#F5FFFC'),
    (New-Color '#A7EED3'),
    55
  )
  $graphics.FillPath($hoodBrush, $hoodPath)

  $innerPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $innerPath.StartFigure()
  $innerPath.AddBezier(512, 214, 395, 214, 326, 313, 326, 430)
  $innerPath.AddBezier(326, 430, 326, 510, 367, 581, 434, 628)
  $innerPath.AddLine(434, 628, 512, 687)
  $innerPath.AddLine(512, 687, 590, 628)
  $innerPath.AddBezier(590, 628, 657, 581, 698, 510, 698, 430)
  $innerPath.AddBezier(698, 430, 698, 313, 629, 214, 512, 214)
  $innerPath.CloseFigure()
  $innerBrush = [System.Drawing.SolidBrush]::new((New-Color '#0B665B'))
  $graphics.FillPath($innerBrush, $innerPath)

  $earBrush = [System.Drawing.SolidBrush]::new((New-Color '#E8FFF8'))
  $leftEar = @(
    [System.Drawing.PointF]::new(302, 384),
    [System.Drawing.PointF]::new(252, 344),
    [System.Drawing.PointF]::new(246, 285),
    [System.Drawing.PointF]::new(281, 239),
    [System.Drawing.PointF]::new(321, 224),
    [System.Drawing.PointF]::new(350, 256)
  )
  $rightEar = @(
    [System.Drawing.PointF]::new(722, 384),
    [System.Drawing.PointF]::new(772, 344),
    [System.Drawing.PointF]::new(778, 285),
    [System.Drawing.PointF]::new(743, 239),
    [System.Drawing.PointF]::new(703, 224),
    [System.Drawing.PointF]::new(674, 256)
  )
  $graphics.FillPolygon($earBrush, $leftEar)
  $graphics.FillPolygon($earBrush, $rightEar)

  $earInnerBrush = [System.Drawing.SolidBrush]::new((New-Color '#FFBD72'))
  $graphics.FillEllipse($earInnerBrush, 280, 260, 58, 92)
  $graphics.FillEllipse($earInnerBrush, 686, 260, 58, 92)

  $hairBrush = [System.Drawing.SolidBrush]::new((New-Color '#123F3A'))
  $graphics.FillEllipse($hairBrush, 357, 265, 310, 270)
  $faceBrush = [System.Drawing.SolidBrush]::new((New-Color '#FFE6CE'))
  $graphics.FillEllipse($faceBrush, 357, 308, 310, 296)

  $hairFringe = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $hairFringe.StartFigure()
  $hairFringe.AddBezier(365, 410, 388, 309, 446, 278, 512, 278)
  $hairFringe.AddBezier(512, 278, 578, 278, 636, 309, 659, 410)
  $hairFringe.AddBezier(659, 410, 603, 367, 557, 349, 512, 349)
  $hairFringe.AddBezier(512, 349, 460, 349, 411, 367, 365, 410)
  $hairFringe.CloseFigure()
  $graphics.FillPath($hairBrush, $hairFringe)

  $eyeBrush = [System.Drawing.SolidBrush]::new((New-Color '#083F39'))
  $graphics.FillEllipse($eyeBrush, 414, 419, 70, 92)
  $graphics.FillEllipse($eyeBrush, 540, 419, 70, 92)
  $eyeLightBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
  $graphics.FillEllipse($eyeLightBrush, 426, 432, 24, 31)
  $graphics.FillEllipse($eyeLightBrush, 552, 432, 24, 31)
  $irisBrush = [System.Drawing.SolidBrush]::new((New-Color '#59E2BA'))
  $graphics.FillEllipse($irisBrush, 452, 475, 15, 15)
  $graphics.FillEllipse($irisBrush, 578, 475, 15, 15)

  $blushBrush = [System.Drawing.SolidBrush]::new((New-Color '#FF8E8E' 150))
  $graphics.FillEllipse($blushBrush, 362, 510, 72, 36)
  $graphics.FillEllipse($blushBrush, 590, 510, 72, 36)

  $mouthPen = [System.Drawing.Pen]::new((New-Color '#7D4336'), 11)
  $mouthPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $mouthPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $graphics.DrawArc($mouthPen, 482, 515, 62, 35, 15, 150)

  $bookmarkBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Rectangle]::new(439, 600, 146, 212),
    (New-Color '#FFE68A'),
    (New-Color '#FFB638'),
    90
  )
  $bookmark = @(
    [System.Drawing.PointF]::new(439, 632),
    [System.Drawing.PointF]::new(439, 812),
    [System.Drawing.PointF]::new(512, 750),
    [System.Drawing.PointF]::new(585, 812),
    [System.Drawing.PointF]::new(585, 632)
  )
  $graphics.FillPolygon($bookmarkBrush, $bookmark)
  $starBrush = [System.Drawing.SolidBrush]::new((New-Color '#6C4900'))
  Add-Star $graphics 512 682 42 $starBrush

  $armPen = [System.Drawing.Pen]::new((New-Color '#E8FFF8'), 42)
  $armPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $armPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $leftArm = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $leftArm.AddBezier(365, 683, 305, 716, 284, 770, 290, 824)
  $rightArm = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $rightArm.AddBezier(659, 683, 719, 716, 740, 770, 734, 824)
  $graphics.DrawPath($armPen, $leftArm)
  $graphics.DrawPath($armPen, $rightArm)

  $sparkleBrush = [System.Drawing.SolidBrush]::new((New-Color '#FFF3B0'))
  Add-Star $graphics 177 446 44 $sparkleBrush
  Add-Star $graphics 850 600 30 $sparkleBrush
  Add-Star $graphics 735 240 23 $sparkleBrush

  $resized = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $resizeGraphics = [System.Drawing.Graphics]::FromImage($resized)
  $resizeGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $resizeGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $resizeGraphics.DrawImage($bitmap, 0, 0, $size, $size)
  $resized.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)

  $resizeGraphics.Dispose()
  $resized.Dispose()
  $sparkleBrush.Dispose()
  $armPen.Dispose()
  $bookmarkBrush.Dispose()
  $mouthPen.Dispose()
  $blushBrush.Dispose()
  $irisBrush.Dispose()
  $eyeLightBrush.Dispose()
  $eyeBrush.Dispose()
  $faceBrush.Dispose()
  $hairBrush.Dispose()
  $earInnerBrush.Dispose()
  $earBrush.Dispose()
  $innerBrush.Dispose()
  $hoodBrush.Dispose()
  $hoodPath.Dispose()
  $innerPath.Dispose()
  $hairFringe.Dispose()
  $leftArm.Dispose()
  $rightArm.Dispose()
  $background.Dispose()
  $graphics.Dispose()
  $bitmap.Dispose()
}

$workspace = Split-Path -Parent $PSScriptRoot
Render-AppIcon 1024 (Join-Path $workspace 'AppScope\resources\base\media\collection_icon.png')
Render-AppIcon 1024 (Join-Path $workspace 'entry\src\main\resources\base\media\collection_icon.png')
Render-AppIcon 512 (Join-Path $workspace 'entry\src\main\resources\base\media\startIcon.png')
