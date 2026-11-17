# Révision de l'audit — Infrastructure

Fiche de préparation de l'évaluation par un pair et de la soutenance devant le
jury. Le projet n'a pas de fiche d'audit séparée : l'évaluation porte sur le
sujet lui-même (`README.md`, section 1), ses quatre sous-phases et leurs
livrables. Les questions ci-dessous en sont tirées. Les détails et les preuves
sont dans le [README](README.md) ; chaque chiffre vient d'une capture rangée dans
le dossier local `preuves/`.

## Les chiffres à connaître

| Sujet | Valeur |
|---|---|
| Services | 6 : `api-gateway`, `inventory-app`, `billing-app`, `inventory-db`, `billing-db`, `rabbitmq` |
| Images | 73 à 204 Mo, Alpine 3.23 épinglée par empreinte, non-root, construction en plusieurs étapes |
| Pile Compose | 205 Mio de mémoire au repos ; construction sans cache 9 s ; saine en 17 s ; `Scripts/compose-test.sh` 92/92 |
| Réseau local | 6 réseaux Compose, dont 5 internes ; une seule entrée, sur `127.0.0.1:3000` |
| Réseau AWS | VPC staging `10.0.0.0/16` (2 privés `/19`, 2 publics `/24`, 2 zones), outillage `10.100.0.0/24`, prod prévue en `10.1.0.0/16` ; une NAT |
| Terraform | socle 54 ressources (59 s) ; staging 88 ressources (apply 11 min 53) |
| Ansible | GitLab et runner en 9 min 23 ; relancé : `changed=0` sur les 3 hôtes |
| Pipelines | `infra` n° 1 : 18 min jusqu'à staging ; applications : 2 min 13 à 3 min 40 du push au déploiement en staging |
| Tests | 101 tests unitaires (40, 39, 22) ; scénario de bout en bout 16/16 par l'URL publique ; RBAC 118/118 ; protections 9/9 |
| Scaling | HPA 2 → 5 réplicas en 30 à 45 s ; 3e nœud prêt 48 s après la demande, plafond de 3 tenu ; retour à 2 nœuds en 4 min 24 |
| Coûts | outillage ≈ 0,23 $/h, staging ≈ 0,39 $/h, séance ≈ 0,62 $/h ; 0 $ entre deux séances ; 9,79 $ dépensés sur les projets précédents, 190,21 $ de crédits restants |
| Sans coupure | 126/126 et 124/124 requêtes en HTTP 200 pendant un remplacement de pods ; 131/131 pendant la vidange d'un nœud |
| Sécurité | 6 images scannées par ECR sans vulnérabilité signalée ; 4 exceptions Trivy motivées ; aucune clé AWS dans les pipelines (OIDC) ; pod privilégié refusé par Pod Security |

## Déroulé de la démonstration

Avant l'évaluation : une séance complète ([README §8](README.md#8-une-séance-sur-aws-de-la-création-à-la-destruction)).
Durées mesurées le 17 novembre : socle 1 min, Ansible 9 min 23, pipeline `infra`
18 min, applications environ 6 min, soit environ 35 minutes de création, plus les
commandes à lancer. Après : `Scripts/teardown.sh`.

| Question | Ce que je montre |
|---|---|
| Le dépôt et sa documentation | l'arborescence, le README (sujet, suivi des livrables et leurs preuves), le manifeste `.agents/MANIFESTE.md` |
| L'application conteneurisée | `docker compose up -d --build --wait`, puis `Scripts/compose-test.sh` (92 vérifications) |
| L'architecture réseau | le schéma de la section 7 ; la matrice des 30 couples de `compose-test.sh` ; sur AWS : `aws ec2 describe-subnets`, `describe-route-tables`, `kubectl get networkpolicy -n movies` |
| L'orchestration et le scaling | `kubectl get pods,hpa,pdb -n movies -o wide` ; `Scripts/load-test.sh pods`, puis `nodes` |
| Le déploiement sur AWS | `Scripts/test-api.sh staging` (16/16) |
| Les coûts | README §10 ; `aws freetier get-account-plan-state --region us-east-1` ; Cost Explorer |
| Le pipeline CI/CD | GitLab : pipelines `infra` et applications, leurs jobs ; une modification de code jusqu'à staging |
| Terraform | le plan relu avant l'apply ; le `diff` de `envs/staging/main.tf` et `envs/prod/main.tf` |
| La supervision | `repos/infra/scripts/grafana.sh staging`, tableau « Namespace (Pods) » ; journaux dans CloudWatch |
| La sécurité | `Scripts/rbac-test.sh staging`, `Scripts/protection-test.sh` ; rôles IAM et leur confiance OIDC ; scans ECR ; `.trivyignore.yaml` |
| La fin de séance | `Scripts/teardown.sh` : l'inventaire des 17 régions répond qu'il ne reste rien |

