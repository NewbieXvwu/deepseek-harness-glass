#!/usr/bin/env node
import { createRequire } from 'node:module'
import { readFileSync, existsSync } from 'node:fs'
import { resolve, relative } from 'node:path'

const args = process.argv.slice(2)
const isInner = args.includes('--inner')
const nonFlagArgs = args.filter(arg => !arg.startsWith('--'))

const [officialRootArgument, sourceArgument, component, fill = '#0F1115'] = nonFlagArgs
if (!officialRootArgument || !sourceArgument || !component) {
  throw new Error('usage: extract_official_icon_ast.mjs <official-root> <source.tsx> <component> [fill] [--inner]')
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
      // Fallback to local typescript
    }
  }
  const requireLocal = createRequire(import.meta.url)
  return requireLocal('typescript')
}

const ts = loadTypeScript()
const sourceText = readFileSync(sourcePath, 'utf8')
const sourceFile = ts.createSourceFile(sourcePath, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX)
const relativePath = relative(officialRoot, sourcePath).replaceAll('\\', '/')

const declaration = findExportedComponent(component)
const svg = singleSvgSubtree(declaration)

if (isInner) {
  const firstChild = svg.children.find(c => ts.isJsxElement(c) || ts.isJsxSelfClosingElement(c))
  const lastChild = [...svg.children].reverse().find(c => ts.isJsxElement(c) || ts.isJsxSelfClosingElement(c))
  if (!firstChild || !lastChild) {
    fail('svg contains no JSX child elements', svg)
  }
  const start = consumeLeadingWhitespace(firstChild.getStart(sourceFile), svg.openingElement.getEnd())
  const replacements = []
  visitSvg(svg, node => {
    if (!ts.isJsxAttribute(node) || !ts.isJsxExpression(node.initializer) || !ts.isIdentifier(node.initializer.expression)) return
    const value = topLevelStringConstant(node.initializer.expression.text)
    if (value !== undefined) replacements.push(replace(node, `${node.name.text}="${escapeXmlAttribute(value)}"`))
  })
  const innerRaw = sourceText.slice(start, lastChild.getEnd())
  process.stdout.write(applyReplacements(innerRaw, replacements, start) + '\n')
  process.exit(0)
}

const size = defaultSizeFromComponent(declaration)
const rawSvg = sourceText.slice(svg.getStart(sourceFile), svg.getEnd())
const replacements = []

visitSvg(svg, node => {
  if (!ts.isJsxAttribute(node)) return
  const name = node.name.text
  const initializer = node.initializer
  const rootAttribute = node.parent?.parent === svg.openingElement
  if (rootAttribute && (name === 'width' || name === 'height')) {
    requireExpressionIdentifier(initializer, 'size', name)
    replacements.push(replace(node, `${name}="${size}"`))
    return
  }
  if (rootAttribute && name === 'className') {
    requireExpressionIdentifier(initializer, 'className', name)
    const start = consumeLeadingWhitespace(node.getStart(sourceFile), svg.getStart(sourceFile))
    replacements.push({ start, end: node.getEnd(), value: '' })
    return
  }
  if (name === 'fillRule' || name === 'clipRule' || name === 'clipPath') {
    replacements.push(replaceRange(node.name.getStart(sourceFile), node.name.getEnd(), kebab(name)))
  }
  if (name === 'fill' && ts.isStringLiteral(initializer)) {
    if (initializer.text === 'currentColor') replacements.push(replace(node, `fill="${fill}"`))
    return
  }
  if (initializer && ts.isJsxExpression(initializer) && initializer.expression && ts.isNumericLiteral(initializer.expression)) {
    replacements.push(replace(node, `${name}="${initializer.expression.text}"`))
  }
})

process.stdout.write(applyReplacements(rawSvg, replacements, svg.getStart(sourceFile)))

