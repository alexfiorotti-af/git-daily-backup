# =============================================================================
#  lib.ps1 - funcoes compartilhadas do git-daily-backup
#  Compativel com Windows PowerShell 5.1 e PowerShell 7+.
#  Nao rode este arquivo sozinho: ele e carregado pelos outros scripts.
# =============================================================================

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8

$script:SistemaDir  = $PSScriptRoot
$script:CofreDir    = Split-Path -Parent $PSScriptRoot
$script:ConfigPath  = Join-Path $PSScriptRoot 'repos.json'
$script:LogDir      = Join-Path $PSScriptRoot 'logs'
$script:Utf8SemBom  = New-Object System.Text.UTF8Encoding($false)
$script:EhWindows   = ($env:OS -eq 'Windows_NT')

# ---------------------------------------------------------------------------
#  Regras de seguranca: o que NUNCA sobe para o GitHub
# ---------------------------------------------------------------------------

# Nome de arquivo que indica segredo (verificado em minusculas).
$script:RegexNomeProibido = '(^\.env$)|(^\.env\.)|(\.env$)|(\.pem$)|(\.key$)|(\.pfx$)|(\.p12$)|(\.keystore$)|(\.kdbx$)|(^id_(rsa|ed25519|ecdsa|dsa))|(credential.*\.json$)|(service.?account.*\.json$)|((senha|senhas|password|passwords|credenciais|credentials|login|acesso|acessos|token|tokens|bitwarden|lastpass|1password).*\.(txt|docx?|xlsx?|csv|pdf|rtf|odt|json)$)'
# Excecoes: modelos de .env sem valores reais.
$script:RegexNomePermitido = '(\.(example|exemplo|sample|modelo|template)$)'

# Conteudo que indica chave/token real. Nomes aparecem no aviso.
$script:PadroesSegredo = @(
    @{ Nome = 'chave Anthropic';        Regex = 'sk-ant-[A-Za-z0-9_\-]{20,}' },
    @{ Nome = 'chave OpenAI';           Regex = 'sk-(proj-)?[A-Za-z0-9]{32,}' },
    @{ Nome = 'token GitHub';           Regex = '(gh[pousr]_[A-Za-z0-9]{36})|(github_pat_[A-Za-z0-9_]{50,})' },
    @{ Nome = 'chave AWS';              Regex = 'AKIA[0-9A-Z]{16}' },
    @{ Nome = 'chave privada';          Regex = '-----BEGIN ((RSA|EC|OPENSSH|DSA|ENCRYPTED) )?PRIVATE KEY-----' },
    @{ Nome = 'token Slack';            Regex = 'xox[baprs]-[A-Za-z0-9\-]{10,}' },
    @{ Nome = 'token Meta/Facebook';    Regex = 'EAA[A-Za-z0-9]{80,}' },
    @{ Nome = 'chave Asaas';            Regex = '\$aact_[A-Za-z0-9_]{20,}' },
    @{ Nome = 'token Mercado Pago';     Regex = 'APP_USR-\d{12,}-\d{6}-[0-9a-f]{32}-\d{6,}' },
    @{ Nome = 'chave Stripe';           Regex = '(sk|rk)_live_[0-9A-Za-z]{20,}' },
    @{ Nome = 'chave Resend';           Regex = 're_[A-Za-z0-9]{8,}_[A-Za-z0-9]{16,}' },
    @{ Nome = 'URL de banco com senha'; Regex = '(postgres(ql)?|mysql|mongodb(\+srv)?)://[^:\s/"''@]+:(?!senha@|password@|pass@|SENHA@|PASSWORD@|\$\{|<|\*|xxx)[^@\s"'']+@(?!localhost|127\.0\.0\.1|db[:/]|postgres[:/]|mysql[:/])[A-Za-z0-9]' }
)

# Extensoes que nao sao lidas por dentro (binarias).
$script:ExtBinarias = @('.png','.jpg','.jpeg','.gif','.webp','.ico','.bmp','.tif','.tiff','.heic',
    '.pdf','.docx','.doc','.xlsx','.xls','.pptx','.ppt','.odt','.ods',
    '.woff','.woff2','.ttf','.otf','.eot',
    '.mp4','.mov','.avi','.mkv','.webm','.mp3','.wav','.flac','.m4a','.aac','.ogg',
    '.zip','.rar','.7z','.gz','.tgz','.tar','.bin','.exe','.dll','.msi','.psd','.ai','.eps','.sketch','.fig')

