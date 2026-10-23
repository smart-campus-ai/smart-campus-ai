# Contribuer à SmartCampus AI

## Team

| Handle | Rôle | Périmètre (CODEOWNERS) |
|---|---|---|
| @PaulPerigault | OPS | `infra/`, `.github/`, `policies/`, configuration des agents et de l'outillage, tout le reste ; co-responsable de `docs/adr/` et `docs/architecture/` |
| @G8LD | AS | `docs/adr/`, `docs/architecture/` (avec @PaulPerigault) |
| @MatRom-03 | QE | `tests/`, `docs/qa/` |
| @LiberiBg | SE | `services/`, `frontend/`, `packages/` |
| @Pawpawzz | PO | décisions produit, priorités, acceptation des user stories (`status/needs-decision`) |
| @BadiiiiX | BA | règles métier, critères d'acceptation, scénario de démo (`role/ba`) |

@PaulPerigault couvre aussi le QE et l'AS côté infrastructure, mais n'est assigné qu'aux issues `role/ops`.

CODEOWNERS demande automatiquement la revue du responsable du périmètre ; il ne bloque pas le merge (0 approbation exigée).

## Langue

Code, identifiants, commentaires, messages de commit et noms de branche en anglais. Issues, descriptions de PR et docs d'équipe en français.

## Branches

- Toujours partir de `develop` à jour : `git switch develop && git pull`.
- Nom : `<type>/<issue>-<slug>` en kebab-case, ex. `feat/12-tickets-store`, `fix/34-sla-timezone`.
- Une branche = une issue = une PR.

## Commits (Conventional Commits)

Format : `<type>(<scope>): <résumé impératif en anglais>`

- Types : `feat fix docs style refactor perf test build ci chore revert`
- Scopes : `bootstrap edge identity api data ai notif sla obs sec ci cd qa docs deps app front contracts`
- Un changement logique par commit. Rupture de compatibilité : `!` après le scope + pied `BREAKING CHANGE:`.

Exemple : `feat(app): add ticket creation handler`

### Règle anti-signature

Aucune signature d'outil dans les commits, les PR ou les commentaires de code :

- pas de trailer `Co-Authored-By` ;
- pas de mention « Generated with » ni équivalent ;
- aucune autre attribution à un outil.

Vérifié par le hook `commit-msg` de lefthook (après EN-01) et par la CI ; un commit non conforme bloque la PR. Corriger avec `git commit --amend` (commit local non poussé) ou un rebase de la branche.

## Pull requests

- Cible : `develop` (seules les PR de release visent `main`).
- Titre = Conventional Commit valide (vérifié par `ci / pr-title`).
- Remplir le template : Résumé · Issue liée (`Closes #n`) · Changements · Tests · Impact sécurité · Plan OpenTofu · Coût · Checklist DoD.
- Conditions de merge : **PR obligatoire, 0 approbation, checks requis verts** (liste fixée par le ruleset, voir EN-71), conversations résolues.
- Merge en **squash** uniquement ; historique linéaire, pas de force-push sur `develop`/`main`.
- Toute exception Checkov/Trivy doit avoir un commentaire `# checkov:skip=<ID>: <raison>` et être listée dans la PR.

## Definition of Done

- Critères d'acceptation couverts par des tests automatisés nommés d'après eux (`US04-AC2 …`).
- `task check` vert en local et en CI (disponible après EN-01) ; plan relu le cas échéant.
- Aucun nouveau finding de sécurité sans justification.
- README de module régénéré ; ADR écrit si une décision a été prise ; issue mise à jour.
- Aucun secret dans le code, les logs, les tfvars ou les workflows.

## Contrat infra ↔ app

L'infra (OPS) possède la configuration, l'app (SE) possède le code. Aucune équipe ne modifie le périmètre de l'autre sans PR revue par son propriétaire.

Le contrat complet est dans [`docs/architecture/infra-app-contract.md`](docs/architecture/infra-app-contract.md) : variables d'environnement, droits IAM et déclencheurs de chaque fonction, ressources partagées et paramètres SSM, API (`packages/contracts`), build zip arm64, déploiement par alias `live` et rollback, interdits.

En bref :

- configuration uniquement par variables d'environnement et SSM ; aucun nom, ARN, compte, région ni secret dans le code ;
- nouvelle variable ou permission : issue `area/infra`, ajoutée côté infra avant usage côté code ;
- code déployé seulement par le pipeline applicatif (EN-74), jamais par la console ;
- tout changement d'API commence par une PR sur `packages/contracts` ; une rupture est marquée `!`.
