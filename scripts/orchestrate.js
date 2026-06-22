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
//   start     : lance les serveurs Node.js (primary + secondary + dashboard)
//   all       : ci + start
//   (vide)    : ci (par défaut)

'use strict';

const { spawnSync } = require('child_process');
const os = require('os');

// ── Détection OS ──────────────────────────────────────────────────────────
const isWindows = os.platform() === 'win32';

function shell(cmd, args, opts) {
  const fullCmd = isWindows ? `${cmd}.bat` : cmd;
  const result = spawnSync(fullCmd, args, {
    stdio: 'inherit',
    shell: isWindows,
    ...opts,
  });
  return result.status;
}

function node(script, args) {
  const scriptPath = `server/${script}`;
  const result = spawnSync('node', [scriptPath, ...(args || [])], {
    stdio: 'inherit',
    shell: isWindows,
  });
  return result.status;
}

// ── Commandes ─────────────────────────────────────────────────────────────

function runAnalyze() {
  console.log('┌──────────────────────────────────────────┐');
  console.log('│  dart analyze                             │');
  console.log('└──────────────────────────────────────────┘');
  return shell('dart', ['analyze']);
}

function runFormat() {
  console.log('┌──────────────────────────────────────────┐');
  console.log('│  dart format                              │');
  console.log('└──────────────────────────────────────────┘');
  return shell('dart', ['format', '--output=none', '--set-exit-if-changed', '.']);
}

function runTest() {
  console.log('┌──────────────────────────────────────────┐');
  console.log('│  flutter test                             │');
  console.log('└──────────────────────────────────────────┘');
  return shell('flutter', ['test']);
}

function runStart() {
  console.log('┌──────────────────────────────────────────┐');
  console.log('│  Démarrage des serveurs Node.js           │');
  console.log('│    Primary  → http://localhost:3000       │');
  console.log('│    Secondary → http://localhost:3001      │');
  console.log('│    Dashboard → http://localhost:3500      │');
  console.log('└──────────────────────────────────────────┘');
  return node('launch_all.js');
}

// ── Dispatch ──────────────────────────────────────────────────────────────

const command = (process.argv[2] || 'ci').toLowerCase();
let exitCode = 0;

switch (command) {
  case 'analyze':
    exitCode = runAnalyze();
    break;
  case 'format':
    exitCode = runFormat();
    break;
  case 'test':
    exitCode = runTest();
    break;
  case 'lint':
    exitCode = runFormat() || runAnalyze();
    break;
  case 'ci':
    exitCode = runFormat() || runAnalyze() || runTest();
    break;
  case 'start':
    exitCode = runStart();
    break;
  case 'all':
    exitCode = runFormat() || runAnalyze() || runTest() || runStart();
    break;
  default:
    console.error(`Commande inconnue : ${command}`);
    console.error('Commandes disponibles : analyze, format, test, lint, ci, start, all');
    exitCode = 1;
}

process.exit(exitCode || 0);