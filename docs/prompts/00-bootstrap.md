# Prompt d'orchestration n°0 — mise en place du dépôt et du backlog

> Utilisation : depuis la racine du dépôt cloné (kit dézippé dedans), lance `claude`, passe en Opus 5.5 avec `/model opus`, puis colle :
> `Lis docs/prompts/00-bootstrap.md et exécute-le.`

---

Tu es l'orchestrateur décrit dans `CLAUDE.md`. Tu appliques strictement ce fichier et `AGENTS.md`. Kiro écrit le code (toujours avec `kiro-cli chat --v3`), toi tu pilotes `gh`, tu vérifies et tu commits.

Contexte fixe :
- `SOURCE_REPO=Pawpawzz/smart-campus-ai` : dépôt d'origine des 21 issues, en **lecture seule**. Tu n'y modifies rien.
- `TARGET_REPO=smart-campus-ai/smart-campus-ai` : dépôt public de l'organisation. Il existe déjà, il est **vide**, et je n'en suis pas forcément le propriétaire unique : ne change jamais sa visibilité.
- Pas de nom de domaine. Machines : macOS (principal) et Windows. Tout l'outillage doit être multiplateforme : macOS, Linux (CI), Windows.
- Langues : code, identifiants et commits en anglais ; issues, PR et docs d'équipe en français.

Arrête-toi à chaque **STOP** et attends ma validation explicite.

## Phase 0 — Vérifications préalables

1. Vérifie que `gh auth status` a bien les scopes `repo`, `workflow`, `project` et `read:org`. Vérifie aussi que je suis **admin** de `TARGET_REPO` : `gh repo view $TARGET_REPO --json viewerPermission`.
2. Vérifie que ces commandes fonctionnent : `kiro-cli --version` et `kiro-cli agent list` (les 7 agents doivent se charger sans erreur). Fais ensuite un appel de test : `kiro-cli chat --v3 --no-interactive --agent aws-inspector "Reply with the single word OK. Do not run any tool."`. Vérifie enfin `mise --version`.
3. Vérifie que `.env` est ignoré (`git check-ignore .env`) et que `.idea/` l'est aussi. N'ouvre jamais `.env`.
4. Lis `docs/backlog/backlog-v2.md`. Ne lis pas les fichiers de steering maintenant.
5. Donne-moi un état en 5 lignes maximum. S'il manque quelque chose, **STOP**.

## Phase 1 — Dépôt

1. Le dépôt local est déjà un clone de `TARGET_REPO` (remote `origin`). Si ce n'est pas le cas, **STOP**.
2. Commite le kit sur `main` avec le message `chore: bootstrap repository with agent guidelines`. Vérifie avant que `git status` ne contient ni `.env`, ni `.idea/`, ni aucun fichier hors du kit.
3. Le push direct sur `main` t'est interdit, y compris le premier. Demande-moi de taper `! git push -u origin main` dans la session. Ensuite, crée `develop`, pousse-la (`git push -u origin develop`) et fais-en la branche par défaut avec `gh repo edit --default-branch develop`.
4. Configure le dépôt via `gh api` / `gh repo edit` :
   - squash merge autorisé, merge commit autorisé (PR de release), rebase merge désactivé ;
   - suppression de la branche après merge, auto-merge activé ;
   - token Actions en lecture par défaut ;
   - GitHub Actions autorisé à créer des PR (release-please) ;
   - secret scanning, push protection, alertes Dependabot et signalement privé des vulnérabilités activés ;
   - Issues et Projects activés, Wiki désactivé.
5. **STOP** : liste-moi les réglages appliqués et ceux que l'API a refusés.

## Phase 2 — Backlog

1. Exporte toutes les issues de `SOURCE_REPO` dans `docs/backlog/source-issues.json` : `gh issue list -R Pawpawzz/smart-campus-ai --state all --limit 100 --json number,title,body,state,labels,assignees`. Kiro ne peut pas appeler `gh`, il travaille donc sur ce fichier.
2. Rédige le plan de migration dans `docs/backlog/migration-plan.md`. Applique `backlog-v2.md` et le format d'issue de `.kiro/steering/git-workflow.md`. Pour chaque issue, indique :
   - le titre final ;
   - les labels ;
   - l'epic parent ;
   - le corps complet en français, avec des AC en Gherkin numérotés et une DoD ;
   - l'issue d'origine (`Migré depuis Pawpawzz/smart-campus-ai#n`) ;
   - les assignés d'origine si le compte existe dans `TARGET_REPO`.
