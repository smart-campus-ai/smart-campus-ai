## Résumé

<!-- Une à trois phrases : quoi et pourquoi. -->

## Issue liée

<!-- Obligatoire. Remplacez par le numéro de l'issue, par exemple : Closes #12 -->
Closes #

## Changements

-

## Tests ajoutés / exécutés

<!-- Nommez les tests d'après les critères d'acceptation (US04-AC2 ...). -->
-

## Impact sécurité

<!-- IAM, KMS, réseau, données personnelles. Écrire « Aucun » si non applicable. -->
-

## Plan OpenTofu (résumé)

<!-- Par stack et environnement : ressources à créer / modifier / détruire. Écrire « N/A » si aucun changement d'infrastructure. -->
-

## Coût

<!-- Différence Infracost. Écrire « N/A » si aucun changement d'infrastructure. -->
-

## Checklist DoD

- [ ] Critères d'acceptation couverts par des tests automatisés nommés d'après les AC
- [ ] `task check` vert en local et en CI
- [ ] Plan OpenTofu relu, aucune destruction inattendue
- [ ] Aucun nouveau finding Checkov/Trivy sans skip justifié (`# checkov:skip=<ID>: <raison>`), skips listés ci-dessus
- [ ] README de module régénéré (`task docs`) et ADR rédigé si une décision a été prise
- [ ] Aucun secret dans le code, les logs ou les sorties
- [ ] Aucune attribution d'outil IA dans les commits, le code ni cette description (AGENTS.md, règle 7)
- [ ] Label et milestone renseignés
- [ ] Issue mise à jour avec une courte note d'avancement