# Pastas que nunca sao percorridas na busca por repositorios aninhados.
$script:PastasIgnoradasBusca = @('node_modules','.git','.next','.venv','venv','__pycache__','dist','build','.vercel','.turbo','.cache')

# ---------------------------------------------------------------------------
#  Utilidades
# ---------------------------------------------------------------------------

function Get-GitExe {
    $c = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Path }
    $candidatos = @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )
    foreach ($p in $candidatos) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return $null
}

function Get-Prop {
    param($Obj, [string]$Nome, $Padrao = $null)
    $p = $Obj.PSObject.Properties[$Nome]
    if ($null -eq $p -or $null -eq $p.Value) { return $Padrao }
    return $p.Value
}

# Roda git e devolve stdout (stderr descartado). Use para LER informacao.
function GitOut {
    param([string]$Repo, [string[]]$A)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $script:GitExe -C $Repo -c core.quotepath=false @A 2>$null
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    $linhas = @()
    if ($null -ne $out) { $linhas = @($out | ForEach-Object { "$_" }) }
    return [pscustomobject]@{ Code = $code; Out = $linhas; Text = ($linhas -join "`n").Trim() }
}

# Roda git e devolve stdout+stderr juntos. Use para EXECUTAR e registrar.
function GitRun {
    param([string]$Repo, [string[]]$A)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $script:GitExe -C $Repo -c core.quotepath=false @A 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    $linhas = @()
    if ($null -ne $out) { $linhas = @($out | ForEach-Object { "$_" }) }
    return [pscustomobject]@{ Code = $code; Out = $linhas; Text = ($linhas -join "`n").Trim() }
}

# Saida de git com -z vira lista de caminhos.
function Split-Nul {
    param([string[]]$Linhas)
    $junto = ($Linhas -join "`n")
    return @($junto -split "`0" | ForEach-Object { $_.Trim("`n") } | Where-Object { $_ -ne '' })
}

function Write-Utf8 {
    param([string]$Caminho, [string]$Texto)
    [System.IO.File]::WriteAllText($Caminho, $Texto, $script:Utf8SemBom)
}

function Write-Log {
    param([string]$Msg, [string]$Nivel = 'INFO')
    $linha = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Msg
    if (-not (Test-Path -LiteralPath $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null }
    $arq = Join-Path $script:LogDir ('sync-{0}.log' -f (Get-Date -Format 'yyyy-MM'))
    [System.IO.File]::AppendAllText($arq, $linha + [Environment]::NewLine, $script:Utf8SemBom)
    $cor = 'Gray'
    if ($Nivel -eq 'ERRO') { $cor = 'Red' } elseif ($Nivel -eq 'ALERTA') { $cor = 'Yellow' } elseif ($Nivel -eq 'OK') { $cor = 'Green' }
    Write-Host $linha -ForegroundColor $cor
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { throw "Nao achei $($script:ConfigPath)" }
    $txt = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.Encoding]::UTF8)
    $cfg = $txt | ConvertFrom-Json
    foreach ($r in $cfg.repos) {
        $r.caminho = [Environment]::ExpandEnvironmentVariables([string]$r.caminho)
    }
    return $cfg
}

function Save-Config {
    param($Cfg)
    # Grava de volta mantendo %USERPROFILE% no lugar do caminho real.
    $perfil = $env:USERPROFILE
    $copia = $Cfg | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    foreach ($r in $copia.repos) {
        if ($perfil -and ([string]$r.caminho).StartsWith($perfil, [System.StringComparison]::OrdinalIgnoreCase)) {
            $r.caminho = '%USERPROFILE%' + ([string]$r.caminho).Substring($perfil.Length)
        }
    }
    Write-Utf8 $script:ConfigPath ($copia | ConvertTo-Json -Depth 6)
}

