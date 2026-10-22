# 0011 — Backend de state : bucket partagé, clé KMS dédiée et stratégie de bootstrap

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, OPS

## Contexte

EN-12 : le state OpenTofu contient des informations sensibles et doit être chiffré, versionné et verrouillé pour permettre des applies concurrents par la CI (ADR-0009). Le bucket de state ne peut pas être créé par une stack qui l'utilise : le bootstrap (`infra/bootstrap`) est donc le seul apply local, exécuté par un humain. Le compte AWS est unique pour dev et prod (ADR-0002).

## Facteurs de décision

- Sécurité : chiffrement serveur (SSE-KMS) et client (bloc `encryption`), TLS obligatoire, rayon d'impact limité.
- Simplicité : peu de ressources manuelles, pas de service supplémentaire à maintenir.
- Compatibilité avec le passage ultérieur en multi-comptes (ADR-0002).
- Absence de secret dans le dépôt et dans les sorties.

## Options considérées

1. Un bucket de state partagé par les deux environnements, clés `<env>/<stack>.tfstate`.
2. Un bucket de state par environnement.
3. Verrou par table DynamoDB plutôt que verrou natif S3.
4. Clé KMS commune avec les clés de domaine, ou clé dédiée au state.
5. State du bootstrap : (a) local au premier apply puis migré dans le bucket, (b) local chiffré durablement, (c) bucket créé à la main.

## Décision

