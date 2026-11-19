<#
  nestedvirtualization-terug.ps1
  Zet de Windows-beveiliging terug aan na nestedvirtualization.ps1:
  Hyper-V-hypervisor, geheugenintegriteit (HVCI), firmwarebeveiliging (System Guard),
  VBS / Device Guard en Platform voor virtuele machine (WSL2, Docker Desktop).

  Let op: daarna werkt nested virtualization in VMware Workstation niet meer.

  GEBRUIK (PowerShell als Administrator):
    1) Tonen wat er zou gebeuren (verandert niets):
         powershell -ExecutionPolicy Bypass -File "$HOME\nestedvirtualization-terug.ps1"
    2) Terugzetten:
         powershell -ExecutionPolicy Bypass -File "$HOME\nestedvirtualization-terug.ps1" -Apply
    3) Ook Hyper-V en Windows Sandbox terug aanzetten (enkel Windows Pro):
         ... -Apply -HyperV
    4) Ook het vinkje voor nested VT-x in een VMware-VM weghalen:
         ... -Apply -VmxPath "D:\VMs\pve\pve.vmx"

  Logbestand: %PUBLIC%\NestedVirtTerug_<datum>.log
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$HyperV,
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

$log = Join-Path $env:PUBLIC ("NestedVirtTerug_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $log | Out-Null

function Title($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Bad($t)   { Write-Host "  [!!]   $t" -ForegroundColor Yellow }
function Info($t)  { Write-Host "         $t" }

$DG   = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
$HVCI = "$DG\Scenarios\HypervisorEnforcedCodeIntegrity"
$SGL  = "$DG\Scenarios\SystemGuard"
$POL  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
$LSA  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

function Zet-Waarde($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path | Out-Null }   # zonder -Force: bestaande sleutel blijft intact
    Set-ItemProperty -Path $path -Name $name -Value $value -Type DWord
}
function Wis-Waarde($path, $name) {
    if (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    }
}

$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$isHome = $cv.EditionID -match 'Core'

Title "Wat dit script terugzet"
Info "1. Hyper-V-hypervisor start weer bij het opstarten (bcdedit: auto)"
Info "2. Platform voor virtuele machine weer aan (WSL2, Docker Desktop)"
if ($HyperV) {
    if ($isHome) { Info "   Hyper-V en Windows Sandbox: bestaan niet op Windows Home, overgeslagen" }
    else         { Info "   ook Hyper-V en Windows Sandbox weer aan" }
}
Info "3. Geheugenintegriteit (HVCI) weer aan"
Info "4. Firmwarebeveiliging (System Guard) weer aan, als je laptop het ondersteunt"
Info "5. VBS / Device Guard: de uitschakeling door het vorige script wordt verwijderd"
Info "   Credential Guard krijgt weer de standaardinstelling van Windows"
if ($VmxPath) { Info "6. vhv.enable = FALSE in $VmxPath" }

if (-not $Apply) {
    Write-Host ""
    Write-Host "Er is niets veranderd. Start opnieuw met -Apply om dit uit te voeren." -ForegroundColor Cyan
    Stop-Transcript | Out-Null
    exit 0
}

# =====================================================================
Title "Terugzetten"

# 0. BitLocker 1 herstart pauzeren (wijzigingen aan VBS/Secure Launch vragen anders vaak de herstelsleutel)
$bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
if ($bl -and $bl.ProtectionStatus -eq 'On') {
    Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 | Out-Null
    Ok "BitLocker gepauzeerd voor 1 herstart."
}

# 1. Hyper-V-hypervisor weer laden
bcdedit /set hypervisorlaunchtype auto | Out-Null
Ok "bcdedit /set hypervisorlaunchtype auto"

# 2. Windows-onderdelen weer aan
$onderdelen = @('VirtualMachinePlatform')
if ($HyperV -and -not $isHome) { $onderdelen += 'Microsoft-Hyper-V-All', 'Containers-DisposableClientVM' }
foreach ($f in $onderdelen) {
    $st = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
    if (-not $st) { Info "$f : niet aanwezig op deze editie" }
    elseif ($st.State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Ok "$f aangezet"
    } else { Ok "$f stond al aan" }
}

# 3. Geheugenintegriteit aan (zelfde waarden als de schakelaar in Windows-beveiliging)
Zet-Waarde $DG 'EnableVirtualizationBasedSecurity' 1
Zet-Waarde $DG 'RequirePlatformSecurityFeatures' 1
Zet-Waarde $HVCI 'Enabled' 1
Ok "Geheugenintegriteit aan"

# 4. Firmwarebeveiliging (System Guard Secure Launch) aan
Zet-Waarde $SGL 'Enabled' 1
Ok "Firmwarebeveiliging aan (werkt enkel als de laptop het ondersteunt)"

# 5. Het groepsbeleid dat VBS uitzette verwijderen, Credential Guard terug naar standaard
Wis-Waarde $POL 'EnableVirtualizationBasedSecurity'
Wis-Waarde $POL 'LsaCfgFlags'
Wis-Waarde $LSA 'LsaCfgFlags'
Ok "Beleid voor VBS en Credential Guard terug naar de standaard van Windows"

# 6. Optioneel: nested VT-x uit in de VMware-VM
if ($VmxPath) {
    if (-not (Test-Path $VmxPath)) { Bad "VMX-bestand niet gevonden: $VmxPath" }
    elseif (Get-Process vmware-vmx -ErrorAction SilentlyContinue) { Bad "Een VM draait nog: sluit VMware af en voer -VmxPath opnieuw uit." }
    else {
        Copy-Item $VmxPath "$VmxPath.bak" -Force
        $lines = Get-Content $VmxPath | Where-Object { $_ -notmatch '^\s*vhv\.enable\s*=' }
        $lines += 'vhv.enable = "FALSE"'
        Set-Content -Path $VmxPath -Value $lines -Encoding ASCII
        Ok "vhv.enable = FALSE gezet in $VmxPath (backup: .bak)"
    }
}

Write-Host ""
Write-Host "Klaar. HERSTART de computer nu." -ForegroundColor Cyan
Write-Host "Controleer daarna met nestedvirtualization.ps1 (zonder -Apply): je ziet dan" -ForegroundColor Cyan
Write-Host "'Er draait nu een Windows-hypervisor' en 'VBS-status nu: DRAAIT'. Dat is nu de bedoeling." -ForegroundColor Cyan
Write-Host "Start een VMware-VM met het vinkje voor VT-x nog aan, dan meldt VMware dat dit niet ondersteund is." -ForegroundColor Cyan
Write-Host "Log: $log"
Stop-Transcript | Out-Null
