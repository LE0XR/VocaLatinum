const { test, expect } = require('@playwright/test');
const fs = require('node:fs/promises');

test.beforeEach(async ({ page }) => {
  await page.goto('/');
});

test('Startseite lädt ohne JavaScript-Ausnahmen', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.reload();
  await expect(page.locator('#home')).toHaveClass(/active/);
  await expect(page.locator('.home-title')).toContainText('Salve');
  await expect(page.locator('.home-stats-open')).toBeVisible();
  await expect(page.locator('#learningCalendar')).toBeHidden();
  expect(errors).toEqual([]);
});

test('Lernkalender und Auswertungen werden gerendert', async ({ page }) => {
  await page.evaluate(() => showPage('stats'));
  await expect(page.locator('#detailStats')).toContainText('Lernaktionen gesamt');
  await expect(page.locator('#lessonMastery')).not.toBeEmpty();
  await page.getByRole('button', { name: /Lernkalender/ }).click();
  await expect(page.locator('#learningCalendar')).toBeVisible();
  await expect(page.locator('#calendarMonth')).not.toBeEmpty();
  await page.getByRole('button', { name: 'Nächster Monat' }).click();
  await expect(page.locator('#calendarMonth')).not.toBeEmpty();
});

test('Einstellung bleibt nach Neuladen gespeichert', async ({ page }) => {
  await page.evaluate(() => showPage('settings'));
  const goal = page.locator('#dailyGoal');
  await goal.fill('35');
  await goal.dispatchEvent('change');
  await page.reload();
  await page.evaluate(() => showPage('settings'));
  await expect(page.locator('#dailyGoal')).toHaveValue('35');
});

test('Backup-Export erzeugt ein gültiges VocaLatinum-JSON', async ({ page }) => {
  await page.evaluate(() => showPage('settings'));
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Backup exportieren' }).click();
  const download = await downloadPromise;
  const path = await download.path();
  const backup = JSON.parse(await fs.readFile(path, 'utf8'));
  expect(backup.app).toBe('VocaLatinum');
  expect(backup.schemaVersion).toBe(1);
  expect(Array.isArray(backup.data.vocab)).toBeTruthy();
});

test('Karteikarten- und Formenbereiche lassen sich öffnen', async ({ page }) => {
  await page.evaluate(() => showPage('cards'));
  await expect(page.locator('#cards')).toHaveClass(/active/);
  await page.evaluate(() => showPage('forms'));
  await expect(page.locator('#forms')).toHaveClass(/active/);
});

test('Service Worker stellt die App-Shell für Offline-Aufrufe bereit', async ({ page, context }) => {
  await page.evaluate(async () => {
    if (!('serviceWorker' in navigator)) throw new Error('Service Worker wird nicht unterstützt');
    await navigator.serviceWorker.ready;
  });
  await page.reload();
  await context.setOffline(true);
  await page.reload();
  await expect(page.locator('.home-title')).toContainText('Salve');
  expect(await page.evaluate(() => typeof XLSX)).toBe('object');
});

test('Fällige Karten enthalten nur tatsächlich fällige Vokabeln', async ({ page }) => {
  const count = await page.evaluate(() => {
    state.vocab[0].seen = 1;
    state.vocab[0].next = 0;
    state.vocab[1].seen = 1;
    state.vocab[1].next = Date.now() + 60 * 60 * 1000;
    save();
    showPage('cards');
    setCardMode('due', document.querySelector('[data-mode="due"]'));
    startCards();
    return sessionCards.length;
  });
  expect(count).toBe(1);
});

test('Karteikarten-Antwort aktualisiert Lernstand und Aktivitätsprotokoll', async ({ page }) => {
  const result = await page.evaluate(() => {
    showPage('cards');
    setCardMode('all', document.querySelector('[data-mode="all"]'));
    startCards();
    revealCard();
    rate(true);
    const first = state.vocab.find(v => (v.seen || 0) > 0);
    return { seen: first.seen, correct: first.correct, box: first.box, cards: state.activity[todayKey()].cards };
  });
  expect(result.seen).toBeGreaterThan(0);
  expect(result.correct).toBeGreaterThan(0);
  expect(result.box).toBeGreaterThan(0);
  expect(result.cards).toBe(1);
});

