<#
.SYNOPSIS
    Copia de seguridad y restauracion de ajustes de usuario de Windows.
.DESCRIPTION
    Exporta e importa los ajustes definidos en el catalogo de Windows Backup:
    accesibilidad, interfaz, raton, notificaciones, temas, Wi-Fi y apps instaladas.
    Disenado para replicar configuracion entre equipos o recuperar tras un reinstall.
.PARAMETER Backup
    Ejecuta la copia de seguridad directamente sin mostrar el menu.
.PARAMETER Restore
    Ejecuta la restauracion sin mostrar el menu.
.PARAMETER BackupPath
    Ruta a la carpeta de backup a restaurar (usar con -Restore).
.EXAMPLE
    .\win-settings-backup.ps1
    .\win-settings-backup.ps1 -Backup
    .\win-settings-backup.ps1 -Restore
    .\win-settings-backup.ps1 -Restore -BackupPath "D:\backup-AORUS-2026-07-07_1530"
.NOTES
    Requiere PowerShell 7+ y permisos de administrador.
    https://github.com/D4rumanDev/win-settings-backup
#>
param(
    [switch]$Backup,
    [switch]$Restore,
    [string]$BackupPath
)

# ── PS7 bootstrap ─────────────────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
    if ($pwsh) { & $pwsh -ExecutionPolicy Bypass -File $PSCommandPath @args; exit $LASTEXITCODE }
    Write-Host 'Se requiere PowerShell 7. Instalalo con: winget install Microsoft.PowerShell' -ForegroundColor Red
    exit 1
}

