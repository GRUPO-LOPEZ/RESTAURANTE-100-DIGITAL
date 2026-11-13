"use client";

import { Fragment, useEffect, useId, useRef, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { MoreHorizontal, Plus, Trash2 } from "lucide-react";

import {
  previewSheetLinesAction,
  saveSheetAction,
  searchComponentsAction,
  unitOptionsAction,
  type ComponentFound,
} from "@/app/recetas/actions";
import { FormNotice } from "@/components/form-notice";
import { Missing } from "@/components/recipe-sheet/missing";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
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
  costPerNetKg,
  countChanges,
  formatGrams,
  formatPct,
  incidence,
  missingReason,
  parseTimes,
  perPortion,
  portionsFrom,
  scale,
  sheetTotals,
  toGrams,
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
  anchor: { top: number; left: number; width: number };
  inputId: string;
};

const comma = (n: number | null) => (n === null ? "" : String(n).replace(".", ","));
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

// La ficha única de una receta (ADR-0042): datos, ingredientes y costos, rendimiento y procedimiento en una sola
// pantalla, con una barra fija que guarda todo junto (una transacción, un motivo). En la computadora se edita donde
// se ve; en el celular es de consulta. Los costos los calcula la base fila por fila mientras se escribe.
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
  // Lo que cambió contra la versión anterior, por nombre (para quien revisa).
  marks: Record<string, "added" | "changed">;
  times: [number, number];
  // Lo que se agrega al id de cada sección (único por receta: Next guarda oculta la ficha anterior). Va como texto:
  // una función no puede pasar de un componente de servidor a uno de cliente.
  anchorSuffix: string;
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

  // La lista de sugerencias flota sobre la página: si la página o la tabla se mueven, sigue al campo.
  const searchInput = search?.inputId;
  useEffect(() => {
    if (!searchInput) return;
    const follow = () =>
      setSearch((s) => {
        const box = s ? document.getElementById(s.inputId)?.getBoundingClientRect() : undefined;
        return s && box
          ? { ...s, anchor: { top: box.bottom, left: box.left, width: Math.max(box.width, 320) } }
          : s;
      });
    window.addEventListener("scroll", follow, true);
    window.addEventListener("resize", follow);
    return () => {
      window.removeEventListener("scroll", follow, true);
      window.removeEventListener("resize", follow);
    };
  }, [searchInput]);

  // Buscador de cada fila, por código o por nombre, desde 3 letras. Solo cuenta la última respuesta.
  useEffect(() => {
    if (!search || search.status !== "searching") return;
    const seq = ++searchSeq.current;
    const timer = setTimeout(() => {
      searchComponentsAction(search.query, recipe.id)
        .catch(() => ({ status: "error" as const }))
        .then((r) => {
          if (seq !== searchSeq.current) return;
          setSearch((s) =>
            s && s.query === search.query
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
    return () => clearTimeout(timer);
  }, [search, recipe.id]);

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
            anchor: { top: box.bottom, left: box.left, width: Math.max(box.width, 320) },
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

  return (
    <TooltipProvider>
      {/* 2. Datos generales */}
      <Card id={anchor("datos")} className="flex scroll-mt-24 flex-col gap-4">
        <CardTitle>Datos generales</CardTitle>
        <div className="hidden grid-cols-[repeat(auto-fill,minmax(14rem,1fr))] gap-4 desk:grid">
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
          <Field id={`${prefix}-rubro`} label="Rubro">
            {ro ? (
              <Input
                readOnly
                value={categories.find((c) => c.id === data.category_id)?.label ?? "—"}
              />
            ) : (
              <Select
                value={data.category_id}
                onChange={(e) => setData({ ...data, category_id: e.target.value })}
                className={
                  data.category_id !== saved.data.category_id
                    ? "border-dashed border-primary"
                    : undefined
                }
              >
                <option value="">Sin rubro</option>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.label}
                  </option>
                ))}
              </Select>
            )}
          </Field>
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
        {/* Celular: consulta. */}
        <dl className="flex flex-col gap-2 desk:hidden">
          <ReadRow label="Nombre corto" value={data.short_name} />
          <ReadRow
            label="Rubro"
            value={categories.find((c) => c.id === data.category_id)?.label ?? ""}
          />
          <ReadRow label="Sector" value={data.sector} />
          <ReadRow label="Partida" value={data.station} />
          <ReadRow label="Tiempo total" value={formatMinutes(totalMinutes)} />
          <ReadRow label="Conservación" value={draft.storage_notes} />
          <ReadRow label="Descripción" value={draft.description} />
          <ReadRow label="Presentación" value={draft.presentation_notes} />
        </dl>
      </Card>

      {/* 3. Ingredientes y costos */}
      <Card id={anchor("ingredientes")} className="flex scroll-mt-24 flex-col gap-4">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <CardTitle>Ingredientes y costos</CardTitle>
          <span className="text-sm text-ink-muted" role="status">
            {calculating
              ? "Calculando…"
              : money
                ? place
                  ? `Precios de ${place.name}, sin IVA.`
                  : "Elegí un local arriba para ver los costos."
                : editable
                  ? "10 filas listas; al completar la última se agrega otra."
                  : ""}
          </span>
        </div>

        {previewFailed ? (
          <Notice status="warn" role="status">
            No pudimos calcular los pesos y los costos. Probá de nuevo en un momento.
          </Notice>
        ) : null}
        {/* Computadora: la planilla. */}
        <div className="relative hidden w-0 min-w-full overflow-x-auto desk:block">
          <table className="w-full border-collapse text-sm" aria-label="Ingredientes y costos">
            <thead>
              <tr className="border-b border-line text-left text-ink-muted">
                <th scope="col" rowSpan={2} className="w-10 px-2 py-2 font-medium">
                  <abbr title="Número de fila" className="no-underline">
                    #
                  </abbr>
                </th>
                <th scope="col" rowSpan={2} className="w-28 px-2 py-2 font-medium">
                  Código
                </th>
                <th scope="col" rowSpan={2} className="px-2 py-2 font-medium">
                  Ingrediente
                </th>
                <th scope="col" rowSpan={2} className="w-20 px-2 py-2 text-right font-medium">
                  Cantidad
                </th>
                <th scope="col" rowSpan={2} className="w-28 px-2 py-2 font-medium">
                  Medida
                </th>
                {[0, 1].map((col) => (
                  <th
                    key={col}
                    scope="colgroup"
                    colSpan={showMoney ? 2 : 1}
                    className="bg-app px-2 py-2 text-center font-medium"
                  >
                    <span className="flex flex-col items-center gap-1">
                      <span className="inline-flex items-center gap-1">
                        Hacer
                        <Input
                          aria-label={`Cantidad de recetas, columna ${col === 0 ? "A" : "B"}`}
                          inputMode="numeric"
                          className="h-control-sm w-14 text-center"
                          value={timesText[col]}
                          onChange={(e) =>
                            setTimesText((t) =>
                              col === 0 ? [e.target.value, t[1]] : [t[0], e.target.value],
                            )
                          }
                        />
                      </span>
                      recetas
                    </span>
                  </th>
                ))}
                {showMoney && prices ? (
                  <th scope="col" rowSpan={2} className="w-28 px-2 py-2 text-right font-medium">
                    Precio por kg o l
                  </th>
                ) : null}
                {showMoney ? (
                  <th scope="col" rowSpan={2} className="w-28 px-2 py-2 text-right font-medium">
                    Costo en la receta
                  </th>
                ) : null}
                {showMoney ? (
                  <th scope="col" rowSpan={2} className="w-20 px-2 py-2 text-right font-medium">
                    Incidencia $
                  </th>
                ) : null}
                <th scope="col" rowSpan={2} className="w-20 px-2 py-2 text-right font-medium">
                  Incidencia peso
                </th>
                {editable ? (
                  <th scope="col" rowSpan={2} className="w-12 px-2 py-2">
                    <span className="sr-only">Más opciones</span>
                  </th>
                ) : null}
              </tr>
              <tr className="border-b border-line text-ink-muted">
                {[0, 1].flatMap((col) => [
                  <th
                    key={`g${col}`}
                    scope="col"
                    className="bg-app px-2 py-1 text-right font-medium"
                  >
                    Peso bruto
                  </th>,
                  showMoney ? (
                    <th
                      key={`c${col}`}
                      scope="col"
                      className="bg-app px-2 py-1 text-right font-medium"
                    >
                      Costo
                    </th>
                  ) : null,
                ])}
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
                    <tr className="border-b border-line align-top">
                      <td className="px-2 py-2 text-ink-muted tabular-nums">{n}</td>
                      <td className="relative px-2 py-1">
                        {ro ? (
                          <span className="text-ink tabular-nums">{r.code}</span>
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
                            className="h-control-sm"
                            value={r.code}
                            onChange={(e) => typeIn(r.key, "code", e.currentTarget)}
                            onKeyDown={(e) => onSearchKey(e, r.key)}
                            onBlur={() => setSearch(null)}
                          />
                        )}
                      </td>
                      <td className="relative px-2 py-1">
                        {ro ? (
                          <span className="flex flex-wrap items-center gap-2 text-ink">
                            {r.name}
                            {r.sub_recipe_id ? (
                              <PrepLink id={r.sub_recipe_id} name={r.name} />
                            ) : null}
                            {mark ? (
                              <Badge status="review">{mark === "added" ? "Nueva" : "Cambió"}</Badge>
                            ) : null}
                          </span>
                        ) : (
                          <div className="flex items-center gap-2">
                            <Input
                              id={`${prefix}-ingrediente-${r.key}`}
                              aria-label={`Ingrediente, fila ${n}`}
                              role="combobox"
                              aria-expanded={open && search?.field === "name"}
                              aria-controls={open && search?.field === "name" ? listId : undefined}
                              aria-activedescendant={active("name")}
                              aria-autocomplete="list"
                              autoComplete="off"
                              placeholder="Escribí para buscar"
                              className="h-control-sm"
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
                            // Fija debajo del campo: la tabla se desplaza de costado y no la recorta.
                            style={{
                              top: search.anchor.top,
                              left: search.anchor.left,
                              width: search.anchor.width,
                            }}
                            className="fixed z-30 flex max-h-72 flex-col overflow-y-auto rounded-sm border border-line bg-surface shadow-sm"
                          >
                            {search.items.map((item, i) => (
                              <li
                                key={`${item.kind}-${item.id}`}
                                id={`${listId}-${i}`}
                                role="option"
                                aria-selected={i === search.active}
                                className={`flex min-h-control cursor-pointer flex-wrap items-center gap-2 px-3 py-2 text-ink ${i === search.active ? "bg-nav-active" : ""}`}
                                onMouseDown={(e) => {
                                  e.preventDefault();
                                  choose(r.key, item);
                                }}
                              >
                                <span>{item.name}</span>
                                <span className="text-ink-muted tabular-nums">· {item.code}</span>
                                {item.kind === "preparation" ? (
                                  <Badge status="info">Preparación</Badge>
                                ) : null}
                              </li>
                            ))}
                          </ul>
                        ) : open && search ? (
                          <p
                            role="status"
                            style={{
                              top: search.anchor.top,
                              left: search.anchor.left,
                              width: search.anchor.width,
                            }}
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
                          <span className="tabular-nums">{r.quantity}</span>
                        ) : (
                          <Input
                            id={`${prefix}-cantidad-${r.key}`}
                            aria-label={`Cantidad, fila ${n}`}
                            inputMode="decimal"
                            className="h-control-sm text-right tabular-nums"
                            value={r.quantity}
                            onChange={(e) => update(r.key, { quantity: e.target.value })}
                          />
                        )}
                      </td>
                      <td className="px-2 py-1">
                        {ro ? (
                          <span>{unitLabel(r.unit)}</span>
                        ) : (
                          <Select
                            id={`${prefix}-medida-${r.key}`}
                            aria-label={`Medida, fila ${n}`}
                            className="h-control-sm"
                            value={r.unit}
                            onChange={(e) => update(r.key, { unit: e.target.value as LineUnit })}
                          >
                            <option value="" disabled>
                              Elegí
                            </option>
                            {units.map((u) => (
                              <option key={u.code} value={u.code}>
                                {unitOptionLabel(u.code)}
                              </option>
                            ))}
                          </Select>
                        )}
                      </td>
                      {scaleCols.flatMap((times, col) => [
                        <td key={`g${col}`} className="bg-app px-2 py-2 text-right">
                          {c.filled
                            ? gramsCell(
                                scale(c.grams, times),
                                times === null ? "Escribí cuántas recetas." : c.gramsReason,
                              )
                            : null}
                        </td>,
                        showMoney ? (
                          <td key={`c${col}`} className="bg-app px-2 py-2 text-right">
                            {c.filled
                              ? moneyCell(
                                  scale(c.cost, times),
                                  times === null ? "Escribí cuántas recetas." : c.costReason,
                                )
                              : null}
                          </td>
                        ) : null,
                      ])}
                      {showMoney && prices ? (
                        <td className="px-2 py-2 text-right">
                          {c.filled ? (
                            c.price ? (
                              <span className="tabular-nums">
                                {formatMoney(c.price.value)} / {c.price.unit}
                              </span>
                            ) : (
                              <Missing reason={c.costReason} />
                            )
                          ) : null}
                        </td>
                      ) : null}
                      {showMoney ? (
                        <td className="px-2 py-2 text-right">
                          {c.filled ? moneyCell(c.cost, c.costReason) : null}
                        </td>
                      ) : null}
                      {showMoney ? (
                        <td className="px-2 py-2 text-right tabular-nums">
                          {c.filled ? (
                            totalCost === null ? (
                              <Missing reason="Falta el costo total: alguna fila no tiene costo." />
                            ) : c.cost === null ? (
                              <Missing reason={c.costReason} />
                            ) : (
                              formatPct(incidence(c.cost, totalCost))
                            )
                          ) : null}
                        </td>
                      ) : null}
                      <td className="px-2 py-2 text-right tabular-nums">
                        {c.filled ? (
                          totals.grams === null ? (
                            <Missing reason="Falta el peso total: alguna fila no se pasa a gramos." />
                          ) : c.grams === null ? (
                            <Missing reason={c.gramsReason} />
                          ) : (
                            formatPct(incidence(c.grams, totals.grams))
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
                              aria-label={`Más opciones de la fila ${n}`}
                              aria-expanded={openRow === r.key}
                              onClick={() => setOpenRow(openRow === r.key ? null : r.key)}
                            >
                              <MoreHorizontal aria-hidden="true" />
                            </Button>
                          ) : null}
                        </td>
                      ) : null}
                    </tr>
                    {editable && openRow === r.key ? (
                      <tr className="border-b border-line bg-app">
                        <td />
                        <td colSpan={99} className="px-2 py-3">
                          <div className="flex flex-wrap items-end gap-4">
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
            <tfoot>
              <tr className="bg-app font-semibold text-ink">
                <td />
                <td />
                <th scope="row" className="px-2 py-2 text-left">
                  Total
                </th>
                <td className="px-2 py-2 text-right">
                  {filled.length > 0
                    ? gramsCell(totals.grams, `Faltan ${totals.missingGrams} filas en gramos.`)
                    : null}
                </td>
                <td />
                {scaleCols.flatMap((times, col) => [
                  <td key={`g${col}`} className="px-2 py-2 text-right">
                    {filled.length > 0
                      ? gramsCell(scale(totals.grams, times), "Falta un dato.")
                      : null}
                  </td>,
                  showMoney ? (
                    <td key={`c${col}`} className="px-2 py-2 text-right">
                      {filled.length > 0
                        ? moneyCell(scale(totalCost, times), "Falta un dato.")
                        : null}
                    </td>
                  ) : null,
                ])}
                {showMoney && prices ? <td /> : null}
                {showMoney ? (
                  <td className="px-2 py-2 text-right">
                    {filled.length > 0
                      ? moneyCell(totalCost, `Falta el costo de ${totals.missingCost} filas.`)
                      : null}
                  </td>
                ) : null}
                {showMoney ? (
                  <td className="px-2 py-2 text-right tabular-nums">
                    {totalCost !== null ? "100 %" : ""}
                  </td>
                ) : null}
                <td className="px-2 py-2 text-right tabular-nums">
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
                    className="text-primary underline-offset-4 hover:underline"
                  >
                    {c.row.name}
                  </Link>
                ) : (
                  c.row.name
                )}
                {c.row.sub_recipe_id ? <Badge status="info">Preparación</Badge> : null}
              </span>
              <span className="text-sm text-ink-muted tabular-nums">
                {c.row.code} · {c.row.quantity} {unitLabel(c.row.unit)}
                {showMoney && c.cost !== null ? ` · ${formatMoney(c.cost)}` : ""}
              </span>
              {showMoney && c.cost === null ? (
                <span className="text-sm text-warn-ink">Costo: — {c.costReason}</span>
              ) : null}
            </li>
          ))}
          {filled.length === 0 ? (
            <li className="text-base text-ink-muted">Sin ingredientes.</li>
          ) : null}
        </ol>

        <div className="grid gap-4 desk:grid-cols-2">
          <Metric
            label="Peso total de la receta"
            value={totals.grams === null ? null : formatGrams(totals.grams)}
            missingReason={
              filled.length === 0
                ? "Todavía no tiene ingredientes."
                : `Incompleto: ${totals.missingGrams} ${totals.missingGrams === 1 ? "fila no se pasa" : "filas no se pasan"} a gramos.`
            }
            status="ok"
            statusLabel="Calculado"
            emptyLabel="Sin datos"
          />
          {money ? (
            <Metric
              label="Costo total de la receta, sin IVA"
              value={totalCost === null ? null : formatMoney(totalCost)}
              missingReason={
                !place
                  ? "Elegí un local arriba para ver el costo."
                  : filled.length === 0
                    ? "Todavía no tiene ingredientes."
                    : `Incompleto: falta el costo de ${totals.missingCost} ${totals.missingCost === 1 ? "fila" : "filas"}.`
              }
              period={place?.name}
              status="ok"
              statusLabel="Calculado"
              emptyLabel="Sin datos"
            />
          ) : null}
        </div>
      </Card>

      {/* 4. Rendimiento */}
      <Card id={anchor("rendimiento")} className="flex scroll-mt-24 flex-col gap-4">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <CardTitle>Rendimiento</CardTitle>
          <CardDescription>
            Las mermas de cada materia prima se cargan en su ficha. Acá va el rendimiento final de
            la receta.
          </CardDescription>
        </div>
        {dish ? (
          <div className="grid gap-4 desk:grid-cols-3">
            {/* En el celular la ficha es de consulta: el peso se lee, no se edita. */}
            <dl className="desk:hidden">
              <ReadRow
                label="Peso de la porción"
                value={draft.portion_grams ? `${draft.portion_grams} g` : ""}
              />
            </dl>
            <Field
              id={`${prefix}-peso-porcion`}
              label="Peso de la porción (g)"
              className="hidden desk:flex"
            >
              <Input
                inputMode="decimal"
                readOnly={ro}
                value={draft.portion_grams}
                className={
                  draft.portion_grams !== saved.draft.portion_grams
                    ? "border-dashed border-primary"
                    : undefined
                }
                onChange={(e) => setDraft({ ...draft, portion_grams: e.target.value })}
              />
            </Field>
            <Metric
              label="Porciones que salen"
              value={
                portions !== null
                  ? formatQuantity(portions)
                  : manualPortions !== null
                    ? formatQuantity(manualPortions)
                    : null
              }
              unit={manualPortions !== null && portions === null ? "cargadas a mano" : undefined}
              missingReason={
                !draft.portion_grams
                  ? "Sin peso de porción."
                  : portionGrams === null || portionGrams <= 0
                    ? "Revisá el peso de la porción."
                    : filled.length === 0
                      ? "Todavía no tiene ingredientes."
                      : "Falta pasar algún ingrediente a gramos."
              }
              status={portions !== null ? "ok" : "info"}
              statusLabel={portions !== null ? "Peso total ÷ porción" : "Cargadas a mano"}
              emptyLabel="Sin datos"
            />
            {money ? (
              <Metric
                label="Costo por porción"
                value={(() => {
                  const v = perPortion(totalCost, portions ?? manualPortions);
                  return v === null ? null : formatMoney(v);
                })()}
                missingReason="Falta el costo total o las porciones."
                period={place?.name}
                status="ok"
                statusLabel="Calculado"
                emptyLabel="Sin datos"
              />
            ) : null}
          </div>
        ) : (
          <div className="grid gap-4 desk:grid-cols-4">
            <Metric
              label="Peso bruto total"
              value={totals.grams === null ? null : formatGrams(totals.grams)}
              missingReason="Falta pasar algún ingrediente a gramos."
              status="ok"
              statusLabel="Suma de los ingredientes"
              emptyLabel="Sin datos"
            />
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
            <div className="hidden flex-col gap-2 desk:flex">
              <div className="flex gap-2">
                <Field
                  id={`${prefix}-peso-neto`}
                  label="Peso neto total"
                  hint="Lo que queda al terminar."
                  className="flex-1"
                >
                  <Input
                    inputMode="decimal"
                    readOnly={ro}
                    value={draft.yield_quantity}
                    className={
                      draft.yield_quantity !== saved.draft.yield_quantity
                        ? "border-dashed border-primary"
                        : undefined
                    }
                    onChange={(e) => setDraft({ ...draft, yield_quantity: e.target.value })}
                  />
                </Field>
                <Field id={`${prefix}-peso-neto-unidad`} label="Unidad" className="w-28">
                  <Select
                    disabled={ro}
                    value={draft.yield_unit}
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
                </Field>
              </div>
            </div>
            <Metric
              label="Rendimiento (neto ÷ bruto)"
              value={ratio === null ? null : formatPct(ratio * 100)}
              missingReason={
                !draft.yield_quantity
                  ? "Sin peso neto."
                  : netGrams === null
                    ? "Rinde en volumen o en unidades: se calcula solo en peso."
                    : "Falta pasar algún ingrediente a gramos."
              }
              status="info"
              statusLabel="Objetivo para el control de lotes"
              emptyLabel="Sin datos"
            />
            {money ? (
              <Metric
                label="Costo por kg neto"
                value={(() => {
                  const v = costPerNetKg(totalCost, netGrams);
                  return v === null ? null : formatMoney(v);
                })()}
                missingReason="Falta el costo total o el peso neto en peso."
                period={place?.name}
                status="ok"
                statusLabel="Calculado"
                emptyLabel="Sin datos"
              />
            ) : null}
          </div>
        )}
      </Card>

      {/* 5. Procedimiento */}
      <Card id={anchor("procedimiento")} className="flex scroll-mt-24 flex-col gap-4">
        <CardTitle>Procedimiento</CardTitle>
        <CardDescription>
          El tiempo total cuenta los pasos que se esperan entre sí; los que van en paralelo no se
          suman.
        </CardDescription>
        {steps.length === 0 ? (
          <p className="text-base text-ink-muted">Todavía no tiene pasos.</p>
        ) : null}
        <ol className="flex flex-col gap-3" aria-label="Pasos">
          {steps.map((s, index) => (
            <StepCard
              key={s.key}
              prefix={prefix}
              step={s}
              index={index}
              previous={steps.slice(0, index)}
              ro={ro}
              yieldLabel={
                dish
                  ? draft.portion_grams || draft.yield_unit
                    ? "porción"
                    : undefined
                  : draft.yield_unit
                    ? unitLabel(draft.yield_unit)
                    : undefined
              }
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
          ))}
        </ol>
        {editable ? (
          <Button
            type="button"
            variant="outline"
            className="hidden self-start border-dashed desk:inline-flex"
            onClick={() => {
              const previous = steps.at(-1);
              setSteps((all) => [
                ...all,
                {
                  key: nextStep,
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
              setTimeout(() => document.getElementById(`${prefix}-paso-${nextStep}-que`)?.focus());
            }}
          >
            <Plus aria-hidden="true" />
            Agregar paso
          </Button>
        ) : null}
      </Card>

      {/* La barra fija: un solo guardado para toda la ficha (ADR-0039). Solo en la computadora. */}
      {editable ? (
        <div className="sticky bottom-0 z-10 -mx-gutter hidden flex-col gap-2 border-t border-line bg-surface px-gutter py-3 desk:flex wide:-mx-gutter-wide wide:px-gutter-wide">
          <FormNotice state={state} />
          <div className="flex flex-wrap items-center gap-2">
            <span className="mr-auto text-base text-ink" role="status">
              <span className="font-semibold">{changesLabel(changes)}</span>
              {version.status === "published" && changes > 0
                ? " · se guardan en un borrador nuevo"
                : ""}
            </span>
            <label htmlFor={`${prefix}-motivo`} className="text-sm font-medium text-ink">
              Motivo<span className="sr-only"> de los cambios</span>
            </label>
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
