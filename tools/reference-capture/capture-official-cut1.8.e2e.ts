import { execFileSync } from 'node:child_process'
import { mkdir, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { chromium, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import {
  acknowledgeReloadConnectionLoss,
  launchWebScaffold,
  watchConsole,
  type WebScaffold,
} from './scaffold.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1680, height: 1000 }
const officialSourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: process.cwd(), encoding: 'utf8' }).trim()

async function writeCaptureMetadata(page: Page, name: string, tripwire: ReturnType<typeof watchConsole>): Promise<void> {
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
  await writeFile(join(outputDirectory, `${name}.json`), JSON.stringify({
    officialSourceCommit,
    viewport,
    locale: 'zh-CN',
    colorScheme: 'light',
    geometry,
    ariaSnapshot,
    consoleWarnings: tripwire.warnings,
    pageErrors: tripwire.pageErrors,
  }, null, 2) + '\n')
}

async function capture(page: Page, name: string, tripwire: ReturnType<typeof watchConsole>): Promise<void> {
  await page.screenshot({ path: join(outputDirectory, `${name}.png`) })
  await writeCaptureMetadata(page, name, tripwire)
  expect(tripwire.warnings).toEqual([])
  expect(tripwire.pageErrors).toEqual([])
}

describe('reference capture: rc.1 CUT1.8 settings surfaces', () => {
  let browser: Awaited<ReturnType<typeof chromium.launch>>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    browser = await chromium.launch({ headless: true })
  })

  afterAll(async () => {
    await browser?.close()
  })

  async function freshPage(): Promise<{
    scaffold: WebScaffold
    page: Page
    close: () => Promise<void>
    tripwire: ReturnType<typeof watchConsole>
  }> {
    const scaffold = await launchWebScaffold({})
    const context = await browser.newContext({ viewport, locale: 'zh-CN', colorScheme: 'light', deviceScaleFactor: 1 })
    const page = await context.newPage()
    const tripwire = watchConsole(page)
    await page.goto(scaffold.authenticatedUrl, { waitUntil: 'load' })
    await page.waitForSelector('[class*="frame"]', { timeout: 30_000 })
    return { scaffold, page, tripwire, close: async () => { await context.close(); await scaffold.close() } }
  }

  it('captures the rc.1 General settings surface', async () => {
    const fixture = await freshPage()
    try {
      await fixture.page.getByRole('button', { name: '设置', exact: true }).click()
      const dialog = fixture.page.getByRole('dialog', { name: '设置' })
      await dialog.waitFor({ timeout: 10_000 })
      await dialog.getByRole('button', { name: '通用设置' }).waitFor({ timeout: 10_000 })
      await dialog.getByRole('button', { name: '工作区内修改' }).waitFor({ timeout: 10_000 })
      await dialog.getByText('语言', { exact: true }).waitFor({ timeout: 10_000 })
      await dialog.getByText('外观', { exact: true }).waitFor({ timeout: 10_000 })
      await capture(fixture.page, 'settings-general-zh', fixture.tripwire)
    } finally {
      await fixture.close()
    }
  }, 60_000)

  it('captures the rc.1 Models provider editor', async () => {
    const fixture = await freshPage()
    try {
      await fixture.page.getByRole('button', { name: '设置', exact: true }).click()
      const dialog = fixture.page.getByRole('dialog', { name: '设置' })
      await dialog.waitFor({ timeout: 10_000 })
      await dialog.getByRole('button', { name: '模型' }).click()
      const add = dialog.getByRole('button', { name: '添加提供方' })
      await add.waitFor({ timeout: 10_000 })
      await expect.poll(() => add.isEnabled(), { timeout: 10_000 }).toBe(true)
      await add.click()
      const provider = dialog.getByLabel('提供方')
      await provider.waitFor({ timeout: 10_000 })
      await provider.selectOption('minimax-cn')
      await dialog.getByRole('textbox', { name: 'API 密钥', exact: true }).waitFor({ timeout: 10_000 })
      await capture(fixture.page, 'models-settings-provider-zh', fixture.tripwire)
    } finally {
      await fixture.close()
    }
  }, 60_000)

  it('captures the rc.1 Plugins configuration cards', async () => {
    const fixture = await freshPage()
    try {
      await fixture.page.getByRole('button', { name: '设置', exact: true }).click()
      const dialog = fixture.page.getByRole('dialog', { name: '设置' })
      await dialog.waitFor({ timeout: 10_000 })
      await dialog.getByRole('button', { name: '插件', exact: true }).click()
      await expect.poll(
        () => dialog.getByRole('tab', { name: '插件配置', exact: true }).getAttribute('aria-selected'),
        { timeout: 5_000 },
      ).toBe('true')
      await dialog.getByText('Subagent', { exact: true }).waitFor({ timeout: 10_000 })
      await dialog.getByText('终端', { exact: true }).waitFor({ timeout: 10_000 })
      await dialog.getByText('Agent 循环', { exact: true }).waitFor({ timeout: 10_000 })
      await dialog.getByText('网页搜索', { exact: true }).waitFor({ timeout: 10_000 })
      await capture(fixture.page, 'plugins-settings-zh', fixture.tripwire)
    } finally {
      await fixture.close()
    }
  }, 60_000)

  it('captures the persisted rc.1 16px content font state', async () => {
    const fixture = await freshPage()
    try {
      const readFontSize = async (): Promise<string> => fixture.page.evaluate(
        () => document.body.style.getPropertyValue('--dsh-content-font-size'),
      )
      expect(await readFontSize()).toBe('14px')
      await fixture.page.getByRole('button', { name: '设置', exact: true }).click()
      const dialog = fixture.page.getByRole('dialog', { name: '设置' })
      await dialog.waitFor({ timeout: 10_000 })
      await dialog.getByText('14', { exact: true }).hover()
      const increase = dialog.getByRole('button', { name: '增大字号' })
      await increase.click()
      await dialog.getByText('15', { exact: true }).waitFor({ timeout: 5_000 })
      await increase.click()
      await dialog.getByText('16', { exact: true }).waitFor({ timeout: 5_000 })
      await expect.poll(readFontSize, { timeout: 5_000 }).toBe('16px')
      await fixture.page.keyboard.press('Escape')

      const warningStart = fixture.tripwire.warnings.length
      await fixture.page.reload({ waitUntil: 'load' })
      acknowledgeReloadConnectionLoss(fixture.tripwire, warningStart)
      await fixture.page.waitForSelector('[class*="frame"]', { timeout: 30_000 })
      await expect.poll(readFontSize, { timeout: 5_000 }).toBe('16px')
      await fixture.page.getByRole('button', { name: '设置', exact: true }).click()
      const restored = fixture.page.getByRole('dialog', { name: '设置' })
      await restored.waitFor({ timeout: 10_000 })
      await restored.getByText('16', { exact: true }).hover()
      await capture(fixture.page, 'settings-font-size-zh', fixture.tripwire)

      const decrease = restored.getByRole('button', { name: '减小字号' })
      await decrease.click()
      await restored.getByText('15', { exact: true }).waitFor({ timeout: 5_000 })
      await decrease.click()
      await restored.getByText('14', { exact: true }).waitFor({ timeout: 5_000 })
    } finally {
      await fixture.close()
    }
  }, 90_000)
})
