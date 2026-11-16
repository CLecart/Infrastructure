# Infrastructure — Construction d'une infrastructure moderne, du réseau à la supervision

**Auteur :** `clecart` — **Filière :** Master · Green IT — **Pile (héritée de code-keeper, à compléter) :** Docker · GitLab CE 19.5.1 · GitLab Runner 19.5.0 ·
Ansible 2.21.5 · Terraform 1.16.6 (fournisseur AWS 6.69.1, modules VPC 6.7.3 et EKS 21.29.0) ·
Amazon EKS 1.36 · Helm · kube-prometheus-stack · Trivy 0.76.1 · TFLint 0.64.0 · Renovate 44.176.2 · Node.js 24

Ce document est à la fois le **compte-rendu** du projet et sa **documentation
complète**. Il reprend d'abord le sujet officiel, puis suit l'avancement des
livrables de chaque sous-phase.

> **Source du sujet** — Gitea Zone01 Normandie :
> [`vfrebourg/public` · `subjects/green-it/infrastructure/README.md`](https://zone01normandie.org/git/vfrebourg/public/src/branch/main/subjects/green-it/infrastructure/README.md)
> (branche `main`). Page du projet sur l'intra :
> <https://zone01normandie.org/intra/rouen/master/infrastructure?event=1311>.

---

## Sommaire

1. [Sujet](#1-sujet)
2. [Suivi des livrables](#2-suivi-des-livrables)
3. [Origine du code](#3-origine-du-code)
4. [Vérifier avant de pousser : la porte locale](#4-vérifier-avant-de-pousser--la-porte-locale)

---

## 1. Sujet

Bienvenue dans un parcours complet de construction d’une infrastructure moderne, de zéro jusqu’à un niveau professionnel.

#### Objectifs

L'objectif de ce projet est de maîtriser les outils et pratiques permettant de construire, déployer, automatiser et superviser une application dans un environnement professionnel.

#### Introduction

- Votre travail doit être structuré et documenté en français clair et technique.
- Chaque choix d’architecture doit être justifié.
- L’infrastructure doit être pensée comme un système complet, évolutif et reproductible.

Vous allez progressivement construire une infrastructure complète en parcourant toutes les couches d’un système moderne : réseau, conteneurisation, orchestration, automatisation et supervision.

Ce projet est découpé en plusieurs sous-phases.

---

#### Sous-phase 1 — Réseau & conteneurs

Vous commencez par comprendre la circulation de l’information dans un système d’information, puis vous mettez en place vos premiers environnements conteneurisés avec Docker.

L’objectif est de produire des images légères, reproductibles et prêtes à être déployées.

##### Livrable

- 1 application conteneurisée fonctionnelle
- 1 documentation d’architecture réseau

---

#### Sous-phase 2 — Orchestration & cloud

Vous déployez votre application à l’échelle avec Kubernetes sur une infrastructure AWS.

Vous apprenez à gérer les ressources, les namespaces, le scaling, et à analyser les coûts et impacts des choix d’infrastructure.

##### Livrable

- 1 application orchestrée sur cluster Kubernetes
- 1 déploiement sur AWS
- 1 analyse des coûts d’infrastructure

---

#### Sous-phase 3 — CI/CD & IaC

Vous automatisez l’ensemble du cycle de vie de l’application : tests, déploiement continu avec GitHub Actions ou GitLab CI, et provisionnement via Terraform.

L’infrastructure devient du code, versionnable, reproductible et détruisable proprement.

##### Livrable

- 1 pipeline CI/CD complet fonctionnel
- 1 infrastructure provisionnée via Terraform

---

#### Sous-phase 4 — Supervision & sécurité

Vous mettez en place la supervision de l’infrastructure avec Prometheus et Grafana.

Vous intégrez des pratiques DevSecOps : gestion des secrets, principe du moindre privilège, audit de vulnérabilités.

##### Livrable

- 1 tableau de bord de supervision opérationnel
- 1 rapport d’audit de sécurité

---

#### Validation finale

Une soutenance technique devant jury professionnel présentant un projet fil rouge intégrant l’ensemble des sous-phases.

---

#### Ce projet vous permettra de découvrir :

- La construction d’une infrastructure complète moderne.
- La conteneurisation et l’orchestration d’applications.
- Le déploiement cloud avec AWS et Kubernetes.
- L’automatisation CI/CD et l’infrastructure as code.
- La supervision et la sécurité en environnement DevSecOps.

---

## 2. Suivi des livrables

| Sous-phase | Livrable | État |
|---|---|---|
| 1 — Réseau & conteneurs | Application conteneurisée fonctionnelle | ☐ |
| 1 — Réseau & conteneurs | Documentation d'architecture réseau | ☐ |
| 2 — Orchestration & cloud | Application orchestrée sur cluster Kubernetes | ☐ |
| 2 — Orchestration & cloud | Déploiement sur AWS | ☐ |
| 2 — Orchestration & cloud | Analyse des coûts d'infrastructure | ☐ |
| 3 — CI/CD & IaC | Pipeline CI/CD complet fonctionnel | ☐ |
| 3 — CI/CD & IaC | Infrastructure provisionnée via Terraform | ☐ |
| 4 — Supervision & sécurité | Tableau de bord de supervision opérationnel | ☐ |
| 4 — Supervision & sécurité | Rapport d'audit de sécurité | ☐ |
| Validation finale | Soutenance technique devant jury (projet fil rouge) | ☐ |

---

## 3. Origine du code

Le socle du projet est importé tel quel du projet **code-keeper**
(`clecart/code-keeper`, commit `66ef390`, 22 octobre 2026), qui réunit déjà
l'application en microservices, l'infrastructure Terraform sur AWS (EKS), la
configuration Ansible de GitLab, les pipelines GitLab CI, les manifests Helm
(dont `kube-prometheus-stack`) et l'analyse de vulnérabilités Trivy.

- Seuls les fichiers suivis par git ont été importés (`git archive`) : aucun
  état Terraform, aucune variable locale, aucun secret Ansible ni preuve de test.
- Le compte-rendu et la fiche de révision d'origine sont conservés dans
  [docs/import/code-keeper/](docs/import/code-keeper/).
- Les ressources (AWS, Kubernetes, groupe GitLab) portent le nom de
  l'application qu'elles servent, un catalogue de films avec prise de
  commandes : **`movies`** (`movies-staging`, `movies/billing-app`,
  `movies-ci-infra`…). Le nom tient sous la limite de 32 caractères d'AWS pour
  le groupe cible de l'ALB (`movies-staging-api-gateway`, 26).

Les mêmes services figurent dans les projets antérieurs, qui restent des
références pour certaines sous-phases :

| Projet | Apport | Sous-phase |
|---|---|---|
| play-with-containers | Application sous Docker Compose | 1 |
| deep-in-net | Exercices réseau | 1 |
| orchestrator | Kubernetes (K3s) sous Vagrant | 2 |
| cloud-design | EKS, Terraform, coûts, supervision | 2, 4 |
| code-keeper | CI/CD, IaC, sécurité — **socle importé** | 2, 3, 4 |

---

## 4. Vérifier avant de pousser : la porte locale

Les pipelines GitLab ne tournent que dans le GitLab que le projet déploie.
Avant chaque push, `Scripts/ci-gate.sh` rejoue donc leurs contrôles sur le
poste, avec les mêmes images, épinglées par empreinte et lues dans les fichiers
de CI, et ajoute ce qu'aucun job ne vérifie.

```bash
Scripts/ci-gate.sh && git push
```

| Étape | Ce qu'elle vérifie | Job de CI repris |
|---|---|---|
| `no-silencing-directive` | aucune directive qui fait taire un outil | — |
| `every-image-pinned` | chaque image tirée par son empreinte | — |
| `shellcheck` | chaque script shell | — |
| `hadolint` | chaque recette Docker, images des bases comprises | `dockerfile-lint` |
| `terraform-validate` | `fmt -check` et `validate` (staging, prod, bootstrap) | `validate` |
| `tflint` | bonnes pratiques Terraform | `tflint` |
| `iac-scan` | mauvaises configurations HIGH et CRITICAL (Trivy) | `iac-scan` |
| `dependency-scan:<app>` | vulnérabilités corrigées et secrets (Trivy) | `dependency-scan` |
| `lint-and-test:<app>` | ESLint et tests unitaires | `lint`, `test` |
| `renovate-config` | configuration de Renovate | `validate-config` |

Elle travaille sur une copie des fichiers que Git suit ou suivrait, n'écrit rien
dans le dépôt (elle le vérifie), va au bout de chaque étape et garde leur journal
dans `~/.local/state/infrastructure-gate/`. Durée mesurée : une minute environ,
dont la moitié pour `terraform init`.

Non rejoués : `semgrep-sast` et `sast-gate` (modèle de GitLab), `integration-test`
(services PostgreSQL et RabbitMQ), et les jobs qui demandent GitLab ou AWS
(construction des images, `plan`, `apply`, déploiements).