# ── Autoelevacion ─────────────────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    $argStr = "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Backup)     { $argStr += ' -Backup' }
    if ($Restore)    { $argStr += ' -Restore' }
    if ($BackupPath) { $argStr += " -BackupPath `"$BackupPath`"" }
    Start-Process pwsh -ArgumentList $argStr -Verb RunAs
    exit 0
}

$ErrorActionPreference = 'Continue'

# ── Configuracion ─────────────────────────────────────────────────────────────
$Version     = '1.0'
$BackupsRoot = "$env:USERPROFILE\win-settings-backup"

$RegKeys = [ordered]@{
    'Accessibility'     = 'HKCU\Control Panel\Accessibility'
    'Desktop'           = 'HKCU\Control Panel\Desktop'
    'Mouse'             = 'HKCU\Control Panel\Mouse'
    'Cursors'           = 'HKCU\Control Panel\Cursors'
    'International'     = 'HKCU\Control Panel\International'
    'Sound'             = 'HKCU\Control Panel\Sound'
    'Accessibility-App' = 'HKCU\Software\Microsoft\Accessibility'
    'Explorer-Advanced' = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    'Explorer-Cabinet'  = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState'
    'Themes'            = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes'
    'Notifications'     = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    'Touchpad'          = 'HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'
    'Start'             = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Start'
    'GameBar'           = 'HKCU\Software\Microsoft\GameBar'
    'GameConfig'        = 'HKCU\System\GameConfigStore'
    'InputPersonal'     = 'HKCU\Software\Microsoft\InputPersonalization'
    'Policies-Explorer' = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    'TabletTip'         = 'HKCU\Software\Microsoft\TabletTip'
}

# ── UI ────────────────────────────────────────────────────────────────────────
$_sep = '  ' + ([string][char]0x2550) * 52

function Write-Ok($msg)   { Write-Host "  [OK]  $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "  [--]  $msg" -ForegroundColor DarkGray }
function Write-Fail($msg) { Write-Host "  [!!]  $msg" -ForegroundColor Red }
function Sep              { Write-Host $_sep -ForegroundColor DarkGray }

function Show-Header {
    param([string]$Sub = '')
    $osi = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    $os  = if ($osi) { $osi.Caption -replace 'Microsoft ', '' } else { 'Windows' }
    Clear-Host
    Write-Host ''
    Write-Host $_sep -ForegroundColor Cyan
    Write-Host "   Windows Settings Backup  v$Version" -ForegroundColor Cyan
    Write-Host $_sep -ForegroundColor Cyan
    Write-Host "   Equipo : $($env:COMPUTERNAME.PadRight(16))  Usuario: $env:USERNAME" -ForegroundColor DarkGray
    Write-Host "   Fecha  : $(Get-Date -Format 'yyyy-MM-dd HH:mm')       OS     : $os" -ForegroundColor DarkGray
    Write-Host $_sep -ForegroundColor Cyan
    if ($Sub) { Write-Host "   $Sub" -ForegroundColor Yellow }
    Write-Host ''
}

# ── Backup ────────────────────────────────────────────────────────────────────
function Invoke-Backup {
    $ts      = Get-Date -Format 'yyyy-MM-dd_HHmm'
    $dest    = "$BackupsRoot\backup-$($env:COMPUTERNAME)-$ts"
    $regDir  = "$dest\registry"
    $wifiDir = "$dest\wifi"
    New-Item -ItemType Directory -Force -Path $regDir, $wifiDir | Out-Null

    Show-Header 'COPIA DE SEGURIDAD'

    Write-Host '  Registro' -ForegroundColor White
    $regOk = 0
    foreach ($kv in $RegKeys.GetEnumerator()) {
        $psPath = $kv.Value -replace '^HKCU\\', 'HKCU:\'
        if (-not (Test-Path $psPath)) { Write-Skip $kv.Key; continue }
        reg export $kv.Value "$regDir\$($kv.Key).reg" /y 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Ok $kv.Key; $regOk++ }
        else                     { Write-Fail $kv.Key }
    }

    Write-Host ''
    Write-Host '  Wi-Fi' -ForegroundColor White
    netsh wlan export profile folder="$wifiDir" key=clear 2>$null | Out-Null
    $wifiCount = (Get-ChildItem "$wifiDir\*.xml" -EA SilentlyContinue | Measure-Object).Count
    if ($wifiCount -gt 0) { Write-Ok "$wifiCount perfil(es)" }
    else                  { Write-Skip 'No hay perfiles Wi-Fi guardados' }

    Write-Host ''
    Write-Host '  Apps (winget)' -ForegroundColor White
    $appsFile = "$dest\apps.json"
    winget export -o $appsFile --accept-source-agreements 2>$null | Out-Null
    if (Test-Path $appsFile) {
        try {
            $n = ((Get-Content $appsFile -Raw | ConvertFrom-Json).Sources |
                  ForEach-Object { $_.Packages.Count } | Measure-Object -Sum).Sum
            Write-Ok "$n aplicacion(es)"
        } catch { Write-Ok 'Apps exportadas' }
    } else { Write-Fail 'winget no disponible o sin resultados' }

    $osi = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    @{
        version  = $Version
        date     = (Get-Date -Format 'o')
        computer = $env:COMPUTERNAME
        user     = $env:USERNAME
        os       = if ($osi) { $osi.Caption } else { '' }
        registry = $regOk
        wifi     = $wifiCount
    } | ConvertTo-Json | Set-Content "$dest\manifest.json" -Encoding UTF8

    Sep
    Write-Host ''
    Write-Host '  Copia guardada en:' -ForegroundColor White
    Write-Host "  $dest" -ForegroundColor Cyan
    Write-Host ''
}

# ── Ver copias ────────────────────────────────────────────────────────────────
function Show-Backups {
    $items = Get-ChildItem "$BackupsRoot\backup-*" -Directory -EA SilentlyContinue |
             Sort-Object Name -Descending
    Show-Header 'COPIAS GUARDADAS'
    if (-not $items) { Write-Skip "No hay copias en $BackupsRoot"; Write-Host ''; return }
    foreach ($b in $items) {
        Write-Host "  $($b.Name)" -ForegroundColor White
        $mf = "$($b.FullName)\manifest.json"
        if (Test-Path $mf) {
            $m    = Get-Content $mf -Raw | ConvertFrom-Json
            $d    = [datetime]::Parse($m.date).ToString('yyyy-MM-dd HH:mm')
            $size = [math]::Round((Get-ChildItem $b.FullName -Recurse -EA SilentlyContinue |
                                   Measure-Object Length -Sum).Sum / 1KB)
            Write-Host "  $($m.computer) · $d · $($m.registry) claves · $($m.wifi) Wi-Fi · ${size} KB" -ForegroundColor DarkGray
        }
        Write-Host ''
    }
    Sep
}

# ── Restore ───────────────────────────────────────────────────────────────────
function Select-Backup {
    $items = Get-ChildItem "$BackupsRoot\backup-*" -Directory -EA SilentlyContinue |
             Sort-Object Name -Descending
    if (-not $items) {
        Show-Header 'RESTAURAR'
        Write-Fail "No hay copias en $BackupsRoot"
        Write-Host ''; return $null
    }
    Show-Header 'SELECCIONAR COPIA'
    $i = 1
    foreach ($b in $items) {
        Write-Host "  [$i]  $($b.Name)" -ForegroundColor White
        $mf = "$($b.FullName)\manifest.json"
        if (Test-Path $mf) {
            $m = Get-Content $mf -Raw | ConvertFrom-Json
            $d = [datetime]::Parse($m.date).ToString('yyyy-MM-dd HH:mm')
            Write-Host "       $($m.computer) · $d · $($m.registry) claves · $($m.wifi) Wi-Fi" -ForegroundColor DarkGray
        }
        Write-Host ''; $i++
    }
    Sep
    $sel = Read-Host '  Numero (Enter para cancelar)'
    if (-not $sel -or $sel -notmatch '^\d+$') { return $null }
    $idx = [int]$sel - 1
    if ($idx -lt 0 -or $idx -ge $items.Count) { return $null }
    return $items[$idx].FullName
}

function Invoke-Restore {
    param([string]$Path = '')
    if (-not $Path) { $Path = Select-Backup }
    if (-not $Path) { return }
    if (-not (Test-Path $Path -PathType Container)) {
        Show-Header 'RESTAURAR'
        Write-Fail "Ruta no encontrada: $Path"
        Write-Host ''; return
    }

    Show-Header 'RESTAURAR COPIA DE SEGURIDAD'
    Write-Host "  Origen: $Path" -ForegroundColor DarkGray
    Write-Host ''

    $regFiles = Get-ChildItem "$Path\registry\*.reg" -EA SilentlyContinue
    if ($regFiles) {
        $ans = Read-Host "  Restaurar $($regFiles.Count) claves de registro? [S/N]"
        if ($ans -match '^[Ss]') {
            Write-Host ''
            foreach ($f in $regFiles) {
                reg import $f.FullName 2>$null
                if ($LASTEXITCODE -eq 0) { Write-Ok $f.BaseName }
                else                     { Write-Fail $f.BaseName }
            }
            Write-Host ''
        }
    } else { Write-Skip 'Sin archivos de registro'; Write-Host '' }

    $wifiFiles = Get-ChildItem "$Path\wifi\*.xml" -EA SilentlyContinue
    if ($wifiFiles) {
        $ans = Read-Host "  Restaurar $($wifiFiles.Count) perfil(es) Wi-Fi? [S/N]"
        if ($ans -match '^[Ss]') {
            Write-Host ''
            foreach ($f in $wifiFiles) {
                netsh wlan add profile filename="$($f.FullName)" 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Ok $f.BaseName }
                else                     { Write-Fail $f.BaseName }
            }
            Write-Host ''
        }
    } else { Write-Skip 'Sin perfiles Wi-Fi'; Write-Host '' }

    $appsFile = "$Path\apps.json"
    if (Test-Path $appsFile) {
        try {
            $n = ((Get-Content $appsFile -Raw | ConvertFrom-Json).Sources |
                  ForEach-Object { $_.Packages.Count } | Measure-Object -Sum).Sum
        } catch { $n = '?' }
        $ans = Read-Host "  Instalar $n app(s) faltantes via winget? [S/N]"
        if ($ans -match '^[Ss]') {
            Write-Host ''
            Write-Host '  Instalando apps (puede tardar varios minutos)...' -ForegroundColor DarkGray
            winget import -i $appsFile --accept-package-agreements --accept-source-agreements --ignore-versions 2>&1 |
                Where-Object { $_ -match '(instalando|installing|failed|error)' } |
                ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            Write-Ok 'Apps — proceso completado'
            Write-Host ''
        }
    } else { Write-Skip 'Sin lista de apps'; Write-Host '' }

    Sep
    Write-Host ''
    Write-Host '  Restauracion completada.' -ForegroundColor Green
    Write-Host '  Reinicia la sesion para aplicar los cambios de registro.' -ForegroundColor DarkGray
    Write-Host ''
}

# ── Main ──────────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $BackupsRoot | Out-Null

if ($Backup)  { Invoke-Backup; exit 0 }
if ($Restore) { Invoke-Restore -Path $BackupPath; exit 0 }

do {
    Show-Header
    Write-Host '    [1]  Hacer copia de seguridad' -ForegroundColor White
    Write-Host '    [2]  Restaurar copia de seguridad' -ForegroundColor White
    Write-Host '    [3]  Ver copias guardadas' -ForegroundColor White
    Write-Host '    [Q]  Salir' -ForegroundColor DarkGray
    Write-Host ''
    Sep
    $choice = (Read-Host '  Opcion').Trim().ToUpper()
    switch ($choice) {
        '1' { Invoke-Backup;  Read-Host '  Pulsa Enter para volver al menu' | Out-Null }
        '2' { Invoke-Restore; Read-Host '  Pulsa Enter para volver al menu' | Out-Null }
        '3' { Show-Backups;   Read-Host '  Pulsa Enter para volver al menu' | Out-Null }
    }
} while ($choice -ne 'Q')