## Les questions tirées du sujet

### Sous-phase 1 — Réseau et conteneurs

#### 1. Comment l'information circule-t-elle dans le système ?
Le client n'entre que par `api-gateway`. Une requête `/api/movies` est transmise
en HTTP à `inventory-app`, qui lit et écrit dans `inventory-db` (PostgreSQL).
Une commande `/api/billing` est publiée dans la file `billing_queue` de RabbitMQ
(AMQP) ; `billing-app` la consomme et l'enregistre dans `billing-db`. La commande
est asynchrone : la passerelle répond dès que RabbitMQ a reçu le message, et la
commande attend dans la file tant que `billing-app` est arrêté (prouvé en local et
sur staging). Sur AWS, le client passe d'abord par API Gateway en HTTPS, avec un
jeton Cognito, puis par le lien VPC, l'ALB interne et le NodePort des nœuds.

#### 2. Comment avez-vous conteneurisé l'application, et pourquoi ces images ?
Une recette par service, dans le dépôt : base Alpine 3.23 épinglée par son
empreinte, construction en plusieurs étapes (les dépendances de développement et
npm n'entrent pas dans l'image servie), utilisateur non-root, `tini` en PID 1,
sonde de santé. Les images pèsent 73 à 204 Mo. Elles sont reproductibles (versions
figées, `npm ci` sur le fichier de verrouillage) et prêtes à déployer : ce sont les
mêmes que la CI construit et qu'EKS exécute. `compose.yaml` les lance en local avec
le durcissement des manifestes Kubernetes : lecture seule, aucune capacité Linux,
`no-new-privileges`, limites de ressources.

#### 3. Décrivez l'architecture réseau.
En local, un réseau par flux autorisé : `edge` (seule entrée, sur la boucle locale),
`inventory-api`, `inventory-data`, `billing-publish`, `billing-consume`,
`billing-data`. Tous sont internes, sauf `edge` : seul `api-gateway` a une route
hors de l'hôte. Le test l'a mesuré sur les 30 couples de services, par adresse IP
et pas seulement par nom ; il a même trouvé une faille de ma première version
(passerelle et `billing-app` sur le même réseau), corrigée en séparant publication
et consommation. Sur AWS : un VPC par environnement, sous-réseaux privés pour les
nœuds et les pods, publics pour la NAT ; un seul point public (API Gateway), un ALB
interne que seul le lien VPC joint, des groupes de sécurité qui se citent l'un
l'autre, et dans le cluster un refus par défaut puis une NetworkPolicy par flux.
Limite assumée : un réseau Compose filtre par appartenance (deux sens, tous ports),
une NetworkPolicy par sens et par port.

### Sous-phase 2 — Orchestration et cloud

#### 4. Comment l'application est-elle orchestrée sur Kubernetes ?
Sur EKS 1.36, deux nœuds `c7i-flex.large` sur deux zones. L'espace `movies` porte
l'application, en Pod Security `restricted` (un pod privilégié y est refusé,
mesuré), avec un quota qui interdit tout load balancer créé hors de Terraform. `api-gateway` et `inventory-app` sont des
Deployments à 2 réplicas au moins, répartis sur les deux nœuds, avec un budget de
perturbation ; `billing-app`, les bases et RabbitMQ sont des StatefulSets à une
copie, les bases et RabbitMQ sur des disques gp3 chiffrés. Chaque conteneur déclare
ses `requests` et `limits`. La supervision vit dans `monitoring`, les journaux dans
`logging`.

