#!/usr/bin/env node
/**
 * AST-driven SVG extraction from the pinned official ui-primitives TSX sources.
 * Replaces the obsolete row-level regular expressions (`extract_official_icon.py`)
 * and the sed line-number hacks (`extract_brand_wordmark.sh`,
 * `extract_fish_logo.sh`): the component and its SVG subtree are located via
 * the TypeScript AST, so upstream reflows that shift lines can never silently
 * grab the wrong fragment.
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname, basename } from "node:path";
import ts from "typescript";

const DEFAULT_FILL = "#0F1115";

function argument(name: string): string {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
}

const sourcePath = resolve(argument("--source"));
const component = argument("--component");
const outputPath = resolve(argument("--output"));
const fill = process.argv.indexOf("--fill") >= 0 ? argument("--fill") : DEFAULT_FILL;
const verbatim = process.argv.includes("--verbatim");

function fail(message: string): never {
  throw new Error(`${message} (component ${component} in ${basename(sourcePath)})`);
}

/** Find `export const <component> = (…) => (…JSX…)` and return its JSX element. */
function locateComponent(sourceText: string): { jsx: ts.JsxElement; size: string | null } {
  const sourceFile = ts.createSourceFile(sourcePath, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  let found: { jsx: ts.JsxElement; size: string | null } | null = null;
  ts.forEachChild(sourceFile, (node) => {
    if (found || !ts.isVariableStatement(node)) return;
    const exported = node.modifiers?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword) ?? false;
    if (!exported) return;
    for (const declaration of node.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || declaration.name.text !== component) continue;
      const initializer = declaration.initializer;
      if (!initializer || !ts.isArrowFunction(initializer)) continue;
      let size: string | null = null;
      const parameter = initializer.parameters[0];
      if (parameter && ts.isObjectBindingPattern(parameter.name)) {
        for (const element of parameter.name.elements) {
          if (!ts.isBindingElement(element) || !ts.isIdentifier(element.name)) continue;
          if (element.name.text !== "size") continue;
          if (element.initializer && ts.isNumericLiteral(element.initializer)) {
            size = element.initializer.text;
          }
        }
      }
      const body = initializer.body;
      if (ts.isParenthesizedExpression(body) && ts.isJsxElement(body.expression)) {
        found = { jsx: body.expression, size };
        return;
      }
      if (ts.isJsxElement(body)) {
        found = { jsx: body, size };
        return;
      }
    }
  });
  return found ?? fail(`component not found`);
}

/** Render an attribute; verbatim keeps the source text except expanding `size`. */
function renderAttribute(attribute: ts.JsxAttribute, size: string | null, sourceText: string, verbatim: boolean): string | null {
  const name = attribute.name.text;
  if (attribute.initializer === undefined) return name;
  const valueNode = attribute.initializer;
  if (ts.isStringLiteral(valueNode)) {
    const value = valueNode.text;
    const kebabName = name.replace(/^fillRule$/, "fill-rule").replace(/^clipRule$/, "clip-rule").replace(/^clipPath$/, "clip-path");
    if (kebabName === "fill" && value === "currentColor") return `fill="${fill}"`;
    return `${kebabName}="${value}"`;
  }
  if (ts.isJsxExpression(valueNode)) {
    const expression = valueNode.expression;
    if (!expression) return `{${sourceText.slice(valueNode.getStart(), valueNode.end)}}`;
    if (verbatim) {
      // Brand/wordmark sources spell width={size}; expand only the sized
      // dimension with the component default and keep everything else intact.
      if (ts.isIdentifier(expression) && expression.text === "size" && size !== null) {
        return `${name}="${size}"`;
      }
      return `${name}={${sourceText.slice(valueNode.getStart(), valueNode.end)}}`;
    }
    if (ts.isIdentifier(expression)) {
      if (expression.text === "size" && size !== null && (name === "width" || name === "height")) {
        return `${name}="${size}"`;
      }
      if (expression.text === "className") return null; // dropped, like the old extractor
      return `{${expression.text}}`;
    }
    if (ts.isNumericLiteral(expression)) return `${name}="${expression.text}"`;
    return `{${sourceText.slice(valueNode.getStart(), valueNode.end)}}`;
  }
  return `{${sourceText.slice(valueNode.getStart(), valueNode.end)}}`;
}

/** Re-render a JSX element subtree as plain SVG text. */
function renderElement(element: ts.JsxElement, size: string | null, sourceText: string, verbatim: boolean): string {
  const opening = element.openingElement;
  const attributes = opening.attributes.properties
    .map((attribute) => (ts.isJsxAttribute(attribute) ? renderAttribute(attribute, size, sourceText, verbatim) : null))
    .filter((attribute): attribute is string => attribute !== null);
  const openText = `<${opening.tagName.getText()}${attributes.length > 0 ? " " + attributes.join(" ") : ""}>`;
  const children = element.children
    .map((child) => {
      if (ts.isJsxText(child)) return sourceText.slice(child.getStart(), child.end);
      if (ts.isJsxElement(child)) return renderElement(child, size, sourceText, verbatim);
      if (ts.isJsxSelfClosingElement(child)) return renderSelfClosing(child, size, sourceText, verbatim);
      if (ts.isJsxExpression(child)) return sourceText.slice(child.getStart(), child.end);
      return "";
    })
    .join("");
  const closing = ts.isJsxClosingElement(element.closingElement) ? `</${element.closingElement.tagName.getText()}>` : "";
  return openText + children + closing;
}

function renderSelfClosing(element: ts.JsxSelfClosingElement, size: string | null, sourceText: string, verbatim: boolean): string {
  const attributes = element.attributes.properties
    .map((attribute) => (ts.isJsxAttribute(attribute) ? renderAttribute(attribute, size, sourceText, verbatim) : null))
    .filter((attribute): attribute is string => attribute !== null);
  return `<${element.tagName.getText()}${attributes.length > 0 ? " " + attributes.join(" ") : ""}/>`;
}

function main(): void {
  const sourceText = readFileSync(sourcePath, "utf8");
  const { jsx, size } = locateComponent(sourceText);
  const rendered = renderElement(jsx, size, sourceText, verbatim);
  mkdirSync(dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, rendered + "\n");
  console.log(`Extracted ${component} → ${basename(outputPath)} (${verbatim ? "verbatim" : `fill=${fill}`}).`);
}

main();