test('Vokabelsuche findet einen vorhandenen lateinischen Eintrag', async ({ page }) => {
  await page.evaluate(() => {
    showPage('vocab');
    document.getElementById('search').value = 'puella';
    renderVocab();
  });
  await expect(page.locator('#vocabList')).toContainText('puella');
});

test('CSV-Import erhält Umlaute und Makron-Zeichen', async ({ page }) => {
  await page.evaluate(() => showPage('vocab'));
  page.once('dialog', dialog => dialog.accept());
  await page.locator('#fileImport').setInputFiles({
    name: 'test-import.csv',
    mimeType: 'text/csv',
    buffer: Buffer.from('Latein;Deutsch;Formen;Lektion\namīcus-test;Freund-Test;amīcus-test, -ī;98', 'utf8')
  });
  await expect.poll(() => page.evaluate(() => state.vocab.some(v => v.l === 'amīcus-test' && v.g === 'Freund-Test'))).toBeTruthy();
});

test('Backup-Import stellt XP und Lernstand wieder her', async ({ page }) => {
  const backup = await page.evaluate(() => {
    state.xp = 321;
    save();
    return { app: 'VocaLatinum', schemaVersion: 1, exportedAt: new Date().toISOString(), data: JSON.parse(JSON.stringify(state)) };
  });
  await page.evaluate(() => { state.xp = 0; save(); showPage('settings'); });
  page.once('dialog', dialog => dialog.accept());
  await page.locator('#backup').setInputFiles({
    name: 'vocalatinum-test-backup.json',
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify(backup), 'utf8')
  });
  await page.waitForTimeout(900);
  const xp = await page.evaluate(() => state.xp);
  expect(xp).toBe(321);
});

test('Dark Mode lässt sich aktivieren und speichern', async ({ page }) => {
  await page.evaluate(() => setDark(true));
  await expect(page.locator('body')).toHaveClass(/dark/);
  await page.reload();
  await expect(page.locator('body')).toHaveClass(/dark/);
});

test('Satztrainer kann eine PC-Konstruktion erzeugen', async ({ page }) => {
  const item = await page.evaluate(() => {
    sentenceFilters.difficulties = ['Schwierig'];
    sentenceFilters.constructions = ['PC'];
    sentenceFilters.tenses = ['Präsens'];
    sentenceFilters.modes = ['Indikativ'];
    sentenceRecent.clear();
    return generateUniqueSentence();
  });
  expect(item).toBeTruthy();
  expect(item.construction).toBe('PC');
  expect(item.deAlternatives.length).toBeGreaterThan(0);
  expect(item.la).toMatch(/[.]$/);
  expect(item.de).toMatch(/[.]$/);
});

test('Gleichwertige Übersetzungen werden als richtig akzeptiert', async ({ page }) => {
  const feedback = await page.evaluate(() => {
    sentenceTrainerItems = [{ de: 'Der Junge sieht das Mädchen.', deAlternatives: ['Der Junge erblickt das Mädchen.'] }];
    sentenceTrainerIndex = 0;
    sentenceAnswered = false;
    sentenceCorrectCount = 0;
    document.getElementById('sentenceUserAnswer').value = 'Der Junge erblickt das Mädchen';
    checkSentenceAnswer();
    return { text: document.getElementById('sentenceFeedback').textContent, correct: sentenceCorrectCount, xp: state.xp, events: state.activity[todayKey()].events };
  });
  expect(feedback.correct).toBe(1);
  expect(feedback.text).toContain('Richtig');
  expect(feedback.xp).toBeGreaterThan(0);
  expect(feedback.events).toBe(1);
});

test('Formenlernen stellt Aufgaben bereit', async ({ page }) => {
  const count = await page.evaluate(() => {
    showPage('forms');
    startFormLearning();
    return formTasks.length;
  });
  expect(count).toBeGreaterThan(0);
  await expect(page.locator('#formLearning')).toBeVisible();
});



