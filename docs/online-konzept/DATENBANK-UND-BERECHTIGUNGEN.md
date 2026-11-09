# VocaLatinum – Online-Konzept: Datenbank und Berechtigungen

**Status:** Entwurf auf Branch `test` – noch keine Online-Funktionen, keine produktive Datenbank und keine Änderung an `main`.

Dieses Dokument beschreibt die geplante Grundlage für spätere Online-Funktionen. Es ist eine fachliche und technische Spezifikation, keine bereits ausgeführte Datenbankmigration.

## 1. Verbindliche Produktregeln

1. **Freunde und Gruppen sind getrennte Bereiche.**
   - Freundschaften ermöglichen – nur nach Annahme – den Zugriff auf ausdrücklich freigegebene persönliche Profil- und Statistikfelder.
   - Gruppen dienen ausschließlich gemeinsamen Lernzielen und gemeinschaftlichen Belohnungen.
2. **Gruppenmitgliedschaft ist keine Freundschaft.** Ein Gruppenmitglied erhält dadurch keinerlei Zugriff auf persönliche Statistiken.
3. **Privat ist der Standard.** Alle persönlichen Freigaben sind anfangs ausgeschaltet.
4. **Interne IDs bleiben geheim.** Sie dienen ausschließlich der eindeutigen technischen Zuordnung. Sie sind weder Suchbegriff noch Freundschaftscode oder Passwort.
5. **Anzeigenamen sind nicht eindeutig.** Die Datenbank identifiziert Konten niemals über den Namen.
6. **Keine Ranglisten in Gruppen.** Gruppenansichten zeigen nur Gruppenziel, Gesamtfortschritt und Gruppenbelohnung – keine individuellen XP, Lernserien, Trefferquoten oder Rangplätze.
7. **Nur bestätigte Freunde können zu einer Gruppe eingeladen werden.**
8. **Sicherheitsregeln gelten serverseitig.** Ausgeblendete Schaltflächen oder Prüfungen im Browser sind kein Zugriffsschutz.

## 2. Vorgeschlagene Datenbankstruktur

Die spätere Datenbank soll PostgreSQL verwenden. Falls Supabase als Backend gewählt wird, kann dessen Authentifizierung und Row Level Security (RLS) genutzt werden. Die endgültige Plattformentscheidung und die konkrete SQL-Migration erfolgen erst in einem späteren Schritt.

| Tabelle | Zweck | Wichtige Felder / Regeln |
|---|---|---|
| `profiles` | Öffentlich auffindbarer, minimaler Profilteil | `user_id` (UUID aus Auth), `display_name`, Erstellungsdatum. Name ist nicht eindeutig. Keine internen IDs nach außen geben. |
| `profile_sharing` | Freigaben des Profilinhabers | `user_id`, einzelne Freigabe-Schalter für Profilfelder und Statistikbereiche; alles standardmäßig `false`. |
| `friend_requests` | Freundschaftsanfragen | Absender, Empfänger, Status (`pending`, `accepted`, `rejected`, `cancelled`), Zeitstempel. Keine Selbstanfragen oder doppelten offenen Anfragen. |
| `friendships` | Bestätigte Freundschaften | Zwei User-IDs in kanonischer Reihenfolge, Erstellungsdatum; eindeutige Kombination. |
| `groups` | Lerngruppen | Gruppen-ID, Name, Ersteller, Erstellungsdatum, Status. |
| `group_members` | Mitgliedschaften und Rollen | Gruppe, Nutzer, Rolle (z. B. owner/member), Beginn und Ende der Mitgliedschaft. |
| `group_invites` | Persönliche Gruppeneinladungen | Gruppe, einladender Nutzer, eingeladener Freund, Status und Ablaufdatum. Keine offenen oder wiederverwendbaren Beitrittscodes. |
| `learning_events` | Serverseitig geprüfte Lernereignisse | Eindeutige Ereignis-ID, Nutzer, XP-Änderung, Ereigniszeit. Deduplizierung über eindeutige Event-ID. |
| `group_weekly_goals` | Wöchentliches Gruppenziel | Gruppe, Wochenbeginn, Wochenende, XP-Ziel, Status. Pro Gruppe und Woche höchstens ein aktives Ziel. |
| `group_goal_rewards` | Einmalige Gruppenbelohnung | Gruppe, Ziel/Woche, Belohnungstyp und Vergabezeit. Eindeutigkeit pro Gruppe und Woche verhindert doppelte Vergabe. |
| `user_reward_grants` | Individuelle Zuteilung einer verdienten Belohnung | Nutzer, Gruppenbelohnung, Art und Status. Eindeutigkeit verhindert doppelte Zuteilung. |

