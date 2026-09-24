import { execFileSync } from 'node:child_process'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { chromium, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { launchWebScaffold, seedSession, watchConsole } from './scaffold.ts'
import { REPO_ROOT } from './support.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1280, height: 840 }
const officialSourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: REPO_ROOT, encoding: 'utf8' }).trim()
const navigationFixture = join(REPO_ROOT, 'snapshots/web/navigation-panes/session.jsonl')

async function capture(page: Page, tripwire: ReturnType<typeof watchConsole>): Promise<void> {
  const name = 'tool-call-details'
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

describe('reference capture: rc.1 CUT1.8 tool call details', () => {
  let browser: Awaited<ReturnType<typeof chromium.launch>>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    browser = await chromium.launch({ headless: true })
  })

  afterAll(async () => {
    await browser?.close()
  })

  it('captures the Event details inspector from the seeded navigation session', async () => {
    const scaffold = await launchWebScaffold()
    const context = await browser.newContext({ viewport, locale: 'en-US', colorScheme: 'light', deviceScaleFactor: 1 })
    const page = await context.newPage()
    const tripwire = watchConsole(page)
    try {
      const sessionCwd = join(scaffold.workspaceCwd, 'workspace')
      await mkdir(sessionCwd, { recursive: true })
      await writeFile(join(sessionCwd, 'nav-a.md'), '# alpha nav\n')
      await writeFile(join(sessionCwd, 'nav-b.md'), '# beta nav\n')
      await seedSession(scaffold, await readFile(navigationFixture, 'utf8'), 'navigation-panes-web-e2e')
      await page.goto(scaffold.authenticatedUrl, { waitUntil: 'load' })
      await page.locator('#root').waitFor({ state: 'attached', timeout: 30_000 })
      await page.getByText('Ungrouped', { exact: true }).waitFor({ timeout: 30_000 })
      const searchButton = page.getByRole('button', { name: 'Search sessions' })
      if (await searchButton.getAttribute('aria-expanded') !== 'true') await searchButton.click()
      const search = page.getByPlaceholder('Search sessions', { exact: false })
      await search.fill('WATERFALL')
      const result = page.getByRole('tree', { name: 'Search results' }).getByRole('treeitem')
      await result.waitFor({ timeout: 30_000 })
      await result.click()
      await page.getByText('FIRST_DONE', { exact: true }).waitFor({ timeout: 30_000 })
      await search.fill('')
      await expect.poll(() => search.inputValue(), { timeout: 5_000 }).toBe('')
      await page.getByRole('tab', { name: 'Trajectory' }).click()
      const toolRow = page.locator('tr[data-kind="tool"]').first()
      await toolRow.waitFor({ timeout: 30_000 })
      await toolRow.click()
      const details = page.getByRole('complementary', { name: 'Event details' })
      await details.waitFor({ timeout: 30_000 })
      await details.getByRole('tab', { name: 'Result' }).click()
      await details.getByText('NAVIGATION_OK', { exact: false }).waitFor({ timeout: 30_000 })
      await capture(page, tripwire)
    } finally {
      await context.close()
      await scaffold.close()
    }
  }, 120_000)
})
