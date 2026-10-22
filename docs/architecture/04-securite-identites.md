# 4 — Frontières de sécurité et identités

Deux vues : (a) identité de la CI, permissions boundaries et isolation dev / prod dans le compte unique ; (b) frontières de confiance à l'exécution, identité des utilisateurs et chiffrement KMS par domaine.

## 4a — Identité CI et permissions boundaries

```mermaid
flowchart LR
  accTitle: Identité CI, rôles OIDC et permissions boundaries
  accDescr: Les workflows GitHub obtiennent un jeton OIDC échangé contre l'un des trois rôles sc-gha, selon le sub du jeton. Ces rôles sont plafonnés par sc-ci-boundary. Chaque rôle apply ne peut créer que des rôles portant la boundary workload de son environnement. Le state est isolé par préfixe. La description complète est sous le diagramme.

  subgraph ghz["Zone GitHub"]
    wpr["Workflows pull_request<br/>forks : aucun jeton OIDC"]
    wdev["Jobs environment: dev<br/>branche develop"]
    wprod["Jobs environment: prod<br/>branche main + approbation"]
  end

  subgraph acct["Compte AWS unique, isolation par préfixe, tag et boundary"]
    oidc["Fournisseur OIDC GitHub<br/>aud = sts.amazonaws.com"]

    subgraph cib["Plafond sc-ci-boundary"]
      rplan["sc-gha-plan<br/>ReadOnlyAccess<br/>+ Deny des lectures de données"]
      radev["sc-gha-apply-dev<br/>politiques sc-dev-*"]
      raprod["sc-gha-apply-prod<br/>politiques sc-prod-*"]
    end

    subgraph wbdev["Plafond sc-dev-workload-boundary"]
      wrdev["Rôles sc-dev-*<br/>un par fonction, Scheduler<br/>Knowledge Base, Malware Protection"]
    end

    subgraph wbprod["Plafond sc-prod-workload-boundary"]
      wrprod["Rôles sc-prod-*"]
    end

    subgraph st["State, hors de portée des workloads"]
      bstate[("Bucket de state<br/>dev/ prod/ bootstrap/")]
      kstate["CMK state<br/>Environment=shared"]
    end
  end

  wpr -->|"sub = repo:…:pull_request"| oidc
  wdev -->|"sub = repo:…:environment:dev"| oidc
  wprod -->|"sub = repo:…:environment:prod"| oidc
  oidc --> rplan
  oidc --> radev
  oidc --> raprod

  rplan -.->|"lecture dev/* sans verrou"| bstate
  radev -->|"lecture / écriture dev/*"| bstate
  raprod -->|"lecture / écriture prod/*"| bstate
  bstate ---|"SSE-KMS + chiffrement client"| kstate

  radev -->|"CreateRole si boundary dev"| wrdev
  raprod -->|"CreateRole si boundary prod"| wrprod
  radev --x|"Deny boundary prod"| wrprod
```

### Légende

- Sous-graphe « Plafond » : permissions boundary. Elle n'accorde rien, elle borne les rôles qu'elle contient.
- Flèche pleine : droit d'écriture ou de création. Flèche pointillée : lecture seule. Flèche terminée par une croix : action explicitement refusée.
- `repo:…` : `repo:smart-campus-ai/smart-campus-ai`, condition `StringEquals` sans joker.

### Description textuelle

GitHub Actions présente un jeton OIDC au fournisseur du compte (audience `sts.amazonaws.com`). Le `sub` du jeton détermine le rôle : `pull_request` donne `sc-gha-plan`, l'environnement `dev` donne `sc-gha-apply-dev`, l'environnement `prod` (limité à `main`, avec approbation) donne `sc-gha-apply-prod`. Les PR de forks n'obtiennent pas de jeton. Aucune clé longue durée n'existe.

Les trois rôles sont plafonnés par `sc-ci-boundary`. Celle-ci leur interdit de modifier les boundaries, leur propre identité `sc-gha-*` et le fournisseur OIDC, et de créer des utilisateurs ou des clés d'accès. Le rôle plan lit tout sauf les données (secrets, items, logs, messages) et seulement le state de dev, sans verrou. Chaque rôle apply n'écrit que sous le préfixe de state de son environnement et ne crée que des rôles `sc-<env>-*` portant la boundary workload de cet environnement ; la boundary de l'autre environnement est refusée.

Les boundaries workload limitent tout rôle applicatif aux ressources `sc-<env>-*` ou au tag `Environment=<env>`. Elles excluent IAM, le bucket et la clé de state, et toute session fédérée. Le bucket de state est chiffré deux fois, côté serveur par la CMK de state et côté client par OpenTofu. Une partie des risques résiduels n'est pas représentée : ressources non taggables, contenu des politiques de confiance. Ils sont listés dans l'ADR-0012.

## 4b — Frontières de confiance, identité utilisateur et KMS par domaine

