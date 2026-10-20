// Takes the README screenshots of the web demo build with Playwright.
//
//   flutter build web --no-web-resources-cdn --dart-define=DEMO=true -o build/web-demo
//   flutter build web --no-web-resources-cdn -o build/web-plain
//   node tool/mock_devices.mjs build/web-demo   # in another shell, then:
//   node tool/screenshots.mjs demo
//   (restart the mock with build/web-plain)  node tool/screenshots.mjs empty
// The last demo shot switches the mock BBQ to greenhouse mode, so restart the
// mock before running `demo` again.
//
// Flutter web downloads Roboto from fonts.gstatic.com at runtime; requests
// are answered from the Roboto copy in the Flutter SDK so this works offline.
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE ?? '/opt/node22/lib/node_modules/playwright');

const flutterRoot = process.env.FLUTTER_ROOT ?? '/opt/flutter';
const roboto = await readFile(join(flutterRoot, 'bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'));
const outDir = new URL('../screenshots/', import.meta.url).pathname;
const url = 'http://localhost:8080/';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });

async function shot(name, { dark = false, action, after } = {}) {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    locale: 'en-US',
    isMobile: true,
    hasTouch: true,
    colorScheme: dark ? 'dark' : 'light',
  });
  await context.route(/fonts\.gstatic\.com/, (route) =>
    /roboto/i.test(route.request().url())
      ? route.fulfill({ body: roboto, contentType: 'font/ttf' })
      : route.abort());
  const page = await context.newPage();
  await page.goto(url);
  await sleep(7000); // app start + first scan
  if (action) await action(page);
  await page.screenshot({ path: join(outDir, `${name}.png`) });
  console.log(`saved ${name}.png`);
  if (after) await after(page);
  await context.close();
}

const mode = process.argv[2] ?? 'demo';
if (mode === 'demo') {
  await shot('device-list');
  await shot('device-list-dark', { dark: true });
  await shot('add-device', {
    action: async (page) => {
      await page.touchscreen.tap(300, 800); // "Add device" FAB
      await sleep(1000);
      await page.keyboard.type('192.168.4.1');
      await sleep(800);
    },
  });
  const openSwitchDialog = async (page) => {
      await page.touchscreen.tap(350, 158); // ⋮ on the multi-mode BBQ card
      await sleep(800);
      await page.touchscreen.tap(290, 170); // "Switch mode"
      await sleep(800);
      await page.touchscreen.tap(170, 461); // "Greenhouse" radio
      await sleep(600);
  };
  await shot('switch-mode', { action: openSwitchDialog });
  await shot('switch-mode-restarting', {
    action: async (page) => {
      await openSwitchDialog(page);
      await page.touchscreen.tap(265, 502); // "Switch"
      await sleep(800);
      await page.touchscreen.tap(245, 518); // "Switch and restart"
      await sleep(1500);
    },
    after: async (page) => {
      if (!process.env.PROBE) return;
      await sleep(12000); // mock reboots for 6 s, then reports the new type
      await page.screenshot({ path: join(outDir, '_probe.png') });
    },
  });
} else {
  await shot('empty-state');
}
await browser.close();
