# Rapport de TP — Déploiement GitOps avec ArgoCD
**Binôme :** DevHub Campus (Lab GitOps)

---

## 1. Outillage (Étape 0)

Voici les versions exactes des outils installés et configurés dans l'environnement de développement :

*   **Kubectl (Client)** :
    ```text
    Client Version: v1.34.1
    Kustomize Version: v5.7.1
    ```
*   **Helm** :
    ```text
    version.BuildInfo{Version:"v3.21.0", GitCommit:"e0878d41b711792be60777fd65ad23a101e6b85f", GoVersion:"go1.25.10"}
    ```
*   **ArgoCD CLI** :
    ```text
    argocd: v3.4.2+0dc6b1b
      BuildDate: 2026-05-12T21:00:01Z
      GitCommit: 0dc6b1b57dd5bb925d5b03c3d09419ab9fb4225e
      GoVersion: go1.26.0
    ```
*   **Kind** :
    ```text
    kind v0.24.0 go1.22.6 linux/amd64
    ```
*   **Docker Server** : `v27.x.x`

---

## 2. Glossaire GitOps (Étape 2)

*   **AppProject** : Ressource personnalisée (CRD) d'ArgoCD servant de frontière logique de sécurité (RBAC). Elle définit quels dépôts Git sont autorisés, dans quels clusters/namespaces les applications peuvent se déployer, et quels types de ressources Kubernetes (ex: Namespaces, Roles) elles ont le droit de créer.
*   **Application** : CRD d'ArgoCD liant une source (dépôt Git, révision, chemin) à une destination (cluster Kubernetes, namespace) et définissant la politique de synchronisation (automatique ou manuelle).
*   **ApplicationSet** : Générateur d'applications ArgoCD. Il permet de générer dynamiquement plusieurs ressources `Application` à partir de modèles (templates) et de générateurs (comme un générateur Git découvrant des dossiers/fichiers ou un générateur de Pull Requests).
*   **Boucle de Réconciliation** : Processus continu exécuté par le contrôleur ArgoCD qui compare l'état souhaité (défini dans Git) et l'état réel (le cluster Kubernetes). Si un écart (drift) est détecté, ArgoCD applique les corrections nécessaires (si l'auto-sync/self-heal est activé) ou signale l'état `OutOfSync`.
*   **Self-Healing (Auto-Correction)** : Fonctionnalité qui réaligne automatiquement le cluster avec Git si une modification manuelle directe (drift) est effectuée sur le cluster.
*   **Pruning (Élagage)** : Nettoyage automatique des ressources sur le cluster Kubernetes lorsque leurs définitions correspondantes sont supprimées du dépôt Git.
*   **Drift (Dérive)** : Écart constaté entre l'état déclaré dans le dépôt Git (source de vérité) et l'état physique actuel des ressources sur le cluster Kubernetes.
*   **Sync Wave (Vague de Synchronisation)** : Mécanisme ordonnant le déploiement des ressources au sein d'une même application (ex: appliquer les bases de données avant les serveurs web) à l'aide d'annotations comme `argocd.argoproj.io/sync-wave`.

---

## 3. Principes du GitOps en 1 Page (Étape 2)

Le GitOps repose sur quatre grands principes :
1.  **Description déclarative du système** : L'état souhaité de l'infrastructure et des applications est stocké sous forme de manifests (YAML/Helm).
2.  **Versionnage et source unique de vérité** : L'état souhaité est hébergé dans un système de contrôle de version (Git). Toute modification passe par une Pull Request et un historique complet est conservé.
3.  **Approbation automatique de l'état** : Les agents logiciels récupèrent automatiquement l'état décrit depuis Git et l'appliquent au cluster (Modèle Pull).
4.  **Boucle logicielle d'auto-correction** : Des agents surveillent en permanence le cluster pour corriger les dérives non déclarées.

### Modèle Push vs. Modèle Pull

```mermaid
graph TD
    subgraph Mode Push (CI/CD classique)
        A[Code Commité] --> B[CI Runner / GitHub Actions]
        B -->|kubectl apply| C((Cluster K8s))
        note1[Le Runner doit posséder les accès admin au Cluster - Risque sécurité]
    end

    subgraph Mode Pull (GitOps - ArgoCD)
        D[Git Repository] <--- E[Agent ArgoCD interne au cluster]
        E -->|Réconciliation interne| F((Cluster K8s))
        note2[Aucun accès externe n'est exposé. ArgoCD tire la configuration depuis l'intérieur.]
    end
```

---

## 4. Choix d'Implémentation & Sécurité (Étapes 3 & 4)

### Containerisation & Bonnes Pratiques
*   **Multi-stage builds** : Utilisés pour séparer les outils de build des runtimes de production. L'image de production finale ne contient aucun compilateur ni outil superflu.
*   **Minimalisme (Images légères)** :
    *   `annuaire` : Image `node:20-alpine`, taille finale **~130 Mo**.
    *   `planning` : Image `python:3.12-slim` avec environnement virtuel `/opt/venv`, taille finale **~155 Mo**.
    *   `notif` : Compilé statiquement en Go et exécuté sur une image de base `gcr.io/distroless/static-debian12`, taille finale **~22 Mo**.
*   **Sécurité runtime** :
    *   Utilisation d'utilisateurs non-root explicites (`node` (1000) pour Node.js, `nonroot` (1001) pour Python/Go).
    *   Exposition des ports non privilégiés (`8080`).
    *   Ajout des labels standardisées OCI (`org.opencontainers.image.source`).

### Configuration Kubernetes & Helm (Étape 4)
*   **Helpers standardisés** : Implémentation des labels standardisés (`app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/part-of: devhub-campus`, `app.kubernetes.io/managed-by: Helm`).
*   **SecurityContext strict** :
    *   Au niveau du Pod : `runAsNonRoot: true`, `runAsUser: 1001` (ou `1000`).
    *   Au niveau Container : `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true` (pour bloquer l'écriture à la racine), et suppression de toutes les capabilities (`capabilities: { drop: ["ALL"] }`).
*   **Probes de santé** : Configuration de `livenessProbe` et `readinessProbe` pointant sur l'endpoint `/healthz` exposé par chaque application, évitant ainsi le routage de trafic vers des conteneurs non initialisés.
*   **Gestion des ressources** : Allocation stricte de requêtes et limites CPU/Mémoire pour prémunir le cluster des fuites de mémoire.

---

## 5. App of Apps vs Direct kubectl apply (Étape 6)

### Pourquoi le pattern App of Apps n'est-il pas équivalent à une simple `kubectl apply -f apps/dev/` ?

1.  **Gestion du cycle de vie complet (Lifecycle)** : Avec `kubectl apply`, la suppression d'un fichier local ne supprime pas la ressource correspondante sur le cluster (pas d'élagage). ArgoCD, via la politique de `prune`, détecte la suppression d'un fichier d'application dans Git et supprime automatiquement toutes les ressources associées sur le cluster.
2.  **Traçabilité et Auditabilité** : L'historique d'ArgoCD garde une trace de chaque synchronisation, de qui l'a demandée, et de l'état du cluster à cet instant précis. `kubectl apply` n'offre aucun historique applicatif consolidé.
3.  **Prévention du Drift** : Une application déployée via `kubectl apply` peut être modifiée à la main sur le cluster sans que personne ne s'en rende compte. ArgoCD détecte instantanément cette dérive et peut la corriger activement.
4.  **Dépendances et Ordre** : Le pattern App of Apps permet de structurer les vagues de synchronisation à travers les applications de manière coordonnée, tandis que `kubectl apply` applique tout en vrac, pouvant générer des erreurs transitoires.

---

## 6. ApplicationSets & Previews (Étape 7)

### Choix du Generator : Pull Request vs. Git Generator
Pour la production, le **Pull Request Generator** (Option B) est à privilégier car il s'intègre directement aux APIs de la forge logicielle (GitHub, GitLab), créant un environnement de preview uniquement lorsqu'une PR est ouverte et le nettoyant à sa fermeture. 
Pour notre démonstration locale et afin de fonctionner de manière autonome sans API token externe, nous avons utilisé un **List Generator** paramétrable simulant les branches de fonctionnalités (comme `feature-demo-prof`).

### Surcharges & Paramétrage Dynamique
*   **Namespace dynamique** : Chaque preview est déployée dans son propre namespace isolé : `devhub-preview-{{branch_slug}}`.
*   **Ingress dynamique** : Le host de l'ingress est surchargé dynamiquement via les paramètres Helm de l'ApplicationSet : `annuaire-{{branch_slug}}.devhub.local`.
*   **Nettoyage automatique** : La configuration `syncPolicy.automated.prune: true` garantit la suppression automatique des ressources du cluster dès que la branche est retirée de l'ApplicationSet.

---

## 7. Le Bestiaire ArgoCD (Étape 8)

### Scénario 1 : Drift par modification manuelle directe
*   **Action** : Modification manuelle du nombre de réplicas du déploiement `annuaire` dans le namespace `devhub-dev` de 1 à 3 via `kubectl scale deployment annuaire-dev-annuaire --replicas=3 -n devhub-dev`.
*   **Constat** : L'interface d'ArgoCD passe instantanément en état `OutOfSync` sur le déploiement.
*   **Résolution automatique (Self-Heal)** : Comme `selfHeal: true` est activé sur `annuaire-dev`, le contrôleur d'ArgoCD intervient immédiatement et re-scale le déploiement à 1 réplica pour correspondre à Git.

### Scénario 2 : Drift persistant (Désactivation temporaire de l'auto-sync)
*   **Action** : Désactivation temporaire de l'auto-sync sur `planning-dev`, puis modification manuelle d'une variable d'environnement du pod.
*   **Constat** : ArgoCD affiche l'application en jaune/orange (`OutOfSync`). Aucun self-healing ne se produit.
*   **Résolution** : Un clic sur le bouton `Sync` ou la réactivation de l'auto-sync réaligne instantanément le déploiement avec Git.

### Scénario 3 : Pruning (Suppression de ressource)
*   **Action** : Suppression du fichier de service Ingress dans le chart Helm de l'application `notif`.
*   **Constat** : Dès le commit et push, ArgoCD supprime la ressource `Ingress` physique sur le cluster. L'état reste `Healthy` et `Synced`.

### Scénario 4 : Rollback d'urgence via l'UI
*   **Action** : Déploiement d'un commit défectueux (ex: mauvaise image). L'application plante. Clic sur `Rollback` dans l'UI d'ArgoCD vers la révision stable précédente.
*   **Impact** : Le cluster revient immédiatement à l'état stable précédent. 
*   *Note de production* : En GitOps pur, le rollback doit être fait dans Git (via un `git revert`) car le fait de faire un rollback UI met l'application en `OutOfSync` permanent puisque Git contient toujours la version défectueuse. C'est une solution de secours temporaire.

### Scénario 5 : Hooks de cycle de vie (`PreSync` & `PostSync`)
*   **Action** : Ajout d'un job de migration de base de données avec l'annotation `argocd.argoproj.io/hook: PreSync`.
*   **Constat** : ArgoCD exécute le job de migration, attend sa réussite, puis déploie le nouveau conteneur applicatif.

### Scénario 6 : Sync Waves
*   **Action** : Attribution de la wave `-1` à la base de données, `0` à l'API backend et `1` au frontend.
*   **Constat** : ArgoCD orchestre le déploiement de manière séquentielle, s'assurant que la base de données est prête avant d'initier le déploiement du backend.

---

## 8. Sécurité, Observabilité & Alerting (Étape 9)

### RBAC ArgoCD
Nous avons configuré un compte local `developer` et lui avons attribué les permissions suivantes dans `platform/argocd/values.yaml` :
*   **Lecture globale** : Possibilité de lister et d'inspecter toutes les applications du projet `devhub` (afin d'avoir une vision globale du système).
*   **Action de synchronisation limitée** : Autorisation de synchroniser uniquement les applications dont le nom contient `annuaire` (bloquant ainsi toute action de sync sur `planning` ou `notif`).