function findExportedComponent(name) {
  let match
  for (const statement of sourceFile.statements) {
    if (!hasExportModifier(statement)) continue
    if (ts.isFunctionDeclaration(statement)) {
      if (statement.name?.text === name) {
        if (match) fail(`duplicate exported component ${name}`, statement)
        match = statement
      }
      continue
    }
    if (ts.isVariableStatement(statement)) {
      for (const candidate of statement.declarationList.declarations) {
        if (!ts.isIdentifier(candidate.name) || candidate.name.text !== name) continue
        if (!candidate.initializer || (!ts.isArrowFunction(candidate.initializer) && !ts.isFunctionExpression(candidate.initializer))) {
          fail(`component must be an exported function`, candidate)
        }
        if (match) fail(`duplicate exported component ${name}`, candidate)
        match = candidate
      }
    }
  }
  if (!match) throw new Error(`component not found: ${name} in ${relativePath}`)
  return match
}

function defaultSizeFromComponent(declaration) {
  const parameters = ts.isFunctionDeclaration(declaration)
    ? declaration.parameters
    : declaration.initializer.parameters
  const parameter = parameters.at(0)
  if (!parameter || !ts.isObjectBindingPattern(parameter.name)) fail('component requires an object binding parameter', declaration)
  const size = parameter.name.elements.find(element => ts.isIdentifier(element.name) && element.name.text === 'size')
  if (!size?.initializer || !ts.isNumericLiteral(size.initializer)) fail('component size must have a numeric default', parameter)
  return size.initializer.text
}

function topLevelStringConstant(name) {
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) continue
    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || declaration.name.text !== name) continue
      if (ts.isStringLiteral(declaration.initializer) || ts.isNoSubstitutionTemplateLiteral(declaration.initializer)) {
        return declaration.initializer.text
      }
    }
  }
}

function singleSvgSubtree(root) {
  const matches = []
  const visit = node => {
    if (ts.isJsxElement(node) && ts.isIdentifier(node.openingElement.tagName) && node.openingElement.tagName.text === 'svg') matches.push(node)
    ts.forEachChild(node, visit)
  }
  visit(root)
  if (matches.length !== 1) fail(`component must contain exactly one SVG JSX element; found ${matches.length}`, root)
  return matches[0]
}

function visitSvg(root, callback) {
  const visit = node => {
    callback(node)
    ts.forEachChild(node, visit)
  }
  visit(root)
}

function requireExpressionIdentifier(initializer, expected, attribute) {
  if (!initializer || !ts.isJsxExpression(initializer) || !initializer.expression || !ts.isIdentifier(initializer.expression) || initializer.expression.text !== expected) {
    fail(`${attribute} must be the ${expected} parameter`, initializer ?? sourceFile)
  }
}

function consumeLeadingWhitespace(position, lowerBound) {
  let start = position
  while (start > lowerBound && (sourceText[start - 1] === ' ' || sourceText[start - 1] === '\t')) start -= 1
  return start
}

function replace(node, value) {
  return replaceRange(node.getStart(sourceFile), node.getEnd(), value)
}

function replaceRange(start, end, value) {
  return { start, end, value }
}

function applyReplacements(svgText, replacements, offset) {
  const ordered = replacements.sort((left, right) => right.start - left.start)
  let output = svgText
  let lastStart = Infinity
  for (const replacement of ordered) {
    if (replacement.end > lastStart) throw new Error(`overlapping AST attribute rewrites in ${relativePath}`)
    output = output.slice(0, replacement.start - offset) + replacement.value + output.slice(replacement.end - offset)
    lastStart = replacement.start
  }
  return output
}

function kebab(name) {
  return name.replace(/[A-Z]/g, letter => `-${letter.toLowerCase()}`)
}

function escapeXmlAttribute(value) {
  return value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;')
}

function hasExportModifier(node) {
  return node.modifiers?.some(modifier => modifier.kind === ts.SyntaxKind.ExportKeyword) === true
}

function fail(message, node) {
  const line = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1
  throw new Error(`${message} at ${relativePath}:${line}`)
}