test('Excel-Import übernimmt eine Arbeitsmappe', async ({ page }) => {
  const base64 = await page.evaluate(() => {
    const wb = XLSX.utils.book_new();
    const ws = XLSX.utils.aoa_to_sheet([
      ['Latein', 'Deutsch', 'Formen', 'Lektion'],
      ['amicus-excel-test', 'Freund Excel', 'amicus, -ī', 97]
    ]);
    XLSX.utils.book_append_sheet(wb, ws, 'Vokabeln');
    return XLSX.write(wb, { bookType: 'xlsx', type: 'base64' });
  });
  await page.evaluate(() => showPage('vocab'));
  page.once('dialog', dialog => dialog.accept());
  await page.locator('#fileImport').setInputFiles({
    name: 'vocalatinum-test.xlsx',
    mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    buffer: Buffer.from(base64, 'base64')
  });
  await expect.poll(() => page.evaluate(() => state.vocab.some(v => v.l === 'amicus-excel-test' && v.g === 'Freund Excel'))).toBeTruthy();
});

test('Automatische Sicherung wird angelegt und angezeigt', async ({ page }) => {
  const count = await page.evaluate(() => {
    state.lastAutoBackupDate = '2000-01-01';
    save();
    showPage('settings');
    return readAutoBackups().length;
  });
  expect(count).toBeGreaterThan(0);
  await expect(page.locator('#autoBackupStatus')).toContainText('automatische Sicherung');
  await expect(page.locator('#restoreAutoBackupBtn')).toBeEnabled();
});

test('Fehlerprotokoll speichert lokale technische Meldungen', async ({ page }) => {
  const count = await page.evaluate(() => {
    addRuntimeError('Testfehler', 'test.js', 42);
    showPage('settings');
    return readRuntimeErrors().length;
  });
  expect(count).toBe(1);
  await expect(page.locator('#errorLogStatus')).toContainText('1 / 30');
});

test('PWA-Manifest ist vorhanden und korrekt konfiguriert', async ({ page }) => {
  const response = await page.request.get('/manifest.webmanifest');
  expect(response.ok()).toBeTruthy();
  const manifest = await response.json();
  expect(manifest.name).toContain('VocaLatinum');
  expect(manifest.display).toBe('standalone');
  expect(manifest.start_url).toBe('./');
});

for (const [construction, tense] of [['PPA', 'Präsens'], ['PPP', 'Perfekt'], ['AcI', 'Präsens']]) {
  test(`Satztrainer erzeugt die Konstruktion ${construction}`, async ({ page }) => {
    const item = await page.evaluate(({ construction, tense }) => {
      sentenceFilters.difficulties = ['Schwierig'];
      sentenceFilters.constructions = [construction];
      sentenceFilters.tenses = [tense];
      sentenceFilters.modes = ['Indikativ'];
      sentenceRecent.clear();
      return generateUniqueSentence();
    }, { construction, tense });
    expect(item).toBeTruthy();
    expect(item.construction).toBe(construction);
    expect(item.la).toMatch(/[.]$/);
    if (construction === 'PPA' || construction === 'PPP') expect(item.deAlternatives.length).toBeGreaterThan(0);
  });
}

test('Formenlernen wertet eine eingegebene richtige Form aus', async ({ page }) => {
  const result = await page.evaluate(() => {
    state.formSettings.mode = 'type';
    startFormLearning();
    const task = formTasks[0];
    document.getElementById('formTyped').value = task.form;
    checkFormAnswer();
    return state.formProgress[formTaskKey(task)].correct;
  });
  expect(result).toBe(1);
});



test('Alle App-Bereiche lassen sich ohne Laufzeitfehler öffnen', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const ids = await page.evaluate(() => [...document.querySelectorAll('.page')].map(el => el.id));
  for (const id of ids) await page.evaluate(id => showPage(id), id);
  expect(ids).not.toContain('quiz');
  expect(ids).toContain('sentenceTrainer');
  expect(errors).toEqual([]);
});

test('Startseite bleibt auf einem schmalen Smartphone-Bildschirm ohne horizontales Scrollen', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.reload();
  const widths = await page.evaluate(() => ({ viewport: document.documentElement.clientWidth, content: document.documentElement.scrollWidth }));
  expect(widths.content).toBeLessThanOrEqual(widths.viewport + 1);
});

