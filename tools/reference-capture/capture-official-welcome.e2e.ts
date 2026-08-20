import { mkdir, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { chromium } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { launchWebScaffold, watchConsole, type WebScaffold } from './scaffold.ts'
import { connectFreshWorkspace, REPO_ROOT } from './support.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1280, height: 840 }
const lifecycleFixture = join(REPO_ROOT, 'apps/web/tests/snapshots/lifecycle-chrome/session.jsonl')
const recordedPrompt = 'Reply with the single word LIGHTHOUSE and stop.'

let scaffold: WebScaffold
let browser: Awaited<ReturnType<typeof chromium.launch>>

async function writeCaptureMetadata(
  page: Awaited<ReturnType<typeof browser.newPage>>,
  name: string,
  consoleWarnings: readonly string[],
  pageErrors: readonly string[],
): Promise<void> {
  const geometry = await page.locator('#root').evaluate(root => {
    const rect = root.getBoundingClientRect()
    return {
      root: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
      text: (root.textContent ?? '').replace(/\s+/g, ' ').trim(),
      viewport: { width: window.innerWidth, height: window.innerHeight, devicePixelRatio: window.devicePixelRatio },
      title: document.title,
    }
  })
  const ariaSnapshot = await page.locator('body').ariaSnapshot()
  await writeFile(join(outputDirectory, `${name}.json`), JSON.stringify({
    officialSourceCommit: '141eb6fef83422698aef7a981029e843e8161534',
    viewport,
    locale: 'en-US',
    colorScheme: 'light',
    geometry,
    ariaSnapshot,
    consoleWarnings,
    pageErrors,
  }, null, 2) + '\n')
}

/** Start a true registry-backed job without consuming model output. */
function registryJob(label: string) {
  let settle!: () => void
  return {
    spec: {
      kind: 'bash' as const,
      label,
      run: () => ({
        cancel: () => {},
        done: new Promise<{ status: 'completed' }>((resolve) => {
          settle = () => { resolve({ status: 'completed' }) }
        }),
        readOutput: () => '',
      }),
    },
    settle: () => { settle() },
  }
}

describe('reference capture: official welcome and session Jobs action', () => {
  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    // The welcome capture remains a no-model-call state. The same scaffold has
    // the locked lifecycle replay ready for the subsequent Jobs session.
    scaffold = await launchWebScaffold({ replayFixture: lifecycleFixture, paceMs: 100 })
    browser = await chromium.launch({ headless: true })
  }, 120_000)

  afterAll(async () => {
    await browser?.close()
    await scaffold?.close()
  })

  it('captures the official 1280x840 light fixture without browser errors', async () => {
    const page = await browser.newPage({ viewport, locale: 'en-US', colorScheme: 'light', deviceScaleFactor: 1 })
    const consoleTripwire = watchConsole(page)
    await page.goto(scaffold.baseUrl, { waitUntil: 'load' })
    await page.locator('#root').waitFor({ state: 'attached', timeout: 30_000 })
    await page.getByRole('textbox', { name: 'Choose workspace' }).waitFor({ timeout: 30_000 })
    await page.screenshot({ path: join(outputDirectory, 'welcome-no-workspace-light.png') })
    await writeCaptureMetadata(page, 'welcome-no-workspace-light', consoleTripwire.warnings, consoleTripwire.pageErrors)
    expect(consoleTripwire.warnings).toEqual([])
    expect(consoleTripwire.pageErrors).toEqual([])
    await page.close()
  }, 120_000)

  it('captures the official expanded Jobs action from a Host-owned whole snapshot', async () => {
    const page = await browser.newPage({ viewport, locale: 'en-US', colorScheme: 'light', deviceScaleFactor: 1 })
    const consoleTripwire = watchConsole(page)
    await page.goto(scaffold.baseUrl, { waitUntil: 'load' })
    await page.locator('#root').waitFor({ state: 'attached', timeout: 30_000 })
    await connectFreshWorkspace(page, scaffold.workspaceCwd)

    const input = page.locator('textarea:enabled[placeholder="Describe what you want to build"]')
    const settled = scaffold.whenTurnSettled()
    await input.fill(recordedPrompt)
    await input.press('Enter')
    const sessionID = await settled
    await page.getByText('LIGHTHOUSE', { exact: true }).waitFor({ timeout: 30_000 })

    const agent = scaffold.ctx.agents.get(sessionID)
    if (agent === undefined) throw new Error('Jobs reference capture requires the current Host agent')
    if (scaffold.ctx.jobs === undefined) throw new Error('Jobs reference capture requires the bundled Host registry')
    const live = registryJob('sleep 60')
    const completed = registryJob('pnpm run build')
    scaffold.ctx.jobs.start({ ...live.spec, owner: agent })
    scaffold.ctx.jobs.start({ ...completed.spec, owner: agent })
    completed.settle()

    try {
      const action = page.getByRole('button', { name: '1 background job running' })
      await action.waitFor({ timeout: 30_000 })
      await action.click()
      const list = page.getByRole('list', { name: 'Background jobs' })
      await list.waitFor({ timeout: 30_000 })
      await page.getByText('completed', { exact: true }).waitFor({ timeout: 30_000 })
      await page.screenshot({ path: join(outputDirectory, 'jobs-expanded-light.png') })
      await writeCaptureMetadata(page, 'jobs-expanded-light', consoleTripwire.warnings, consoleTripwire.pageErrors)
      expect(consoleTripwire.warnings).toEqual([])
      expect(consoleTripwire.pageErrors).toEqual([])
    } finally {
      // The capture intentionally observes this job as live. Settle only after
      // the PNG/ARIA evidence is written so scaffold.close() never awaits an
      // artificial indefinitely-running task.
      live.settle()
      await page.close()
    }
  }, 120_000)
})
