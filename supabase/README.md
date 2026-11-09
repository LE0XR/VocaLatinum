# Supabase-Datenbank für VocaLatinum

## Status

- Supabase ist als Backend ausgewählt.
- Die Datenbankmigrationen liegen unter `supabase/migrations/`.
- Die lokale CLI-Konfiguration liegt in `supabase/config.toml`.
- GitHub Actions startet für Änderungen an `supabase/**` eine isolierte lokale Supabase-Instanz und führt Migrationen sowie pgTAP-Tests aus.
- Die Datenbankgrundlage, Freundschaftsanfragen, Freundescodes und Profilsuche wurden in der isolierten CI-Umgebung erfolgreich getestet.
- Die Migrationen wurden noch **nicht** auf ein echtes Supabase-Projekt angewendet.
- Es wurden keine Zugangsdaten oder Schlüssel im Repository gespeichert.
- Die Website ist noch nicht mit Supabase verbunden.
- Gruppen, Chat und Uploads sind noch nicht online nutzbar.

## Sicherheitsprinzipien

- Profile und Freigaben sind standardmäßig privat.
- Anzeigenamen müssen nicht eindeutig sein.
- Interne Auth-UUIDs werden nicht über Such- oder Gruppenlisten an andere Nutzer ausgegeben.
- Freundschafts- und Gruppentabellen haben keine direkten Client-Rechte; Freundschaftsanfragen laufen über geprüfte RPC-Funktionen.
- Jede Tabelle hat Row Level Security (RLS); für Clientrollen gelten ausdrücklich minimale Grants.
- Noch nicht implementierte Abläufe werden erst nach sicheren serverseitigen RPC-Funktionen freigeschaltet.

## Freundescodes und Profilsuche

- Jedes Profil erhält automatisch einen eindeutigen sechsstelligen Freundescode aus einem Zeichensatz, der leicht verwechselbare Zeichen vermeidet.
- `search_profiles(text)` sucht ab mindestens drei Zeichen nach dem Anfang eines Anzeigenamens oder exakt nach einem Freundescode.
- Das eigene Profil wird ausgeschlossen; höchstens 20 Treffer mit Anzeigename und Freundescode werden zurückgegeben.
- `send_friend_request_by_code(text)` löst den Code serverseitig auf und erstellt die Anfrage, ohne interne Auth-UUIDs an den Client weiterzugeben.
- Die sichtbare Website-Oberfläche ist vorbereitet, aber noch nicht mit einem echten Backend verbunden.

## Lokale Prüfung

Voraussetzungen: Docker und die Supabase CLI.

1. `supabase start -x studio,edge-runtime,logflare,vector,imgproxy`
2. `supabase db reset` – baut die Datenbank frisch auf und spielt alle Migrationen ein.
3. `supabase test db` – führt die pgTAP-Prüfungen aus.
4. `supabase stop --no-backup`

Die automatisierte GitHub-Prüfung führt dieselben Schritte in einer kurzlebigen CI-Umgebung aus. Sie benötigt keine Projekt-URL, keinen Supabase-API-Schlüssel und keine echten Nutzerkonten.

## Tests

- `001_privacy_foundation.test.sql`: RLS-Aktivierung, RLS-Erzwingung und minimale Rollen-/Spaltenrechte.
- `002_two_account_access.test.sql`: zwei künstliche Testkonten; jedes Konto darf ausschließlich das eigene Profil und die eigenen Freigaben lesen und nur den eigenen Anzeigenamen ändern.
- `003_friend_request_workflow.test.sql`: zwei künstliche Testkonten prüfen Senden, eingehende/ausgehende Liste, Empfänger-Annahme, Ablehnung, gespeicherten Freundschaftsstatus und gesperrten direkten Tabellenzugriff.
- `004_friend_code_search.test.sql`: automatisch erzeugte eindeutige Freundescodes, Suche nach Anzeigenamen, Ausschluss des eigenen Kontos, Mindestlänge der Suche und Anfrageversand per Freundescode.

Die Tests verwenden ausschließlich erfundene Konten mit `.invalid`-E-Mail-Adressen. Vor dem Online-Start müssen weitere Zwei-Konten-Tests für Profilfreigaben, Gruppen, Rollen, Chat, Anhänge und Moderation ergänzt und bestanden werden.

## Noch offen

- Echtes Supabase-Projekt durch eine erwachsene Kontoverwaltung einrichten.
- Migrationen kontrolliert auf das Projekt anwenden.
- Registrierung und Anmeldung in der Website einrichten.
- Website sicher mit Supabase verbinden.
- Profilsuche und Freundschaftsanfragen live aktivieren.
- Profilfreigaben an bestätigte Freunde ergänzen.
- Gruppenerstellung, Einladungen und Mitgliedschaften umsetzen.
- Gruppenchat, Bilder, Moderation und Umfragen umsetzen.
- XP-Synchronisierung, Wochenziele, Glücksrad und Belohnungen umsetzen.
- XP-Boost-Aktivierung umsetzen.

**Wichtig:** Erfolgreiche CI-Tests belegen die lokale Datenbanklogik. Sie bedeuten nicht, dass ein echtes Online-Projekt eingerichtet oder die Website bereits verbunden ist.