Die interne Auth-ID ist die technische Identität. Ein Anzeigename darf mehrfach vorkommen. Bei der Suche nach Namen wird nur ein minimaler Suchtreffer zurückgegeben; persönliche Statistiken und interne IDs gehören niemals in Suchergebnisse.

## 3. Berechtigungsregeln

### Profil- und Statistikzugriff

- Der Profilinhaber darf das eigene Profil und die eigenen Statistiken sehen.
- Nicht bestätigte Nutzer sehen keine persönlichen Statistiken.
- Bestätigte Freunde sehen ausschließlich die Felder, die der Profilinhaber jeweils freigegeben hat.
- Wird eine Freigabe ausgeschaltet oder die Freundschaft beendet, endet der Zugriff unmittelbar.
- Eine Gruppenmitgliedschaft gewährt keinen Profilzugriff.
- Interne UUIDs, Auth-Daten und technische Ereignisdetails sind für andere Nutzer nicht sichtbar.

### Freundschaftsanfragen

- Eine Anfrage kann nur an ein anderes Konto gehen.
- Empfänger sehen Absender-Anzeigename und Anfrage-Status, nicht die interne ID.
- Erst die Annahme erzeugt eine bestätigte Freundschaft.
- Ablehnen, Abbrechen und Entfernen einer Freundschaft müssen möglich sein.
- Doppelte offene Anfragen und Selbstanfragen werden serverseitig verhindert.

### Gruppen

- Eine Einladung darf nur an einen bereits bestätigten Freund gehen.
- Einladungsempfänger müssen aktiv annehmen, bevor sie Mitglied werden.
- Gruppenmitglieder dürfen Gruppennamen, Mitgliederliste und gemeinsamen Fortschritt sehen.
- Gruppenmitglieder dürfen keine persönlichen Lernstatistiken anderer Mitglieder sehen – auch dann nicht, wenn sie gemeinsam in einer Gruppe sind.
- Gruppen haben keine persönlichen Ranglisten, Vergleichsansichten oder individuellen XP-Anzeigen.
- Nur Gruppenfortschritt und Gruppenbelohnungen werden gemeinsam angezeigt.

## 4. Gemeinsames Wochenziel und XP-Berechnung

- Wochen laufen nach lokaler deutscher Zeit von Montag 00:00 Uhr bis zum folgenden Montag 00:00 Uhr (Europe/Berlin).
- Beispiel: Gruppenziel 2.500 XP; die Gruppe hat zusammen 1.600 XP gesammelt. Die Gruppenansicht zeigt **1.600 / 2.500 XP**.
- Der Fortschritt wird aus gültigen, serverseitig geprüften Lernereignissen der Gruppenmitglieder aggregiert.
- Die Gruppenansicht erhält nur die Summe. Einzelbeiträge werden nicht offengelegt.
- Ein Lernereignis darf nur einmal zählen. Wiederholtes Laden, Synchronisieren oder Senden desselben Ereignisses darf keine zusätzlichen XP erzeugen.
- Beim Erreichen des Ziels wird die Gruppenbelohnung genau einmal ausgelöst. Datenbank-Eindeutigkeitsregeln müssen doppelte Vergaben verhindern.
- Der Wochenwechsel startet einen neuen Zeitraum; vergangene Wochen bleiben für die technische Nachvollziehbarkeit erhalten.

