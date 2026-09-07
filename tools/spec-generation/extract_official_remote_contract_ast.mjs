#!/usr/bin/env node
import { createRequire } from 'node:module'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { resolve, relative } from 'node:path'

const [officialRootArgument] = process.argv.slice(2)
if (!officialRootArgument) throw new Error('usage: extract_official_remote_contract_ast.mjs <official-root>')
const officialRoot = resolve(officialRootArgument)

let ts
try {
  const requireOfficial = createRequire(resolve(officialRoot, 'package.json'))
  ts = requireOfficial('typescript')
} catch {}

if (!ts || !ts.createSourceFile) {
  const fallbackRoots = [
    resolve(process.env.HOME || '', 'deepseek-harness'),
    resolve(officialRoot, '../deepseek-harness'),
    resolve(officialRoot, '../../deepseek-harness'),
    process.cwd(),
  ]
  for (const root of fallbackRoots) {
    try {
      const candidateRequire = createRequire(resolve(root, 'package.json'))
      ts = candidateRequire('typescript')
      if (ts && ts.createSourceFile) break
    } catch {}
  }
}

if (!ts || !ts.createSourceFile) {
  try {
    const localRequire = createRequire(import.meta.url)
    ts = localRequire('typescript')
  } catch {}
}

if (!ts || !ts.createSourceFile) {
  throw new Error(`cannot load typescript compiler API for AST extraction at ${officialRoot}`)
}

const SOURCE_PATHS = [
  'packages/preset/agent-presets/src/index.ts',
  'packages/api/settings-controller/src/index.ts',
  'packages/api/settings-controller/src/credentials.ts',
  'packages/goal/goal/src/index.ts',
  'packages/llm/llm/src/index.ts',
  'packages/feedback/message-feedback/src/index.ts',
  'packages/subagent/subagent/src/index.ts',
  'packages/api/session-controller/src/index.ts',
  'packages/api/workspace-controller/src/index.ts',
]

const ERROR_SCAN_ROOTS = [
  'packages/preset/agent-presets/src',
  'packages/api/settings-controller/src',
  'packages/goal/goal/src',
  'packages/llm/llm/src',
  'packages/feedback/message-feedback/src',
  'packages/subagent/subagent/src',
  'packages/api/session-controller/src',
  'packages/api/workspace-controller/src',
  'packages/core/session/src',
  'packages/workspace/workspace/src',
]

const EXTRA_GATEWAY_ERRORS = ['gateway/method-unavailable', 'gateway/service-unavailable']

const SKIP_ENDPOINTS = new Set(['settings/update', 'settings/replace'])
const LOOKUPS = new Map([
  ['Agent', { lookup: 'agent', wire: 'agentId' }],
  ['Session', { lookup: 'session', wire: 'sessionId' }],
])

function remoteDecorator(method) {
  const decorators = ts.canHaveDecorators(method) ? ts.getDecorators(method) : undefined
  for (const decorator of decorators ?? []) {
    const expr = decorator.expression
    const call = ts.isCallExpression(expr) ? expr : undefined
    const target = call ? call.expression : expr
    if (!ts.isIdentifier(target) || target.text !== 'Remote') continue
    let exportName
    let mode = 'unary'
    if (call && call.arguments.length === 1) {
      const argument = call.arguments[0]
      if (ts.isStringLiteral(argument)) exportName = argument.text
      else if (ts.isObjectLiteralExpression(argument)) {
        const props = argument.properties.filter(ts.isPropertyAssignment)
        if (props.length !== 1 || props[0].name.getText() !== 'mode' || !ts.isStringLiteral(props[0].initializer) || props[0].initializer.text !== 'stream') {
          throw new Error(`unsupported Remote decorator at ${method.getSourceFile().fileName}`)
        }
        mode = 'stream'
      }
    } else if (call && call.arguments.length > 1) {
      throw new Error(`unsupported Remote decorator arity at ${method.getSourceFile().fileName}`)
    }
    return { exportName, mode }
  }
  return undefined
}

function classNamespace(cls, sourceFile) {
  for (const member of cls.members) {
    if (!ts.isConstructorDeclaration(member) || !member.body) continue
    for (const statement of member.body.statements) {
      if (!ts.isExpressionStatement(statement) || !ts.isCallExpression(statement.expression)) continue
      const call = statement.expression
      if (call.expression.kind !== ts.SyntaxKind.SuperKeyword) continue
      const args = call.arguments
      let namespace
      if (args.length >= 2 && ts.isStringLiteral(args[1])) namespace = args[1].text
      if (args.length >= 3 && ts.isObjectLiteralExpression(args[2])) {
        for (const property of args[2].properties) {
          if (ts.isPropertyAssignment(property) && property.name.getText(sourceFile) === 'namespace' && ts.isStringLiteral(property.initializer)) {
            namespace = property.initializer.text
          }
        }
      }
      if (namespace) return namespace
    }
  }
  return undefined
}

function normalizeType(text) {
  return text.replace(/\s+/g, ' ').replace(/\s*([<>{}\[\](),|&?:])\s*/g, '$1').trim()
}

