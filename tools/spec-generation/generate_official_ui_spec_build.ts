#!/usr/bin/env node
/**
 * Generate deterministic OfficialUISpec build metadata from the locked upstream
 * tree. The Swift scaffold is emitted from a TS template literal, which is
 * lexically immune to the `{{ }}`/`\\(` escaping hazards of the previous
 * Python f-string version; no source parsing is involved beyond pinned paths.
 */

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync, readdirSync } from "node:fs";
import { resolve, relative, dirname, join } from "node:path";

const GENERATOR_NAME = "generate_official_ui_spec_build.py";
const GENERATOR_VERSION = "1.0.0";
const EXPECTED_COMMIT = "a66e4702047846cdaa10c66c9d3df3951f5ea70d";
const HOST_BUILD_ID = "dsh-0.1.2-rc.1-official-a66e470";
const UI_SPEC_REVISION = "official-a66e470-ui-spec-r1";

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

function globExpression(pattern: string): RegExp {
  // This generator needs only deterministic path globs, but they must match
  // against paths relative to the official root. In particular `**/` permits
  // zero directories while `*` never crosses a path separator.
  let expression = "^";
  for (let index = 0; index < pattern.length;) {
    if (pattern.startsWith("**/", index)) {
      expression += "(?:.*/)?";
      index += 3;
    } else if (pattern.startsWith("**", index)) {
      expression += ".*";
      index += 2;
    } else if (pattern[index] === "*") {
      expression += "[^/]*";
      index += 1;
    } else {
      const character = pattern[index];
      expression += /[|\\{}()[\]^$+?.]/.test(character) ? `\\${character}` : character;
      index += 1;
    }
  }
  return new RegExp(`${expression}$`);
}

function glob(root: string, pattern: string): string[] {
  const matcher = globExpression(pattern);
  try {
    return readdirRecursive(root).filter((path) => {
      const relativePath = relative(root, path).replaceAll("\\", "/");
      return matcher.test(relativePath);
    }).sort();
  } catch {
    // Directory absent for this pattern; the caller fails on missing inputs.
    return [];
  }
}

function sourcePaths(root: string): Record<string, string[]> {
  const locale = new Set<string>([
    ...glob(root, "packages/client/**/src/client/locales.ts"),
    ...glob(root, "packages/client/**/src/client/locale.ts"),
    ...glob(root, "packages/client/locale/src/locales/*.ts"),
  ]);
  const groups: Record<string, string[]> = {
    locale: [...locale].sort(),
    token: [join(root, "packages/client/ui-theme/src/styles/design-platform.css")],
    layout: [
      join(root, "packages/client/ui-layout/src/client/columns.ts"),
      join(root, "packages/client/ui-conversation/src/client/skeleton/ConversationRoot.module.css"),
      join(root, "packages/client/ui-conversation/src/client/skeleton/InputBar.module.css"),
      join(root, "packages/client/ui-workspace/src/client/rows/WorkspaceBrowser.module.css"),
    ],
    fixture: [
      join(root, "apps/web/tests/remote-welcome.e2e.ts"),
      join(root, "apps/web/tests/support.ts"),
      join(root, "packages/client/connection/src/client/fixture.ts"),
    ],
  };
  for (const [name, paths] of Object.entries(groups)) {
    const missing = paths.filter((path) => {
      try {
        readFileSync(path);
        return false;
      } catch {
        return true;
      }
    });
    if (missing.length > 0) {
      throw new Error(`${name} source(s) missing: ${missing.join(", ")}`);
    }
  }
  return groups;
}

interface InputEntry { path: string; sha256: string; lines: number }

function digest(paths: string[], root: string): { revision: string; entries: InputEntry[] } {
  const accumulator = createHash("sha256");
  const entries: InputEntry[] = paths
    .slice()
    .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
    .map((path) => {
      const contents = readFileSync(path);
      const fileHash = createHash("sha256").update(contents).digest("hex");
      const relativePath = relative(root, path).replaceAll("\\", "/");
      accumulator.update(relativePath);
      accumulator.update("\0");
      accumulator.update(contents);
      return { path: relativePath, sha256: fileHash, lines: contents.toString("utf8").split("\n").length };
    });
  return { revision: accumulator.digest("hex"), entries };
}

function main(): void {
  const root = resolve(argument("--official-root"));
  const jsonOutput = resolve(argument("--json-output"));
  const swiftOutput = resolve(argument("--swift-output"));
  const commit = git(root, "rev-parse", "HEAD");
  if (commit !== EXPECTED_COMMIT) throw new Error(`official root must be ${EXPECTED_COMMIT}, got ${commit}`);
  const commitTime = git(root, "show", "-s", "--format=%cI", commit);

  const groups = sourcePaths(root);
  const revisions: Record<string, string> = {};
  const inputs: Array<InputEntry & { kind: string }> = [];
  for (const [group, paths] of Object.entries(groups)) {
    const { revision, entries } = digest(paths, root);
    revisions[`${group}Revision`] = `sha256:${revision}`;
    for (const entry of entries) inputs.push({ ...entry, kind: group });
  }
  inputs.sort((a, b) => (a.kind === b.kind ? (a.path < b.path ? -1 : a.path > b.path ? 1 : 0) : a.kind < b.kind ? -1 : 1));

  const metadata = {
    schemaVersion: 1,
    sourceCommit: commit,
    hostBuildId: HOST_BUILD_ID,
    uiSpecRevision: UI_SPEC_REVISION,
    ...revisions,
    generatedAt: commitTime,
    generator: { name: GENERATOR_NAME, version: GENERATOR_VERSION },
    inputs,
  };

  mkdirSync(dirname(jsonOutput), { recursive: true });
  writeFileSync(jsonOutput, `${JSON.stringify(metadata, null, 2)}\n`);

  // TS template literal: `{{` would be an error-prone Python f-string artifact,
  // not something that exists here; Swift's `\(` and `{` pass through verbatim.
  const swift = `// Generated by ${GENERATOR_NAME} ${GENERATOR_VERSION}; do not edit.
import Foundation

extension OfficialUISpec {
    enum Build {
        static let id = "${HOST_BUILD_ID}"
        static let sourceCommit = "${commit}"
        static let uiSpecRevision = "${UI_SPEC_REVISION}"
        static let localeRevision = "${metadata.localeRevision}"
        static let tokenRevision = "${metadata.tokenRevision}"
        static let layoutRevision = "${metadata.layoutRevision}"
        static let fixtureRevision = "${metadata.fixtureRevision}"
        static let generatedAt = "${commitTime}"
        static let generatorVersion = "${GENERATOR_VERSION}"

        static func isCompatible(with hostBuildID: String) -> Bool {
            hostBuildID == id
        }

        static func requireCompatibility(with hostBuildID: String) {
            precondition(isCompatible(with: hostBuildID), "Official UI spec build \\(id) is incompatible with Host build \\(hostBuildID)")
        }
    }
}
`;
  if (swift.includes("`")) {
    throw new Error("generated Swift unexpectedly contains a backtick");
  }
  mkdirSync(dirname(swiftOutput), { recursive: true });
  writeFileSync(swiftOutput, swift);
  console.log(`Generated OfficialUISpec metadata for ${commit}: ${inputs.length} upstream inputs.`);
}

main();
