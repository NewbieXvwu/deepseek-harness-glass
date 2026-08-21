#!/usr/bin/env node
/**
 * Generate the provenance-preserving English/Chinese locale catalog from the
 * locked upstream TypeScript using the TypeScript compiler API — no line-level
 * regular expressions, no statement-boundary heuristics.
 *
 * The extracted JSON keeps the exact schema of the previous generator so gates
 * and Swift consumers are unchanged, but every key/value/line fact now comes
 * from an AST node (PropertyAssignment/VariableDeclaration/StringLiteral).
 */

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync, readdirSync } from "node:fs";
import { resolve, relative, dirname, join, basename } from "node:path";
import ts from "typescript";

const GENERATOR_NAME = "generate_official_locales.py";
const GENERATOR_VERSION = "1.0.0";
const EXPECTED_COMMIT = "528c682e061696f5a160f363f236ecbf53cbd006";
const ONBOARDING_COPY_RELATIVE = "packages/client/ui-settings-models/src/onboarding-copy.ts";

function argument(name: string): string {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
}

function git(root: string, ...args: string[]): string {
  return execFileSync("git", ["-C", root, ...args], { encoding: "utf8" }).trim();
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
  root: string;
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
      // mirrors the locked upstream globs: **/src/client/locales.ts,
      // **/src/client/locale.ts, and locale/src/locales/*.ts
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
    let namespace: string;
    if (match) {
      namespace = match[1];
    } else if (relativePath.startsWith("packages/client/locale/src/locales/")) {
      namespace = "locale";
    } else {
      throw new Error(`unrecognized locale path: ${relativePath}`);
    }
    return { root, path, namespace };
  });
}

function sourceInputRevision(root: string, paths: string[]): string {
  const accumulator = createHash("sha256");
  for (const path of paths) {
    accumulator.update(relative(root, path).replaceAll("\\", "/"));
    accumulator.update("\0");
    accumulator.update(readFileSync(path));
  }
  return "sha256:" + accumulator.digest("hex");
}

interface LocaleEntry {
  id: string;
  namespace: string;
  key: string;
  language: string;
  value: string;
  interpolationParameters: string[];
  pluralCategory: string | null;
  source: { path: string; line: number; commit: string };
  exportStartedAtLine: number;
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

/** Evaluate a locale value node to its static string against known constants. */
function evalString(
  node: ts.Node,
  constants: Map<string, string>,
  sourceText: string,
  filePath: string
): string {
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) {
    return node.text;
  }
  if (ts.isTemplateExpression(node)) {
    // Preserve the raw template verbatim (including ${...} placeholders) like
    // the previous generator kept the original back-ticked source.
    const raw = sourceText.slice(node.getStart(), node.end);
    if (!raw.startsWith("`") || !raw.endsWith("`")) {
      throw new Error(`unexpected template literal shape in ${filePath}`);
    }
    return raw.slice(1, -1);
  }
  if (ts.isBinaryExpression(node)) {
    if (node.operatorToken.kind !== ts.SyntaxKind.PlusToken) {
      throw new Error(`unsupported locale operator in ${filePath}`);
    }
    return evalString(node.left, constants, sourceText, filePath) + evalString(node.right, constants, sourceText, filePath);
  }
  if (ts.isParenthesizedExpression(node)) {
    return evalString(node.expression, constants, sourceText, filePath);
  }
  if (ts.isIdentifier(node)) {
    const resolved = constants.get(node.text);
    if (resolved === undefined) throw new Error(`unresolved locale string constant: ${node.text} (${filePath})`);
    return resolved;
  }
  if (ts.isPropertyAccessExpression(node)) {
    const key = propertyAccessKey(node);
    const resolved = key === undefined ? undefined : constants.get(key);
    if (resolved === undefined) {
      throw new Error(`unresolved locale property access: ${node.getText()} (${filePath})`);
    }
    return resolved;
  }
  throw new Error(`unsupported locale value at ${filePath}: ${ts.SyntaxKind[node.kind]}`);
}

/** Object-literal property key as a plain string, for identifiers or literals. */
function propertyKey(property: ts.PropertyAssignment): string | null {
  const name = property.name;
  if (ts.isIdentifier(name) || ts.isStringLiteral(name)) return name.text;
  return null;
}

function unwrappedObjectLiteral(expression: ts.Expression | undefined): ts.ObjectLiteralExpression | undefined {
  var current = expression;
  while (current !== undefined && (
    ts.isAsExpression(current)
    || ts.isSatisfiesExpression(current)
    || ts.isTypeAssertionExpression(current)
    || ts.isParenthesizedExpression(current)
  )) {
    current = current.expression;
  }
  return current !== undefined && ts.isObjectLiteralExpression(current) ? current : undefined;
}

