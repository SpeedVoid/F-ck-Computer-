$Signatures = @'
[DllImport("user32.dll")]
public static extern IntPtr GetDC(IntPtr hWnd);

[DllImport("user32.dll")]
public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

[DllImport("gdi32.dll")]
public static extern bool BitBlt(IntPtr hdcDest, int nXDest, int nYDest, int nWidth, int nHeight, IntPtr hdcSrc, int nXSrc, int nYSrc, uint dwRop);

[DllImport("user32.dll")]
public static extern int GetSystemMetrics(int nIndex);

[DllImport("kernel32.dll")]
public static extern bool Beep(uint dwFreq, uint dwDuration);

[DllImport("gdi32.dll")]
public static extern bool StretchBlt(IntPtr hdcDest, int nXOriginDest, int nYOriginDest, int nWidthDest, int nHeightDest, IntPtr hdcSrc, int nXOriginSrc, int nYOriginSrc, int nWidthSrc, int nHeightSrc, uint dwRop);
'@

# Компилируем расширенный набор функций
$WinAPI = Add-Type -MemberDefinition $Signatures -Name "GDIMaxFixed" -Namespace "Win32" -PassThru

# Определяем границы экрана
$w = [Win32.GDIMaxFixed]::GetSystemMetrics(0)
$h = [Win32.GDIMaxFixed]::GetSystemMetrics(1)

Write-Host "ВНИМАНИЕ: Исправленный агрессивный режим GDI + Звук!" -ForegroundColor DarkRed
Write-Host "Для мгновенной остановки закройте это окно или нажмите Ctrl+C." -ForegroundColor Yellow

try {
    while ($true) {
        $hdc = [Win32.GDIMaxFixed]::GetDC([IntPtr]::Zero)
        
        # Параметры для разрушения геометрии
        $x = Get-Random -Minimum 0 -Maximum $w
        $y = Get-Random -Minimum 0 -Maximum $h
        $width = Get-Random -Minimum 100 -Maximum 500
        $height = Get-Random -Minimum 100 -Maximum 500
        
        $mode = Get-Random -Minimum 0 -Maximum 5

        switch ($mode) {
            0 {
                # ТУННЕЛЬНЫЙ ЭФФЕКТ: Сжимает весь экран внутрь себя
                [Win32.GDIMaxFixed]::StretchBlt($hdc, 10, 10, $w - 20, $h - 20, $hdc, 0, 0, $w, $h, 0x00CC0020)
            }
            1 {
                # КРУПНОЗЕРНИСТЫЙ ПИКСЕЛЬНЫЙ СДВИГ
                [Win32.GDIMaxFixed]::BitBlt($hdc, $x + (Get-Random -Minimum -40 -Maximum 41), $y, $width, $height, $hdc, $x, $y, 0x00CC0020)
            }
            2 {
                # ЦВЕТОВОЙ ШОК (Инверсия мерцания)
                [Win32.GDIMaxFixed]::BitBlt($hdc, $x, $y, $width, $height, $hdc, $x, $y, 0x00550009)
            }
            3 {
                # РАСТЯЖЕНИЕ ПИКСЕЛЕЙ (Жидкий экран)
                [Win32.GDIMaxFixed]::StretchBlt($hdc, $x, $y, $width * 2, $height / 2, $hdc, $x, $y, $width, $height, 0x00CC0020)
            }
            4 {
                # ПОЛНЫЙ СБОЙ МАТРИЦЫ (Перемешивание блоков)
                $destX = Get-Random -Minimum 0 -Maximum $w
                $destY = Get-Random -Minimum 0 -Maximum $h
                [Win32.GDIMaxFixed]::BitBlt($hdc, $destX, $destY, $width, $height, $hdc, $x, $y, 0x00CC0020)
            }
        }
        
        # Генерируем страшный аналоговый писк
        $freq = Get-Random -Minimum 150 -Maximum 2500
        $duration = Get-Random -Minimum 10 -Maximum 35
        
        # ИСПРАВЛЕНИЕ: Явное приведение к [Action], чтобы избежать двусмысленности перегрузки метода Run
        $SoundAction = [Action]{ [Win32.GDIMaxFixed]::Beep($freq, $duration) }
        [void][Threading.Tasks.Task]::Run($SoundAction)

        [Win32.GDIMaxFixed]::ReleaseDC([IntPtr]::Zero, $hdc)
        
        # Минимальная задержка для безумной скорости отрисовки
        Start-Sleep -Milliseconds 2
    }
}
finally {
    # Принудительное очищение ресурсов при выходе из цикла
    $hdc = [Win32.GDIMaxFixed]::GetDC([IntPtr]::Zero)
    [Win32.GDIMaxFixed]::ReleaseDC([IntPtr]::Zero, $hdc)
    Write-Host "Работа завершена. Экран очищен." -ForegroundColor Green
}
