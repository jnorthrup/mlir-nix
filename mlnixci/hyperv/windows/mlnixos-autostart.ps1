# Keep the mlnixos distro running from boot, as Kali-Autostart keeps kali-linux: a WSL distro stops once nothing holds it.
# NixOS has no /bin/sleep: the system profile's.
$action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wsl.exe' -Argument '-d mlnixos --exec /run/current-system/sw/bin/sleep infinity'
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'mlnixos-Autostart' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force |
  Out-Null
Start-ScheduledTask -TaskName 'mlnixos-Autostart'
Get-ScheduledTask -TaskName 'mlnixos-Autostart' | Select-Object TaskName, State
