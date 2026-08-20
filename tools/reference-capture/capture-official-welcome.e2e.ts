import { mkdir, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { chromium, type Locator, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { launchWebScaffold, watchConsole, type WebScaffold } from './scaffold.ts'
import { connectFreshWorkspace, REPO_ROOT } from './support.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1280, height: 840 }
const railViewport = { width: 1023, height: 840 }
const lifecycleFixture = join(REPO_ROOT, 'apps/web/tests/snapshots/lifecycle-chrome/session.jsonl')
const recordedPrompt = 'Reply with the single word LIGHTHOUSE and stop.'
const captureColorSchemes = ['light', 'dark'] as const
type CaptureColorScheme = typeof captureColorSchemes[number]

let scaffold: WebScaffold
let browser: Awaited<ReturnType<typeof chromium.launch>>

type CapturePage = Page

async function applyOfficialColorScheme(page: CapturePage, colorScheme: CaptureColorScheme): Promise<void> {
  // RC8 ThemeRuntime uses this body attribute as the authoritative dark-theme
  // cascade. The browser media preference is still supplied on page creation,
  // but the attribute ensures the official user-visible palette itself is
  // captured instead of relying on an implementation-default preference.
  await page.evaluate(async (scheme) => {
    document.body.toggleAttribute('data-ds-dark-theme', scheme === 'dark')
    await new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))
  }, colorScheme)
}

async function writeCaptureMetadata(
  page: CapturePage,
  name: string,
  colorScheme: CaptureColorScheme,
  captureViewport: { width: number, height: number },
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
    viewport: captureViewport,
    locale: 'en-US',
    colorScheme,
    geometry,
    ariaSnapshot,
    consoleWarnings,
    pageErrors,
  }, null, 2) + '\n')
}

/** Start a true registry-backed job without consuming model output. */
async function revealAndClickRowAction(row: Locator, actionName: string): Promise<void> {
  const action = row.getByRole('button', { name: actionName })
  for (let attempt = 0; attempt < 4; attempt += 1) {
    await row.hover()
    if (await action.isVisible()) {
      await action.click()
      return
    }
    await row.page().waitForTimeout(100)
  }
  throw new Error(`row action did not become visible: ${actionName}`)
}

