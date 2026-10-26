# =============================================================================
#  00-diagnostico.ps1 - confere se o computador esta pronto. NAO muda nada.
#  Uso: clique direito na pasta _sistema > "Abrir no Terminal" e rode:
#       powershell -ExecutionPolicy Bypass -File .\00-diagnostico.ps1
# =============================================================================
. (Join-Path $PSScriptRoot 'lib.ps1')

$ok = 0; $falta = 0
function Item([bool]$Passou, [string]$Texto, [string]$ComoResolver = '') {
    if ($Passou) { Write-Host "  [OK]    $Texto" -ForegroundColor Green; $script:ok++ }
    else {
        Write-Host "  [FALTA] $Texto" -ForegroundColor Yellow
        if ($ComoResolver) { Write-Host "          -> $ComoResolver" -ForegroundColor DarkGray }
        $script:falta++
    }
}

Write-Host ''
Write-Host '=== Diagnostico do sistema de backup (nada sera alterado) ===' -ForegroundColor Cyan
Write-Host ''

$script:GitExe = Get-GitExe
Item ([bool]$script:GitExe) 'Git instalado' 'rode 01-preparar.ps1'
if ($script:GitExe) {
    $v = (& $script:GitExe --version) 2>$null
    Write-Host "          $v" -ForegroundColor DarkGray
    $nome  = (& $script:GitExe config --global user.name) 2>$null
    $email = (& $script:GitExe config --global user.email) 2>$null
    Item ([bool]$nome -and [bool]$email) "Identidade do Git ($nome <$email>)" 'rode 01-preparar.ps1'
    $cred = (& $script:GitExe config --get credential.helper) 2>$null
    Item ([bool]$cred) "Gerenciador de credenciais do Git ($cred)" 'reinstale o Git pelo 01-preparar.ps1'
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
Item ([bool]$gh) 'GitHub CLI (gh) instalado' 'rode 01-preparar.ps1'
if ($gh) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $st = & gh auth status 2>&1 | Out-String
    $logado = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $old
    Item $logado 'GitHub CLI conectado a sua conta' 'rode 01-preparar.ps1 (vai abrir o navegador para login)'
    if ($logado -and ($st -match 'account (\S+)')) { Write-Host "          conta: $($Matches[1])" -ForegroundColor DarkGray }
}

$gl = Get-Command gitleaks -ErrorAction SilentlyContinue
if ($gl) { Write-Host '  [OK]    Gitleaks instalado (usado pelo ORDO)' -ForegroundColor Green } else { Write-Host '  [info]  Gitleaks nao encontrado (opcional; o ORDO usa no GitHub Actions)' -ForegroundColor DarkGray }

$drive = (Test-Path "$env:ProgramFiles\Google\Drive File Stream") -or (Get-Process -Name 'GoogleDriveFS' -ErrorAction SilentlyContinue)
Item ([bool]$drive) 'Google Drive para computador (copia das midias pesadas)' 'baixe em https://www.google.com/drive/download/ (passo 6 do COMECE-AQUI)'

Write-Host ''
Write-Host '--- Repositorios configurados (repos.json) ---' -ForegroundColor Cyan
try {
    $cfg = Read-Config
    foreach ($r in $cfg.repos) {
        $existe = Test-Path -LiteralPath $r.caminho
        $ehRepo = Test-Path -LiteralPath (Join-Path $r.caminho '.git')
        $remoto = ''
        if ($ehRepo -and $script:GitExe) { $remoto = (GitOut $r.caminho @('remote', 'get-url', 'origin')).Text }
        $txt = '{0,-14} {1}' -f $r.nome, $r.caminho
        if (-not $existe)      { Item $false $txt 'a pasta nao existe - confira o caminho em repos.json' }
        elseif (-not $ehRepo)  { Item $false "$txt  (ainda nao e repositorio)" 'rode 02-criar-repos.ps1' }
        elseif (-not $remoto)  { Item $false "$txt  (SEM GitHub)" 'rode 02-criar-repos.ps1' }
        else                   { Item $true  "$txt  -> $remoto" }
    }
} catch { Write-Host "  Erro lendo repos.json: $_" -ForegroundColor Red }

Write-Host ''
$tarefa = $null
try { $tarefa = Get-ScheduledTask -TaskName 'Git Daily Backup' -ErrorAction Stop } catch { }
Item ([bool]$tarefa) 'Tarefa agendada do backup diario' 'rode 03-agendar.ps1'
if ($tarefa) {
    $info = $tarefa | Get-ScheduledTaskInfo
    Write-Host ("          ultima execucao: {0}  resultado: {1}  proxima: {2}" -f $info.LastRunTime, $info.LastTaskResult, $info.NextRunTime) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host ("Resultado: {0} ok, {1} pendente(s)." -f $ok, $falta) -ForegroundColor Cyan
if ($falta -gt 0) { Write-Host 'Siga o COMECE-AQUI.md na ordem; os pendentes somem conforme os passos.' }
Write-Host ''
