<#
  NestedVirtualization_VMware.ps1
  Zet de host (Windows 10/11) klaar voor nested virtualization in VMware Workstation,
  zoals in de cursus (Hyper-V uit, Windows-onderdelen uit, kernisolatie/geheugenintegriteit uit,
  firmwarebeveiliging uit, Device Guard / VBS uit).

  GEBRUIK (PowerShell als Administrator):
    1) Enkel controleren (verandert niets):
         powershell -ExecutionPolicy Bypass -File .\nestedvirtualization.ps1
    2) Instellingen toepassen:
         powershell -ExecutionPolicy Bypass -File .\nestedvirtualization.ps1 -Apply
    3) Na de herstart: opnieuw stap 1 uitvoeren om te controleren.
    Optioneel: -VmxPath "C:\pad\naar\vm.vmx" zet ook vhv.enable = TRUE in die VM (VMware afgesloten!).

  Logbestand: %PUBLIC%\NestedVirt_<datum>.log
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$VmxPath
)

$ErrorActionPreference = 'Continue'

# ---------- Administrator? ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Start PowerShell met 'Als administrator uitvoeren' en probeer opnieuw." -ForegroundColor Red
    exit 1
}

$log = Join-Path $env:PUBLIC ("NestedVirt_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $log | Out-Null

# ---------- Uitvoerhelpers ----------
# Bad  = moet opgelost worden (telt mee in de samenvatting)
# Warn = goed om te weten, maar blokkeert niets
$script:Issues = 0
function Title($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Bad($t)   { $script:Issues++; Write-Host "  [!!]   $t" -ForegroundColor Red }
function Warn($t)  { Write-Host "  [i]    $t" -ForegroundColor Yellow }
function Info($t)  { Write-Host "         $t" }

$DG   = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
$HVCI = "$DG\Scenarios\HypervisorEnforcedCodeIntegrity"
$SGL  = "$DG\Scenarios\SystemGuard"
$POL  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
$LSA  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$MDM  = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceGuard'

$Features = 'Microsoft-Hyper-V-All','VirtualMachinePlatform','HypervisorPlatform','Containers-DisposableClientVM'

function RegVal($path, $name) {
    try { (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { $null }
}

function Get-LaunchType {
    $bcd = (bcdedit /enum '{current}') -join "`n"
    if ($bcd -match 'hypervisorlaunchtype\s+(\S+)') { $Matches[1] } else { $null }   # $null = niet ingesteld (= Auto)
}

function Get-EnabledFeatures {
    foreach ($f in $Features) {
        $st = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if ($st -and $st.State -eq 'Enabled') { $f }
    }
}

function Show-Status {
    # ---------- Windows ----------
    Title "Windows"
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$cv.CurrentBuild
    $win = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    Info ("{0} {1}  versie {2}  (build {3}.{4})" -f $win, $cv.EditionID, $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR)
    $script:IsHome = $cv.EditionID -match 'Core'
    if ($script:IsHome) { Warn "Home-editie: Hyper-V, Sandbox en gpedit bestaan niet; script gebruikt het register." }

    # ---------- CPU ----------
    Title "Processor"
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Info $cpu.Name
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.HypervisorPresent) {
        Bad "Er draait nu een Windows-hypervisor (Hyper-V/VBS). VMware kan dan GEEN VT-x/AMD-V doorgeven."
    } else {
        Ok "Geen Windows-hypervisor actief."
        if ($cpu.VirtualizationFirmwareEnabled) { Ok "VT-x/AMD-V staat aan in BIOS/UEFI." }
        else { Bad "VT-x/AMD-V staat UIT in BIOS/UEFI: zet 'Virtualization Technology' / 'SVM' aan in het BIOS." }
    }

    # ---------- Windows-onderdelen (eerst, want de bcdedit-beoordeling hangt hiervan af) ----------
    $enabled = @(Get-EnabledFeatures)

    # ---------- Hypervisor launch type ----------
    Title "Hyper-V hypervisor (bcdedit)"
    $hlt = Get-LaunchType
    if ($hlt -match '^Off$') {
        Ok "hypervisorlaunchtype = Off"
    }
    elseif (-not $hlt -or $hlt -match '^Auto$') {
        $shown = if ($hlt) { $hlt } else { 'niet ingesteld (= Auto)' }
        if ($enabled.Count -eq 0 -and -not $cs.HypervisorPresent) {
            Warn "hypervisorlaunchtype = $shown. Nu onschadelijk (geen Hyper-V-onderdelen aan), maar Windows kan de hypervisor later terug starten."
            Info "-Apply zet dit expliciet op Off."
        } else {
            Bad "hypervisorlaunchtype = $shown en er zijn Hyper-V-onderdelen aan: -Apply zet dit op Off."
        }
    }
    else {
        Bad "hypervisorlaunchtype = $hlt (verwacht: Off)"
    }

    # ---------- Windows-onderdelen ----------
    Title "Windows-onderdelen"
    foreach ($f in $Features) {
        $st = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if (-not $st) { Info "$f : niet aanwezig op deze editie" }
        elseif ($st.State -eq 'Enabled') { Bad "$f : AAN" }
        else { Ok "$f : $($st.State)" }
    }
    $wsl = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Windows-Subsystem-Linux' -ErrorAction SilentlyContinue
    if ($wsl -and $wsl.State -eq 'Enabled') { Warn "WSL2 en Docker Desktop werken niet meer zonder VirtualMachinePlatform." }

    # ---------- VBS / Device Guard ----------
    Title "Kernisolatie / VBS / Device Guard"
    $hv = RegVal $HVCI 'Enabled'
    if ($hv -eq 1) { Bad "Geheugenintegriteit (HVCI) : AAN" } else { Ok "Geheugenintegriteit (HVCI) : uit" }
    $sg = RegVal $SGL 'Enabled'
    if ($sg -eq 1) { Bad "Firmwarebeveiliging (System Guard) : AAN" } else { Ok "Firmwarebeveiliging (System Guard) : uit/niet ingesteld" }
    $vbsPol = RegVal $POL 'EnableVirtualizationBasedSecurity'
    $vbsReg = RegVal $DG  'EnableVirtualizationBasedSecurity'
    Info "VBS-beleid (gpedit) = $vbsPol   VBS-register = $vbsReg"
    $cg = RegVal $LSA 'LsaCfgFlags'
    if ($cg -and $cg -ne 0) { Bad "Credential Guard staat aan (LsaCfgFlags = $cg)" }
    try {
        $d = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
        $s = @{0='uit';1='ingeschakeld maar draait niet';2='DRAAIT'}[[int]$d.VirtualizationBasedSecurityStatus]
        if ($d.VirtualizationBasedSecurityStatus -eq 2) { Bad "VBS-status nu: $s (diensten: $($d.SecurityServicesRunning -join ','))" }
        else { Ok "VBS-status nu: $s" }
    } catch { Info "VBS-status kon niet gelezen worden." }

    # ---------- Beheerd toestel? ----------
    Title "Beheer"
    if (Test-Path $MDM) {
        Warn "Device Guard wordt via Intune/MDM beheerd: instellingen kunnen na een sync terugkomen. Contacteer IT als dat gebeurt."
    } else { Ok "Geen Intune/MDM-beleid voor Device Guard gevonden." }
    $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
    if ($bl -and $bl.ProtectionStatus -eq 'On') {
        Warn "BitLocker staat aan op $($env:SystemDrive): wordt bij -Apply voor 1 herstart gepauzeerd. Houd toch je herstelsleutel bij de hand."
    }

    # ---------- Samenvatting ----------
    Title "Samenvatting"
    if ($script:Issues -eq 0) { Ok "Alles staat goed voor nested virtualization in VMware." }
    else { Write-Host "  $($script:Issues) punt(en) vragen aandacht (rood hierboven)." -ForegroundColor Red }
}

Show-Status

if (-not $Apply) {
    Write-Host ""
    if ($script:Issues -eq 0) {
        Write-Host "Enkel gecontroleerd. Niets te doen." -ForegroundColor Cyan
        if ((Get-LaunchType) -notmatch '^Off$') {
            Write-Host "Tip: -Apply zet hypervisorlaunchtype nog expliciet op Off (aanbevolen)." -ForegroundColor Cyan
        }
    } else {
        Write-Host "Enkel gecontroleerd. Start opnieuw met -Apply om de instellingen toe te passen." -ForegroundColor Cyan
    }
    Stop-Transcript | Out-Null
    exit 0
}

# =====================================================================
Title "Instellingen toepassen"

# 0. BitLocker 1 herstart pauzeren (anders vaak herstelsleutel nodig na VBS/Secure Launch-wijziging)
$bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
if ($bl -and $bl.ProtectionStatus -eq 'On') {
    Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 | Out-Null
    Ok "BitLocker gepauzeerd voor 1 herstart."
}

# 1. Hyper-V hypervisor niet laden (en controleren dat het echt vastgelegd is)
if ((Get-LaunchType) -match '^Off$') {
    Ok "hypervisorlaunchtype stond al op Off"
} else {
    bcdedit /set hypervisorlaunchtype off | Out-Null
    if ((Get-LaunchType) -match '^Off$') { Ok "hypervisorlaunchtype = Off ingesteld" }
    else { Bad "hypervisorlaunchtype kon niet op Off gezet worden (Secure Boot/beleid?). Controleer: bcdedit /enum '{current}'" }
}

# 2. Windows-onderdelen uit
foreach ($f in $Features) {
    $st = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
    if ($st -and $st.State -eq 'Enabled') {
        Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Ok "$f uitgeschakeld"
    }
}

# 3. Kernisolatie: geheugenintegriteit uit
New-Item -Path $HVCI -Force | Out-Null
Set-ItemProperty -Path $HVCI -Name Enabled -Value 0 -Type DWord
Ok "Geheugenintegriteit uit"

# 4. Firmwarebeveiliging (System Guard Secure Launch) uit
New-Item -Path $SGL -Force | Out-Null
Set-ItemProperty -Path $SGL -Name Enabled -Value 0 -Type DWord
Ok "Firmwarebeveiliging uit"

# 5. Device Guard / VBS uit (= gpedit 'Beveiliging op basis van virtualisatie inschakelen' -> Uitgeschakeld)
New-Item -Path $POL -Force | Out-Null
Set-ItemProperty -Path $POL -Name EnableVirtualizationBasedSecurity -Value 0 -Type DWord
Set-ItemProperty -Path $POL -Name LsaCfgFlags -Value 0 -Type DWord
Set-ItemProperty -Path $DG  -Name EnableVirtualizationBasedSecurity -Value 0 -Type DWord
Set-ItemProperty -Path $LSA -Name LsaCfgFlags -Value 0 -Type DWord
Ok "VBS / Device Guard / Credential Guard uit"

# 6. Optioneel: nested VT-x aanzetten in de VMware-VM (= vinkje 'Virtualize Intel VT-x/EPT or AMD-V/RVI')
if ($VmxPath) {
    if (-not (Test-Path $VmxPath)) { Bad "VMX-bestand niet gevonden: $VmxPath" }
    elseif (Get-Process vmware-vmx -ErrorAction SilentlyContinue) { Bad "Een VM draait nog: sluit VMware af en voer -VmxPath opnieuw uit." }
    else {
        Copy-Item $VmxPath "$VmxPath.bak" -Force
        $lines = Get-Content $VmxPath | Where-Object { $_ -notmatch '^\s*vhv\.enable\s*=' }
        $lines += 'vhv.enable = "TRUE"'
        Set-Content -Path $VmxPath -Value $lines -Encoding ASCII
        Ok "vhv.enable = TRUE gezet in $VmxPath (backup: .bak)"
    }
}

Write-Host ""
if ($script:Issues -gt 0) {
    Write-Host "Let op: $($script:Issues) stap(pen) mislukt (rood hierboven). Los die eerst op." -ForegroundColor Red
}
Write-Host "Klaar. HERSTART de computer nu en voer daarna het script opnieuw uit zonder -Apply om te controleren." -ForegroundColor Cyan
Write-Host "Verwacht na herstart: 'Geen Windows-hypervisor actief', 'hypervisorlaunchtype = Off' en 'VBS-status nu: uit'." -ForegroundColor Cyan
Write-Host "Log: $log"
Stop-Transcript | Out-Null
