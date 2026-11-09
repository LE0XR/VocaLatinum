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
});