/** WELCOME_NOTICE_COPY en/zh facts from the pinned onboarding copy module. */
function onboardingCopyConstants(root: string): Map<string, string> {
  const path = join(root, ONBOARDING_COPY_RELATIVE);
  const sourceText = readFileSync(path, "utf8");
  const sourceFile = ts.createSourceFile(path, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const constants = new Map<string, string>();
  ts.forEachChild(sourceFile, (node) => {
    if (!ts.isVariableStatement(node)) return;
    for (const declaration of node.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || declaration.name.text !== "WELCOME_NOTICE_COPY") continue;
      const notice = unwrappedObjectLiteral(declaration.initializer);
      if (notice === undefined) continue;
      for (const languageProperty of notice.properties) {
        if (!ts.isPropertyAssignment(languageProperty)) continue;
        const language = propertyKey(languageProperty);
        if (language !== "en" && language !== "zh") continue;
        const languageObject = unwrappedObjectLiteral(languageProperty.initializer);
        if (languageObject === undefined) continue;
        for (const field of languageObject.properties) {
          if (!ts.isPropertyAssignment(field)) continue;
          const fieldName = propertyKey(field);
          if (!fieldName || !["title", "body", "continueLabel"].includes(fieldName)) continue;
          constants.set(
            `WELCOME_NOTICE_COPY.${language}.${fieldName}`,
            evalString(field.initializer, constants, sourceText, path)
          );
        }
      }
    }
  });
  for (const language of ["en", "zh"]) {
    for (const field of ["title", "body", "continueLabel"]) {
      if (!constants.has(`WELCOME_NOTICE_COPY.${language}.${field}`)) {
        throw new Error(`missing WELCOME_NOTICE_COPY.${language}.${field} in ${path}`);
      }
    }
  }
  return constants;
}

/** Whether a file references the onboarding copy constant at all. */
function referencesOnboardingCopy(sourceFile: ts.SourceFile): boolean {
  let referenced = false;
  ts.forEachChild(sourceFile, function visit(node) {
    if (referenced) return;
    if (ts.isIdentifier(node) && node.text === "WELCOME_NOTICE_COPY") {
      referenced = true;
      return;
    }
    ts.forEachChild(node, visit);
  });
  return referenced;
}

function parseFile(file: LocaleFile, onboardingConstants: Map<string, string>, commit: string): LocaleEntry[] {
  const sourceText = readFileSync(file.path, "utf8");
  const sourceFile = ts.createSourceFile(file.path, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const constants = new Map(onboardingConstants);
  if (!referencesOnboardingCopy(sourceFile)) {
    // Only files that import the onboarding copy may resolve it; others stay
    // module-local so an accidental reference still fails as unresolved.
    constants.clear();
  }
  const entries: LocaleEntry[] = [];
  const lineOf = (node: ts.Node) => sourceFile.getLineAndCharacterOfPosition(node.getStart()).line + 1;

  // First pass: non-exported literal constants usable by locale values.
  ts.forEachChild(sourceFile, (node) => {
    if (!ts.isVariableStatement(node)) return;
    const exported = node.modifiers?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword) ?? false;
    if (exported) return;
    for (const declaration of node.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || !declaration.initializer) continue;
      try {
        constants.set(declaration.name.text, evalString(declaration.initializer, constants, sourceText, file.path));
      } catch {
        // Conditional helpers (non-literal or runtime-valued) are deliberately
        // not locale constants; a locale entry that references one still fails
        // as unresolved below.
      }
    }
  });

  // Second pass: the exported en/zh object literal, node by node.
  ts.forEachChild(sourceFile, (node) => {
    if (!ts.isVariableStatement(node)) return;
    if (!node.modifiers?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword)) return;
    for (const declaration of node.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name)) continue;
      const name = declaration.name.text;
      if (name !== "en" && name !== "zh") continue;
      const dictionary = unwrappedObjectLiteral(declaration.initializer);
      if (dictionary === undefined) continue;
      const exportStartedAtLine = lineOf(node);
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
          language: name,
          value,
          interpolationParameters: interpolationParameters(value),
          pluralCategory: pluralCategory(key),
          source: { path: relative(file.root, file.path).replaceAll("\\", "/"), line: lineOf(property), commit },
          exportStartedAtLine,
        });
      }
    }
  });
  return entries;
}

/** Compact, sorted-key JSON serialization matching the previous gate's revision hash. */
function compactStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return typeof value === "string" ? JSON.stringify(value) : String(value);
  }
  if (Array.isArray(value)) return `[${value.map(compactStringify).join(",")}]`;
  const entries = Object.entries(value as Record<string, unknown>).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return `{${entries.map(([key, child]) => `${JSON.stringify(key)}:${compactStringify(child)}`).join(",")}}`;
}

