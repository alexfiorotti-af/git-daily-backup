# =============================================================================
#  02-criar-repos.ps1 - transforma cada pasta do repos.json em repositorio
#  e liga ao GitHub (privado). Mostra uma previa e pede confirmacao antes
#  do primeiro envio de cada um.
#
#  Uso:  powershell -ExecutionPolicy Bypass -File .\02-criar-repos.ps1
#        ... -Somente mapa-app          (so um)
#        ... -Sim                       (nao pergunta; use com cuidado)
# =============================================================================
param([string]$Somente = '', [switch]$Sim)

. (Join-Path $PSScriptRoot 'lib.ps1')
$script:GitExe = Get-GitExe
if (-not $script:GitExe) { Write-Host 'Git nao encontrado. Rode 01-preparar.ps1 primeiro.' -ForegroundColor Red; exit 1 }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Host 'GitHub CLI nao encontrado. Rode 01-preparar.ps1 primeiro.' -ForegroundColor Red; exit 1 }

function GhOk([string[]]$A) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & gh @A 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    return [pscustomobject]@{ Ok = ($code -eq 0); Text = $out.Trim() }
}

if (-not (GhOk @('auth', 'status')).Ok) { Write-Host 'GitHub CLI sem login. Rode 01-preparar.ps1.' -ForegroundColor Red; exit 1 }

$cfg = Read-Config
$usuario = Get-Prop $cfg 'githubUsuario' ''
if (-not $usuario) { Write-Host 'Preencha "githubUsuario" no repos.json.' -ForegroundColor Red; exit 1 }
$limite = [long]([double](Get-Prop $cfg 'limiteMB' 45) * 1MB)
$lista = @($cfg.repos)
if ($Somente) { $lista = @($lista | Where-Object { $_.nome -eq $Somente }) }

foreach ($r in $lista) {
    Write-Host ''
    Write-Host ("==== {0}  ({1})" -f $r.nome, $r.caminho) -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $r.caminho)) { Write-Host '  pasta nao existe - pulando' -ForegroundColor Yellow; continue }
    $mono = [bool](Get-Prop $r 'monorepo' $false)
    $modo = Get-Prop $r 'modo' 'direto'

    # 1. git init + .gitignore
    if (-not (Test-Path -LiteralPath (Join-Path $r.caminho '.git'))) {
        GitRun $r.caminho @('init', '-b', 'main') | Out-Null
        Write-Host '  repositorio criado (git init)'
    }
    $gi = Join-Path $r.caminho '.gitignore'
    $modelo = Get-Prop $r 'gitignore' 'default'
    $origemGi = Join-Path (Join-Path $script:SistemaDir 'gitignore-templates') ("{0}.gitignore" -f $modelo)
    if (-not (Test-Path -LiteralPath $gi) -and (Test-Path -LiteralPath $origemGi)) {
        Copy-Item -LiteralPath $origemGi -Destination $gi
        Write-Host "  .gitignore '$modelo' copiado"
    }

    # 2. primeiro commit (se ainda nao tem nenhum)
    $temHead = (GitOut $r.caminho @('rev-parse', '--verify', '-q', 'HEAD')).Code -eq 0
    if (-not $temHead) {
        $pv = Get-Previa $r.caminho $limite $mono
        Write-Host ("  Previa: {0} arquivo(s), ~{1} MB vao para o GitHub." -f $pv.Entram, $pv.MB)
        if ($pv.Barrados.Count -gt 0) {
            Write-Host ("  {0} arquivo(s) serao BARRADOS (ficam so no disco):" -f $pv.Barrados.Count) -ForegroundColor Yellow
            $pv.Barrados | Select-Object -First 25 | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
        }
        if (-not $Sim) {
            $resp = Read-Host '  Criar o primeiro commit e enviar? (S/N)'
            if ($resp -notmatch '^[sSyY]') { Write-Host '  pulado.'; continue }
        }
        $res = New-Resultado $r.nome $r.caminho 'direto'
        Sync-Direto $r.caminho $limite $res $mono
        if ($res.Status -eq 'ERRO') { Write-Host "  ERRO: $($res.Erro)" -ForegroundColor Red; continue }
        Write-Host ("  primeiro commit: {0} ({1} arquivos)" -f $res.Commit, $res.Arquivos.Count) -ForegroundColor Green
    }

    # 3. remoto no GitHub
    $remoto = (GitOut $r.caminho @('remote', 'get-url', 'origin')).Text
    if (-not $remoto) {
        $fixo = Get-Prop $r 'remoto' ''
        $alvo = "$usuario/$($r.nome)"
        if ($fixo) {
            GitRun $r.caminho @('remote', 'add', 'origin', $fixo) | Out-Null
        } elseif ((GhOk @('repo', 'view', $alvo)).Ok) {
            Write-Host "  $alvo ja existe no GitHub - ligando a pasta a ele"
            GitRun $r.caminho @('remote', 'add', 'origin', "https://github.com/$alvo.git") | Out-Null
        } else {
            $argsGh = @('repo', 'create', $alvo, '--private', '--source', $r.caminho, '--remote', 'origin')
            $desc = Get-Prop $r 'descricao' ''
            if ($desc) { $argsGh += @('--description', $desc) }
            $c = GhOk $argsGh
            if (-not $c.Ok) { Write-Host "  ERRO criando no GitHub: $($c.Text)" -ForegroundColor Red; continue }
            Write-Host "  criado no GitHub (privado): https://github.com/$alvo" -ForegroundColor Green
        }
        $branch = (GitOut $r.caminho @('rev-parse', '--abbrev-ref', 'HEAD')).Text
        $p = GitRun $r.caminho @('push', '-u', 'origin', $branch)
        if ($p.Code -ne 0) { Write-Host "  ERRO no envio: $($p.Text)" -ForegroundColor Red; continue }
        Write-Host "  branch '$branch' enviada" -ForegroundColor Green
    } else {
        Write-Host "  ja ligado ao GitHub: $remoto" -ForegroundColor Green
    }

    # 4. snapshot inicial do que esta fora de commit (repos de codigo)
    if ($modo -eq 'snapshot') {
        $res = New-Resultado $r.nome $r.caminho 'snapshot'
        Sync-Snapshot $r.caminho $limite $res
        Write-Host ("  backup do trabalho em andamento: {0} | envio: {1} {2}" -f $res.Status, $res.Envio, $res.Erro)
        foreach ($a in $res.Alertas) { Write-Host "    $a" -ForegroundColor Yellow }
        foreach ($a in $res.Avisos)  { Write-Host "    $a" -ForegroundColor DarkGray }
    }
}

Write-Host ''
Write-Host 'Terminado. Confira com 00-diagnostico.ps1 e depois rode 03-agendar.ps1.' -ForegroundColor Cyan
Write-Host ''
