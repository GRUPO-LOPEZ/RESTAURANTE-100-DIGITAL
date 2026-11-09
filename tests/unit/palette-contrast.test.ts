// Verifica que la paleta de app/globals.css cumpla contraste WCAG AA (4,5:1 en texto).
// Lee los colores del propio CSS: si alguien cambia un color, esta prueba lo controla.
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const css = readFileSync(path.resolve(import.meta.dirname, "../../app/globals.css"), "utf8");

function token(name: string): string {
  const match = css.match(new RegExp(`--color-${name}:\\s*(#[0-9a-fA-F]{6})`));
  if (!match?.[1]) throw new Error(`No se encontró el color --color-${name} en globals.css`);
  return match[1];
}

function luminance(hex: string): number {
  const channels = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const [r, g, b] = channels.map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
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
  ["primary", "app"],
  ["bad-ink", "surface"],
  ["ok-ink", "ok"],
  ["warn-ink", "warn"],
  ["bad-ink", "bad"],
  ["info-ink", "info"],
  ["review-ink", "review"],
  ["draft-ink", "draft"],
  ["none-ink", "none"],
  // Barra lateral y botón principal al pasar el mouse (ADR-0036).
  ["nav-ink", "nav"],
  ["nav-active-ink", "nav-active"],
  // El logo y el contorno de foco de la barra lateral usan nav-active sobre nav.
  ["nav-active", "nav"],
  ["primary-ink", "primary-hover"],
];

describe("contraste de la paleta (WCAG AA)", () => {
  it.each(PAIRS)("%s sobre %s llega a 4,5:1", (fg, bg) => {
    expect(contrast(token(fg), token(bg))).toBeGreaterThanOrEqual(4.5);
  });

  // Los tonos fuertes de gráficos (barras, líneas, puntos): 3:1 como objeto gráfico (WCAG 1.4.11).
  it.each(
    [1, 2, 3, 4, 5, 6].flatMap(
      (n) =>
        [
          [n, "surface"],
          [n, "app"],
        ] as const,
    ),
  )("chart-strong-%i sobre %s llega a 3:1", (n, bg) => {
    expect(contrast(token(`chart-strong-${n}`), token(bg))).toBeGreaterThanOrEqual(3);
  });

  // Los del prompt de rediseño (ADR-0036).
  it("los colores son los del prompt maestro", () => {
    expect(token("app").toUpperCase()).toBe("#F7F8FA");
    expect(token("ink").toUpperCase()).toBe("#1F2937");
    expect(token("primary").toUpperCase()).toBe("#4A6FB8");
    expect(token("nav").toUpperCase()).toBe("#22304A");
    expect(token("none").toUpperCase()).toBe("#F1F2F4");
  });

  it("el color del navegador (themeColor) es el fondo de la app", () => {
    const layout = readFileSync(path.resolve(import.meta.dirname, "../../app/layout.tsx"), "utf8");
    expect(layout).toContain(`themeColor: "${token("app")}"`);
  });

  // Documentado en design.md: el texto secundario no va sobre fondos pastel.
  it.each(["ok", "warn"])("ink-muted NO llega a AA sobre %s (por eso está prohibido)", (bg) => {
    expect(contrast(token("ink-muted"), token(bg))).toBeLessThan(4.5);
  });
});
