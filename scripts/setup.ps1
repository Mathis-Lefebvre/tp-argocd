param(
    [string]$GithubPat = "",
    [string]$RepoOwner = "Mathis-Lefebvre",
    [string]$RepoName  = "tp-argocd",
    [string]$RunnerDir = "$env:USERPROFILE\actions-runner-wsl"
)

# ─────────────────────────────────────────────────────────────────────────────
#  setup.ps1 — Configuration automatique du self-hosted runner GitHub Actions
#
#  À exécuter UNE SEULE FOIS en cliquant droit → "Exécuter avec PowerShell"
#  (ou depuis PowerShell : .\scripts\setup.ps1)
#
#  Ce script :
#   1. Demande votre Personal Access Token GitHub (stocké dans Windows)
#   2. Installe le runner dans WSL
#   3. Crée une tâche Windows qui démarre le runner automatiquement au login
#
#  Après ça : GitHub → Actions → "🚀 Déployer" → c'est tout.
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

# ── Couleurs console ──────────────────────────────────────────────────────────
function Write-Step   { param($msg) Write-Host "`n══ $msg ══" -ForegroundColor Cyan }
function Write-OK     { param($msg) Write-Host "  ✅ $msg"   -ForegroundColor Green }
function Write-Warn   { param($msg) Write-Host "  ⚠️  $msg"  -ForegroundColor Yellow }
function Write-Fail   { param($msg) Write-Host "  ❌ $msg"   -ForegroundColor Red }
function Write-Info   { param($msg) Write-Host "  ℹ️  $msg"  -ForegroundColor Gray }

# ─────────────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║   🤖  Setup GitHub Actions Runner — DevHub Campus            ║
║                                                              ║
║   Ce script configure le runner UNE SEULE FOIS.             ║
║   Ensuite : cliquez "Deploy" sur GitHub, c'est tout.         ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1 / 4 — Votre Personal Access Token GitHub"
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Un PAT (Personal Access Token) est nécessaire pour que le runner" -ForegroundColor White
Write-Host "  s'enregistre automatiquement auprès de GitHub sans action manuelle." -ForegroundColor White
Write-Host ""
Write-Host "  Comment créer votre PAT :" -ForegroundColor Yellow
Write-Host "    1. Allez sur : https://github.com/settings/tokens/new" -ForegroundColor White
Write-Host "    2. Note : 'DevHub Runner Auto-Register'" -ForegroundColor White
Write-Host "    3. Expiration : No expiration (ou 1 an)" -ForegroundColor White
Write-Host "    4. Scopes : cochez uniquement  [ repo ]" -ForegroundColor White
Write-Host "    5. Cliquez 'Generate token' et copiez la valeur" -ForegroundColor White
Write-Host ""

# Vérifier si le PAT est déjà stocké
$credentialTarget = "GitHubPAT_DevHub"
$existingCred = $null
try {
    $existingCred = [System.Net.CredentialCache]::DefaultNetworkCredentials
    $stored = cmdkey /list:$credentialTarget 2>$null
    if ($stored -match $credentialTarget) {
        Write-Warn "Un PAT est déjà stocké pour DevHub."
        $choice = Read-Host "  Voulez-vous le réutiliser ? (O/n)"
        if ($choice -ne 'n' -and $choice -ne 'N') {
            # Récupérer le PAT stocké
            $cred = Get-StoredCredential -Target $credentialTarget -ErrorAction SilentlyContinue
        }
    }
} catch {}

if (-not $GithubPat) {
    $securePat = Read-Host "  Collez votre PAT GitHub ici" -AsSecureString
    $GithubPat = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePat)
    )
}

if (-not $GithubPat -or $GithubPat.Length -lt 10) {
    Write-Fail "PAT invalide ou vide. Abandon."
    exit 1
}

# Tester le PAT
Write-Info "Vérification du PAT auprès de GitHub..."
try {
    $headers = @{ Authorization = "Bearer $GithubPat"; "X-GitHub-Api-Version" = "2022-11-28" }
    $user = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers
    Write-OK "PAT valide — connecté en tant que : $($user.login)"
} catch {
    Write-Fail "PAT invalide ou sans les droits 'repo'. Vérifiez et réessayez."
    exit 1
}

# Stocker le PAT dans le Gestionnaire de credentials Windows
Write-Info "Stockage du PAT dans le Gestionnaire de credentials Windows..."
cmdkey /generic:$credentialTarget /user:github /pass:$GithubPat | Out-Null
Write-OK "PAT stocké de façon sécurisée (Windows Credential Manager)"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2 / 4 — Création du script de démarrage automatique (WSL)"
# ─────────────────────────────────────────────────────────────────────────────

# Créer le dossier de travail local
New-Item -ItemType Directory -Force -Path $RunnerDir | Out-Null