test('Automatische Sicherung kann mit zusätzlicher Rücksicherung wiederhergestellt werden', async ({ page }) => {
  await page.evaluate(() => {
    const snapshot = JSON.parse(JSON.stringify(state));
    snapshot.xp = 50;
    localStorage.setItem(KEY + '-auto-backups', JSON.stringify([{ date: '2026-01-01', data: snapshot }]));
    state.xp = 999;
    state.lastAutoBackupDate = todayKey();
    save();
  });
  page.once('dialog', dialog => dialog.accept());
  await page.evaluate(() => restoreLatestAutoBackup());
  await page.waitForTimeout(900);
  const result = await page.evaluate(() => ({
    restoredXp: state.xp,
    rollbackXp: JSON.parse(localStorage.getItem(KEY + '-pre-restore-backup')).data.xp
  }));
  expect(result.restoredXp).toBe(50);
  expect(result.rollbackXp).toBe(999);
});

test('Älterer Lernstand wird migriert, ohne XP oder Vokabelfortschritt zu verlieren', async ({ page }) => {
  await page.evaluate(() => {
    const legacy = JSON.parse(JSON.stringify(state));
    legacy.xp = 456;
    delete legacy.activity;
    delete legacy.syncMeta;
    legacy.vocab.push({ id: 'migration-test', l: 'amare-test', g: 'lieben (Test)', forms: '', lessons: [99], box: 3, next: Date.now() + 86400000, seen: 7, correct: 5, wrong: 2, source: false });
    localStorage.setItem(KEY, JSON.stringify(legacy));
  });
  await page.reload();
  const result = await page.evaluate(() => {
    const vocab = state.vocab.find(v => v.id === 'migration-test');
    return { xp: state.xp, seen: vocab?.seen, correct: vocab?.correct, wrong: vocab?.wrong, box: vocab?.box, activity: !!state.activity, syncDevice: !!state.syncMeta?.deviceId };
  });
  expect(result.xp).toBe(456);
  expect(result.seen).toBe(7);
  expect(result.correct).toBe(5);
  expect(result.wrong).toBe(2);
  expect(result.box).toBe(3);
  expect(result.activity).toBeTruthy();
  expect(result.syncDevice).toBeTruthy();
});

test('Karteikarten funktionieren in beiden Abfragerichtungen', async ({ page }) => {
  const result = await page.evaluate(() => {
    state.direction = 'de-la';
    showPage('cards');
    setCardMode('all', document.querySelector('[data-mode="all"]'));
    startCards();
    toggleDirection();
    return { direction: state.direction, front: document.getElementById('flash').dataset.front, expected: sessionCards[current].l };
  });
  expect(result.direction).toBe('la-de');
  expect(result.front).toBe(result.expected);
});

test('Fehler- und Unsicher-Modus finden die richtigen Vokabeln', async ({ page }) => {
  const result = await page.evaluate(() => {
    state.vocab[0].seen = 1;
    state.vocab[0].wrong = 3;
    state.vocab[0].box = 0;
    state.vocab[1].seen = 1;
    state.vocab[1].wrong = 0;
    state.vocab[1].box = 1;
    return { firstId: state.vocab[0].id, secondId: state.vocab[1].id, errors: getErrorPool().map(v => v.id), uncertain: getUncertainPool().map(v => v.id) };
  });
  expect(result.errors).toContain(result.firstId);
  expect(result.uncertain).toContain(result.firstId);
  expect(result.uncertain).toContain(result.secondId);
});

test('Eigene Vokabeln können hinzugefügt und gespeichert werden', async ({ page }) => {
  const saved = await page.evaluate(() => {
    showPage('add');
    document.getElementById('newLatin').value = 'testare-vocalatinum';
    document.getElementById('newGerman').value = 'testen';
    document.getElementById('newForms').value = 'testare, -avi, -atum';
    document.getElementById('newLessons').value = '99';
    addVocab();
    return state.vocab.find(v => v.l === 'testare-vocalatinum');
  });
  expect(saved).toBeTruthy();
  expect(saved.g).toBe('testen');
  expect(saved.lessons).toContain(99);
});

