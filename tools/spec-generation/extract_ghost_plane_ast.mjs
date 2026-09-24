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

function parse(relativePath, scriptKind = ts.ScriptKind.TS) {
  const filePath = resolve(officialRoot, relativePath)
  if (!existsSync(filePath)) throw new Error(`required source not found: ${relativePath}`)
  const sourceText = readFileSync(filePath, 'utf8')
  return ts.createSourceFile(filePath, sourceText, ts.ScriptTarget.Latest, true, scriptKind)
}

const SLOT_SOURCES = [
  'packages/client/ui-conversation/src/client/contract/slots.ts',
  'packages/client/ui-chat/src/client/contract/slots.ts',
]
const slots = []

function extractSlotMap(node, sourcePath) {
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
      if (kind && scope) slots.push({ name, kind, scope, sourcePath })
    }
  }
  ts.forEachChild(node, child => extractSlotMap(child, sourcePath))
}

for (const relativePath of SLOT_SOURCES) {
  const sourceFile = parse(relativePath)
  extractSlotMap(sourceFile, relativePath)
}

const TSX_SOURCES = [
  'packages/client/ui-conversation/src/client/skeleton/ConversationRoot.tsx',
  'packages/client/ui-chat/src/client/chat/ChatView.tsx',
  'packages/client/ui-chat/src/client/chat/ChatNodeSeat.tsx',
  'packages/client/ui-chat/src/client/chat/AssistantMarkdown.tsx',
]
const dataSelectors = new Set()
for (const relativePath of TSX_SOURCES) {
  const sourceFile = parse(relativePath, ts.ScriptKind.TSX)
  function visit(node) {
    if (ts.isJsxAttribute(node)) {
      const attrName = node.name.text
      if (attrName.startsWith('data-')) dataSelectors.add(`[${attrName}]`)
    }
    ts.forEachChild(node, visit)
  }
  visit(sourceFile)
}

function namedInterface(sourceFile, name) {
  return sourceFile.statements.find(statement => ts.isInterfaceDeclaration(statement) && statement.name.text === name)
}

function namedFunction(sourceFile, name) {
  return sourceFile.statements.find(statement => ts.isFunctionDeclaration(statement) && statement.name?.text === name)
}

function namedTypeAlias(sourceFile, name) {
  return sourceFile.statements.find(statement => ts.isTypeAliasDeclaration(statement) && statement.name.text === name)
}

function propertyName(member) {
  if (!member.name) return null
  if (ts.isIdentifier(member.name) || ts.isStringLiteral(member.name)) return member.name.text
  return null
}

function typeReferenceName(typeNode) {
  return typeNode && ts.isTypeReferenceNode(typeNode) && ts.isIdentifier(typeNode.typeName)
    ? typeNode.typeName.text
    : null
}

function stringLiteralUnion(typeNode) {
  const nodes = ts.isUnionTypeNode(typeNode) ? typeNode.types : [typeNode]
  const values = []
  for (const node of nodes) {
    if (!ts.isLiteralTypeNode(node) || !ts.isStringLiteral(node.literal)) return null
    values.push(node.literal.text)
  }
  return values
}

function templateText(template, sourceFile) {
  if (ts.isNoSubstitutionTemplateLiteral(template)) return template.text
  if (!ts.isTemplateExpression(template)) return null
  let value = template.head.text
  for (const span of template.templateSpans) {
    value += '${' + span.expression.getText(sourceFile) + '}' + span.literal.text
  }
  return value
}

