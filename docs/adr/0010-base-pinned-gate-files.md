# 0010 — Fichiers de contrôle épinglés sur le commit de base des PR

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : OPS

## Contexte

Les rulesets de `develop` et `main` imposent une PR, 0 approbation et des checks requis au vert (décision OPS, EN-71). Sans relecteur obligatoire, les checks requis sont la seule barrière avant la fusion. secops a relevé le risque : ces checks exécutent des fichiers versionnés dans le dépôt (Taskfile, configurations des linters, politiques Checkov, scripts CI). Une PR qui modifie ces fichiers peut donc affaiblir les contrôles qu'elle doit elle-même passer et les faire passer au vert.

## Facteurs de décision

- Sécurité : un check requis ne doit pas pouvoir être neutralisé par la PR qu'il contrôle.
- Cohérence avec la décision « 0 approbation » : pas de revue humaine bloquante.
- Délai : applicable tout de suite au niveau du dépôt, sans fonctionnalité d'organisation.
- Simplicité et auditabilité.

## Options considérées

1. Supprimer puis restaurer, depuis le commit de BASE de la PR, les fichiers de contrôle avant tout check, dans `ci.yml` et `pr-governance.yml` sur `pull_request`.
2. Exiger la revue d'un code owner sur les chemins de contrôle.
3. Exécuter les checks depuis un required workflow stocké sur une ref protégée (ruleset d'organisation).
4. Statu quo.

## Décision

Option 1. Sur l'événement `pull_request`, avant tout check, les jobs de `ci.yml` et `pr-governance.yml` suppriment puis restaurent depuis le commit de base. La base est le premier parent du commit de fusion de la PR (`HEAD^1`, checkout avec `fetch-depth: 2`) et non `pull_request.base.sha` : ce dernier peut être plus ancien que la branche cible réelle (l'avertissement listerait alors des changements étrangers à la PR), et le récupérer par SHA échoue sans jeton sur un dépôt privé.

Deux ensembles de fichiers sont concernés.

Fichiers de contrôle explicites (appelés directement par la CI ou le Taskfile) :

- `Taskfile.yml`, `taskfiles/**`
- `.mise.toml`, `mise.lock`, `.mise/**` (verrous et configuration)
- `.checkov.yaml`, `.tflint.hcl`, `.gitleaks.toml`, `commitlint.config.mjs`
- `policies/**`, `scripts/ci/**`, `.github/actions/**`, `.github/scripts/**`

Fichiers de configuration implicites (chargés d'eux-mêmes par les outils s'ils sont présents) :

- mise : `mise.toml`, `.config/mise.toml`, `.config/mise/**`, `mise*.local.toml`, `.tool-versions` (un `[env]` ou `_.path` permettrait de placer un faux `checkov`, `trivy` ou `tflint` en tête du `PATH`) ;
- trivy : `trivy.yaml`, `.trivyignore*` ;
- gitleaks : `.gitleaksignore` ;
- checkov : tout `.checkov.y{a,}ml` autre que `.checkov.yaml` à la racine (checkov fusionne aussi `./.checkov.yml` et `<dossier -d>/.checkov.y{a,}ml`) ;
- commitlint : `.commitlintrc*`, `package.json` (un `.commitlintrc.js` exécute du JavaScript arbitraire) ;
- actionlint, zizmor, shellcheck : `.github/actionlint.y{a,}ml`, `zizmor.yml`, `.github/zizmor.yml`, `.shellcheckrc` (racine et `.github/`).

En complément, l'action `setup-toolchain` fixe `MISE_OVERRIDE_CONFIG_FILENAMES=.mise.toml` pour que mise ne lise que le fichier restauré, et commitlint est appelé avec `--config commitlint.config.mjs`.

La suppression préalable empêche aussi qu'un fichier ajouté par la PR dans ces chemins (par exemple une nouvelle politique, un nouveau script ou un fichier d'exclusion) soit pris en compte. L'étape `uses: ./.github/actions/setup-toolchain` s'exécute après la restauration : c'est donc la version de base de l'action composite qui tourne. Le code contrôlé (infra, services, tests) reste celui de la PR ; seuls les outils, règles et configurations de contrôle viennent de la base. Le run émet un avertissement (`::warning::`) listant les fichiers de contrôle modifiés par la PR : leurs changements ne s'appliquent qu'après la fusion, au premier run sur la branche cible.