test('XP, Level-Belohnungen und Lernserie werden aktualisiert', async ({ page }) => {
  const result = await page.evaluate(() => {
    state.xp = 0;
    state.badges = {};
    state.rewardClaimed = {};
    state.antiCheat.lastAnswerAt = 0;
    addXP(1500, 'Regressionstest', true);
    state.streak = 0;
    state.lastDay = null;
    updateStreak();
    return { level: levelFromXp(state.xp), badges: Object.keys(state.badges).length, streak: state.streak };
  });
  expect(result.level).toBeGreaterThan(1);
  expect(result.badges).toBeGreaterThan(0);
  expect(result.streak).toBe(1);
});


test('Ungültiger Backup-Import verändert den bestehenden Lernstand nicht', async ({ page }) => {
  await page.evaluate(() => {
    state.xp = 777;
    save();
    showPage('settings');
  });
  await page.locator('#backup').setInputFiles({
    name: 'ungueltiges-backup.json',
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify({
      app: 'VocaLatinum',
      schemaVersion: 1,
      data: { vocab: [{ l: 'puella', g: '' }] }
    }), 'utf8')
  });
  await expect(page.locator('#toast')).toContainText('Backup ungültig');
  expect(await page.evaluate(() => state.xp)).toBe(777);
  await page.reload();
  expect(await page.evaluate(() => state.xp)).toBe(777);
});

test('Abgebrochener Backup-Import lässt den vorhandenen Lernstand unverändert', async ({ page }) => {
  const backupData = await page.evaluate(() => {
    state.xp = 123;
    save();
    return JSON.parse(JSON.stringify(state));
  });
  await page.evaluate(() => {
    state.xp = 888;
    save();
    showPage('settings');
  });
  page.once('dialog', dialog => dialog.dismiss());
  await page.locator('#backup').setInputFiles({
    name: 'abgebrochenes-backup.json',
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify({
      app: 'VocaLatinum',
      schemaVersion: 1,
      data: backupData
    }), 'utf8')
  });
  await expect.poll(() => page.evaluate(() => state.xp)).toBe(888);
  await page.reload();
  expect(await page.evaluate(() => state.xp)).toBe(888);
});

test('Grammatik-Quiz ist aus der Oberfläche entfernt, Formenlernen bleibt verfügbar', async ({ page }) => {
  await expect(page.getByText('Grammatik-Quiz', { exact: true })).toHaveCount(0);
  await expect(page.locator('#quiz')).toHaveCount(0);
  await page.evaluate(() => showPage('forms'));
  await expect(page.locator('#forms')).toHaveClass(/active/);
});

test('Lernstatistiken sind über drei getrennte Ansichten erreichbar', async ({ page }) => {
  await page.evaluate(() => showPage('stats'));
  await expect(page.locator('[data-stat-view="details"]')).toBeVisible();
  await expect(page.locator('[data-stat-view="calendar"]')).toBeHidden();
  await expect(page.locator('[data-stat-view="vocab"]')).toBeHidden();
  await page.getByRole('button', { name: /Lernkalender/ }).click();
  await expect(page.locator('[data-stat-view="calendar"]')).toBeVisible();
  await expect(page.locator('[data-stat-view="details"]')).toBeHidden();
  await page.getByRole('button', { name: /Vokabeln zum Wiederholen/ }).click();
  await expect(page.locator('[data-stat-view="vocab"]')).toBeVisible();
  await expect(page.locator('[data-stat-view="calendar"]')).toBeHidden();
});


test('KNG-Quiz ordnet jede richtige Antwort korrekt zu und wertet Fehlversuche ohne Laufzeitfehler aus', async ({ page }) => {
  const result = await page.evaluate(() => {
    quizType = 'kng';
    const indices = DATA.kng.map(question => getQuizCorrectIndex(question));
    const question = DATA.kng[0];
    const correct = getQuizCorrectIndex(question);
    const options = document.createElement('div');
    options.id = 'kngRegressionOptions';
    options.innerHTML = question[2].map(option => '<button class="option">' + option + '</button>').join('');
    const feedback = document.createElement('div');
    feedback.id = 'quizResult';
    document.body.append(options, feedback);
    quizData = [question];
    quizIndex = 0;
    answered = false;
    answer((correct + 1) % question[2].length);
    return {
      indices,
      expectedCount: DATA.kng.length,
      correctMarked: options.querySelectorAll('.option.correct').length,
      wrongMarked: options.querySelectorAll('.option.bad').length,
      feedback: feedback.textContent
    };
  });
  expect(result.indices).toHaveLength(result.expectedCount);
  expect(result.indices.every(index => index >= 0)).toBeTruthy();
  expect(result.correctMarked).toBe(1);
  expect(result.wrongMarked).toBe(1);
  expect(result.feedback).toContain('Noch einmal üben');
});