# ---------------------------------------------------------------------------
#  Verificacao de um arquivo antes de subir. Devolve $null se estiver OK,
#  ou o motivo do bloqueio.
# ---------------------------------------------------------------------------
function Test-Arquivo {
    param([string]$Repo, [string]$Rel, [long]$LimiteBytes)
    $full = Join-Path $Repo $Rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    $fi = Get-Item -LiteralPath $full -Force
    if ($fi.Length -gt $LimiteBytes) { return ('arquivo grande ({0:N1} MB)' -f ($fi.Length / 1MB)) }
    $nome = $fi.Name.ToLowerInvariant()
    if (($nome -match $script:RegexNomeProibido) -and ($nome -notmatch $script:RegexNomePermitido)) {
        return 'nome indica senha/credencial'
    }
    $ext = $fi.Extension.ToLowerInvariant()
    if (($fi.Length -gt 0) -and ($fi.Length -lt 2MB) -and ($script:ExtBinarias -notcontains $ext)) {
        try { $txt = [System.IO.File]::ReadAllText($full) } catch { return $null }
        foreach ($p in $script:PadroesSegredo) {
            if ($txt -cmatch $p.Regex) { return ('possivel segredo no conteudo: ' + $p.Nome) }
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
#  Exclusoes automaticas (.git/info/exclude): repositorios aninhados +
#  arquivos barrados em execucoes anteriores.
# ---------------------------------------------------------------------------
function ConvertTo-GitPattern {
    param([string]$Rel)
    $p = $Rel -replace '\\', '/'
    $p = $p -replace '([\[\]\*\?])', '\$1'
    if ($p.StartsWith('#') -or $p.StartsWith('!')) { $p = '\' + $p }
    return '/' + $p
}

function Find-ReposAninhados {
    param([string]$Raiz, [int]$Profundidade = 5)
    $achados = New-Object System.Collections.Generic.List[string]
    $fila = New-Object System.Collections.Generic.Queue[object]
    $fila.Enqueue(@($Raiz, 0))
    while ($fila.Count -gt 0) {
        $item = $fila.Dequeue(); $dir = $item[0]; $nivel = $item[1]
        $subs = @()
        try { $subs = @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction Stop) } catch { continue }
        foreach ($s in $subs) {
            if ($script:PastasIgnoradasBusca -contains $s.Name) { continue }
            if (Test-Path -LiteralPath (Join-Path $s.FullName '.git')) {
                $rel = $s.FullName.Substring($Raiz.TrimEnd('\','/').Length).TrimStart('\','/')
                $achados.Add($rel)
                continue
            }
            if ($nivel + 1 -lt $Profundidade) { $fila.Enqueue(@($s.FullName, ($nivel + 1))) }
        }
    }
    return @($achados)
}

function Get-GitDir {
    param([string]$Repo)
    $r = GitOut $Repo @('rev-parse', '--absolute-git-dir')
    if ($r.Code -ne 0) { return $null }
    return $r.Out[0]
}

function Get-Bloqueados {
    param([string]$GitDir)
    $arq = Join-Path $GitDir 'af-bloqueados.txt'
    if (-not (Test-Path -LiteralPath $arq)) { return @() }
    return @([System.IO.File]::ReadAllLines($arq, [System.Text.Encoding]::UTF8) | Where-Object { $_.Trim() -ne '' })
}

function Add-Bloqueado {
    param([string]$GitDir, [string]$Rel)
    $atuais = Get-Bloqueados $GitDir
    if ($atuais -contains $Rel) { return }
    $arq = Join-Path $GitDir 'af-bloqueados.txt'
    [System.IO.File]::AppendAllText($arq, $Rel + "`n", $script:Utf8SemBom)
}

function Update-Exclude {
    param([string]$Repo, [bool]$Monorepo, $Resultado)
    $gitDir = Get-GitDir $Repo
    if (-not $gitDir) { return }
    $infoDir = Join-Path $gitDir 'info'
    if (-not (Test-Path -LiteralPath $infoDir)) { New-Item -ItemType Directory -Path $infoDir -Force | Out-Null }
    $arq = Join-Path $infoDir 'exclude'
    $atual = ''
    if (Test-Path -LiteralPath $arq) { $atual = [System.IO.File]::ReadAllText($arq, [System.Text.Encoding]::UTF8) }
    $inicio = '# >>> af-sync (gerado automaticamente - nao edite entre estas linhas)'
    $fim    = '# <<< af-sync'
    $semBloco = [regex]::Replace($atual, '(?s)' + [regex]::Escape($inicio) + '.*?' + [regex]::Escape($fim) + '\r?\n?', '')

    $linhas = New-Object System.Collections.Generic.List[string]
    $linhas.Add($inicio)
    if ($Monorepo) {
        $linhas.Add('# repositorios proprios dentro desta pasta (cada um tem backup separado)')
        foreach ($rel in (Find-ReposAninhados $Repo)) {
            $linhas.Add((ConvertTo-GitPattern $rel) + '/')
            # Se a pasta ja era acompanhada aqui, para de acompanhar (arquivos continuam no disco).
            $rastreado = GitOut $Repo @('ls-files', '-z', '--', ($rel -replace '\\', '/'))
            if ((Split-Nul $rastreado.Out).Count -gt 0) {
                GitRun $Repo @('rm', '-r', '--cached', '-q', '--', ($rel -replace '\\', '/')) | Out-Null
                if ($Resultado) { $Resultado.Avisos.Add("'$rel' virou repositorio proprio e saiu deste backup") }
            }
        }
    }
    $bloq = Get-Bloqueados $gitDir
    if ($bloq.Count -gt 0) {
        $linhas.Add('# arquivos barrados pela verificacao de seguranca/tamanho')
        foreach ($b in $bloq) { $linhas.Add((ConvertTo-GitPattern $b)) }
    }
    $linhas.Add($fim)
    $novo = $semBloco.TrimEnd() + "`n`n" + ($linhas -join "`n") + "`n"
    Write-Utf8 $arq $novo.TrimStart()
}

# ---------------------------------------------------------------------------
#  Confere o que esta no indice (normal ou temporario) e tira o que nao pode.
# ---------------------------------------------------------------------------
function Invoke-Verificacao {
    param([string]$Repo, [long]$LimiteBytes, [bool]$TemHead, [string]$ComparaCom, $Resultado, [bool]$Monorepo = $false)
    $gitDir = Get-GitDir $Repo
    $a = @('diff', '--cached', '--name-only', '-z', '--diff-filter=ACMR')
    if ($ComparaCom) { $a += $ComparaCom }
    $lista = Split-Nul (GitOut $Repo $a).Out
    $barrados = 0
    foreach ($rel in $lista) {
        $motivo = Test-Arquivo $Repo $rel $LimiteBytes
        if ($motivo) {
            if ($TemHead) { GitRun $Repo @('reset', '-q', '--', $rel) | Out-Null }
            else          { GitRun $Repo @('rm', '--cached', '-q', '--', $rel) | Out-Null }
            Add-Bloqueado $gitDir $rel
            $Resultado.Alertas.Add("BARRADO: $rel -> $motivo")
            $barrados++
        }
    }
    if ($barrados -gt 0) { Update-Exclude $Repo $Monorepo $null }
    return $barrados
}

function New-Resultado {
    param([string]$Nome, [string]$Caminho, [string]$Modo)
    return [pscustomobject]@{
        Nome = $Nome; Caminho = $Caminho; Modo = $Modo
        Status = 'sem mudancas'; Arquivos = New-Object System.Collections.Generic.List[string]
        Commit = ''; Envio = '-'; Alertas = New-Object System.Collections.Generic.List[string]
        Avisos = New-Object System.Collections.Generic.List[string]; Erro = ''
    }
}

function Get-PastasTopo {
    param([string[]]$Arquivos)
    $pastas = @{}
    foreach ($linha in $Arquivos) {
        $caminho = ($linha -split "`t")[-1]
        $topo = ($caminho -split '/')[0]
        if ($caminho -notmatch '/') { $topo = '(raiz)' }
        $pastas[$topo] = $true
    }
    return @($pastas.Keys | Sort-Object)
}

# ---------------------------------------------------------------------------
#  MODO DIRETO: commit na branch atual + push. Para pastas de documentos
#  e para o proprio cofre (nada ligado a deploy).
# ---------------------------------------------------------------------------
function Sync-Direto {
    param($Repo, [long]$LimiteBytes, $Resultado, [bool]$Monorepo)
    $temHead = (GitOut $Repo @('rev-parse', '--verify', '-q', 'HEAD')).Code -eq 0
    Update-Exclude $Repo $Monorepo $Resultado

    $add = GitRun $Repo @('add', '-A')
    if ($add.Code -ne 0) { $Resultado.Status = 'ERRO'; $Resultado.Erro = "git add falhou: $($add.Text)"; return }

    Invoke-Verificacao $Repo $LimiteBytes $temHead $null $Resultado $Monorepo | Out-Null

    $mudancas = @((GitOut $Repo @('diff', '--cached', '--name-status')).Out | Where-Object { $_ -ne '' })
    if ($mudancas.Count -gt 0) {
        foreach ($m in $mudancas) { $Resultado.Arquivos.Add($m) }
        $msg = 'backup: {0} - {1} arquivo(s)' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $mudancas.Count
        if ($Monorepo) { $msg += ' - ' + ((Get-PastasTopo $mudancas) -join ', ') }
        $c = GitRun $Repo @('commit', '-q', '-m', $msg)
        if ($c.Code -ne 0) { $Resultado.Status = 'ERRO'; $Resultado.Erro = "commit falhou: $($c.Text)"; return }
        $Resultado.Commit = (GitOut $Repo @('rev-parse', '--short', 'HEAD')).Text
        $Resultado.Status = 'commit feito'
    }

    if ((GitOut $Repo @('remote', 'get-url', 'origin')).Code -ne 0) {
        if ($Resultado.Status -ne 'sem mudancas') { $Resultado.Envio = 'SEM REMOTO' }
        $Resultado.Alertas.Add('repositorio sem GitHub (origin) - o backup esta so no disco')
        return
    }
    $branch = (GitOut $Repo @('rev-parse', '--abbrev-ref', 'HEAD')).Text
    if ($branch -eq 'HEAD' -or $branch -eq '') { $Resultado.Alertas.Add('HEAD destacado - envio pulado'); return }
    $up = GitOut $Repo @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    $precisa = $true
    if ($up.Code -eq 0) {
        $ahead = (GitOut $Repo @('rev-list', '--count', '@{u}..HEAD')).Text
        $precisa = ([int]$ahead -gt 0)
    }
    if (-not $precisa) { if ($Resultado.Status -ne 'sem mudancas') { $Resultado.Envio = 'ok' }; return }
    $p = GitRun $Repo @('push', '-u', 'origin', $branch)
    if ($p.Code -eq 0) { $Resultado.Envio = 'ok'; if ($Resultado.Status -eq 'sem mudancas') { $Resultado.Status = 'envio pendente reenviado' } }
    else { $Resultado.Envio = 'FALHOU'; $Resultado.Erro = "push falhou: $($p.Text)" }
}

# ---------------------------------------------------------------------------
#  MODO SNAPSHOT: fotografa a pasta inteira (inclusive o que nao foi
#  commitado) e envia para a branch backup/auto. NAO mexe na main, no seu
#  indice nem nos seus arquivos. Nada e publicado em producao.
# ---------------------------------------------------------------------------
function Sync-Snapshot {
    param($Repo, [long]$LimiteBytes, $Resultado)
    $refLocal  = 'refs/af/backup'
    $refRemota = 'refs/remotes/origin/backup/auto'
    $gitDir = Get-GitDir $Repo
    if ((GitOut $Repo @('rev-parse', '--verify', '-q', 'HEAD')).Code -ne 0) {
        $Resultado.Status = 'ERRO'; $Resultado.Erro = 'repositorio sem nenhum commit - rode 02-criar-repos.ps1'; return
    }
    Update-Exclude $Repo $false $Resultado

    $idx = Join-Path $gitDir 'af-sync-index'
    $env:GIT_INDEX_FILE = $idx
    $tree = ''
    try {
        if (Test-Path -LiteralPath $idx) { Remove-Item -LiteralPath $idx -Force }
        $rt = GitRun $Repo @('read-tree', 'HEAD')
        if ($rt.Code -ne 0) { throw "read-tree falhou: $($rt.Text)" }
        $add = GitRun $Repo @('add', '-A')
        if ($add.Code -ne 0) { throw "git add falhou: $($add.Text)" }
        Invoke-Verificacao $Repo $LimiteBytes $true 'HEAD' $Resultado | Out-Null
        foreach ($m in @((GitOut $Repo @('diff', '--cached', '--name-status', 'HEAD')).Out | Where-Object { $_ -ne '' })) { $Resultado.Arquivos.Add($m) }
        $tree = (GitOut $Repo @('write-tree')).Text
    } catch {
        $Resultado.Status = 'ERRO'; $Resultado.Erro = "$_"
    } finally {
        Remove-Item Env:\GIT_INDEX_FILE -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $idx) { Remove-Item -LiteralPath $idx -Force -ErrorAction SilentlyContinue }
    }
    if ($Resultado.Status -eq 'ERRO') { return }

    # Commits na main que ainda nao foram para o GitHub: so avisa (push da main pode publicar o site).
    $ahead = 0
    $up = GitOut $Repo @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    if ($up.Code -eq 0) {
        $ahead = [int](GitOut $Repo @('rev-list', '--count', '@{u}..HEAD')).Text
        if ($ahead -gt 0) { $Resultado.Avisos.Add("$ahead commit(s) na branch principal ainda nao enviados (o envio da principal e manual: git push)") }
    } elseif ((GitOut $Repo @('remote', 'get-url', 'origin')).Code -eq 0) {
        $Resultado.Avisos.Add('branch principal sem upstream no GitHub')
    }

    $headTree = (GitOut $Repo @('rev-parse', 'HEAD^{tree}')).Text
    $ultimo   = GitOut $Repo @('rev-parse', '-q', '--verify', $refLocal)
    $temUltimo = ($ultimo.Code -eq 0)
    $ultimoTree = ''
    if ($temUltimo) { $ultimoTree = (GitOut $Repo @('rev-parse', ($refLocal + '^{tree}'))).Text }

    # Commits locais ainda nao enviados tambem precisam de copia: so pula se nao houver nenhum.
    if ($tree -eq $headTree -and $ahead -eq 0 -and ((-not $temUltimo) -or $ultimoTree -eq $tree)) {
        $Resultado.Arquivos.Clear()
    } elseif ($temUltimo -and $ultimoTree -eq $tree -and ((GitOut $Repo @('merge-base', '--is-ancestor', 'HEAD', $refLocal)).Code -eq 0)) {
        $Resultado.Status = 'sem mudancas desde o ultimo backup'
    } else {
        $headSha = (GitOut $Repo @('rev-parse', 'HEAD')).Text
        $a = @('commit-tree', $tree, '-p', $headSha)
        if ($temUltimo -and $ultimo.Text -ne $headSha) { $a += @('-p', $ultimo.Text) }
        $msg = 'backup automatico: {0} - {1} arquivo(s) fora de commit' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $Resultado.Arquivos.Count
        $a += @('-m', $msg)
        $ct = GitOut $Repo $a
        if ($ct.Code -ne 0 -or -not $ct.Text) { $Resultado.Status = 'ERRO'; $Resultado.Erro = 'commit-tree falhou (confira git config user.name/user.email)'; return }
        GitRun $Repo @('update-ref', $refLocal, $ct.Text) | Out-Null
        $Resultado.Commit = $ct.Text.Substring(0, 7)
        $Resultado.Status = 'snapshot feito'
    }

    if (-not ((GitOut $Repo @('rev-parse', '-q', '--verify', $refLocal)).Code -eq 0)) { return }
    if ((GitOut $Repo @('remote', 'get-url', 'origin')).Code -ne 0) {
        $Resultado.Envio = 'SEM REMOTO'
        $Resultado.Alertas.Add('repositorio sem GitHub (origin) - o backup esta so no disco')
        return
    }
    $local  = (GitOut $Repo @('rev-parse', $refLocal)).Text
    $remoto = GitOut $Repo @('rev-parse', '-q', '--verify', $refRemota)
    if ($remoto.Code -eq 0 -and $remoto.Text -eq $local) { if ($Resultado.Commit) { $Resultado.Envio = 'ok' }; return }
    $p = GitRun $Repo @('push', '--force', 'origin', ($refLocal + ':refs/heads/backup/auto'))
    if ($p.Code -eq 0) {
        GitRun $Repo @('update-ref', $refRemota, $local) | Out-Null
        $Resultado.Envio = 'ok (branch backup/auto)'
    } else { $Resultado.Envio = 'FALHOU'; $Resultado.Erro = "push falhou: $($p.Text)" }
}

# ---------------------------------------------------------------------------
#  Previa: o que entraria e o que seria barrado, sem gravar nada no Git.
# ---------------------------------------------------------------------------
function Get-Previa {
    param([string]$Repo, [long]$LimiteBytes, [bool]$Monorepo)
    Update-Exclude $Repo $Monorepo $null
    $st = Split-Nul (GitOut $Repo @('status', '--porcelain', '-z', '-uall')).Out
    $entram = 0; $bytes = [long]0
    $barrados = New-Object System.Collections.Generic.List[string]
    foreach ($e in $st) {
        if ($e.Length -lt 4 -or $e -notmatch '^[ MADRCU\?!]{2} ') { continue }
        $xy = $e.Substring(0, 2); $rel = $e.Substring(3)
        if ($xy -match 'D') { continue }
        $motivo = Test-Arquivo $Repo $rel $LimiteBytes
        if ($motivo) { $barrados.Add("$rel -> $motivo") }
        else {
            $entram++
            $f = Join-Path $Repo $rel
            if (Test-Path -LiteralPath $f -PathType Leaf) { $bytes += (Get-Item -LiteralPath $f -Force).Length }
        }
    }
    return [pscustomobject]@{ Entram = $entram; MB = [math]::Round($bytes / 1MB, 1); Barrados = $barrados }
}

# ---------------------------------------------------------------------------
#  Resumo legivel (o Claude le este arquivo para atualizar os diarios)
# ---------------------------------------------------------------------------
function Write-Resumo {
    param($Resultados, [datetime]$Inicio)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Ultimo backup')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('Rodou em **{0}** no computador **{1}**.' -f ($Inicio.ToString('yyyy-MM-dd HH:mm')), $env:COMPUTERNAME))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Repositorio | Resultado | Arquivos | Envio ao GitHub |')
    [void]$sb.AppendLine('|---|---|---|---|')
    foreach ($r in $Resultados) {
        $st = $r.Status; if ($r.Erro) { $st += ' - ' + ($r.Erro -replace '\|', '/' -replace "`r?`n", ' ') }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $r.Nome, $st, $r.Arquivos.Count, $r.Envio))
    }
    $comAlerta = @($Resultados | Where-Object { $_.Alertas.Count -gt 0 -or $_.Avisos.Count -gt 0 })
    if ($comAlerta.Count -gt 0) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine('## Alertas e avisos'); [void]$sb.AppendLine('')
        foreach ($r in $comAlerta) {
            foreach ($a in $r.Alertas) { [void]$sb.AppendLine("- **$($r.Nome)**: $a") }
            foreach ($a in $r.Avisos)  { [void]$sb.AppendLine("- $($r.Nome): $a") }
        }
    }
    $comArq = @($Resultados | Where-Object { $_.Arquivos.Count -gt 0 })
    if ($comArq.Count -gt 0) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine('## O que mudou'); [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Legenda: A = novo, M = alterado, D = apagado, R = renomeado.')
        foreach ($r in $comArq) {
            [void]$sb.AppendLine(''); [void]$sb.AppendLine("### $($r.Nome)  ($($r.Modo))")
            $n = 0
            foreach ($a in $r.Arquivos) {
                if ($n -ge 60) { [void]$sb.AppendLine("- ... e mais $($r.Arquivos.Count - 60)"); break }
                [void]$sb.AppendLine('- ' + ($a -replace "`t", ' '))
                $n++
            }
        }
    }
    Write-Utf8 (Join-Path $script:SistemaDir 'ultimo-sync.md') $sb.ToString()

    $hist = Join-Path $script:LogDir 'historico.md'
    if (-not (Test-Path -LiteralPath $hist)) {
        Write-Utf8 $hist ("# Historico de backups`n`n| Data | Repositorio | Resultado | Arquivos | Envio |`n|---|---|---|---|---|`n")
    }
    foreach ($r in $Resultados) {
        if ($r.Status -eq 'sem mudancas' -and $r.Alertas.Count -eq 0) { continue }
        $linha = '| {0} | {1} | {2} | {3} | {4} |' -f $Inicio.ToString('yyyy-MM-dd HH:mm'), $r.Nome, $r.Status, $r.Arquivos.Count, $r.Envio
        [System.IO.File]::AppendAllText($hist, $linha + "`n", $script:Utf8SemBom)
    }
}
