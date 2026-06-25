#!/usr/bin/env node
/**
 * streetphare-dev-toolkit — MCP Server
 *
 * Tools:
 *   - search_npm_docs : Fetch package README from npm registry.
 *   - analyze_bundle_size : Analyze local package.json / build size.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as fs from "fs";
import * as path from "path";

// ---- helpers ---------------------------------------------------------

async function fetchNpmDocs(packageName: string): Promise<string> {
  const url = `https://registry.npmjs.org/${encodeURIComponent(packageName)}/latest`;
  const resp = await fetch(url, {
    headers: { Accept: "application/json" },
  });
  if (!resp.ok) {
    return `npm registry returned ${resp.status} ${resp.statusText}`;
  }
  const data = (await resp.json()) as Record<string, unknown>;
  if (!data || typeof data !== "object") {
    return "Unexpected response from npm registry.";
  }
  const readme: string =
    typeof data.readme === "string" ? data.readme : "No README found in registry.";
  const version = (data.version as string) ?? "unknown";
  const description = (data.description as string) ?? "";
  const homepage = (data.homepage as string) ?? "";
  const repository =
    typeof data.repository === "object" && data.repository !== null
      ? (data.repository as Record<string, unknown>).url ?? ""
      : "";

  return [
    `## ${packageName}@${version}`,
    description ? `> ${description}` : "",
    homepage ? `Homepage: ${homepage}` : "",
    repository ? `Repository: ${repository}` : "",
    "",
    readme.substring(0, 8000), // truncate to avoid huge context
  ]
    .filter(Boolean)
    .join("\n");
}

function analyzeLocalBundle(projectRoot: string): string {
  const pkgPath = path.join(projectRoot, "package.json");
  if (!fs.existsSync(pkgPath)) {
    return `No package.json found at ${pkgPath}. Run inside a Node.js project.`;
  }

  const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8")) as Record<string, unknown>;
  const deps = { ...((pkg.dependencies as Record<string, string>) ?? {}), ...((pkg.devDependencies as Record<string, string>) ?? {}) };
  const depCount = Object.keys(deps).length;

  // Try to estimate node_modules size
  const nmPath = path.join(projectRoot, "node_modules");
  let nodeModulesSizeMB = 0;
  if (fs.existsSync(nmPath)) {
    nodeModulesSizeMB = Math.round(dirSizeSync(nmPath) / 1024 / 1024);
  }

  // Check build dir
  const buildDir = path.join(projectRoot, "build");
  let buildSizeMB = 0;
  if (fs.existsSync(buildDir)) {
    buildSizeMB = Math.round(dirSizeSync(buildDir) / 1024 / 1024);
  }

  const lines = [
    `## Bundle Analysis — ${pkg.name ?? "unknown"}@${pkg.version ?? "0.0.0"}`,
    `- Dependencies: **${depCount}** packages`,
    `- node_modules size: **${nodeModulesSizeMB} MB**`,
    `- build size: **${buildSizeMB} MB**`,
    "",
    "### Top-level packages",
    ...Object.entries(deps)
      .sort(([, a], [, b]) => a.localeCompare(b))
      .map(([name, ver]) => `- ${name}@${ver}`),
  ];

  // Highlight large packages
  const largeDeps = Object.entries(deps).filter(([, ver]) => ver.startsWith("file:") || depCount > 50);
  if (largeDeps.length > 0) {
    lines.push("", "### ⚠️ Optimization hints", "- Consider lazy-loading or code-splitting large dependencies.");
  }

  return lines.join("\n");
}

function dirSizeSync(dir: string): number {
  let size = 0;
  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        size += dirSizeSync(full);
      } else if (e.isFile()) {
        size += fs.statSync(full).size;
      }
    }
  } catch {
    // ignore permission errors
  }
  return size;
}

// ---- MCP Server ------------------------------------------------------

const server = new McpServer({
  name: "streetphare-dev-toolkit",
  version: "1.0.0",
});

// Tool 1: search_npm_docs
server.tool("search_npm_docs", "Fetch package README/documentation from npm registry", {
  package: z.string().describe("npm package name (e.g. 'react', 'express')"),
}, async ({ package: pkg }) => {
  const result = await fetchNpmDocs(pkg);
  return {
    content: [{ type: "text", text: result }],
  };
});

// Tool 2: analyze_bundle_size
server.tool("analyze_bundle_size", "Analyze local package.json and node_modules/build size", {
  projectRoot: z.string().default(process.cwd()).describe("Absolute path to the project root"),
}, async ({ projectRoot }) => {
  const result = analyzeLocalBundle(projectRoot);
  return {
    content: [{ type: "text", text: result }],
  };
});

// ---- Bootstrap -------------------------------------------------------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  // Log to stderr (stdio is reserved for MCP protocol)
  console.error(`[streetphare-dev-toolkit] MCP server started.`);
}

main().catch((err) => {
  console.error("[streetphare-dev-toolkit] Fatal error:", err);
  process.exit(1);
});