test('Wöchentliche Wettbewerbsstatistiken berechnen alle sieben ausgewählten Kategorien korrekt', async ({ page }) => {
  const stats = await page.evaluate(() => {
    state.activity = {
      '2026-11-09': { events: 10, correct: 8, wrong: 2, xp: 40, cards: 4, cardIds: ['v1', 'v2'], units: 1 },
      '2026-11-10': { events: 5, correct: 4, wrong: 1, xp: 20, cards: 3, cardIds: ['v2', 'v3'], units: 2 },
      '2026-11-11': { events: 0, correct: 0, wrong: 0, xp: 0, cards: 1, cardIds: ['v4'], units: 0 },
      '2026-11-08': { events: 20, correct: 20, wrong: 0, xp: 100, cards: 10, cardIds: ['old'], units: 5 }
    };
    state.badges = {
      5: { title: 'Test 1', date: '09.11.2026' },
      10: { title: 'Test 2', date: '2026-11-10' },
      15: { title: 'Alt', date: '08.11.2026' }
    };
    return getWeeklyCompetitionStats(new Date(2026, 10, 11, 12));
  });
  expect(stats.weekStart).toBe('2026-11-09');
  expect(stats.weekEnd).toBe('2026-11-15');
  expect(stats.correctAnswers).toBe(12);
  expect(stats.wrongAnswers).toBe(3);
  expect(stats.attempts).toBe(15);
  expect(stats.accuracy).toBe(80);
  expect(stats.xp).toBe(60);
  expect(stats.newBadges).toBe(2);
  expect(stats.learnedCards).toBe(4);
  expect(stats.longestStreak).toBe(3);
  expect(stats.completedUnits).toBe(3);
});

test('Wöchentliche Kartenstatistik zählt jede Karte nur einmal und Lernabschlüsse getrennt', async ({ page }) => {
  const stats = await page.evaluate(() => {
    state.activity = {};
    recordCardReview('vocab-1');
    recordCardReview('vocab-1');
    recordCardReview('vocab-2');
    recordCompletedLearningUnit('Karteikarten');
    recordCompletedLearningUnit('Quiz');
    return getWeeklyCompetitionStats(new Date());
  });
  expect(stats.learnedCards).toBe(2);
  expect(stats.completedUnits).toBe(2);
});


test('Freunde-Bereich zeigt alle sieben Wochenwettbewerbskategorien und wechselt die Rangliste', async ({ page }) => {
  await page.evaluate(() => {
    state.profile.name = 'Lernfuchs';
    state.groups = [{
      id: 'grp-weekly-test',
      name: 'Testgruppe',
      code: 'TEST-123',
      ownerId: state.profile.id,
      members: [
        { id: state.profile.id, name: 'Lernfuchs', xp: 25, level: 1, badges: 0 },
        { id: 'friend-local', name: 'Freund' }
      ]
    }];
    state.activity = {
      [todayKey()]: { events: 4, correct: 3, wrong: 1, xp: 25, cards: 2, cardIds: ['a', 'b'], units: 1 }
    };
    state.badges = {};
    save();
    showPage('friends');
  });
  await expect(page.locator('#weeklyCompetitionStats [data-weekly-category]')).toHaveCount(7);
  await expect(page.locator('#weeklyCompetitionStats')).toContainText('Richtige Antworten');
  await expect(page.locator('#weeklyCompetitionStats')).toContainText('Trefferquote');
  await expect(page.locator('#weeklyCompetitionStats')).toContainText('Gesammelte XP');
  await expect(page.locator('#weeklyCompetitionStats')).toContainText('Neue Abzeichen');
  await expect(page.locator('#weeklyCompetitionStats')).toContainText('Gelernte Karten');
  await expect(page.locator('#weeklyCompetitionStats')).toContainText('Längste Lernserie');
  await expect(page.locator('#weeklyCompetitionStats')).toContainText('Abgeschlossene Lerneinheiten');
  await expect(page.locator('#weeklyCompetitionRanking')).toContainText('Lernfuchs');
  await expect(page.locator('#weeklyCompetitionRanking')).toContainText('3 Antworten');
  await expect(page.locator('#weeklyCompetitionRanking')).toContainText('1 Gruppenmitglied(er) haben noch keine synchronisierten Wochenwerte.');
  await page.locator('[data-weekly-category="accuracy"]').click();
  await expect(page.locator('#weeklyCompetitionTitle')).toHaveText('Rangliste · Trefferquote');
  await expect(page.locator('#weeklyCompetitionRanking')).toContainText('75 %');
  await expect(page.locator('[data-weekly-category="accuracy"]')).toHaveClass(/active/);
});

