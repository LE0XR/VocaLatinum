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
| `group_members` | Mitgliedschaften und Rollen | Gruppe, Nutzer, Rolle (`leader`, `deputy_leader`, `member`), Beginn und Ende der Mitgliedschaft. Pro Gruppe gibt es genau einen Gruppenanführer und genau einen gewählten Vize-Anführer. |
| `group_settings` | Gruppeneinstellungen | Gruppe, automatische Chat-Aufbewahrungsdauer, Einstellungszeitpunkt und Frist für die Wahl eines Vize-Anführers. Die Aufbewahrungsdauer wird vom Gruppenanführer oder Vize-Anführer festgelegt. |
| `group_lifecycle` | Gruppenstatus und Fristen | Gruppe, Status, Beginn/Ende einer Frist ohne Vize-Anführer und geplanter Löschzeitpunkt. Wenn innerhalb von zwei Tagen kein Vize-Anführer gewählt wird, wird die Gruppe samt Gruppeninhalten automatisch gelöscht. |
| `group_invites` | Persönliche Gruppeneinladungen | Gruppe, einladender Nutzer, eingeladener Freund, Status und Ablaufdatum. Keine offenen oder wiederverwendbaren Beitrittscodes. |
| `group_messages` | Gruppenchat-Nachrichten und Ankündigungen | Gruppe, Absender, Nachrichtentext, Nachrichtentyp (normal/Ankündigung), Zeitstempel. Nur aktuelle Gruppenmitglieder dürfen lesen und schreiben. |
| `group_attachments` | Bilder und andere freigegebene Chat-Anhänge | Nachricht, interner Speicherpfad, Dateityp, Größe, Upload-Zeit. Zugriff nur für Gruppenmitglieder; sichere Typ-/Größenprüfung und private Speicherung. |
| `group_polls` | Umfragen im Gruppenchat | Gruppe, Ersteller, Frage, Laufzeit, Status. Umfragen können z. B. zur Beratung bei einer Gleichstandsentscheidung dienen. |
| `group_poll_options` | Antwortmöglichkeiten einer Umfrage | Umfrage, Antworttext, Sortierung. |
| `group_poll_votes` | Stimmen zu Gruppen-Umfragen | Umfrage, Option, Nutzer, Zeitstempel. Pro Nutzer und Umfrage höchstens eine gültige Stimme; Änderung nur solange die Umfrage offen ist. |
| `group_message_hidden_for_users` | Persönliches Ausblenden/Löschen | Nachricht, Nutzer, Zeitstempel. Entfernt eine Nachricht nur aus der eigenen Ansicht; andere Gruppenmitglieder sehen sie weiterhin. |
| `group_message_reports` | Meldungen zu Nachrichten und Bildern | Meldender Nutzer, Nachricht/Anhang, Grund, Status, Zeitstempel und Bearbeitung. Meldungen sind nur für berechtigte Moderation sichtbar. |
| `group_user_blocks` | Blockierte Mitspieler | Blockierender Nutzer, blockierter Nutzer, Zeitstempel. Blockieren wirkt für das eigene Konto und kann aufgehoben werden. |
| `group_moderation_actions` | Moderationsnachweise | Gruppe, moderierende Person, betroffener Inhalt, Aktion (z. B. gruppenweit gelöscht), Zeitstempel und optionaler Grund. Nur notwendige Nachweisdaten speichern. |
| `learning_events` | Serverseitig geprüfte Lernereignisse | Eindeutige Ereignis-ID, Nutzer, XP-Änderung, Ereigniszeit. Deduplizierung über eindeutige Event-ID. |
| `group_weekly_goals` | Wöchentliches Gruppenziel | Gruppe, Wochenbeginn, Wochenende, XP-Ziel, Status. Pro Gruppe und Woche höchstens ein aktives Ziel. |
| `group_goal_rewards` | Einmalige Gruppenbelohnung | Gruppe, Ziel/Woche, Belohnungstyp und Vergabezeit. Eindeutigkeit pro Gruppe und Woche verhindert doppelte Vergabe. |
| `user_reward_grants` | Individuelle Zuteilung einer verdienten Belohnung | Nutzer, Gruppenbelohnung, Art und Status. Eindeutigkeit verhindert doppelte Zuteilung. |
| `user_badges` | Gesammelte Abzeichen | Nutzer, Abzeichen-ID, Herkunft (z. B. Gruppenbelohnung oder Belohnungspfad), Vergabezeit. Doppelte Vergabe desselben Abzeichens wird verhindert. |
| `xp_boost_inventory` | Noch nicht verwendete XP-Boosts | Nutzer, Herkunft, Status (verfügbar/eingelöst), Vergabe- und Einlösezeit. Jeder Boost ist ein einzeln einlösbarer Gegenstand. |
| `xp_boost_activations` | Websiteweite Boost-Aktivierungen | Nutzer, Startzeit, Endzeit und lokales Aktivierungsdatum (Europe/Berlin). Serverseitige Begrenzung auf eine Aktivierung pro Nutzer und Kalendertag – unabhängig vom Lernpfad oder Gerät. |

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

