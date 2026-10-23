# packages/contracts

Source of truth for the SmartCampus AI HTTP API. This contract is shared by:

- **SE** — implements the Lambda handlers (`services/`) and the SPA (`frontend/`) against it.
- **QE** — derives smoke, BOLA and schema tests (`tests/`) from it.
- **OPS** — generates API Gateway request-validation models and wires each
  operation to a Lambda alias (EN-33).

Any API change starts with a PR on this package. A breaking change is marked
`!` in the commit (scope `contracts`) and called out in the PR description.

## Files

| File | Purpose |
|---|---|
| `openapi.yaml` | OpenAPI 3.1 description of every operation, parameters and responses |
| `schemas/common.json` | Shared primitives: `Id`, `Timestamp`, `Date`, `Sub`, `Error`, pagination |
| `schemas/ticket.json` | Ticket statuses, category, priority, ticket payloads and audit events |
| `schemas/attachment.json` | Presigned upload request and response |
| `schemas/chat.json` | Chat sessions, messages, send-message request/response |
| `schemas/kpi.json` | KPI summary and trend |

Schemas are JSON Schema draft 2020-12 so they can be reused directly as API
Gateway models and compiled into front/back types.

## Conventions

- **Base path.** All paths are served under `/api` via CloudFront (`/api/*`
  behaviour). The SPA and API share the same origin, so there is **no CORS**.
- **Auth.** Every operation requires a Cognito access token
  (`Authorization: Bearer <jwt>`), validated by the native API Gateway Cognito
  authorizer. Groups are read from `cognito:groups`.
- **Identity.** A caller's identity is always the JWT `sub`. Owner/identity
  fields are server-assigned and ignored if sent in a request body.
- **Admin methods** (`PATCH /tickets/{id}`, `GET /kpi`) additionally check the
  `admin` group in the handler and return `403` otherwise.
- **BOLA.** Reading a ticket or chat session the caller does not own returns
  `404`, never `403`, so existence is not revealed (US03-AC5, US02-AC6).
- **Errors.** All non-2xx responses use the `Error` envelope
  (`code`, `message`, optional `details`, `requestId`). Messages never contain
  ticket or chat content.
- **Enums are French** reference values (US03/US01/US04). Categories and
  priorities are the current working set pending PO confirmation.
- **Pagination** is cursor-based: list responses carry `nextCursor` (null at
  the end); clients pass it back as the `cursor` query parameter.

## Operations

| Method & path | Operation | Lambda | Who | Backlog |
|---|---|---|---|---|
| `GET /tickets` | listTickets | `tickets` | student (own) / admin (all) | US03, US01 |
| `POST /tickets` | createTicket | `tickets` | student | US04, RF01 |
| `GET /tickets/{id}` | getTicket | `tickets` | owner / admin | US03 |
| `PATCH /tickets/{id}` | updateTicket | `tickets` | admin | US01 |
| `POST /tickets/{id}/attachments` | createAttachmentUpload | `tickets` | student | US04-AC6 |
| `GET /chat/sessions` | listChatSessions | `chat` | student (own) | US02 |
| `DELETE /chat/sessions` | deleteChatHistory | `chat` | student (own) | US08 |
| `GET /chat/sessions/{id}` | getChatSession | `chat` | owner | US02 |
| `POST /chat/messages` | sendChatMessage | `chat` | student | US02, RF03, US10 |
| `GET /kpi` | getKpi | `kpi` | admin | US05 |

## Domain rules baked into the contract

- **Ticket statuses:** `Ouvert`, `En cours`, `En attente étudiant`, `Résolu`,
  `Fermé`. A new ticket starts at `Ouvert` (RF01-AC1).
- **Resolution note:** moving to `Résolu` or `Fermé` requires a note; the
  contract expresses the intent, the handler enforces it and returns `400`
  (US01-AC5).
- **Security category:** a `sécurité` ticket is created with priority
  `critique` and triggers an immediate admin alert (US04-AC5). Priority is
  server-assigned on creation.
- **SLA:** creation schedules a one-time escalation at +24 h; this is internal
  and not part of the HTTP surface (RF01, EN-44).
- **Attachments:** presigned POST only, `image/jpeg` or `image/png`, 10 MB max;
  only objects marked clean by Malware Protection are served (EN-43).
- **Chat grounding:** `sendChatMessage` returns `answered: false` and a
  `ticketSuggestion` when the assistant cannot ground an answer (RF03, US10).

## Open points (PO / BA)

These are encoded as a working set and may change via a `contracts` PR:

- Final ticket **categories** (`besoin`, `incident`, `sécurité`?) — US04.
- Final **priority** scale and the SLA escalation target level — US01, RF01.
- Attachment feature confirmation (JPG/PNG ≤ 10 MB) — US04-AC6.

## Changing the contract

1. Open an `area/app` issue describing the change.
2. Edit `openapi.yaml` and the relevant schema(s) in the same PR.
3. Validate locally (see below); mark breaking changes with `!`.
4. OPS updates API Gateway models, QE updates tests, SE implements.

### Local validation

The contract is plain OpenAPI 3.1 + JSON Schema. Validate with any standard
tooling, for example:

```sh
# OpenAPI structure
npx @redocly/cli lint packages/contracts/openapi.yaml

# JSON Schema well-formedness
npx ajv-cli compile -s "packages/contracts/schemas/*.json"
```

Pin the exact tool versions once they are added to the toolchain.
