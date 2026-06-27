<#
###############################################################################
 wsl-portproxy.ps1 — expõe as portas do nginx (WSL2) para a LAN / internet

 No WSL2 o Docker roda numa VM com IP interno. Para que outros dispositivos
 da sua rede (ou o roteador, via port forward) alcancem o nginx, o Windows
 precisa redirecionar as portas 80/443 para o IP do WSL.

 Este script:
   1. Descobre o IP atual do WSL
   2. Cria as regras netsh portproxy (80 e 443)
   3. Abre as portas no Firewall do Windows

 EXECUTE COMO ADMINISTRADOR (PowerShell > "Executar como administrador"):
   Set-ExecutionPolicy -Scope Process Bypass
   .\scripts\wsl-portproxy.ps1

 Para REMOVER tudo depois:
   .\scripts\wsl-portproxy.ps1 -Remove

 OBS: o IP do WSL muda a cada reboot. Rode de novo após reiniciar, ou use o
 Cloudflare Tunnel/ngrok (não dependem de port forward).
###############################################################################
#>

param(
    [switch]$Remove,
    [int[]]$Ports = @(80, 443)
)

$ErrorActionPreference = "Stop"

# Requer privilégios de administrador
$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Error "Rode este script como Administrador."; exit 1 }

if ($Remove) {
    foreach ($p in $Ports) {
        netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 2>$null
        Remove-NetFirewallRule -DisplayName "WSL nginx $p" -ErrorAction SilentlyContinue
    }
    Write-Host "Regras de portproxy e firewall removidas." -ForegroundColor Green
    netsh interface portproxy show all
    exit 0
}

# Descobre o IP do WSL
$wslIp = (wsl hostname -I).Trim().Split(" ")[0]
if (-not $wslIp) { Write-Error "Não foi possível obter o IP do WSL. O WSL está rodando?"; exit 1 }
Write-Host "IP do WSL detectado: $wslIp" -ForegroundColor Cyan

foreach ($p in $Ports) {
    # Remove regra antiga (se houver) e recria apontando para o IP atual
    netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 2>$null
    netsh interface portproxy add v4tov4 `
        listenport=$p listenaddress=0.0.0.0 `
        connectport=$p connectaddress=$wslIp

    # Libera no firewall
    Remove-NetFirewallRule -DisplayName "WSL nginx $p" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "WSL nginx $p" -Direction Inbound `
        -Action Allow -Protocol TCP -LocalPort $p | Out-Null

    Write-Host ("Porta {0} -> {1}:{0}  (firewall liberado)" -f $p, $wslIp) -ForegroundColor Green
}

Write-Host "`nRegras ativas:" -ForegroundColor Cyan
netsh interface portproxy show all

Write-Host "`nPróximos passos:" -ForegroundColor Yellow
Write-Host " - Teste na LAN:  https://<IP-do-Windows>"
Write-Host " - Para internet: configure port forward no roteador 80/443 -> IP do Windows"
Write-Host " - Alternativa sem mexer no roteador: use Cloudflare Tunnel ou ngrok."
