#!/usr/bin/env node
import { createRequire } from 'node:module'
import { readFileSync } from 'node:fs'
import { resolve, dirname, relative, extname } from 'node:path'

const [officialRootArgument, sourceArgument] = process.argv.slice(2)
if (!officialRootArgument || !sourceArgument) {
  throw new Error('usage: extract_official_locales_ast.mjs <official-root> <source-file>')
}

const officialRoot = resolve(officialRootArgument)
const sourcePath = resolve(sourceArgument)
const requireFromOfficial = createRequire(resolve(officialRoot, 'package.json'))
const ts = requireFromOfficial('typescript')
const sourceText = readFileSync(sourcePath, 'utf8')
const sourceFile = ts.createSourceFile(sourcePath, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)
const relativePath = relative(officialRoot, sourcePath).replaceAll('\\', '/')
const namespace = namespaceFor(relativePath)
const constants = new Map()

for (const statement of sourceFile.statements) {
  if (!ts.isVariableStatement(statement)) continue
  for (const declaration of statement.declarationList.declarations) {
    if (!ts.isIdentifier(declaration.name) || !declaration.initializer) continue
    try {
      constants.set(declaration.name.text, evaluate(declaration.initializer, constants, sourceFile))
    } catch {
      // Non-locale helper declarations remain intentionally unavailable. Any
      // locale property that depends on one later fails loudly in evaluate().
    }
  }
}

for (const statement of sourceFile.statements) {
  if (!ts.isImportDeclaration(statement) || !statement.importClause?.namedBindings || !ts.isNamedImports(statement.importClause.namedBindings)) continue
  const importedNames = statement.importClause.namedBindings.elements
    .filter(specifier => specifier.name.text === 'WELCOME_NOTICE_COPY')
  if (importedNames.length === 0 || !ts.isStringLiteral(statement.moduleSpecifier)) continue
  const importedPath = resolveImport(sourcePath, statement.moduleSpecifier.text)
  constants.set('WELCOME_NOTICE_COPY', exportedConstant(importedPath, 'WELCOME_NOTICE_COPY'))
}

const entries = []
for (const statement of sourceFile.statements) {
  if (!ts.isVariableStatement(statement) || !hasExportModifier(statement)) continue
  for (const declaration of statement.declarationList.declarations) {
    if (!ts.isIdentifier(declaration.name) || !['en', 'zh'].includes(declaration.name.text) || !declaration.initializer) continue
    const localeObject = unwrapObjectLiteral(declaration.initializer)
    if (!localeObject) {
      throw new Error(`locale export ${declaration.name.text} must be an object at ${relativePath}:${lineOf(sourceFile, declaration)}`)
    }
    const language = declaration.name.text
    const exportStartedAtLine = lineOf(sourceFile, declaration)
    for (const property of localeObject.properties) {
      if (!ts.isPropertyAssignment(property)) {
        throw new Error(`unsupported locale property form at ${relativePath}:${lineOf(sourceFile, property)}`)
      }
      const key = propertyName(property.name, sourceFile)
      const value = evaluate(property.initializer, constants, sourceFile)
      if (typeof value !== 'string') {
        throw new Error(`locale ${language}.${key} is not a string at ${relativePath}:${lineOf(sourceFile, property)}`)
      }
      entries.push({
        id: `${namespace}.${key}`,
        namespace,
        key,
        language,
        value,
        interpolationParameters: [...new Set([...value.matchAll(/\{([A-Za-z_][A-Za-z0-9_]*)\}/g)].map(match => match[1]))].sort(),
        pluralCategory: pluralCategory(key),
        source: { path: relativePath, line: lineOf(sourceFile, property), commit: '__COMMIT__' },
        exportStartedAtLine,
      })
    }
  }
}
// Locale source discovery also includes re-export-only index modules. They
// contribute no catalog entries but remain provenance inputs in the Python
// generator, matching its established behavior.
process.stdout.write(JSON.stringify(entries))