// 1. Extract Procedures
const procedures = []
for (const relativePath of SOURCE_PATHS) {
  const absolutePath = resolve(officialRoot, relativePath)
  if (!existsSync(absolutePath)) throw new Error(`required Remote source missing: ${relativePath}`)
  const sourceText = readFileSync(absolutePath, 'utf8')
  const sourceFile = ts.createSourceFile(absolutePath, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)
  for (const statement of sourceFile.statements) {
    if (!ts.isClassDeclaration(statement)) continue
    const namespace = classNamespace(statement, sourceFile)
    if (!namespace) continue
    for (const member of statement.members) {
      if (!ts.isMethodDeclaration(member) || !member.name || !ts.isIdentifier(member.name)) continue
      const remote = remoteDecorator(member)
      if (!remote) continue
      const method = remote.exportName ?? member.name.text
      const endpoint = `${namespace}/${method}`
      if (SKIP_ENDPOINTS.has(endpoint)) continue
      const parameters = []
      const injected = []
      for (const parameter of member.parameters) {
        if (!ts.isIdentifier(parameter.name) || !parameter.type) throw new Error(`${endpoint}: unsupported parameter declaration`)
        const name = parameter.name.text
        const authoredType = normalizeType(parameter.type.getText(sourceFile))
        if (name === 'signal' && authoredType === 'AbortSignal') {
          injected.push({ name: 'signal', kind: 'AbortSignal' })
          continue
        }
        const lookup = LOOKUPS.get(authoredType)
        parameters.push({
          name,
          wire: lookup?.wire ?? name,
          source: lookup ? 'lookup' : 'json',
          ...(lookup ? { lookup: lookup.lookup } : {}),
          type: authoredType,
          optional: parameter.questionToken !== undefined,
        })
      }
      const returnType = member.type ? normalizeType(member.type.getText(sourceFile)) : 'unknown'
      const line = sourceFile.getLineAndCharacterOfPosition(member.getStart(sourceFile)).line + 1
      procedures.push({ endpoint, mode: remote.mode, parameters, injected, returnType, sourcePath: relativePath, sourceLine: line })
    }
  }
}
procedures.sort((a, b) => a.endpoint.localeCompare(b.endpoint))

// 2. Extract Errors via AST
function getAllTsFiles(dir) {
  let results = []
  if (!existsSync(dir)) return results
  const list = readdirSync(dir)
  for (const file of list) {
    const fullPath = resolve(dir, file)
    const stat = statSync(fullPath)
    if (stat && stat.isDirectory()) results = results.concat(getAllTsFiles(fullPath))
    else if (file.endsWith('.ts') && file !== 'directory-picker.ts') results.push(fullPath)
  }
  return results
}

const declaredErrors = new Map()
const thrownErrorCodes = new Set()

function scanErrorFile(filePath) {
  const relPath = relative(officialRoot, filePath)
  const sourceText = readFileSync(filePath, 'utf8')
  const sourceFile = ts.createSourceFile(filePath, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)

  function visit(node) {
    if (ts.isInterfaceDeclaration(node) && node.name.text === 'RemoteErrorDetailsMap') {
      for (const member of node.members) {
        if (ts.isPropertySignature(member) && member.name) {
          const rawName = member.name.getText(sourceFile)
          const code = rawName.replace(/^['"]|['"]$/g, '')
          const detailsType = member.type ? member.type.getText(sourceFile).replace(/\s+/g, ' ').trim() : 'unknown'
          declaredErrors.set(code, { detailsType, sourcePath: relPath })
        }
      }
    }
    if (ts.isNewExpression(node)) {
      const target = node.expression
      if (ts.isIdentifier(target) && target.text === 'RemoteError' && node.arguments && node.arguments.length > 0) {
        const firstArg = node.arguments[0]
        if (ts.isStringLiteral(firstArg)) {
          thrownErrorCodes.add(firstArg.text)
        }
      }
    }
    ts.forEachChild(node, visit)
  }
  visit(sourceFile)
}

for (const root of ERROR_SCAN_ROOTS) {
  for (const file of getAllTsFiles(resolve(officialRoot, root))) {
    scanErrorFile(file)
  }
}
scanErrorFile(resolve(officialRoot, 'packages/typert/protocol/src/types.ts'))
scanErrorFile(resolve(officialRoot, 'packages/api/gateway/src/remote-error-codes.ts'))

for (const extra of EXTRA_GATEWAY_ERRORS) {
  thrownErrorCodes.add(extra)
}

const missing = [...thrownErrorCodes].filter(c => !declaredErrors.has(c))
if (missing.length > 0) {
  throw new Error('Remote errors lack declared details: ' + missing.join(', '))
}

const closedRemoteErrors = [...thrownErrorCodes].sort().map(code => {
  const decl = declaredErrors.get(code)
  return {
    code,
    detailsType: decl.detailsType,
    sourcePath: decl.sourcePath,
  }
})

process.stdout.write(JSON.stringify({ procedures, closedRemoteErrors }, null, 2))

