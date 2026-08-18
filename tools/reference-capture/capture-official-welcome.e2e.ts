import { mkdir, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { chromium } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { launchWebScaffold, watchConsole, type WebScaffold } from './scaffold.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1280, height: 840 }

let scaffold: WebScaffold
let browser: Awaited<ReturnType<typeof chromium.launch>>

describe('reference capture: official welcome without workspace', () => {
  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    scaffold = await launchWebScaffold()
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
    await writeFile(join(outputDirectory, 'welcome-no-workspace-light.json'), JSON.stringify({
      officialSourceCommit: '99f6f02fecdb7dff40c3fbc9470f5907c29f74ca',
      viewport,
      locale: 'en-US',
      colorScheme: 'light',
      geometry,
      ariaSnapshot,
      consoleWarnings: consoleTripwire.warnings,
      pageErrors: consoleTripwire.pageErrors,
    }, null, 2) + '\n')
    expect(consoleTripwire.warnings).toEqual([])
    expect(consoleTripwire.pageErrors).toEqual([])
    await page.close()
  }, 120_000)
})
