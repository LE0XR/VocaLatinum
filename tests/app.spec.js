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
  await expect(page.locator('#learningCalendar')).toBeVisible();
  expect(errors).toEqual([]);
});

test('Lernkalender und Auswertungen werden gerendert', async ({ page }) => {
  await expect(page.locator('#calendarMonth')).not.toBeEmpty();
  await expect(page.locator('#detailStats')).toContainText('Lernaktionen gesamt');
  await expect(page.locator('#lessonMastery')).not.toBeEmpty();
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
    return { text: document.getElementById('sentenceFeedback').textContent, correct: sentenceCorrectCount };
  });
  expect(feedback.correct).toBe(1);
  expect(feedback.text).toContain('Richtig');
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

test('Tempora-Quiz zeigt Antwortmöglichkeiten', async ({ page }) => {
  await page.evaluate(() => startQuiz('tempora'));
  await expect(page.locator('#quizTitle')).toContainText('Tempora');
  await expect(page.locator('#options .option')).toHaveCount(4);
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

test('Quiz speichert eine richtige Antwort', async ({ page }) => {
  const result = await page.evaluate(() => {
    startQuiz('tempora');
    const question = quizData[0];
    const correctIndex = question[2].indexOf(question[1]);
    answer(correctIndex);
    return state.quizProgress['tempora:0'].correct;
  });
  expect(result).toBe(1);
});

test('Alle App-Bereiche lassen sich ohne Laufzeitfehler öffnen', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const ids = await page.evaluate(() => [...document.querySelectorAll('.page')].map(el => el.id));
  for (const id of ids) await page.evaluate(id => showPage(id), id);
  expect(ids).toContain('quiz');
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