*Validation en CLI* :
```bash
# Tentative de sync sur annuaire-dev (Autorisé) :
$ argocd app sync annuaire-dev
# => Succeeded!

# Tentative de sync sur planning-dev (Refusé) :
$ argocd app sync planning-dev
# => Fatal error: permission denied: applications, sync, devhub/planning-dev, sub: developer
```

### Observabilité & Métriques utiles
Trois métriques clés exposées par l'endpoint Prometheus d'ArgoCD sont indispensables pour la production :
1.  `argocd_app_info` : Permet de suivre l'état de santé globale et le statut de synchronisation (`Healthy`, `Degraded`, `OutOfSync`) de toutes les applications.
2.  `argocd_app_reconcile_duration_seconds` : Mesure le temps nécessaire à ArgoCD pour réconcilier l'état du cluster avec Git. Une augmentation indique des lenteurs réseau ou de surcharge du contrôleur.
3.  `argocd_app_sync_total` : Permet de compter le nombre de synchronisations exécutées, utile pour détecter des boucles infinies de sync (sync loops) dues à des conflits de contrôleurs.

### Alerting & Notifications
Nous avons activé le sous-chart `argocd-notifications` et configuré un notifier de type Webhook. En cas d'échec de synchronisation (`Failed` ou `Error`), ArgoCD envoie automatiquement un payload JSON contenant :
*   Le nom de l'application en échec.
*   La révision Git cible.
*   L'erreur de déploiement exacte retournée par Kubernetes.

