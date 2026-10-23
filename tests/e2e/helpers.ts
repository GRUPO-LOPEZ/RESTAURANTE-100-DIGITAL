import { createHmac } from "node:crypto";
import { expect, type Page } from "@playwright/test";

// Datos de prueba del seed (supabase/seed.sql). Solo locales y ficticios.
export const PASSWORD = "Demo-Local-2026!";
// Secreto TOTP ficticio del seed para los roles con doble verificación.
const TOTP_SECRET = "JBSWY3DPEHPK3PXP";

function base32Decode(input: string): Buffer {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const char of input.replace(/=+$/, "")) {
    const value = alphabet.indexOf(char.toUpperCase());
    if (value < 0) throw new Error("Secreto TOTP inválido");
    bits += value.toString(2).padStart(5, "0");
  }
  const bytes: number[] = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) bytes.push(parseInt(bits.slice(i, i + 8), 2));
  return Buffer.from(bytes);
}

// Código TOTP (RFC 6238, SHA-1, 6 dígitos, 30 s), sin dependencias.
export function totp(at: number = Date.now()): string {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(at / 1000 / 30)));
  const hmac = createHmac("sha1", base32Decode(TOTP_SECRET)).update(counter).digest();
  const offset = (hmac[hmac.length - 1] ?? 0) & 0xf;
  const code = ((hmac.readUInt32BE(offset) & 0x7fffffff) % 1_000_000).toString();
  return code.padStart(6, "0");
}

// No usar dos veces el mismo código: si ya se usó el de este período, esperar al próximo.
let lastPeriod = -1;
export async function freshTotp(page: Page): Promise<string> {
  let period = Math.floor(Date.now() / 30_000);
  if (period === lastPeriod) {
    await page.waitForTimeout(30_000 - (Date.now() % 30_000) + 500);
    period = Math.floor(Date.now() / 30_000);
  }
  lastPeriod = period;
  return totp();
}

export async function fillLogin(page: Page, email: string, password = PASSWORD) {
  await page.goto("/ingresar");
  await page.getByLabel("Correo").fill(email);
  await page.getByLabel("Contraseña").fill(password);
  await page.getByRole("button", { name: "Ingresar" }).click();
}

// Ingreso completo: contraseña y, si el rol lo exige, doble verificación.
export async function login(page: Page, email: string, { mfa = false }: { mfa?: boolean } = {}) {
  await fillLogin(page, email);
  if (mfa) {
    await expect(page).toHaveURL(/\/ingresar\/doble-verificacion$/);
    await page.getByLabel("Código de 6 números").fill(await freshTotp(page));
    await page.getByRole("button", { name: "Verificar" }).click();
  }
  await expect(page.getByRole("heading", { level: 1, name: "Inicio" })).toBeVisible();
}

export async function logout(page: Page) {
  await page.getByRole("button", { name: /^Salir/ }).click();
  await expect(page).toHaveURL(/\/ingresar$/);
}

// Un enlace del menú principal. En el celular el menú está plegado detrás de "Menú": se abre.
export async function menuLink(page: Page, name: string) {
  // El encabezado llega en streaming, después del resto de la página: primero se lo espera.
  await page.getByRole("button", { name: /^Salir/ }).waitFor();
  const toggle = page.locator("summary", { hasText: "Menú" });
  if (await toggle.isVisible()) {
    const open = await toggle.evaluate((el) => (el.parentElement as HTMLDetailsElement).open);
    if (!open) await toggle.click();
  }
  return page
    .getByRole("navigation", { name: "Menú principal" })
    .getByRole("link", { name, exact: true });
}

// Abre una acción plegada de la ficha (por ejemplo, "Desactivar…").
export async function openAction(page: Page, summary: string) {
  await page.locator("summary", { hasText: summary }).click();
}

// El aviso de la pantalla (no el anunciador de rutas de Next, que también es role=alert).
export function notice(page: Page) {
  return page.locator('[data-slot="notice"]');
}
