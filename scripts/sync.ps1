# =============================================================================
#  sync.ps1 - backup diario de todos os repositorios listados em repos.json
#
#  Uso manual (PowerShell, dentro da pasta _sistema):
#     .\sync.ps1              faz o backup agora
#     .\sync.ps1 -Simular     so mostra o que subiria / seria barrado
#     .\sync.ps1 -Somente ordo-juria    so um repositorio
#
#  A tarefa agendada do Windows roda este arquivo todo dia.
# =============================================================================
param(
    [switch]$Simular,
    [string]$Somente = '',
    [switch]$SemAviso
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$script:GitExe = Get-GitExe
if (-not $script:GitExe) { Write-Log 'Git nao encontrado. Rode 01-preparar.ps1.' 'ERRO'; exit 1 }

# --- trava: evita duas execucoes ao mesmo tempo ------------------------------
if (-not (Test-Path -LiteralPath $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null }
$trava = Join-Path $script:LogDir 'sync.lock'
if (Test-Path -LiteralPath $trava) {
    $idade = (Get-Date) - (Get-Item -LiteralPath $trava).LastWriteTime
    if ($idade.TotalHours -lt 2) { Write-Log 'Outro backup ja esta rodando. Saindo.' 'ALERTA'; exit 0 }
}
Write-Utf8 $trava ([string]$PID)

try {
    $cfg = Read-Config
    $limite = [long]([double](Get-Prop $cfg 'limiteMB' 45) * 1MB)
    $cofreNome = Get-Prop $cfg 'cofre' 'notes'
    $repos = @($cfg.repos | Where-Object { (Get-Prop $_ 'ativo' $true) -ne $false })
    if ($Somente) { $repos = @($repos | Where-Object { $_.nome -eq $Somente }) }
    # O cofre vai por ultimo, para levar junto o resumo deste backup.
    $repos = @($repos | Where-Object { $_.nome -ne $cofreNome }) + @($repos | Where-Object { $_.nome -eq $cofreNome })

    $inicio = Get-Date
    Write-Log ('==== inicio ({0} repositorio(s)){1}' -f $repos.Count, $(if ($Simular) { ' [SIMULACAO]' } else { '' }))
    $resultados = New-Object System.Collections.Generic.List[object]

    foreach ($r in $repos) {
        $modo = Get-Prop $r 'modo' 'direto'
        $mono = [bool](Get-Prop $r 'monorepo' $false)
        $res = New-Resultado $r.nome $r.caminho $modo

        if (-not (Test-Path -LiteralPath $r.caminho)) {
            $res.Status = 'ERRO'; $res.Erro = 'pasta nao existe'
        } elseif (-not (Test-Path -LiteralPath (Join-Path $r.caminho '.git'))) {
            $res.Status = 'ERRO'; $res.Erro = 'pasta ainda nao e repositorio - rode 02-criar-repos.ps1'
        } elseif ($Simular) {
            $pv = Get-Previa $r.caminho $limite $mono
            $res.Status = 'simulacao'
            $res.Arquivos.Add(('{0} arquivo(s) novos ou alterados (~{1} MB)' -f $pv.Entram, $pv.MB))
            foreach ($b in $pv.Barrados) { $res.Alertas.Add("seria BARRADO: $b") }
        } else {
            if ($r.nome -eq $cofreNome) { Write-Resumo $resultados $inicio }
            try {
                if ($modo -eq 'snapshot') { Sync-Snapshot $r.caminho $limite $res }
                else { Sync-Direto $r.caminho $limite $res $mono }
            } catch { $res.Status = 'ERRO'; $res.Erro = "$_" }
        }

        $nivel = 'OK'
        if ($res.Status -eq 'ERRO' -or $res.Envio -eq 'FALHOU') { $nivel = 'ERRO' } elseif ($res.Alertas.Count -gt 0) { $nivel = 'ALERTA' }
        Write-Log ('{0}: {1} | {2} arquivo(s) | envio: {3} {4}' -f $res.Nome, $res.Status, $res.Arquivos.Count, $res.Envio, $res.Erro) $nivel
        foreach ($a in $res.Alertas) { Write-Log ('   ' + $a) 'ALERTA' }
        foreach ($a in $res.Avisos)  { Write-Log ('   ' + $a) 'INFO' }
        $resultados.Add($res)
    }

    if (-not $Simular) { Write-Resumo $resultados $inicio }
    Write-Log ('==== fim ({0:N0} s)' -f ((Get-Date) - $inicio).TotalSeconds)

    $problemas = @($resultados | Where-Object { $_.Status -eq 'ERRO' -or $_.Envio -eq 'FALHOU' -or $_.Alertas.Count -gt 0 })
    if ($problemas.Count -gt 0 -and -not $Simular -and -not $SemAviso -and $script:EhWindows) {
        $txt = "Backup GitHub: $($problemas.Count) repositorio(s) precisam de atencao:`n`n"
        foreach ($p in $problemas) { $txt += "- $($p.Nome): $($p.Status) $($p.Erro)`n" }
        $txt += "`nDetalhes em ultimo-sync.md, na pasta dos scripts"
        try { (New-Object -ComObject WScript.Shell).Popup($txt, 120, 'Git Daily Backup', 48) | Out-Null } catch { }
    }
    if ($problemas.Count -gt 0) { exit 2 } else { exit 0 }
}
finally {
    Remove-Item -LiteralPath $trava -Force -ErrorAction SilentlyContinue
}