function extractModuleLoader() {
  const manifest = parse('packages/client/modules/src/client/manifest.ts')
  const host = parse('packages/client/modules/src/index.ts')

  const windowInterface = namedInterface(manifest, 'DshWindow')
  const loaderTarget = namedInterface(manifest, 'ClientModuleLoaderTarget')
  const registration = namedInterface(manifest, 'ClientBundleRegistration')
  const graph = namedInterface(manifest, 'WebBootGraph')
  const moduleRow = namedInterface(manifest, 'BootModuleRow')
  const batchPhase = namedTypeAlias(manifest, 'WebBootBatchPhase')
  const parseManifest = namedFunction(manifest, 'parseBootManifest')
  const comboUrl = namedFunction(host, 'comboUrl')
  if (!windowInterface || !loaderTarget || !registration || !graph || !moduleRow || !batchPhase || !parseManifest?.body || !comboUrl?.body) {
    throw new Error('rc.1 module-loader AST contract is incomplete')
  }

  let bootGlobal = null
  let registrationGlobal = null
  for (const member of windowInterface.members) {
    if (!ts.isPropertySignature(member) || !member.type) continue
    const name = propertyName(member)
    if (!name) continue
    if (member.type.kind === ts.SyntaxKind.UnknownKeyword) bootGlobal = name
    if (typeReferenceName(member.type) === 'ClientModuleLoaderTarget') registrationGlobal = name
  }
  if (!bootGlobal || !registrationGlobal) throw new Error('rc.1 DshWindow globals are missing')

  let registrationMethod = null
  for (const member of loaderTarget.members) {
    if (!ts.isMethodSignature(member) || member.parameters.length !== 1) continue
    if (typeReferenceName(member.parameters[0].type) === 'ClientBundleRegistration') {
      registrationMethod = propertyName(member)
    }
  }
  if (!registrationMethod) throw new Error('rc.1 module registration method is missing')

  const factoryRegistration = registration.members.some(member =>
    ts.isPropertySignature(member) && propertyName(member) === 'factory' && member.type && ts.isFunctionTypeNode(member.type),
  )
  if (!factoryRegistration) throw new Error('rc.1 bundle registration factory is missing')

  const graphHasBatches = graph.members.some(member =>
    ts.isPropertySignature(member) && propertyName(member) === 'batches',
  )
  const moduleRowHasInitialUrl = moduleRow.members.some(member =>
    ts.isPropertySignature(member) && propertyName(member) === 'initialUrl',
  )
  if (!graphHasBatches || !moduleRowHasInitialUrl) throw new Error('rc.1 boot graph batch projection is missing')

  function unwrapExpression(node) {
    while (ts.isAsExpression(node) || ts.isTypeAssertionExpression(node) || ts.isParenthesizedExpression(node) || ts.isSatisfiesExpression?.(node)) {
      node = node.expression
    }
    return node
  }

  let sawBatchIteration = false
  let sawInitialUrlSet = false
  let sawInitialUrlProjection = false
  function visitManifest(node) {
    if (ts.isForOfStatement(node)) {
      const iterable = unwrapExpression(node.expression)
      if (ts.isPropertyAccessExpression(iterable) && iterable.name.text === 'batches') {
        sawBatchIteration = true
      }
    }
    if (ts.isCallExpression(node)
      && ts.isPropertyAccessExpression(node.expression)) {
      const call = node
      if (ts.isIdentifier(call.expression.expression)
        && call.expression.expression.text === 'initialUrls'
        && call.expression.name.text === 'set') {
        sawInitialUrlSet = true
      }
    }
    if (ts.isObjectLiteralExpression(node)) {
      const hasInitialUrl = node.properties.some(property =>
        ts.isShorthandPropertyAssignment(property) && property.name.text === 'initialUrl',
      )
      const hasRowSpread = node.properties.some(property =>
        ts.isSpreadAssignment(property) && ts.isIdentifier(property.expression) && property.expression.text === 'row',
      )
      if (hasInitialUrl && hasRowSpread) sawInitialUrlProjection = true
    }
    ts.forEachChild(node, visitManifest)
  }
  visitManifest(parseManifest.body)
  const initialURLFromBatches = sawBatchIteration && sawInitialUrlSet && sawInitialUrlProjection
  if (!initialURLFromBatches) throw new Error('rc.1 initialUrl is no longer projected from boot batches')

  const bootBatchPhases = stringLiteralUnion(batchPhase.type)
  if (!bootBatchPhases || bootBatchPhases.length === 0) throw new Error('rc.1 boot batch phases are missing')

  let comboRouteTemplate = null
  function visitCombo(node) {
    if (ts.isReturnStatement(node) && node.expression) {
      const candidate = templateText(node.expression, host)
      if (candidate !== null) comboRouteTemplate = candidate
    }
    ts.forEachChild(node, visitCombo)
  }
  visitCombo(comboUrl.body)
  if (!comboRouteTemplate) throw new Error('rc.1 comboUrl does not return a template literal')

  return {
    bootGlobal,
    registrationGlobal,
    registrationMethod,
    comboRouteTemplate,
    bootBatchPhases,
    initialURLFromBatches,
    factoryRegistration,
  }
}

const result = {
  slots: slots.sort((a, b) => a.name.localeCompare(b.name)),
  dataSelectors: Array.from(dataSelectors).sort(),
  moduleLoader: extractModuleLoader(),
}

process.stdout.write(JSON.stringify(result))
