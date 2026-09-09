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

async function capture(page: Page, tripwire: ReturnType<typeof watchConsole>): Promise<void> {
  const name = 'error-recovery-reload'
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
    colorScheme: 'light',
    geometry,
    ariaSnapshot,
    consoleWarnings: tripwire.warnings,
    pageErrors: tripwire.pageErrors,
  }, null, 2) + '\n')
  expect(tripwire.warnings).toEqual([])
  expect(tripwire.pageErrors).toEqual([])
}

describe('reference capture: rc.1 CUT1.8 reload recovery', () => {
  let browser: Awaited<ReturnType<typeof chromium.launch>>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    browser = await chromium.launch({ headless: true })
  })

  afterAll(async () => {
    await browser?.close()
  })

  it('captures the recovered conversation after reloading the recorded rc.1 turn', async () => {
    const scaffold = await launchWebScaffold({
      replayFixture: lifecycleFixture,
      replayOverride: lifecycleOverride,
      paceMs: 100,
    })
    const context = await browser.newContext({ viewport, locale: 'en-US', colorScheme: 'light', deviceScaleFactor: 1 })
    const page = await context.newPage()
    const tripwire = watchConsole(page)
    try {
      await page.goto(scaffold.authenticatedUrl, { waitUntil: 'load' })
      await page.waitForSelector('[class*="frame"]', { timeout: 30_000 })
      await connectFreshWorkspace(page, scaffold.workspaceCwd)
      const input = page.locator('[data-composer-input]').first()
      await input.waitFor({ timeout: 10_000 })
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
      await capture(page, tripwire)
    } finally {
      await context.close()
      await scaffold.close()
    }
  }, 120_000)
})
