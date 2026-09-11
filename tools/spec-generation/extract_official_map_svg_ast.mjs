#!/usr/bin/env node
import { createRequire } from 'node:module'
import { existsSync, readFileSync } from 'node:fs'
import { relative, resolve } from 'node:path'

const [officialRootArgument, sourceArgument, mapName, entryKey] = process.argv.slice(2)
if (!officialRootArgument || !sourceArgument || !mapName || !entryKey) {
  throw new Error('usage: extract_official_map_svg_ast.mjs <official-root> <source.tsx> <map-name> <entry-key>')
}

const officialRoot = resolve(officialRootArgument)
const sourcePath = resolve(sourceArgument)

function loadTypeScript() {
  const officialPkg = resolve(officialRoot, 'package.json')
  if (existsSync(officialPkg)) {
    try {
      const requireFromOfficial = createRequire(officialPkg)
      return requireFromOfficial('typescript')
    } catch {
      // Fall through to the parser pinned by this repository.
    }
  }
  return createRequire(import.meta.url)('typescript')
}

const ts = loadTypeScript()
const sourceText = readFileSync(sourcePath, 'utf8')
const sourceFile = ts.createSourceFile(sourcePath, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX)
const relativePath = relative(officialRoot, sourcePath).replaceAll('\\', '/')

function fail(message, node = sourceFile) {
  const line = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1
  throw new Error(`${message} at ${relativePath}:${line}`)
}

function unwrap(expression) {
  let current = expression
  while (
    ts.isParenthesizedExpression(current) ||
    ts.isAsExpression(current) ||
    ts.isTypeAssertionExpression(current) ||
    ts.isSatisfiesExpression(current)
  ) {
    current = current.expression
  }
  return current
}

function findMapInitializer() {
  let found
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) continue
    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || declaration.name.text !== mapName) continue
      if (found) fail(`duplicate map declaration ${mapName}`, declaration)
      const initializer = declaration.initializer && unwrap(declaration.initializer)
      if (!initializer || !ts.isNewExpression(initializer) || !ts.isIdentifier(initializer.expression) || initializer.expression.text !== 'Map') {
        fail(`${mapName} must be initialized with new Map(...)`, declaration)
      }
      const argument = initializer.arguments?.at(0)
      if (!argument || !ts.isArrayLiteralExpression(unwrap(argument))) {
        fail(`${mapName} must receive an array literal`, initializer)
      }
      found = unwrap(argument)
    }
  }
  if (!found) throw new Error(`map not found: ${mapName} in ${relativePath}`)
  return found
}

function literalKey(node) {
  const value = unwrap(node)
  if (ts.isStringLiteral(value) || ts.isNoSubstitutionTemplateLiteral(value)) return value.text
  if (ts.isIdentifier(value)) return topLevelStringConstant(value.text)
  return undefined
}

function topLevelStringConstant(name) {
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) continue
    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || declaration.name.text !== name) continue
      const initializer = declaration.initializer && unwrap(declaration.initializer)
      if (initializer && (ts.isStringLiteral(initializer) || ts.isNoSubstitutionTemplateLiteral(initializer))) return initializer.text
    }
  }
}

function findEntryValue(array) {
  let found
  for (const element of array.elements) {
    const entry = unwrap(element)
    if (!ts.isArrayLiteralExpression(entry) || entry.elements.length < 2) continue
    if (literalKey(entry.elements[0]) !== entryKey) continue
    if (found) fail(`duplicate ${mapName} entry ${entryKey}`, entry)
    found = unwrap(entry.elements[1])
  }
  if (!found) throw new Error(`entry not found: ${mapName}[${JSON.stringify(entryKey)}] in ${relativePath}`)
  return found
}

function singleSvgSubtree(root) {
  const matches = []
  const visit = node => {
    if (ts.isJsxElement(node) && ts.isIdentifier(node.openingElement.tagName) && node.openingElement.tagName.text === 'svg') matches.push(node)
    ts.forEachChild(node, visit)
  }
  visit(root)
  if (matches.length !== 1) fail(`map entry must contain exactly one SVG JSX element; found ${matches.length}`, root)
  return matches[0]
}

const SVG_ATTRIBUTE_NAMES = new Map([
  ['fillRule', 'fill-rule'],
  ['clipRule', 'clip-rule'],
  ['clipPath', 'clip-path'],
  ['strokeWidth', 'stroke-width'],
  ['strokeLinejoin', 'stroke-linejoin'],
  ['strokeLinecap', 'stroke-linecap'],
])

function svgAttributeName(name) {
  return SVG_ATTRIBUTE_NAMES.get(name) ?? name
}

function escapeXmlAttribute(value) {
  return value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;')
}

function attributeValue(attribute) {
  const initializer = attribute.initializer
  if (!initializer) return null
  if (ts.isStringLiteral(initializer)) return initializer.text
  if (!ts.isJsxExpression(initializer) || !initializer.expression) return undefined
  const expression = unwrap(initializer.expression)
  if (ts.isStringLiteral(expression) || ts.isNoSubstitutionTemplateLiteral(expression)) return expression.text
  if (ts.isNumericLiteral(expression)) return expression.text
  if (ts.isIdentifier(expression)) return topLevelStringConstant(expression.text)
  return undefined
}

function renderAttributes(properties, root = false) {
  const rendered = []
  for (const property of properties) {
    if (!ts.isJsxAttribute(property)) fail('spread attributes are not supported', property)
    const name = property.name.text
    if (root && name === 'aria-hidden') continue
    const value = attributeValue(property)
    if (value === null) {
      rendered.push(svgAttributeName(name))
      continue
    }
    if (value === undefined) fail(`attribute ${name} is not a static literal`, property)
    rendered.push(`${svgAttributeName(name)}="${escapeXmlAttribute(value)}"`)
  }
  if (root && !rendered.some(value => value.startsWith('xmlns='))) rendered.push('xmlns="http://www.w3.org/2000/svg"')
  return rendered.length ? ` ${rendered.join(' ')}` : ''
}

function renderNode(node, depth, root = false) {
  const indent = '  '.repeat(depth)
  if (ts.isJsxSelfClosingElement(node)) {
    return `${indent}<${node.tagName.getText(sourceFile)}${renderAttributes(node.attributes.properties, root)}/>`
  }
  if (!ts.isJsxElement(node)) fail('only JSX element children are supported', node)
  const tag = node.openingElement.tagName.getText(sourceFile)
  const open = `${indent}<${tag}${renderAttributes(node.openingElement.attributes.properties, root)}>`
  const children = node.children.filter(child => !ts.isJsxText(child) || child.getText(sourceFile).trim().length > 0)
  if (children.length === 0) return `${open}</${tag}>`
  const body = children.map(child => {
    if (ts.isJsxElement(child) || ts.isJsxSelfClosingElement(child)) return renderNode(child, depth + 1)
    fail('map SVG contains a non-element JSX child', child)
  }).join('\n')
  return `${open}\n${body}\n${indent}</${tag}>`
}

const svg = singleSvgSubtree(findEntryValue(findMapInitializer()))
process.stdout.write(renderNode(svg, 0, true) + '\n')
