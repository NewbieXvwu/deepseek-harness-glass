#!/usr/bin/env node
/** Extract the English/Chinese locale catalog from a supplied Harness source tree. */

import { mkdirSync, readFileSync, writeFileSync, readdirSync } from "node:fs";
import { resolve, relative, dirname, join } from "node:path";
import ts from "typescript";

function argument(name: string): string {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
}

function readdirRecursive(directory: string): string[] {
  const result: string[] = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const full = join(directory, entry.name);
    result.push(...(entry.isDirectory() ? readdirRecursive(full) : [full]));
  }
  return result;
}

interface LocaleFile {
  path: string;
  namespace: string;
}

function localeFiles(root: string): LocaleFile[] {
  const candidates: string[] = [];
  const packagesBase = join(root, "packages", "client");
  for (const entry of readdirSync(packagesBase, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const packageRoot = join(packagesBase, entry.name);
    for (const path of readdirRecursive(packageRoot)) {
      const relativePath = relative(root, path).replaceAll("\\", "/");
      if (/(?:^|\/)src\/client\/locales\.ts$/.test(relativePath)
        || /(?:^|\/)src\/client\/locale\.ts$/.test(relativePath)
        || (entry.name === "locale" && /(?:^|\/)src\/locales\/[^/]+\.ts$/.test(relativePath))) {
        candidates.push(path);
      }
    }
  }
  if (candidates.length === 0) throw new Error(`no locale source files found under ${root}`);
  return candidates.sort().map((path) => {
    const relativePath = relative(root, path).replaceAll("\\", "/");
    const match = /^packages\/client\/([^/]+)\/src\/client\/(?:locales|locale)\.ts$/.exec(relativePath);
    if (match) return { path, namespace: match[1] };
    if (relativePath.startsWith("packages/client/locale/src/locales/")) return { path, namespace: "locale" };
    throw new Error(`unrecognized locale path: ${relativePath}`);
  });
}

interface LocaleEntry {
  id: string;
  namespace: string;
  key: string;
  language: string;
  value: string;
  interpolationParameters: string[];
  pluralCategory: string | null;
}

function pluralCategory(key: string): string | null {
  const finalPart = key.split(".").pop() ?? "";
  return ["zero", "one", "two", "few", "many", "other"].includes(finalPart) ? finalPart : null;
}

function interpolationParameters(value: string): string[] {
  const parameters = new Set<string>();
  const pattern = /\{([A-Za-z_][A-Za-z0-9_]*)\}/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(value)) !== null) parameters.add(match[1]);
  return [...parameters].sort();
}

function propertyAccessKey(node: ts.Expression): string | undefined {
  if (ts.isIdentifier(node)) return node.text;
  if (!ts.isPropertyAccessExpression(node)) return undefined;
  const base = propertyAccessKey(node.expression);
  return base === undefined ? undefined : `${base}.${node.name.text}`;
}

function evalString(
  node: ts.Node,
  constants: Map<string, string>,
  sourceText: string,
  filePath: string
): string {
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text;
  if (ts.isTemplateExpression(node)) {
    const raw = sourceText.slice(node.getStart(), node.end);
    if (!raw.startsWith("`") || !raw.endsWith("`")) throw new Error(`unexpected template literal shape in ${filePath}`);
    return raw.slice(1, -1);
  }
  if (ts.isBinaryExpression(node)) {
    if (node.operatorToken.kind !== ts.SyntaxKind.PlusToken) throw new Error(`unsupported locale operator in ${filePath}`);
    return evalString(node.left, constants, sourceText, filePath) + evalString(node.right, constants, sourceText, filePath);
  }
  if (ts.isParenthesizedExpression(node)) return evalString(node.expression, constants, sourceText, filePath);
  if (ts.isIdentifier(node)) {
    const resolved = constants.get(node.text);
    if (resolved === undefined) throw new Error(`unresolved locale string constant: ${node.text} (${filePath})`);
    return resolved;
  }
  if (ts.isPropertyAccessExpression(node)) {
    const key = propertyAccessKey(node);
    const resolved = key === undefined ? undefined : constants.get(key);
    if (resolved === undefined) throw new Error(`unresolved locale property access: ${node.getText()} (${filePath})`);
    return resolved;
  }
  throw new Error(`unsupported locale value at ${filePath}: ${ts.SyntaxKind[node.kind]}`);
}