### Gruppenchat, Bilder und Umfragen

- Jede Gruppe erhält einen eigenen Chat, der ausschließlich für aktuelle Gruppenmitglieder zugänglich ist. Eine Gruppenmitgliedschaft gewährt weiterhin keinen Zugriff auf persönliche Lernstatistiken.
- Mitglieder können Textnachrichten schreiben und Bilder in den Chat senden. Anhänge werden privat gespeichert und dürfen nicht über öffentliche oder erratbare Links zugänglich sein.
- Der Gruppenanführer kann wichtige Nachrichten als Ankündigungen kennzeichnen bzw. anheften, damit Regeln, Hinweise und Aufgaben gut sichtbar bleiben.
- Jede Gruppe muss zusätzlich zum Gruppenanführer einen Vize-Anführer haben. Der Gruppenanführer wählt ein Gruppenmitglied für diese Rolle aus. Der Vize-Anführer besitzt dieselben Verwaltungs- und Moderationsrechte wie der Gruppenanführer und kann bei Problemen oder Missbrauch durch den Gruppenanführer eingreifen.
- Ist kein Vize-Anführer vorhanden, beginnt eine Frist von zwei Tagen. Wird innerhalb dieser Frist kein neuer Vize-Anführer gewählt, wird die Gruppe automatisch gelöscht. Die Gruppe und ihre Chat-Inhalte sind danach nicht mehr zugänglich.
- Mitglieder können Umfragen mit einer Frage und mehreren Antwortmöglichkeiten erstellen, um die Gruppe zu befragen oder eine Entscheidung vorzubereiten.
- Umfragen haben einen klaren Status und optional eine Laufzeit. Pro Mitglied und Umfrage zählt höchstens eine Stimme; eine Stimmänderung ist nur bis zum Ende der Umfrage möglich.
- Chat, Bilder, Umfragen und Ankündigungen sind nur für aktuelle Gruppenmitglieder sichtbar. Nach dem Austritt oder Entfernen aus einer Gruppe endet der Zugriff auf neue und bisherige Gruppeninhalte; die genaue Aufbewahrung und Sichtbarkeit alter Nachrichten muss vor der Umsetzung festgelegt werden.
- **Eigene Nachrichten für sich löschen:** Jedes Mitglied darf Nachrichten aus der eigenen Ansicht entfernen. Das ist ein persönliches Ausblenden und löscht die Nachricht nicht für andere Mitglieder. Bei Bildern bleiben die Bilddateien für die übrigen berechtigten Gruppenmitglieder verfügbar.
- **Gruppenweite Moderation:** Der Gruppenanführer darf jede Nachricht und jedes Bild in seiner Gruppe für alle Mitglieder löschen, insbesondere bei Beleidigungen, Belästigung, Spam oder ungeeigneten Inhalten. Der Inhalt wird dann für die Gruppe unzugänglich; die Moderationsaktion wird mit minimalen Nachweisdaten protokolliert.
- **Melden:** Mitglieder können Nachrichten und Bilder an die Gruppenmoderation melden. Eine Meldung entfernt den Inhalt nicht automatisch. Der Gruppenanführer kann den gemeldeten Inhalt prüfen und bei Bedarf gruppenweit löschen.
- **Blockieren:** Mitglieder können andere Mitspieler blockieren und die Blockierung später wieder aufheben. Blockieren ist eine persönliche Schutzfunktion und löscht keine Inhalte für andere Gruppenmitglieder. Für das blockierende Mitglied werden Inhalte des blockierten Kontos im Chat ausgeblendet; außerdem wird eine direkte Kontaktaufnahme zwischen diesen Konten unterbunden. Gruppenweite Moderation bleibt Aufgabe des Gruppenanführers.
- Es sollen nur notwendige Daten gespeichert werden. Nutzer sollen keine privaten Kontaktdaten oder sensiblen persönlichen Informationen im Gruppenchat teilen müssen.

