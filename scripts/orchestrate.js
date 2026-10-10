#!/usr/bin/env node
// scripts/orchestrate.js
//
// Orchestrateur unique cross-plateforme StreetPhare.
// Remplace les scripts dispersés .sh / .bat / .ps1.
//
// Usage :
//   node scripts/orchestrate.js [commande]
//
// Commandes :
//   analyze   : dart analyze
//   format    : dart format --output=none --set-exit-if-changed .
//   test      : flutter test
//   lint      : dart analyze + dart format
//   ci        : lint + flutter test (équivalent CI complet)
//   (vide)    : ci (par défaut)

"use strict";

const { spawnSync } = require("child_process");
const os = require("os");

// ── Détection OS ──────────────────────────────────────────────────────────
const isWindows = os.platform() === "win32";
let VERBOSE = false;

function shell(cmd, args, opts) {
  const fullCmd = isWindows ? `${cmd}.bat` : cmd;
  if (VERBOSE) {
    console.error(`\n▶ ${fullCmd} ${args.join(" ")}\n`);
  }
  const result = spawnSync(fullCmd, args, {
    stdio: "inherit",
    shell: isWindows,
    ...opts,
  });
  // spawnSync renvoie `result.error` si le binaire est introuvable
  // (ex: dart/flutter absents du PATH) : on le fait remonter explicitement.
  if (result.error) {
    console.error(`❌ Impossible de lancer « ${fullCmd} » : ${result.error.message}`);
    return 1;
  }
  if (result.status !== 0) {
    console.error(`❌ « ${fullCmd} » a échoué avec le code ${result.status}.`);
    return result.status;
  }
  return 0;
}

// ── Commandes ─────────────────────────────────────────────────────────────

function runAnalyze() {
  console.log("┌──────────────────────────────────────────┐");
  console.log("│  dart analyze                             │");
  console.log("└──────────────────────────────────────────┘");
  return shell("dart", ["analyze"]);
}

function runFormat() {
  console.log("┌──────────────────────────────────────────┐");
  console.log("│  dart format                              │");
  console.log("└──────────────────────────────────────────┘");
  return shell("dart", [
    "format",
    "--output=none",
    "--set-exit-if-changed",
    ".",
  ]);
}

function runTest() {
  console.log("┌──────────────────────────────────────────┐");
  console.log("│  flutter test                             │");
  console.log("└──────────────────────────────────────────┘");
  return shell("flutter", ["test"]);
}

// ── Dispatch ──────────────────────────────────────────────────────────────

// Le premier argument non-flag est la commande ; --verbose active le mode verbeux.
VERBOSE = process.argv.includes("--verbose");
const commandArgs = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const command = (commandArgs[0] || "ci").toLowerCase();
let exitCode = 0;

switch (command) {
  case "analyze":
    exitCode = runAnalyze();
    break;
  case "format":
    exitCode = runFormat();
    break;
  case "test":
    exitCode = runTest();
    break;
  case "lint":
    exitCode = runFormat() || runAnalyze();
    break;
  case "ci":
    exitCode = runFormat() || runAnalyze() || runTest();
    break;
  default:
    console.error(`Commande inconnue : ${command}`);
    console.error(
      "Commandes disponibles : analyze, format, test, lint, ci (options : --verbose)",
    );
    exitCode = 1;
}

// Ne jamais sortir avec un code indéfini/null (masquerait l'échec).
process.exit(exitCode == null ? 1 : exitCode);
