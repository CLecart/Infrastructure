# Manifeste de développement — Infrastructure

Les règles non négociables du projet, tirées des standards de l'industrie :
Clean Code, Twelve-Factor, CIS Benchmarks, OWASP, principe du moindre privilège,
Green IT. Chaque règle dit ce qui doit être, et nomme la garde qui la tient
quand il y en a une. Une règle qu'aucune garde ne tient le dit.

Toute intervention, humaine ou outillée, s'y conforme.

---

## ⚠️ Règle prioritaire — un manifeste qui se lit et s'enrichit

- Avant toute modification, le manifeste se lit en entier, et la solution se vérifie contre ses règles.
- Après une correction significative : cause réelle, puis risque de répétition ailleurs ; si le risque existe, une règle nouvelle, avec la garde qui la tient. Une règle ne se supprime jamais pour passer, et le manifeste reste fidèle à l'état réel du projet (règle 15).
- Le manifeste énonce des règles, jamais leur histoire : l'incident, sa date et ses chiffres vont dans le message de commit (règle 6).
- Seul le durable y entre : architecture, convention, contrainte technique, piège récurrent, dépendance importante. Une erreur ponctuelle reste au commit.

> **ERREUR → ANALYSE → CORRECTION → NOUVELLE RÈGLE SI NÉCESSAIRE → MANIFESTE MIS À JOUR**

**Il n'y a qu'une infrastructure.** Le socle importé d'un projet antérieur
devient celle de ce projet : aucune règle ni aucun document qui décrit le présent
ne la compare à « l'ancienne version ». Seul `docs/import/` garde, tel quel, le
compte-rendu d'origine.

---

## I. Les règles de l'art

1. **Architecture limpide, en couches :**
   L'infrastructure se lit par couches, chacune à sa place : amorçage (`bootstrap/`), configuration des machines (`ansible/`), infrastructure cloud (`repos/infra/terraform/`), plateforme Kubernetes (`repos/infra/platform/`), services (`repos/<service>/`), environnement local (`compose.yaml`), scripts d'exploitation (`Scripts/`). Un fichier dans la mauvaise couche est un défaut, même s'il fonctionne.
   - Un module Terraform ne porte qu'une responsabilité ; un environnement (`envs/staging`, `envs/prod`) n'est qu'un appel du module commun, avec ses variables, jamais une copie divergente.
   - Un réglage qui dépend de l'environnement vit dans la configuration (variables, `tfvars`, ConfigMap, secrets), jamais dans le code (Twelve-Factor, III).
   - Un seul mécanisme par problème : deux générations concurrentes du même dispositif sont une faute, la morte se supprime aussitôt.

2. **Clean Code et documentation :**
   Le code s'explique par son nommage. Un commentaire dit ce que le code ne peut pas dire — une contrainte, un choix, un coût, un piège —, et rien d'autre.
   - Jamais de commentaire perroquet, jamais d'histoire dans le code : ce qui s'est passé va dans le message de commit.
   - Code, commentaires et messages de commit s'écrivent en anglais ; la documentation du projet (`README.md`, `docs/`) en français clair et technique, comme le sujet l'exige.
   - Zéro code mort : variable Terraform sans lecteur, script que rien n'appelle, manifeste que rien n'applique se suppriment. L'historique Git est la sauvegarde. Les déclarations Terraform inutilisées sont tenues par le job `tflint` (`repos/infra/.tflint.hcl`) ; le reste n'est tenu par aucune garde.

3. **Complexité maîtrisée :**
   Un script fait une chose ; au-delà, il s'extrait en fonctions. Complexité cognitive de 15 au plus pour le code applicatif (Sonar S3776). Aucune garde ne la tient encore.

---

## II. Les bonnes pratiques

