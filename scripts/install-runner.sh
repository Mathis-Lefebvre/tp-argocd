#!/usr/bin/env bash
# =============================================================================
# install-runner.sh — Installe et configure le GitHub Actions self-hosted runner
# en service systemd (WSL) ou tâche Windows (Task Scheduler)
#
# Usage :
#   bash scripts/install-runner.sh --token <TOKEN> [--url <REPO_URL>]
#
# Le token s'obtient sur :
#   https://github.com/Mathis-Lefebvre/tp-argocd → Settings → Actions → Runners
#   → New self-hosted runner → copier la valeur après --token
# =============================================================================

set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

info()    { echo -e "${CYAN}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
error()   { echo -e "${RED}❌ $*${NC}"; exit 1; }
step()    { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }

# ── Paramètres par défaut ─────────────────────────────────────────────────────
RUNNER_VERSION="2.323.0"
RUNNER_DIR="${HOME}/actions-runner"
REPO_URL="https://github.com/Mathis-Lefebvre/tp-argocd"
RUNNER_NAME="devhub-local-$(hostname)"
TOKEN=""
RUNNER_LABELS="self-hosted,devhub,kind"

# ── Parsing des arguments ─────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)   TOKEN="$2";      shift 2 ;;
    --url)     REPO_URL="$2";   shift 2 ;;
    --dir)     RUNNER_DIR="$2"; shift 2 ;;
    --name)    RUNNER_NAME="$2";shift 2 ;;
    *) error "Argument inconnu : $1" ;;
  esac
done

# ── Vérification du token ─────────────────────────────────────────────────────
if [[ -z "$TOKEN" ]]; then
  echo ""
  echo -e "${BOLD}Comment obtenir le token :${NC}"
  echo "  1. Aller sur : ${REPO_URL}/settings/actions/runners/new"
  echo "  2. Choisir Linux / x64"
  echo "  3. Copier la valeur après '--token' dans la commande ./config.sh"
  echo ""
  read -rp "Collez votre token ici : " TOKEN
  [[ -z "$TOKEN" ]] && error "Token vide, abandon."
fi

# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   🤖  Installation GitHub Actions Self-Hosted Runner       ║${NC}"
echo -e "${BOLD}╠═══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║  Repo   : ${REPO_URL}${NC}"
echo -e "${BOLD}║  Dossier: ${RUNNER_DIR}${NC}"
echo -e "${BOLD}║  Nom    : ${RUNNER_NAME}${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
step "1 / 5 — Vérification de l'environnement"
# ─────────────────────────────────────────────────────────────────────────────

for tool in curl tar; do
  command -v $tool &>/dev/null && success "$tool disponible" || error "$tool manquant"
done

# Vérifier qu'on est dans WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
  success "Environnement WSL détecté"
  IN_WSL=true
else
  warn "Pas dans WSL — continuons quand même"
  IN_WSL=false
fi

# ─────────────────────────────────────────────────────────────────────────────
step "2 / 5 — Téléchargement du runner v${RUNNER_VERSION}"
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

ARCHIVE="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"

if [[ -f "${ARCHIVE}" ]]; then
  warn "Archive déjà présente, on réutilise"
else
  info "Téléchargement depuis GitHub Releases..."
  curl -fsSL -o "${ARCHIVE}" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${ARCHIVE}"
  success "Téléchargement terminé"
fi

info "Extraction de l'archive..."
tar xzf "${ARCHIVE}"
success "Runner extrait dans ${RUNNER_DIR}"

# ─────────────────────────────────────────────────────────────────────────────
step "3 / 5 — Configuration du runner"
# ─────────────────────────────────────────────────────────────────────────────

# Supprimer l'ancienne config si elle existe
if [[ -f ".runner" ]]; then
  warn "Runner déjà configuré — suppression de l'ancienne config..."
  ./config.sh remove --token "${TOKEN}" 2>/dev/null || true
fi

info "Configuration du runner..."
./config.sh \
  --unattended \
  --url "${REPO_URL}" \
  --token "${TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --work "_work" \
  --replace

success "Runner configuré"

# ─────────────────────────────────────────────────────────────────────────────
step "4 / 5 — Installation en service automatique"
# ─────────────────────────────────────────────────────────────────────────────

# Détecter si systemd est disponible dans WSL
SYSTEMD_AVAILABLE=false
if [[ "$IN_WSL" == "true" ]] && command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
  SYSTEMD_AVAILABLE=true
fi

if [[ "$SYSTEMD_AVAILABLE" == "true" ]]; then
  # ── Méthode 1 : systemd (WSL avec systemd activé) ────────────────────────
  info "Installation via systemd..."
  sudo ./svc.sh install
  sudo ./svc.sh start
  sleep 2
  sudo ./svc.sh status
  success "Runner installé en service systemd — démarrage automatique activé"

else
  # ── Méthode 2 : script de démarrage + tâche Windows ──────────────────────
  warn "systemd non disponible — création d'un script de démarrage Windows"

  # Créer un script de démarrage WSL
  STARTUP_SCRIPT="${RUNNER_DIR}/start-runner.sh"
  cat > "${STARTUP_SCRIPT}" << 'SCRIPT'