```mermaid
flowchart LR
  accTitle: Frontières de confiance à l'exécution et chiffrement KMS par domaine
  accDescr: Les requêtes venues d'Internet traversent la bordure (CloudFront et deux web ACL), puis l'authentification Cognito, avant d'atteindre les fonctions Lambda plafonnées par la boundary workload. Les données sont chiffrées par trois CMK de domaine, data, logs et ai. Les services AWS qui assument un rôle sont conditionnés par aws:SourceArn et aws:SourceAccount. La description complète est sous le diagramme.

  subgraph z0["Zone 0 : Internet, non fiable"]
    u["Navigateur"]
    directapi["Appel direct à l'URL execute-api"]
  end

  subgraph z1["Zone 1 : bordure"]
    cf["CloudFront<br/>+ WAF CLOUDFRONT"]
    wafr["WAF REGIONAL<br/>débit par Authorization et par IP"]
  end

  subgraph z2["Zone 2 : authentification"]
    cog["Cognito User Pool<br/>code + PKCE, MFA admin"]
    entra["Entra ID<br/>option"]:::opt
    authz["Authorizer Cognito natif<br/>signature, expiration<br/>émetteur, audience"]
  end

  subgraph z3["Zone 3 : traitements, boundary workload"]
    h["Handlers Lambda<br/>identité = sub du JWT<br/>admin = cognito:groups"]
    svc["Principaux de service<br/>Scheduler, Bedrock, GuardDuty<br/>conditions aws:SourceArn / aws:SourceAccount"]
  end

  subgraph z4["Zone 4 : données chiffrées par CMK, rotation activée"]
    kdata["CMK data"]
    klogs["CMK logs"]
    kai["CMK ai"]
    ddata[("DynamoDB tickets, chat-sessions, kpi<br/>S3 pièces jointes")]
    dlogs[("CloudWatch Logs<br/>Lambda, accès API, aws-waf-logs-*")]
    dai[("S3 documents sources, S3 Vectors<br/>Guardrail")]
  end

  u -->|"HTTPS"| cf
  u -->|"authentification"| cog
  cog -.->|"fédération OIDC"| entra
  cog -->|"JWT, accès ≤ 60 min"| u
  cf -->|"/api/*"| wafr
  directapi -->|"même contrôle"| wafr
  wafr --> authz
  authz -->|"JWKS du pool"| cog
  authz -->|"claims validés"| h
  h -->|"IAM + TLS"| ddata
  h -.->|"logs JSON sans PII"| dlogs
  h -->|"IAM + TLS"| dai
  svc -->|"Scheduler : invoque escalation"| h
  svc -->|"GuardDuty : analyse et tag"| ddata
  svc -->|"Bedrock KB : sources, vecteurs"| dai
  kdata --- ddata
  klogs --- dlogs
  kai --- dai

  classDef opt stroke-dasharray: 5 5
```

### Légende

- Zone : frontière de confiance. Une requête ne passe à la zone suivante qu'après le contrôle de la zone qu'elle quitte.
- Trait sans flèche entre une CMK et un stockage : clé qui chiffre ce stockage.
- Bordure pointillée : composant optionnel (`enable_entra_federation`).
- Toutes les CMK existent par environnement (alias `sc-<env>-data`, `-logs`, `-ai`). La CMK de state, partagée, est sur la vue 4a.

### Description textuelle

Zone 0 : tout ce qui vient d'Internet est non fiable, y compris un appel direct à l'URL `execute-api`, qui ne peut pas être désactivée sans domaine personnalisé. Zone 1 : CloudFront applique la web ACL CLOUDFRONT, TLS 1.2 minimum et les en-têtes de sécurité. Chaque appel à l'API, qu'il vienne de CloudFront ou d'un appel direct, passe ensuite par la web ACL REGIONAL et ses limites de débit.

Zone 2 : l'utilisateur s'authentifie auprès de Cognito (code + PKCE, MFA pour les admins, fédération Entra en option) et reçoit un jeton d'accès de 60 minutes au plus. L'authorizer natif de l'API vérifie la signature, l'expiration, l'émetteur et l'audience ; un jeton absent ou invalide donne 401.

Zone 3 : les handlers prennent l'identité de l'étudiant dans le `sub` du JWT, jamais dans la requête (OWASP API1/BOLA), et vérifient `cognito:groups` pour les méthodes admin. Chaque fonction a son rôle, plafonné par la boundary workload de l'environnement. Les services AWS qui assument un rôle (Scheduler, Bedrock, GuardDuty Malware Protection) sont limités par `aws:SourceArn` et `aws:SourceAccount` (protection contre le confused deputy).

Zone 4 : les données sont chiffrées par trois CMK de domaine. `data` couvre les tables et le bucket des pièces jointes, `logs` les groupes CloudWatch Logs, dont les logs WAF, `ai` le bucket des sources, l'index S3 Vectors et le Guardrail. Les logs ne contiennent ni en-tête `Authorization`, ni corps de requête, ni PII en clair. Tous les accès aux services AWS passent par TLS et IAM, sans VPC.

## Décisions liées

- [ADR-0002](../adr/0002-single-account-dev-prod.md) Compte unique, isolation par préfixe
- [ADR-0004](../adr/0004-rest-api-regional-waf.md) Deux web ACL, protection de `execute-api`
- [ADR-0005](../adr/0005-native-cognito-authorizer.md) Authorizer Cognito natif, BOLA par le `sub`
- [ADR-0006](../adr/0006-no-vpc.md) Pas de VPC : TLS + IAM vers les API régionales
- [ADR-0007](../adr/0007-s3-vectors.md) S3 Vectors chiffré par la CMK `ai`
- [ADR-0011](../adr/0011-state-backend-bootstrap.md) CMK de state dédiée, double chiffrement
- [ADR-0012](../adr/0012-github-oidc-ci-identity.md) Rôles OIDC, boundary CI et boundaries workload par environnement
- [ADR-0013](../adr/0013-workshop-region-us-east-1.md) Région us-east-1, données hors UE acceptées pour l'atelier (utilisateurs de test)