function namespaceFor(path) {
  const match = path.match(/^packages\/client\/([^/]+)\/src\/client\/(?:locales|locale)\.ts$/)
  if (match) return match[1]
  if (path.startsWith('packages/client/locale/src/locales/')) return 'locale'
  throw new Error(`unrecognized locale path: ${path}`)
}

function unwrapObjectLiteral(node) {
  while (ts.isSatisfiesExpression(node) || ts.isAsExpression(node) || ts.isTypeAssertionExpression(node) || ts.isParenthesizedExpression(node)) {
    node = node.expression
  }
  return ts.isObjectLiteralExpression(node) ? node : null
}

function hasExportModifier(node) {
  return node.modifiers?.some(modifier => modifier.kind === ts.SyntaxKind.ExportKeyword) === true
}

function resolveImport(from, specifier) {
  const base = resolve(dirname(from), specifier)
  const candidates = extname(base) ? [base] : [`${base}.ts`, `${base}.tsx`, resolve(base, 'index.ts')]
  const candidate = candidates.find(path => {
    try { readFileSync(path); return true } catch { return false }
  })
  if (!candidate) throw new Error(`cannot resolve imported locale constant ${specifier} from ${from}`)
  return candidate
}

function exportedConstant(path, name) {
  const text = readFileSync(path, 'utf8')
  const file = ts.createSourceFile(path, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)
  const env = new Map()
  for (const statement of file.statements) {
    if (!ts.isVariableStatement(statement)) continue
    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || !declaration.initializer) continue
      const value = evaluate(declaration.initializer, env, file)
      env.set(declaration.name.text, value)
      if (declaration.name.text === name) return value
    }
  }
  throw new Error(`missing exported constant ${name} in ${path}`)
}

function evaluate(node, env, file) {
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text
  if (ts.isTemplateExpression(node)) {
    throw new Error(`template interpolation is unsupported at ${file.fileName}:${lineOf(file, node)}`)
  }
  if (ts.isParenthesizedExpression(node) || ts.isSatisfiesExpression(node) || ts.isAsExpression(node) || ts.isTypeAssertionExpression(node)) {
    return evaluate(node.expression, env, file)
  }
  if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.PlusToken) {
    const left = evaluate(node.left, env, file)
    const right = evaluate(node.right, env, file)
    if (typeof left !== 'string' || typeof right !== 'string') throw new Error(`string concatenation expected at ${file.fileName}:${lineOf(file, node)}`)
    return left + right
  }
  if (ts.isIdentifier(node)) {
    if (!env.has(node.text)) throw new Error(`unresolved identifier ${node.text} at ${file.fileName}:${lineOf(file, node)}`)
    return env.get(node.text)
  }
  if (ts.isPropertyAccessExpression(node)) {
    const target = evaluate(node.expression, env, file)
    if (!target || typeof target !== 'object' || !(node.name.text in target)) {
      throw new Error(`unresolved property ${node.getText(file)} at ${file.fileName}:${lineOf(file, node)}`)
    }
    return target[node.name.text]
  }
  if (ts.isObjectLiteralExpression(node)) {
    const object = {}
    for (const property of node.properties) {
      if (!ts.isPropertyAssignment(property)) throw new Error(`unsupported object property at ${file.fileName}:${lineOf(file, property)}`)
      object[propertyName(property.name, file)] = evaluate(property.initializer, env, file)
    }
    return object
  }
  throw new Error(`unsupported locale expression ${ts.SyntaxKind[node.kind]} at ${file.fileName}:${lineOf(file, node)}`)
}

function propertyName(name, file) {
  if (ts.isIdentifier(name) || ts.isStringLiteral(name) || ts.isNumericLiteral(name)) return name.text
  throw new Error(`unsupported property name ${name.getText(file)} at ${file.fileName}:${lineOf(file, name)}`)
}

function lineOf(file, node) {
  return file.getLineAndCharacterOfPosition(node.getStart(file)).line + 1
}

function pluralCategory(key) {
  const value = key.split('.').at(-1)
  return ['zero', 'one', 'two', 'few', 'many', 'other'].includes(value) ? value : null
}