test('Freunde-Profil erhält eine eindeutige private ID und startet standardmäßig privat', async ({ page }) => {
  const initial = await page.evaluate(() => {
    showPage('friends');
    runFriendsSecurityCheck();
    return {
      id: state.profile.id,
      visibility: state.profile.privacy.visibility,
      weekly: state.profile.privacy.shareWeeklyStats,
      progress: state.profile.privacy.shareProgress,
      allowRequests: state.profile.privacy.allowFriendRequests
    };
  });
  expect(initial.id).toMatch(/^usr-[a-f0-9]{32}$/i);
  expect(initial.visibility).toBe('private');
  expect(initial.weekly).toBe(false);
  expect(initial.progress).toBe(false);
  expect(initial.allowRequests).toBe(false);
  await expect(page.locator('#privateUserId')).toHaveText(initial.id);
  await expect(page.locator('#friendsSecurityResults')).toContainText('Online-Datenbank und serverseitige Zugriffsregeln sind noch nicht verbunden');
  await page.reload();
  expect(await page.evaluate(() => state.profile.id)).toBe(initial.id);
});

test('Privatsphäre-Einstellungen lassen sich speichern und bleiben nach Neuladen erhalten', async ({ page }) => {
  await page.evaluate(() => showPage('friends'));
  await page.locator('#privacyFriends').check();
  await page.locator('#shareWeeklyStats').check();
  await page.locator('#shareProgress').check();
  const saved = await page.evaluate(() => ({ ...state.profile.privacy }));
  expect(saved).toEqual({ visibility: 'friends', shareWeeklyStats: true, shareProgress: true, allowFriendRequests: false });
  await page.reload();
  await page.evaluate(() => showPage('friends'));
  await expect(page.locator('#privacyFriends')).toBeChecked();
  await expect(page.locator('#shareWeeklyStats')).toBeChecked();
  await expect(page.locator('#shareProgress')).toBeChecked();
  await expect(page.locator('#allowFriendRequests')).not.toBeChecked();
});

test('Öffentliche Namen und Anzeigen von Wochenwerten sind getrennte Privatsphäre-Einstellungen', async ({ page }) => {
  await page.evaluate(() => showPage('friends'));
  await page.locator('#privacyPublic').check();
  await expect(page.locator('#privacyVisibilityInfo')).toContainText('Öffentlich');
  await page.locator('#shareWeeklyStats').check();
  await page.locator('#shareWeeklyStats').uncheck();
  const privacy = await page.evaluate(() => state.profile.privacy);
  expect(privacy.visibility).toBe('public');
  expect(privacy.shareWeeklyStats).toBe(false);
});

test('Gleiche Anzeigenamen sind erlaubt, die interne ID bleibt der eindeutige Schlüssel', async ({ page }) => {
  const result = await page.evaluate(() => {
    state.profile.name = 'Alex';
    state.groups = [{
      id: 'grp-duplicate-name',
      name: 'Latein',
      code: 'ABC-2345',
      ownerId: 'other-owner',
      members: [{ id: 'usr-other-unique-id', name: 'Alex', xp: 12, level: 1, badges: 0 }]
    }];
    document.getElementById('joinGroupCode').value = 'ABC-2345';
    joinFriendGroup();
    return {
      memberIds: state.groups[0].members.map(member => member.id),
      memberNames: state.groups[0].members.map(member => member.name)
    };
  });
  expect(result.memberNames).toEqual(['Alex', 'Alex']);
  expect(new Set(result.memberIds).size).toBe(2);
});