# Créer le script WSL qui sera appelé au démarrage Windows
$wslStartupScript = "$RunnerDir\runner-autostart.sh"

@"
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# runner-autostart.sh — Démarre automatiquement le GitHub Actions runner
# Appelé par la tâche Windows au login. Ne nécessite aucune intervention.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_OWNER="$RepoOwner"
REPO_NAME="$RepoName"
RUNNER_HOME="`$HOME/actions-runner"
LOG_FILE="`$RUNNER_HOME/autostart.log"
RUNNER_VERSION="2.323.0"

log() { echo "[`$(date '+%Y-%m-%d %H:%M:%S')] `$*" | tee -a "`$LOG_FILE"; }

mkdir -p "`$RUNNER_HOME"
log "═══ Démarrage automatique du runner DevHub ═══"

# ── Récupérer le PAT depuis le Gestionnaire de credentials Windows ──────────
log "Récupération du PAT depuis Windows Credential Manager..."
PAT="`$(powershell.exe -NoProfile -NonInteractive -Command "
(Get-StoredCredential -Target '$credentialTarget').GetNetworkCredential().Password
" 2>/dev/null | tr -d '\r\n')"

# Fallback : lire depuis un fichier chiffré local
if [[ -z "`$PAT" || `${#PAT} -lt 10 ]]; then
    PAT_FILE="`$HOME/.devhub-pat"
    if [[ -f "`$PAT_FILE" ]]; then
        PAT="`$(cat "`$PAT_FILE" | tr -d '\r\n')"
        log "PAT lu depuis le fichier de secours"
    else
        log "ERREUR : PAT introuvable. Relancez setup.ps1"
        exit 1
    fi
fi

log "PAT récupéré (longueur: `${#PAT})"

# ── Attendre que Docker soit disponible ─────────────────────────────────────
log "Attente de Docker..."
for i in `$(seq 1 30); do
    docker info &>/dev/null && break
    sleep 2
done
docker info &>/dev/null && log "Docker disponible" || { log "ERREUR: Docker inaccessible"; exit 1; }

# ── Télécharger le runner si nécessaire ─────────────────────────────────────
if [[ ! -f "`$RUNNER_HOME/run.sh" ]]; then
    log "Téléchargement du runner v`$RUNNER_VERSION..."
    ARCHIVE="actions-runner-linux-x64-`$RUNNER_VERSION.tar.gz"
    curl -fsSL -o "`$RUNNER_HOME/`$ARCHIVE" \
        "https://github.com/actions/runner/releases/download/v`$RUNNER_VERSION/`$ARCHIVE"
    tar xzf "`$RUNNER_HOME/`$ARCHIVE" -C "`$RUNNER_HOME"
    rm "`$RUNNER_HOME/`$ARCHIVE"
    log "Runner extrait"
fi

# ── Obtenir un token d'enregistrement via l'API GitHub ──────────────────────
log "Obtention d'un token d'enregistrement via GitHub API..."
REG_TOKEN="`$(curl -fsSL \
    -X POST \
    -H "Authorization: Bearer `$PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/`$REPO_OWNER/`$REPO_NAME/actions/runners/registration-token" \
    | grep '"token"' | cut -d'"' -f4)"

if [[ -z "`$REG_TOKEN" ]]; then
    log "ERREUR : impossible d'obtenir un token d'enregistrement GitHub"
    exit 1
fi
log "Token d'enregistrement obtenu"

# ── (Re)configurer le runner ─────────────────────────────────────────────────
cd "`$RUNNER_HOME"

# Supprimer l'ancienne config si elle existe
if [[ -f ".runner" ]]; then
    log "Reconfiguration du runner existant..."
    REMOVE_TOKEN="`$(curl -fsSL \
        -X POST \
        -H "Authorization: Bearer `$PAT" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/`$REPO_OWNER/`$REPO_NAME/actions/runners/remove-token" \
        | grep '"token"' | cut -d'"' -f4)"
    ./config.sh remove --token "`$REMOVE_TOKEN" 2>/dev/null || true
fi

RUNNER_NAME="devhub-`$(hostname | tr -d '\r')"
log "Configuration du runner : `$RUNNER_NAME"

./config.sh \
    --unattended \
    --url "https://github.com/`$REPO_OWNER/`$REPO_NAME" \
    --token "`$REG_TOKEN" \
    --name "`$RUNNER_NAME" \
    --labels "self-hosted,devhub,kind" \
    --work "_work" \
    --replace

log "Runner configuré"

# ── Démarrer via systemd si disponible, sinon en background ─────────────────
if command -v systemctl &>/dev/null && systemctl is-system-running --wait 2>/dev/null; then
    log "Installation en service systemd..."
    sudo ./svc.sh install 2>/dev/null || true
    sudo ./svc.sh start  2>/dev/null || true
    log "Service systemd démarré"
else
    log "Démarrage en mode background..."
    nohup ./run.sh >> "`$LOG_FILE" 2>&1 &
    log "Runner démarré (PID: `$!)"
fi

log "✅ Runner opérationnel — en attente de jobs GitHub Actions"
"@ | Set-Content -Encoding UTF8 -Path $wslStartupScript

# Convertir les fins de ligne Windows → Unix pour WSL
$content = Get-Content $wslStartupScript -Raw
$content = $content -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($wslStartupScript, $content)

Write-OK "Script de démarrage créé : $wslStartupScript"

# Aussi sauvegarder le PAT dans WSL comme fallback
$wslHome = wsl bash -c "echo `$HOME" 2>$null
if ($wslHome) {
    $wslHome = $wslHome.Trim()
    Write-Info "Sauvegarde du PAT dans WSL (fallback chiffré)..."
    wsl bash -c "echo '$GithubPat' > $wslHome/.devhub-pat && chmod 600 $wslHome/.devhub-pat"
    Write-OK "PAT sauvegardé dans WSL"
}

# Copier le script dans WSL
$wslScriptPath = "$wslHome/runner-autostart.sh"
$wslStartupScriptWsl = (wsl wslpath "'$wslStartupScript'" 2>$null).Trim()
wsl bash -c "cp '$wslStartupScriptWsl' '$wslScriptPath' && chmod +x '$wslScriptPath'"
Write-OK "Script copié dans WSL : $wslScriptPath"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "3 / 4 — Tâche de démarrage automatique Windows"
# ─────────────────────────────────────────────────────────────────────────────

$taskName = "GitHubActionsRunner-DevHub"

# Détecter la distro WSL disponible
$wslDistro = (wsl --list --quiet 2>$null | Where-Object { $_ -match '\S' } | Select-Object -First 1)
if (-not $wslDistro) { $wslDistro = "Ubuntu" }
$wslDistro = $wslDistro.Trim() -replace "`0", ""

Write-Info "Distro WSL détectée : $wslDistro"

# Supprimer l'ancienne tâche si elle existe
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Write-Info "Suppression de l'ancienne tâche..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Créer la tâche Windows
$action = New-ScheduledTaskAction `
    -Execute "wsl.exe" `
    -Argument "-d $wslDistro bash -c 'nohup ~/runner-autostart.sh > ~/runner-autostart-boot.log 2>&1 &'"

$trigger = @(
    $(New-ScheduledTaskTrigger -AtLogOn),          # Au login Windows
    $(New-ScheduledTaskTrigger -AtStartup)          # Au démarrage système
)

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 2) `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

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
    -Description "Démarre automatiquement le GitHub Actions runner DevHub au login Windows. Ne pas supprimer." `
    -Force | Out-Null

Write-OK "Tâche Windows créée : '$taskName'"
Write-Info "Le runner démarrera automatiquement à chaque login Windows"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "4 / 4 — Premier démarrage du runner"
# ─────────────────────────────────────────────────────────────────────────────

Write-Info "Lancement du runner maintenant (pas besoin de redémarrer)..."
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 8

# Vérifier que le runner est bien visible sur GitHub
try {
    $headers = @{ Authorization = "Bearer $GithubPat"; "X-GitHub-Api-Version" = "2022-11-28" }
    $runners = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$RepoOwner/$RepoName/actions/runners" `
        -Headers $headers

    $activeRunner = $runners.runners | Where-Object { $_.status -eq "online" }

    if ($activeRunner) {
        Write-OK "Runner en ligne sur GitHub !"
        Write-Host "     Nom : $($activeRunner[0].name)" -ForegroundColor Green
        Write-Host "     ID  : $($activeRunner[0].id)" -ForegroundColor Green
    } else {
        Write-Warn "Runner en cours de démarrage (peut prendre 30s)..."
        Write-Info "Vérifiez sur : https://github.com/$RepoOwner/$RepoName/settings/actions/runners"
    }
} catch {
    Write-Warn "Impossible de vérifier le statut du runner via l'API."
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║   ✅  Configuration terminée !                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  🎉 Le runner démarre automatiquement à chaque login.        ║
║                                                              ║
║  Pour déployer l'infrastructure :                            ║
║  → https://github.com/$RepoOwner/$RepoName/actions          ║
║  → "🚀 Déployer l'infrastructure" → Run workflow            ║
║                                                              ║
║  Pour détruire :                                             ║
║  → "🗑️ Détruire l'infrastructure" → Run workflow (DESTROY)  ║
║                                                              ║
║  Vérifier les runners actifs :                               ║
║  → https://github.com/$RepoOwner/$RepoName/settings/actions/runners
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

Read-Host "`nAppuyez sur Entrée pour fermer"
