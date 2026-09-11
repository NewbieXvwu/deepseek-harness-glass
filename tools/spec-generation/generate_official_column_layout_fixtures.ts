#!/usr/bin/env node
/** Generate executable three-column solver fixtures by invoking upstream code. */

import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const SOURCE_PATH = "packages/client/ui-layout/src/client/columns.ts";

interface Columns { sidebar: number; center: number; details: number }
interface ColumnModule {
  computeColumns(viewport: number, sidebar: number, details: number): Columns;
}

function argument(name: string): string {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
}

function fixtureInputs(): Array<{ name: string; viewport: number; sidebarPreference: number; detailsPreference: number }> {
  const exact = [
    ["default-preferred-fits", 1280, 280, 360],
    ["default-preferred-one-pixel-short", 1279, 280, 360],
    ["default-details-minimum-boundary", 1220, 280, 360],
    ["default-details-auto-closes-below-minimum", 1219, 280, 360],
    ["default-details-reopens-on-widen", 1221, 280, 360],
    ["collapsed-sidebar-preferred-fits", 1056, 0, 360],
    ["collapsed-sidebar-compact-rail", 1023, 0, 360],
    ["collapsed-sidebar-details-minimum-boundary", 996, 0, 360],
    ["collapsed-sidebar-details-auto-closes-below-minimum", 995, 0, 360],
    ["deliverables-capture-compact-rail", 780, 0, 360],
    ["details-closed-center-absorbs", 900, 280, 0],
    ["details-closed-narrow-center-floor-fallback", 200, 280, 0],
    ["sidebar-min-preferred-boundary", 1264, 264, 360],
    ["sidebar-min-details-minimum-boundary", 1204, 264, 360],
    ["sidebar-max-preferred-boundary", 1420, 420, 360],
    ["sidebar-max-details-minimum-boundary", 1360, 420, 360],
    ["details-min-preferred-boundary", 1220, 280, 300],
    ["details-max-preferred-boundary", 1440, 280, 520],
    ["sidebar-negative-preference-clamps", 1280, -100, 360],
    ["sidebar-low-fraction-rounds-then-clamps", 1280, 263.49, 360],
    ["sidebar-half-rounds-up", 1280, 264.5, 360],
    ["sidebar-high-fraction-rounds-then-clamps", 1440, 420.49, 360],
    ["sidebar-too-wide-clamps", 1440, 999, 360],
    ["details-negative-preference-clamps", 1280, 280, -100],
    ["details-low-fraction-rounds-then-clamps", 1280, 280, 299.49],
    ["details-half-rounds-up", 1280, 280, 300.5],
    ["details-high-fraction-rounds-then-clamps", 1440, 280, 520.49],
    ["details-too-wide-clamps", 1440, 280, 999],
    ["zero-viewport", 0, 0, 0],
    ["sub-rail-viewport", 55, 0, 0],
    ["rail-viewport", 56, 0, 0],
    ["fractional-viewport", 1220.5, 280, 360],
  ] as const;
  return exact.map(([name, viewport, sidebarPreference, detailsPreference]) => ({ name, viewport, sidebarPreference, detailsPreference }));
}

async function main(): Promise<void> {
  const officialRoot = resolve(argument("--official-root"));
  const output = resolve(argument("--output"));
  const module = await import(pathToFileURL(resolve(officialRoot, SOURCE_PATH)).href) as ColumnModule;
  const fixtures = fixtureInputs().map((input) => ({
    ...input,
    expected: module.computeColumns(input.viewport, input.sidebarPreference, input.detailsPreference),
  }));
  mkdirSync(resolve(output, ".."), { recursive: true });
  writeFileSync(output, `${JSON.stringify({ schemaVersion: 1, fixtures }, null, 2)}\n`);
  console.log(`Generated ${fixtures.length} official computeColumns fixtures.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
