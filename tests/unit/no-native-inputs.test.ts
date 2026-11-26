// Todo en español, también los controles del navegador (criterio 12 de Soy, ADR-0068): ningún campo de fecha ni de
// archivo del navegador a la vista. Con Chrome en inglés dicen «11/19/2026» y «Choose File No file chosen». Las fechas
// van con DateInput (o FormDate) y los archivos con FileUpload; un input de archivo propio vale solo si está escondido
// detrás de su botón (hidden o sr-only), como la cámara de la recepción.
import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

import { uploadLabel } from "@/components/ui/file-upload";

const ROOT = path.resolve(import.meta.dirname, "../..");
const ALLOWED = new Set([
  path.join("components", "ui", "date-input.tsx"),
  path.join("components", "ui", "file-upload.tsx"),
]);

function files(dir: string): string[] {
  return readdirSync(path.join(ROOT, dir)).flatMap((name) => {
    const rel = path.join(dir, name);
    if (statSync(path.join(ROOT, rel)).isDirectory()) return files(rel);
    return rel.endsWith(".tsx") ? [rel] : [];
  });
}

const sources = [...files("app"), ...files("components")]
  .filter((rel) => !ALLOWED.has(rel))
  .map((rel) => ({ rel, text: readFileSync(path.join(ROOT, rel), "utf8") }));

// Cada elemento JSX (de «<» a «>» o «/>») que tiene ese tipo.
function tagsWith(text: string, type: string): string[] {
  const out: string[] = [];
  const re = /<(?:input|Input|FormInput)\b[^>]*?>/gs;
  for (const m of text.matchAll(re)) if (m[0].includes(`type="${type}"`)) out.push(m[0]);
  return out;
}

describe("controles del navegador", () => {
  it("ningún campo de fecha del navegador: se usa DateInput o FormDate", () => {
    const found = sources.filter((s) => tagsWith(s.text, "date").length > 0).map((s) => s.rel);
    expect(found).toEqual([]);
  });

  it("ningún campo de archivo a la vista: se usa FileUpload (o uno propio escondido)", () => {
    const found = sources
      .flatMap((s) => tagsWith(s.text, "file").map((tag) => ({ rel: s.rel, tag })))
      .filter(({ tag }) => !/\bhidden\b|sr-only/.test(tag))
      .map(({ rel }) => rel);
    expect(found).toEqual([]);
  });

  it("el control de esta prueba encuentra lo que busca", () => {
    expect(tagsWith('<Input type="date" name="desde" />', "date")).toHaveLength(1);
    expect(tagsWith('<input\n  type="file"\n  className="sr-only"\n/>', "file")).toHaveLength(1);
  });
});

describe("uploadLabel", () => {
  it("dice qué se sube, en castellano", () => {
    expect(uploadLabel("image/jpeg,image/png,application/pdf")).toBe("Subir foto o PDF");
    expect(uploadLabel("image/*")).toBe("Subir foto");
    expect(uploadLabel("application/pdf")).toBe("Subir PDF");
    expect(
      uploadLabel(".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
    ).toBe("Subir planilla");
    expect(uploadLabel(undefined)).toBe("Subir archivo");
  });
});