### Gruppen

- Eine Einladung darf nur an einen bereits bestätigten Freund gehen.
- Einladungsempfänger müssen aktiv annehmen, bevor sie Mitglied werden.
- Gruppenmitglieder dürfen Gruppennamen, Mitgliederliste und gemeinsamen Fortschritt sehen.
- Gruppenmitglieder dürfen keine persönlichen Lernstatistiken anderer Mitglieder sehen – auch dann nicht, wenn sie gemeinsam in einer Gruppe sind.
- Gruppenchat, Anhänge, Umfragen und Ankündigungen sind nur für aktuelle Mitglieder dieser Gruppe zugänglich.
- Der Gruppenanführer darf bei einem Gleichstand des Glücksrads zwischen den gleichauf liegenden Paketen entscheiden. Er kann vorher über den Gruppenchat beraten und eine Umfrage starten; die endgültige Gleichstandsentscheidung bleibt beim Gruppenanführer.
- Der Gruppenanführer kann wichtige Gruppenhinweise als Ankündigung sichtbar machen. Moderations- und Meldefunktionen müssen vor dem Online-Start umgesetzt sein.
- Gruppen haben keine persönlichen Ranglisten, Vergleichsansichten oder individuellen XP-Anzeigen.
- Nur Gruppenfortschritt und Gruppenbelohnungen werden gemeinsam angezeigt.

## 4. Gemeinsames Wochenziel und XP-Berechnung

- Wochen laufen nach lokaler deutscher Zeit von Montag 00:00 Uhr bis zum folgenden Montag 00:00 Uhr (Europe/Berlin).
- XP zählen für ein Gruppenwochenziel für jedes Mitglied erst ab dem tatsächlichen Zeitpunkt des Gruppeneintritts. Vor dem Beitritt gesammelte XP werden nicht rückwirkend angerechnet. Der Eintrittszeitpunkt wird serverseitig gespeichert.
- Beispiel: Gruppenziel 2.500 XP; die Gruppe hat zusammen 1.600 XP seit den jeweiligen Beitritten gesammelt. Die Gruppenansicht zeigt **1.600 / 2.500 XP**.
- Der Fortschritt wird aus gültigen, serverseitig geprüften Lernereignissen der Gruppenmitglieder aggregiert.
- Die Gruppenansicht erhält nur die Summe. Einzelbeiträge werden nicht offengelegt.
- Ein Lernereignis darf nur einmal zählen. Wiederholtes Laden, Synchronisieren oder Senden desselben Ereignisses darf keine zusätzlichen XP erzeugen.
- Beim Erreichen des Ziels wird die Gruppenbelohnung genau einmal ausgelöst. Datenbank-Eindeutigkeitsregeln müssen doppelte Vergaben verhindern.
- **Belohnungsberechtigt sind ausschließlich Gruppenmitglieder, die im betreffenden Wochenzeitraum seit ihrem tatsächlichen Beitritt mindestens einen gültigen XP-Beitrag zum Gruppenziel geleistet haben.** Mitglieder ohne eigenen Beitrag erhalten keine Belohnung.
- **Auch nicht beitragende Gruppenmitglieder werden informiert**, sobald das Ziel erreicht und die Belohnung verteilt bzw. abholbar ist. Die Mitteilung enthält genau diesen Satz: **„Ohne Fleiß kein Preis“**. Sie bleiben weiterhin Gruppenmitglieder.
- Die individuelle Berechtigungsprüfung und Belohnungszuteilung erfolgen serverseitig. Für jedes berechtigte Mitglied darf es höchstens eine Zuteilung geben. Nicht berechtigte Mitglieder erhalten keine Belohnung, aber die beschriebene Statusmitteilung.
- Für den ersten Start gibt es genau drei **Belohnungspakete**. Pro erreichtem Gruppenziel wird immer nur **ein** Paket vergeben:
  1. **XP-Boost-Paket:** Ein XP-Verdoppler-Gegenstand wird dem Konto gutgeschrieben. Er verdoppelt die während seiner Laufzeit erspielten XP für **30 Minuten**, wird aber nicht automatisch gestartet.
  2. **Abzeichen-Paket:** Das berechtigte Mitglied erhält ein besonderes Gruppen-Abzeichen und zusätzlich **100 XP**. Namensideen für das Abzeichen: **„Gemeinsam unschlagbar“**, **„Ziel erreicht!“** oder **„Lernteam-Legenden“**.
  3. **XP-Paket:** Das berechtigte Mitglied erhält einmalig **500 XP**.