async function openWorkspaceManagementDialog(page: CapturePage, kind: 'workspace-rename' | 'session-rename' | 'workspace-delete'): Promise<string> {
  if (kind === 'session-rename') {
    const action = page.locator('button[aria-label^="Session actions for "]').first()
    const actionName = await action.getAttribute('aria-label')
    if (actionName === null) throw new Error('session fixture has no row action')
    const row = action.locator('xpath=ancestor::*[@role="treeitem"][1]')
    await revealAndClickRowAction(row, actionName)
    await page.getByRole('menuitem', { name: 'Rename', exact: true }).click()
    return 'Rename session'
  }

  const actionName = 'Workspace actions for workspace'
  const action = page.locator(`button[aria-label="${actionName}"]`).first()
  const row = action.locator('xpath=ancestor::*[@role="treeitem"][1]')
  await revealAndClickRowAction(row, actionName)
  if (kind === 'workspace-rename') {
    await page.getByRole('menuitem', { name: 'Rename', exact: true }).click()
    return 'Rename workspace'
  }
  await page.getByRole('menuitem', { name: 'Delete workspace', exact: true }).click()
  return 'Delete workspace'
}

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
    // Welcome is a no-model-call state, so it must not mount a replay fixture
    // with an unconsumed scripted turn. Each Jobs theme creates its own isolated
    // replay scaffold below because the Host registry is stateful.
    scaffold = await launchWebScaffold()
    browser = await chromium.launch({ headless: true })
  }, 120_000)

  afterAll(async () => {
    await browser?.close()
    await scaffold?.close()
  })

  it('captures official 1280x840 welcome fixtures in light and dark mode without browser errors', async () => {
    for (const colorScheme of captureColorSchemes) {
      const name = `welcome-no-workspace-${colorScheme}`
      const context = await browser.newContext({ viewport, locale: 'en-US', colorScheme, deviceScaleFactor: 1 })
      const page = await context.newPage()
      const consoleTripwire = watchConsole(page)
      await page.goto(scaffold.baseUrl, { waitUntil: 'load' })
      await page.locator('#root').waitFor({ state: 'attached', timeout: 30_000 })
      await applyOfficialColorScheme(page, colorScheme)
      await page.getByRole('textbox', { name: 'Choose workspace' }).waitFor({ timeout: 30_000 })
      await page.screenshot({ path: join(outputDirectory, `${name}.png`) })
      await writeCaptureMetadata(page, name, colorScheme, viewport, consoleTripwire.warnings, consoleTripwire.pageErrors)
      expect(consoleTripwire.warnings).toEqual([])
      expect(consoleTripwire.pageErrors).toEqual([])
      await context.close()
    }
  }, 120_000)

  it('captures official 1023px compact-rail fixtures in light and dark mode without browser errors', async () => {
    for (const colorScheme of captureColorSchemes) {
      const name = `sidebar-rail-narrow-${colorScheme}`
      const context = await browser.newContext({ viewport: railViewport, locale: 'en-US', colorScheme, deviceScaleFactor: 1 })
      const page = await context.newPage()
      const consoleTripwire = watchConsole(page)
      await page.goto(scaffold.baseUrl, { waitUntil: 'load' })
      await page.locator('#root').waitFor({ state: 'attached', timeout: 30_000 })
      await applyOfficialColorScheme(page, colorScheme)
      await page.getByRole('textbox', { name: 'Choose workspace' }).waitFor({ timeout: 30_000 })
      await page.screenshot({ path: join(outputDirectory, `${name}.png`) })
      await writeCaptureMetadata(page, name, colorScheme, railViewport, consoleTripwire.warnings, consoleTripwire.pageErrors)
      expect(consoleTripwire.warnings).toEqual([])
      expect(consoleTripwire.pageErrors).toEqual([])
      await context.close()
    }
  }, 120_000)

  it('captures official workspace management dialogs in light and dark mode through real row actions', async () => {
    const kinds = ['workspace-rename', 'session-rename', 'workspace-delete'] as const
    for (const kind of kinds) {
      for (const colorScheme of captureColorSchemes) {
        const name = `${kind}-${colorScheme}`
        const managementScaffold = await launchWebScaffold()
        const context = await browser.newContext({ viewport: { width: 1280, height: 1100 }, locale: 'en-US', colorScheme, deviceScaleFactor: 1 })
        const page = await context.newPage()
        const consoleTripwire = watchConsole(page)
        try {
          await page.goto(managementScaffold.baseUrl, { waitUntil: 'load' })
          await page.locator('#root').waitFor({ state: 'attached', timeout: 30_000 })
          await applyOfficialColorScheme(page, colorScheme)
          await connectFreshWorkspace(page, managementScaffold.workspaceCwd)
          const dialogName = await openWorkspaceManagementDialog(page, kind)
          await page.getByRole('dialog', { name: dialogName }).waitFor({ timeout: 30_000 })
          await page.screenshot({ path: join(outputDirectory, `${name}.png`) })
          await writeCaptureMetadata(page, name, colorScheme, { width: 1280, height: 1100 }, consoleTripwire.warnings, consoleTripwire.pageErrors)
          expect(consoleTripwire.warnings).toEqual([])
          expect(consoleTripwire.pageErrors).toEqual([])
        } finally {
          await context.close()
          await managementScaffold.close()
        }
      }
    }
  }, 240_000)

  it('captures official expanded Jobs actions in light and dark mode from Host-owned whole snapshots', async () => {
    for (const colorScheme of captureColorSchemes) {
      const name = `jobs-expanded-${colorScheme}`
      // Browser contexts isolate local storage, but a scaffold also owns the
      // real Host workspace/session registry. Give each themed Jobs fixture a
      // new scaffold/DSH_HOME so a captured light session cannot be
      // auto-selected by the subsequent dark page.
      const jobsScaffold = await launchWebScaffold({ replayFixture: lifecycleFixture, paceMs: 100 })
      const context = await browser.newContext({ viewport, locale: 'en-US', colorScheme, deviceScaleFactor: 1 })
      const page = await context.newPage()
      const consoleTripwire = watchConsole(page)
      let live: ReturnType<typeof registryJob> | undefined
      try {
        await page.goto(jobsScaffold.baseUrl, { waitUntil: 'load' })
        await page.locator('#root').waitFor({ state: 'attached', timeout: 30_000 })
        await applyOfficialColorScheme(page, colorScheme)
        await connectFreshWorkspace(page, jobsScaffold.workspaceCwd)

        const input = page.locator('textarea:enabled[placeholder="Describe what you want to build"]')
        const settled = jobsScaffold.whenTurnSettled()
        await input.fill(recordedPrompt)
        await input.press('Enter')
        const sessionID = await settled
        await page.getByText('LIGHTHOUSE', { exact: true }).waitFor({ timeout: 30_000 })

        const agent = jobsScaffold.ctx.agents.get(sessionID)
        if (agent === undefined) throw new Error('Jobs reference capture requires the current Host agent')
        if (jobsScaffold.ctx.jobs === undefined) throw new Error('Jobs reference capture requires the bundled Host registry')
        live = registryJob('sleep 60')
        const completed = registryJob('pnpm run build')
        jobsScaffold.ctx.jobs.start({ ...live.spec, owner: agent })
        jobsScaffold.ctx.jobs.start({ ...completed.spec, owner: agent })
        completed.settle()

        const action = page.getByRole('button', { name: '1 background job running' })
        await action.waitFor({ timeout: 30_000 })
        await action.click()
        const list = page.getByRole('list', { name: 'Background jobs' })
        await list.waitFor({ timeout: 30_000 })
        await page.getByText('completed', { exact: true }).waitFor({ timeout: 30_000 })
        await page.screenshot({ path: join(outputDirectory, `${name}.png`) })
        await writeCaptureMetadata(page, name, colorScheme, viewport, consoleTripwire.warnings, consoleTripwire.pageErrors)
        expect(consoleTripwire.warnings).toEqual([])
        expect(consoleTripwire.pageErrors).toEqual([])
      } finally {
        // The capture intentionally observes this job as live. Settle only after
        // the PNG/ARIA evidence is written so scaffold.close() never awaits an
        // artificial indefinitely-running task.
        live?.settle()
        await context.close()
        await jobsScaffold.close()
      }
    }
  }, 120_000)
})