**Noch festzulegen:** Ob XP ab dem Zeitpunkt des Gruppeneintritts zählen oder rückwirkend ab Wochenbeginn; wer bei Zielerreichung die Belohnung erhält (alle aktiven Mitglieder oder nur Mitglieder mit eigenem Beitrag); welche Belohnungen zuerst angeboten werden und wie lange ein zeitlich begrenzter XP-Boost gilt.

## 5. Sicherheitsanforderungen für die spätere Umsetzung

1. Zugriffsschutz durch Datenbankregeln (RLS) und sichere serverseitige Funktionen, nicht nur durch JavaScript im Browser.
2. Keine geheimen Server- oder Service-Schlüssel im Frontend oder im Git-Repository.
3. XP und Belohnungen nicht blind vom Browser übernehmen. Lernereignisse müssen serverseitig geprüft und eindeutig verarbeitet werden.
4. Suchfunktionen geben nur die minimal erforderlichen Profildaten zurück.
5. Änderungen an Freigaben, Freundschaften und Gruppenmitgliedschaften wirken sofort auf nachfolgende Zugriffe.
6. Kontolöschung und Datenaufbewahrung müssen vor einem echten öffentlichen Start geregelt werden.
7. Keine unnötigen persönlichen Daten sammeln. Für die Lernfunktion sind insbesondere Klarname, Schule, genaue Adresse und Standort nicht erforderlich.

## 6. Geplante Tests vor einer Veröffentlichung

Die spätere Online-Implementierung gilt erst dann als bereit für eine Freigabe, wenn mindestens folgende Fälle mit getrennten Testkonten geprüft wurden:

- Zwei Konten mit gleichem Anzeigenamen bleiben technisch eindeutig unterscheidbar.
- Nicht-Freunde können keine persönlichen Statistiken lesen.
- Ein Freund sieht nur freigegebene Felder.
- Das Ausschalten einer Freigabe und das Beenden einer Freundschaft sperren den Zugriff.
- Ein Gruppenmitglied, das kein Freund ist, sieht keinerlei persönliche Statistiken.
- Nicht-Freunde können nicht eingeladen werden; Einladungen müssen angenommen werden.
- Gruppenansichten enthalten nur gemeinsamen XP-Fortschritt, niemals persönliche Ranglisten.
- Ein Lernereignis wird auch bei wiederholter Übertragung nur einmal gezählt.
- Das Wochenziel und die Belohnung werden bei parallelen Anfragen nicht doppelt verarbeitet.
- Wochenwechsel und Zeitzonen-/Sommerzeitgrenzen funktionieren korrekt.
- Nicht berechtigte direkte Datenbank- und API-Anfragen werden abgewiesen.

## 7. Bewusst noch nicht umgesetzt

- Kein Authentifizierungsanbieter eingerichtet.
- Keine Online-Datenbank erstellt oder verbunden.
- Keine Freundschaftsanfragen oder Online-Freundesuche aktiviert.
- Keine Online-Gruppen oder Einladungen aktiviert.
- Keine XP-Synchronisierung oder Belohnungsautomatik aktiviert.
- Keine Änderung an `main` und keine Veröffentlichung.

## 8. Entscheidungen für den nächsten Konzeptschritt

Vor der SQL-Migration müssen wir die offenen Produktentscheidungen aus Abschnitt 4 treffen und klären, wie doppelte Anzeigenamen in Suchergebnissen unterscheidbar angezeigt werden sollen, ohne interne IDs preiszugeben. Danach kann die konkrete Datenbankmigration samt RLS-Regeln entworfen und zunächst isoliert getestet werden.