- Die drei Pakete sind Alternativen: Bei einem einzelnen Gruppenziel gibt es nicht mehrere Pakete gleichzeitig. Die Auswahl erfolgt über ein **wöchentliches Glücksrad-Prinzip**:
  1. Zu Beginn jeder neuen Gruppenwoche wird jedes Gruppenmitglied beim Öffnen der Website auf das noch ausstehende Glücksrad hingewiesen. Das Glücksrad wird pro Gruppe und Woche durchgeführt.
  2. Jedes Gruppenmitglied muss das Glücksrad selbst manuell drehen. Der Dreh liefert zufällig genau eines der drei Belohnungspakete als Stimme für die Gruppenentscheidung.
  3. Ein Mitglied kann in derselben Gruppenwoche nur einmal drehen. Das Ergebnis wird gespeichert; erneutes Laden oder ein anderes Gerät ermöglicht keinen zweiten Dreh.
  4. Am Ende des Montags wird geprüft, ob das 50-%-Quorum erreicht wurde. Wenn ja, werden die abgegebenen Stimmen ausgezählt. Das Paket mit den meisten Stimmen wird als einzige Gruppenbelohnung dieser Woche festgelegt; es müssen dafür nicht alle Mitglieder gedreht haben.
  5. Die individuelle Belohnungsberechtigung bleibt davon getrennt: Nur Mitglieder mit mindestens einem gültigen XP-Beitrag erhalten das ausgewählte Paket. Nicht beitragende Mitglieder erhalten stattdessen ausschließlich die festgelegte Mitteilung.
  6. Die Zufallsauswahl, gespeicherten Stimmen, Auszählung und endgültige Paketfestlegung müssen serverseitig erfolgen und gegen Manipulation sowie doppelte Verarbeitung geschützt sein.
- **Automatische Auswahl, wenn am Montag niemand dreht:** Wenn bis zum Ende des Montags kein Gruppenmitglied das Glücksrad manuell gedreht hat, wählt das System automatisch und zufällig eines der drei Belohnungspakete für diese Gruppenwoche aus. Die Auswahl wird serverseitig gespeichert und gilt als endgültige Gruppenentscheidung.
- **Mindestbeteiligung (50-%-Quorum):** Die manuell abgegebenen Glücksrad-Drehungen zählen nur, wenn mindestens 50 % aller zum Abstimmungsstart stimmberechtigten Gruppenmitglieder gedreht haben. Bei einer ungeraden Mitgliederzahl wird auf die nächste ganze Person aufgerundet (z. B. bei 5 Mitgliedern mindestens 3 Drehungen).
- Wird das 50-%-Quorum erreicht, zählen die abgegebenen Drehungen; das Paket mit den meisten Stimmen gewinnt.
- Wird das Quorum bis zum Ende des Montags nicht erreicht, ist die Abstimmung ungültig und das System wählt automatisch zufällig eines der drei Belohnungspakete aus. Die wenigen abgegebenen Drehungen werden dann nicht berücksichtigt.
- **Gleichstand beim Glücksrad:** Wenn zwei oder mehr Belohnungspakete gleich viele Stimmen erhalten, darf der Gruppenanführer (Owner) zwischen den gleichauf liegenden Paketen entscheiden. Möchte er nicht allein entscheiden, kann er die Gruppe vorher im Gruppenchat beraten lassen und dort eine Umfrage erstellen. Die Umfrage dient als Entscheidungshilfe; die abschließende Auswahl bei Gleichstand trifft weiterhin der Gruppenanführer.
- **Abzeichenübersicht:** Alle erhaltenen Abzeichen sollen in einer gemeinsamen Übersicht gesammelt werden. Dort erscheinen sowohl Gruppen-Abzeichen als auch Abzeichen aus dem Belohnungspfad/Pass. Die Übersicht zeigt, welche Abzeichen bereits erhalten wurden; noch nicht erhaltene Abzeichen aus dem Belohnungspfad können dort ebenfalls entsprechend als noch nicht freigeschaltet erkennbar sein.
- **XP-Boost manuell aktivieren:** Ein gutgeschriebener XP-Boost landet zunächst im verfügbaren Bestand und startet nicht automatisch. Auf den Lernpfaden gibt es ein Stern-Symbol. Durch Anklicken wird die Option **„XP-Boost aktivieren“** angezeigt; erst die bewusste Bestätigung startet den Boost. Nach erfolgreicher Aktivierung läuft er genau **30 Minuten**.
- **Websiteweite Tagesbegrenzung:** Pro Nutzer darf höchstens **ein XP-Boost pro Kalendertag** aktiviert werden. Diese Regel gilt für die gesamte Website und alle Lernpfade, nicht je Lernpfad oder Gerät. Auch wenn mehrere Boosts im Bestand liegen, kann nach einer Aktivierung am selben Tag kein zweiter Boost gestartet werden – auch nicht nach Ablauf der ersten 30 Minuten. Der verwendete Boost wird beim Aktivieren verbraucht; weitere Boosts bleiben bis zu einem späteren Tag im Bestand.
- Die Tagesbegrenzung und der Verbrauch werden serverseitig geprüft und gespeichert, damit sie nicht durch einen anderen Browser, ein weiteres Gerät oder mehrere Tabs umgangen werden können.
- Weitere Belohnungsarten können später ergänzt werden.
- Der Wochenwechsel startet einen neuen Zeitraum; vergangene Wochen bleiben für die technische Nachvollziehbarkeit erhalten.

