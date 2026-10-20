// Verifica que la paleta de app/globals.css cumpla contraste WCAG AA (4,5:1 en texto).
// Lee los colores del propio CSS: si alguien cambia un color, esta prueba lo controla.
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const css = readFileSync(
  path.resolve(import.meta.dirname, "../../app/globals.css"),
  "utf8",
);

function token(name: string): string {
  const match = css.match(new RegExp(`--color-${name}:\\s*(#[0-9a-fA-F]{6})`));
  if (!match?.[1])
    throw new Error(`No se encontró el color --color-${name} en globals.css`);
  return match[1];
}

function luminance(hex: string): number {
  const channels = [1, 3, 5].map(
    (i) => parseInt(hex.slice(i, i + 2), 16) / 255,
  );
  const [r, g, b] = channels.map((c) =>
    c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4,
  );
  return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!;
}

function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi! + 0.05) / (lo! + 0.05);
}

const PAIRS: [texto: string, fondo: string][] = [
  ["ink", "app"],
  ["ink", "surface"],
  ["ink-muted", "app"],
  ["ink-muted", "surface"],
  ["primary-ink", "primary"],
  ["primary", "surface"],
  ["ok-ink", "ok"],
  ["warn-ink", "warn"],
  ["bad-ink", "bad"],
  ["info-ink", "info"],
  ["review-ink", "review"],
  ["draft-ink", "draft"],
];

describe("contraste de la paleta (WCAG AA)", () => {
  it.each(PAIRS)("%s sobre %s llega a 4,5:1", (fg, bg) => {
    expect(contrast(token(fg), token(bg))).toBeGreaterThanOrEqual(4.5);
  });

  it("los colores son los del prompt maestro", () => {
    expect(token("app").toUpperCase()).toBe("#FAFAF9");
    expect(token("ink").toUpperCase()).toBe("#1F2937");
    expect(token("primary").toUpperCase()).toBe("#4F6D9A");
  });
});
