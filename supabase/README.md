# Supabase-Datenbank für VocaLatinum

## Status

- Supabase ist als Backend ausgewählt.
- Die erste Migration liegt unter `supabase/migrations/`.
- Die lokale CLI-Konfiguration liegt in `supabase/config.toml`.
- GitHub Actions startet für Änderungen an `supabase/**` eine isolierte lokale Supabase-Instanz und führt Migrationen sowie pgTAP-Tests aus.
- Die Migration wurde noch **nicht** auf ein echtes Supabase-Projekt angewendet.
- Es wurden keine Zugangsdaten oder Schlüssel im Repository gespeichert.
- Freundschaftsanfragen, automatisch erzeugte Freundescodes und eine sichere Profilsuche sind als lokale Datenbank-RPCs vorbereitet und werden in CI getestet; die Website-Anbindung fehlt noch.
- Gruppen, Chat und Uploads sind noch nicht online nutzbar.

## Sicherheitsprinzipien

- Profile und Freigaben sind standardmäßig privat.
- Anzeigenamen müssen nicht eindeutig sein.
- Interne Auth-UUIDs werden nicht über Such- oder Gruppenlisten an andere Nutzer ausgegeben.
- Freundschafts- und Gruppentabellen haben keine direkten Client-Rechte; Freundschaftsanfragen laufen ausschließlich über geprüfte RPC-Funktionen.
- Jede Tabelle hat Row Level Security (RLS); für Clientrollen gelten ausdrücklich minimale Grants.
- Noch nicht implementierte Abläufe werden erst nach sicheren serverseitigen RPC-Funktionen freigeschaltet.

## Lokale Prüfung

Voraussetzungen: Docker und die Supabase CLI.

1. `supabase start -x studio,edge-runtime,logflare,vector,imgproxy`
2. `supabase db reset` – baut die lokale Datenbank frisch auf und spielt alle Migrationen ein.
3. `supabase test db` – führt die pgTAP-Prüfungen aus.
4. `supabase stop --no-backup`

Die automatisierte GitHub-Prüfung führt dieselben Schritte in einer kurzlebigen CI-Umgebung aus. Sie benötigt keine Projekt-URL, keinen Supabase-API-Schlüssel und keine echten Nutzerkonten.

## Tests

- `001_privacy_foundation.test.sql`: RLS-Aktivierung, RLS-Erzwingung und minimale Rollen-/Spaltenrechte.
- `002_two_account_access.test.sql`: zwei künstliche Testkonten; jedes Konto darf ausschließlich das eigene Profil und die eigenen Freigaben lesen und nur den eigenen Anzeigenamen ändern.
- `003_friend_request_workflow.test.sql`: zwei künstliche Testkonten prüfen Senden, eingehende/ausgehende Liste, Empfänger-Annahme, Ablehnung, gespeicherten Freundschaftsstatus und gesperrten direkten Tabellenzugriff.\n- `004_friend_code_search.test.sql`: automatisch erzeugte eindeutige Freundescodes, Suche nach Anzeigenamen, Ausschluss des eigenen Kontos, Mindestlänge der Suche und Anfrageversand per Freundescode.

Die Tests verwenden ausschließlich erfundene Konten mit `.invalid`-E-Mail-Adressen. Vor dem Online-Start müssen weitere Zwei-Konten-Tests für Freundschaftsfreigaben, Gruppen, Rollen, Chat, Anhänge und Moderation ergänzt und bestanden werden.

## Noch nicht freigeschaltet

- Konto-Registrierung und Anmeldung in der Website
- Website-Oberfläche für Profilsuche und Freundschaftsanfragen
- Profilfreigaben an bestätigte Freunde
- Gruppenerstellung, Einladungen und Mitgliedschaften
- Gruppenchat, Bilder, Moderations-Bot und Umfragen
- XP-Synchronisierung, Wochenziele, Glücksrad und Belohnungen
- XP-Boost-Aktivierung

Die Migrationen sind ein getesteter lokaler Datenbankbaustein, aber noch kein fertiges Online-System. Die Website ist noch nicht mit Supabase verbunden.


Die CI-Prüfung läuft bei jeder Änderung an dieser Supabase-Konfiguration oder den Migrationen automatisch auf GitHub Actions.
\n\n## Freundescodes und Profilsuche (Backend)\n\n- Jedes Profil erhält automatisch einen eindeutigen sechsstelligen Freundescode aus einem verwechselungsarmen Zeichensatz.\n- `search_profiles(text)` sucht ab mindestens drei Zeichen nach dem Anfang eines Anzeigenamens oder exakt nach einem Freundescode. Das eigene Konto wird ausgeschlossen; höchstens 20 Treffer mit Anzeigename und Freundescode werden zurückgegeben.\n- `send_friend_request_by_code(text)` löst den Freundescode serverseitig auf und legt die Anfrage an, ohne interne Auth-UUIDs an den Client weiterzugeben.\n- Die Website-Oberfläche, echte Konten und ein echtes Supabase-Projekt sind weiterhin nicht verbunden.\n