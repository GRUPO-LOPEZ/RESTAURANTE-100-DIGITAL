import { missingState } from "@/lib/metrics";

// Los accesos grandes del Inicio (ADR-0045): cada uno con su número del momento y una palabra, para ver dónde hay algo
// para hacer. Sin acceso a la base: sale de los conteos que el Inicio ya cargó, y se prueba con Vitest.

export type ShortcutKey = "recipes" | "ingredients" | "costs" | "approvals" | "quality" | "reports";

export type ShortcutStatus = "ok" | "warn" | "bad" | "info" | "none" | "neutral";

export type ShortcutState = { status: ShortcutStatus; label: string; text: string | null };

type Count = { done: number; total: number };

export type ShortcutInput = {
  // Los indicadores de calidad del local (null = la persona no ve ese indicador).
  approved: Count | null;
  priced: Count | null;
  costed: Count | null;
  // Las solicitudes que la persona puede decidir; capped = se cortó en el tope de la lectura.
  approvals: { count: number; capped: boolean } | null;
  // Todo lo que falta en los indicadores que la persona ve (null = no ve ninguno).
  quality: Count | null;
};

const number = new Intl.NumberFormat("es-AR");

// Un acceso sin número para este rol: sin chip (label vacío), nunca «Al día».
const OPEN: ShortcutState = { status: "neutral", label: "", text: null };

// Lo que falta de un total, con la regla única (lib/metrics.ts): «4 sin aprobar» en Atención o Crítico, «Al día» con
// el total, «Sin datos» sin nada que medir.
function counted(
  count: Count | null,
  missingText: string,
  okText: (total: number) => string,
  emptyText: string,
): ShortcutState {
  if (!count) return OPEN;
  const missing = count.total - count.done;
  const state = missingState(missing, count.total);
  if (state.status === "none") return { status: "none", label: "Sin datos", text: emptyText };
  if (state.status === "ok") return { status: "ok", label: "Al día", text: okText(count.total) };
  return { status: state.status, label: `${number.format(missing)} ${missingText}`, text: null };
}

const plural = (n: number, one: string, many: string) =>
  `${number.format(n)} ${n === 1 ? one : many}`;

export function shortcutStates(input: ShortcutInput): Record<ShortcutKey, ShortcutState> {
  const approvals: ShortcutState = !input.approvals
    ? OPEN
    : input.approvals.count === 0
      ? { status: "ok", label: "Al día", text: "Nada para decidir" }
      : {
          status: "info",
          label: input.approvals.capped
            ? `${number.format(input.approvals.count)} o más esperan tu decisión`
            : input.approvals.count === 1
              ? "1 espera tu decisión"
              : `${number.format(input.approvals.count)} esperan tu decisión`,
          text: null,
        };

  // Calidad avisa en Atención: es la suma de muchos indicadores, cada uno con su propio color en su pantalla.
  const qualityMissing = input.quality ? input.quality.total - input.quality.done : 0;
  const quality: ShortcutState = !input.quality
    ? OPEN
    : input.quality.total <= 0
      ? { status: "none", label: "Sin datos", text: "Nada que medir" }
      : qualityMissing <= 0
        ? { status: "ok", label: "Al día", text: "Todo completo" }
        : {
            status: "warn",
            label: plural(qualityMissing, "dato por completar", "datos por completar"),
            text: null,
          };

  return {
    recipes: counted(
      input.approved,
      "sin aprobar",
      (t) => plural(t, "receta", "recetas"),
      "Sin recetas",
    ),
    ingredients: counted(
      input.priced,
      "sin precio",
      (t) => plural(t, "cargada", "cargadas"),
      "Sin materias primas",
    ),
    costs: counted(input.costed, "por corregir", () => "Todo con costo", "Sin recetas"),
    approvals,
    quality,
    reports: { status: "neutral", label: "Informes", text: "Costos y recetario" },
  };
}
