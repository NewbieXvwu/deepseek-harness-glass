import { execFileSync } from 'node:child_process'
import { mkdir, stat, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { chromium, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { launchWebScaffold, seedBlankSession, watchConsole } from './scaffold.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1280, height: 840 }
const officialSourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: process.cwd(), encoding: 'utf8' }).trim()
const sessionId = 'cold-blank-session-web-e2e'
const workspaceName = 'cold-blank-workspace'

async function capture(page: Page, tripwire: ReturnType<typeof watchConsole>): Promise<void> {
  const name = 'empty-session-workspace'
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

describe('reference capture: rc.1 CUT1.8 cold blank Session', () => {
  let browser: Awaited<ReturnType<typeof chromium.launch>>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    browser = await chromium.launch({ headless: true })
  })

  afterAll(async () => {
    await browser?.close()
  })

  it('captures the sidebar while a verified cold blank Session remains filtered out', async () => {
    const scaffold = await launchWebScaffold({})
    const cwd = join(scaffold.workspaceCwd, workspaceName)
    await mkdir(cwd, { recursive: true })
    await seedBlankSession(scaffold, sessionId, cwd)
    const header = (await scaffold.ctx.sessionPersistence.list()).find(candidate => candidate.id === sessionId)
    if (header === undefined) throw new Error('blank Session fixture did not materialize')
    const location = scaffold.ctx.sessionPersistence.locate(header)
    if (location === undefined) throw new Error('JSONL fixture has no physical artifact')
    expect((await stat(location.path)).size).toBeLessThanOrEqual(1024)

    const context = await browser.newContext({ viewport, locale: 'en-US', colorScheme: 'light', deviceScaleFactor: 1 })
    const page = await context.newPage()
    const tripwire = watchConsole(page)
    try {
      await page.goto(scaffold.authenticatedUrl, { waitUntil: 'load' })
      await page.waitForSelector('[class*="frame"]', { timeout: 30_000 })
      const tree = page.getByRole('tree', { name: 'Sessions' })
      await tree.waitFor({ timeout: 30_000 })
      expect(await tree.getByText(workspaceName, { exact: true }).count()).toBe(0)
      await capture(page, tripwire)
    } finally {
      await context.close()
      await scaffold.close()
    }
  }, 120_000)
})
