SHELL := /bin/bash
CLUSTER ?= devhub
ARGOCD_CHART_VERSION ?= 7.6.12
INGRESS_CHART_VERSION ?= 4.11.3

SERVICES := annuaire planning notif

.PHONY: help tools-check cluster-up cluster-down argocd-install argocd-password hosts-print images clean runner-install runner-status runner-stop

help:
	@echo "Cibles disponibles :"
	@echo "  tools-check       - vérifie que les outils requis sont installés"
	@echo "  cluster-up        - démarre un cluster Kubernetes local (kind)"
	@echo "  cluster-down      - détruit le cluster"
	@echo "  argocd-install    - installe ingress-nginx + ArgoCD via Helm"
	@echo "  argocd-password   - affiche le mot de passe admin initial"
	@echo "  hosts-print       - affiche les lignes à ajouter dans /etc/hosts"
	@echo "  images            - construit les 3 images de services"
	@echo "  clean             - détruit le cluster et nettoie les artefacts locaux"
	@echo ""
	@echo "  runner-install    - installe le self-hosted runner GitHub Actions en service auto"
	@echo "  runner-status     - vérifie l'état du runner"
	@echo "  runner-stop       - arrête et désinstalle le runner"

tools-check:
	@for t in docker kubectl helm kind argocd; do \
		command -v $$t >/dev/null 2>&1 || { echo "manquant : $$t"; exit 1; }; \
	done
	@echo "tous les outils sont présents."
	@docker version --format '  docker  : {{.Server.Version}}'
	@kubectl version --client --short 2>/dev/null | sed 's/^/  /'
	@helm version --short | sed 's/^/  helm    : /'
	@kind version | sed 's/^/  /'
	@argocd version --client --short 2>/dev/null | sed 's/^/  /'

cluster-up:
	kind create cluster --name $(CLUSTER) --config cluster/kind-config.yaml
	@echo ">>> cluster prêt — contexte courant : kind-$(CLUSTER)"

cluster-down:
	kind delete cluster --name $(CLUSTER)

argocd-install:
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx --create-namespace \
		--version $(INGRESS_CHART_VERSION) \
		--set controller.service.type=NodePort \
		--set-string controller.nodeSelector."ingress-ready"=true \
		--set "controller.tolerations[0].key=node-role.kubernetes.io/control-plane" \
		--set "controller.tolerations[0].operator=Exists" \
		--set "controller.tolerations[0].effect=NoSchedule" \
		--set controller.hostPort.enabled=true \
		--set controller.publishService.enabled=false
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=180s
	helm upgrade --install argocd argo/argo-cd \
		--namespace argocd --create-namespace \
		--version $(ARGOCD_CHART_VERSION) \
		-f platform/argocd/values.yaml

argocd-password:
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d ; echo

hosts-print:
	@echo "ajoutez ces lignes à votre fichier hosts :"
	@echo "  macOS/Linux : /etc/hosts"
	@echo "  Windows     : C:\\Windows\\System32\\drivers\\etc\\hosts"
	@echo ""
	@echo "127.0.0.1  argocd.devhub.local"
	@echo "127.0.0.1  annuaire.devhub.local"
	@echo "127.0.0.1  planning.devhub.local"
	@echo "127.0.0.1  notif.devhub.local"

# TODO : adaptez GHCR_USER à votre compte GitHub.
GHCR_USER ?= changeme
SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

images:
	@for svc in $(SERVICES); do \
		echo ">>> build $$svc"; \
		docker build -t ghcr.io/$(GHCR_USER)/$$svc:$(SHA) services/$$svc; \
	done

clean:
	kind delete cluster --name $(CLUSTER) 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions Self-Hosted Runner
# ─────────────────────────────────────────────────────────────────────────────
# Obtenir le token sur :
#   https://github.com/Mathis-Lefebvre/tp-argocd/settings/actions/runners/new
#
# Usage : make runner-install TOKEN=<votre_token>
# ─────────────────────────────────────────────────────────────────────────────
RUNNER_DIR ?= $(HOME)/actions-runner

runner-install:
	@if [ -z "$(TOKEN)" ]; then \
		echo "❌ TOKEN manquant. Usage : make runner-install TOKEN=<votre_token>"; \
		echo "   Token disponible sur : https://github.com/Mathis-Lefebvre/tp-argocd/settings/actions/runners/new"; \
		exit 1; \
	fi
	bash scripts/install-runner.sh --token "$(TOKEN)"

runner-status:
	@echo "=== État du service GitHub Actions Runner ==="
	@if systemctl is-active --quiet actions.runner.* 2>/dev/null; then \
		sudo systemctl status "$$(systemctl list-units --type=service | grep actions.runner | awk '{print $$1}' | head -1)" --no-pager; \
	elif [ -f "$(RUNNER_DIR)/runner.log" ]; then \
		echo "Runner en mode background (pas de service systemd)"; \
		tail -20 $(RUNNER_DIR)/runner.log; \
	else \
		echo "⚠️  Runner non démarré ou non configuré"; \
	fi

runner-stop:
	@echo "🛑 Arrêt et désinstallation du runner..."
	@if systemctl is-active --quiet actions.runner.* 2>/dev/null; then \
		SVC=$$(systemctl list-units --type=service | grep actions.runner | awk '{print $$1}' | head -1); \
		cd $(RUNNER_DIR) && sudo ./svc.sh stop && sudo ./svc.sh uninstall; \
		echo "✅ Service systemd supprimé"; \
	else \
		pkill -f "$(RUNNER_DIR)/run.sh" 2>/dev/null && echo "✅ Runner arrêté" || echo "ℹ️  Runner déjà arrêté"; \
	fi
