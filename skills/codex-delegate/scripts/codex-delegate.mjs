#!/usr/bin/env node
// codex-delegate.mjs — hands a task to Codex (codex exec) on the current checkout.
//
// Meant for Claude Code's Bash tool with run_in_background: true. The tool returns at once,
// the session stays free, and Claude Code wakes it when this process exits. The short summary
// printed at the end is what Claude reads.
//
// Usage:
//   node codex-delegate.mjs --slug <slug> [--repo <path>] [--model <m>] [--effort <level>]
//        [--allow-dirty] [--resume] [--prompt-file <f>] -- "task prompt"
//
// --resume continues the Codex session of the latest run of that slug in the same repo, so a
// round of fixes does not read the code from scratch again.
// --model and --effort default to the Codex config (`model`, `model_reasoning_effort`).
//
// Optional environment variables:
//   CODEX_BIN    Codex binary (default: `codex` on PATH, else the one bundled with Codex.app)
//   CODEX_FLAGS  extra flags for `codex exec` (default: "--sandbox workspace-write")
//   CODEX_HOME   Codex's data directory, where it records sessions (default: ~/.codex)

import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const USAGE =
  'Usage: codex-delegate.mjs --slug <slug> [--repo <path>] [--model <m>] [--effort <level>] ' +
  '[--allow-dirty] [--resume] [--prompt-file <f>] -- "prompt"';
const APP_CODEX = '/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex';
const MAX_SUMMARY = 1500;
const MAX_FILES = 20;

// Appended to every prompt: Codex shares the checkout with the Claude session.
const FOOTER =
  '\n\n---\nRules for this delegated task: you are working on a shared checkout. Leave committing ' +
  'and branch changes to the caller, and use stash, reset or checkout only on files you changed. ' +
  'When done, reply with a short summary: what you changed, what you verified (commands and ' +
  'results), and what is left.';

function fail(msg, code = 2) {
  console.error(msg);
  process.exit(code);
}

function parseArgs(argv) {
  const o = {};
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--') { rest.push(...argv.slice(i + 1)); break; }
    else if (a === '--slug') o.slug = argv[++i];
    else if (a === '--repo') o.repo = argv[++i];
    else if (a === '--model') o.model = argv[++i];
    else if (a === '--effort') o.effort = argv[++i];
    else if (a === '--prompt-file') o.promptFile = argv[++i];
    else if (a === '--allow-dirty') o.allowDirty = true;
    else if (a === '--resume') o.resume = true;
    else if (a.startsWith('--')) fail(`unknown flag: ${a}\n${USAGE}`);
    else rest.push(a);
  }
  o.prompt = o.promptFile ? fs.readFileSync(o.promptFile, 'utf8') : rest.join(' ');
  return o;
}

