import { execFileSync } from 'node:child_process'
import { mkdir, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { chromium, type Page } from 'playwright'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { createMessage, createUserMessage } from '@deepseek-ai/dsh-llm'
import { SESSION_FORMAT_VERSION, Session, SessionId } from '@deepseek-ai/dsh-session'
import type {} from '@deepseek-ai/dsh-session-title'
import { launchWebScaffold, seedSession, watchConsole, type WebScaffold } from './scaffold.ts'

const outputDirectory = resolve(process.env.DSH_REFERENCE_SCREENSHOT_DIR ?? '.artifacts/reference-webui')
const viewport = { width: 1100, height: 900 }
const sourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: process.cwd(), encoding: 'utf8' }).trim()
const fillMarker = 'MWT_FILL_C1'
const wideMarker = 'MWT_WIDE_C01'
const longMarker = 'MWT_LONGCELL_F1'
const tailMarker = 'MWT_TABLES_DONE'

function fixture(): string {
  const sentence = 'This cell carries one full sentence so the unwrapped table is far wider than the message column.'
  const longToken = 'workspace/deepseek-harness/packages/client/ui-primitives/src/markdown/render.tsx/'.repeat(3)
  const wideHeader = [wideMarker, ...Array.from({ length: 11 }, (_, i) => `C${String(i + 2).padStart(2, '0')}`)]
  const wideRow = (row: number) => Array.from({ length: 12 }, (_, i) => `v${String(row)}${String(i + 1).padStart(2, '0')}`)
  const markdown = [
    'Three markdown tables exercise the wide-table layout rules.',
    '',
    `| ${fillMarker} | Current approach | Proposed approach |`,
    '| --- | --- | --- |',
    `| Rendering | ${sentence} | ${sentence} |`,
    `| Memory | ${sentence} | ${sentence} |`,
    '',
    `| ${wideHeader.join(' | ')} |`,
    `|${' --- |'.repeat(12)}`,
    `| ${wideRow(1).join(' | ')} |`,
    `| ${wideRow(2).join(' | ')} |`,
    '',
    `| ${longMarker} | Value |`,
    '| --- | --- |',
    `| path | ${longToken} |`,
    '| 说明 | 这个单元格包含一段较长的中文说明，用来验证长内容在窄列宽下按最小可读宽度换行而不是把列压缩到无法阅读。 |',
    '',
    tailMarker,
  ].join('\n')

  const session = Session.create(SessionId('markdown-wide-table-source'))
  const origin = new Date().setHours(12, 0, 0, 0)
  session.append('turn/start', { turn: 1 })
  const user = session.append('user/message', createUserMessage({
    content: [{ type: 'text', text: 'Show the wide-table layout scenarios.' }],
    source: { kind: 'user' },
  }), { surfaceOp: 'append' })
  session.append('session/title', { title: 'Markdown wide tables', messageSeqs: [user.seq], source: { kind: 'fallback' } })
  session.append('step/start', { turn: 1, step: 1 })
  session.append('assistant/message', {
    turn: 1,
    step: 1,
    message: createMessage({
      role: 'assistant',
      content: [{ type: 'text', text: markdown }],
      source: { kind: 'model', provider: 'fixture', model: 'fixture' },
    }),
  }, { surfaceOp: 'append' })
  session.append('step/end', { turn: 1, step: 1 })
  session.append('turn/end', { turn: 1, reason: { kind: 'completed' } })
  return [
    JSON.stringify({ type: 'session', version: SESSION_FORMAT_VERSION, id: '{{sessionId}}', createdAt: 0, cwd: '{{cwd}}' }),
    ...session.snapshotEvents().map(event => JSON.stringify({ ...event, time: origin + event.seq * 1_000 })),
    '',
  ].join('\n')
}

async function closeDetails(page: Page): Promise<void> {
  await page.getByRole('button', { name: 'Close details', exact: true }).waitFor({ timeout: 10_000 })
  await page.evaluate(() => document.querySelector<HTMLElement>('button[aria-label="Close details"]')?.click())
  await page.waitForSelector('[data-details-collapsed]', { timeout: 5_000 })
}

