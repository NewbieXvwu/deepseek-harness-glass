import { copyFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'

const workspace = process.env.GITHUB_WORKSPACE
if (workspace === undefined) throw new Error('GITHUB_WORKSPACE is required for official reference capture')
const destination = fileURLToPath(new URL('.', import.meta.url))

for (const name of [
  'capture-official-base.e2e.ts',
  'capture-official-cut1.8.e2e.ts',
  'capture-official-cut1.8-image.e2e.ts',
  'capture-official-cut1.8-table.e2e.ts',
  'capture-official-cut1.8-history-image.e2e.ts',
  'capture-official-cut1.8-recovery.e2e.ts',
  'capture-official-cut1.8-tool-details.e2e.ts',
]) {
  await copyFile(join(workspace, 'tools/reference-capture', name), join(destination, name))
}

await import('./capture-official-base.e2e.ts')
await import('./capture-official-cut1.8.e2e.ts')
await import('./capture-official-cut1.8-image.e2e.ts')
await import('./capture-official-cut1.8-table.e2e.ts')
await import('./capture-official-cut1.8-history-image.e2e.ts')
await import('./capture-official-cut1.8-recovery.e2e.ts')
await import('./capture-official-cut1.8-tool-details.e2e.ts')
