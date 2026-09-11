import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { fileURLToPath } from 'node:url'
import { join, resolve } from 'node:path'
import { chromium, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { deriveReplayScript, parseSessionLog, type ReplayEntry } from '@deepseek-ai/dsh-llm-replay'
import {
  launchWebScaffold,
  watchConsole,
  type WebScaffold,
} from './scaffold.ts'
import { connectFreshWorkspace } from './support.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1280, height: 840 }
const replayFixture = fileURLToPath(new URL('../../../snapshots/web/live-interactions/session.jsonl', import.meta.url))
const pngFixture = fileURLToPath(new URL('../../../snapshots/session/read-image/workspace/red.png', import.meta.url))
const officialSourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: process.cwd(), encoding: 'utf8' }).trim()

async function pasteImage(page: Page, bytes: Uint8Array): Promise<void> {
  await page.locator('[data-composer-input]').first().evaluate((surface, data) => {
    const transfer = new DataTransfer()
    transfer.items.add(new File([new Uint8Array(data)], 'queued.png', { type: 'image/png' }))
    surface.dispatchEvent(new ClipboardEvent('paste', { clipboardData: transfer, bubbles: true, cancelable: true }))
  }, [...bytes])
}

async function capture(page: Page, tripwire: ReturnType<typeof watchConsole>): Promise<void> {
  const name = 'queued-image-light'
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

describe('reference capture: rc.1 queued image', () => {
  let browser: Awaited<ReturnType<typeof chromium.launch>>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    browser = await chromium.launch({ headless: true })
  })

  afterAll(async () => {
    await browser?.close()
  })

  it('captures the durable queued thumbnail and verifies FIFO delivery', async () => {
    const overrideDir = await mkdtemp(join(tmpdir(), 'dsh-cut18-queued-image-'))
    let scaffold: WebScaffold | undefined
    const context = await browser.newContext({ viewport, locale: 'en-US', colorScheme: 'light', deviceScaleFactor: 1 })
    try {
      const readyFile = join(overrideDir, '.hang-ready')
      const overridePath = join(overrideDir, 'replay.override.json')
      const recorded = deriveReplayScript(parseSessionLog(await readFile(replayFixture, 'utf8')))
      expect(recorded).toHaveLength(1)
      const replay: ReplayEntry[] = [{ kind: 'hang', readyFile }, recorded[0]!, recorded[0]!]
      await writeFile(overridePath, JSON.stringify(replay))

      scaffold = await launchWebScaffold({
        replayFixture,
        replayOverride: overridePath,
        compareReplaySession: false,
      })
      const page = await context.newPage()
      const tripwire = watchConsole(page)
      await page.goto(scaffold.authenticatedUrl, { waitUntil: 'load' })
      await page.waitForSelector('[class*="frame"]', { timeout: 30_000 })
      await connectFreshWorkspace(page, scaffold.workspaceCwd)

      const input = page.locator('[data-composer-input]').first()
      const firstSettled = scaffold.whenTurnSettled()
      await input.fill('Reply with a one-sentence description of event sourcing, then stop.')
      await input.press('Enter')
      await expect.poll(() => existsSync(readyFile), { timeout: 15_000 }).toBe(true)
      await page.locator('[data-composer-input][contenteditable="true"]').first().waitFor({ timeout: 10_000 })
      await pasteImage(page, await readFile(pngFixture))
      await page.getByRole('img', { name: 'queued.png' }).waitFor({ timeout: 10_000 })
      await input.fill('Compare with this screenshot')
      await input.press('Enter')

      const dockThumb = page.locator('[data-queue-dock] img[alt="Queued message image"]')
      await dockThumb.waitFor({ timeout: 15_000 })
      await expect.poll(() => dockThumb.getAttribute('src')).toMatch(/^blob:/)
      await page.getByText('Compare with this screenshot', { exact: true }).waitFor()
      await page.getByRole('button', { name: 'Remove queued message' }).waitFor({ timeout: 15_000 })
      await capture(page, tripwire)

      await page.getByRole('button', { name: 'Stop generating' }).click()
      await firstSettled
      await dockThumb.waitFor({ timeout: 10_000 })
      const settled = scaffold.whenTurnSettled()
      await input.fill('Continue with the queued comparison')
      await input.press('Enter')
      await settled
      await expect.poll(() => page.locator('[data-queue-dock]').count(), { timeout: 15_000 }).toBe(0)
      await page.locator('[class*="userRow"] img').first().waitFor({ timeout: 15_000 })
      expect(tripwire.pageErrors).toEqual([])
      expect(tripwire.warnings).toEqual([])
    } finally {
      await context.close()
      await scaffold?.close()
      await rm(overrideDir, { recursive: true, force: true })
    }
  }, 120_000)
})