#### 5. Comment le scaling fonctionne-t-il ?
Deux niveaux. Les HPA ajoutent des réplicas quand le processeur dépasse 60 % de la
réservation : sous charge, de 2 à 5 en 30 à 45 secondes, puis retour à 2 en moins
de 4 minutes. Le Cluster Autoscaler ajoute un nœud quand des pods ne trouvent pas de
place : décision 10 s après la demande, nœud prêt 48 s plus tard, plafond de 3 tenu
(`max size reached`), nœud retiré 4 min 24 après la fin du test.

#### 6. Comment l'application est-elle déployée sur AWS ?
Tout naît du code, en une séance : le socle (`bootstrap/`, Terraform depuis le
poste), GitLab et le runner (Ansible), puis le pipeline `infra` crée staging et sa
plateforme, et les pipelines des applications y déploient leurs images. Le plan est
relu avant chaque apply. Le scénario de bout en bout passe par l'URL publique HTTPS :
16/16, dont le refus sans jeton et avec un jeton forgé.

#### 7. Combien coûte l'infrastructure, et quels choix la tiennent ?
Tarifs relevés dans l'API de prix d'AWS (Paris) : outillage ≈ 0,23 $/h, staging
≈ 0,39 $/h, soit ≈ 0,62 $/h pour une séance ; oubliés allumés, ≈ 15 $ par jour. Rien
ne survit à une séance, socle compris : 0 $ entre deux séances. La facture le
confirme : 9,79 $ dépensés sur les projets précédents, uniquement les jours de
séance. Choix : une seule NAT, machines du plan gratuit, pas de clé KMS dédiée,
journaux gardés un jour, plafonds d'autoscaling, pas de production, destruction en
fin de séance contrôlée par l'inventaire des 17 régions ; budget de 10 $ avec
alertes.

### Sous-phase 3 — CI/CD et IaC

#### 8. Que fait le pipeline CI/CD ?
Pour chaque application : `build`, tests unitaires et d'intégration (vrais
PostgreSQL et RabbitMQ), SAST, Trivy, hadolint, ESLint ; l'image n'est construite,
scannée et poussée dans ECR que si tout est vert, puis déployée en staging ; la prod
attend une approbation humaine. Pour l'infrastructure : images de plateforme,
`init`, `validate` (`terraform validate`, TFLint, Trivy), plans des deux
environnements, apply de staging et sa plateforme, approbation, apply de la prod ;
avec `DESTROY=true`, le même chemin détruit. Seul `main` déploie, et seul un
Maintainer peut lancer un pipeline sur `main` (prouvé : 9/9).

#### 9. Pourquoi Terraform, et comment l'infrastructure reste-t-elle reproductible et destructible ?
L'infrastructure est décrite, relue et versionnée : staging et prod sont le même
module appelé deux fois, seuls le nom et la plage réseau changent. Versions figées
(Terraform, fournisseurs, modules, charts, images par empreinte), états séparés dans
S3 avec verrou, plan enregistré et appliqué tel quel. Destructible : tout ce qui
coûte est créé par Terraform, y compris l'ALB (un load balancer créé par Kubernetes
survivrait au cluster) ; `Scripts/teardown.sh` détruit staging puis le socle, et
l'inventaire prouve qu'il ne reste rien.

### Sous-phase 4 — Supervision et sécurité

#### 10. Comment l'infrastructure est-elle supervisée ?
Prometheus et Grafana dans le cluster (`kube-prometheus-stack`, 24 tableaux de
bord), sans adresse publique : accès par port-forward. Le tableau « Namespace
(Pods) » montre le processeur, les quotas et la mémoire de chaque pod ; la capture
du README a été prise pendant la montée en charge. Fluent Bit envoie les journaux
des conteneurs dans CloudWatch, un flux par pod, gardés un jour.

#### 11. Comment les secrets sont-ils gérés ?
Aucun secret dans le dépôt : coffre Ansible chiffré pour GitLab, mot de passe du
coffre hors du dépôt ; aucune clé AWS dans les pipelines (OIDC, identifiants
temporaires) ; mots de passe des bases et de RabbitMQ tirés au hasard dans le
cluster ; `.env` local ignoré par Git, sans lequel Compose refuse de démarrer.
Trivy cherche les secrets du code à chaque pipeline ; avant chaque push, la porte
passe gitleaks sur tout l'historique et sur les fichiers pas encore commités, et
un faux jeton y est arrêté, commité ou non.

