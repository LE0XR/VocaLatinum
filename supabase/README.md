# Supabase-Datenbank für VocaLatinum

## Status

- Supabase ist als Backend ausgewählt.
- Die erste Migration liegt unter `supabase/migrations/`.
- Die Migration wurde noch **nicht** auf ein echtes Supabase-Projekt angewendet.
- Es wurden keine Zugangsdaten oder Schlüssel im Repository gespeichert.
- Freundschaften, Gruppen, Chat und Uploads sind noch nicht online nutzbar.

## Sicherheitsprinzipien

- Profile und Freigaben sind standardmäßig privat.
- Anzeigenamen müssen nicht eindeutig sein.
- Interne Auth-UUIDs werden nicht über Such- oder Gruppenlisten an andere Nutzer ausgegeben.
- Freundschafts- und Gruppentabellen haben in dieser ersten Stufe keine direkten Client-Rechte.
- Jede Tabelle hat Row Level Security (RLS); für Clientrollen gelten ausdrücklich minimale Grants.
- Noch nicht implementierte Abläufe werden erst nach sicheren serverseitigen RPC-Funktionen freigeschaltet.

## Lokal prüfen

Voraussetzungen: Docker und die Supabase CLI.

1. `supabase init` nur ausführen, falls die Projektkonfiguration noch nicht vorhanden ist.
2. `supabase start` starten.
3. `supabase db reset` ausführen, damit Migrationen frisch angewendet werden.
4. `supabase test db` ausführen, um die pgTAP-Prüfungen in `supabase/tests/` zu starten.

Die Tests in dieser ersten Stufe prüfen RLS-Aktivierung und Tabellen-/Spaltenrechte. Vor dem Online-Start müssen zusätzlich echte Zwei-Konten-Tests für jede erlaubte und verbotene Datenabfrage ergänzt und bestanden werden.

## Noch nicht freigeschaltet

- Konto-Registrierung und Anmeldung
- Suche nach Anzeigenamen und Freundschaftsanfragen
- Profilfreigaben an bestätigte Freunde
- Gruppenerstellung, Einladungen und Mitgliedschaften
- Gruppenchat, Bilder, Moderations-Bot und Umfragen
- XP-Synchronisierung, Wochenziele, Glücksrad und Belohnungen
- XP-Boost-Aktivierung

Die Migration ist nur das sichere Grundgerüst, kein fertiges Online-System.