4. **Syntaxe moderne et sûre :**
   - Shell : `#!/usr/bin/env bash` et `set -euo pipefail` en tête de tout script ; variables entre guillemets ; une suppression par variable se protège de la variable vide (`"${VAR:?}"`).
   - Terraform : chaque variable porte un `type` et une `description`, et une `validation` quand une valeur la rend dangereuse (un CIDR `0.0.0.0/0` qui s'ouvrirait au monde). Tenue par le job `tflint`.
   - Kubernetes : chaque conteneur déclare ses `requests` et `limits`, ses sondes, et s'exécute sans privilège (`runAsNonRoot`, `allowPrivilegeEscalation: false`). Aucune garde ne le tient encore.
   - Docker Compose : chaque service reprend les limites et le durcissement de son manifeste Kubernetes (`read_only`, `cap_drop: ["ALL"]`, `no-new-privileges`), et chaque flux qu'ouvre une NetworkPolicy a son réseau interne. Tenu par `Scripts/compose-test.sh` sur la pile lancée ; la porte n'en vérifie que la syntaxe.

5. **Zéro avertissement, zéro récidive :**
   - Tout avertissement se résout à la source. Une remarque se corrige dans le code, jamais par une directive qui la fait taire (`# shellcheck disable`, `# hadolint ignore`, `eslint-disable`, `tflint-ignore`, `#trivy:ignore`, `NOSONAR`). Seul un faux positif connu de l'outil, prouvé par sa référence publique et un cas minimal, se contourne, par une forme du code qui l'évite. Tenue par l'étape `no-silencing-directive` de la porte (`Scripts/ci-gate.sh`).
   - Une trouvaille de sécurité acceptée se nomme dans le fichier d'exceptions de l'outil (`.trivyignore.yaml`), une entrée par trouvaille, bornée au fichier où elle tombe, sous le motif qui la justifie. Tenue par le job `iac-scan`.

6. **Tests, CI/CD et journal de bord :**
   L'infrastructure se vérifie avant de s'appliquer, et chaque garde s'éprouve en cassant ce qu'elle garde.
   - Terraform : `terraform fmt -check -recursive`, `terraform validate` sur chaque environnement, `tflint`, puis `trivy config` qui refuse toute mauvaise configuration HIGH ou CRITICAL non motivée. Tenue par les jobs `validate`, `tflint` et `iac-scan` de `repos/infra/.gitlab-ci.yml`.
   - Services : tests, tests d'intégration, lint (ESLint), analyse statique (Semgrep), vulnérabilités des dépendances et secrets (`trivy fs`), bonnes pratiques des recettes (hadolint). Tenue par les jobs `test`, `integration-test`, `lint`, `semgrep-sast`, `sast-gate`, `dependency-scan` et `dockerfile-lint` de chaque `repos/<service>/.gitlab-ci.yml`.
   - Un `plan` précède tout `apply`, et se lit avant : ce qu'il crée, modifie ou détruit se compte. Production derrière une approbation manuelle. Tenue par les jobs `plan-*` et `approve-production`.
   - Tout script de test d'exploitation (`Scripts/*-test.sh`) sort en échec dès qu'une vérification tombe, jamais sur un simple message.
   - Les pipelines ne tournent que dans le GitLab que `bootstrap/` et `ansible/` déploient ; le dépôt Gitea de l'école n'exécute rien. **La porte locale, `Scripts/ci-gate.sh`, passe avant tout push** : elle exécute le script de chaque job qui ne demande ni GitLab, ni AWS, ni service (`validate`, `tflint`, `iac-scan`, `dependency-scan`, `build`, `test`, `lint`, `dockerfile-lint`, `validate-config`), dans l'image du job, tous deux lus dans les fichiers de CI : elle ne peut pas s'écarter des jobs, et un job renommé ou supprimé la fait tomber. Elle ajoute ce qu'aucun job ne tient : shellcheck sur chaque script, hadolint sur chaque recette, Terraform de `bootstrap/`, aucune directive de silence, aucune image sans empreinte, charts Helm compris, un `compose.yaml` valide, aucun secret dans l'historique ni dans les fichiers à commiter. Elle travaille sur une copie des fichiers que Git suit ou suivrait, n'écrit rien dans le dépôt et le vérifie, va au bout de chaque étape et garde leur journal hors du dépôt. Une étape refusée se lit dans son journal avant de relancer. Elle ne rejoue ni `semgrep-sast` et `sast-gate` (modèle de GitLab), ni `integration-test` (services PostgreSQL et RabbitMQ), ni ce qui demande GitLab ou AWS.
   - **Le `git log` est le journal de bord.** Ni `JOURNAL_DE_BORD.md`, ni `CHANGELOG.md`. En contrepartie, le message de commit porte le raisonnement : ce qui a été mesuré, ce qui a été écarté, pourquoi.

---

## III. La conformité

7. **Sécurité DevSecOps (OWASP, CIS, moindre privilège) :**
   - **Moindre privilège partout** : un rôle IAM, un compte de service Kubernetes, un jeton GitLab n'a que les droits de sa tâche, sur ses seules ressources. Un `*` dans une politique IAM se motive au commentaire ou se retire. Aucune garde ne le tient : `iac-scan` en voit une partie.
   - La CI s'authentifie à AWS par OIDC, sans clé d'accès longue durée (`bootstrap/oidc.tf`).
   - Le trafic interne est fermé par défaut (`NetworkPolicy`), et chaque ouverture se nomme.
   - Rien n'écoute le monde sans nécessité : un point d'accès public se restreint à des plages nommées, jamais `0.0.0.0/0` pour l'administration.

8. **Secrets et données sensibles :**
   - Aucun secret n'est commité : état Terraform, `*.tfvars`, vault Ansible, identifiants AWS, jetons. Seuls les modèles `*.example` le sont, sans valeur de secret. Tenu par `.gitignore`, dans le code des services par le scanner de secrets du job `dependency-scan`, et sur tout le dépôt par l'étape `secrets-in-history` de la porte : gitleaks lit chaque commit de chaque branche, puis les fichiers pas encore commités.
   - Un secret vit dans un coffre (Ansible Vault, secret Kubernetes chiffré au repos, variable masquée et protégée de GitLab), jamais en clair dans un fichier suivi, un journal ou une sortie de commande.
   - Ce qui identifie le compte ou le poste — identifiant du compte AWS, adresse IP d'administration, nom d'hôte public — ne paraît ni dans un commit, ni dans la documentation, ni dans une capture : il se masque.

9. **Sobriété numérique et coûts (Green IT, FinOps) :**
   La sobriété se juge à ce qui tourne réellement, et à ce qu'il coûte.
   - Rien ne survit à une séance de travail, socle compris : le compte ne coûte rien entre deux séances. `Scripts/teardown.sh` détruit staging par son pipeline, puis le socle, puis lance l'inventaire des 17 régions, qui sort en échec s'il reste quoi que ce soit. Un environnement oublié est un défaut.
   - Rien ne tourne pour rien, AWS ou poste : ce qui ne sert plus s'arrête aussitôt.
   - Chaque choix de dimensionnement se justifie : type d'instance, nombre de nœuds, NAT, stockage. L'option la moins coûteuse qui tient le besoin passe la première ; un écart se motive.
   - Les images restent légères : image de base minimale, construction en plusieurs étapes, aucune dépendance de développement dans l'image servie. Leur poids se mesure et se documente.
   - Toute dépendance ajoutée — module, chart, outil — se justifie : une dépendance qui remplace vingt lignes n'entre pas.
   - L'analyse des coûts donne des chiffres mesurés (facture, Cost Explorer, calculateur AWS cité avec sa date et sa région), jamais estimés de mémoire.

10. **Reproductibilité :**
    L'infrastructure est du code : elle se construit, se détruit et se reconstruit à l'identique, sans un clic dans une console.
    - Toute ressource naît du code. Une action manuelle inévitable (création du compte, première clé) se documente pas à pas, et elle seule.
    - Chaque version se fige à l'exact : Terraform, fournisseurs et modules (`.terraform.lock.hcl` commité), charts Helm, images, outils de la CI. Tenue pour Terraform par le job `tflint`.
    - Une image se tire par l'empreinte de son index multi-architecture, l'étiquette gardée devant pour la lecture (`image:étiquette@sha256:…`) : recettes, CI, scripts, Ansible, valeurs Helm. Renovate tient les empreintes à jour (`docker:pinDigests`, `repos/renovate/default.json`), et propose d'épingler une image qui ne l'est pas. Un exemple de commande dans un README garde l'étiquette seule : Renovate ne le lit pas. Une image sans empreinte est refusée par l'étape `every-image-pinned` de la porte. Les images que tirent les charts Helm eux-mêmes s'épinglent de même dans leurs valeurs, et les pods de test des charts (`helm test`), jamais lancés, se désactivent ; l'étape `helm-images-pinned` de la porte calcule le rendu des charts (`helm template`, versions de `scripts/deploy-platform.sh`) et refuse toute référence d'image qui ne finit pas par son empreinte (un chart qui ajoute un suffixe après l'étiquette la casse) ou un champ `version:` qui en contient une ; une empreinte passe par le champ que le chart prévoit (`sha`, `digest`) quand il lit ou complète l'étiquette. Les images de shellcheck, de gitleaks et de Helm, que seule la porte emploie, s'actualisent à la main. Un job n'installe aucun outil sans version : les jobs qui touchent AWS, Kubernetes ou Docker, et `sast-gate`, tournent dans l'image de l'AWS CLI épinglée par empreinte (jq compris), et y reçoivent kubectl, Helm, le client Docker et buildx depuis leurs publications officielles, vérifiés par la SHA-256 écrite dans la CI, aux versions de la ligne **Pile** ; git y vient de `dnf`, verrouillé sur la version d'Amazon Linux de l'image. Ces versions et sommes s'actualisent à la main, Renovate ne sachant pas recalculer une somme.
    - Un `destroy` laisse le compte propre : aucune ressource orpheline, facturée ou non. Il se vérifie après coup, par l'inventaire (`Scripts/inventory.sh`).
    - Parité : une seule version de chaque outil entre le poste, la CI et les images, écrite une fois dans la ligne **Pile** du `README.md`.

