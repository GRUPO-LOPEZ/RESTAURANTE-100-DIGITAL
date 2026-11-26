// Fechas como se escriben acá: dd/mm/aaaa (criterio 12 de Soy, ADR-0068). El campo de fecha del navegador sigue el
// idioma de Chrome (en inglés, 11/19/2026); por eso los formularios usan un campo de texto propio (DateInput) y la fecha
// viaja en ISO (aaaa-mm-dd), como siempre. Lo puro, sin navegador: se prueba en tests/unit/date-input.test.ts.

const ISO = /^(\d{4})-(\d{2})-(\d{2})$/;

// aaaa-mm-dd → dd/mm/aaaa (vacío si no hay fecha o no es ISO).
export function isoToDay(iso: string | null | undefined): string {
  const m = ISO.exec((iso ?? "").slice(0, 10));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "";
}

// Lo que se escribe, con las barras puestas solas: «1911» → «19/11», «19112026» → «19/11/2026». Si ya trae barras
// («1/2/2026») se respetan. Pegar una fecha ISO («2026-11-19») la pasa a dd/mm/aaaa.
export function maskDay(text: string): string {
  const raw = text.trim();
  if (ISO.test(raw)) return isoToDay(raw);
  if (raw.includes("/")) {
    const parts = raw
      .split("/")
      .slice(0, 3)
      .map((p) => p.replace(/\D/g, ""));
    // Cada parte entra en su lugar (día y mes de hasta 2, año de hasta 4): se respeta como está. Si una se pasa
    // (se siguió escribiendo sobre «19/11»), se arma de nuevo con todos los números.
    const fits = parts.every((p, i) => p.length <= (i === 2 ? 4 : 2));
    if (fits) return parts.join("/");
  }
  const digits = raw.replace(/\D/g, "").slice(0, 8);
  if (digits.length <= 2) return digits;
  if (digits.length <= 4) return `${digits.slice(0, 2)}/${digits.slice(2)}`;
  return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`;
}

export type DayParse = { kind: "empty" } | { kind: "invalid" } | { kind: "ok"; iso: string };

// dd/mm/aaaa (o d/m/aa) → aaaa-mm-dd. Dos dígitos de año son del 2000 («26» → 2026). Una fecha que no existe
// (31/02, 29/02 de un año no bisiesto) no vale.
export function dayToIso(text: string): DayParse {
  const raw = text.trim();
  if (raw === "") return { kind: "empty" };
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})$/.exec(raw);
  if (!m) return { kind: "invalid" };
  const day = Number(m[1]);
  const month = Number(m[2]);
  const yearText = m[3] ?? "";
  const year = yearText.length === 2 ? 2000 + Number(yearText) : Number(yearText);
  if (year < 1900 || month < 1 || month > 12 || day < 1) return { kind: "invalid" };
  const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
  if (day > last) return { kind: "invalid" };
  const pad = (n: number) => String(n).padStart(2, "0");
  return { kind: "ok", iso: `${year}-${pad(month)}-${pad(day)}` };
}

// Por qué no vale una fecha escrita, o null si vale (o está vacía). min y max en ISO, como en el campo del navegador.
export function dayError(text: string, min?: string, max?: string): string | null {
  const parsed = dayToIso(text);
  if (parsed.kind === "empty") return null;
  if (parsed.kind === "invalid") return "Escribí una fecha que exista, como dd/mm/aaaa.";
  if (min && parsed.iso < min) return `Tiene que ser desde el ${isoToDay(min)}.`;
  if (max && parsed.iso > max) return `Tiene que ser hasta el ${isoToDay(max)}.`;
  return null;
}
