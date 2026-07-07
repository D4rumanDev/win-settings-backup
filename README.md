# Windows Settings Backup

Copia de seguridad y restauración de ajustes de usuario de Windows basada en el [catálogo oficial de Windows Backup](https://support.microsoft.com/en-us/windows/windows-backup-settings-catalog-deebcba2-5bc0-4e63-279a-329926955708).

Diseñado para replicar configuración entre equipos con hardware diferente o recuperar ajustes tras una reinstalación limpia.

## Qué incluye

Cada copia guarda tres elementos:

| Elemento | Contenido |
|----------|-----------|
| **Registro** | 18 claves HKCU: accesibilidad, escritorio, ratón, cursores, idioma, sonido, Explorer, temas, notificaciones, touchpad, menú Inicio, Game Bar, personalización de escritura |
| **Wi-Fi** | Todos los perfiles guardados, incluidas las contraseñas (WPA) |
| **Apps** | Lista de aplicaciones instaladas via winget (`apps.json`) |

### Qué no incluye (y por qué)

| Ajuste | Motivo |
|--------|--------|
| Night Light | Datos binarios cifrados con DPAPI — no portables entre cuentas de usuario |
| Credenciales web | Almacenadas en Windows Credential Manager con cifrado por usuario |
| Zona horaria | Clave HKLM — depende del hardware y la región del equipo |
| Configuración interna de apps Win32 | Cada app usa su propio mecanismo; no hay formato estándar |

## Requisitos

- Windows 10 / 11
- PowerShell 7+ (el script se auto-relanza con `pwsh` si se ejecuta desde PS5)
- Permisos de administrador (necesarios para exportar contraseñas Wi-Fi con `netsh wlan export key=clear`)

## Uso

### Desde GitHub (irm)

```powershell
# Menú interactivo — se auto-eleva a admin
irm https://raw.githubusercontent.com/D4rumanDev/win-settings-backup/master/win-settings-backup.ps1 | iex

# Con parámetros (requiere ScriptBlock para pasar args)
& ([ScriptBlock]::Create((irm 'https://raw.githubusercontent.com/D4rumanDev/win-settings-backup/master/win-settings-backup.ps1'))) -Backup
& ([ScriptBlock]::Create((irm 'https://raw.githubusercontent.com/D4rumanDev/win-settings-backup/master/win-settings-backup.ps1'))) -List
```

### Desde archivo local

```powershell
.\win-settings-backup.ps1                            # Menú interactivo
.\win-settings-backup.ps1 -Backup                   # Backup directo
.\win-settings-backup.ps1 -Restore                  # Restaurar (menú de selección)
.\win-settings-backup.ps1 -Restore -BackupPath "D:\backup-PC1-2026-01-15_1030"
.\win-settings-backup.ps1 -List                     # Listar copias guardadas
```

### Ejecución remota (Invoke-Command)

```powershell
# Backup en equipo remoto
Invoke-Command -ComputerName PC2 -ScriptBlock {
    & "C:\Scripts\win-settings-backup.ps1" -Backup
}

# Restaurar desde ruta de red (requiere admin en destino)
Invoke-Command -ComputerName PC2 -ScriptBlock {
    & "C:\Scripts\win-settings-backup.ps1" -Restore -BackupPath "\\NAS\shared\backup-PC1-2026-01-15_1030"
}
```

### Hacer una copia de seguridad

1. Ejecutar el script (solicita elevación automáticamente si es necesario)
2. Seleccionar **[1] Hacer copia de seguridad**
3. La copia se guarda en:
   ```
   %USERPROFILE%\win-settings-backup\backup-{EQUIPO}-{FECHA}\
   ```

### Restaurar en otro equipo

1. Copiar la carpeta del backup al equipo destino (USB, red, nube...)
2. Ejecutar el script y seleccionar **[2] Restaurar copia de seguridad**
3. El script lista las copias disponibles en `%USERPROFILE%\win-settings-backup\`
   — o usar `-BackupPath` para apuntar a una carpeta diferente
4. Confirmar individualmente qué restaurar: registro, Wi-Fi, apps

> **Importante:** Reiniciar la sesión de Windows tras restaurar el registro para que los cambios surtan efecto.

## Estructura de la copia

```
backup-PC1-2026-01-15_1030\
├── registry\
│   ├── Accessibility.reg
│   ├── Desktop.reg
│   ├── Mouse.reg
│   ├── Cursors.reg
│   ├── International.reg
│   ├── Sound.reg
│   ├── Accessibility-App.reg
│   ├── Explorer-Advanced.reg
│   ├── Explorer-Cabinet.reg
│   ├── Themes.reg
│   ├── Notifications.reg
│   ├── Touchpad.reg
│   ├── Start.reg
│   ├── GameBar.reg
│   ├── GameConfig.reg
│   ├── InputPersonal.reg
│   ├── Policies-Explorer.reg
│   └── TabletTip.reg
├── wifi\
│   └── NombreRed.xml
├── apps.json
└── manifest.json
```

## Nota de seguridad

Los perfiles Wi-Fi se exportan con contraseña en texto claro dentro del XML (`key=clear`). Guardar las copias en una ubicación de acceso controlado (no repositorio público, no USB sin cifrar).

El registro exportado es HKCU — solo afecta al perfil del usuario actual, sin tocar el sistema.
