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

/**
 * Where the site lives: the custom domain set in Settings → Pages. GitHub Pages
 * redirects adrianeyre.github.io/agent-usage-widget/ here, so this, never that, is
 * the canonical address in the page, the sitemap and robots.txt.
 */
export const siteUrl = "https://agent-usage-widget.adrianeyre.co.uk";

/** The page's name and summary, shared by its meta tags, structured data and manifest. */
export const siteName = "Agent Usage";
export const siteDescription =
  "A free macOS menu-bar app and desktop widget that shows your Claude, Codex and GitHub Copilot usage limits, with a pace marker that says whether you'll run out before the reset.";

const root = join(import.meta.dirname, "..");
const source = import.meta.dirname;
const output = join(source, "dist");

/** Each `{{NAME}}` placeholder in the page, and what it becomes. */
const placeholders: Record<string, string> = {
  REPO_URL: repositoryUrl,
  DOCS_URL: `${repositoryUrl}/blob/main/docs/guide`,
  SITE_URL: siteUrl,
  SITE_NAME: siteName,
  SITE_DESCRIPTION: siteDescription,
  // The day of the build, for the structured data's dateModified.
  BUILD_DATE: new Date().toISOString().slice(0, 10),
};

/** The images the sitemap lists for image search: the card and the screenshots. */
const sitemapImages = [
  "social/card.png",
  "images/widgets.png",
  "images/menu.png",
  "images/manage-accounts.png",
  "images/add-account.png",
  "images/widget-states.png",
];

/** The one page, with its images, for search engines (sitemaps.org, with Google's image extension). */
function sitemap(): string {
  const images = sitemapImages
    .map((path) => `    <image:image><image:loc>${siteUrl}/${path}</image:loc></image:image>`)
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
  <url>
    <loc>${siteUrl}/</loc>
    <lastmod>${placeholders.BUILD_DATE}</lastmod>
${images}
  </url>
</urlset>
`;
}

/** Every crawler may read everything; the sitemap says where the page is. */
const robots = `User-agent: *
Allow: /

Sitemap: ${siteUrl}/sitemap.xml
`;

/** So the site can be added to a home screen or dock with its own name and icon. */
const manifest = {
  name: siteName,
  short_name: siteName,
  description: siteDescription,
  start_url: "./",
  scope: "./",
  display: "browser",
  background_color: "#0b1120",
  theme_color: "#16a34a",
  icons: [
    { src: "favicon.svg", type: "image/svg+xml", sizes: "any" },
    { src: "social/icon-192.png", type: "image/png", sizes: "192x192" },
    { src: "social/icon-512.png", type: "image/png", sizes: "512x512" },
  ],
};

/**
 * The files the page names by path (`images/…`, `social/…`), the files crawlers and
 * browsers look for at the root (`robots.txt`, `sitemap.xml`, `site.webmanifest`,
 * `apple-touch-icon.png`) and `.nojekyll`, gathered in a folder of their own that Vite serves and copies into `dist/` as they are.
 */
function gatherPublicFiles(): string {
  const folder = mkdtempSync(join(tmpdir(), "agent-usage-site-"));
  cpSync(join(root, "docs/images"), join(folder, "images"), { recursive: true });
  cpSync(join(source, "favicon.svg"), join(folder, "favicon.svg"));
  // The link-preview card and PNG icons (rendered by scripts/social-images.sh).
  cpSync(join(source, "social"), join(folder, "social"), { recursive: true });
  // At the root as well, where browsers and crawlers look for it without being told.
  cpSync(join(source, "social/apple-touch-icon.png"), join(folder, "apple-touch-icon.png"));
  writeFileSync(join(folder, "robots.txt"), robots);
  writeFileSync(join(folder, "sitemap.xml"), sitemap());
  writeFileSync(join(folder, "site.webmanifest"), `${JSON.stringify(manifest, null, 2)}\n`);
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
