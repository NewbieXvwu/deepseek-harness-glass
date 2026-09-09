import { execFileSync } from 'node:child_process'
import { mkdir, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { chromium, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { launchWebScaffold, watchConsole } from './scaffold.ts'
import { connectFreshWorkspace } from './support.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const captureViewport = { width: 480, height: 1000 }
const officialSourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: process.cwd(), encoding: 'utf8' }).trim()
const lifecycleFixture = join(process.cwd(), 'snapshots/web/lifecycle-chrome/session.jsonl')
const lifecycleOverride = join(process.cwd(), 'snapshots/web/lifecycle-chrome/replay.override.json')
const prompt = 'Reply with the single word LIGHTHOUSE and stop.'

async function capture(page: Page, tripwire: ReturnType<typeof watchConsole>): Promise<void> {
  const name = 'streaming-answer'
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
    viewport: captureViewport,
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

describe('reference capture: rc.1 CUT1.8 streaming answer', () => {
  let browser: Awaited<ReturnType<typeof chromium.launch>>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    browser = await chromium.launch({ headless: true })
  })

  afterAll(async () => {
    await browser?.close()
  })

  it('captures the running think tail at the locked narrow lifecycle viewport', async () => {
    const scaffold = await launchWebScaffold({
      replayFixture: lifecycleFixture,
      replayOverride: lifecycleOverride,
      paceMs: 100,
    })
    const context = await browser.newContext({
      viewport: { width: 1280, height: 840 },
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
      const input = page.locator('[data-composer-input]').first()
      await input.waitFor({ timeout: 10_000 })
      await input.fill(prompt)
      const settled = scaffold.whenTurnSettled()
      await page.setViewportSize(captureViewport)
      await input.press('Enter')
      const liveTail = page.locator('[data-variant="think"][data-state="running"] [data-follow-end]')
      await expect.poll(async () => {
        if (await liveTail.count() !== 1) return false
        return await liveTail.evaluate(element => {
          const text = element.firstElementChild
          if (!(text instanceof HTMLElement)) return false
          const viewport = element.getBoundingClientRect()
          const content = text.getBoundingClientRect()
          return content.width > viewport.width && Math.abs(content.right - viewport.right) <= 1
        })
      }, { timeout: 10_000, interval: 10 }).toBe(true)
      await capture(page, tripwire)
      await settled
      await page.getByText('LIGHTHOUSE', { exact: true }).waitFor({ timeout: 30_000 })
    } finally {
      await context.close()
      await scaffold.close()
    }
  }, 120_000)
})
