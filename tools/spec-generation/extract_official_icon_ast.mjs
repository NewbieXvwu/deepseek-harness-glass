#!/usr/bin/env node
import { createRequire } from 'node:module'
import { readFileSync } from 'node:fs'
import { resolve, relative } from 'node:path'

const [officialRootArgument, sourceArgument, component, fill = '#0F1115'] = process.argv.slice(2)
if (!officialRootArgument || !sourceArgument || !component) {
  throw new Error('usage: extract_official_icon_ast.mjs <official-root> <source.tsx> <component> [fill]')
}

const officialRoot = resolve(officialRootArgument)
const sourcePath = resolve(sourceArgument)
const requireFromOfficial = createRequire(resolve(officialRoot, 'package.json'))
const ts = requireFromOfficial('typescript')
const sourceText = readFileSync(sourcePath, 'utf8')
const sourceFile = ts.createSourceFile(sourcePath, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX)
const relativePath = relative(officialRoot, sourcePath).replaceAll('\\', '/')

const declaration = findExportedComponent(component)
const size = defaultSizeFromComponent(declaration)
const svg = singleSvgSubtree(declaration.initializer)
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
    if (!ts.isVariableStatement(statement) || !hasExportModifier(statement)) continue
    for (const candidate of statement.declarationList.declarations) {
      if (!ts.isIdentifier(candidate.name) || candidate.name.text !== name) continue
      if (!candidate.initializer || !ts.isArrowFunction(candidate.initializer)) {
        fail(`component must be an exported arrow function`, candidate)
      }
      if (match) fail(`duplicate exported component ${name}`, candidate)
      match = candidate
    }
  }
  if (!match) throw new Error(`component not found: ${name} in ${relativePath}`)
  return match
}

function defaultSizeFromComponent(declaration) {
  const parameter = declaration.initializer.parameters.at(0)
  if (!parameter || !ts.isObjectBindingPattern(parameter.name)) fail('component requires an object binding parameter', declaration)
  const size = parameter.name.elements.find(element => ts.isIdentifier(element.name) && element.name.text === 'size')
  if (!size?.initializer || !ts.isNumericLiteral(size.initializer)) fail('component size must have a numeric default', parameter)
  return size.initializer.text
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
  while (start > lowerBound && /\s/.test(sourceText[start - 1])) start -= 1
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

function hasExportModifier(node) {
  return node.modifiers?.some(modifier => modifier.kind === ts.SyntaxKind.ExportKeyword) === true
}

function fail(message, node) {
  const line = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1
  throw new Error(`${message} at ${relativePath}:${line}`)
}
