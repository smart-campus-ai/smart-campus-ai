# Migration du backlog

`apply.sh` applique `docs/backlog/migration-plan.md` au dépôt `smart-campus-ai/smart-campus-ai` via `gh`. À lancer depuis la racine du dépôt, une phase à la fois :

```bash
bash scripts/backlog/apply.sh dry        # vérifie le tableau (actions, doublons, corps manquants)
bash scripts/backlog/apply.sh labels     # supprime les labels par défaut, crée la taxonomie
bash scripts/backlog/apply.sh issues     # crée les issues CREATE, modifie les UPDATE ; écrit map.tsv (ID -> numéro)
bash scripts/backlog/apply.sh subissues  # rattache chaque issue à son epic
bash scripts/backlog/apply.sh board      # ajoute les issues au projet 1 et renseigne les champs
```

`S` désigne le dossier de travail (`map.tsv`, `rows.tsv`). La correspondance ID → numéro de la migration du 22/10 est dans `docs/backlog/issue-map.tsv`.
Attention : la phase `issues` n'est pas idempotente pour les créations (relancer crée des doublons).
