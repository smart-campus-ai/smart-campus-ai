"""Demo test data: knowledge-base documents, tickets, chat sessions, KPI aggregates.

Seeds the in-memory stores so the demo shows a realistic, populated campus. Owner
subs match the demo identities: student-001 (alice@esiea.fr), admin-001.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

STUDENT = "student-001"
ADMIN = "admin-001"


def _iso(days_ago=0, hours_ago=0):
    dt = datetime.now(timezone.utc) - timedelta(days=days_ago, hours=hours_ago)
    return dt.isoformat().replace("+00:00", "Z")


# Knowledge base: (title, uri, text, [keywords]) — the demo KB answers these.
KB_DOCS = [
    ("Horaires de la BU", "s3://kb/bu-horaires.md",
     "La bibliothèque universitaire est ouverte du lundi au vendredi de 8h à 20h, et le samedi de 9h à 17h.",
     ["bu", "bibliothèque", "biblio", "horaire", "horaires", "ouvre", "ouverture"]),
    ("Connexion au Wi-Fi eduroam", "s3://kb/wifi-eduroam.md",
     "Pour vous connecter à eduroam, utilisez votre identifiant ESIEA complet (prenom.nom@esiea.fr) et votre mot de passe du campus.",
     ["wifi", "wi-fi", "eduroam", "internet", "réseau", "connexion"]),
    ("Réinitialiser son mot de passe", "s3://kb/mot-de-passe.md",
     "Réinitialisez votre mot de passe sur https://account.esiea.fr ; un e-mail de confirmation vous est envoyé.",
     ["mot de passe", "password", "réinitialiser", "oublié", "compte"]),
    ("Restauration et cafétéria", "s3://kb/resto.md",
     "Le restaurant universitaire sert de 11h30 à 14h. La cafétéria est ouverte de 7h30 à 18h.",
     ["resto", "restaurant", "cafétéria", "cafet", "manger", "repas"]),
]


def seed_tickets(store):
    """Create demo tickets as META + EVENT items (shapes from mapping.py)."""
    import mapping

    def ticket(tid, title, desc, category, status, priority, owner, created_days, assignee=None, location=None):
        created = _iso(created_days)
        meta = {
            "pk": mapping.ticket_pk(tid), "sk": mapping.SK_META, "id": tid,
            "title": title, "description": desc, "category": category,
            "status": status, "priority": priority, "ownerSub": owner,
            "createdAt": created, "updatedAt": created,
        }
        if location:
            meta["location"] = location
        if assignee:
            meta["assigneeSub"] = assignee
        event = {
            "pk": mapping.ticket_pk(tid), "sk": mapping.event_sk(created, 0),
            "at": created, "actorSub": owner, "field": "status",
            "oldValue": None, "newValue": "Ouvert",
        }
        store.put_ticket(meta, event)

    ticket("DEMO000000000000000000001", "Wi-Fi indisponible en salle 204",
           "Impossible de se connecter à eduroam depuis ce matin.", "incident",
           "Ouvert", "normale", STUDENT, 2, location="Bâtiment A, salle 204")
    ticket("DEMO000000000000000000002", "Demande d'accès à la salle projet",
           "Besoin d'un accès badge à la salle projet pour le groupe.", "besoin",
           "En cours", "basse", STUDENT, 5, assignee=ADMIN)
    ticket("DEMO000000000000000000003", "Compte bloqué après plusieurs tentatives",
           "Mon compte est verrouillé, je ne peux plus me connecter.", "incident",
           "Résolu", "haute", STUDENT, 8, assignee=ADMIN)
    # A ticket owned by another student (BOLA/demo isolation target).
    ticket("DEMO000000000000000000004", "Problème de vidéoprojecteur",
           "Le vidéoprojecteur de la salle 110 ne s'allume plus.", "incident",
           "Ouvert", "normale", "student-002", 1, location="Salle 110")


def seed_chat(store):
    """One prior chat session for the student (answered question with sources)."""
    now = _iso(0, 1)
    store.save_session({
        "id": "DEMOCHAT000000000000000001",
        "ownerSub": STUDENT,
        "title": "Horaires de la bibliothèque",
        "messages": [
            {"id": "DEMOMSG0000000000000000001", "role": "user",
             "content": "Quels sont les horaires de la BU ?", "createdAt": now},
            {"id": "DEMOMSG0000000000000000002", "role": "assistant",
             "content": "La bibliothèque universitaire est ouverte du lundi au vendredi de 8h à 20h, et le samedi de 9h à 17h.",
             "createdAt": now,
             "sources": [{"title": "Horaires de la BU", "uri": "s3://kb/bu-horaires.md"}]},
        ],
        "createdAt": now, "updatedAt": now,
        "ttl": int((datetime.now(timezone.utc) + timedelta(days=30)).timestamp()),
    })


def seed_kpi(store):
    """Daily aggregates over the last ~14 days for the KPI dashboard."""
    categories = ("incident", "besoin", "sécurité")
    rows = []
    for d in range(14, -1, -1):
        day = (datetime.now(timezone.utc) - timedelta(days=d)).strftime("%Y-%m-%d")
        # A light, plausible distribution.
        rows.append({"date": day, "status": "Ouvert", "category": "incident",
                     "created": 2 + (d % 3), "resolved": 0, "resolutionSecondsSum": 0, "open": 1 + (d % 2)})
        rows.append({"date": day, "status": "Résolu", "category": "incident",
                     "created": 1, "resolved": 1 + (d % 2), "resolutionSecondsSum": 3600 * (2 + (d % 3)), "open": 0})
        rows.append({"date": day, "status": "Résolu", "category": "besoin",
                     "created": 1, "resolved": 1, "resolutionSecondsSum": 1800, "open": 0})
    store.rows = rows


# Convenience used by the gateway bootstrap.
def seed_all(tickets_service, chat_service, kpi_store):  # pragma: no cover - alt entry
    pass