---

## IV. Cadre opérationnel

11. **Intégrité de l'espace de travail :**
    Aucun script jetable à la racine du projet ; des modifications chirurgicales ; `git status` relu avant chaque commit, jamais de `git add -A` à l'aveugle.
    - Hors du dépôt — `terraform apply` ou `destroy`, création de ressources AWS, sudo, services, paquets —, une action se précède de ce qu'elle modifie, de ce qu'elle coûte, de ce qu'elle peut casser, et du moyen de revenir en arrière.

12. **Délégation à des sous-agents :**
    Un travail large et indépendant peut se confier à des sous-agents, avec un rôle précis. C'est une faculté, jamais une obligation.
    - Ne se délèguent ni un choix d'architecture, ni une action sur le compte AWS.
    - Le compte rendu d'un sous-agent est une piste, pas une preuve : l'agent principal vérifie ce sur quoi il s'engage, et ne rapporte que ce qu'il a constaté.

13. **Attribution et discrétion (historique Git) :**
    Commits et tags sont rédigés au seul nom du développeur (`CLecart`), avec l'identité que le dépôt porte déjà : aucun trailer `Co-Authored-By`, aucune signature, aucune mention d'un agent IA, de Claude ou d'Anthropic. Messages en anglais, au format Conventional Commits (`feat`, `fix`, `docs`, `ci`, `chore`, `test`, `refactor`). Aucune garde ne le tient.

