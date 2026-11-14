"use client";

import { Fragment, useEffect, useId, useRef, useState, useTransition, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { MoreHorizontal, Plus, Trash2 } from "lucide-react";

import { previewSheetLinesAction, saveSheetAction, unitOptionsAction } from "@/app/recetas/actions";
import type { ComponentFound, ComponentSearch } from "@/lib/recipe-search";
import { FormNotice } from "@/components/form-notice";
import { Missing } from "@/components/recipe-sheet/missing";
import { ReviewBox } from "@/components/recipe-sheet/review-box";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { SidePanel } from "@/components/ui/dialog";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { InfoTip } from "@/components/ui/info-tip";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { Tile } from "@/components/ui/tile";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { reasonField, recipeLinesSchema, recipeStepsSchema } from "@/lib/forms/schemas";
import { formatMoney, parseAmount } from "@/lib/money";
import {
  BASIS_LABELS,
  LINE_UNITS,
  STEP_KIND_LABELS,
  formatMinutes,
  formatQuantity,
  lineUnitForYield,
  unitDimension,
  unitOptionLabel,
  type LineUnit,
  type QuantityBasis,
  type RecipeType,
  type StepKind,
  type UnitDimension,
} from "@/lib/recipe-format";
import {
  bigUnitPrice,
  changesLabel,
  countChanges,
  formatGrams,
  formatPct,
  incidence,
  missingReason,
  parseTimes,
  portionsFrom,
  scale,
  sheetKpis,
  sheetTotals,
  toGrams,
  totalState,
  withTrailingRow,
  yieldRatio,
  type PreviewLine,
} from "@/lib/recipe-sheet";
import type { RecipeLine, RecipeStep, VersionStatus } from "@/lib/recipes";

export type SheetRecipe = {
  id: string;
  type: RecipeType;
  name: string;
  shortName: string | null;
  categoryId: string | null;
  sector: string | null;
  station: string | null;
};
export type SheetVersion = {
  id: string;
  number: number;
  status: VersionStatus;
  updatedAt: string;
  yieldQuantity: number | null;
  yieldUnit: string | null;
  portions: number | null;
  portionGrams: number | null;
  description: string | null;
  storageNotes: string | null;
  presentationNotes: string | null;
  changeSummary: string | null;
};

type Row = {
  key: number;
  ingredient_id: string | null;
  sub_recipe_id: string | null;
  code: string;
  name: string;
  quantity: string;
  unit: LineUnit | "";
  basis: QuantityBasis;
  yield_profile_id: string | null;
  no_scale: boolean;
  notes: string;
  // Las medidas que admite (null: todavía no se sabe; se ofrecen todas).
  dims: UnitDimension[] | null;
};
type Step = {
  key: number;
  kind: StepKind;
  instructions: string;
  active_minutes: string;
  passive_minutes: string;
  equipment: string;
  equipment_capacity: string;
  capacity_unit: string;
  depends: number[];
};
type Data = {
  name: string;
  short_name: string;
  category_id: string;
  sector: string;
  station: string;
};
type Draft = {
  description: string;
  storage_notes: string;
  presentation_notes: string;
  change_summary: string;
  portion_grams: string;
  yield_quantity: string;
  yield_unit: string;
};
type Search = {
  key: number;
  field: "code" | "name";
  query: string;
  status: "searching" | "done" | "error";
  items: (ComponentFound & { kind: "ingredient" | "preparation" })[];
  active: number;
  anchor: Anchor;
  inputId: string;
};

// Dónde se dibuja la lista de sugerencias (fija, fuera de la tabla): debajo del campo o, si abajo no hay lugar (las
// últimas filas a la vista de la planilla), arriba. Su alto no pasa del espacio que queda: la página no tiene scroll.
type Anchor = { top?: number; bottom?: number; left: number; width: number; maxHeight: number };
function anchorFor(box: DOMRect): Anchor {
  const below = window.innerHeight - box.bottom - 8;
  const above = box.top - 72;
  const base = { left: box.left, width: Math.max(box.width, 320) };
  return below >= 200 || below >= above
    ? { ...base, top: box.bottom, maxHeight: Math.min(288, below) }
    : { ...base, bottom: window.innerHeight - box.top, maxHeight: Math.min(288, above) };
}

const comma = (n: number | null) => (n === null ? "" : String(n).replace(".", ","));
// Las dos columnas fijas a la izquierda de la planilla (ADR-0047): Código mide siempre 140 px (w-35), que es el
// corrimiento de Ingrediente; el borde marca dónde termina lo fijo. Debajo del título y del total fijos (z-10).
// La celda de Ingrediente lleva la lista de sugerencias: mientras está abierta sube por encima del título y del total.
const STICKY_CODE = "sticky left-0 z-5 w-35 min-w-35 max-w-35";
const STICKY_NAME = "sticky left-35 min-w-36 shadow-[inset_-1px_0_var(--color-line)]";
const blankRow = (key: number): Row => ({
  key,
  ingredient_id: null,
  sub_recipe_id: null,
  code: "",
  name: "",
  quantity: "",
  unit: "",
  basis: "purchase",
  yield_profile_id: null,
  no_scale: false,
  notes: "",
  dims: null,
});
const isFilled = (r: Row) =>
  (r.ingredient_id !== null || r.sub_recipe_id !== null) &&
  (parseAmount(r.quantity) ?? 0) > 0 &&
  r.unit !== "";
const isTouched = (r: Row) =>
  r.ingredient_id !== null ||
  r.sub_recipe_id !== null ||
  r.code !== "" ||
  r.name !== "" ||
  r.quantity !== "";
const rowSnapshot = (r: Row) =>
  JSON.stringify([
    r.ingredient_id,
    r.sub_recipe_id,
    parseAmount(r.quantity),
    r.unit,
    r.basis,
    r.notes,
  ]);

function stepPayload(steps: Step[]) {
  const position = new Map(steps.map((s, i) => [s.key, i + 1]));
  return steps.map((s) => ({
    kind: s.kind,
    instructions: s.instructions,
    active_minutes: s.active_minutes,
    passive_minutes: s.passive_minutes,
    equipment: s.equipment,
    equipment_capacity: s.equipment_capacity,
    equipment_capacity_unit: s.capacity_unit,
    depends_on: s.depends
      .map((d) => position.get(d))
      .filter((n): n is number => typeof n === "number")
      .sort((a, b) => a - b),
  }));
}

function suggestedUnit(unitName: string): LineUnit {
  if (unitName === "ml") return "ml";
  if (unitName === "unidad") return "unit";
  return "g";
}

// La ficha de una receta (ADR-0042; en una pantalla, ADR-0047): 4 indicadores, la planilla de ingredientes con su
// propio scroll y, a la derecha, datos, rendimiento, procedimiento y el resumen. Una barra fija guarda todo junto (una
// transacción, un motivo); lo que no entra se edita en un panel sobre el mismo borrador. En la computadora se edita
// donde se ve; en el celular es de consulta. Los costos los calcula la base fila por fila mientras se escribe.
export function SheetEditor({
  recipe,
  version,
  categories,
  lines: initialLines,
  steps: initialSteps,
  unitOptions,
  editable,
  canSubmit,
  place,
  money,
  prices,
  totalMinutes,
  marks,
  times: initialTimes,
  anchorSuffix,
  scopeLabel,
  review,
  notice,
  photos,
  mobilePhotos,
  summary,
}: {
  recipe: SheetRecipe;
  version: SheetVersion;
  categories: { id: string; label: string }[];
  lines: RecipeLine[];
  steps: RecipeStep[];
  unitOptions: Record<string, UnitDimension[]>;
  editable: boolean;
  canSubmit: boolean;
  place: { id: string; name: string } | null;
  money: boolean;
  prices: boolean;
  totalMinutes: number;
  // Lo que cambió contra la versión anterior, por nombre («antes 380 g» o «Nueva», para quien revisa).
  marks: Record<string, string>;
  times: [number, number];
  // Lo que se agrega al id de cada sección (único por receta: Next guarda oculta la ficha anterior). Va como texto:
  // una función no puede pasar de un componente de servidor a uno de cliente.
  anchorSuffix: string;
  // El alcance, en palabras («De la marca Demo Pastas»).
  scopeLabel: string;
  // Quien revisa decide en la barra de abajo, en lugar de Guardar (ADR-0047).
  review: { requestId: string; changes: number; removed: number } | null;
  // El último guardado, en la barra al lado del contador (en el celular va arriba).
  notice: { status: "ok" | "info" | "warn"; text: string } | null;
  // Lo que arma el servidor: las fotos (miniatura y la del celular) y la franja de resumen con sus paneles.
  photos: ReactNode;
  mobilePhotos: ReactNode;
  summary: ReactNode;
}) {
  const prefix = useId();
  const anchor = (key: string) => `${key}-${anchorSuffix}`;
  const router = useRouter();
  const dish = recipe.type === "dish";

  const startData: Data = {
    name: recipe.name,
    short_name: recipe.shortName ?? "",
    category_id: recipe.categoryId ?? "",
    sector: recipe.sector ?? "",
    station: recipe.station ?? "",
  };
  const startDraft: Draft = {
    description: version.description ?? "",
    storage_notes: version.storageNotes ?? "",
    presentation_notes: version.presentationNotes ?? "",
    change_summary: version.changeSummary ?? "",
    portion_grams: comma(version.portionGrams),
    yield_quantity: comma(version.yieldQuantity),
    yield_unit: version.yieldUnit ?? "",
  };
  const startRows = initialLines.map((l, i): Row => ({
    key: i + 1,
    ingredient_id: l.ingredientId,
    sub_recipe_id: l.subRecipeId,
    code: l.code,
    name: l.ingredient,
    quantity: comma(l.quantity),
    unit: (LINE_UNITS.find((u) => u.code === l.unit)?.code ?? "g") as LineUnit,
    basis: l.basis,
    yield_profile_id: l.yieldProfileId,
    no_scale: l.noScale,
    notes: l.notes ?? "",
    dims: l.subRecipeId
      ? [unitDimension(l.unit) ?? "mass"]
      : (unitOptions[l.ingredientId ?? ""] ?? null),
  }));
  const startSteps = initialSteps.map((s): Step => ({
    key: s.number,
    kind: s.kind,
    instructions: s.instructions,
    active_minutes: String(s.activeMinutes),
    passive_minutes: String(s.passiveMinutes),
    equipment: s.equipment ?? "",
    equipment_capacity: comma(s.equipmentCapacity),
    capacity_unit: s.equipmentCapacityUnit ?? "",
    depends: s.dependsOn,
  }));

  const [data, setData] = useState<Data>(startData);
  const [draft, setDraft] = useState<Draft>(startDraft);
  const [rows, setRows] = useState<Row[]>(() =>
    editable
      ? withTrailingRow(startRows, isFilled, () => blankRow(0)).map((r, i) => ({
          ...r,
          key: i + 1,
        }))
      : startRows,
  );
  const [nextKey, setNextKey] = useState(() => Math.max(startRows.length, 10) + 2);
  const [steps, setSteps] = useState<Step[]>(startSteps);
  const [nextStep, setNextStep] = useState(() => Math.max(0, ...startSteps.map((s) => s.key)) + 1);
  // Lo guardado, para contar los cambios (se actualiza al guardar).
  const [saved, setSaved] = useState(() => ({
    data: startData,
    draft: startDraft,
    lines: startRows.filter(isTouched).map(rowSnapshot),
    steps: JSON.stringify(stepPayload(startSteps)),
    stepList: stepPayload(startSteps).map((s) => JSON.stringify(s)),
  }));
  const [reason, setReason] = useState("");
  const [state, setState] = useState<ActionState>({});
  const [pending, startTransition] = useTransition();
  const [search, setSearch] = useState<Search | null>(null);
  // Lo último que calculó la base, con la grilla para la que lo calculó.
  const [previewed, setPreviewed] = useState<{
    input: string;
    lines: Map<number, PreviewLine>;
    failed: boolean;
  }>({ input: "", lines: new Map(), failed: false });
  const [timesText, setTimesText] = useState<[string, string]>([
    String(initialTimes[0]),
    String(initialTimes[1]),
  ]);
  const [openRow, setOpenRow] = useState<number | null>(null);
  // El panel abierto: los datos generales o los pasos (trabajan sobre el mismo borrador).
  const [panel, setPanel] = useState<"datos" | "pasos" | null>(null);
  const previewSeq = useRef(0);
  const searchSeq = useRef(0);

  // Contador de cambios: campos, filas y pasos distintos de lo guardado.
  const touched = rows.filter(isTouched);
  const lineSnapshots = touched.map(rowSnapshot);
  const linesChanged = countChanges(saved.lines, lineSnapshots, (a, b) => a === b);
  const stepsNow = stepPayload(steps).map((s) => JSON.stringify(s));
  const stepsChanged = countChanges(saved.stepList, stepsNow, (a, b) => a === b);
  const dataChanged = (Object.keys(data) as (keyof Data)[]).filter(
    (k) => data[k] !== saved.data[k],
  ).length;
  const draftChanged = (Object.keys(draft) as (keyof Draft)[]).filter(
    (k) => draft[k] !== saved.draft[k],
  ).length;
  const changes = linesChanged + stepsChanged + dataChanged + draftChanged;
  useUnsavedWarning(changes > 0);

  // Los números «Hacer N recetas» se recuerdan en la dirección (no son datos oficiales).
  const timesA = parseTimes(timesText[0]);
  const timesB = parseTimes(timesText[1]);
  useEffect(() => {
    if (timesA === null || timesB === null) return;
    const url = new URL(window.location.href);
    url.searchParams.set("hacer", `${timesA},${timesB}`);
    window.history.replaceState(window.history.state, "", url);
  }, [timesA, timesB]);

  // La base calcula pesos y costos de las filas completas mientras se escribe (con una pausa corta).
  const previewInput = JSON.stringify(
    rows.map((r) =>
      isFilled(r)
        ? {
            ingredient_id: r.ingredient_id,
            sub_recipe_id: r.sub_recipe_id,
            quantity: parseAmount(r.quantity),
            unit: r.unit,
            basis: r.sub_recipe_id ? "finished" : r.basis,
            yield_profile_id: r.yield_profile_id,
          }
        : null,
    ),
  );
  useEffect(() => {
    const seq = ++previewSeq.current;
    const payload = JSON.parse(previewInput) as unknown[];
    if (!payload.some((p) => p !== null)) return;
    const timer = setTimeout(() => {
      const failed = () => {
        if (seq === previewSeq.current)
          setPreviewed({ input: previewInput, lines: new Map(), failed: true });
      };
      previewSheetLinesAction(version.id, place?.id ?? null, payload)
        .then((r) => {
          if (seq !== previewSeq.current) return;
          if (r.status !== "ok") return failed();
          setPreviewed({
            input: previewInput,
            lines: new Map(r.lines.map((l) => [l.lineOrder, l])),
            failed: false,
          });
        })
        .catch(failed);
    }, 400);
    return () => clearTimeout(timer);
  }, [previewInput, version.id, place?.id]);
  const anyFilled = rows.some(isFilled);
  const calculating = anyFilled && previewed.input !== previewInput;
  // Un error del servidor no se confunde con un dato que falta: se avisa aparte.
  const previewFailed = anyFilled && !calculating && previewed.failed;
  const preview = previewed.lines;

  // Al abrir «Más opciones» de una fila, el foco pasa a su primer control.
  useEffect(() => {
    if (openRow === null) return;
    document
      .getElementById(`${prefix}-opciones-${openRow}`)
      ?.querySelector<HTMLElement>("select, input, textarea, button")
      ?.focus();
  }, [openRow, prefix]);

  // Con las flechas, la opción marcada queda a la vista dentro de la lista.
  const activeOption = search ? `${prefix}-sugerencias-${search.key}-${search.active}` : null;
  useEffect(() => {
    if (activeOption) document.getElementById(activeOption)?.scrollIntoView({ block: "nearest" });
  }, [activeOption]);

  // La lista de sugerencias flota sobre la página: si la página o la tabla se mueven, sigue al campo.
  const searchInput = search?.inputId;
  useEffect(() => {
    if (!searchInput) return;
    const follow = () =>
      setSearch((s) => {
        const box = s ? document.getElementById(s.inputId)?.getBoundingClientRect() : undefined;
        return s && box ? { ...s, anchor: anchorFor(box) } : s;
      });
    window.addEventListener("scroll", follow, true);
    window.addEventListener("resize", follow);
    return () => {
      window.removeEventListener("scroll", follow, true);
      window.removeEventListener("resize", follow);
    };
  }, [searchInput]);

  // Buscador de cada fila, por código o por nombre, desde 3 letras. Solo cuenta la última respuesta. Depende solo del
  // texto buscado: si la lista se mueve con el desplazamiento de la planilla, la búsqueda no vuelve a empezar. Va por
  // una ruta GET (no una acción de servidor): las acciones se corren de a una y quedaba detrás del cálculo de la
  // planilla. Al seguir escribiendo, el pedido anterior se cancela.
  const pendingQuery = search?.status === "searching" ? search.query : null;
  useEffect(() => {
    if (pendingQuery === null) return;
    const seq = ++searchSeq.current;
    const abort = new AbortController();
    const timer = setTimeout(() => {
      const params = new URLSearchParams({ q: pendingQuery, receta: recipe.id });
      fetch(`/recetas/buscar-componentes?${params}`, { signal: abort.signal, cache: "no-store" })
        .then((res) =>
          res.ok ? (res.json() as Promise<ComponentSearch>) : { status: "error" as const },
        )
        .catch((): ComponentSearch => ({ status: "error" }))
        .then((r) => {
          if (seq !== searchSeq.current) return;
          setSearch((s) =>
            s && s.query === pendingQuery
              ? r.status === "ok"
                ? {
                    ...s,
                    status: "done",
                    active: 0,
                    items: [
                      ...r.ingredients.map((i) => ({ ...i, kind: "ingredient" as const })),
                      ...r.preparations.map((i) => ({ ...i, kind: "preparation" as const })),
                    ],
                  }
                : { ...s, status: "error", items: [] }
              : s,
          );
        });
    }, 300);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [pendingQuery, recipe.id]);

  const update = (key: number, change: Partial<Row>) =>
    setRows((all) =>
      withTrailingRow(
        all.map((r) => (r.key === key ? { ...r, ...change } : r)),
        isFilled,
        () => blankRow(-1),
      ).map((r) => (r.key === -1 ? { ...r, key: nextKeyRef.current++ } : r)),
    );
  const nextKeyRef = useRef(nextKey);
  useEffect(() => {
    nextKeyRef.current = Math.max(nextKeyRef.current, nextKey);
  }, [nextKey]);

  function typeIn(key: number, field: "code" | "name", input: HTMLInputElement) {
    const value = input.value;
    // Escribir de nuevo suelta lo elegido: la fila queda incompleta hasta elegir otra vez.
    update(key, { [field]: value, ingredient_id: null, sub_recipe_id: null, dims: null });
    // La lista se dibuja fija debajo del campo, fuera de la tabla: así no la recorta el desplazamiento.
    const box = input.getBoundingClientRect();
    setSearch(
      value.trim().length >= 3
        ? {
            key,
            field,
            query: value.trim(),
            status: "searching",
            items: [],
            active: 0,
            anchor: anchorFor(box),
            inputId: input.id,
          }
        : null,
    );
  }

  function choose(key: number, item: Search["items"][number]) {
    const preparation = item.kind === "preparation";
    const unit = preparation ? lineUnitForYield(item.unit) : suggestedUnit(item.unit);
    update(key, {
      ingredient_id: preparation ? null : item.id,
      sub_recipe_id: preparation ? item.id : null,
      code: item.code,
      name: item.name,
      unit,
      basis: preparation ? "finished" : "purchase",
      yield_profile_id: null,
      dims: preparation ? [unitDimension(unit) ?? "mass"] : null,
    });
    setSearch(null);
    if (!preparation) {
      // Si no se pueden leer las medidas, se ofrecen todas: la base controla la unidad al guardar.
      unitOptionsAction([item.id])
        .then((o) => {
          const dims = o[item.id];
          if (dims)
            setRows((all) =>
              all.map((r) => (r.ingredient_id === item.id && r.dims === null ? { ...r, dims } : r)),
            );
        })
        .catch(() => undefined);
    }
    document.getElementById(`${prefix}-cantidad-${key}`)?.focus();
  }

  function onSearchKey(e: React.KeyboardEvent, key: number) {
    if (!search || search.key !== key) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const n = search.items.length;
      if (n === 0) return;
      setSearch({ ...search, active: (search.active + (e.key === "ArrowDown" ? 1 : n - 1)) % n });
    } else if (e.key === "Enter") {
      const item = search.items[search.active];
      if (item) {
        e.preventDefault();
        choose(key, item);
      }
    } else if (e.key === "Escape") {
      setSearch(null);
    }
  }

  function removeRow(key: number) {
    setRows((all) =>
      withTrailingRow(
        all.filter((r) => r.key !== key),
        isFilled,
        () => blankRow(nextKeyRef.current++),
      ),
    );
    setOpenRow(null);
  }

  // Valores de cada fila, con lo que devolvió la base.
  const computed = rows.map((r, i) => {
    const p = isFilled(r) ? preview.get(i + 1) : undefined;
    return {
      row: r,
      index: i,
      filled: isFilled(r),
      grams: p?.grams ?? null,
      gramsReason: p ? missingReason(p.weightStatus) : "Se calcula al completar la fila.",
      cost: p?.lineCost ?? null,
      costReason: p ? missingReason(p.status) : "Se calcula al completar la fila.",
      price: bigUnitPrice(p?.unitCost ?? null, p?.costUnit ?? null),
    };
  });
  const filled = computed.filter((c) => c.filled);
  const totals = sheetTotals(
    filled.map((c) => ({ grams: c.grams, cost: money && place !== null ? c.cost : 0 })),
  );
  // Con permiso de costos pero sin local elegido, no hay columnas de dinero: las métricas dicen por qué.
  const showMoney = money && place !== null;
  const totalCost = showMoney ? totals.cost : null;

  // Rendimiento: plato (peso de la porción) o preparación (peso neto cargado a mano).
  const portionGrams = parseAmount(draft.portion_grams);
  const portions = dish ? portionsFrom(totals.grams, portionGrams) : null;
  const manualPortions =
    dish && portions === null && version.yieldQuantity !== null && !draft.portion_grams
      ? version.yieldQuantity
      : null;
  const netGrams = dish
    ? null
    : toGrams(parseAmount(draft.yield_quantity), draft.yield_unit || null);
  const ratio = yieldRatio(netGrams, totals.grams);

  async function save(submit: boolean) {
    const errors: string[] = [];
    const bad = rows.findIndex((r) => isTouched(r) && !isFilled(r));
    if (bad >= 0)
      errors.push(
        `Fila ${bad + 1}: elegí el ingrediente de la lista, la cantidad y la medida (o vaciá la fila).`,
      );
    const lines = touched.filter(isFilled).map((r) => ({
      ingredient_id: r.ingredient_id,
      sub_recipe_id: r.sub_recipe_id,
      ingredient: r.name,
      quantity: r.quantity,
      unit: r.unit as LineUnit,
      basis: r.sub_recipe_id ? ("finished" as const) : r.basis,
      yield_profile_id: r.yield_profile_id,
      no_scale: r.no_scale,
      notes: r.notes,
    }));
    const parsedLines = recipeLinesSchema.safeParse(lines);
    if (!parsedLines.success) {
      const issue = parsedLines.error.issues[0];
      const at = typeof issue?.path[0] === "number" ? issue.path[0] : null;
      const row = at === null ? undefined : rows.filter((r) => isTouched(r) && isFilled(r))[at];
      const i = row ? rows.indexOf(row) + 1 : null;
      errors.push(`${i ? `Fila ${i}: ` : ""}${issue?.message ?? "Revisá los ingredientes."}`);
    }
    const parsedSteps = recipeStepsSchema.safeParse(stepPayload(steps));
    if (!parsedSteps.success) {
      const issue = parsedSteps.error.issues[0];
      const i = typeof issue?.path[0] === "number" ? issue.path[0] + 1 : null;
      errors.push(`${i ? `Paso ${i}: ` : ""}${issue?.message ?? "Revisá los pasos."}`);
    }
    const parsedReason = reasonField.safeParse(reason);
    if (!parsedReason.success) errors.push("Escribí el motivo de los cambios.");
    if (errors.length > 0 || !parsedLines.success || !parsedSteps.success) {
      setState({ status: "bad", message: errors[0] ?? "Revisá los datos." });
      if (!parsedReason.success) document.getElementById(`${prefix}-motivo`)?.focus();
      return;
    }
    const draftKeys = (Object.keys(draft) as (keyof Draft)[]).filter(
      (k) => draft[k] !== saved.draft[k],
    );
    const draftOut = draftKeys.length
      ? Object.fromEntries(
          draftKeys.flatMap((k) =>
            // Un plato no manda el rendimiento: lo calcula la base con el peso de la porción.
            dish && (k === "yield_quantity" || k === "yield_unit")
              ? []
              : k === "yield_quantity" || k === "yield_unit"
                ? [
                    ["yield_quantity", draft.yield_quantity],
                    ["yield_unit", draft.yield_unit],
                  ]
                : [[k, draft[k]]],
          ),
        )
      : null;
    startTransition(async () => {
      const result = await saveSheetAction({
        recipeId: recipe.id,
        versionId: version.id,
        expectedUpdatedAt: version.updatedAt,
        reason,
        submit,
        recipe: dataChanged > 0 ? data : null,
        draft: draftOut && Object.keys(draftOut).length > 0 ? draftOut : null,
        lines: linesChanged > 0 ? parsedLines.data : null,
        steps: stepsChanged > 0 ? parsedSteps.data : null,
      });
      setState(result);
      if (result.status === "ok" || result.status === "info") {
        setSaved({
          data,
          draft,
          lines: lineSnapshots,
          steps: JSON.stringify(stepPayload(steps)),
          stepList: stepsNow,
        });
        setReason("");
        // La ficha vuelve a leerse con lo guardado (o con el borrador nuevo) y avisa arriba.
        const hacer = timesA !== null && timesB !== null ? `&hacer=${timesA},${timesB}` : "";
        const aviso = submit ? "revision" : result.warning ? "porciones" : "guardado";
        router.replace(`/recetas/${recipe.id}?aviso=${aviso}${hacer}`, {
          scroll: false,
        });
      }
    });
  }

  function discard() {
    setData(startData);
    setDraft(startDraft);
    setRows(
      withTrailingRow(startRows, isFilled, () => blankRow(0)).map((r, i) => ({ ...r, key: i + 1 })),
    );
    setNextKey(Math.max(startRows.length, 10) + 2);
    setSteps(startSteps);
    setReason("");
    setState({});
  }

  const ro = !editable;
  const unitLabel = (code: string) => LINE_UNITS.find((u) => u.code === code)?.label ?? code;
  const moneyCell = (v: number | null, reason: string) =>
    v === null ? (
      <Missing reason={reason} />
    ) : (
      <span className="tabular-nums">{formatMoney(v)}</span>
    );
  const gramsCell = (v: number | null, reason: string) =>
    v === null ? (
      <Missing reason={reason} />
    ) : (
      <span className="tabular-nums">{formatGrams(v)}</span>
    );
  const scaleCols = [timesA, timesB] as const;

  // Los 4 indicadores de arriba (no se repiten abajo) y el estado del total de la planilla.
  const kpis = sheetKpis({
    dish,
    money,
    place: place?.name ?? null,
    lines: filled.length,
    grams: totals.grams,
    missingGrams: totals.missingGrams,
    cost: totalCost,
    missingCost: totals.missingCost,
    portionText: draft.portion_grams,
    portionGrams,
    portions,
    manualPortions,
    netText: draft.yield_quantity,
    netGrams,
    ratio,
    totalMinutes,
  });
  const incomplete = filled.filter(
    (c) => c.grams === null || (showMoney && c.cost === null),
  ).length;
  const total = totalState(filled.length, incomplete);
  // Lo que cambió en el panel de datos (cuenta en la barra; acá se avisa al lado de «Editar datos»).
  const panelData = (["name", "short_name", "sector", "station"] as const).filter(
    (k) => data[k] !== saved.data[k],
  ).length;
  const panelDraft = (
    ["description", "storage_notes", "presentation_notes", "change_summary"] as const
  ).filter((k) => draft[k] !== saved.draft[k]).length;
  const dataPanelChanges = panelData + panelDraft;
  const categoryLabel = categories.find((c) => c.id === data.category_id)?.label ?? "Sin rubro";

  function addStep() {
    const previous = steps.at(-1);
    const key = nextStep;
    setSteps((all) => [
      ...all,
      {
        key,
        kind: "preparation",
        instructions: "",
        active_minutes: "0",
        passive_minutes: "0",
        equipment: "",
        equipment_capacity: "",
        capacity_unit: "",
        depends: previous ? [previous.key] : [],
      },
    ]);
    setNextStep((k) => k + 1);
    setPanel("pasos");
    // El panel toma el foco al abrirse: después, el foco va al paso nuevo.
    setTimeout(() => document.getElementById(`${prefix}-paso-${key}-que`)?.focus(), 50);
  }

  const stepYieldLabel = dish
    ? draft.portion_grams || draft.yield_unit
      ? "porción"
      : undefined
    : draft.yield_unit
      ? unitLabel(draft.yield_unit)
      : undefined;
  const stepCards = steps.map((s, index) => (
    <StepCard
      key={s.key}
      prefix={prefix}
      step={s}
      index={index}
      previous={steps.slice(0, index)}
      ro={ro}
      yieldLabel={stepYieldLabel}
      changed={saved.stepList[index] !== stepsNow[index]}
      onChange={(change) =>
        setSteps((all) => all.map((x) => (x.key === s.key ? { ...x, ...change } : x)))
      }
      onRemove={() =>
        setSteps((all) =>
          all
            .filter((x) => x.key !== s.key)
            .map((x) => ({ ...x, depends: x.depends.filter((d) => d !== s.key) })),
        )
      }
    />
  ));
  const changedInput = (changed: boolean) => (changed ? "border-dashed border-primary" : "");

  return (
    <TooltipProvider>
      {/* 4 indicadores. En el celular, de a uno: los montos no entran de a dos (ADR-0046). */}
      <div className="grid gap-3 desk:grid-cols-4 desk:gap-4">
        {kpis.map(({ key: kpiKey, ...m }) => (
          <Metric compact key={kpiKey} {...m} />
        ))}
      </div>

      {/* Dos columnas que ocupan el alto que queda: la planilla (la única parte con scroll propio) y 300 px a la
          derecha. En el celular, una debajo de la otra. */}
      <div className="grid gap-4 desk:min-h-0 desk:flex-1 desk:grid-cols-[minmax(0,1fr)_300px] desk:grid-rows-[minmax(0,1fr)]">
        <Tile
          id={anchor("ingredientes")}
          title="Ingredientes y costos"
          titleExtra={
            <span className="text-xs text-ink-muted tabular-nums">
              · {filled.length} {filled.length === 1 ? "ingrediente" : "ingredientes"}
              {showMoney ? " · sin IVA" : ""}
            </span>
          }
          aside={
            <span className="text-xs text-ink-muted" role="status">
              {calculating
                ? "Calculando…"
                : money
                  ? place
                    ? `Precios de ${place.name}.`
                    : "Elegí un local arriba para ver los costos."
                  : editable
                    ? "Al completar la última fila se agrega otra."
                    : ""}
            </span>
          }
          className="desk:min-h-0"
        >
          {previewFailed ? (
            <Notice status="warn" role="status" className="py-2 text-sm">
              No pudimos calcular los pesos y los costos. Probá de nuevo en un momento.
            </Notice>
          ) : null}
          {/* Computadora: la planilla. Los títulos y el total quedan fijos; solo el cuerpo se desplaza. El margen de
              desplazamiento deja a la vista la fila que recibe el foco con el teclado (no queda bajo el título ni el
              total). La base de 0 px (no 0 %) hace que la tabla no aporte su alto a la fila: solo ocupa lo que queda. */}
          <div
            data-slot="sheet-scroll"
            // Se enfoca con el teclado para desplazarla aunque no tenga controles (quien solo lee, con dinero).
            tabIndex={0}
            role="region"
            aria-label="Planilla de ingredientes (se desplaza)"
            className="relative hidden min-h-0 scroll-pt-12 scroll-pb-12 scroll-pl-76 overflow-auto rounded-sm border border-line focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:block desk:h-0 desk:flex-[1_1_0px]"
          >
            <table className="w-full border-collapse text-sm" aria-label="Ingredientes y costos">
              <thead className="sticky top-0 z-10 bg-app">
                <tr className="text-left text-ink-muted shadow-[inset_0_-1px_0_var(--color-line)]">
                  {/* Anchos mínimos: el código y la medida se leen enteros. Sin dinero entra en 1440; con dinero, la
                      planilla se desplaza de costado dentro de su tarjeta (nunca la página). */}
                  {/* Código e Ingrediente quedan fijos a la izquierda al desplazar de costado (con dinero, en 1440 y
                      1600): nunca se pierde de qué fila es cada número. Código mide siempre 140 px, el corrimiento
                      de Ingrediente. */}
                  <th scope="col" className={`${STICKY_CODE} bg-app px-2 py-2 font-medium`}>
                    Código
                  </th>
                  <th scope="col" className={`${STICKY_NAME} z-5 bg-app px-2 py-2 font-medium`}>
                    Ingrediente
                  </th>
                  <th scope="col" className="min-w-20 px-2 py-2 text-right font-medium">
                    Cantidad
                  </th>
                  <th scope="col" className="min-w-22 px-2 py-2 font-medium">
                    Medida
                  </th>
                  {[0, 1].map((col) => (
                    <th key={col} scope="col" className="min-w-28 px-2 py-1 text-right font-medium">
                      <span className="flex flex-col items-end">
                        <span className="inline-flex items-center gap-1 whitespace-nowrap">
                          Hacer
                          <Input
                            aria-label={`Hacer: cantidad de recetas, columna ${col === 0 ? "A" : "B"}`}
                            inputMode="numeric"
                            className="w-12 px-1 text-center desk:h-8 desk:min-h-8 desk:text-sm"
                            value={timesText[col]}
                            onChange={(e) =>
                              setTimesText((t) =>
                                col === 0 ? [e.target.value, t[1]] : [t[0], e.target.value],
                              )
                            }
                          />
                        </span>
                        <span className="text-xs whitespace-nowrap">
                          {showMoney ? "peso / costo" : "peso"}
                        </span>
                      </span>
                    </th>
                  ))}
                  {showMoney && prices ? (
                    <th
                      scope="col"
                      className="min-w-24 px-2 py-2 text-right font-medium whitespace-nowrap"
                    >
                      $ por kg o l
                    </th>
                  ) : null}
                  {showMoney ? (
                    <th scope="col" className="min-w-24 px-2 py-2 text-right font-medium">
                      Costo
                    </th>
                  ) : null}
                  {showMoney ? (
                    <th
                      scope="col"
                      className="min-w-14 px-2 py-2 text-right font-medium whitespace-nowrap"
                    >
                      <abbr title="Incidencia en el costo" className="no-underline">
                        % $
                      </abbr>
                    </th>
                  ) : null}
                  <th
                    scope="col"
                    className="min-w-16 px-2 py-2 text-right font-medium whitespace-nowrap"
                  >
                    <abbr title="Incidencia en el peso" className="no-underline">
                      % peso
                    </abbr>
                  </th>
                  {editable ? (
                    <th scope="col" className="w-10 px-1 py-2">
                      <span className="sr-only">Más opciones</span>
                    </th>
                  ) : null}
                </tr>
              </thead>
              <tbody>
                {computed.map((c) => {
                  const r = c.row;
                  const n = c.index + 1;
                  const open = search?.key === r.key;
                  const active = (field: "code" | "name") =>
                    open && search?.field === field && search.items[search.active]
                      ? `${listId}-${search.active}`
                      : undefined;
                  const listId = `${prefix}-sugerencias-${r.key}`;
                  const mark = marks[r.name];
                  const units = LINE_UNITS.filter((u) => !r.dims || r.dims.includes(u.dimension));
                  return (
                    <Fragment key={r.key}>
                      <tr
                        className={`border-b border-line align-top ${mark ? "bg-review" : "bg-surface"}`}
                      >
                        <td className={`${STICKY_CODE} bg-inherit px-2 py-1`}>
                          {ro ? (
                            <span className="inline-flex min-h-8 items-center text-ink tabular-nums">
                              {r.code}
                            </span>
                          ) : (
                            <Input
                              id={`${prefix}-codigo-${r.key}`}
                              aria-label={`Código, fila ${n}`}
                              role="combobox"
                              aria-expanded={open && search?.field === "code"}
                              aria-controls={open && search?.field === "code" ? listId : undefined}
                              aria-activedescendant={active("code")}
                              aria-autocomplete="list"
                              autoComplete="off"
                              placeholder="Código"
                              className="px-2 desk:h-8 desk:min-h-8 desk:text-sm"
                              value={r.code}
                              onChange={(e) => typeIn(r.key, "code", e.currentTarget)}
                              onKeyDown={(e) => onSearchKey(e, r.key)}
                              onBlur={() => setSearch(null)}
                            />
                          )}
                        </td>
                        <td
                          className={`${STICKY_NAME} ${open ? "z-30" : "z-5"} bg-inherit px-2 py-1`}
                        >
                          {ro ? (
                            <span className="flex min-h-8 flex-wrap items-center gap-2 text-ink">
                              {r.name}
                              {r.sub_recipe_id ? (
                                <PrepLink id={r.sub_recipe_id} name={r.name} />
                              ) : null}
                              {/* Quien revisa: lo que cambió contra la versión anterior. */}
                              {mark ? <Badge status="review">{mark}</Badge> : null}
                            </span>
                          ) : (
                            <div className="flex items-center gap-2">
                              <Input
                                id={`${prefix}-ingrediente-${r.key}`}
                                aria-label={`Ingrediente, fila ${n}`}
                                role="combobox"
                                aria-expanded={open && search?.field === "name"}
                                aria-controls={
                                  open && search?.field === "name" ? listId : undefined
                                }
                                aria-activedescendant={active("name")}
                                aria-autocomplete="list"
                                autoComplete="off"
                                placeholder="Escribí para buscar"
                                className="desk:h-8 desk:min-h-8 desk:text-sm"
                                value={r.name}
                                onChange={(e) => typeIn(r.key, "name", e.currentTarget)}
                                onKeyDown={(e) => onSearchKey(e, r.key)}
                                onBlur={() => setSearch(null)}
                              />
                              {r.sub_recipe_id ? (
                                <PrepLink id={r.sub_recipe_id} name={r.name} />
                              ) : null}
                            </div>
                          )}
                          {open && search && search.items.length > 0 ? (
                            <ul
                              id={listId}
                              role="listbox"
                              aria-label="Sugerencias"
                              // Fija junto al campo (abajo o arriba, anchorFor): la planilla se desplaza y no la recorta.
                              style={search.anchor}
                              className="fixed z-30 flex flex-col overflow-y-auto rounded-sm border border-line bg-surface shadow-sm"
                            >
                              {search.items.map((item, i) => (
                                <li
                                  key={`${item.kind}-${item.id}`}
                                  id={`${listId}-${i}`}
                                  role="option"
                                  aria-selected={i === search.active}
                                  className={`flex min-h-control cursor-pointer flex-wrap items-center gap-2 px-3 py-2 text-ink ${i === search.active ? "bg-line/50" : ""}`}
                                  onMouseDown={(e) => {
                                    e.preventDefault();
                                    choose(r.key, item);
                                  }}
                                >
                                  <span>{item.name}</span>
                                  {/* Sobre la opción marcada (fondo line/50), el código va en ink: el gris queda al límite de 4,5:1. */}
                                  <span
                                    className={`tabular-nums ${i === search.active ? "text-ink" : "text-ink-muted"}`}
                                  >
                                    · {item.code}
                                  </span>
                                  {item.kind === "preparation" ? (
                                    <Badge status="info">Preparación</Badge>
                                  ) : null}
                                </li>
                              ))}
                            </ul>
                          ) : open && search ? (
                            <p
                              role="status"
                              style={{ ...search.anchor, maxHeight: undefined }}
                              className="fixed z-30 rounded-sm border border-line bg-surface px-3 py-2 text-ink-muted shadow-sm"
                            >
                              {search.status === "error"
                                ? "No pudimos buscar. Probá de nuevo."
                                : search.status === "done"
                                  ? `Sin resultados para «${search.query}».`
                                  : "Buscando…"}
                            </p>
                          ) : null}
                        </td>
                        <td className="px-2 py-1 text-right">
                          {ro ? (
                            <span className="inline-flex min-h-8 items-center tabular-nums">
                              {r.quantity}
                            </span>
                          ) : (
                            <Input
                              id={`${prefix}-cantidad-${r.key}`}
                              aria-label={`Cantidad, fila ${n}`}
                              inputMode="decimal"
                              className="text-right tabular-nums desk:h-8 desk:min-h-8 desk:text-sm"
                              value={r.quantity}
                              onChange={(e) => update(r.key, { quantity: e.target.value })}
                            />
                          )}
                        </td>
                        <td className="px-2 py-1">
                          {ro ? (
                            <span className="inline-flex min-h-8 items-center">
                              {unitLabel(r.unit)}
                            </span>
                          ) : (
                            <Select
                              id={`${prefix}-medida-${r.key}`}
                              aria-label={`Medida, fila ${n}`}
                              className="pr-1 pl-2 desk:h-8 desk:min-h-8 desk:text-sm"
                              value={r.unit}
                              onChange={(e) => update(r.key, { unit: e.target.value as LineUnit })}
                            >
                              <option value="" disabled>
                                Elegí
                              </option>
                              {/* La abreviatura («g», «cda»), como en una planilla: el nombre largo no entra en la
                                  columna. El nombre completo, al pasar el mouse. */}
                              {units.map((u) => (
                                <option key={u.code} value={u.code} title={unitOptionLabel(u.code)}>
                                  {u.label}
                                </option>
                              ))}
                            </Select>
                          )}
                        </td>
                        {scaleCols.map((times, col) => {
                          // El peso arriba y el costo abajo: la columna es angosta y la fila casi no crece. Si faltan los
                          // dos, un solo «—» con los dos motivos.
                          const grams = scale(c.grams, times);
                          const cost = showMoney ? scale(c.cost, times) : undefined;
                          const gramsWhy =
                            times === null ? "Escribí cuántas recetas." : c.gramsReason;
                          const costWhy =
                            times === null ? "Escribí cuántas recetas." : c.costReason;
                          return (
                            <td key={col} className="px-2 py-1 text-right">
                              {!c.filled ? null : grams === null && cost === null ? (
                                <span className="flex min-h-8 items-center justify-end">
                                  <Missing
                                    compact
                                    reason={
                                      gramsWhy === costWhy ? gramsWhy : `${gramsWhy} ${costWhy}`
                                    }
                                  />
                                </span>
                              ) : (
                                <span className="flex min-h-8 flex-col items-end justify-center text-xs leading-4 whitespace-nowrap tabular-nums">
                                  {grams === null ? (
                                    <Missing compact reason={gramsWhy} />
                                  ) : (
                                    <span>{formatGrams(grams)}</span>
                                  )}
                                  {cost === undefined ? null : cost === null ? (
                                    <Missing compact reason={costWhy} />
                                  ) : (
                                    <span>{formatMoney(cost)}</span>
                                  )}
                                </span>
                              )}
                            </td>
                          );
                        })}
                        {showMoney && prices ? (
                          <td className="px-2 py-1 text-right">
                            {c.filled ? (
                              c.price ? (
                                <span className="inline-flex min-h-8 items-center whitespace-nowrap tabular-nums">
                                  {formatMoney(c.price.value)} / {c.price.unit}
                                </span>
                              ) : (
                                <Missing reason={c.costReason} />
                              )
                            ) : null}
                          </td>
                        ) : null}
                        {showMoney ? (
                          <td className="px-2 py-1 text-right whitespace-nowrap">
                            {c.filled ? moneyCell(c.cost, c.costReason) : null}
                          </td>
                        ) : null}
                        {showMoney ? (
                          <td className="px-2 py-1 text-right whitespace-nowrap tabular-nums">
                            {c.filled ? (
                              totalCost === null ? (
                                <Missing reason="Falta el costo total: alguna fila no tiene costo." />
                              ) : c.cost === null ? (
                                <Missing reason={c.costReason} />
                              ) : (
                                <span className="inline-flex min-h-8 items-center">
                                  {formatPct(incidence(c.cost, totalCost))}
                                </span>
                              )
                            ) : null}
                          </td>
                        ) : null}
                        <td className="px-2 py-1 text-right whitespace-nowrap tabular-nums">
                          {c.filled ? (
                            totals.grams === null ? (
                              <Missing reason="Falta el peso total: alguna fila no se pasa a gramos." />
                            ) : c.grams === null ? (
                              <Missing reason={c.gramsReason} />
                            ) : (
                              <span className="inline-flex min-h-8 items-center">
                                {formatPct(incidence(c.grams, totals.grams))}
                              </span>
                            )
                          ) : null}
                        </td>
                        {editable ? (
                          <td className="px-1 py-1">
                            {isTouched(r) ? (
                              <Button
                                type="button"
                                variant="ghost"
                                size="icon"
                                className="desk:size-8 desk:min-h-8"
                                aria-label={`Más opciones de la fila ${n}`}
                                aria-expanded={openRow === r.key}
                                aria-controls={
                                  openRow === r.key ? `${prefix}-opciones-${r.key}` : undefined
                                }
                                onClick={() => setOpenRow(openRow === r.key ? null : r.key)}
                              >
                                <MoreHorizontal aria-hidden="true" />
                              </Button>
                            ) : null}
                          </td>
                        ) : null}
                      </tr>
                      {editable && openRow === r.key ? (
                        <tr
                          id={`${prefix}-opciones-${r.key}`}
                          className="border-b border-line bg-app"
                        >
                          <td colSpan={99} className="px-2 py-3">
                            {/* Fija al borde izquierdo a la vista: con la planilla corrida de costado (con dinero),
                                se abre donde se ve. */}
                            <div className="sticky left-2 flex w-fit flex-wrap items-end gap-4">
                              {r.sub_recipe_id ? null : (
                                <Field id={`${prefix}-base-${r.key}`} label="La cantidad es">
                                  <Select
                                    value={r.basis}
                                    onChange={(e) =>
                                      update(r.key, { basis: e.target.value as QuantityBasis })
                                    }
                                  >
                                    {(Object.keys(BASIS_LABELS) as QuantityBasis[])
                                      .filter((b) => b !== "finished")
                                      .map((b) => (
                                        <option key={b} value={b}>
                                          {BASIS_LABELS[b]}
                                        </option>
                                      ))}
                                  </Select>
                                </Field>
                              )}
                              <Field
                                id={`${prefix}-obs-${r.key}`}
                                label="Observaciones (opcional)"
                                className="min-w-72 flex-1"
                              >
                                <Input
                                  value={r.notes}
                                  maxLength={500}
                                  onChange={(e) => update(r.key, { notes: e.target.value })}
                                />
                              </Field>
                              <Button
                                type="button"
                                variant="outline"
                                onClick={() => removeRow(r.key)}
                              >
                                <Trash2 aria-hidden="true" />
                                Quitar la fila
                              </Button>
                            </div>
                          </td>
                        </tr>
                      ) : null}
                    </Fragment>
                  );
                })}
              </tbody>
              <tfoot className="sticky bottom-0 z-10 bg-app">
                <tr className="font-semibold text-ink shadow-[inset_0_1px_0_var(--color-line)]">
                  <th
                    scope="row"
                    colSpan={2}
                    className="sticky left-0 z-5 bg-app px-2 py-2 text-left shadow-[inset_-1px_0_var(--color-line)]"
                  >
                    <span className="inline-flex flex-wrap items-center gap-2">
                      Total
                      <Badge status={total.status}>{total.label}</Badge>
                    </span>
                  </th>
                  <td colSpan={2} className="px-2 py-2 text-right">
                    {filled.length > 0
                      ? gramsCell(
                          totals.grams,
                          totals.missingGrams === 1
                            ? "Falta 1 fila en gramos."
                            : `Faltan ${totals.missingGrams} filas en gramos.`,
                        )
                      : null}
                  </td>
                  {scaleCols.map((times, col) => (
                    <td key={col} className="px-2 py-2 text-right">
                      {filled.length > 0 ? (
                        <span className="flex flex-col items-end whitespace-nowrap">
                          {gramsCell(scale(totals.grams, times), "Falta un dato.")}
                          {showMoney ? moneyCell(scale(totalCost, times), "Falta un dato.") : null}
                        </span>
                      ) : null}
                    </td>
                  ))}
                  {showMoney && prices ? <td /> : null}
                  {showMoney ? (
                    <td className="px-2 py-2 text-right whitespace-nowrap">
                      {filled.length > 0
                        ? moneyCell(
                            totalCost,
                            `Falta el costo de ${totals.missingCost} ${totals.missingCost === 1 ? "fila" : "filas"}.`,
                          )
                        : null}
                    </td>
                  ) : null}
                  {showMoney ? (
                    <td className="px-2 py-2 text-right whitespace-nowrap tabular-nums">
                      {totalCost !== null ? "100 %" : ""}
                    </td>
                  ) : null}
                  <td className="px-2 py-2 text-right whitespace-nowrap tabular-nums">
                    {totals.grams !== null ? "100 %" : ""}
                  </td>
                  {editable ? <td /> : null}
                </tr>
              </tfoot>
            </table>
          </div>

          {/* Celular: tarjetas de consulta. */}
          <ol className="flex flex-col gap-2 desk:hidden" aria-label="Ingredientes">
            {filled.map((c) => (
              <li key={c.row.key} className="flex flex-col gap-1 rounded-sm border border-line p-3">
                <span className="flex flex-wrap items-center gap-2 font-medium text-ink">
                  {c.row.sub_recipe_id ? (
                    <Link
                      href={`/recetas/${c.row.sub_recipe_id}`}
                      className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline"
                    >
                      {c.row.name}
                    </Link>
                  ) : (
                    c.row.name
                  )}
                  {c.row.sub_recipe_id ? <Badge status="info">Preparación</Badge> : null}
                  {marks[c.row.name] ? <Badge status="review">{marks[c.row.name]}</Badge> : null}
                </span>
                <span className="text-sm text-ink-muted tabular-nums">
                  {c.row.code} · {c.row.quantity} {unitLabel(c.row.unit)}
                  {showMoney && c.cost !== null ? ` · ${formatMoney(c.cost)}` : ""}
                </span>
                {showMoney && c.cost === null ? (
                  <span className="text-sm text-ink">Costo: — {c.costReason}</span>
                ) : null}
              </li>
            ))}
            {filled.length === 0 ? (
              <li className="text-base text-ink-muted">Sin ingredientes.</li>
            ) : null}
          </ol>
        </Tile>

        {/* La columna no impone su alto (va en una capa que ocupa la fila): la fila mide lo que queda de la ventana y el
            procedimiento se achica y muestra los pasos que entren. Las tarjetas llevan 12 px de margen y los controles
            32 px (ADR-0046). */}
        <div className="min-w-0 desk:relative desk:min-h-0">
          {/* Por debajo del alto de diseño (900 px), la columna se desplaza adentro en lugar de encimarse. */}
          <div className="flex min-w-0 flex-col gap-4 desk:absolute desk:inset-0 desk:gap-3 desk:overflow-y-auto">
            {/* Fotos y datos generales. El resto de los datos se edita en su panel, sobre el mismo borrador. */}
            <Tile
              id={anchor("datos")}
              title="Datos generales"
              className="desk:shrink-0 desk:p-3"
              aside={
                <Button
                  type="button"
                  variant="link"
                  size="sm"
                  aria-haspopup="dialog"
                  className={`hidden px-0 desk:inline-flex desk:min-h-8 ${dataPanelChanges > 0 ? "underline decoration-dashed" : ""}`}
                  onClick={() => setPanel("datos")}
                >
                  {ro ? "Ver todos los datos" : "Editar datos"}
                  {dataPanelChanges > 0 ? ` · ${changesLabel(dataPanelChanges)}` : ""}
                </Button>
              }
            >
              <div className="hidden gap-3 desk:flex">
                {photos}
                <div className="grid min-w-0 flex-1 grid-cols-[auto_minmax(0,1fr)] content-start items-center gap-x-2 gap-y-1 text-sm">
                  {ro ? (
                    <span className="text-ink">Rubro</span>
                  ) : (
                    <label htmlFor={`${prefix}-rubro`} className="text-ink">
                      Rubro
                    </label>
                  )}
                  {ro ? (
                    <span className="truncate text-right text-ink">{categoryLabel}</span>
                  ) : (
                    <Select
                      id={`${prefix}-rubro`}
                      value={data.category_id}
                      onChange={(e) => setData({ ...data, category_id: e.target.value })}
                      className={`w-full min-w-0 px-2 desk:h-8 desk:min-h-8 desk:text-sm ${changedInput(data.category_id !== saved.data.category_id)}`}
                    >
                      <option value="">Sin rubro</option>
                      {categories.map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.label}
                        </option>
                      ))}
                    </Select>
                  )}
                  <span className="text-ink">Alcance</span>
                  <span className="truncate text-right text-ink-muted" title={scopeLabel}>
                    {scopeLabel}
                  </span>
                </div>
              </div>
              {/* Celular: consulta. */}
              <div className="flex flex-col gap-3 desk:hidden">
                {mobilePhotos}
                <dl className="flex flex-col gap-2">
                  <ReadRow label="Nombre corto" value={data.short_name} />
                  <ReadRow label="Rubro" value={categoryLabel} />
                  <ReadRow label="Alcance" value={scopeLabel} />
                  <ReadRow label="Sector" value={data.sector} />
                  <ReadRow label="Partida" value={data.station} />
                  <ReadRow label="Tiempo total" value={formatMinutes(totalMinutes)} />
                  <ReadRow label="Conservación" value={draft.storage_notes} />
                  <ReadRow label="Descripción" value={draft.description} />
                  <ReadRow label="Presentación" value={draft.presentation_notes} />
                </dl>
              </div>
            </Tile>

            <Tile
              id={anchor("rendimiento")}
              title="Rendimiento"
              titleExtra={
                <InfoTip label="rendimiento">
                  Las mermas de cada materia prima se cargan en su ficha. Acá va el rendimiento
                  final de la receta.
                </InfoTip>
              }
              className="desk:shrink-0 desk:p-3"
            >
              {/* En la computadora, solo el campo: las porciones, el peso bruto y el rendimiento están en los indicadores
                de arriba y no se repiten (ADR-0046). */}
              {dish ? (
                <div className="flex flex-col gap-2 text-sm">
                  <div className="hidden items-center justify-between gap-2 desk:flex">
                    <label htmlFor={`${prefix}-peso-porcion`} className="text-ink">
                      Peso de la porción (g)
                    </label>
                    <Input
                      id={`${prefix}-peso-porcion`}
                      inputMode="decimal"
                      readOnly={ro}
                      value={draft.portion_grams}
                      className={`w-24 text-right tabular-nums desk:h-8 desk:min-h-8 desk:text-sm ${changedInput(draft.portion_grams !== saved.draft.portion_grams)}`}
                      onChange={(e) => setDraft({ ...draft, portion_grams: e.target.value })}
                    />
                  </div>
                  <dl className="desk:hidden">
                    <ReadRow
                      label="Peso de la porción"
                      value={draft.portion_grams ? `${draft.portion_grams} g` : ""}
                    />
                  </dl>
                  <p className="text-ink-muted desk:hidden">
                    {portions !== null
                      ? `Salen ${formatQuantity(portions)} porciones de ${formatGrams(totals.grams)}.`
                      : manualPortions !== null
                        ? `${formatQuantity(manualPortions)} porciones cargadas a mano.`
                        : "Con el peso de la porción se calculan las porciones."}
                  </p>
                </div>
              ) : (
                <div className="flex flex-col gap-2 text-sm">
                  <div className="flex items-center justify-between gap-2 desk:hidden">
                    <span className="text-ink">Peso bruto (suma)</span>
                    <span className="font-semibold text-ink tabular-nums">
                      {formatGrams(totals.grams)}
                    </span>
                  </div>
                  <div className="hidden items-center justify-between gap-2 desk:flex">
                    <label htmlFor={`${prefix}-peso-neto`} className="text-ink">
                      Peso neto total
                    </label>
                    <span className="flex gap-1">
                      <Input
                        id={`${prefix}-peso-neto`}
                        inputMode="decimal"
                        readOnly={ro}
                        value={draft.yield_quantity}
                        className={`w-20 text-right tabular-nums desk:h-8 desk:min-h-8 desk:text-sm ${changedInput(draft.yield_quantity !== saved.draft.yield_quantity)}`}
                        onChange={(e) => setDraft({ ...draft, yield_quantity: e.target.value })}
                      />
                      <Select
                        aria-label="Unidad"
                        disabled={ro}
                        value={draft.yield_unit}
                        className={`w-20 desk:h-8 desk:min-h-8 desk:text-sm ${changedInput(draft.yield_unit !== saved.draft.yield_unit)}`}
                        onChange={(e) => setDraft({ ...draft, yield_unit: e.target.value })}
                      >
                        <option value="" disabled>
                          Elegí
                        </option>
                        {LINE_UNITS.filter((u) => u.code !== "portion").map((u) => (
                          <option key={u.code} value={u.code}>
                            {u.label}
                          </option>
                        ))}
                      </Select>
                    </span>
                  </div>
                  <dl className="desk:hidden">
                    <ReadRow
                      label="Peso neto total"
                      value={
                        draft.yield_quantity
                          ? `${draft.yield_quantity} ${draft.yield_unit ? unitLabel(draft.yield_unit) : ""}`
                          : ""
                      }
                    />
                  </dl>
                  <p className="text-ink-muted desk:hidden">
                    {ratio !== null
                      ? `Rinde ${formatPct(ratio * 100)}. Contra esto se controlan los lotes.`
                      : "Con el peso neto se calcula el rendimiento."}
                  </p>
                </div>
              )}
            </Tile>

            <Tile
              id={anchor("procedimiento")}
              title="Procedimiento"
              // Sin tooltip: el título y «Editar los N pasos» entran en una línea. La aclaración del tiempo total está en
              // el panel de los pasos.
              aside={
                steps.length > 0 ? (
                  <Button
                    type="button"
                    variant="link"
                    size="sm"
                    aria-haspopup="dialog"
                    className="hidden px-0 desk:inline-flex desk:min-h-8"
                    onClick={() => setPanel("pasos")}
                  >
                    {`${editable ? "Editar" : "Ver"} ${steps.length === 1 ? "el paso" : `los ${steps.length} pasos`}`}
                  </Button>
                ) : editable ? (
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="hidden desk:inline-flex desk:min-h-8"
                    onClick={addStep}
                  >
                    <Plus aria-hidden="true" />
                    Agregar paso
                  </Button>
                ) : undefined
              }
              className="desk:min-h-24 desk:flex-1 desk:p-3"
            >
              {/* Computadora: los pasos que entren en el alto que queda, una línea cada uno; todos se ven y se editan en el
                panel. Los que no entran pasan a una segunda columna que queda oculta: nunca se ve un paso cortado. */}
              {steps.length === 0 ? (
                <p className="hidden text-sm text-ink-muted desk:block">Todavía no tiene pasos.</p>
              ) : (
                <ul
                  aria-label="Pasos"
                  className="hidden min-h-0 flex-1 flex-col flex-wrap content-start overflow-hidden desk:flex"
                >
                  {steps.map((s, index) => {
                    const changed = saved.stepList[index] !== stepsNow[index];
                    return (
                      <li
                        key={s.key}
                        className={`w-full truncate border-b border-line py-1 text-sm text-ink ${changed ? "border-l border-dashed border-l-primary pl-2" : ""}`}
                      >
                        {index + 1}. {s.instructions || "Sin texto todavía."}
                      </li>
                    );
                  })}
                </ul>
              )}
              {/* Celular: todos los pasos, de consulta. */}
              <ol className="flex flex-col gap-3 desk:hidden" aria-label="Pasos">
                {steps.length === 0 ? (
                  <li className="text-base text-ink-muted">Todavía no tiene pasos.</li>
                ) : (
                  steps.map((s, index) => (
                    <li
                      key={s.key}
                      className="flex flex-col gap-1 rounded-sm border border-line p-3"
                    >
                      <span className="font-medium text-ink">
                        {index + 1}. {STEP_KIND_LABELS[s.kind]} ·{" "}
                        {formatMinutes(Number(s.active_minutes) + Number(s.passive_minutes))}
                        {s.equipment ? ` · ${s.equipment}` : ""}
                      </span>
                      <span className="text-ink">{s.instructions}</span>
                    </li>
                  ))
                )}
              </ol>
            </Tile>

            {summary}
          </div>
        </div>
      </div>

      {/* Los paneles: trabajan sobre el mismo borrador; lo cambiado cuenta en la barra y se guarda junto. */}
      <SidePanel
        open={panel === "datos"}
        onOpenChange={(next) => setPanel(next ? "datos" : null)}
        title="Datos generales"
        description={
          ro ? undefined : "Se guardan con «Guardar cambios», junto con el resto de la ficha."
        }
      >
        <div className="grid grid-cols-2 gap-4">
          <TextField
            id={`${prefix}-nombre`}
            label="Nombre"
            value={data.name}
            ro={ro}
            max={120}
            onChange={(v) => setData({ ...data, name: v })}
            changed={data.name !== saved.data.name}
          />
          <TextField
            id={`${prefix}-nombre-corto`}
            label="Nombre corto"
            placeholder="Para la comanda"
            value={data.short_name}
            ro={ro}
            max={40}
            onChange={(v) => setData({ ...data, short_name: v })}
            changed={data.short_name !== saved.data.short_name}
          />
          <TextField
            id={`${prefix}-sector`}
            label="Sector"
            value={data.sector}
            ro={ro}
            max={60}
            onChange={(v) => setData({ ...data, sector: v })}
            changed={data.sector !== saved.data.sector}
          />
          <TextField
            id={`${prefix}-partida`}
            label="Partida"
            value={data.station}
            ro={ro}
            max={60}
            onChange={(v) => setData({ ...data, station: v })}
            changed={data.station !== saved.data.station}
          />
          <Field id={`${prefix}-tiempo`} label="Tiempo total" hint="Sale de los pasos.">
            <Input readOnly value={formatMinutes(totalMinutes)} />
          </Field>
          <AreaField
            id={`${prefix}-conservacion`}
            label="Conservación"
            placeholder="Por ejemplo: 3 días en cámara a 4 °C"
            value={draft.storage_notes}
            ro={ro}
            max={2000}
            onChange={(v) => setDraft({ ...draft, storage_notes: v })}
            changed={draft.storage_notes !== saved.draft.storage_notes}
          />
          <AreaField
            id={`${prefix}-descripcion`}
            label="Descripción"
            placeholder="Qué es y cómo se presenta"
            value={draft.description}
            ro={ro}
            max={2000}
            onChange={(v) => setDraft({ ...draft, description: v })}
            changed={draft.description !== saved.draft.description}
          />
          <AreaField
            id={`${prefix}-presentacion`}
            label="Presentación"
            value={draft.presentation_notes}
            ro={ro}
            max={2000}
            onChange={(v) => setDraft({ ...draft, presentation_notes: v })}
            changed={draft.presentation_notes !== saved.draft.presentation_notes}
          />
          <AreaField
            id={`${prefix}-cambio`}
            label="Qué cambió en esta versión"
            value={draft.change_summary}
            ro={ro}
            max={1000}
            onChange={(v) => setDraft({ ...draft, change_summary: v })}
            changed={draft.change_summary !== saved.draft.change_summary}
          />
        </div>
        <Button type="button" variant="outline" className="self-end" onClick={() => setPanel(null)}>
          Listo
        </Button>
      </SidePanel>

      <SidePanel
        open={panel === "pasos"}
        onOpenChange={(next) => setPanel(next ? "pasos" : null)}
        title="Procedimiento"
        description={
          ro
            ? "El tiempo total cuenta los pasos que se esperan entre sí; los que van en paralelo no se suman."
            : "Se guardan con «Guardar cambios», junto con el resto de la ficha. El tiempo total cuenta los pasos que se esperan entre sí."
        }
        className="desk:w-[60rem]"
      >
        {steps.length === 0 ? (
          <p className="text-base text-ink-muted">Todavía no tiene pasos.</p>
        ) : null}
        <ol className="flex flex-col gap-3" aria-label="Pasos">
          {stepCards}
        </ol>
        {editable ? (
          <div className="flex flex-wrap justify-between gap-2">
            <Button type="button" variant="outline" className="border-dashed" onClick={addStep}>
              <Plus aria-hidden="true" />
              Agregar paso
            </Button>
            <Button type="button" variant="outline" onClick={() => setPanel(null)}>
              Listo
            </Button>
          </div>
        ) : null}
      </SidePanel>

      {/* La barra fija: un solo guardado para toda la ficha (ADR-0039). Solo en la computadora. */}
      {editable ? (
        <div className="sticky bottom-0 z-10 -mx-gutter hidden flex-col gap-2 border-t border-line bg-surface px-gutter py-2 desk:flex wide:-mx-gutter-wide wide:px-gutter-wide">
          <FormNotice state={state} />
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-base text-ink" role="status">
              <span className="font-semibold">{changesLabel(changes)}</span>
              {version.status === "published" && changes > 0
                ? " · se guardan en un borrador nuevo"
                : ""}
            </span>
            {/* El último guardado, al lado del contador (se va con el próximo cambio). */}
            <div className="mr-auto">
              {notice && changes === 0 ? (
                <Notice status={notice.status} className="items-center px-3 py-1 text-sm">
                  {notice.text}
                </Notice>
              ) : null}
            </div>
            <label htmlFor={`${prefix}-motivo`} className="text-sm font-medium text-ink">
              Motivo<span className="sr-only"> de los cambios</span>
            </label>
            <span aria-hidden="true" className="-ml-1 text-sm font-medium text-ink">
              *
            </span>
            <Input
              id={`${prefix}-motivo`}
              placeholder="Obligatorio: por qué cambia"
              aria-required="true"
              className="w-80"
              maxLength={500}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
            <Button
              type="button"
              variant="outline"
              disabled={pending || changes === 0}
              onClick={discard}
            >
              Descartar
            </Button>
            <Button
              type="button"
              disabled={pending || changes === 0}
              onClick={() => void save(false)}
            >
              {pending ? "Guardando…" : "Guardar cambios"}
            </Button>
            {canSubmit ? (
              <Button
                type="button"
                variant="outline"
                disabled={pending}
                onClick={() => void save(true)}
              >
                Enviar a revisión
              </Button>
            ) : null}
          </div>
        </div>
      ) : review ? (
        <ReviewBox
          variant="bar"
          recipeId={recipe.id}
          requestId={review.requestId}
          versionNumber={version.number}
          changes={review.changes}
          removed={review.removed}
        />
      ) : null}
    </TooltipProvider>
  );
}

