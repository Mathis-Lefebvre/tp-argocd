# DevHub Campus — GitOps & ArgoCD

> TP complet de déploiement GitOps avec ArgoCD sur Kubernetes (Kind).
> **Auteur : Mathis Lefebvre — 5ESGI SRC**

---

## Table des matières

- [Architecture](#architecture)
- [Prérequis](#prérequis)
- [Démarrage rapide (manuel)](#démarrage-rapide-manuel)
- [Déployer depuis GitHub (recommandé)](#déployer-depuis-github-recommandé)
  - [1. Configuration unique du runner](#1-configuration-unique-du-runner-5-minutes)
  - [2. Déployer l'infrastructure](#2-déployer-linfrastructure)
  - [3. Détruire l'infrastructure](#3-détruire-linfrastructure)
- [Credentials & URLs](#credentials--urls)
- [Structure du dépôt](#structure-du-dépôt)
- [Commandes utiles](#commandes-utiles)
- [Dépannage](#dépannage)

---

## Architecture

```
GitHub (source de vérité)
        │
        │  git pull (mode Pull — GitOps)
        ▼
┌─────────────────────────────────────────────────┐
│           Cluster Kind "devhub" (local)          │
│                                                  │
│  ┌─────────────┐   ┌──────────────────────────┐ │
│  │   ArgoCD    │──▶│  devhub-dev namespace    │ │
│  │  (argocd)   │   │  ├─ annuaire (Node.js)   │ │
│  └─────────────┘   │  ├─ planning (Python)    │ │
│        │           │  └─ notif (Go)            │ │
│        │           └──────────────────────────┘ │
│        │           ┌──────────────────────────┐ │
│        └──────────▶│  devhub-preview-*        │ │
│                    │  (environnements éphémères)│ │
│                    └──────────────────────────┘ │
│                                                  │
│  Ingress-NGINX → *.devhub.local                 │
└─────────────────────────────────────────────────┘
        ▲
        │  GitHub Actions self-hosted runner
        │  (s'exécute dans WSL, démarre automatiquement)
GitHub Actions (Deploy / Destroy)
```

---

## Prérequis

| Outil | Version testée | Installation |
|---|---|---|
| Docker Desktop (WSL2) | v27+ | [docker.com](https://docs.docker.com/desktop/windows/install/) |
| WSL2 + Ubuntu | Ubuntu 22.04+ | `wsl --install` |
| kubectl | v1.34 | `apt install kubectl` dans WSL |
| Helm | v3.21 | `apt install helm` dans WSL |
| Kind | v0.24 | `apt install kind` dans WSL |
| ArgoCD CLI | v3.4 | [github.com/argoproj/argo-cd](https://github.com/argoproj/argo-cd/releases) |

> **Windows uniquement** : toutes les commandes Makefile s'exécutent dans WSL2.

### Fichier hosts Windows

Ajouter dans `C:\Windows\System32\drivers\etc\hosts` :

```
127.0.0.1  argocd.devhub.local
127.0.0.1  annuaire.devhub.local
127.0.0.1  planning.devhub.local
127.0.0.1  notif.devhub.local
127.0.0.1  annuaire-feature-demo-prof.devhub.local
```

---

## Démarrage rapide (manuel)

Si vous préférez tout contrôler manuellement depuis WSL :

```bash
make tools-check          # vérifie les outils
make cluster-up           # crée le cluster Kind
make argocd-install       # installe Ingress-NGINX + ArgoCD
make argocd-password      # affiche le mot de passe admin
make hosts-print          # affiche les lignes à ajouter dans /etc/hosts

# Bootstrapper les applications (App of Apps)
kubectl apply -f platform/projects/devhub.yaml
kubectl apply -f platform/bootstrap/root-app.yaml

# Démarrer le daemon Git local (pour ArgoCD)
git daemon --base-path=. --export-all --enable=receive-pack \
           --reuseaddr --port=9000 --verbose &
```

---

## Déployer depuis GitHub (recommandé)

Cette méthode permet de **déployer et détruire l'infrastructure en un clic** depuis l'interface GitHub, sans ouvrir de terminal.

### 1. Configuration unique du runner (5 minutes)

> À faire **une seule fois**. Après ça, le runner démarre automatiquement à chaque login Windows.

#### Étape A — Créer un Personal Access Token GitHub

1. Aller sur : **https://github.com/settings/tokens/new**
2. Remplir :
   - **Note** : `DevHub Runner`
   - **Expiration** : `No expiration`
   - **Scopes** : cocher uniquement ☑ **`repo`**
3. Cliquer **Generate token**
4. **Copier le token** (commence par `ghp_...`) — il n'est affiché qu'une seule fois

#### Étape B — Lancer le script de configuration

Dans l'Explorateur Windows, aller dans :
```
scripts\
```

**Double-cliquer sur `lancer-setup.bat`**

- Windows demande les droits administrateur → cliquer **Oui**
- Le script demande le PAT → coller le token `ghp_...` → Entrée
- Le script configure tout automatiquement :
  - ✅ Stocke le PAT dans Windows Credential Manager
  - ✅ Crée le script de démarrage dans WSL
  - ✅ Installe le runner GitHub Actions
  - ✅ Crée une tâche Windows pour le démarrage automatique
  - ✅ Démarre le runner immédiatement

#### Ce qui se passe après

```
Redémarrage Windows
        ↓
Tâche Windows "GitHubActionsRunner-DevHub" se déclenche
        ↓
WSL démarre + runner s'enregistre automatiquement via API GitHub
        ↓
Runner visible "online" sur GitHub → prêt à recevoir des jobs
```

Vérifier que le runner est actif :
**https://github.com/Mathis-Lefebvre/tp-argocd/settings/actions/runners**

---

### 2. Déployer l'infrastructure

1. Aller sur **https://github.com/Mathis-Lefebvre/tp-argocd/actions**
2. Cliquer sur **"🚀 Déployer l'infrastructure"**
3. Cliquer **Run workflow**
4. Options disponibles :

| Option | Défaut | Description |
|---|---|---|
| Nom du cluster | `devhub` | Nom du cluster Kind à créer |
| Passer le build des images | `false` | Réutiliser les images déjà buildées |
| Bootstrapper les apps ArgoCD | `true` | Créer la Root App (App of Apps) |

5. Cliquer **Run workflow** → suivre la progression dans les logs

Le workflow exécute dans l'ordre :
- ✅ Vérification des outils
- ✅ Création du cluster Kind
- ✅ Build & import des images Docker
- ✅ Installation Ingress-NGINX + ArgoCD
- ✅ Bootstrap App of Apps
- ✅ Affichage du résumé avec les URLs

---

### 3. Détruire l'infrastructure

1. Aller sur **https://github.com/Mathis-Lefebvre/tp-argocd/actions**
2. Cliquer sur **"🗑️ Détruire l'infrastructure"**
3. Cliquer **Run workflow**
4. Dans le champ **"Tapez DESTROY pour confirmer"** → saisir `DESTROY`
5. Cliquer **Run workflow**

> Le runner continue de tourner après la destruction — il reste disponible pour un prochain déploiement.

---

## Credentials & URLs

### ArgoCD

| Paramètre | Valeur |
|---|---|
| URL | http://argocd.devhub.local |
| Login admin | `admin` |
| Mot de passe admin | *Généré aléatoirement* (voir ci-dessous) |
| Login developer | `developer` |
| Mot de passe developer | `developerpassword` |

#### 🔑 Comment récupérer le mot de passe de l'admin ?

Le mot de passe change à chaque fois que tu recrées le cluster. Pour l'obtenir :

* **Méthode 1 (Ligne de commande WSL) :**
  ```bash
  make argocd-password
  ```
* **Méthode 2 (Sans commande) :**
  Va sur GitHub Actions, clique sur ton dernier déploiement vert, déroule le job **Bootstrap App of Apps** puis l'étape **Résumé final** : le mot de passe est affiché en clair !

### URLs des services

| Service | URL |
|---|---|
| ArgoCD UI | http://argocd.devhub.local |
| Annuaire (dev) | http://annuaire.devhub.local |
| Planning (dev) | http://planning.devhub.local |
| Notif (dev) | http://notif.devhub.local |
| Preview branch | http://annuaire-feature-demo-prof.devhub.local |

### RBAC — Droits du compte developer

| Action | annuaire-* | planning-* | notif-* |
|---|---|---|---|
| Lire / voir | ✅ | ✅ | ✅ |
| Synchroniser | ✅ | ❌ | ❌ |

---

## Structure du dépôt

```
devhub-campus/
├── .github/
│   └── workflows/
│       ├── build.yml              # CI : build & push images sur GHCR
│       ├── infra-deploy.yml       # Déployer l'infra depuis GitHub
│       └── infra-destroy.yml      # Détruire l'infra depuis GitHub
│
├── cluster/
│   └── kind-config.yaml           # Config cluster Kind (2 nœuds)
│
├── platform/
│   ├── argocd/
│   │   └── values.yaml            # Config ArgoCD (RBAC, notifications)
│   ├── bootstrap/
│   │   └── root-app.yaml          # Root Application (App of Apps)
│   ├── projects/
│   │   └── devhub.yaml            # AppProject (périmètre RBAC)
│   └── apps/
│       ├── dev/                   # Applications par service (env stable)
│       │   ├── annuaire-dev.yaml
│       │   ├── planning-dev.yaml
│       │   └── notif-dev.yaml
│       └── sets/
│           └── preview-appset.yaml  # ApplicationSet (previews par branche)
│
├── services/
│   ├── annuaire/                  # Frontend Node.js + Helm chart
│   ├── planning/                  # API Python + Helm chart
│   └── notif/                     # Service Go + Helm chart
│
├── scripts/
│   ├── lancer-setup.bat           # Double-cliquer pour configurer le runner
│   ├── setup.ps1                  # Script PowerShell de configuration runner
│   └── install-runner.sh          # Alternative CLI : make runner-install TOKEN=...
│
├── Makefile                       # Commandes de gestion du cluster
├── RAPPORT.md                     # Compte-rendu du TP
└── ORAL_PREPARATION.pdf           # Support de présentation orale
```

---

## Commandes utiles

### Cluster

```bash
make cluster-up              # Créer le cluster Kind
make cluster-down            # Détruire le cluster
make tools-check             # Vérifier les outils installés
```

### ArgoCD CLI

```bash
# Login admin
argocd login argocd.devhub.local --insecure \
  --username admin --password DevHubPassword123!

# Login developer (accès restreint)
argocd login argocd.devhub.local --insecure \
  --username developer --password developerpassword

# Lister les applications
argocd app list

# Synchroniser une application
argocd app sync annuaire-dev

# Vérifier le statut
argocd app get annuaire-dev --refresh
```

### Runner GitHub Actions

```bash
make runner-status           # Vérifier l'état du runner
make runner-stop             # Arrêter et désinstaller le runner
make runner-install TOKEN=<token>  # Réinstaller le runner (si token expiré)
```

### Git Daemon (pour ArgoCD local)

```bash
# Démarrer le daemon Git (ArgoCD en lit les sources)
git daemon --base-path=. --export-all \
           --enable=receive-pack --reuseaddr --port=9000 --verbose &

# Arrêter le daemon
pkill -f "git daemon"
```

---

## Dépannage

### Le runner n'apparaît pas sur GitHub

```bash
# Vérifier que le runner tourne dans WSL
make runner-status

# Consulter les logs
cat ~/actions-runner/autostart.log

# Relancer manuellement
~/runner-autostart.sh
```

### Le workflow échoue avec "No runner matching"

Le runner n'est pas démarré. Deux causes possibles :
1. **WSL ne s'est pas lancé** → ouvrir un terminal WSL manuellement
2. **La tâche Windows n'a pas démarré** → dans le Planificateur de tâches Windows, chercher `GitHubActionsRunner-DevHub` et cliquer **Exécuter**

### ArgoCD UI inaccessible

```bash
# Vérifier les pods ArgoCD
kubectl get pods -n argocd

# Vérifier l'ingress
kubectl get ingress -n argocd

# Vérifier le fichier hosts Windows
# C:\Windows\System32\drivers\etc\hosts
# doit contenir : 127.0.0.1  argocd.devhub.local
```

### Applications ArgoCD en OutOfSync

```bash
# Vérifier que le daemon Git tourne
ps aux | grep "git daemon"

# Redémarrer le daemon
pkill -f "git daemon" 2>/dev/null || true
git daemon --base-path=. --export-all \
           --enable=receive-pack --reuseaddr --port=9000 --verbose &

# Forcer la synchronisation
argocd app sync root --prune
```

### Réinitialiser complètement

```bash
# Tout détruire et repartir de zéro
make cluster-down
# Puis depuis GitHub → Actions → "🚀 Déployer l'infrastructure"
```

---

## Référence

- **Polycopié TP** : `../POLYCOPIE-ARGOCD.pdf`
- **Rapport TP** : `RAPPORT.md`
- **Support oral** : `ORAL_PREPARATION.pdf`
- **ArgoCD Docs** : https://argo-cd.readthedocs.io
- **GitHub Actions** : https://docs.github.com/actions
- **Kind** : https://kind.sigs.k8s.io