#### 12. Comment le moindre privilège est-il appliqué ?
Un rôle IAM par projet GitLab, que seul le jeton de sa branche `main` peut prendre ;
le rôle `infra` ne peut créer que des rôles bornés par une limite de permissions, et
ne peut pas toucher au socle. Dans Kubernetes, un Role par application : son
pipeline ne modifie que ses propres objets (118/118). Dans GitLab, un Developer ne
peut ni pousser sur `main`, ni déployer, ni approuver, ni lire les variables, ni
créer de projet (9/9). Les conteneurs tournent sans root, en lecture seule, sans
aucune capacité.

#### 13. Comment les vulnérabilités sont-elles auditées ?
À chaque pipeline, de façon bloquante sur HIGH et CRITICAL : Trivy sur les
dépendances, les secrets et la configuration Terraform, Semgrep sur le code,
hadolint sur les recettes ; ECR scanne chaque image à l'envoi (6 images, rien de
signalé). La porte locale rejoue ces contrôles avant chaque push et refuse toute
directive qui ferait taire un outil. Renovate propose les mises à jour chaque jour
ouvré. Quatre trouvailles Trivy sont acceptées et motivées, une par une.

### Questions du jury

#### 14. Quelles difficultés, et comment les avez-vous résolues ?
- **Un test qui trouve une faille de conception** : en local, la passerelle et
  `billing-app` partageaient le réseau de RabbitMQ ; séparé en deux réseaux.
- **Un test qui ne mesurait pas ce qu'il disait** : la vérification de la lecture
  seule passait même cassée (refus dû aux droits, pas au réglage) ; elle lit
  maintenant la configuration du conteneur. Chaque garde est cassée exprès pour la
  voir tomber.
- **Une garde trouée** : la porte ne voyait pas une image courte sans empreinte
  (`busybox:1.37`) ; motif corrigé et éprouvé.
- **Un script de destruction dangereux** : une erreur AWS se lisait « pas de
  staging », et le socle aurait été détruit sous un environnement vivant ; trouvé
  par un essai avec un faux `aws` en échec, corrigé, éprouvé.
- **Un GitLab neuf à chaque séance** : la publication ne savait pas remplir un
  projet vide ; les clés SSH des machines neuves se vérifient contre la console EC2.
- **Des versions non figées** : Docker du runner s'installait à la dernière
  version, et les jobs de CI installaient leurs outils sans version (Helm 3.19 au
  lieu de 4.3.1) ; tout est figé à la version de la ligne Pile, prouvé dans les
  pipelines de la seconde séance.
- **Une empreinte mal placée, vue au déploiement** : écrite dans l'étiquette, elle
  rendait node-exporter invalide (le chart ajoute `-distroless` après) et
  empêchait l'opérateur de lire la version de Prometheus ; la garde de la porte ne
  vérifiait que le début de la référence. Empreintes passées par les champs des
  charts, garde rendue stricte et éprouvée sur les valeurs fautives.

#### 15. Quelle sobriété (Green IT) ?
Images minimales et mesurées, aucune dépendance de développement servie ; rien ne
tourne pour rien, en local comme sur AWS ; plafonds d'autoscaling ; journaux et
métriques gardés un jour ; un seul environnement allumé, seulement pendant les
séances.

#### 16. Si c'était à refaire, ou pour aller plus loin ?
Une NAT par zone et des bases gérées (RDS) pour la haute disponibilité de
production ; des NetworkPolicies de sortie ; des environnements protégés GitLab
(Premium) pour nommer les approbateurs ; une recherche de secrets dans l'historique
du dépôt à chaque push.

## Alternatives et limites

- **Alternatives écartées** : images officielles `postgres` et `rabbitmq` en local
  (on éprouve plutôt les images qui partent en production) ; ECS Fargate (toute la
  configuration à réécrire) ; une NAT par zone (0,055 $/h de
  plus) ; un load balancer créé par Kubernetes (il survivrait à la destruction) ;
  GitLab éteint entre deux séances (≈ 13,80 $ par mois pour rien) ; accepter la clé
  SSH d'une machine neuve à la première connexion (vérifiée contre la console EC2).
- **Limites** : une seule NAT, des bases et RabbitMQ à une copie, une seule instance
  GitLab ; la prod n'est jamais créée ; un réseau Compose filtre par appartenance,
  pas par sens ; l'approbation de la prod repose sur le droit de fusionner dans
  `main`.