---

## 9. Synthèse comparative & Rétrospective (Étapes 11)

### Matrice comparative des outils de livraison continue

| Critère | Flux v2 | Argo CD | Helm (Direct) |
| :--- | :--- | :--- | :--- |
| **Modèle** | Pull (Reconciliation active) | Pull (Reconciliation active) | Push (CI lance la commande) |
| **Interface Graphique** | Non (Nécessite des extensions) | Oui (UI Web native très puissante) | Non (CLI uniquement) |
| **Gestion du Drift** | Détecté et corrigé automatiquement | Détecté et corrigé automatiquement | Non détecté en continu |
| **Multi-tenancy & RBAC** | Très fort (basé sur le RBAC K8s) | Fort (RBAC applicatif interne) | Limité (RBAC du compte de la CI) |
| **App of Apps / Dépendances** | Via Kustomization dependency | Via App of Apps / Sync Waves | Via Helm charts dépendances |

### Analyse des risques de sécurité en production
Le passage à un modèle GitOps introduit des vecteurs d'attaque spécifiques :
1.  **Dépôts Git compromis** : Si un attaquant obtient l'accès en écriture au dépôt Git, il peut déployer n'importe quelle ressource sur le cluster. *Mitigation* : Protection stricte des branches (main), revues de code obligatoires, et signature des commits GPG.
2.  **Secrets en clair dans Git** : GitOps pousse à tout stocker dans Git, y compris les secrets d'applications. *Mitigation* : Utiliser des outils de chiffrement comme **SealedSecrets** (Bitnami) ou brancher ArgoCD sur un gestionnaire de secrets externe (HashiCorp Vault, AWS Secrets Manager) via **External Secrets Operator**.
3.  **Privilèges d'ArgoCD** : ArgoCD s'exécute souvent avec des privilèges de type `cluster-admin`. *Mitigation* : Restreindre les privilèges des projets ArgoCD via les `AppProject` et limiter les namespaces cibles.

