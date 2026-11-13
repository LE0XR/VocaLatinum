# Supabase-Datenbank für VocaLatinum

## Aktueller Stand auf Branch `test`

Die Datenbank-Grundlage für den Online-Bereich ist vorbereitet und die automatisierten Prüfungen für den aktuellen Commit sind erfolgreich:

- Supabase-Migrationen werden in GitHub Actions in einer isolierten lokalen Datenbank ausgeführt.
- Datenbanktests (pgTAP): erfolgreich.
- Browser-Tests: erfolgreich.
- Playwright-Tests: erfolgreich.
- Der aktuelle Teststand ist auf Branch `test`; `main` wurde nicht verändert.

**Wichtig:** Das ist noch kein gestarteter Online-Dienst. Es gibt noch kein eingerichtetes echtes Supabase-Projekt, die Migrationen wurden dort noch nicht ausgeführt und die Website ist noch nicht mit Supabase verbunden. Die Online-Funktionen sind deshalb auf der veröffentlichten Lernseite noch nicht nutzbar.

## Bereits vorbereitete Datenbankfunktionen

### Datenschutz und Freundschaften
- Private Profileinstellungen mit standardmäßig ausgeschalteten Freigaben.
- Eindeutiger sechsstelliger Freundescode; Anzeigenamen dürfen mehrfach vorkommen.
- Profilsuche ab drei Zeichen bzw. exakter Freundescode-Suche.
- Serverseitige Begrenzung der Profilsuche (20 Suchanfragen je zehn Minuten).
- Serverseitige Begrenzung ausgehender Freundschaftsanfragen (10 je Stunde).
- Freundschaftsanfragen senden, auflisten, annehmen und ablehnen.
- Bestätigte Freundschaften auflisten und Freundschaften beenden.
- Profilfreigaben verwalten und die Freigabeeinstellungen bestätigter Freunde abrufen.

### Gruppen
- Gruppen mit Gruppenleitung und Stellvertretung erstellen.
- Gruppen auflisten und bestätigte Freunde einladen.
- Gruppeneinladungen auflisten und annehmen/ablehnen.
- Gruppenmitglieder auflisten, austreten und durch die Gruppenleitung entfernen.
- Stellvertretung wechseln und Gruppenleitung übertragen.

### Gruppenchat und Umfragen
- Textnachrichten senden und auflisten.
- Eigene Nachrichten löschen; Gruppenleitung/Stellvertretung kann Nachrichten moderieren.
- Nachrichten melden sowie Mitglieder individuell blockieren/entblockieren.
- Umfragen erstellen, abstimmen, auflisten und schließen.
- Aufbewahrungsdauer für Chatnachrichten konfigurieren.

## Sicherheitsprinzipien

- Profile und persönliche Freigaben sind standardmäßig privat.
- Interne Auth-UUIDs werden nicht in Freundes- oder Gruppenlisten ausgegeben.
- Anzeigenamen werden nicht als eindeutige Kontokennung verwendet.
- Datenbanktabellen sind mit Row Level Security (RLS) geschützt; Clientrollen erhalten nur ausdrücklich notwendige Rechte.
- Kritische Abläufe werden über serverseitig geprüfte RPC-Funktionen ausgeführt.
- Die CI-Tests verwenden künstliche Konten und benötigen keine echten Nutzerkonten oder Projekt-Schlüssel.

## Noch nicht umgesetzt bzw. nicht live

1. Echtes Supabase-Projekt einrichten und sicher verwalten.
2. Migrationen nach Prüfung kontrolliert auf das echte Projekt anwenden.
3. Registrierung, Anmeldung und Sitzungsverwaltung in der Website integrieren.
4. Website mit Supabase verbinden und die Oberfläche an die RPC-Funktionen anschließen.
5. Tatsächliche Lernstände/XP mit Profilfreigaben verbinden.
6. Gruppen-XP, Wochenziele, Teilnahmeprüfung und Belohnungsvergabe umsetzen.
7. Glücksrad und XP-Boost-Inventar/Aktivierung umsetzen.
8. Private Bild-Uploads mit Dateiprüfung und Zugriffsregeln ergänzen.
9. Automatische Moderation, Verwarnungs-/Sperrabläufe und Überprüfung von Fehlentscheidungen ergänzen.
10. Automatische Ausführung der Chat-Aufbewahrung/gelöschten Nachrichten einrichten und testen.
11. Gruppenfrist ohne Stellvertretung mit automatischer Gruppenlöschung umsetzen.
12. Weitere Tests für alle Online-Abläufe und eine abschließende Sicherheitsprüfung durchführen.

Einige Datenbankgrundlagen für Gruppenchat und Umfragen sind vorhanden; die dazugehörigen Website-Oberflächen, Bild-Uploads und vollständigen Moderationsabläufe fehlen noch. Die Chat-Aufbewahrungsfunktion ist konfigurierbar, die automatische regelmäßige Bereinigung muss aber noch eingerichtet werden.

## Lokale Prüfung

Voraussetzungen: Docker und Supabase CLI.

```bash
supabase start -x studio,edge-runtime,logflare,vector,imgproxy
supabase db reset
supabase test db
supabase stop --no-backup
```

GitHub Actions führt die Migrationen und Datenbanktests in einer kurzlebigen CI-Umgebung aus. Dafür werden keine Zugangsdaten eines echten Supabase-Projekts benötigt.

## Veröffentlichung

Erst nach Einrichtung des echten Backends, Verbindung der Website, Tests mit getrennten Testkonten und einer Sicherheitsprüfung darf der Online-Bereich freigeschaltet werden. Änderungen bleiben bis zu einer ausdrücklichen Freigabe auf Branch `test`; `main` wird nicht automatisch geändert.
