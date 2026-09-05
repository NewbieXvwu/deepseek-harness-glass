#!/usr/bin/env node
import { createRequire } from 'node:module'
import { readFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'

const [officialRootArgument] = process.argv.slice(2)
if (!officialRootArgument) {
  throw new Error('usage: extract_ghost_plane_ast.mjs <official-root>')
}

const officialRoot = resolve(officialRootArgument)

function loadTypeScript() {
  const officialPkg = resolve(officialRoot, 'package.json')
  if (existsSync(officialPkg)) {
    try {
      const requireFromOfficial = createRequire(officialPkg)
      return requireFromOfficial('typescript')
    } catch {
      // Fallback to local typescript
    }
  }
  const requireLocal = createRequire(import.meta.url)
  return requireLocal('typescript')
}

const ts = loadTypeScript()

const SLOT_PATHS = [
  'packages/client/ui-conversation/src/client/contract/slots.ts',
  'packages/client/ui-chat/src/client/contract/slots.ts',
].map(relativePath => resolve(officialRoot, relativePath))
for (const slotPath of SLOT_PATHS) {
  if (!existsSync(slotPath)) throw new Error(`slots.ts not found at ${slotPath}`)
}

const slots = []

function extractSlotMap(node) {
  if (ts.isInterfaceDeclaration(node) && node.name.text === 'SlotMap') {
    for (const member of node.members) {
      if (!ts.isPropertySignature(member)) continue
      let name = null
      if (ts.isStringLiteral(member.name) || ts.isIdentifier(member.name)) {
        name = member.name.text
      }
      if (!name || !member.type || !ts.isTypeLiteralNode(member.type)) continue

      let kind = null
      let scope = null

      for (const subMember of member.type.members) {
        if (!ts.isPropertySignature(subMember) || !ts.isIdentifier(subMember.name)) continue
        const propName = subMember.name.text
        if (propName === 'kind' && subMember.type && ts.isLiteralTypeNode(subMember.type) && ts.isStringLiteral(subMember.type.literal)) {
          kind = subMember.type.literal.text
        } else if (propName === 'scope' && subMember.type && ts.isLiteralTypeNode(subMember.type) && ts.isStringLiteral(subMember.type.literal)) {
          scope = subMember.type.literal.text
        }
      }

      if (kind && scope) {
        slots.push({ name, kind, scope })
      }
    }
  }
  ts.forEachChild(node, extractSlotMap)
}

for (const slotPath of SLOT_PATHS) {
  const slotSourceText = readFileSync(slotPath, 'utf8')
  const slotSourceFile = ts.createSourceFile(slotPath, slotSourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)
  extractSlotMap(slotSourceFile)
}

const TSX_SOURCES = [
  'packages/client/ui-conversation/src/client/skeleton/ConversationRoot.tsx',
  'packages/client/ui-chat/src/client/chat/ChatView.tsx',
  'packages/client/ui-chat/src/client/chat/ChatNodeSeat.tsx',
  'packages/client/ui-chat/src/client/chat/AssistantMarkdown.tsx',
]

const dataSelectors = new Set()

for (const relativePath of TSX_SOURCES) {
  const filePath = resolve(officialRoot, relativePath)
  if (!existsSync(filePath)) {
    throw new Error(`required TSX source not found: ${relativePath}`)
  }
  const sourceText = readFileSync(filePath, 'utf8')
  const sourceFile = ts.createSourceFile(filePath, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX)

  function visit(node) {
    if (ts.isJsxAttribute(node)) {
      const attrName = node.name.text
      if (attrName.startsWith('data-')) {
        dataSelectors.add(`[${attrName}]`)
      }
    }
    ts.forEachChild(node, visit)
  }

  visit(sourceFile)
}

const result = {
  slots: slots.sort((a, b) => a.name.localeCompare(b.name)),
  dataSelectors: Array.from(dataSelectors).sort(),
}

process.stdout.write(JSON.stringify(result))
