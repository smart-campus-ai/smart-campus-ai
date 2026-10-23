# Estimation des coûts d'infrastructure — SmartCampus AI

> Projection de coûts AWS pour un déploiement type **école ESIEA**.
> Région `us-east-1`, architecture 100 % serverless (pay-per-request).
>
> **Statut** : estimation à partir des modules OpenTofu et de l'architecture (README + ADR).
> Le stack `infra/stacks/platform` n'étant pas encore câblé aux modules, ces chiffres sont
> une **projection**, pas un `tofu plan` + `infracost` sur des ressources résolues.
> Dernière mise à jour : 2026-10-23.

## 1. Hypothèses d'usage (valeurs simples, école type ESIEA)

| Paramètre | Valeur retenue | Commentaire |
|---|---|---|
| Étudiants + personnels | ~2 200 | ~2 000 étudiants, ~200 personnels |
| Utilisateurs actifs / mois (MAU Cognito) | **1 000** | tout le monde ne se connecte pas chaque mois |
| Requêtes API / mois | **300 000** | ~10 000/jour ouvré, usage concentré en semaine |
| Tickets créés / mois | **1 000** | incidents + demandes |
| Conversations avec l'assistant RAG / mois | **2 000** | ~6 tours de chat par conversation → ~12 000 tours |
| Pièces jointes uploadées / mois | **1 000** | captures d'écran, photos (≤ 10 Mo) |
| Documents dans la Knowledge Base | ~500 | ré-indexation rare |
| Région | `us-east-1` | imposée par le compte atelier (ADR-0013) |
| Modèle de chat Bedrock | **Amazon Nova** | profil `us.*`, modèle économique retenu pour l'atelier |

Ces valeurs sont volontairement rondes et prudentes. Elles se mettent à l'échelle linéairement :
diviser le trafic par deux ne change presque rien au total (les postes fixes dominent).

## 2. Estimation mensuelle — environnement de production

| Poste | Détail à ce volume | Coût/mois (USD) |
|---|---|---|
| **WAF** | 2 web ACL (CloudFront + API REST) + ~8 règles / groupes managés à ~1 $ | **~22 $** |
| **KMS** | 3 clés gérées (data / logs / ai) + requêtes de chiffrement | **~4 $** |
| **CloudWatch Logs + X-Ray** | X-Ray actif sur les 8 Lambda + l'API, logs chiffrés KMS | **~5 $** |
| **CloudFront** | 300 k requêtes + egress modeste (SPA + API), PriceClass_100 | **~2 $** |
| **API Gateway REST** | 300 k requêtes × 3,50 $/M | **~1 $** |
| **Lambda ×8 (arm64)** | ~450 k invocations, 256 Mo, courtes (sous / proche du free tier) | **~1 $** |
| **DynamoDB** (3 tables) | on-demand + PITR + streams + GSI, volumes faibles | **~3 $** |
| **GuardDuty Malware S3** | ~1 000 objets, < 10 Go scannés (1 Go gratuit/mois) | **~2 $** |
| **S3** (SPA, pièces jointes, sources, vecteurs, state) | stockage faible | **~2 $** |
| **Cognito** | 1 000 MAU, tier Essentials (threat protection désactivé) | **~0–5 $** |
| **SES / SNS** | emails étudiants + alertes exploitation | **~1 $** |
| **EventBridge Scheduler** | ~1 000 planifications/mois (1 par ticket) | **< 1 $** |
| **Bedrock — embeddings** (Titan V2) | ingestion rare + ~2 000 requêtes RAG | **~1 $** |
| **Bedrock — Guardrail** | text units sur ~12 000 tours de chat | **~2 $** |
| **Bedrock — génération chat** (Amazon Nova) | ~12 000 tours, contexte RAG inclus | **~3–8 $** |

### Total estimé (production)

| Modèle de chat | Total mensuel | Total annuel |
|---|---|---|
| **Amazon Nova** | **~50–65 $/mois** | **~600–780 $/an** |

## 3. Environnement de développement

Le dev reprend les mêmes postes fixes (2 WAF + 3 KMS ≈ **24 $**) mais avec un trafic bien plus
faible, une rétention de logs plus courte (14 j au lieu de 90 j) et le budget désactivé.

- Dev actif en continu : **~25–30 $/mois**
- Si dev et prod cohabitent sur le compte : ajouter ~25 $ au total production.

## 4. Ce qui pilote le coût (par ordre d'impact)

1. **Modèle Bedrock du chat** — seul poste réellement variable et le plus sensible.
   On retient **Amazon Nova** (modèle économique) : la facture d'IA reste sous ~10 $/mois à ce
   volume. Passer à un modèle premium (famille Claude Sonnet) multiplierait ce poste par 10 à 30 :
   à éviter sauf besoin qualité avéré. **Arbitrage n°1.**
2. **WAF (~22 $, fixe)** — 2 web ACL avec tous les groupes managés toujours actifs.
   Retirer le web ACL CloudFront (ne garder que celui de l'API) économise ~11 $/mois,
   au prix d'une surface de protection réduite. `enable_bot_control` est à `false` (bon choix coût).
3. **KMS (~4 $, fixe)** — 3 clés gérées, incompressible tant qu'on chiffre par clé client.
4. **X-Ray actif partout** — pratique mais payant ; désactivable en dev pour réduire les traces.
5. **Rétention des logs** (`log_retention_days`) — levier direct sur CloudWatch.
6. **Cognito threat protection** — laisser à `false` (sinon tier Plus facturé par MAU, bien plus cher).

## 5. Ordre de grandeur à retenir

Pour une utilisation réaliste à l'échelle de l'ESIEA, avec **Amazon Nova** comme modèle de chat,
compter **~50–65 $/mois** (~600–780 $/an).

L'essentiel du coût est **fixe** (WAF + KMS ≈ 26 $/mois) ; le reste de l'infrastructure
serverless reste sous quelques dollars grâce au pay-per-request et aux free tiers. Le seul
poste qui peut déraper est le modèle de chat Bedrock.

## 6. Limites de cette estimation

- Chiffres en **ordres de grandeur**, basés sur l'architecture des modules — pas sur un plan résolu
  (le stack `platform` n'est pas câblé). Les postes fixes (WAF, KMS) sont fiables ;
  la partie Bedrock dépend de la longueur réelle des conversations et du modèle choisi.
- Pour une estimation au centime près des postes fixes une fois le stack câblé :
  lancer **`infracost`** (déjà épinglé dans `.mise.toml`) sur le `tofu plan`.
- Prix de référence : tarifs AWS `us-east-1` consultés en octobre 2026
  (AWS WAF, Amazon Bedrock, GuardDuty Malware Protection for S3). Les tarifs AWS évoluent.
