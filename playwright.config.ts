import { readFileSync } from "node:fs";
import { defineConfig, devices } from "@playwright/test";

const PORT = 3100;
const isCI = Boolean(process.env.CI);

// La app de prueba usa los valores públicos de desarrollo local de .env.example (nunca claves
// de servidor ni de otros ambientes).
function publicEnv(): Record<string, string> {
  const env: Record<string, string> = {};
  for (const line of readFileSync(".env.example", "utf8").split(/\r?\n/)) {
    const match = /^(NEXT_PUBLIC_[A-Z_]+)=(.*)$/.exec(line.trim());
    if (match?.[1] && match[2] !== undefined) env[match[1]] = match[2];
  }
  return env;
}

// Celular primero: cada prueba corre en un celular y en una computadora (prompt maestro, sección 9).
// Un solo worker: las pruebas de flujo cambian datos de la base local (bloqueos, bajas) y
// usan códigos de doble verificación que no conviene repetir en paralelo.
export default defineConfig({
  testDir: "tests/e2e",
  fullyParallel: false,
  workers: 1,
  forbidOnly: isCI,
  retries: isCI ? 1 : 0,
  reporter: isCI ? [["github"], ["html", { open: "never" }]] : [["list"]],
  globalSetup: "./tests/e2e/global-setup.ts",
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    locale: "es-AR",
    timezoneId: "America/Argentina/Buenos_Aires",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "celular", use: { ...devices["Pixel 7"] } },
    {
      name: "computadora",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1280, height: 800 },
      },
    },
  ],
  webServer: {
    // En CI el build ya se hizo en un paso anterior.
    command: isCI ? `npm run start -- -p ${PORT}` : `npm run build && npm run start -- -p ${PORT}`,
    url: `http://127.0.0.1:${PORT}/ingresar`,
    reuseExistingServer: !isCI,
    timeout: 240_000,
    env: publicEnv(),
  },
});
