# =============================================================================
#  03-agendar.ps1 - cria (ou atualiza) a tarefa do Windows que roda o backup
#  todo dia no horario do repos.json. Se o computador estiver desligado na
#  hora, roda assim que voce ligar.
#
#  Uso:  powershell -ExecutionPolicy Bypass -File .\03-agendar.ps1
#        ... -Remover      (apaga a tarefa)
#        ... -Testar       (roda a tarefa agora para conferir)
# =============================================================================
param([switch]$Remover, [switch]$Testar)

. (Join-Path $PSScriptRoot 'lib.ps1')
$nomeTarefa = 'Git Daily Backup'

if ($Remover) {
    Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host 'Tarefa removida.' -ForegroundColor Yellow
    exit 0
}

$cfg = Read-Config
$horario = Get-Prop $cfg 'horario' '21:00'
$sync = Join-Path $script:SistemaDir 'sync.ps1'

# Lancador invisivel (sem janela piscando na tela).
$vbs = Join-Path $script:SistemaDir 'rodar-oculto.vbs'
$conteudoVbs = @"
' Roda o sync.ps1 sem abrir janela. Gerado por 03-agendar.ps1.
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$sync""", 0, True
"@
# VBScript le o arquivo como ANSI/UTF-16; UTF-16 aceita acentos no caminho.
[System.IO.File]::WriteAllText($vbs, $conteudoVbs, [System.Text.Encoding]::Unicode)

$acao = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}"' -f $vbs) -WorkingDirectory $script:SistemaDir
$gatilho = New-ScheduledTaskTrigger -Daily -At $horario
$config = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -RunOnlyIfNetworkAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
$quem = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $nomeTarefa -Action $acao -Trigger $gatilho -Settings $config -Principal $quem `
    -Description 'Backup diario das pastas de projeto para o GitHub (sync.ps1).' -Force | Out-Null

Write-Host ''
Write-Host "[OK] Tarefa '$nomeTarefa' agendada para todo dia as $horario." -ForegroundColor Green
Write-Host '     Se o PC estiver desligado nesse horario, ela roda quando voce ligar.'
Write-Host '     Para ver/editar: menu Iniciar > "Agendador de Tarefas" > Biblioteca.'
Write-Host ''

if ($Testar) {
    Write-Host 'Rodando agora para testar (acompanhe o arquivo ultimo-sync.md)...' -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $nomeTarefa
}