#!/usr/bin/env bash
# Démarre le GitHub Actions runner (lancé automatiquement par Windows)
RUNNER_DIR="${HOME}/actions-runner"
LOG_FILE="${RUNNER_DIR}/runner.log"

echo "[$(date)] Démarrage du runner..." >> "${LOG_FILE}"
cd "${RUNNER_DIR}"

# Attendre que le réseau soit disponible
for i in {1..30}; do
  curl -s --head https://github.com >/dev/null 2>&1 && break
  sleep 2
done

./run.sh >> "${LOG_FILE}" 2>&1 &
echo "[$(date)] Runner PID: $!" >> "${LOG_FILE}"
SCRIPT
  chmod +x "${STARTUP_SCRIPT}"

  # Convertir le chemin WSL en chemin Windows pour le planificateur
  WSL_DISTRO=$(cat /proc/version | grep -oP '(?<=WSL2 )\S+' 2>/dev/null || wsl.exe -l -q 2>/dev/null | head -1 | tr -d '\r\0' || echo "Ubuntu")

  # Créer le script PowerShell pour le planificateur de tâches
  RUNNER_DIR_WIN=$(wslpath -w "${RUNNER_DIR}" 2>/dev/null || echo "\\\\wsl.localhost\\Ubuntu${RUNNER_DIR}")

  cat > "${RUNNER_DIR}/register-windows-task.ps1" << PSSCRIPT
# Script PowerShell — Enregistre le runner comme tâche Windows au démarrage
# Lancer depuis PowerShell en administrateur :
#   Set-ExecutionPolicy Bypass -Scope Process
#   & "${RUNNER_DIR_WIN}\\register-windows-task.ps1"

\$action = New-ScheduledTaskAction `
  -Execute "wsl.exe" `
  -Argument "-d \$(wsl -l -q | Select-Object -First 1) bash -c 'nohup ~/actions-runner/start-runner.sh > /dev/null 2>&1 &'"

\$trigger = New-ScheduledTaskTrigger -AtLogOn

\$settings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit 0 `
  -RestartCount 3 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -StartWhenAvailable

\$principal = New-ScheduledTaskPrincipal `
  -UserId \$env:USERNAME `
  -LogonType Interactive `
  -RunLevel Limited

Register-ScheduledTask `
  -TaskName "GitHubActionsRunner-DevHub" `
  -Action \$action `
  -Trigger \$trigger `
  -Settings \$settings `
  -Principal \$principal `
  -Description "Démarre automatiquement le GitHub Actions self-hosted runner au login Windows" `
  -Force

Write-Host "✅ Tâche planifiée créée : GitHubActionsRunner-DevHub"
Write-Host "   Le runner démarrera automatiquement au prochain login Windows."
PSSCRIPT

  success "Script de démarrage créé : ${STARTUP_SCRIPT}"
  info "Pour activer le démarrage automatique Windows, exécutez dans PowerShell (admin) :"
  echo ""
  echo -e "  ${YELLOW}Set-ExecutionPolicy Bypass -Scope Process${NC}"
  echo -e "  ${YELLOW}& '$(wslpath -w "${RUNNER_DIR}/register-windows-task.ps1" 2>/dev/null)'${NC}"
  echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
step "5 / 5 — Démarrage immédiat du runner"
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$SYSTEMD_AVAILABLE" == "true" ]]; then
  info "Runner déjà démarré via systemd"
else
  info "Démarrage du runner en arrière-plan..."
  nohup "${RUNNER_DIR}/run.sh" > "${RUNNER_DIR}/runner.log" 2>&1 &
  RUNNER_PID=$!
  sleep 3

  if kill -0 $RUNNER_PID 2>/dev/null; then
    success "Runner démarré (PID: ${RUNNER_PID})"
    info "Logs : ${RUNNER_DIR}/runner.log"
  else
    error "Le runner ne semble pas avoir démarré. Consultez ${RUNNER_DIR}/runner.log"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   ✅  Installation terminée avec succès !                 ║${NC}"
echo -e "${BOLD}${GREEN}╠═══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║                                                           ║${NC}"
echo -e "${BOLD}${GREEN}║  Le runner est actif et enregistré sur GitHub.            ║${NC}"
echo -e "${BOLD}${GREEN}║                                                           ║${NC}"
echo -e "${BOLD}${GREEN}║  Pour déployer l'infra :                                  ║${NC}"
echo -e "${BOLD}${GREEN}║  → GitHub → Actions → 🚀 Déployer l'infrastructure        ║${NC}"
echo -e "${BOLD}${GREEN}║  → Run workflow                                           ║${NC}"
echo -e "${BOLD}${GREEN}║                                                           ║${NC}"
echo -e "${BOLD}${GREEN}║  Vérifier le runner :                                     ║${NC}"
echo -e "${BOLD}${GREEN}║  ${REPO_URL}/settings/actions/runners${NC}"
echo -e "${BOLD}${GREEN}║                                                           ║${NC}"
echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