function propertyKey(property: ts.PropertyAssignment): string | null {
  const name = property.name;
  return ts.isIdentifier(name) || ts.isStringLiteral(name) ? name.text : null;
}

function unwrappedObjectLiteral(expression: ts.Expression | undefined): ts.ObjectLiteralExpression | undefined {
  let current = expression;
  while (current !== undefined && (
    ts.isAsExpression(current)
    || ts.isSatisfiesExpression(current)
    || ts.isTypeAssertionExpression(current)
    || ts.isParenthesizedExpression(current)
  )) current = current.expression;
  return current !== undefined && ts.isObjectLiteralExpression(current) ? current : undefined;
}

function parseFile(file: LocaleFile): LocaleEntry[] {
  const sourceText = readFileSync(file.path, "utf8");
  const sourceFile = ts.createSourceFile(file.path, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const constants = new Map<string, string>();
  const entries: LocaleEntry[] = [];
  const lineOf = (node: ts.Node) => sourceFile.getLineAndCharacterOfPosition(node.getStart()).line + 1;

  ts.forEachChild(sourceFile, (node) => {
    if (!ts.isVariableStatement(node)) return;
    if (node.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword)) return;
    for (const declaration of node.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || !declaration.initializer) continue;
      try {
        constants.set(declaration.name.text, evalString(declaration.initializer, constants, sourceText, file.path));
      } catch {
        // Runtime-valued helpers are not locale constants. A locale entry that
        // references one still fails below when its value cannot be resolved.
      }
    }
  });

  ts.forEachChild(sourceFile, (node) => {
    if (!ts.isVariableStatement(node)) return;
    if (!node.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword)) return;
    for (const declaration of node.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name)) continue;
      const language = declaration.name.text;
      if (language !== "en" && language !== "zh") continue;
      const dictionary = unwrappedObjectLiteral(declaration.initializer);
      if (dictionary === undefined) continue;
      for (const property of dictionary.properties) {
        if (!ts.isPropertyAssignment(property)) {
          throw new Error(`unsupported locale property at ${file.path}:${lineOf(property)}`);
        }
        const key = propertyKey(property);
        if (!key) throw new Error(`unsupported locale property key at ${file.path}:${lineOf(property)}`);
        const value = evalString(property.initializer, constants, sourceText, file.path);
        entries.push({
          id: `${file.namespace}.${key}`,
          namespace: file.namespace,
          key,
          language,
          value,
          interpolationParameters: interpolationParameters(value),
          pluralCategory: pluralCategory(key),
        });
      }
    }
  });
  return entries;
}

function main(): void {
  const root = resolve(argument("--official-root"));
  const output = resolve(argument("--json-output"));
  const entries = localeFiles(root).flatMap(parseFile);
  if (entries.length === 0) throw new Error("no locale entries found");

  const compare = (left: string, right: string): number => left < right ? -1 : left > right ? 1 : 0;
  entries.sort((a, b) => compare(a.namespace, b.namespace) || compare(a.key, b.key) || compare(a.language, b.language));

  const unique = new Set(entries.map((entry) => `${entry.id}\u0000${entry.language}`));
  if (unique.size !== entries.length) throw new Error("duplicate namespace/key/language locale entry");

  const byKey = new Map<string, Set<string>>();
  for (const entry of entries) {
    if (!byKey.has(entry.id)) byKey.set(entry.id, new Set());
    byKey.get(entry.id)!.add(entry.language);
  }
  const incomplete = [...byKey.entries()]
    .filter(([, languages]) => !["en", "zh"].every((language) => languages.has(language)))
    .map(([key]) => key)
    .sort();
  if (incomplete.length > 0) throw new Error("locale keys missing en/zh translation: " + incomplete.slice(0, 20).join(", "));

  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, `${JSON.stringify({ schemaVersion: 1, languages: ["en", "zh"], entries }, null, 2)}\n`);
  console.log(`Generated ${entries.length} locale entries across ${byKey.size} keys from AST.`);
}

main();
