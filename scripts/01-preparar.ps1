# =============================================================================
#  01-preparar.ps1 - instala e configura o que falta (Git, GitHub CLI, login)
#  Uso: powershell -ExecutionPolicy Bypass -File .\01-preparar.ps1
#  Pode rodar quantas vezes quiser: o que ja esta pronto e pulado.
# =============================================================================
. (Join-Path $PSScriptRoot 'lib.ps1')

function Atualizar-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u"
}

function Instalar([string]$Id, [string]$Nome) {
    Write-Host "Instalando $Nome (pode pedir permissao do Windows)..." -ForegroundColor Cyan
    winget install -e --id $Id --accept-source-agreements --accept-package-agreements
    Atualizar-Path
}

Write-Host ''
Write-Host '=== Preparando o computador ===' -ForegroundColor Cyan

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'O winget (instalador do Windows) nao foi encontrado. Atualize o "Instalador de Aplicativo" pela Microsoft Store e rode de novo.' -ForegroundColor Red
    exit 1
}

# 1. Git
if (-not (Get-GitExe)) { Instalar 'Git.Git' 'Git' } else { Write-Host '[OK] Git ja instalado' -ForegroundColor Green }
$script:GitExe = Get-GitExe
if (-not $script:GitExe) { Write-Host 'Git ainda nao aparece. Feche e abra o terminal e rode este script de novo.' -ForegroundColor Red; exit 1 }

# 2. GitHub CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Instalar 'GitHub.cli' 'GitHub CLI' } else { Write-Host '[OK] GitHub CLI ja instalado' -ForegroundColor Green }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Host 'GitHub CLI ainda nao aparece. Feche e abra o terminal e rode de novo.' -ForegroundColor Red; exit 1 }

# 3. Configuracao do Git (so preenche o que estiver vazio)
function Set-SeVazio([string]$Chave, [string]$Valor) {
    $atual = (& $script:GitExe config --global $Chave) 2>$null
    if (-not $atual) { & $script:GitExe config --global $Chave $Valor; Write-Host "   git config $Chave = $Valor" }
}
$nomeAtual = (& $script:GitExe config --global user.name) 2>$null
if (-not $nomeAtual) { Set-SeVazio 'user.name' (Read-Host 'Seu nome para os commits (ex.: Maria Silva)') }
$emailAtual = (& $script:GitExe config --global user.email) 2>$null
if (-not $emailAtual) { Set-SeVazio 'user.email' (Read-Host 'Seu e-mail do GitHub') }
Set-SeVazio 'init.defaultBranch' 'main'
& $script:GitExe config --global core.quotepath false
& $script:GitExe config --global core.longpaths true
Write-Host '[OK] Git configurado' -ForegroundColor Green

# 4. Login no GitHub (abre o navegador uma vez; depois fica salvo)
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& gh auth status 2>&1 | Out-Null
$logado = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $old
if (-not $logado) {
    Write-Host ''
    Write-Host 'Agora vamos conectar ao GitHub. Vai aparecer um codigo de 8 letras:' -ForegroundColor Cyan
    Write-Host 'copie o codigo, aperte Enter, o navegador abre, cole o codigo e autorize.' -ForegroundColor Cyan
    & gh auth login --hostname github.com --git-protocol https --web
}
& gh auth setup-git
Write-Host '[OK] GitHub conectado' -ForegroundColor Green

Write-Host ''
Write-Host 'Pronto. Proximo passo: 02-criar-repos.ps1' -ForegroundColor Cyan
Write-Host ''