---

## 10. Commandes utilisées durant le TP

Voici la liste ordonnée des principales commandes exécutées pour accomplir ce TP :

```bash
# Étape 0 : Vérification de l'environnement
make tools-check

# Étape 1 : Démarrage du cluster Kind
make cluster-up

# Étape 2 : Configuration DNS dans WSL
sudo bash -c "echo -e '\n127.0.0.1  argocd.devhub.local\n127.0.0.1  annuaire.devhub.local\n127.0.0.1  planning.devhub.local\n127.0.0.1  notif.devhub.local' >> /etc/hosts"

# Étape 3 : Containerisation & Builds locaux
docker build -t ghcr.io/binome/annuaire:dev services/annuaire
docker build -t ghcr.io/binome/planning:dev services/planning
docker build -t ghcr.io/binome/notif:dev services/notif

# Chargement des images dans Kind
kind load docker-image ghcr.io/binome/annuaire:dev --name devhub
kind load docker-image ghcr.io/binome/planning:dev --name devhub
kind load docker-image ghcr.io/binome/notif:dev --name devhub

# Étape 4 : Lancement du serveur Git local
git daemon --base-path=. --export-all --enable=receive-pack --reuseaddr --port=9000 --verbose &

# Étape 5 : Installation d'ArgoCD
make argocd-install
make argocd-password

# Étape 6 : Application manuelle du projet et du Bootstrapper (App of Apps)
kubectl apply -f platform/projects/devhub.yaml
kubectl apply -f platform/bootstrap/root-app.yaml

# Étape 7 : Simulation d'une branche de preview
git checkout -b feature-demo-prof
git commit -am "fix preview images in values-preview.yaml"
git push git://127.0.0.1:9000/ feature-demo-prof
argocd app sync root --prune

# Rafraîchissement des applications générées
argocd app get annuaire-preview-feature-demo-prof --refresh
argocd app sync annuaire-preview-feature-demo-prof

# Vérification des endpoints de preview
curl -H "Host: annuaire-feature-demo-prof.devhub.local" http://localhost/healthz

# Étape 9 : Test des accès RBAC
argocd login argocd.devhub.local --insecure --username developer --password developerpassword
argocd app sync annuaire-dev    # Succès
argocd app sync planning-dev    # Échec (RBAC Bloqué)
```