- **Bucket partagé** (option 1) : `<préfixe>-tfstate-<id de compte>`, un état par environnement et par stack (`dev/foundation.tfstate`, `prod/platform.tfstate`, `bootstrap/bootstrap.tfstate`). Dev et prod partagent déjà le compte, un second bucket n'ajouterait pas d'isolation réelle (mêmes administrateurs, même clé de compte) ; l'isolation par environnement repose sur les clés d'objet et les politiques des rôles OIDC d'EN-13 (accès limité au préfixe `<env>/`). Le passage en multi-comptes se fait en changeant `backend.hcl`.
- **Verrou natif S3** (`use_lockfile = true`), sans DynamoDB : une ressource en moins, un coût en moins, et l'option est dépréciée côté DynamoDB dans les backends récents.
- **Clé KMS dédiée au state**, séparée des clés de domaine `data`, `logs`, `ai` (EN-14) : un incident ou une suppression d'une clé de domaine ne rend pas le state illisible, et inversement. Rotation activée, politique de clé explicite, aucun principal `*`. Trois instructions :
  - `EnableIamDelegation` : le principal `arn:<partition>:iam::<compte>:root`, avec les seules actions d'usage (`Encrypt`, `Decrypt`, `ReEncrypt*`, `GenerateDataKey*`, `DescribeKey`). C'est cette instruction qui délègue réellement à IAM : un principal du compte n'utilise la clé que si sa propre politique IAM l'y autorise. Les rôles d'EN-13 reçoivent donc un droit d'usage par politique IAM, sans modifier la politique de clé. (Une première version utilisait un principal `*` conditionné par `aws:PrincipalAccount` ; ce n'est pas une délégation, cela donnait la clé à tout principal du compte sans politique IAM, y compris les rôles Lambda.)
  - `RootLockoutRecovery` : `DescribeKey`, `GetKeyPolicy`, `PutKeyPolicy` pour `:root`, minimum conseillé par AWS pour sortir d'un verrouillage. `ScheduleKeyDeletion` et `DisableKey` ne sont jamais accordés à `:root`.
  - `KeyAdministration` : les `admin_principal_arns` (humain du bootstrap, rôle de secours), seuls habilités à administrer la clé (`PutKeyPolicy`, `DisableKey`, `ScheduleKeyDeletion`, rotation, alias, tags). Le rôle CI d'EN-13 ne reçoit que l'usage, plus un `Deny` IAM explicite sur `kms:ScheduleKeyDeletion`, `kms:PutKeyPolicy` et `kms:DisableKey`.
- **Politique de bucket** : refus sans `aws:SecureTransport`, refus de TLS < 1.2, refus des écritures dont l'en-tête SSE n'est pas `aws:kms` ou qui désignent une autre clé (les clients doivent donc fournir `kms_key_id` sous forme d'ARN complet), refus de SSE-C (`DenySSEC` : une requête SSE-C n'a pas d'en-tête `x-amz-server-side-encryption`, elle échapperait aux deux refus `IfExists` et produirait un état illisible). `DenyRecoveryTampering` protège le chemin de récupération : `s3:DeleteObjectVersion`, `s3:PutBucketVersioning`, `s3:PutLifecycleConfiguration`, `s3:DeleteBucketPolicy` et `s3:PutBucketPolicy` sont refusés sauf si `aws:PrincipalArn` fait partie de `admin_principal_arns`. Conséquence : seuls ces administrateurs peuvent appliquer un changement de versioning, de cycle de vie ou de politique du bucket, donc l'exécutant du bootstrap doit figurer dans la liste.
- **Principaux administrateurs** : variable `admin_principal_arns` du bootstrap (sans valeur par défaut, au moins un rôle ou utilisateur IAM existant, ARN sans joker). Elle couvre à la fois la clé et le bucket. À renseigner dans un `terraform.tfvars` non versionné (modèle : `terraform.tfvars.example`).
- **Isolation dev / prod** : le chiffrement ne sépare pas dev et prod. Avec une clé de bucket S3, le contexte de chiffrement KMS est l'ARN du bucket, commun aux deux environnements, et le key provider `aws_kms` d'OpenTofu n'accepte pas de contexte de chiffrement. Tout principal autorisé à utiliser la clé peut déchiffrer les états des deux environnements. L'isolation repose uniquement sur les politiques IAM par préfixe S3 (`<env>/*`) des rôles OIDC d'EN-13, qui devront donc être testées.
- **Chiffrement client** : chaque stack déclare un bloc `encryption` (`aws_kms` + `aes_gcm`, `enforced = true` pour state et plan), alimenté par `state_kms_key_arn`. Un état lu par une personne ayant accès au bucket seul reste illisible.
- **State du bootstrap** (option 5a) : premier apply avec un state local (le bucket n'existe pas encore ; le state ne contient que des noms et ARN, aucun secret, et reste ignoré par git). Ensuite, le bloc `backend "s3"` commenté de `infra/bootstrap/backend.tf` est activé et `tofu init -migrate-state` déplace le state dans le bucket (`bootstrap/bootstrap.tfstate`). Le fichier local est supprimé après vérification. Le chiffrement client du bootstrap peut être ajouté ensuite avec un `fallback` temporaire.
- Les ressources sont protégées par `prevent_destroy` ; le bucket n'a pas de `force_destroy`.

## Conséquences

- Positives : un seul backend à opérer, verrou sans service annexe, clé de state isolée, procédure de bootstrap reproductible.
- Négatives / dette : une erreur de politique de bucket ou de clé touche les deux environnements ; le state du bootstrap est local entre le premier apply et la migration ; la perte de la clé KMS rend tous les états irrécupérables (fenêtre de suppression de 30 jours par défaut, versioning actif) ; pas de réplication inter-régions ni de journalisation d'accès au premier apply (journalisation activable plus tard, CloudTrail couvre le compte) ; les principaux administrateurs doivent exister avant le premier apply et rester gérés hors de la CI ; `:root` garde `PutKeyPolicy` pour éviter le verrouillage, donc tout principal du compte dont la politique IAM autorise `kms:PutKeyPolicy` pourrait réécrire la politique de clé : le `Deny` explicite côté rôle CI (EN-13) et la détection ci-dessous compensent.

## Suites

- EN-14 / EN-61 : alerte (EventBridge ou métrique CloudTrail vers SNS) sur `ScheduleKeyDeletion`, `DisableKey` et `PutKeyPolicy` pour la clé de state.
- EN-13 : rôle d'apply limité à l'usage de la clé et au préfixe `<env>/` du bucket, avec `Deny` sur `kms:ScheduleKeyDeletion`, `kms:PutKeyPolicy`, `kms:DisableKey`, et test de l'isolation par préfixe.

## Impact sécurité

Chiffrement double (SSE-KMS avec clé gérée par le client, puis chiffrement client OpenTofu), TLS 1.2 minimum, accès public bloqué, propriétaire d'objet imposé, versions conservées 90 jours par défaut puis expirées. Les sorties du bootstrap (noms et ARN) ne contiennent aucun secret.

## Impact coût

Une clé KMS (environ 1 USD/mois) et un bucket de quelques ko ; l'absence de DynamoDB évite tout coût de verrou. Requêtes KMS négligeables à l'échelle de l'atelier.

## Liens

- EN-12 (`docs/backlog/issues/EN-12.md`), EN-13 (rôles OIDC), EN-14 (clés de domaine)
- ADR [0002](0002-single-account-dev-prod.md), [0009](0009-gitops-no-local-apply.md)
- `.kiro/steering/security.md`, `.kiro/steering/iac.md`
