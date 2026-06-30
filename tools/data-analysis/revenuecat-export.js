#!/usr/bin/env node
/**
 * Read-only RevenueCat REST API v2 exporter.
 *
 * NOTE: This only works if the session's network policy allows
 * api.revenuecat.com. As of this writing that host is blocked by the
 * egress proxy, so this script is provided for when the policy is opened.
 *
 * Credentials are read from the environment, never hard-coded:
 *   - RC_API_KEY     A RevenueCat v2 secret API key (read scope is enough)
 *   - RC_PROJECT_ID  Your RevenueCat project id (from the dashboard URL)
 *
 * Optional:
 *   - EXPORT_DIR     Where to write JSON dumps (default ./export)
 *
 * This script only performs GET requests.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const API_KEY = process.env.RC_API_KEY;
const PROJECT_ID = process.env.RC_PROJECT_ID;
const BASE = 'https://api.revenuecat.com/v2';

if (!API_KEY) {
  console.error('ERROR: set RC_API_KEY (RevenueCat v2 secret key).');
  process.exit(1);
}
if (!PROJECT_ID) {
  console.error('ERROR: set RC_PROJECT_ID (from your RevenueCat dashboard URL).');
  process.exit(1);
}

async function get(urlPath) {
  const res = await fetch(`${BASE}${urlPath}`, {
    headers: { Authorization: `Bearer ${API_KEY}`, Accept: 'application/json' },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`GET ${urlPath} -> ${res.status} ${res.statusText}: ${body.slice(0, 300)}`);
  }
  return res.json();
}

// Walk RevenueCat's cursor pagination (items[] + next_page).
async function getAll(urlPath) {
  const items = [];
  let next = urlPath;
  while (next) {
    const page = await get(next);
    if (Array.isArray(page.items)) items.push(...page.items);
    next = page.next_page || null;
  }
  return items;
}

async function main() {
  const exportDir = path.resolve(process.env.EXPORT_DIR || path.join(__dirname, 'export'));
  fs.mkdirSync(exportDir, { recursive: true });

  const datasets = {
    products: `/projects/${PROJECT_ID}/products`,
    entitlements: `/projects/${PROJECT_ID}/entitlements`,
    offerings: `/projects/${PROJECT_ID}/offerings`,
  };

  console.log(`RevenueCat project: ${PROJECT_ID}`);
  console.log(`Export dir: ${exportDir}\n`);

  for (const [name, urlPath] of Object.entries(datasets)) {
    process.stdout.write(`Fetching ${name} ... `);
    try {
      const items = await getAll(urlPath);
      const outFile = path.join(exportDir, `revenuecat-${name}.json`);
      fs.writeFileSync(outFile, JSON.stringify(items, null, 2));
      console.log(`${items.length} items -> ${path.relative(process.cwd(), outFile)}`);
    } catch (e) {
      console.log(`SKIPPED (${e.message})`);
    }
  }

  console.log('\nDone. All operations were read-only (GET).');
  console.log('Tip: per-subscriber lookups use /projects/{id}/customers/{app_user_id}.');
}

main().catch((err) => {
  console.error('\nERROR:', err.message);
  process.exit(1);
});