async function tableRelations(page: Page): Promise<{ fill: number; wide: number; long: number }> {
  return page.evaluate(([fill, wide, long]) => {
    const overflow = (marker: string): number => {
      const wrapper = [...document.querySelectorAll<HTMLElement>('[class*="tableScroll"]')]
        .find(candidate => candidate.textContent?.includes(marker) ?? false)
      if (wrapper === undefined) throw new Error(`table wrapper ${marker} missing`)
      return wrapper.scrollWidth - wrapper.clientWidth
    }
    return { fill: overflow(fill), wide: overflow(wide), long: overflow(long) }
  }, [fillMarker, wideMarker, longMarker])
}

describe('reference capture: rc.1 Markdown wide-table scaling', () => {
  let scaffold: WebScaffold
  let browser: Awaited<ReturnType<typeof chromium.launch>>
  let page: Page
  let tripwire: ReturnType<typeof watchConsole>

  beforeAll(async () => {
    await mkdir(outputDirectory, { recursive: true })
    scaffold = await launchWebScaffold({})
    await seedSession(scaffold, fixture(), 'markdown-wide-table-web-e2e')
    browser = await chromium.launch({ headless: true })
    const context = await browser.newContext({ viewport, locale: 'en-US', colorScheme: 'light', deviceScaleFactor: 1 })
    page = await context.newPage()
    tripwire = watchConsole(page)
    await page.goto(scaffold.authenticatedUrl, { waitUntil: 'load' })
    await page.waitForSelector('[class*="frame"]', { timeout: 30_000 })
    const group = page.locator('[role="treeitem"]').first()
    await group.waitFor({ timeout: 15_000 })
    await group.click()
    const session = page.locator('[role="treeitem"]').nth(1)
    await session.waitFor({ timeout: 10_000 })
    await session.click()
    await page.getByText(tailMarker, { exact: true }).waitFor({ timeout: 15_000 })
    await page.getByRole('button', { name: 'Collapse sidebar', exact: true }).click()
    await closeDetails(page)
  }, 180_000)

  afterAll(async () => {
    await browser?.close()
    await scaffold?.close()
  })

  it('captures the 1100px table state and preserves scroll/wrap relations under keyboard and zoom', async () => {
    await expect.poll(async () => {
      const relation = await tableRelations(page)
      return relation.fill <= 1 && relation.long <= 1 && relation.wide > 1
    }, { timeout: 10_000 }).toBe(true)

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
    const name = 'markdown-wide-table-scaling'
    await page.screenshot({ path: join(outputDirectory, `${name}.png`) })
    await writeFile(join(outputDirectory, `${name}.json`), JSON.stringify({
      officialSourceCommit: sourceCommit,
      viewport,
      locale: 'en-US',
      colorScheme: 'light',
      geometry,
      ariaSnapshot,
      consoleWarnings: tripwire.warnings,
      pageErrors: tripwire.pageErrors,
    }, null, 2) + '\n')

    const wide = page.locator('[class*="tableScroll"]', { hasText: wideMarker })
    await wide.focus()
    await page.keyboard.press('ArrowRight')
    await page.keyboard.press('ArrowRight')
    await expect.poll(() => wide.evaluate(element => element.scrollLeft), { timeout: 5_000 }).toBeGreaterThan(0)
    await page.evaluate(() => { document.documentElement.style.zoom = '1.25' })
    try {
      await expect.poll(async () => {
        const relation = await tableRelations(page)
        return relation.fill <= 1 && relation.long <= 1 && relation.wide > 1
      }, { timeout: 10_000 }).toBe(true)
    } finally {
      await page.evaluate(() => { document.documentElement.style.zoom = '' })
    }
    expect(tripwire.pageErrors).toEqual([])
    expect(tripwire.warnings).toEqual([])
  }, 120_000)
})
