# Infrastructure — Construction d'une infrastructure moderne, du réseau à la supervision

**Auteur :** `clecart` — **Filière :** Master · Green IT — **Pile (héritée de code-keeper, à compléter) :** Docker 29.9.3 · Docker Compose 5.7.1 · GitLab CE 19.5.1 · GitLab Runner 19.5.0 ·
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
4. [Application conteneurisée : Docker Compose](#4-application-conteneurisée--docker-compose)
5. [Architecture réseau](#5-architecture-réseau)
6. [Vérifier avant de pousser : la porte locale](#6-vérifier-avant-de-pousser--la-porte-locale)

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

| Sous-phase | Livrable | État | Preuve |
|---|---|---|---|
| 1 — Réseau & conteneurs | Application conteneurisée fonctionnelle | ☑ | [section 4](#4-application-conteneurisée--docker-compose), `Scripts/compose-test.sh` |
| 1 — Réseau & conteneurs | Documentation d'architecture réseau | ◐ | [section 5](#5-architecture-réseau) : local mesuré ; AWS décrit d'après le code, mesures au déploiement |
| 2 — Orchestration & cloud | Application orchestrée sur cluster Kubernetes | ☐ | |
| 2 — Orchestration & cloud | Déploiement sur AWS | ☐ | |
| 2 — Orchestration & cloud | Analyse des coûts d'infrastructure | ☐ | |
| 3 — CI/CD & IaC | Pipeline CI/CD complet fonctionnel | ☐ | |
| 3 — CI/CD & IaC | Infrastructure provisionnée via Terraform | ☐ | |
| 4 — Supervision & sécurité | Tableau de bord de supervision opérationnel | ☐ | |
| 4 — Supervision & sécurité | Rapport d'audit de sécurité | ☐ | |
| Validation finale | Soutenance technique devant jury (projet fil rouge) | ☐ | |

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

## 4. Application conteneurisée : Docker Compose

`compose.yaml` lance l'application entière sur le poste, à partir des recettes
du dépôt : les images qui tournent en local sont celles que la CI construit et
qu'EKS déploie.

```bash
cp .env.example .env                  # puis remplacer chaque CHANGE_ME (openssl rand -hex 24)
docker compose up -d --build --wait   # construit, démarre, attend que tout soit sain
Scripts/compose-test.sh               # 92 vérifications, sortie en échec si une tombe
curl http://127.0.0.1:3000/api/movies/
docker compose down                   # ajouter -v pour effacer aussi les données
```

| Service | Recette | Rôle | Port | Mémoire mesurée au repos / limite | Image |
|---|---|---|---|---|---|
| `api-gateway` | `repos/api-gateway-app` | point d'entrée : `/api/movies` vers inventory-app, `/api/billing` vers RabbitMQ | 3000, publié sur `127.0.0.1` | 21 Mio / 256 Mio | 121 Mo |
| `inventory-app` | `repos/inventory-app` | API REST du catalogue de films | 8080 | 22 Mio / 256 Mio | 115 Mo |
| `billing-app` | `repos/billing-app` | consomme les commandes de la file `billing_queue` | 8080 | 22 Mio / 256 Mio | 116 Mo |
| `inventory-db` | `repos/infra/images/inventory-database` | PostgreSQL 17, table `movies` | 5432 | 22 Mio / 384 Mio | 73 Mo |
| `billing-db` | `repos/infra/images/billing-database` | PostgreSQL 17, table `orders` | 5432 | 28 Mio / 384 Mio | 73 Mo |
| `rabbitmq` | `repos/infra/images/rabbitmq-server` | courtier AMQP, file durable `billing_queue` | 5672 | 85 Mio / 512 Mio | 204 Mo |

Mesures du 16 novembre 2026 sur le poste de développement (`docker stats`,
`docker image inspect`) : 200 Mio de mémoire pour toute la pile au repos ;
construction sans cache en 10 s, l'image de base Alpine déjà présente ;
démarrage jusqu'à l'état sain des six services en 19 s.

**Choix et leur motif**

- **Les noms de service sont ceux de Kubernetes** (`inventory-db`, `billing-db`,
  `rabbitmq`) : les applications reçoivent les mêmes variables d'environnement
  en local et dans le cluster.
- **Le durcissement reprend celui des manifestes** : système de fichiers
  racine en lecture seule, toutes les capacités Linux retirées,
  `no-new-privileges`, utilisateur non-root fixé par la recette, `requests` et
  `limits` recopiés en réservations et limites. Les répertoires où un service
  doit écrire sont des volumes nommés (données) ou des `tmpfs` (socket,
  configuration générée au démarrage).
- **Les secrets viennent de `.env`**, que Git ignore ; Compose refuse de
  démarrer si l'un manque (`${VAR:?}`).
- **RabbitMQ reçoit la taille de sa mémoire par l'environnement**
  (`RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS`) : il calcule sinon son seuil d'alarme
  sur la mémoire de l'hôte, et serait tué par sa limite de 512 Mio avant de
  freiner les producteurs. Mesuré : seuil de 0,322 Go, soit 0,6 × 512 Mio.
  Le fichier de configuration du cluster (ConfigMap) n'est pas repris :
  Compose refuse une configuration écrite en ligne dans un service en lecture
  seule.
- **Alternative écartée** : les images officielles `postgres` et `rabbitmq`.
  Le job `integration-test` les emploie comme services GitLab ; la pile locale
  prend les images que le cluster déploie, pour éprouver ce qui part en
  production.

**Preuve** : `Scripts/compose-test.sh`, sur la pile lancée. Il vérifie
l'entrée (publiée sur la seule boucle locale), le catalogue (création puis
recherche d'un film), la facturation (la commande arrive dans `billing-db`),
la file d'attente (`billing-app` arrêté, la commande attend dans RabbitMQ puis
s'enregistre à son retour), l'isolement réseau sur les 30 couples de services
(section 5) et le durcissement de chaque conteneur. Le test a été éprouvé à
l'envers : `billing-app` ajouté au réseau de publication fait tomber deux
vérifications, `read_only: false` sur une base en fait tomber une.

---

## 5. Architecture réseau

### 5.1 Circulation d'une requête

| Flux | De | Vers | Protocole, port |
|---|---|---|---|
| Lecture et écriture du catalogue | client | `api-gateway` | HTTP 3000 |
| | `api-gateway` (mandataire) | `inventory-app` | HTTP 8080 |
| | `inventory-app` | `inventory-db` | PostgreSQL 5432 |
| Commande | client | `api-gateway` | HTTP 3000 |
| | `api-gateway` (publie) | `rabbitmq`, file `billing_queue` | AMQP 0-9-1, 5672 |
| | `billing-app` (consomme) | `rabbitmq` | AMQP 0-9-1, 5672 |
| | `billing-app` | `billing-db` | PostgreSQL 5432 |

La commande est asynchrone : `api-gateway` répond dès que RabbitMQ a reçu le
message, et la commande attend dans la file durable tant que `billing-app` est
arrêté.

### 5.2 En local : un réseau par flux

```mermaid
flowchart LR
  host(["hôte<br/>127.0.0.1:3000"]) -- edge --> gw[api-gateway]
  gw -- inventory-api --> inv[inventory-app]
  inv -- inventory-data --> invdb[(inventory-db)]
  gw -- billing-publish --> mq[[rabbitmq]]
  bill[billing-app] -- billing-consume --> mq
  bill -- billing-data --> billdb[(billing-db)]
```

| Réseau | Interne | Membres | Flux porté |
|---|---|---|---|
| `edge` | non | `api-gateway` | entrée depuis l'hôte, sortie vers Internet |
| `inventory-api` | oui | `api-gateway`, `inventory-app` | mandataire HTTP |
| `inventory-data` | oui | `inventory-app`, `inventory-db` | SQL du catalogue |
| `billing-publish` | oui | `api-gateway`, `rabbitmq` | publication des commandes |
| `billing-consume` | oui | `billing-app`, `rabbitmq` | consommation des commandes |
| `billing-data` | oui | `billing-app`, `billing-db` | SQL des commandes |

- **Deux services ne se joignent que s'ils partagent un réseau.** Docker isole
  les ponts entre eux, et son DNS ne résout un nom que sur les réseaux du
  demandeur. RabbitMQ porte deux réseaux pour que `api-gateway` et
  `billing-app` ne se voient pas.
- **Un réseau interne n'a pas de route hors de l'hôte** : seul `api-gateway`
  en a une, par `edge`. Une base compromise n'a aucune route vers Internet.
- **Seule l'entrée est publiée**, et sur la boucle locale de l'hôte : la pile
  n'est pas joignable depuis le réseau du poste.
- **Les adresses ne se fixent pas** : Docker attribue un sous-réseau à chaque
  réseau dans sa réserve (`172.20.0.0/16` à `172.26.0.0/16` sur le poste), et
  les services se trouvent par leur nom.

**Mesuré** par `Scripts/compose-test.sh` : pour chacun des 30 couples
ordonnés de services, une connexion TCP est tentée vers chaque adresse de la
cible, et pas seulement par son nom ; elle n'aboutit que pour les cinq paires
du schéma, et seulement sur l'adresse de leur réseau commun. L'absence de route
par défaut se lit dans `/proc/net/route` de chaque conteneur.

**Limite assumée** : un réseau Compose laisse passer les deux sens et tous les
ports, là où une NetworkPolicy filtre par sens et par port. En local,
`inventory-app` peut donc ouvrir une connexion vers `api-gateway:3000`,
`inventory-db` vers `inventory-app:8080`, `billing-db` vers `billing-app:8080`
et `rabbitmq` vers `api-gateway:3000` ; le cluster refuse ces quatre sens.

### 5.3 Sur AWS

Cette partie décrit ce que construit le code Terraform et Kubernetes du dépôt.
[CIBLE] Aucune sortie n'est encore capturée sur l'infrastructure réelle : les
captures (`aws ec2 describe-…`, `kubectl get networkpolicy`) s'ajoutent au
déploiement de la sous-phase 2.

**Plan d'adressage** : trois VPC aux plages disjointes, dans `eu-west-3`.

| VPC | Plage | Sous-réseaux | Sortie vers Internet | Code |
|---|---|---|---|---|
| outillage (GitLab, runner) | `10.100.0.0/24` | un public | passerelle Internet, une IP Elastic par machine, pas de NAT | `bootstrap/network.tf` |
| `movies-staging` | `10.0.0.0/16` | 2 privés `/19` (`10.0.0.0`, `10.0.32.0`), 2 publics `/24` (`10.0.96.0`, `10.0.97.0`), sur deux zones | une passerelle NAT | `repos/infra/terraform/modules/environment/vpc.tf` |
| `movies-prod` | `10.1.0.0/16` | même découpe | une passerelle NAT | idem |

- Les sous-réseaux privés sont larges parce que le VPC CNI donne à chaque pod
  une adresse du VPC.
- Une seule passerelle NAT par environnement, au lieu d'une par zone :
  0,05 USD de l'heure d'économie (tarif cité dans le code, à vérifier au
  calculateur AWS lors de l'analyse des coûts). En contrepartie, si la zone de
  la NAT tombe, les nœuds de l'autre zone ne tirent plus d'image.

**Chaîne d'entrée** : un seul point public, géré par AWS.

```text
client --HTTPS--> API Gateway (HTTP API, certificat TLS géré par AWS)
                  /api/*   : jeton d'accès Cognito exigé (autorisation JWT)
                  /health  : public
                  20 requêtes/s, rafales de 50
        --lien VPC--> ALB interne :80 (sous-réseaux privés, aucune adresse publique)
        --> chaque nœud :30080 (NodePort du Service api-gateway)
        --> kube-proxy --> un pod api-gateway :3000
```

| Groupe de sécurité | Entrée | Sortie |
|---|---|---|
| lien VPC | — | TCP 80 vers le groupe de l'ALB |
| ALB | TCP 80 depuis le groupe du lien VPC | TCP 30080 vers le groupe des nœuds |
| nœuds EKS | TCP 30080 depuis le groupe de l'ALB, plus les règles du module EKS | — |
| GitLab | 22, 80, 443 depuis les plages d'administration ; 80, 443 depuis l'équipe ; 443 depuis l'IP Elastic du runner | tout |
| runner | 22 depuis les plages d'administration | tout |

Le groupe par défaut du VPC d'outillage est vidé de ses règles : seuls les
groupes nommés s'appliquent.

**Dans le cluster** : toute connexion entrante est refusée, puis seuls les
cinq flux de la section 5.1 sont ouverts, port par port et dans un seul sens
(`repos/infra/platform/network-policies.yaml`, appliqué par le VPC CNI avec
`enableNetworkPolicy`).

**Administration** : l'API du cluster EKS n'est publique que pour les plages
de `eks_api_allowed_cidrs`, dont la validation refuse `0.0.0.0/0` ; les nœuds
passent par le point d'accès privé.

### 5.4 Du local au cluster

| Local (Compose) | AWS (EKS) |
|---|---|
| port publié sur `127.0.0.1:3000`, réseau `edge` | API Gateway, lien VPC, ALB interne, NodePort 30080 |
| un réseau interne par flux | une NetworkPolicy par service, refus par défaut |
| filtrage par appartenance à un réseau, deux sens, tous ports | filtrage par sens et par port |
| pas de route hors de l'hôte, sauf `api-gateway` | sortie de tous les nœuds par la passerelle NAT, sans filtrage sortant |
| DNS de Docker, par nom de service | CoreDNS, par nom de Service |

---

## 6. Vérifier avant de pousser : la porte locale

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
| `compose-config` | `compose.yaml` valide, lu avec `.env.example` | — |

Elle travaille sur une copie des fichiers que Git suit ou suivrait, n'écrit rien
dans le dépôt (elle le vérifie), va au bout de chaque étape et garde leur journal
dans `~/.local/state/infrastructure-gate/`. Durée mesurée : une minute environ,
dont la moitié pour `terraform init`.

Non rejoués : `semgrep-sast` et `sast-gate` (modèle de GitLab), `integration-test`
(services PostgreSQL et RabbitMQ), et les jobs qui demandent GitLab ou AWS
(construction des images, `plan`, `apply`, déploiements).

