# Publier une release

`main` est la production. Une release suit le flux gitflow : promotion `develop` → `main`, PR de release générée par [release-please](https://github.com/googleapis/release-please), tag et release GitHub, puis back-merge `main` → `develop`. Configuration : `release-please-config.json`, `.release-please-manifest.json`, workflow `.github/workflows/release.yml`.

Release-please utilise `GITHUB_TOKEN` (aucun secret, décision EN-02). Conséquence : les workflows ne se déclenchent pas sur la PR qu'il crée (étape 3).

## Prérequis (une seule fois, admin du dépôt)

- Settings → Actions → General → **Allow GitHub Actions to create and approve pull requests** activé. Sans cela, release-please échoue à ouvrir la PR.
- Le ruleset `main` autorise le **merge commit** (pas de squash obligatoire) et exige les checks `ci / lint`, `ci / security`, `ci / test`, `ci / docs`, `ci / pr-title` et `guard-main`.

## Étapes

### 1. Promouvoir `develop` vers `main`

1. Ouvrir une PR `develop` → `main`, titre en Conventional Commit (ex. `chore: promote develop to main`), corps avec `Closes #<n>` si applicable.
2. Attendre les checks verts (`guard-main` accepte la branche `develop`).
3. Fusionner avec un **merge commit** (pas de squash : l'historique des commits conventionnels de `develop` doit rester visible pour release-please).

### 2. Release-please ouvre la PR de release

Le push sur `main` déclenche le workflow `release`. Il ouvre ou met à jour la PR `release-please--branches--main` → `main`, titrée exactement `chore(release): <version>`. Elle contient la mise à jour de `CHANGELOG.md` (sections en français) et de `.release-please-manifest.json`.

Si aucune PR n'apparaît : vérifier l'exécution du workflow `release` (onglet Actions) et qu'au moins un commit `feat`, `fix`, `perf` ou `revert` a été promu (les types `docs`, `refactor`, `build`, `ci` apparaissent au changelog mais ne suffisent pas toujours à produire une version ; `test`, `style`, `chore` sont masqués).

### 3. Déclencher les checks : fermer puis rouvrir la PR

La PR est créée par `github-actions[bot]` avec `GITHUB_TOKEN` : GitHub ne lance aucun workflow dessus, donc les checks requis ne remontent jamais et la PR reste bloquée.

1. Ouvrir la PR de release et vérifier l'onglet **Commits** (uniquement `github-actions[bot]`) et l'onglet **Files changed** (uniquement `CHANGELOG.md`, `.release-please-manifest.json`, `version.txt`). Sinon, fermer la PR sans la rouvrir et alerter l'OPS.
2. **Close pull request**, puis **Reopen pull request** (avec un compte humain). L'événement `reopened` déclenche `ci` avec un acteur humain.
3. Attendre les checks verts. `guard-main` accepte la branche `release-please--*` uniquement si l'auteur de la PR est `github-actions[bot]` **et** si la PR ne modifie que les trois fichiers ci-dessus.

À répéter si release-please met à jour la PR après de nouveaux pushes sur `main` (le nouveau commit de la branche n'est pas non plus couvert par les checks).

### 4. Fusionner la PR de release

Fusionner avec un **merge commit**. Le workflow `release` se relance sur le push et crée le tag `v<version>` et la release GitHub avec les notes du changelog.

### 5. Vérifier

- Tag `v<version>` présent (Code → Tags).
- Release GitHub publiée avec les notes attendues (Releases).
- `CHANGELOG.md` sur `main` contient la version.
- Le label `autorelease: tagged` est posé sur la PR de release.

### 6. Back-merge `main` → `develop`

Le commit de release (changelog, manifest) et le merge commit n'existent que sur `main`.

1. Ouvrir une PR `main` → `develop`, titre `chore: back-merge main into develop`.
2. Fusionner avec un merge commit une fois les checks verts.

Sans back-merge, la prochaine promotion `develop` → `main` entrera en conflit sur `CHANGELOG.md`.

## Rollback

- Release GitHub ou tag erroné non encore déployé : supprimer la release puis le tag. Si un ruleset protège les tags `v*`, la suppression se fait par un admin, dans l'UI (**Releases** → tag → **Delete**) ; sinon `git push origin :refs/tags/v<version>`, et corriger le manifest si besoin. À éviter une fois la version consommée.
- Version déjà déployée : ne pas réécrire l'historique de `main`. Ouvrir une PR de correctif sur `develop` (`fix(...)` ou `revert: ...`), la promouvoir, et laisser release-please publier une version corrective. Le rollback applicatif et infra passe par le pipeline de déploiement (alias `live` des Lambdas, apply du commit précédent), pas par ce workflow.