3. Pour économiser tes tokens, délègue la rédaction de `migration-plan.md` à l'agent Kiro `architect` : il part de `source-issues.json` et de `backlog-v2.md`, son périmètre d'écriture est `docs/backlog/**`, et le format est un bloc par issue, directement exploitable par `gh issue create --body-file`. Toi, tu ne relis que la cohérence globale : doublons, priorités, dépendances.
4. **STOP** : je valide le plan.
5. Applique le plan, dans cet ordre :
   1. supprime les labels par défaut et crée la taxonomie (`gh label`) ;
   2. crée les epics, puis les issues ;
   3. rattache chaque issue à son epic : `gh api repos/$TARGET_REPO/issues/<parent>/sub_issues -F sub_issue_id=<id numérique de l'issue enfant>` ;
   4. crée le board de l'organisation (`gh project create --owner smart-campus-ai --title "SmartCampus AI"`), relie-le au dépôt (`gh project link`), crée les champs de `git-workflow.md`, puis ajoute-y toutes les issues avec leurs champs ;
   5. sur `SOURCE_REPO`, ne fais rien. Je préviendrai l'équipe que le backlog a migré.
6. Fais-moi un récapitulatif : nombre d'issues créées, modifiées et fermées, et le lien du board.

## Phase 3 — EN-01 : outillage du dépôt (via Kiro)

1. Exécute `gh issue develop <EN-01> --base develop --name chore/<n>-repo-tooling --checkout`.
2. Délègue à l'agent `cicd` :
   - `.mise.toml` (dernières versions stables, épinglées) ;
   - `Taskfile.yml` (les cibles de `AGENTS.md`) ;
   - `lefthook.yml`, la config commitlint, `.editorconfig`, `.tflint.hcl`, `.checkov.yaml`, `.gitleaks.toml` ;
   - `.github/ISSUE_TEMPLATE/*`, `PULL_REQUEST_TEMPLATE.md` et `CODEOWNERS` (le propriétaire OPS couvre `infra/`, `.github/`, `tests/` et `docs/` ; mets un placeholder `@<handle-se>` pour `services/` et `frontend/`, et demande-moi les handles).
3. Applique la boucle de vérification de `CLAUDE.md`, commite en conventional commits, ouvre la PR vers `develop`, attends que les checks soient verts, puis merge (la commande demande une confirmation).

## Phase 4 — EN-71 : CI, puis rulesets

1. Délègue `ci.yml` à l'agent `cicd`, puis lance `secops` sur le diff. Commite, ouvre la PR et vérifie que le run passe au vert.
2. **STOP** : je valide l'activation des rulesets.
3. Crée les rulesets de `develop` et `main` (`git-workflow.md`) avec les checks requis issus du run réel, puis les environnements GitHub :
   - `dev` : déploiement depuis `develop` uniquement ;
   - `prod` : déploiement depuis `main` uniquement, avec moi comme reviewer obligatoire.

## Phase 5 — Fondations AWS (dès que les identifiants du workshop sont disponibles)

1. EN-11 : délègue à l'agent `aws-inspector` la vérification de :
   - l'identité ;
   - la région autorisée (eu-west-3, us-east-1) ;
   - `iam:CreateOpenIDConnectProvider`, `iam:CreateRole` et `iam:PassRole` ;
   - la disponibilité de Bedrock (modèles, profils d'inférence EU), de Knowledge Bases et de S3 Vectors ;
   - le statut SES (sandbox) ;
   - la présence de CloudTrail, GuardDuty, Security Hub et Config ;
   - la durée de vie des identifiants.

   Publie le résultat en commentaire de l'issue et délègue à `architect` les ADR impactés.
2. EN-12 et EN-13 : délègue `infra/bootstrap` à l'agent `iac`, puis lance `secops`, commite et ouvre la PR. **STOP** : j'exécute moi-même `tofu apply` sur le bootstrap en local. Ensuite, tu enregistres les sorties comme **variables** d'environnement GitHub (`gh variable set --env dev|prod`), jamais comme secrets.

## Ensuite — boucle continue

Prends l'issue `ready` suivante selon l'ordre de `backlog-v2.md`, puis enchaîne :
1. crée la branche ;
2. délègue au bon agent (ou à l'agent Kiro `orchestrator` pour une tranche qui touche plusieurs domaines) ;
3. applique la vérification de `CLAUDE.md` ;
4. commite, ouvre la PR, attends que la CI passe et merge ;
5. commente l'issue.

Fais-moi un point toutes les 3 issues : ce qui est fait, ce qui bloque, et ce qui attend une décision de ma part.