function revision(entries: LocaleEntry[]): string {
  const serial = compactStringify(entries as unknown as Record<string, unknown>);
  return "sha256:" + createHash("sha256").update(serial).digest("hex");
}

function swiftSource(
  entries: LocaleEntry[],
  commit: string,
  localeRevision: string,
  sourceInput: string
): string {
  const values: Record<string, string> = {};
  for (const entry of entries) values[`${entry.language}|${entry.id}`] = entry.value;
  const body = Object.keys(values)
    .sort()
    .map((key) => `        ${JSON.stringify(key)}: ${JSON.stringify(values[key])}`)
    .join(",\n");
  // A TS template literal is lexically immune to the `{{ }}`/`\\(` escaping
  // hazards of the previous Python f-string scaffold: Swift's `\(` and `{`
  // are inert inside it. A stray backtick is the only accidental escape that
  // could leak through, so guard that defensively; `${` is legitimate content
  // inside serialized locale values and must not trip the check.
  const swift = `// Generated by ${GENERATOR_NAME} ${GENERATOR_VERSION}; do not edit.
import Foundation

extension OfficialUISpec {
    enum LocaleCatalog {
        static let sourceCommit = "${commit}"
        static let revision = "${localeRevision}"
        static let sourceInputRevision = "${sourceInput}"
        static let supportedLanguages: Set<String> = ["en", "zh"]
        static let values: [String: String] = [
${body}
        ]

        static func contains(namespace: String, key: String, language: String) -> Bool {
            values["\\(language)|\\(namespace).\\(key)"] != nil
        }

        static func value(namespace: String, key: String, language: String) -> String? {
            values["\\(language)|\\(namespace).\\(key)"]
        }
    }
}
`;
  if (swift.includes("`")) {
    throw new Error("generated Swift unexpectedly contains a backtick");
  }
  return swift;
}

function main(): void {
  const root = resolve(argument("--official-root"));
  const jsonOutput = resolve(argument("--json-output"));
  const swiftOutput = resolve(argument("--swift-output"));
  const commit = git(root, "rev-parse", "HEAD");
  if (commit !== EXPECTED_COMMIT) throw new Error(`official root must be ${EXPECTED_COMMIT}, got ${commit}`);

  const onboardingConstants = onboardingCopyConstants(root);
  const files = localeFiles(root);
  const entries: LocaleEntry[] = [];
  for (const file of files) entries.push(...parseFile(file, onboardingConstants, commit));
  if (entries.length === 0) throw new Error("no locale entries found");
  const compareCodePoints = (left: string, right: string): number =>
    left < right ? -1 : left > right ? 1 : 0;
  // Keep the Python generator's code-point ordering rather than locale-aware
  // collation, which changes both byte output and revision hashes by runtime.
  entries.sort((a, b) =>
    compareCodePoints(a.namespace, b.namespace)
    || compareCodePoints(a.key, b.key)
    || compareCodePoints(a.language, b.language)
  );
  const unique = new Set(entries.map((entry) => `${entry.id}\u0000${entry.language}`));
  if (unique.size !== entries.length) throw new Error("duplicate namespace/key/language locale entry");
  const languages = new Set(entries.map((entry) => entry.language));
  if (!["en", "zh"].every((language) => languages.has(language))) {
    throw new Error("generated locale catalog must contain English and Chinese");
  }
  const byKey = new Map<string, Set<string>>();
  for (const entry of entries) {
    if (!byKey.has(entry.id)) byKey.set(entry.id, new Set());
    byKey.get(entry.id)!.add(entry.language);
  }
  const incomplete = [...byKey.entries()]
    .filter(([, languageSet]) => !["en", "zh"].every((language) => languageSet.has(language)))
    .map(([key]) => key)
    .sort();
  if (incomplete.length > 0) {
    throw new Error("locale keys missing en/zh translation: " + incomplete.slice(0, 20).join(", "));
  }

  const localeRevision = revision(entries);
  const sourceInput = sourceInputRevision(
    root,
    [...files.map((file) => file.path), join(root, ONBOARDING_COPY_RELATIVE)].sort()
  );
  const metadata = {
    schemaVersion: 1,
    sourceCommit: commit,
    localeRevision,
    sourceInputRevision: sourceInput,
    generatedAt: git(root, "show", "-s", "--format=%cI", commit),
    generator: { name: GENERATOR_NAME, version: GENERATOR_VERSION },
    languages: [...languages].sort(),
    entries,
  };

  mkdirSync(dirname(jsonOutput), { recursive: true });
  writeFileSync(jsonOutput, `${JSON.stringify(metadata, null, 2)}\n`);
  mkdirSync(dirname(swiftOutput), { recursive: true });
  writeFileSync(swiftOutput, swiftSource(entries, commit, localeRevision, sourceInput));
  console.log(`Generated ${entries.length} locale entries across ${byKey.size} keys from AST.`);
}

main();