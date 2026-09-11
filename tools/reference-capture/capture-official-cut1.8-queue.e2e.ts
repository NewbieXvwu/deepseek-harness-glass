import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { deriveReplayScript, parseSessionLog, type ReplayEntry } from '@deepseek-ai/dsh-llm-replay'
import { chromium, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { launchWebScaffold, watchConsole } from './scaffold.ts'
import { connectFreshWorkspace } from './support.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const captureViewport = { width: 640, height: 1000 }
const officialSourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: process.cwd(), encoding: 'utf8' }).trim()
const fixture = join(process.cwd(), 'snapshots/web/live-interactions/session.jsonl')
const activePrompt = 'Reply with a one-sentence description of event sourcing, then stop.'
const removeText = 'Queue item to remove'
const editText = 'Queue item to edit'
const editedText = 'Edited queue item'
const tailText = 'Queue item preserved after stop'
const wakeText = 'Wake the preserved queue'

async function capture(page: Page, tripwire: ReturnType<typeof watchConsole>): Promise<void> {
  const name = 'queue-actions-narrow'
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

describe('reference capture: rc.1 CUT1.8 queue actions narrow', () => {
  let browser: Awaited<ReturnType<typeof chromium.launch>>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    browser = await chromium.launch({ headless: true })
  })

  afterAll(async () => {
    await browser?.close()
  })

  it('captures the expanded editing queue inside the narrow composer card', async () => {
    const overrideDir = await mkdtemp(join(tmpdir(), 'dsh-cut18-queue-'))
    const readyFile = join(overrideDir, '.hang-ready')
    const overridePath = join(overrideDir, 'replay.override.json')
    const recorded = deriveReplayScript(parseSessionLog(await readFile(fixture, 'utf8')))
    expect(recorded).toHaveLength(1)
    const replay: ReplayEntry[] = [
      { kind: 'hang', readyFile },
      recorded[0]!,
      recorded[0]!,
      recorded[0]!,
    ]
    await writeFile(overridePath, JSON.stringify(replay))

    const scaffold = await launchWebScaffold({
      replayFixture: fixture,
      replayOverride: overridePath,
      compareReplaySession: false,
    })
    const context = await browser.newContext({
      viewport: { width: 1680, height: 1000 },
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
      const firstSettled = scaffold.whenTurnSettled()
      await input.fill(activePrompt)
      await input.press('Enter')
      await expect.poll(() => existsSync(readyFile), { timeout: 15_000 }).toBe(true)

      for (const text of [removeText, editText]) {
        await page.locator('[data-composer-input][contenteditable="true"]').first().waitFor({ timeout: 10_000 })
        await input.fill(text)
        await input.press('Enter')
      }
      const queueHeader = page.getByRole('button', { name: '2 queued messages' })
      await expect.poll(() => queueHeader.getAttribute('aria-expanded'), { timeout: 10_000 }).toBe('false')
      await queueHeader.click()
      await expect.poll(() => page.getByRole('button', { name: 'Remove queued message' }).count(), { timeout: 10_000 }).toBe(2)

      const editRow = page.locator('[data-queue-dock] li', { hasText: editText })
      await editRow.getByRole('button', { name: 'Edit queued message' }).click()
      const editor = page.getByRole('textbox', { name: 'Edit queued message' })
      await editor.fill(editedText)
      await page.setViewportSize(captureViewport)

      const queueBox = await page.locator('[data-queue-dock]').boundingBox()
      const composerBox = await page.locator('[data-composer-card]').boundingBox()
      expect(queueBox).not.toBeNull()
      expect(composerBox).not.toBeNull()
      expect(queueBox!.x).toBeGreaterThanOrEqual(composerBox!.x)
      expect(queueBox!.x + queueBox!.width).toBeLessThanOrEqual(composerBox!.x + composerBox!.width)
      await page.getByRole('button', { name: 'Save queued message' }).waitFor({ timeout: 10_000 })
      await page.getByRole('button', { name: 'Stop generating' }).waitFor({ timeout: 10_000 })
      await capture(page, tripwire)

      await page.getByRole('button', { name: 'Save queued message' }).click()
      await page.getByText(editedText, { exact: true }).waitFor()
      const removeRow = page.locator('[data-queue-dock] li', { hasText: removeText })
      await removeRow.getByRole('button', { name: 'Remove queued message' }).click()
      await expect.poll(() => page.getByText(removeText, { exact: true }).count()).toBe(0)

      await input.fill(tailText)
      await input.press('Enter')
      await expect.poll(
        () => page.getByRole('button', { name: 'Remove queued message' }).count(),
        { timeout: 10_000 },
      ).toBe(2)

      await page.getByRole('button', { name: 'Stop generating' }).click()
      await firstSettled
      await expect.poll(() => page.getByRole('button', { name: 'Stop generating' }).count()).toBe(0)
      await expect.poll(() => page.getByRole('button', { name: 'Remove queued message' }).count()).toBe(2)

      const settled = scaffold.whenTurnSettled()
      await input.fill(wakeText)
      await input.press('Enter')
      await settled
      await expect.poll(() => page.locator('[data-queue-dock]').count()).toBe(0)
    } finally {
      await context.close()
      await scaffold.close()
      await rm(overrideDir, { recursive: true, force: true })
    }
  }, 120_000)
})
