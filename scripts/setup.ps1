param(
    [string]$GithubPat = "",
    [string]$RepoOwner = "Mathis-Lefebvre",
    [string]$RepoName  = "tp-argocd"
)

$ErrorActionPreference = "Stop"

# ── Fonctions d'affichage (sans emojis pour eviter les erreurs d'encodage) ───
function Write-Step { param($msg) Write-Host "`n== $msg ==" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "  [ERR]  $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "  [...]  $msg" -ForegroundColor Gray }

# ─────────────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Setup GitHub Actions Runner -- DevHub Campus             " -ForegroundColor Cyan
Write-Host "                                                            " -ForegroundColor Cyan
Write-Host "   Ce script configure le runner UNE SEULE FOIS.           " -ForegroundColor Cyan
Write-Host "   Ensuite : cliquez Deploy sur GitHub, c'est tout.        " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1 / 4 -- Personal Access Token GitHub"
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Comment creer votre PAT :" -ForegroundColor Yellow
Write-Host "    1. Allez sur : https://github.com/settings/tokens/new" -ForegroundColor White
Write-Host "    2. Note : DevHub Runner" -ForegroundColor White
Write-Host "    3. Expiration : No expiration" -ForegroundColor White
Write-Host "    4. Scopes : cochez uniquement [ repo ]" -ForegroundColor White
Write-Host "    5. Cliquez Generate token et copiez la valeur (ghp_...)" -ForegroundColor White
Write-Host ""

if (-not $GithubPat) {
    $securePat = Read-Host "  Collez votre PAT GitHub ici" -AsSecureString
    $GithubPat = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePat)
    )
}

if (-not $GithubPat -or $GithubPat.Length -lt 10) {
    Write-Fail "PAT invalide ou vide. Abandon."
    Read-Host "Appuyez sur Entree pour fermer"
    exit 1
}

