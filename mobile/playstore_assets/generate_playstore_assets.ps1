Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $ScriptDir "..\..")
$OutDir = $ScriptDir
$IconPath = Join-Path $Root "mobile\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png"

function ColorFromHex([string]$hex) {
    $clean = $hex.TrimStart("#")
    return [System.Drawing.Color]::FromArgb(
        [Convert]::ToInt32($clean.Substring(0, 2), 16),
        [Convert]::ToInt32($clean.Substring(2, 2), 16),
        [Convert]::ToInt32($clean.Substring(4, 2), 16)
    )
}

function Font([float]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
    return New-Object System.Drawing.Font("Segoe UI", $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function New-Canvas([int]$width, [int]$height) {
    $bitmap = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    return @{ Bitmap = $bitmap; Graphics = $graphics }
}

function RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function FillRoundRect($g, [float]$x, [float]$y, [float]$w, [float]$h, [float]$r, [System.Drawing.Color]$color) {
    if ($r -le 0) {
        $brush = New-Object System.Drawing.SolidBrush($color)
        $g.FillRectangle($brush, $x, $y, $w, $h)
        $brush.Dispose()
        return
    }
    $path = RoundedPath $x $y $w $h $r
    $brush = New-Object System.Drawing.SolidBrush($color)
    $g.FillPath($brush, $path)
    $brush.Dispose()
    $path.Dispose()
}

function StrokeRoundRect($g, [float]$x, [float]$y, [float]$w, [float]$h, [float]$r, [System.Drawing.Color]$color, [float]$width = 2) {
    if ($r -le 0) {
        $pen = New-Object System.Drawing.Pen($color, $width)
        $g.DrawRectangle($pen, $x, $y, $w, $h)
        $pen.Dispose()
        return
    }
    $path = RoundedPath $x $y $w $h $r
    $pen = New-Object System.Drawing.Pen($color, $width)
    $g.DrawPath($pen, $path)
    $pen.Dispose()
    $path.Dispose()
}

function DrawText($g, [string]$text, [float]$x, [float]$y, [float]$w, [float]$h, $font, [System.Drawing.Color]$color, [string]$align = "Near") {
    $brush = New-Object System.Drawing.SolidBrush($color)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::$align
    $format.LineAlignment = [System.Drawing.StringAlignment]::Near
    $format.Trimming = [System.Drawing.StringTrimming]::EllipsisWord
    $rect = New-Object System.Drawing.RectangleF($x, $y, $w, $h)
    $g.DrawString($text, $font, $brush, $rect, $format)
    $format.Dispose()
    $brush.Dispose()
}

function DrawPill($g, [string]$text, [float]$x, [float]$y, [float]$w, [System.Drawing.Color]$bg, [System.Drawing.Color]$fg) {
    FillRoundRect $g $x $y $w 42 21 $bg
    DrawText $g $text ($x + 20) ($y + 9) ($w - 40) 28 (Font 17 ([System.Drawing.FontStyle]::Bold)) $fg
}

function DrawMap($g, [float]$x, [float]$y, [float]$w, [float]$h, [bool]$dark = $false) {
    $bg = if ($dark) { ColorFromHex "#0F766E" } else { ColorFromHex "#E6F4F1" }
    $road = if ($dark) { [System.Drawing.Color]::FromArgb(80, 255, 255, 255) } else { ColorFromHex "#B9DDD6" }
    $minor = if ($dark) { [System.Drawing.Color]::FromArgb(42, 255, 255, 255) } else { ColorFromHex "#D5EAE6" }
    FillRoundRect $g $x $y $w $h 22 $bg
    $penMinor = New-Object System.Drawing.Pen($minor, 3)
    for ($i = 0; $i -lt 7; $i++) {
        $yy = $y + 35 + ($i * ($h / 7))
        $g.DrawBezier($penMinor, $x - 20, $yy, $x + ($w * .30), $yy - 45, $x + ($w * .68), $yy + 52, $x + $w + 20, $yy)
    }
    for ($i = 0; $i -lt 6; $i++) {
        $xx = $x + 30 + ($i * ($w / 6))
        $g.DrawBezier($penMinor, $xx, $y - 20, $xx + 42, $y + ($h * .32), $xx - 48, $y + ($h * .66), $xx + 12, $y + $h + 20)
    }
    $penMinor.Dispose()

    $penRoad = New-Object System.Drawing.Pen($road, 8)
    $g.DrawBezier($penRoad, $x + 40, $y + $h - 70, $x + ($w * .30), $y + ($h * .52), $x + ($w * .55), $y + ($h * .72), $x + $w - 50, $y + 62)
    $penRoad.Dispose()

    $routePen = New-Object System.Drawing.Pen((ColorFromHex "#FFA726"), 10)
    $routePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $routePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawBezier($routePen, $x + 80, $y + $h - 115, $x + ($w * .38), $y + ($h * .36), $x + ($w * .56), $y + ($h * .68), $x + $w - 85, $y + 90)
    $routePen.Dispose()

    FillRoundRect $g ($x + 64) ($y + $h - 136) 36 36 18 (ColorFromHex "#008080")
    FillRoundRect $g ($x + $w - 103) ($y + 72) 36 36 18 (ColorFromHex "#DC2626")
}

function DrawSmallIcon($g, [string]$kind, [float]$x, [float]$y, [System.Drawing.Color]$color) {
    $pen = New-Object System.Drawing.Pen($color, 7)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $brush = New-Object System.Drawing.SolidBrush($color)
    if ($kind -eq "search") {
        $g.DrawEllipse($pen, $x, $y, 28, 28)
        $g.DrawLine($pen, $x + 24, $y + 24, $x + 42, $y + 42)
    } elseif ($kind -eq "seat") {
        FillRoundRect $g $x ($y + 8) 42 36 9 $color
        FillRoundRect $g ($x + 6) $y 30 22 8 ([System.Drawing.Color]::FromArgb(235, $color))
    } elseif ($kind -eq "track") {
        $g.DrawEllipse($pen, $x + 7, $y + 2, 30, 30)
        $points = @(
            (New-Object System.Drawing.PointF(($x + 22), ($y + 48))),
            (New-Object System.Drawing.PointF(($x + 5), ($y + 26))),
            (New-Object System.Drawing.PointF(($x + 39), ($y + 26)))
        )
        $g.FillPolygon($brush, $points)
    } else {
        $g.DrawLine($pen, $x + 6, $y + 33, $x + 36, $y + 33)
        $g.DrawLine($pen, $x + 12, $y + 18, $x + 20, $y + 6)
        $g.DrawLine($pen, $x + 30, $y + 18, $x + 38, $y + 6)
        $g.DrawEllipse($pen, $x + 4, $y + 32, 10, 10)
        $g.DrawEllipse($pen, $x + 31, $y + 32, 10, 10)
    }
    $pen.Dispose()
    $brush.Dispose()
}

function DrawPhoneShell($g, [float]$x, [float]$y, [float]$w, [float]$h) {
    FillRoundRect $g $x $y $w $h 58 (ColorFromHex "#101820")
    FillRoundRect $g ($x + 24) ($y + 28) ($w - 48) ($h - 56) 40 ([System.Drawing.Color]::White)
    FillRoundRect $g ($x + ($w / 2) - 62) ($y + 18) 124 18 9 (ColorFromHex "#101820")
}

function DrawStatusBar($g, [float]$x, [float]$y, [float]$w) {
    DrawText $g "9:41" ($x + 24) ($y + 18) 90 30 (Font 18 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#0F172A")
    FillRoundRect $g ($x + $w - 116) ($y + 24) 36 12 6 (ColorFromHex "#0F172A")
    FillRoundRect $g ($x + $w - 72) ($y + 24) 48 12 6 (ColorFromHex "#16A34A")
}

function DrawScreenChrome($g, [float]$x, [float]$y, [float]$w, [string]$title) {
    FillRoundRect $g $x $y $w 92 0 ([System.Drawing.Color]::White)
    DrawStatusBar $g $x $y $w
    DrawText $g $title ($x + 24) ($y + 54) ($w - 48) 34 (Font 23 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#0F172A")
}

function DrawFeatureGraphic {
    $canvas = New-Canvas 1024 500
    $g = $canvas.Graphics
    $bmp = $canvas.Bitmap
    $teal = ColorFromHex "#008080"
    $deep = ColorFromHex "#004E52"
    $amber = ColorFromHex "#FFA726"
    $ink = ColorFromHex "#0F172A"

    $g.Clear((ColorFromHex "#F8FAFC"))
    FillRoundRect $g -80 -120 690 740 0 $teal
    FillRoundRect $g 560 -80 540 660 0 (ColorFromHex "#E7F5F2")

    $meshPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(35, 255, 255, 255), 3)
    for ($i = 0; $i -lt 9; $i++) {
        $yy = 40 + ($i * 54)
        $g.DrawBezier($meshPen, -10, $yy, 160, $yy - 85, 310, $yy + 90, 600, $yy - 20)
    }
    $meshPen.Dispose()

    $icon = [System.Drawing.Image]::FromFile($IconPath)
    $g.DrawImage($icon, 68, 58, 86, 86)
    $icon.Dispose()

    DrawText $g "Rishfy" 176 52 330 64 (Font 54 ([System.Drawing.FontStyle]::Bold)) ([System.Drawing.Color]::White)
    DrawText $g "Trusted routes across Tanzania" 76 164 430 92 (Font 29 ([System.Drawing.FontStyle]::Bold)) ([System.Drawing.Color]::White)
    DrawText $g "Book seats, track trips live, and move with D5-licensed confidence." 78 266 410 82 (Font 22) ([System.Drawing.Color]::FromArgb(235, 255, 255, 255))

    DrawPill $g "D5 licensed" 78 368 148 ([System.Drawing.Color]::FromArgb(32, 255, 255, 255)) ([System.Drawing.Color]::White)
    DrawPill $g "Live tracking" 242 368 154 ([System.Drawing.Color]::FromArgb(32, 255, 255, 255)) ([System.Drawing.Color]::White)
    DrawPill $g "Bookings" 412 368 126 ([System.Drawing.Color]::FromArgb(32, 255, 255, 255)) ([System.Drawing.Color]::White)

    DrawPhoneShell $g 650 42 250 420
    $sx = 674
    $sy = 70
    $sw = 202
    DrawScreenChrome $g $sx $sy $sw "Route details"
    DrawMap $g ($sx + 14) ($sy + 102) ($sw - 28) 150 $false
    DrawText $g "Dar -> Morogoro" ($sx + 18) ($sy + 268) ($sw - 36) 32 (Font 17 ([System.Drawing.FontStyle]::Bold)) $ink
    DrawText $g "Today, 14:30" ($sx + 18) ($sy + 300) 112 26 (Font 14) (ColorFromHex "#64748B")
    DrawText $g "TZS 12,000" ($sx + 18) ($sy + 332) 112 28 (Font 18 ([System.Drawing.FontStyle]::Bold)) $teal
    FillRoundRect $g ($sx + 18) ($sy + 365) ($sw - 36) 40 8 $teal
    DrawText $g "Book seat" ($sx + 18) ($sy + 374) ($sw - 36) 28 (Font 15 ([System.Drawing.FontStyle]::Bold)) ([System.Drawing.Color]::White) "Center"

    $bmp.Save((Join-Path $OutDir "feature-graphic-1024x500.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

function DrawSearchScreen($g, [float]$x, [float]$y, [float]$w, [float]$h) {
    DrawScreenChrome $g $x $y $w "Search routes"
    DrawMap $g ($x + 22) ($y + 108) ($w - 44) 430 $false
    FillRoundRect $g ($x + 22) ($y + 568) ($w - 44) 508 24 ([System.Drawing.Color]::White)
    StrokeRoundRect $g ($x + 22) ($y + 568) ($w - 44) 508 24 (ColorFromHex "#D7E5E2") 2
    DrawText $g "Where to?" ($x + 54) ($y + 604) ($w - 108) 44 (Font 31 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#0F172A")
    @(
        @("From", "Dar es Salaam CBD", "#008080"),
        @("To", "Morogoro Bus Terminal", "#DC2626"),
        @("When", "Today at 14:30", "#FFA726"),
        @("Seats", "2 passengers", "#0EA5E9")
    ) | ForEach-Object -Begin { $i = 0 } -Process {
        $yy = $y + 674 + ($i * 76)
        FillRoundRect $g ($x + 54) $yy ($w - 108) 58 12 (ColorFromHex "#F8FAFC")
        FillRoundRect $g ($x + 74) ($yy + 18) 22 22 11 (ColorFromHex $_[2])
        DrawText $g $_[0] ($x + 112) ($yy + 8) 120 22 (Font 14 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#64748B")
        DrawText $g $_[1] ($x + 112) ($yy + 27) ($w - 184) 28 (Font 21 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#0F172A")
        $i++
    }
    FillRoundRect $g ($x + 54) ($y + 998) ($w - 108) 54 14 (ColorFromHex "#008080")
    DrawText $g "Find routes" ($x + 54) ($y + 1012) ($w - 108) 30 (Font 20 ([System.Drawing.FontStyle]::Bold)) ([System.Drawing.Color]::White) "Center"
}

function DrawBookingScreen($g, [float]$x, [float]$y, [float]$w, [float]$h) {
    DrawScreenChrome $g $x $y $w "Route details"
    DrawMap $g ($x + 22) ($y + 104) ($w - 44) 350 $false
    DrawText $g "Dar es Salaam -> Dodoma" ($x + 30) ($y + 486) ($w - 60) 42 (Font 29 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#0F172A")
    @(
        @("Departure", "Today, 14:30", "track"),
        @("Available seats", "4 / 6", "seat"),
        @("Price per seat", "TZS 18,000", "cash"),
        @("Driver rating", "4.8 / 5.0 - Amani", "search")
    ) | ForEach-Object -Begin { $i = 0 } -Process {
        $yy = $y + 554 + ($i * 86)
        FillRoundRect $g ($x + 30) $yy ($w - 60) 68 16 (ColorFromHex "#F8FAFC")
        DrawSmallIcon $g $_[2] ($x + 52) ($yy + 13) (ColorFromHex "#008080")
        DrawText $g $_[0] ($x + 118) ($yy + 9) 190 24 (Font 15 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#64748B")
        DrawText $g $_[1] ($x + 118) ($yy + 34) ($w - 172) 28 (Font 21 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#0F172A")
        $i++
    }
    FillRoundRect $g ($x + 30) ($y + 928) ($w - 60) 66 16 (ColorFromHex "#008080")
    DrawText $g "Book this route" ($x + 30) ($y + 944) ($w - 60) 36 (Font 23 ([System.Drawing.FontStyle]::Bold)) ([System.Drawing.Color]::White) "Center"
}

function DrawTrackingScreen($g, [float]$x, [float]$y, [float]$w, [float]$h) {
    DrawScreenChrome $g $x $y $w "Your trip"
    DrawMap $g ($x + 0) ($y + 92) $w 760 $false
    FillRoundRect $g ($x + $w - 78) ($y + 116) 52 52 26 (ColorFromHex "#DC2626")
    DrawText $g "!" ($x + $w - 78) ($y + 119) 52 46 (Font 30 ([System.Drawing.FontStyle]::Bold)) ([System.Drawing.Color]::White) "Center"
    FillRoundRect $g ($x + 34) ($y + 780) ($w - 68) 292 28 ([System.Drawing.Color]::White)
    StrokeRoundRect $g ($x + 34) ($y + 780) ($w - 68) 292 28 (ColorFromHex "#D7E5E2") 2
    DrawText $g "Driver arriving soon" ($x + 66) ($y + 820) ($w - 132) 38 (Font 28 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#0F172A")
    DrawText $g "Amani is 6 min away" ($x + 66) ($y + 866) ($w - 132) 32 (Font 21) (ColorFromHex "#64748B")
    FillRoundRect $g ($x + 66) ($y + 924) 150 74 18 (ColorFromHex "#E6F4F1")
    DrawText $g "Live" ($x + 86) ($y + 936) 110 26 (Font 16 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#008080") "Center"
    DrawText $g "tracking" ($x + 86) ($y + 960) 110 26 (Font 16 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#008080") "Center"
    FillRoundRect $g ($x + 236) ($y + 924) 190 74 18 (ColorFromHex "#FFF4E4")
    DrawText $g "Emergency" ($x + 256) ($y + 936) 150 26 (Font 16 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#B45309") "Center"
    DrawText $g "ready" ($x + 256) ($y + 960) 150 26 (Font 16 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#B45309") "Center"
}

function DrawDriverScreen($g, [float]$x, [float]$y, [float]$w, [float]$h) {
    DrawScreenChrome $g $x $y $w "Post a route"
    DrawText $g "Fill seats on routes you already drive." ($x + 30) ($y + 106) ($w - 60) 54 (Font 22) (ColorFromHex "#64748B")
    @(
        @("Origin", "Arusha Clock Tower"),
        @("Destination", "Moshi Town"),
        @("Departure", "Tomorrow, 08:00"),
        @("Seats", "3 seats available"),
        @("Price", "TZS 9,000 per seat")
    ) | ForEach-Object -Begin { $i = 0 } -Process {
        $yy = $y + 178 + ($i * 82)
        FillRoundRect $g ($x + 30) $yy ($w - 60) 62 14 (ColorFromHex "#F8FAFC")
        DrawText $g $_[0] ($x + 56) ($yy + 9) 150 22 (Font 15 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#64748B")
        DrawText $g $_[1] ($x + 56) ($yy + 31) ($w - 112) 28 (Font 21 ([System.Drawing.FontStyle]::Bold)) (ColorFromHex "#0F172A")
        $i++
    }
    DrawMap $g ($x + 30) ($y + 620) ($w - 60) 270 $false
    FillRoundRect $g ($x + 30) ($y + 930) ($w - 60) 66 16 (ColorFromHex "#008080")
    DrawText $g "Publish route" ($x + 30) ($y + 946) ($w - 60) 36 (Font 23 ([System.Drawing.FontStyle]::Bold)) ([System.Drawing.Color]::White) "Center"
}

function DrawScreenshot([string]$fileName, [string]$headline, [string]$subhead, [string]$kind) {
    $canvas = New-Canvas 1080 1920
    $g = $canvas.Graphics
    $bmp = $canvas.Bitmap
    $teal = ColorFromHex "#008080"
    $ink = ColorFromHex "#0F172A"
    $g.Clear((ColorFromHex "#F8FAFC"))
    FillRoundRect $g 0 0 1080 570 0 $teal
    $meshPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(30, 255, 255, 255), 5)
    for ($i = 0; $i -lt 8; $i++) {
        $yy = 55 + ($i * 74)
        $g.DrawBezier($meshPen, -30, $yy, 300, $yy - 120, 660, $yy + 130, 1120, $yy - 40)
    }
    $meshPen.Dispose()

    DrawText $g $headline 96 88 888 98 (Font 58 ([System.Drawing.FontStyle]::Bold)) ([System.Drawing.Color]::White)
    DrawText $g $subhead 100 202 820 76 (Font 30) ([System.Drawing.Color]::FromArgb(232, 255, 255, 255))

    DrawPhoneShell $g 150 390 780 1410
    $sx = 174
    $sy = 418
    $sw = 732
    $sh = 1354
    if ($kind -eq "search") { DrawSearchScreen $g $sx $sy $sw $sh }
    elseif ($kind -eq "book") { DrawBookingScreen $g $sx $sy $sw $sh }
    elseif ($kind -eq "track") { DrawTrackingScreen $g $sx $sy $sw $sh }
    else { DrawDriverScreen $g $sx $sy $sw $sh }

    $icon = [System.Drawing.Image]::FromFile($IconPath)
    $g.DrawImage($icon, 86, 1690, 72, 72)
    $icon.Dispose()
    DrawText $g "Rishfy" 176 1700 220 48 (Font 35 ([System.Drawing.FontStyle]::Bold)) $ink

    $bmp.Save((Join-Path $OutDir $fileName), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

DrawFeatureGraphic
DrawScreenshot "screenshot-01-find-routes-1080x1920.png" "Find trusted routes" "Search available seats between Tanzanian cities in seconds." "search"
DrawScreenshot "screenshot-02-book-seat-1080x1920.png" "Book seats fast" "See price, departure time, seats, vehicle, and driver details." "book"
DrawScreenshot "screenshot-03-live-tracking-1080x1920.png" "Track trips live" "Follow your driver on the map with emergency tools close by." "track"
DrawScreenshot "screenshot-04-driver-routes-1080x1920.png" "Drive and earn" "Post routes, set seats, preview the map, and publish quickly." "driver"

Write-Output "Generated Play Store assets in $OutDir"
