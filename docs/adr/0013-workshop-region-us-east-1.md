# 0013 — Région us-east-1 imposée par le compte workshop

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : OPS

## Contexte

L'architecture v3 place la plateforme en `eu-west-3` (Paris), avec `us-east-1` réservé à la web ACL CLOUDFRONT et à ACM. Une vérification en lecture seule avec l'AWS CLI sur le compte workshop (suite de #41) montre que les services de la plateforme (Lambda, DynamoDB, Bedrock, Cognito, CloudWatch Logs, SNS, SQS, SSM, EventBridge Scheduler) sont refusés en `eu-west-3`, `eu-west-1`, `eu-central-1` et `us-west-2`. Ils ne sont autorisés qu'en `us-east-1`. La contrainte vient du compte, pas de notre code : elle ne se contourne pas.

Exigences concernées : toutes les stacks (`foundation`, `platform`), le bootstrap (ADR-0011, ADR-0012), l'assistant (US02, US07, US08, RF03), RGPD (US08).

## Facteurs de décision

- Délai : l'atelier doit déployer sur le compte fourni, sans attendre une levée de la restriction.
- Conformité : aucune donnée réelle pendant l'atelier, seulement des utilisateurs de test.
- Réversibilité : une vraie production doit revenir dans l'UE sans réécriture.
- Sécurité : les invariants (CMK, TLS, least privilege, boundaries) ne dépendent pas de la région.

## Options considérées

1. Région principale `us-east-1` pour l'atelier, région en paramètre pour un retour en `eu-west-3`.
2. Garder `eu-west-3` et demander l'ouverture de la région au propriétaire du compte.
3. Une autre région UE (`eu-west-1`, `eu-central-1`).

## Décision

Option 1. L'option 2 bloque l'atelier sur une demande hors de notre contrôle. L'option 3 est refusée par le compte, comme `eu-west-3`.

- Région principale : `us-east-1` pour dev et prod pendant l'atelier (`aws_region` des stacks et du bootstrap, `region` des `backend.hcl`, `allowed_regions = ["us-east-1"]`).
- Bord : la web ACL CLOUDFRONT et ACM (`enable_custom_domain`, toujours `false`) sont désormais dans la même région que le reste. Le provider `aws.us_east_1` est conservé dans les stacks : un retour en `eu-west-3` n'exige aucun changement de modules. Les deux web ACL restent distinctes (portées CLOUDFRONT et REGIONAL), ADR-0004 inchangé sur le fond.
- Bedrock : profils d'inférence inter-régions US (`us.*`) pour le modèle de génération, Titan Text Embeddings v2 (`amazon.titan-embed-text-v2:0`) pour la Knowledge Base, tous deux disponibles en `us-east-1`. Le modèle reste une variable (steering). Knowledge Base et S3 Vectors sont disponibles en `us-east-1` : pas de repli nécessaire au sens d'ADR-0007.
- Retour en `eu-west-3` pour une vraie production, par paramètres :
  - `aws_region = "eu-west-3"` dans les tfvars de l'environnement ;
  - `region = "eu-west-3"` dans `envs/<env>/backend.hcl`, avec un bootstrap dans cette région (`allowed_regions = ["eu-west-3", "us-east-1"]`, ADR-0011, ADR-0012) ;
  - identifiant de modèle vers un profil d'inférence EU (`eu.*`), modèle d'embedding disponible dans la région.
  - Les ressources régionales sont recréées, pas déplacées : un retour impose une migration des données (tables, buckets, utilisateurs Cognito) planifiée dans un runbook.

## Conséquences

- Positives : déploiement possible tout de suite sur le compte fourni ; code et modules inchangés (la région est déjà une variable) ; un seul jeu de régions dans les politiques CI, donc des politiques plus courtes.
- Négatives / dette :
  - écart avec la décision « eu-west-3 » du steering d'architecture et d'`AGENTS.md`, à aligner ;
  - le critère d'E5 « l'inférence reste dans l'UE » n'est pas tenu pendant l'atelier ;
  - latence réseau plus élevée depuis la France pour `/api/*`, non mis en cache par CloudFront (la SPA reste servie depuis les points de présence) ; seuils de performance (k6) à confirmer en `us-east-1` ;
  - un profil `us.*` peut router l'inférence vers d'autres régions US (dont `us-west-2`) ; si le refus du compte en `us-west-2` porte sur Bedrock, certaines invocations échoueront. À vérifier par une invocation de test ; repli : identifiant de modèle à la demande en `us-east-1`.

## Impact sécurité

Surface d'attaque, authentification, chiffrement CMK, TLS et traçabilité inchangés. Les politiques IAM de `chat` et de la Knowledge Base doivent autoriser l'ARN du profil d'inférence et les ARN des modèles de fondation dans chaque région de destination du profil. `allowed_regions` réduit à `us-east-1` resserre le périmètre des rôles apply.

RGPD : pendant l'atelier, des données sortent de l'UE (comptes Cognito, tickets, transcriptions de chat, inférence Bedrock), ce qui est accepté parce qu'il n'y a que des utilisateurs de test et aucune donnée réelle. Les mesures d'US08 restent en place (TTL, effacement, masquage PII par le Guardrail, journalisation des invocations désactivée ou à rétention courte). Une vraie production avec des données d'étudiants exige le retour en `eu-west-3` et le profil d'inférence EU avant toute mise en service ; cette ADR ne couvre pas ce cas.

## Impact coût

Pas de coût fixe supplémentaire. Les tarifs en `us-east-1` sont en général égaux ou inférieurs à ceux de `eu-west-3`. WAF CLOUDFRONT et ACM étant dans la région principale, l'infrastructure n'est plus répartie sur deux régions. Un retour en `eu-west-3` coûte surtout du temps de migration.

## Liens

- #41, EN-11 (vérification des services du compte), E5, US08
- `.kiro/steering/architecture.md` (en-tête de région, AI assistant), `AGENTS.md` (Environnements)
- ADR [0002](0002-single-account-dev-prod.md) : compte unique, dev et prod tous deux en `us-east-1`
- ADR [0004](0004-rest-api-regional-waf.md) : deux web ACL, désormais dans la même région
- ADR [0007](0007-s3-vectors.md) : Knowledge Base et S3 Vectors disponibles en `us-east-1`, pas de repli
- ADR [0011](0011-state-backend-bootstrap.md), [0012](0012-github-oidc-ci-identity.md) : région du state et `allowed_regions`