function gitRaw(cwd, ...args) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args[0]} failed: ${r.stderr.trim()}`);
  return r.stdout;
}
const git = (cwd, ...args) => gitRaw(cwd, ...args).trim();

// File -> hash of its content (null when deleted), for every modified or untracked file.
function dirtyFiles(repo) {
  // -z: paths unquoted; for a rename, the source path comes as a separate entry.
  const entries = gitRaw(repo, 'status', '--porcelain', '-z', '--untracked-files=all').split('\0');
  const files = new Map();
  for (let i = 0; i < entries.length; i++) {
    if (!entries[i]) continue;
    const p = entries[i].slice(3);
    if (/^[RC]/.test(entries[i])) i++;
    files.set(p, fs.existsSync(path.join(repo, p)) ? git(repo, 'hash-object', '--', p) : null);
  }
  return files;
}

function codexBin() {
  if (process.env.CODEX_BIN) return process.env.CODEX_BIN;
  const r = spawnSync('/bin/sh', ['-c', 'command -v codex'], { encoding: 'utf8' });
  if (r.status === 0) return r.stdout.trim();
  if (fs.existsSync(APP_CODEX)) return APP_CODEX;
  fail('Codex not found: add it to PATH or set CODEX_BIN');
}

// Codex session of the latest run of this slug in this repo, from its meta.json.
function lastSession(runsDir, slug, repo) {
  let dirs = [];
  try { dirs = fs.readdirSync(runsDir); } catch { return null; }
  const runs = dirs
    .map((d) => {
      try { return JSON.parse(fs.readFileSync(path.join(runsDir, d, 'meta.json'), 'utf8')); }
      catch { return null; }
    })
    .filter((m) => m && m.slug === slug && m.repo === repo && m.sessionId)
    .sort((a, b) => b.started.localeCompare(a.started));
  return runs[0]?.sessionId ?? null;
}

// Codex records each session in a rollout file whose token_count events carry the token totals
// and the account's rate limits. The format is Codex-internal, so every read is best effort.
function rolloutFile(sessionId) {
  const dir = path.join(process.env.CODEX_HOME ?? path.join(os.homedir(), '.codex'), 'sessions');
  try {
    const hit = fs.readdirSync(dir, { recursive: true }).find((f) => f.endsWith(`-${sessionId}.jsonl`));
    return hit ? path.join(dir, hit) : null;
  } catch { return null; }
}

function lastTokenCount(file) {
  if (!file) return null;
  try {
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      if (!lines[i].includes('"token_count"')) continue;
      const p = JSON.parse(lines[i]).payload;
      if (p?.type === 'token_count' && p.info) return p;
    }
  } catch { /* unreadable rollout */ }
  return null;
}

// Tokens this run spent (on --resume, the growth over the session's earlier total), how full the
// context was on the last call, and the account's rate-limit windows.
function usageOf(after, before) {
  const t = after.info.total_token_usage;
  const b = before?.info?.total_token_usage ?? {};
  const delta = (f) => (t[f] ?? 0) - (b[f] ?? 0);
  const ctx = after.info.model_context_window;
  const ctxUsed = after.info.last_token_usage?.total_tokens ?? 0;
  return {
    input: delta('input_tokens'),
    cached: delta('cached_input_tokens'),
    output: delta('output_tokens'),
    contextUsed: ctxUsed,
    contextPct: ctx ? Math.round((ctxUsed / ctx) * 100) : null,
    contextWindow: ctx ?? null,
    limits: ['primary', 'secondary']
      .map((w) => after.rate_limits?.[w])
      .filter(Boolean)
      .map((w) => ({ windowMinutes: w.window_minutes, usedPct: w.used_percent, resetsAt: w.resets_at })),
  };
}

// 186500 -> "186.5K", 1000000 -> "1M".
const compact = (n) => {
  const [v, unit] = n >= 1e6 ? [n / 1e6, 'M'] : n >= 1e3 ? [n / 1e3, 'K'] : [n, ''];
  return `${v.toFixed(1).replace(/\.0$/, '')}${unit}`;
};
const windowLabel = (m) =>
  m === 300 ? '5h Session' : m === 10080 ? 'Weekly' : m % 1440 === 0 ? `${m / 1440}d` : `${Math.round(m / 60)}h`;

function usageLines(u) {
  const lines = [];
  if (u.contextPct !== null) {
    lines.push(`Context: ${u.contextPct}% (${compact(u.contextUsed)} / ${compact(u.contextWindow)})`);
  }
  for (const l of u.limits) lines.push(`${windowLabel(l.windowMinutes)}: ${l.usedPct}%`);
  return lines;
}

const isAlive = (pid) => {
  try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; }
};

// One Codex task per repo. A lock whose pid is gone belongs to a run that died.
function acquireLock(lockFile, info) {
  try { fs.writeFileSync(lockFile, JSON.stringify(info), { flag: 'wx' }); return; }
  catch (e) { if (e.code !== 'EEXIST') throw e; }
  let held = null;
  try { held = JSON.parse(fs.readFileSync(lockFile, 'utf8')); } catch { /* corrupt lock */ }
  if (held && isAlive(held.pid)) {
    fail(`a Codex task is already running in this repo: ${held.slug} (pid ${held.pid}, log ${held.logFile})`);
  }
  fs.writeFileSync(lockFile, JSON.stringify(info));
}

const o = parseArgs(process.argv.slice(2));
if (!o.slug || !o.prompt.trim()) fail(USAGE);
if (o.effort && !/^[a-z]+$/.test(o.effort)) fail(`invalid --effort: ${o.effort}`);

const slug = o.slug.replace(/[^a-zA-Z0-9_-]/g, '-');
const repo = path.resolve((o.repo ?? process.cwd()).replace(/^~/, os.homedir()));

// --- Preflight: everything that can fail before spending Codex tokens ---
let top, gitDir, baseHead, baseBranch, baseline;
try {
  top = git(repo, 'rev-parse', '--show-toplevel');
  gitDir = git(repo, 'rev-parse', '--absolute-git-dir');
  baseHead = git(top, 'rev-parse', 'HEAD');
  baseBranch = git(top, 'branch', '--show-current') || '(detached)';
  baseline = dirtyFiles(top);
} catch (e) {
  fail(`${repo}: ${e.message}`);
}
if (baseline.size > 0 && !o.allowDirty) {
  fail(
    `the checkout has ${baseline.size} uncommitted file(s); commit them or pass --allow-dirty:\n` +
      [...baseline.keys()].slice(0, MAX_FILES).join('\n'),
  );
}
const bin = codexBin();

const runsDir = path.join(os.homedir(), '.codex-delegate');
const resumeId = o.resume ? lastSession(runsDir, slug, top) : null;
if (o.resume && !resumeId) fail(`no previous run of "${slug}" in ${top} to resume`);

const startedAt = new Date().toISOString();
const outDir = path.join(runsDir, `${slug}-${startedAt.replace(/[:.]/g, '-').slice(0, 19)}`);
fs.mkdirSync(outDir, { recursive: true });
const resultFile = path.join(outDir, 'result.md');
const logFile = path.join(outDir, 'codex.log');
const lockFile = path.join(gitDir, 'codex-delegate.lock');

acquireLock(lockFile, { pid: process.pid, slug, logFile });
console.log(
  `[codex:${slug}] ${resumeId ? `resumed (session ${resumeId})` : 'started'} in ${top} ` +
    `(branch ${baseBranch})\nlog: ${logFile}`,
);

// --- Codex ---
// Codex runs commands in the repo: keep the ability to message the Claude session away from it.
const env = { ...process.env };
for (const k of Object.keys(env)) if (k.startsWith('CLAUDE_CODE_MESSAGING_')) delete env[k];

const flags = (process.env.CODEX_FLAGS ?? '--sandbox workspace-write').split(/\s+/).filter(Boolean);
// `exec` flags go before `resume`, which accepts no --cd or --sandbox of its own.
const args = [
  'exec', '--cd', top, '--color', 'never', ...flags,
  ...(o.effort ? ['-c', `model_reasoning_effort="${o.effort}"`] : []),
  ...(resumeId ? ['resume', resumeId] : []),
  ...(o.model ? ['-m', o.model] : []),
  '--output-last-message', resultFile,
  o.prompt + FOOTER,
];

// On --resume, the session's earlier total, so the summary reports only this run's tokens.
const usageBefore = resumeId ? lastTokenCount(rolloutFile(resumeId)) : null;
const started = Date.now();
let code;
try {
  const logFd = fs.openSync(logFile, 'a');
  code = await new Promise((res) => {
    const p = spawn(bin, args, { cwd: top, stdio: ['ignore', logFd, logFd], env });
    // If the background task is stopped, stop Codex and carry on to release the lock and summarize.
    for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(sig, () => p.kill(sig));
    p.on('error', (e) => { fs.writeSync(logFd, `spawn error: ${e.message}\n`); res(127); });
    p.on('close', (c, sig) => res(c ?? (sig ? 128 : 1)));
  });
  fs.closeSync(logFd);
} finally {
  fs.rmSync(lockFile, { force: true });
}

// --- Summary: only what Codex changed, not what was already dirty ---
const lines = [];
const secs = Math.round((Date.now() - started) / 1000);
lines.push(
  `[codex:${slug}] ${code === 0 ? 'DONE' : `FAILED (exit ${code})`} in ${Math.floor(secs / 60)}m${secs % 60}s`,
);
let changed = [];
try {
  const after = dirtyFiles(top);
  changed = [...after].filter(([p, h]) => !baseline.has(p) || baseline.get(p) !== h).map(([p]) => p);
  // A dirty file that Codex brought back to HEAD no longer shows in status.
  for (const p of baseline.keys()) if (!after.has(p)) changed.push(`${p} (reverted)`);
  const head = git(top, 'rev-parse', 'HEAD');
  const branch = git(top, 'branch', '--show-current') || '(detached)';
  if (branch !== baseBranch) lines.push(`⚠ branch changed: ${baseBranch} -> ${branch}`);
  if (head !== baseHead) lines.push(`⚠ HEAD moved: ${baseHead.slice(0, 7)} -> ${head.slice(0, 7)}`);
} catch (e) {
  lines.push(`could not read the git state: ${e.message}`);
}
lines.push(
  changed.length === 0
    ? 'files changed: none'
    : `files changed (${changed.length}):\n  ` +
        changed.slice(0, MAX_FILES).join('\n  ') +
        (changed.length > MAX_FILES ? `\n  … and ${changed.length - MAX_FILES} more` : ''),
);

let result = '';
try { result = fs.readFileSync(resultFile, 'utf8').trim(); } catch { /* Codex never answered */ }
let sessionId = null;
try { sessionId = fs.readFileSync(logFile, 'utf8').match(/^session id: (\S+)/m)?.[1] ?? null; } catch { /* no log */ }
const usageAfter = sessionId ? lastTokenCount(rolloutFile(sessionId)) : null;
const usage = usageAfter ? usageOf(usageAfter, usageBefore) : null;
lines.push(`result: ${result ? resultFile : '(no result)'}\nlog: ${logFile}`);
if (sessionId) lines.push(`Codex session: ${sessionId} (next round: --resume)`);
if (usage) lines.push(...usageLines(usage));
else if (sessionId) lines.push('Usage: unavailable (no token record in the Codex session)');
if (result) {
  lines.push(`summary:\n${result.length > MAX_SUMMARY ? result.slice(0, MAX_SUMMARY) + ' …' : result}`);
}

fs.writeFileSync(
  path.join(outDir, 'meta.json'),
  JSON.stringify(
    { slug, code, repo: top, started: startedAt, sessionId, baseBranch, baseHead, changed, secs, usage },
    null,
    2,
  ),
);
console.log(lines.join('\n'));
process.exitCode = code;
