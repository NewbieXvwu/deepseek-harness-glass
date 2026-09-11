import { execFileSync } from 'node:child_process'
import { mkdir, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { chromium, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { launchWebScaffold, watchConsole, type WebScaffold } from './scaffold.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1280, height: 840 }
const fixtureOverlay = fileURLToPath(new URL('./goal-bar.overlay.yml', import.meta.url))
const officialSourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: process.cwd(), encoding: 'utf8' }).trim()

async function capture(page: Page, tripwire: ReturnType<typeof watchConsole>): Promise<void> {
  const name = 'history-image-lightbox'
  const root = page.locator('#root')
  const geometry = await root.evaluate(node => {
    const rect = node.getBoundingClientRect()
    return {
      root: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
      text: (node.textContent ?? '').replace(/\s+/g, ' ').trim(),
      viewport: { width: innerWidth, height: innerHeight, devicePixelRatio },
    }
  })
  const ariaSnapshot = await page.locator('body').ariaSnapshot()
  await page.screenshot({ path: join(outputDirectory, `${name}.png`) })
  await writeFile(join(outputDirectory, `${name}.json`), JSON.stringify({
    officialSourceCommit,
    viewport,
    locale: 'en-US',
    colorScheme: 'light',
    geometry,
    ariaSnapshot,
    consoleWarnings: tripwire.warnings,
    pageErrors: tripwire.pageErrors,
  }, null, 2) + '\n')
}

describe('reference capture: rc.1 history image lightbox', () => {
  let scaffold: WebScaffold
  let browser: Awaited<ReturnType<typeof chromium.launch>>
  let page: Page
  let tripwire: ReturnType<typeof watchConsole>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    scaffold = await launchWebScaffold({ extraOverlayPath: fixtureOverlay, welcomeNoticePending: true })
    browser = await chromium.launch({ headless: true })
    const context = await browser.newContext({ viewport, locale: 'en-US', colorScheme: 'light', deviceScaleFactor: 1 })
    page = await context.newPage()
    tripwire = watchConsole(page)
    const login = await page.context().request.get(scaffold.authenticatedUrl, { maxRedirects: 0 })
    expect(login.status()).toBe(303)
    await page.goto(`${scaffold.baseUrl}?fixture`, { waitUntil: 'load' })
    await page.waitForSelector('[class*="frame"]', { timeout: 30_000 })
  }, 120_000)

  afterAll(async () => {
    await browser?.close()
    await scaffold?.close()
  })

  it('captures the authorized history gallery with its original-size lightbox open', async () => {
    const tree = page.getByRole('tree', { name: 'Sessions' })
    await tree.waitFor({ timeout: 15_000 })
    const group = tree.getByText('fixture', { exact: true }).first().locator('xpath=ancestor::*[@role="treeitem"][1]')
    await group.waitFor({ timeout: 15_000 })
    if (await group.getAttribute('aria-expanded') === 'false') await group.getByText('fixture', { exact: true }).click()

    const session = tree.getByText('Fixture 历史会话', { exact: true })
    await session.waitFor({ timeout: 15_000 })
    await session.click()
    const userImage = page.locator('[data-align="end"] img').first()
    const assistantImage = page.locator('[data-align="start"] img').first()
    await userImage.waitFor({ timeout: 15_000 })
    await assistantImage.waitFor({ timeout: 15_000 })
    await expect.poll(() => userImage.getAttribute('src')).toMatch(/^blob:/)
    await expect.poll(() => assistantImage.getAttribute('src')).toMatch(/^blob:/)

    const frame = userImage.locator('xpath=ancestor::button[1]')
    await frame.click()
    const dialog = page.getByRole('dialog', { name: 'Original image preview' })
    await dialog.waitFor({ timeout: 10_000 })
    const lightboxImage = dialog.getByRole('img', { name: 'fixture-image.png', exact: true })
    await expect.poll(() => lightboxImage.getAttribute('src')).toMatch(/^blob:/)
    await capture(page, tripwire)

    await dialog.getByRole('button', { name: 'Close original image preview' }).click()
    await expect.poll(() => page.getByRole('dialog').count(), { timeout: 5_000 }).toBe(0)
    expect(tripwire.warnings).toEqual([])
    expect(tripwire.pageErrors).toEqual([])
  }, 120_000)
})