// La etiqueta «Preparación» de una fila es también el enlace a su ficha.
function PrepLink({ id, name }: { id: string; name: string }) {
  return (
    <Link
      href={`/recetas/${id}`}
      aria-label={`Abrir la preparación ${name}`}
      className="inline-flex shrink-0 items-center rounded-sm bg-info px-2 py-0.5 text-xs font-medium text-info-ink underline-offset-4 hover:underline"
    >
      Preparación
    </Link>
  );
}

function ReadRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col">
      <dt className="text-sm font-medium text-ink">{label}</dt>
      <dd className="text-base break-words text-ink-muted">{value || "—"}</dd>
    </div>
  );
}

function TextField(props: {
  id: string;
  label: string;
  value: string;
  ro: boolean;
  max: number;
  placeholder?: string;
  changed: boolean;
  onChange: (v: string) => void;
}) {
  return (
    <Field id={props.id} label={props.label}>
      <Input
        readOnly={props.ro}
        maxLength={props.max}
        placeholder={props.placeholder}
        value={props.value}
        className={props.changed ? "border-dashed border-primary" : undefined}
        onChange={(e) => props.onChange(e.target.value)}
      />
    </Field>
  );
}

function AreaField(props: {
  id: string;
  label: string;
  value: string;
  ro: boolean;
  max: number;
  placeholder?: string;
  changed: boolean;
  onChange: (v: string) => void;
}) {
  return (
    <Field id={props.id} label={props.label} className="col-span-full desk:col-span-2">
      <Textarea
        readOnly={props.ro}
        maxLength={props.max}
        placeholder={props.placeholder}
        value={props.value}
        className={props.changed ? "border-dashed border-primary" : undefined}
        onChange={(e) => props.onChange(e.target.value)}
      />
    </Field>
  );
}