# Tester le PAT
Write-Info "Verification du PAT aupres de GitHub..."
try {
    $headers = @{
        Authorization       = "Bearer $GithubPat"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $user = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers
    Write-OK "PAT valide -- connecte en tant que : $($user.login)"
} catch {
    Write-Fail "PAT invalide ou sans les droits 'repo'. Verifiez et reessayez."
    Write-Fail "Erreur : $_"
    Read-Host "Appuyez sur Entree pour fermer"
    exit 1
}

# Stocker le PAT dans le Gestionnaire de credentials Windows
Write-Info "Stockage du PAT (Windows Credential Manager)..."
cmdkey /generic:"GitHubPAT_DevHub" /user:github /pass:$GithubPat | Out-Null
Write-OK "PAT stocke de facon securisee"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2 / 4 -- Creation du script de demarrage WSL"
# ─────────────────────────────────────────────────────────────────────────────

# Recuperer le HOME WSL
$wslHome = (wsl bash -c "echo `$HOME").Trim()
if (-not $wslHome) {
    Write-Fail "Impossible de trouver le HOME WSL. WSL est-il installe ?"
    Read-Host "Appuyez sur Entree pour fermer"
    exit 1
}
Write-OK "Home WSL detecte : $wslHome"

# Sauvegarder le PAT dans WSL comme fallback
wsl bash -c "echo '$GithubPat' > $wslHome/.devhub-pat && chmod 600 $wslHome/.devhub-pat"
Write-OK "PAT sauvegarde dans WSL ($wslHome/.devhub-pat)"

# Creer le script de demarrage dans WSL (heredoc via fichier temporaire)
$tempScript = "$env:TEMP\runner-autostart.sh"

$scriptContent = @'
#!/usr/bin/env bash
# runner-autostart.sh -- Demarre automatiquement le GitHub Actions runner
# Appele par la tache Windows au login. Aucune intervention necessaire.

REPO_OWNER="PLACEHOLDER_OWNER"
REPO_NAME="PLACEHOLDER_REPO"
RUNNER_HOME="$HOME/actions-runner"
LOG_FILE="$RUNNER_HOME/autostart.log"
RUNNER_VERSION="2.323.0"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

mkdir -p "$RUNNER_HOME"
log "=== Demarrage automatique du runner DevHub ==="

# Recuperer le PAT depuis le fichier local WSL
PAT_FILE="$HOME/.devhub-pat"
if [[ -f "$PAT_FILE" ]]; then
    PAT="$(cat "$PAT_FILE" | tr -d '\r\n')"
    log "PAT lu depuis $PAT_FILE"
else
    log "ERREUR : PAT introuvable dans $PAT_FILE. Relancez lancer-setup.bat"
    exit 1
fi

if [[ ${#PAT} -lt 10 ]]; then
    log "ERREUR : PAT trop court (${#PAT} caracteres). Relancez lancer-setup.bat"
    exit 1
fi

log "PAT recupere (longueur: ${#PAT})"

# Attendre que Docker soit disponible (max 60s)
log "Attente de Docker..."
for i in $(seq 1 30); do
    docker info &>/dev/null && break
    sleep 2
done
if ! docker info &>/dev/null; then
    log "ERREUR: Docker inaccessible apres 60s"
    exit 1
fi
log "Docker disponible"

# Telecharger le runner si necessaire
if [[ ! -f "$RUNNER_HOME/run.sh" ]]; then
    log "Telechargement du runner v$RUNNER_VERSION..."
    ARCHIVE="actions-runner-linux-x64-$RUNNER_VERSION.tar.gz"
    curl -fsSL -o "$RUNNER_HOME/$ARCHIVE" \
        "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/$ARCHIVE"
    tar xzf "$RUNNER_HOME/$ARCHIVE" -C "$RUNNER_HOME"
    rm "$RUNNER_HOME/$ARCHIVE"
    log "Runner extrait dans $RUNNER_HOME"
fi

# Obtenir un token d'enregistrement via l'API GitHub
log "Obtention d'un token d'enregistrement GitHub..."
API_RESPONSE=$(curl -fsSL \
    -X POST \
    -H "Authorization: Bearer $PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runners/registration-token")

REG_TOKEN=$(echo "$API_RESPONSE" | grep '"token"' | cut -d'"' -f4)

if [[ -z "$REG_TOKEN" ]]; then
    log "ERREUR : impossible d'obtenir un token GitHub. Reponse API: $API_RESPONSE"
    exit 1
fi
log "Token d'enregistrement obtenu"

# (Re)configurer le runner
cd "$RUNNER_HOME"

if [[ -f ".runner" ]]; then
    log "Suppression de l'ancienne configuration..."
    REMOVE_RESPONSE=$(curl -fsSL \
        -X POST \
        -H "Authorization: Bearer $PAT" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runners/remove-token")
    REMOVE_TOKEN=$(echo "$REMOVE_RESPONSE" | grep '"token"' | cut -d'"' -f4)
    ./config.sh remove --token "$REMOVE_TOKEN" 2>/dev/null || true
fi

RUNNER_NAME="devhub-$(hostname | tr -d '\r')"
log "Configuration du runner: $RUNNER_NAME"

./config.sh \
    --unattended \
    --url "https://github.com/$REPO_OWNER/$REPO_NAME" \
    --token "$REG_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "self-hosted,devhub,kind" \
    --work "_work" \
    --replace

log "Runner configure"

# Demarrer via systemd si disponible, sinon en background
if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    log "Demarrage via systemd..."
    sudo ./svc.sh install 2>/dev/null || true
    sudo ./svc.sh start  2>/dev/null || true
    log "Service systemd demarre"
else
    log "Demarrage en mode background..."
    nohup ./run.sh >> "$LOG_FILE" 2>&1 &
    log "Runner demarre (PID: $!)"
fi

log "Runner operationnel -- en attente de jobs GitHub Actions"
'@

# Remplacer les placeholders par les vraies valeurs
$scriptContent = $scriptContent -replace "PLACEHOLDER_OWNER", $RepoOwner
$scriptContent = $scriptContent -replace "PLACEHOLDER_REPO",  $RepoName

# Ecrire le script en UTF-8 sans BOM avec fins de ligne Unix
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tempScript, ($scriptContent -replace "`r`n", "`n"), $utf8NoBom)

# Copier dans WSL et rendre executable
$tempScriptWsl = (wsl wslpath "'$tempScript'").Trim()
wsl bash -c "cp '$tempScriptWsl' '$wslHome/runner-autostart.sh' && chmod +x '$wslHome/runner-autostart.sh'"
Write-OK "Script cree dans WSL : $wslHome/runner-autostart.sh"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "3 / 4 -- Tache de demarrage automatique Windows"
# ─────────────────────────────────────────────────────────────────────────────

$taskName = "GitHubActionsRunner-DevHub"

# Detecter la distro WSL
$wslDistro = (wsl --list --quiet 2>$null) -split "`n" |
    Where-Object { $_ -match '\S' } |
    ForEach-Object { $_ -replace "`0","" } |
    Select-Object -First 1
if (-not $wslDistro) { $wslDistro = "Ubuntu" }
$wslDistro = $wslDistro.Trim()
Write-Info "Distro WSL : $wslDistro"

# Supprimer l'ancienne tache si elle existe
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Write-Info "Suppression de l'ancienne tache..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction `
    -Execute "wsl.exe" `
    -Argument "-d $wslDistro bash -c 'nohup ~/runner-autostart.sh > ~/runner-boot.log 2>&1 &'"

$trigger = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 2) `
    -StartWhenAvailable

$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Demarre automatiquement le GitHub Actions runner DevHub au login Windows." `
    -Force | Out-Null

Write-OK "Tache Windows creee : '$taskName'"
Write-Info "Le runner demarrera automatiquement a chaque login Windows"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "4 / 4 -- Premier demarrage du runner"
# ─────────────────────────────────────────────────────────────────────────────

Write-Info "Lancement du runner maintenant..."
Start-ScheduledTask -TaskName $taskName
Write-Info "Attente de 15 secondes..."
Start-Sleep -Seconds 15

# Verifier sur GitHub
try {
    $headers = @{
        Authorization          = "Bearer $GithubPat"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $runners = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$RepoOwner/$RepoName/actions/runners" `
        -Headers $headers

    $active = $runners.runners | Where-Object { $_.status -eq "online" }

    if ($active) {
        Write-OK "Runner EN LIGNE sur GitHub !"
        Write-OK "Nom : $($active[0].name)"
    } else {
        Write-Warn "Runner en cours de demarrage (peut prendre 30-60s)..."
        Write-Info "Verifiez sur : https://github.com/$RepoOwner/$RepoName/settings/actions/runners"
    }
} catch {
    Write-Warn "Impossible de verifier via l'API : $_"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "   INSTALLATION TERMINEE !                                  " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Le runner demarre automatiquement a chaque login Windows." -ForegroundColor White
Write-Host ""
Write-Host "  Pour deployer l'infrastructure :" -ForegroundColor Yellow
Write-Host "  --> https://github.com/$RepoOwner/$RepoName/actions" -ForegroundColor White
Write-Host "  --> 'Deployer l'infrastructure' --> Run workflow" -ForegroundColor White
Write-Host ""
Write-Host "  Pour verifier les runners actifs :" -ForegroundColor Yellow
Write-Host "  --> https://github.com/$RepoOwner/$RepoName/settings/actions/runners" -ForegroundColor White
Write-Host ""

Read-Host "Appuyez sur Entree pour fermer"
