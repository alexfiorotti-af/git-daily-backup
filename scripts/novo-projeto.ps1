# =============================================================================
#  novo-projeto.ps1 - da a uma pasta o seu PROPRIO repositorio no GitHub
#  (em vez de ficar dentro do af-projetos). Use quando um projeto virar
#  codigo de verdade, for ter deploy, ou for ser compartilhado com socio.
#
#  Uso:
#    powershell -ExecutionPolicy Bypass -File .\novo-projeto.ps1 `
#       -Pasta "C:\Users\alexf\Documents\CLAUDE\Projects\Marcel - IA\pousa-hoteis" `
#       -Nome pousa-hoteis -Modo snapshot
#
#  -Modo direto   : commit + envio direto na main (documentos, sem deploy)
#  -Modo snapshot : codigo; backup vai para a branch backup/auto e a main
#                   so e enviada por voce (evita publicar site pela metade)
# =============================================================================
param(
    [Parameter(Mandatory = $true)][string]$Pasta,
    [Parameter(Mandatory = $true)][string]$Nome,
    [ValidateSet('direto', 'snapshot')][string]$Modo = 'snapshot',
    [string]$Descricao = ''
)

. (Join-Path $PSScriptRoot 'lib.ps1')

if (-not (Test-Path -LiteralPath $Pasta)) { Write-Host "Pasta nao existe: $Pasta" -ForegroundColor Red; exit 1 }
if ($Nome -notmatch '^[a-z0-9][a-z0-9\-\.]*$') { Write-Host 'Nome do repositorio: so letras minusculas, numeros, ponto e hifen (ex.: pousa-hoteis).' -ForegroundColor Red; exit 1 }
$Pasta = (Resolve-Path -LiteralPath $Pasta).Path

$cfg = Read-Config
if (@($cfg.repos | Where-Object { $_.nome -eq $Nome }).Count -gt 0) { Write-Host "Ja existe um repositorio chamado '$Nome' no repos.json." -ForegroundColor Red; exit 1 }
if (@($cfg.repos | Where-Object { $_.caminho -eq $Pasta }).Count -gt 0) { Write-Host 'Essa pasta ja esta no repos.json.' -ForegroundColor Red; exit 1 }

$novo = [pscustomobject]@{ nome = $Nome; caminho = $Pasta; modo = $Modo; descricao = $Descricao }
$cfg.repos = @($cfg.repos) + $novo
Save-Config $cfg
Write-Host "[OK] '$Nome' adicionado ao repos.json" -ForegroundColor Green

& (Join-Path $script:SistemaDir '02-criar-repos.ps1') -Somente $Nome
Write-Host ''
Write-Host 'Obs.: se essa pasta estava dentro de Projects, o af-projetos deixa de acompanha-la no proximo backup (o historico antigo continua la).' -ForegroundColor DarkGray
