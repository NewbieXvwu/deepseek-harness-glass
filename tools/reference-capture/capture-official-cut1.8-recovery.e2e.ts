import { execFileSync } from 'node:child_process'
import { mkdir, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { chromium, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import {
  acknowledgeReloadConnectionLoss,
  launchWebScaffold,
  watchConsole,
} from './scaffold.ts'
import { connectFreshWorkspace } from './support.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1280, height: 840 }
const officialSourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: process.cwd(), encoding: 'utf8' }).trim()
const lifecycleFixture = join(process.cwd(), 'snapshots/web/lifecycle-chrome/session.jsonl')
const lifecycleOverride = join(process.cwd(), 'snapshots/web/lifecycle-chrome/replay.override.json')
const prompt = 'Reply with the single word LIGHTHOUSE and stop.'
type CaptureColorScheme = 'light' | 'dark'

async function capture(
  page: Page,
  name: string,
  tripwire: ReturnType<typeof watchConsole>,
  colorScheme: CaptureColorScheme = 'light',
): Promise<void> {
  const geometry = await page.locator('#root').evaluate(root => {
    const rect = root.getBoundingClientRect()
    return {
      root: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
      text: (root.textContent ?? '').replace(/\s+/g, ' ').trim(),
      viewport: { width: window.innerWidth, height: window.innerHeight, devicePixelRatio: window.devicePixelRatio },
      title: document.title,
      activeElement: (() => {
        const active = document.activeElement as HTMLElement | null
        return active === null ? null : {
          tagName: active.tagName,
          role: active.getAttribute('role'),
          ariaLabel: active.getAttribute('aria-label'),
          text: (active.textContent ?? '').replace(/\s+/g, ' ').trim(),
        }
      })(),
    }
  })
  const ariaSnapshot = await page.locator('body').ariaSnapshot()
  await page.screenshot({ path: join(outputDirectory, `${name}.png`) })
  await writeFile(join(outputDirectory, `${name}.json`), JSON.stringify({
    officialSourceCommit,
    viewport,
    locale: 'en-US',
    colorScheme,
    geometry,
    ariaSnapshot,
    consoleWarnings: tripwire.warnings,
    pageErrors: tripwire.pageErrors,
  }, null, 2) + '\n')
  expect(tripwire.warnings).toEqual([])
  expect(tripwire.pageErrors).toEqual([])
}

describe('reference capture: rc.1 CUT1.8 lifecycle surfaces', () => {
  let browser: Awaited<ReturnType<typeof chromium.launch>>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    browser = await chromium.launch({ headless: true })
  })

  afterAll(async () => {
    await browser?.close()
  })

  it('captures the empty hero, recovered conversation, and dark cascade from the recorded rc.1 lifecycle', async () => {
    const scaffold = await launchWebScaffold({
      replayFixture: lifecycleFixture,
      replayOverride: lifecycleOverride,
      paceMs: 100,
    })
    const context = await browser.newContext({
      viewport,
      locale: 'en-US',
      colorScheme: 'light',
      deviceScaleFactor: 1,
      timezoneId: 'Asia/Shanghai',
    })
    const page = await context.newPage()
    const tripwire = watchConsole(page)
    try {
      await page.goto(scaffold.authenticatedUrl, { waitUntil: 'load' })
      await page.waitForSelector('[class*="frame"]', { timeout: 30_000 })
      await connectFreshWorkspace(page, scaffold.workspaceCwd)
      await page.getByText('Into the Unknown', { exact: false }).waitFor({ timeout: 15_000 })
      const input = page.locator('[data-composer-input]').first()
      await input.waitFor({ timeout: 10_000 })
      await capture(page, 'startup-empty-hero', tripwire)

      const settled = scaffold.whenTurnSettled()
      await input.fill(prompt)
      await input.press('Enter')
      await settled
      await page.getByText('LIGHTHOUSE', { exact: true }).waitFor({ timeout: 30_000 })

      const warningStart = tripwire.warnings.length
      await page.reload({ waitUntil: 'load' })
      await page.waitForSelector('[class*="frame"]', { timeout: 30_000 })
      acknowledgeReloadConnectionLoss(tripwire, warningStart)
      await page.getByText('LIGHTHOUSE', { exact: true }).waitFor({ timeout: 30_000 })
      await page.locator('[role="treeitem"][aria-selected="true"]').waitFor({ timeout: 30_000 })
      await capture(page, 'error-recovery-reload', tripwire)

      const sample = async (): Promise<{ token: string; sidebarBg: string; bodyBg: string }> => page.evaluate(() => {
        const sidebar = document.querySelector('[class*="sidebar"], [class*="rail"]') ?? document.body
        return {
          token: getComputedStyle(document.body).getPropertyValue('--dsw-alias-bg-base').trim(),
          sidebarBg: getComputedStyle(sidebar).backgroundColor,
          bodyBg: getComputedStyle(document.body).backgroundColor,
        }
      })
      const light = await sample()
      await page.evaluate(async () => {
        document.body.setAttribute('data-ds-dark-theme', '')
        await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
      })
      const dark = await sample()
      expect(dark.token).not.toBe(light.token)
      expect(dark.sidebarBg !== light.sidebarBg || dark.bodyBg !== light.bodyBg).toBe(true)
      await capture(page, 'dark-theme-cascade', tripwire, 'dark')
      await page.evaluate(() => { document.body.removeAttribute('data-ds-dark-theme') })
      expect(await sample()).toEqual(light)
    } finally {
      await context.close()
      await scaffold.close()
    }
  }, 120_000)
})
