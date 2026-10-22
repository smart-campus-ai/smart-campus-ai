# Onboarding — nouveau membre SE

Checklist à suivre dans l'ordre. Cocher au fur et à mesure.

## 1. Accès

- [ ] Compte GitHub avec 2FA activée.
- [ ] Invitation à l'organisation acceptée, accès en écriture au dépôt (demander à @PaulPerigault).
- [ ] Accès au tableau GitHub Projects de l'équipe.
- [ ] Pas d'accès AWS nécessaire : les déploiements passent par la CI.

## 2. Outils

- [ ] Git installé, identité configurée (`git config --global user.name` / `user.email` = e-mail lié à GitHub).
- [ ] Authentification GitHub (clé SSH ou HTTPS via Git Credential Manager).
- [ ] mise installé et activé dans le shell (voir [README](../README.md#installation)).

## 3. Premier clone

- [ ] `git clone` puis `git switch develop`.
- [ ] `mise trust && mise install` *(disponible après EN-01)*.
- [ ] `task setup` — installe les hooks lefthook *(disponible après EN-01)*.
- [ ] Copier `.env.example` en `.env` et le compléter localement ; ne jamais le committer.
- [ ] Lire : [README](../README.md), [CONTRIBUTING](../CONTRIBUTING.md) (surtout le contrat infra ↔ app), [AGENTS.md](../AGENTS.md) (carte du dépôt), `packages/contracts`.

## 4. Première PR

- [ ] Choisir une issue `role/se` taguée `size/xs` ou `size/s` en colonne Ready, se l'assigner, passer en In progress.
- [ ] Créer la branche : `git switch -c feat/<issue>-<slug>`.
- [ ] Modifier uniquement `services/`, `frontend/` ou `packages/` ; besoin infra (variable, IAM) → issue `area/infra`.
- [ ] Commits en Conventional Commits, sans aucune signature d'outil.
- [ ] `task check` vert en local *(disponible après EN-01)*.
- [ ] `git push -u origin <branche>`, ouvrir la PR vers `develop`, remplir le template avec `Closes #<n>`.
- [ ] Obtenir 1 approbation et des checks verts, puis squash merge.
- [ ] Vérifier le déploiement `dev` (workflow `app-deploy`) et les tests smoke.

## Contacts

| Sujet | Contact |
|---|---|
| Infra, CI/CD, qualité, architecture | @PaulPerigault |
| Application (services, front, contrats) | TODO (handles SE) |
