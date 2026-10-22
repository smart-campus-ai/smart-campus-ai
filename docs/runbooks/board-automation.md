# Automatisation du board GitHub Projects

Le board [SmartCampus AI](https://github.com/orgs/smart-campus-ai/projects/1) utilise uniquement les **workflows intégrés** de GitHub Projects : aucun workflow Actions ni token (`PROJECT_TOKEN` volontairement absent, voir EN-02). L'API GraphQL ne permet pas de les configurer (seule la suppression existe) : la configuration se fait dans l'UI, par un admin du projet.

## Réglages

Board → `⋯` (en haut à droite) → **Workflows**. Pour chaque ligne : sélectionner le workflow, **Edit**, régler, **Save and turn on workflow**.

| Workflow | Réglage | Effet |
|---|---|---|
| Auto-add to project | Repository `smart-campus-ai/smart-campus-ai`, filtre `is:issue,pr is:open` | toute issue ou PR ouverte arrive sur le board |
| Auto-add sub-issues to project | activé (par défaut) | les sous-issues suivent leur epic |
| Item added to project | Types : **Issues** ; Status → **Backlog** | une nouvelle issue arrive en Backlog |
| Pull request linked to issue | Status → **In progress** | l'issue liée à une PR passe In progress |
| Item reopened | Types : Issues, Pull requests ; Status → **In progress** | une issue rouverte repart en cours |
| Item closed | Types : Issues, Pull requests ; Status → **Done** | issue fermée ou PR fermée → Done |
| Pull request merged | Status → **Done** | PR mergée → Done |
| Code changes requested | Status → **In progress** | optionnel |
| Code review approved | Status → **In review** | optionnel |

## PR ouverte → In review

Aucun workflow intégré ne réagit à l'ouverture d'une PR. Deux réglages possibles, au choix de l'OPS :

1. **Recommandé** : dupliquer `Item added to project` (`⋯` → *Duplicate*) avec Types : **Pull requests** et Status → **In review**. Une PR ajoutée par l'auto-add arrive donc directement en In review.
2. Si la duplication n'est pas proposée : cocher Issues et Pull requests dans `Item added to project` avec Status → Backlog ; les PR passent alors à Done au merge et se lisent via le champ *Linked pull requests* de l'issue (In progress).

## Vérification

Ouvrir une issue de test, une PR qui la référence (`Closes #n`), puis la merger : l'issue doit passer Backlog → In progress → Done et la PR In review → Done.