function StepCard({
  prefix,
  step,
  index,
  previous,
  ro,
  yieldLabel,
  changed,
  onChange,
  onRemove,
}: {
  prefix: string;
  step: Step;
  index: number;
  previous: Step[];
  ro: boolean;
  yieldLabel?: string;
  changed: boolean;
  onChange: (change: Partial<Step>) => void;
  onRemove: () => void;
}) {
  const id = (field: string) => `${prefix}-paso-${step.key}-${field}`;
  const n = index + 1;
  if (ro) {
    return (
      <li className="flex flex-col gap-1 rounded-sm border border-line p-3">
        <span className="font-medium text-ink">
          {n}. {STEP_KIND_LABELS[step.kind]} ·{" "}
          {formatMinutes(Number(step.active_minutes) + Number(step.passive_minutes))}
          {step.equipment ? ` · ${step.equipment}` : ""}
        </span>
        <span className="text-ink">{step.instructions}</span>
      </li>
    );
  }
  return (
    <li
      className={`flex flex-col gap-3 rounded-sm border p-3 ${changed ? "border-dashed border-primary" : "border-line"}`}
    >
      {/* Celular: consulta. */}
      <div className="flex flex-col gap-1 desk:hidden">
        <span className="font-medium text-ink">
          {n}. {STEP_KIND_LABELS[step.kind]}
        </span>
        <span className="text-ink">{step.instructions}</span>
      </div>
      <div className="hidden grid-cols-[2.5rem_3fr_repeat(4,minmax(0,1fr))_auto] items-start gap-3 desk:grid">
        <span
          aria-hidden="true"
          className="mt-7 flex size-control items-center justify-center rounded-full bg-app font-semibold text-ink"
        >
          {n}
        </span>
        <Field id={id("que")} label={`Qué se hace (paso ${n})`}>
          <Textarea
            value={step.instructions}
            maxLength={2000}
            rows={2}
            onChange={(e) => onChange({ instructions: e.target.value })}
          />
        </Field>
        <Field id={id("tipo")} label="Tipo">
          <Select
            value={step.kind}
            onChange={(e) => onChange({ kind: e.target.value as StepKind })}
          >
            {(Object.keys(STEP_KIND_LABELS) as StepKind[]).map((k) => (
              <option key={k} value={k}>
                {STEP_KIND_LABELS[k]}
              </option>
            ))}
          </Select>
        </Field>
        <Field id={id("activos")} label="Minutos trabajando">
          <Input
            inputMode="numeric"
            value={step.active_minutes}
            onChange={(e) => onChange({ active_minutes: e.target.value })}
          />
        </Field>
        <Field id={id("espera")} label="Minutos de espera">
          <Input
            inputMode="numeric"
            value={step.passive_minutes}
            onChange={(e) => onChange({ passive_minutes: e.target.value })}
          />
        </Field>
        <Field id={id("equipo")} label="Equipo">
          <Input
            value={step.equipment}
            maxLength={120}
            onChange={(e) => onChange({ equipment: e.target.value })}
          />
        </Field>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="mt-7"
          aria-label={`Quitar el paso ${n}`}
          onClick={onRemove}
        >
          <Trash2 aria-hidden="true" />
        </Button>
      </div>
      <details className="hidden desk:block">
        <summary className="flex min-h-control cursor-pointer items-center text-sm text-primary underline-offset-4 hover:underline">
          Capacidad del equipo y orden
        </summary>
        <div className="flex flex-wrap items-end gap-4 pt-2">
          <Field
            id={id("capacidad")}
            label={`Capacidad del equipo (${LINE_UNITS.find((u) => u.code === step.capacity_unit)?.label ?? yieldLabel ?? "unidad del rendimiento"})`}
            hint="Opcional. Cuánto entra de una vez: avisa si hacen falta más tandas."
          >
            <Input
              inputMode="decimal"
              disabled={!step.capacity_unit && !yieldLabel}
              value={step.equipment_capacity}
              onChange={(e) => onChange({ equipment_capacity: e.target.value })}
            />
          </Field>
          {previous.length > 0 ? (
            <fieldset className="flex flex-col gap-2">
              <legend className="text-sm font-medium text-ink">Empieza cuando terminan</legend>
              <div className="flex flex-wrap gap-x-4">
                {previous.map((o, i) => (
                  <Checkbox
                    key={o.key}
                    id={`${prefix}-espera-${step.key}-${o.key}`}
                    label={`Paso ${i + 1}`}
                    checked={step.depends.includes(o.key)}
                    onChange={(e) =>
                      onChange({
                        depends: e.target.checked
                          ? [...step.depends, o.key]
                          : step.depends.filter((d) => d !== o.key),
                      })
                    }
                  />
                ))}
              </div>
            </fieldset>
          ) : null}
        </div>
      </details>
    </li>
  );
}
