// Builds the project website (GitHub Pages) in `site/dist/` with Vite: the page,
// its stylesheet and fonts from `site/`, and its one script, which runs the page's
// enhancements and mounts the product demos (React, on the Stageshow kit vendored
// in `site/stageshow/`). The screenshots in `docs/images/` (rendered from the app by
// `scripts/screenshots.sh`) are copied in as `images/`, never kept twice in Git.
// `.github/workflows/pages.yml` runs it and publishes `site/dist/`. Run it yourself
// with `pnpm site:build`, then serve `site/dist/` (`pnpm site:preview`);
// `pnpm site:dev` serves the page as you edit it.
import { cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import react from "@vitejs/plugin-react";
import { build, createServer, preview, type InlineConfig } from "vite";

/** The repository, named once: every link to it on the page comes from here. */
export const repositoryUrl = "https://github.com/adrianeyre/agent-usage-widget";

/** Where GitHub Pages serves the site (no custom domain). */
export const siteUrl = "https://adrianeyre.github.io/agent-usage-widget";

const root = join(import.meta.dirname, "..");
const source = import.meta.dirname;
const output = join(source, "dist");

/** Each `{{NAME}}` placeholder in the page, and what it becomes. */
const placeholders: Record<string, string> = {
  REPO_URL: repositoryUrl,
  DOCS_URL: `${repositoryUrl}/blob/main/docs/guide`,
  SITE_URL: siteUrl,
};

/**
 * The files the page names by path (`images/…`, `.nojekyll`), gathered in a folder
 * of their own that Vite serves and copies into `dist/` as they are.
 */
function gatherPublicFiles(): string {
  const folder = mkdtempSync(join(tmpdir(), "agent-usage-site-"));
  cpSync(join(root, "docs/images"), join(folder, "images"), { recursive: true });
  cpSync(join(source, "favicon.svg"), join(folder, "favicon.svg"));
  // Pages serves the folder as it is, with no Jekyll step.
  writeFileSync(join(folder, ".nojekyll"), "");
  return folder;
}

function config(publicDir: string): InlineConfig {
  return {
    configFile: false,
    root: source,
    // Relative, so the built page works under /agent-usage-widget/ and from any folder.
    base: "./",
    publicDir,
    logLevel: "warn",
    plugins: [
      react(),
      {
        name: "agent-usage-placeholders",
        transformIndexHtml: (page) =>
          page.replaceAll(/\{\{([A-Z_]+)\}\}/g, (match, name: string) => {
            const value = placeholders[name];
            if (value === undefined) {
              throw new Error(`site/index.html names an unknown placeholder ${match}`);
            }
            return value;
          }),
      },
    ],
    resolve: { dedupe: ["react", "react-dom"] },
    build: {
      outDir: output,
      emptyOutDir: true,
      target: "es2022",
    },
  };
}

const mode = process.argv[2];
const publicDir = gatherPublicFiles();

if (mode === "--dev") {
  const server = await createServer(config(publicDir));
  await server.listen();
  server.printUrls();
} else if (mode === "--preview") {
  const server = await preview(config(publicDir));
  server.printUrls();
} else {
  try {
    await build(config(publicDir));
  } finally {
    rmSync(publicDir, { recursive: true, force: true });
  }
  console.log(`Built the website in ${output}`);
}