14. **Socle de sécurité non régressif :**
    Une correction ne retire jamais une garde ni une restriction pour passer : une politique qui s'élargit, une exception de scanner qui s'ajoute, un port qui s'ouvre se motive dans le même commit.

15. **Honnêteté documentaire (fait ou cible) :**
    Ce qui n'est pas en place ne se présente jamais comme existant : il se marque `[CIBLE]`, et le `[CIBLE]` se retire dès que le fait est acquis.
    - **Ne jamais annoncer une vérification non exécutée.** Un test non lancé se dit « non lancé ».
    - Les sorties citées dans la documentation sont capturées sur l'infrastructure réellement construite depuis ce dépôt, jamais reconstituées.
    - Chaque séance laisse ses journaux bruts dans `preuves/<date>-<sujet>/`, ignoré par Git, avec un `LISEZMOI.md` qui dit ce que prouve chaque fichier ; un chiffre du `README.md` a sa capture. Un journal gardé dans un dossier temporaire n'est pas une preuve : il se range avant la fin de la séance.
    - L'arborescence décrite dans le `README.md` correspond au disque, fichier pour fichier.

---

## V. Règles propres au projet

16. **Le sujet est la grille :**
    Il n'existe pas de fiche d'audit séparée : l'auditeur et le jury jugent sur le sujet (`README.md`, section 1). Chaque livrable des quatre sous-phases a sa preuve, désignée dans le tableau de suivi ; une case ne se coche qu'avec elle.
    - Périmètre, ni plus ni moins : ce que le sujet demande se fait ; une amélioration non demandée se propose avant de se coder, et un écart voulu se documente avec son motif.

17. **Chaque choix se justifie :**
    Le sujet l'exige. Un choix d'architecture se documente avec l'alternative écartée, la raison, et la mesure qui l'appuie quand il y en a une. Une affirmation qui ne vient pas d'une mesure du projet cite sa source : documentation officielle, avec sa version.

18. **Mesurer, jamais estimer :**
    Toute valeur qui décide d'un comportement — délai, seuil, taille, nombre de réplicas, coût — se mesure avant d'être écrite.
    - Un instrument prouve qu'il mesure avant qu'on croie son verdict : une garde se casse pour la voir tomber.
    - La mesure porte sur ce qu'on croit mesurer : l'image réellement déployée (son empreinte), le commit réellement appliqué, le compte et la région réellement visés.
    - Quand la mesure est impossible, on le dit, et on demande.

19. **Un compte-rendu qui se défend devant un jury :**
    `README.md` est à la fois le compte-rendu et la documentation complète : prérequis, installation, utilisation, architecture, choix techniques, coûts, sécurité, supervision, dépannage. `REVISION-AUDIT.md` prépare l'évaluation par un pair et la soutenance, comme dans les projets précédents : chiffres mesurés, déroulé de la démonstration, questions tirées du sujet et leurs réponses, alternatives et limites.