Règle de maintenance : tout outil ajouté à un check requis doit faire ajouter, dans la même PR, ses fichiers de configuration implicites (noms et emplacements découverts automatiquement) à l'ensemble restauré, ou être appelé avec un chemin de configuration explicite pointant vers un fichier restauré. La revue `secops` d'un changement de workflow vérifie ce point.

L'option 2 contredit la décision « 0 approbation ». L'option 3 est la solution la plus robuste mais demande une fonctionnalité de ruleset d'organisation qui n'est pas disponible pendant l'atelier ; elle reste l'évolution visée. L'option 4 laisse le risque ouvert. Piliers Well-Architected : sécurité (intégrité des contrôles, SEC11 sécurité du cycle de développement) et fiabilité (les checks requis gardent la même définition pendant la PR).

## Conséquences

- Positives : une PR ne peut plus affaiblir le Taskfile, la toolchain épinglée, les règles et fichiers d'exclusion des linters et scanners, ni les scripts CI qui la contrôlent ; mécanisme visible dans les logs et sans dépendance externe.
- Négatives / dette :
  - Une PR qui modifie un fichier de contrôle n'est pas validée avec la nouvelle version : une règle cassée ou trop stricte n'apparaît qu'après la fusion, sur `develop`. Il faut corriger vite par une PR de suivi.
  - Une PR qui ajoute une tâche ou un outil et l'utilise dans le même changement échoue en CI ; il faut d'abord fusionner la modification des fichiers de contrôle, puis son usage.
  - La liste des chemins est maintenue à la main dans deux workflows et doit rester alignée avec cet ADR.
  - La liste des configurations implicites dépend du comportement de chaque outil : une nouvelle version peut découvrir un nouveau nom de fichier. Il faut la revoir à chaque ajout d'outil et à chaque montée de version majeure.
  - Un `package.json` à la racine est figé sur la base ; une future application Node doit vivre dans son propre dossier (`frontend/`, `services/`).

## Impact sécurité

Réduit la surface d'attaque de la chaîne CI : les checks requis ne dépendent plus de fichiers modifiables par la PR, explicites ou implicites, à deux réserves près.

Risque résiduel lié à la maintenance : une configuration implicite qu'un outil découvre mais qui n'est pas dans la liste reste modifiable par la PR. La règle de maintenance ci-dessus et la revue `secops` le couvrent ; il n'existe pas de règle générique « refuser toute configuration inconnue ».

Risque résiduel, assumé : les workflows eux-mêmes (`.github/workflows/**`) sont exécutés depuis la PR sur `pull_request`. Une PR qui modifie `ci.yml` peut retirer l'étape de restauration, puis les fichiers de contrôle. Mesures d'atténuation :

- CODEOWNERS sur `.github/` : la revue est demandée mais non bloquante.
- Règle de CLAUDE.md : revue `secops` obligatoire de tout changement de workflow avant commit.
- Audit de l'historique des branches protégées (squash-merge, un commit par PR, traçable jusqu'à son issue).
- Évolution prévue : required workflows au niveau organisation ou GitHub App de contrôle, exécutés depuis une ref protégée.

`pull_request_target` reste exclu (EN-71 AC5) : il exécuterait les workflows de la base mais avec des secrets et un jeton en écriture, ce qui crée un risque plus grave. Aucun changement sur l'authentification AWS (OIDC, ADR 0009), le chiffrement ou la journalisation.

## Impact coût

Aucun : quelques secondes de `git checkout` par job, dans les minutes CI existantes.

## Liens

- Issue #39 (EN-71, suivi)
- ADR [0009](0009-gitops-no-local-apply.md)
- `.kiro/steering/security.md` (chaîne d'approvisionnement)
- `.github/workflows/ci.yml`, `.github/workflows/pr-governance.yml`