**Noch festzulegen:** Nach welchem Verfahren pro erreichtem Gruppenziel genau eines der drei Belohnungspakete ausgewählt wird. Der endgültige Name des besonderen Gruppen-Abzeichens ist ebenfalls noch auszuwählen.

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
- Nichtmitglieder können weder Gruppenchat-Nachrichten noch Bilder, Umfragen oder Ankündigungen einer Gruppe lesen oder aufrufen.
- Nach dem Austritt bzw. Entfernen aus einer Gruppe wird der Zugriff auf den Gruppenchat und seine Anhänge entzogen.
- Gruppenanführer und Vize-Anführer können die automatische Aufbewahrungsdauer einstellen; abgelaufene Nachrichten und Bilder sind für alle nicht mehr sichtbar.
- Der Vize-Anführer hat dieselben Verwaltungs- und Moderationsrechte wie der Gruppenanführer und kann bei missbräuchlicher Nutzung eingreifen.
- Wenn der Vize-Anführer fehlt, wird die Gruppe nach einer Frist von zwei Tagen automatisch gelöscht, sofern bis dahin kein neuer Vize-Anführer gewählt wurde.
- Mitglieder können eigene Nachrichten nur für sich ausblenden; andere Mitglieder sehen sie weiterhin.
- Der Gruppenanführer kann Nachrichten und Bilder anderer Mitglieder gruppenweit löschen.
- Mitglieder können Nachrichten und Bilder melden; eine Meldung löscht den Inhalt nicht automatisch.
- Mitglieder können andere Mitglieder blockieren; die Blockierung beeinflusst nur die eigene Ansicht und direkte Kontaktmöglichkeiten, nicht die Ansichten der übrigen Gruppe.
- Gruppenmitglieder können Textnachrichten und Bilder austauschen, Umfragen erstellen und Ankündigungen der Gruppenleitung sehen.
- Gruppenleitung kann die automatische Aufbewahrungsdauer ändern; abgelaufene Nachrichten und Bilder sind für alle nicht mehr sichtbar.
- Der Vize-Anführer besitzt dieselben Verwaltungsrechte wie der Gruppenanführer und kann bei dessen missbräuchlicher Nutzung eingreifen.
- Wenn kein Vize-Anführer vorhanden ist, wird nach zwei Tagen ohne Ersatzwahl die Gruppe automatisch gelöscht.
- Umfragen zählen pro Mitglied höchstens eine Stimme und erlauben nur während der Laufzeit eine Stimmänderung.
- Bei einem Gleichstand der Glücksrad-Stimmen kann der Gruppenanführer nach optionaler Beratung und Chat-Umfrage die endgültige Auswahl treffen.
- Nicht-Freunde können nicht eingeladen werden; Einladungen müssen angenommen werden.
- Gruppenansichten enthalten nur gemeinsamen XP-Fortschritt, niemals persönliche Ranglisten.
- Eine Gruppe ohne Vize-Anführer wird nach zwei Tagen automatisch gelöscht, wenn bis dahin kein Ersatz gewählt wird.
- Ein Lernereignis wird auch bei wiederholter Übertragung nur einmal gezählt.
- Das Wochenziel, die Glücksrad-Auswertung und die Belohnung werden bei parallelen Anfragen nicht doppelt verarbeitet.
- Jedes Gruppenmitglied sieht zu Wochenbeginn das Glücksrad für die jeweilige Gruppe und kann pro Gruppenwoche genau einmal manuell drehen.
- Glücksrad-Drehungen werden zufällig und serverseitig erzeugt, gespeichert und können weder wiederholt noch nachträglich geändert werden.
- Das Belohnungspaket mit den meisten Stimmen wird nach Abschluss aller Drehungen als einziges Paket für die Gruppenwoche ausgewählt.
- Wenn am Montag niemand manuell dreht, wird eines der drei Pakete automatisch und zufällig serverseitig ausgewählt.
- Die manuelle Abstimmung zählt nur bei mindestens 50 % Beteiligung der stimmberechtigten Gruppenmitglieder; bei weniger als 50 % wird sie verworfen und das Paket automatisch zufällig ausgewählt.
- Bei ungerader Mitgliederzahl wird die erforderliche Mindestzahl aufgerundet.
- Nur Mitglieder mit mindestens einem gültigen XP-Beitrag im maßgeblichen Zeitraum erhalten eine Belohnung.
- Nicht beitragende Mitglieder erhalten nach Zielerreichung eine Mitteilung, aber keine Belohnung.
- Der XP-Verdoppler läuft exakt 30 Minuten und wird nicht versehentlich mehrfach für dieselbe Belohnung aktiviert.
- Eine feste XP-Belohnung von 400 XP wird pro berechtigtem Mitglied nur einmal gutgeschrieben.
- Ein besonderes Gruppen-Abzeichen wird nur berechtigten Mitgliedern zugeteilt und nicht doppelt vergeben.
- Gruppen-Abzeichen und Abzeichen aus dem Belohnungspfad/Pass erscheinen in derselben Abzeichenübersicht.
- Pro Gruppenziel wird genau ein Belohnungspaket vergeben, niemals mehrere Pakete gleichzeitig.
- Ein XP-Boost startet erst nach bewusster manueller Aktivierung durch das Stern-Symbol auf einem Lernpfad.
- Ein XP-Boost dauert genau 30 Minuten; der Boost-Gegenstand wird bei Aktivierung verbraucht.
- Auch bei mehreren verfügbaren Boost-Gegenständen kann pro Nutzer und Europe/Berlin-Kalendertag nur ein Boost aktiviert werden – selbst wenn der erste Boost bereits abgelaufen ist.
- Die Tagesbegrenzung gilt websiteweit, über alle Lernpfade, Browser, Tabs und Geräte hinweg.
- Ein Abzeichen-Paket vergibt genau ein Gruppen-Abzeichen und zusätzlich 100 XP; ein XP-Paket vergibt genau 500 XP.
- Wochenwechsel und Zeitzonen-/Sommerzeitgrenzen funktionieren korrekt.
- Nicht berechtigte direkte Datenbank- und API-Anfragen werden abgewiesen.

## 7. Bewusst noch nicht umgesetzt

- Kein Authentifizierungsanbieter eingerichtet.
- Keine Online-Datenbank erstellt oder verbunden.
- Keine Freundschaftsanfragen oder Online-Freundesuche aktiviert.
- Keine Online-Gruppen, Einladungen oder Gruppenchats aktiviert.
- Keine Chat-Nachrichten, Bildanhänge, Umfragen, Gruppenankündigungen, Melde-/Blockierfunktionen, Moderationswerkzeuge, automatische Chat-Aufbewahrung oder Vize-Anführer-Verwaltung aktiviert.
- Keine XP-Synchronisierung oder Belohnungsautomatik aktiviert.
- Keine Änderung an `main` und keine Veröffentlichung.

## 8. Entscheidungen für den nächsten Konzeptschritt

Vor der SQL-Migration müssen wir noch festlegen, wie doppelte Anzeigenamen in Suchergebnissen unterscheidbar angezeigt werden sollen, ohne interne IDs preiszugeben, und welche festen Auswahlwerte für die vom Gruppenanführer einstellbare Chat-Aufbewahrungsdauer angeboten werden sollen. Danach kann die konkrete Datenbankmigration samt RLS-Regeln entworfen und zunächst isoliert getestet werden.
