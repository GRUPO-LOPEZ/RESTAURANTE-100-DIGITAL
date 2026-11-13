"use client";

import { createContext, useContext, useId, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Plus, X } from "lucide-react";

import { saveIngredientSheetAction } from "@/app/materias-primas/actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input, Select, Textarea } from "@/components/ui/field";
import { InfoTip } from "@/components/ui/info-tip";
import { Segmented } from "@/components/ui/segmented";
import { ToggleField } from "@/components/ui/toggle-field";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { ingredientSheetSchema, reasonField } from "@/lib/forms/schemas";
import {
  CONVERSION_KINDS,
  countSheetChanges,
  sheetChanges,
  sheetPayload,
  splitAliases,
  type IngredientSheetDraft,
  type SheetChanges,
  type SheetConversion,
} from "@/lib/ingredient-sheet";
import type { AllergenStatus, ConversionKind, DataSource } from "@/lib/catalog";
import { changesLabel } from "@/lib/recipe-sheet";
import { cn } from "@/lib/utils";

// Ficha única de materia prima (ADR-0043). La página (del servidor) pone cada sección en su lugar; los campos que se
// editan, el interruptor de congelada y la barra de abajo comparten un borrador: todo se guarda junto, con un motivo,
// en una transacción (catalog.save_ingredient_sheet). En el celular la ficha es de consulta (ADR-0036): los campos se
// ven como texto y no hay barra.

type Option = { value: string; label: string };
type UnitOption = { code: string; label: string; dimension: string; isBase: boolean };

export type SheetOptions = {
  categories: { id: string; label: string }[];
  units: UnitOption[];
  allergens: { id: string; name: string; validated: boolean }[];
  sources: Option[];
  statuses: Option[];
};

type Ctx = {
  prefix: string;
  editable: boolean;
  hasPrices: boolean;
  categoryLocked: boolean;
  options: SheetOptions;
  saved: IngredientSheetDraft;
  draft: IngredientSheetDraft;
  setDraft: (update: (d: IngredientSheetDraft) => IngredientSheetDraft) => void;
  changed: SheetChanges;
  count: number;
  reason: string;
  setReason: (v: string) => void;
  // Lo escrito en «Otros nombres» sin tocar «Agregar»: cuenta como cambio y se guarda igual.
  aliasText: string;
  setAliasText: (v: string) => void;
  // El campo con error (el final de su id, por ejemplo «alergeno-<id>-fuente»): lleva aria-invalid y recibe el foco.
  invalid: string | null;
  state: ActionState;
  pending: boolean;
  discard: () => void;
  save: () => Promise<void>;
};

const SheetContext = createContext<Ctx | null>(null);

function useSheet(): Ctx {
  const ctx = useContext(SheetContext);
  if (!ctx) throw new Error("Falta IngredientSheetProvider.");
  return ctx;
}

const UNIT_GROUPS: [string, string][] = [
  ["mass", "Peso"],
  ["volume", "Volumen"],
  ["count", "Unidades"],
  ["package", "Envases"],
];
const BASE_NAME: Record<string, string> = {
  mass: "gramos (g)",
  volume: "mililitros (ml)",
  count: "unidades",
};
const CONVERSION_LABEL: Record<ConversionKind, { name: string; unit: string }> = {
  density: { name: "Densidad", unit: "g por ml" },
  unit_weight: { name: "Peso por unidad", unit: "g por unidad" },
};

// Hoy, en la hora de la Argentina, como fecha de una medición nueva.
function today(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Argentina/Buenos_Aires" }).format(
    new Date(),
  );
}

// Dónde está el error de un guardado: la clave del campo (para su id y aria-invalid) y cómo se llama, para el mensaje.
const DATA_FIELDS: Record<string, { id: string; label: string }> = {
  name: { id: "nombre", label: "Nombre" },
  category_id: { id: "rubro", label: "Rubro" },
  recipe_unit: { id: "unidad", label: "Se usa en recetas en" },
  purchase_unit: { id: "compra", label: "Se compra en" },
  notes: { id: "notas", label: "Observaciones" },
};
function locateIssue(
  path: PropertyKey[],
  payload: ReturnType<typeof sheetPayload>,
  options: SheetOptions,
): { key: string; label: string } | null {
  const [block, index, field] = path;
  if (block === "data" && typeof index === "string") {
    const f = DATA_FIELDS[index];
    return f ? { key: f.id, label: f.label } : null;
  }
  if (block === "aliases") return { key: "alias", label: "Otros nombres" };
  if (block === "conversions" && typeof index === "number") {
    const kind = payload.conversions?.[index]?.kind;
    if (!kind) return null;
    const part = field === "source" ? "fuente" : field === "measured_on" ? "fecha" : "valor";
    return { key: `conv-${kind}-${part}`, label: CONVERSION_LABEL[kind].name };
  }
  if (block === "allergens" && typeof index === "number") {
    const id = payload.allergens?.[index]?.allergen_id;
    const name = options.allergens.find((a) => a.id === id)?.name;
    if (!id || !name) return null;
    return { key: `alergeno-${id}-fuente`, label: `Alérgeno ${name}` };
  }
  return null;
}

export function IngredientSheetProvider({
  ingredientId,
  stamp,
  editable,
  hasPrices,
  categoryLocked,
  initial,
  options,
  children,
}: {
  ingredientId: string;
  // El último cambio de la ficha: la base rechaza el guardado si alguien la cambió en el medio.
  stamp: string | null;
  editable: boolean;
  hasPrices: boolean;
  categoryLocked: boolean;
  initial: IngredientSheetDraft;
  options: SheetOptions;
  children: React.ReactNode;
}) {
  const prefix = useId();
  const router = useRouter();
  const pathname = usePathname();
  const search = useSearchParams();
  const [saved, setSaved] = useState(initial);
  const [draft, setDraftState] = useState(initial);
  const [reason, setReason] = useState("");
  const [state, setState] = useState<ActionState>({});
  const [pending, setPending] = useState(false);
  const [aliasText, setAliasText] = useState("");
  const [invalid, setInvalid] = useState<string | null>(null);
  // Lo que se va a guardar: el borrador más los otros nombres escritos y todavía no agregados.
  const effective = useMemo(() => {
    const more = splitAliases(aliasText);
    return more.length > 0 ? { ...draft, aliases: [...draft.aliases, ...more] } : draft;
  }, [draft, aliasText]);
  const changed = useMemo(() => sheetChanges(saved, effective), [saved, effective]);
  const count = countSheetChanges(changed);
  useUnsavedWarning(editable && count > 0);
  // Después de guardar llega lo guardado, con su sello nuevo (y la base ya normalizó, por ejemplo kg → g). La ficha no
  // se vuelve a armar: si ya se empezó a editar otra cosa, eso no se pierde; si no hay cambios, se toma lo guardado.
  const [seenStamp, setSeenStamp] = useState(stamp);
  if (stamp !== seenStamp) {
    setSeenStamp(stamp);
    setSaved(initial);
    if (count === 0) setDraftState(initial);
  }

  function discard() {
    setDraftState(saved);
    setAliasText("");
    setInvalid(null);
    setState({});
  }

  async function save() {
    const payload = sheetPayload(saved, effective);
    const parsed = ingredientSheetSchema.safeParse({
      ingredientId,
      expectedStamp: stamp ?? "",
      reason,
      ...payload,
    });
    if (!parsed.success) {
      // El mensaje dice dónde está el error, el campo queda marcado y recibe el foco (WCAG 3.3.1).
      const issue = parsed.error.issues[0];
      const where = locateIssue(issue?.path ?? [], payload, options);
      if (where) {
        setInvalid(where.key);
        setState({
          status: "bad",
          message: `${where.label}: ${issue?.message ?? "revisá el dato."}`,
        });
        document.getElementById(`${prefix}-${where.key}`)?.focus();
      } else if (!reasonField.safeParse(reason).success) {
        setInvalid("motivo");
        setState({ status: "bad", message: "Escribí el motivo de los cambios." });
        document.getElementById(`${prefix}-motivo`)?.focus();
      } else {
        setState({ status: "bad", message: issue?.message ?? "Revisá los datos." });
      }
      return;
    }
    setInvalid(null);
    setPending(true);
    try {
      const result = await saveIngredientSheetAction(parsed.data);
      // Si salió bien, el aviso va arriba de la ficha (uno solo); en la barra, solo los errores.
      setState(result.status === "ok" || result.status === "info" ? {} : result);
      if (result.status === "ok" || result.status === "info") {
        // Dejar de comprarla congelada queda pendiente: hasta que lo aprueben, sigue congelada (se ve lo vigente).
        const next =
          result.status === "info"
            ? { ...effective, requiresThawing: saved.requiresThawing }
            : effective;
        setSaved(next);
        setDraftState(next);
        setAliasText("");
        setReason("");
        // El aviso va arriba de la ficha, por la dirección: la ficha vuelve con lo guardado (y su sello nuevo).
        const q = new URLSearchParams(search.toString());
        q.set(
          "aviso",
          result.status === "info"
            ? "congelada-pendiente"
            : payload.requiresThawing
              ? "congelada"
              : "guardado",
        );
        router.replace(`${pathname}?${q}`, { scroll: false });
      }
    } finally {
      setPending(false);
    }
  }

  const value: Ctx = {
    prefix,
    editable,
    hasPrices,
    categoryLocked,
    options,
    saved,
    draft,
    setDraft: (update) => setDraftState((d) => update(d)),
    changed,
    count,
    reason,
    setReason,
    aliasText,
    setAliasText,
    invalid,
    state,
    pending,
    discard,
    save,
  };
  return <SheetContext.Provider value={value}>{children}</SheetContext.Provider>;
}

// ---------------------------------------------------------------------------
// Piezas de lectura (celular, o quien no edita)
// ---------------------------------------------------------------------------
function ReadRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col desk:flex-row desk:gap-2">
      <dt className="text-sm font-medium text-ink desk:w-48 desk:shrink-0">{label}</dt>
      <dd className="text-base break-words text-ink-muted">{value || "—"}</dd>
    </div>
  );
}

// Lo editable solo en la computadora; en el celular, lo mismo como texto (ADR-0036). Quien no edita ve el texto siempre.
function Split({ edit, read }: { edit: React.ReactNode; read: React.ReactNode }) {
  const { editable } = useSheet();
  if (!editable) return <>{read}</>;
  return (
    <>
      <div className="hidden desk:contents">{edit}</div>
      <div className="desk:hidden">{read}</div>
    </>
  );
}

const changedRing = "border-dashed border-ink";

function UnitSelectOptions({ units, packages }: { units: UnitOption[]; packages: boolean }) {
  return (
    <>
      {UNIT_GROUPS.filter(([d]) => packages || d !== "package").map(([dimension, label]) => {
        const list = units.filter((u) => u.dimension === dimension);
        return list.length === 0 ? null : (
          <optgroup key={dimension} label={label}>
            {list.map((u) => (
              <option key={u.code} value={u.code}>
                {u.label}
              </option>
            ))}
          </optgroup>
        );
      })}
    </>
  );
}

// ---------------------------------------------------------------------------
// Datos generales
// ---------------------------------------------------------------------------
export function DataSection() {
  const {
    prefix,
    draft,
    saved,
    setDraft,
    changed,
    options,
    hasPrices,
    categoryLocked,
    aliasText: alias,
    setAliasText: setAlias,
    invalid,
  } = useSheet();
  const bad = (key: string) => (invalid === key ? true : undefined);
  const set = (key: keyof IngredientSheetDraft["data"], value: string) =>
    setDraft((d) => ({ ...d, data: { ...d.data, [key]: value } }));
  const is = (key: keyof IngredientSheetDraft["data"]) => changed.data.includes(key);
  const unitOf = (code: string) => options.units.find((u) => u.code === code);
  const recipeUnit = unitOf(draft.data.recipe_unit);
  const categoryLabel = (id: string) => options.categories.find((c) => c.id === id)?.label ?? "";
  const id = (name: string) => `${prefix}-${name}`;

  function addAliases() {
    const more = splitAliases(alias);
    if (more.length === 0) return;
    setDraft((d) => ({ ...d, aliases: [...d.aliases, ...more] }));
    setAlias("");
  }

  const read = (
    <dl className="flex flex-col gap-2">
      <ReadRow label="Nombre" value={saved.data.name} />
      <ReadRow label="Rubro" value={categoryLabel(saved.data.category_id)} />
      <ReadRow
        label="Se usa en recetas en"
        value={unitOf(saved.data.recipe_unit)?.label ?? saved.data.recipe_unit}
      />
      <ReadRow
        label="Se compra en"
        value={unitOf(saved.data.purchase_unit)?.label ?? "Sin indicar"}
      />
      <ReadRow label="Otros nombres" value={saved.aliases.join(", ")} />
      <ReadRow label="Observaciones" value={saved.data.notes} />
    </dl>
  );

  const edit = (
    <div className="grid grid-cols-2 gap-x-6 gap-y-4 wide:grid-cols-3">
      <div className="flex flex-col gap-1">
        <label htmlFor={id("nombre")} className="text-sm font-medium text-ink">
          Nombre <span aria-hidden="true">*</span>
        </label>
        <Input
          id={id("nombre")}
          aria-invalid={bad("nombre")}
          value={draft.data.name}
          maxLength={120}
          aria-required="true"
          onChange={(e) => set("name", e.target.value)}
          className={cn(is("name") && changedRing)}
        />
      </div>
      <div className="flex flex-col gap-1">
        <span className="flex items-center gap-1">
          <label htmlFor={id("rubro")} className="text-sm font-medium text-ink">
            Rubro
          </label>
          {categoryLocked ? (
            <InfoTip label="por qué no se cambia el rubro">
              Ya tiene precios: el rubro decide cuándo un precio está desactualizado, y eso lo
              cambia Dirección General (precios).
            </InfoTip>
          ) : null}
        </span>
        <Select
          id={id("rubro")}
          aria-invalid={bad("rubro")}
          value={draft.data.category_id}
          disabled={categoryLocked}
          onChange={(e) => set("category_id", e.target.value)}
          className={cn(is("category_id") && changedRing)}
        >
          {options.categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.label}
            </option>
          ))}
        </Select>
      </div>
      <div className="flex flex-col gap-1">
        <span className="flex items-center gap-1">
          <label htmlFor={id("unidad")} className="text-sm font-medium text-ink">
            Se usa en recetas en
          </label>
          <InfoTip label="la unidad de recetas">
            {hasPrices
              ? "Ya tiene precios: la unidad no cambia, porque los precios se guardaron en esa unidad."
              : "Podés elegir cualquier medida: las recetas la calculan en su unidad base."}
          </InfoTip>
        </span>
        <Select
          id={id("unidad")}
          aria-invalid={bad("unidad")}
          value={draft.data.recipe_unit}
          disabled={hasPrices}
          aria-describedby={id("unidad-base")}
          onChange={(e) => set("recipe_unit", e.target.value)}
          className={cn(is("recipe_unit") && changedRing)}
        >
          <UnitSelectOptions units={options.units} packages={false} />
        </Select>
        <p id={id("unidad-base")} className="text-sm text-ink-muted">
          {recipeUnit && BASE_NAME[recipeUnit.dimension]
            ? `Las recetas la calculan en ${BASE_NAME[recipeUnit.dimension]}.`
            : ""}
        </p>
      </div>
      <div className="flex flex-col gap-1">
        <label htmlFor={id("compra")} className="text-sm font-medium text-ink">
          Se compra en
        </label>
        <Select
          id={id("compra")}
          aria-invalid={bad("compra")}
          value={draft.data.purchase_unit}
          onChange={(e) => set("purchase_unit", e.target.value)}
          className={cn(is("purchase_unit") && changedRing)}
        >
          <option value="">Sin indicar</option>
          <UnitSelectOptions units={options.units} packages />
        </Select>
      </div>
      <div className="col-span-2 flex flex-col gap-1">
        <span className="flex items-center gap-1">
          <label htmlFor={id("alias")} className="text-sm font-medium text-ink">
            Otros nombres
          </label>
          <InfoTip label="otros nombres">
            Sirven para buscar e importar sin duplicar. Separá varios con coma.
          </InfoTip>
        </span>
        <div
          className={cn(
            "flex flex-wrap items-center gap-2 rounded-sm border border-transparent p-1",
            changed.aliases && changedRing,
          )}
        >
          <ul className="flex flex-wrap gap-2" aria-label="Otros nombres cargados">
            {draft.aliases.map((a, i) => (
              <li
                key={`${a}-${i}`}
                className="inline-flex items-center gap-1 rounded-sm bg-none py-0.5 pl-2 text-sm text-none-ink"
              >
                {a}
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  aria-label={`Quitar «${a}»`}
                  onClick={() =>
                    setDraft((d) => ({ ...d, aliases: d.aliases.filter((_, j) => j !== i) }))
                  }
                >
                  <X aria-hidden="true" />
                </Button>
              </li>
            ))}
          </ul>
          <Input
            id={id("alias")}
            aria-invalid={bad("alias")}
            value={alias}
            className="w-56"
            maxLength={200}
            placeholder="Agregar otro nombre"
            onChange={(e) => setAlias(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                addAliases();
              }
            }}
          />
          <Button type="button" variant="outline" onClick={addAliases}>
            <Plus aria-hidden="true" />
            Agregar
          </Button>
        </div>
        {changed.aliases ? (
          <span className="sr-only" role="status">
            Otros nombres: cambio sin guardar
          </span>
        ) : null}
      </div>
      <div className="col-span-2 flex flex-col gap-1 wide:col-span-1">
        <label htmlFor={id("notas")} className="text-sm font-medium text-ink">
          Observaciones
        </label>
        <Textarea
          id={id("notas")}
          aria-invalid={bad("notas")}
          value={draft.data.notes}
          maxLength={1000}
          rows={3}
          onChange={(e) => set("notes", e.target.value)}
          className={cn(is("notes") && changedRing)}
        />
      </div>
    </div>
  );
  return <Split edit={edit} read={read} />;
}

// ---------------------------------------------------------------------------
// ¿Se compra congelada? (ADR-0040): marcarla se aplica; desmarcarla pide aprobación
// ---------------------------------------------------------------------------
export function ThawingToggle({ pending: requestPending }: { pending: boolean }) {
  const { prefix, editable, draft, saved, setDraft } = useSheet();
  const tip = (
    <InfoTip label="se compra congelada">
      Si se compra congelada, su costo suma la merma de descongelado aprobada. Dejar de comprarla
      congelada baja el costo: lo aprueba un Chef de todo el grupo.
    </InfoTip>
  );
  const read = (
    <p className="text-base text-ink">
      ¿Se compra congelada?{" "}
      <span className="font-medium">{saved.requiresThawing ? "Sí" : "No"}</span>
    </p>
  );
  const edit = (
    <div className="flex items-center gap-1">
      <ToggleField
        // Con un pedido pendiente sigue congelada hasta que lo aprueben: se ve lo vigente.
        key={`${saved.requiresThawing}`}
        id={`${prefix}-congelada`}
        name="requires_thawing"
        label="¿Se compra congelada?"
        defaultValue={saved.requiresThawing}
        disabled={requestPending}
        value={draft.requiresThawing}
        onChange={(v) => setDraft((d) => ({ ...d, requiresThawing: v }))}
      />
      {tip}
    </div>
  );
  return (
    <div className="flex flex-col gap-2">
      {editable ? <Split edit={edit} read={read} /> : read}
      {requestPending ? (
        <Badge status="review" className="self-start whitespace-normal">
          Pedido pendiente: dejar de comprarla congelada
        </Badge>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Conversiones: densidad y peso por unidad, con su fuente y fecha (nunca se supone)
// ---------------------------------------------------------------------------
export function ConversionsSection() {
  const { prefix, draft, saved, setDraft, changed, options, invalid } = useSheet();
  const bad = (key: string) => (invalid === key ? true : undefined);
  const number = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 6 });
  const sourceLabel = (v: string) => options.sources.find((s) => s.value === v)?.label ?? "";
  const set = (kind: ConversionKind, value: SheetConversion | null) =>
    setDraft((d) => ({ ...d, conversions: { ...d.conversions, [kind]: value } }));
  const patch = (kind: ConversionKind, part: Partial<SheetConversion>) => {
    const current = draft.conversions[kind];
    if (current) set(kind, { ...current, ...part });
  };
  const loaded = CONVERSION_KINDS.filter((k) => saved.conversions[k] !== null);

  const read =
    loaded.length === 0 ? (
      <p className="text-base text-ink-muted">No tiene conversiones cargadas.</p>
    ) : (
      <dl className="flex flex-col gap-2">
        {loaded.map((k) => {
          const c = saved.conversions[k];
          if (!c) return null;
          const value = `${number.format(Number(c.factor.replace(",", ".")))} ${CONVERSION_LABEL[k].unit} · ${sourceLabel(c.source)} · ${c.measured_on.split("-").reverse().join("/")}${c.measured_by ? ` · ${c.measured_by}` : ""}`;
          return <ReadRow key={k} label={CONVERSION_LABEL[k].name} value={value} />;
        })}
      </dl>
    );

  const rows = CONVERSION_KINDS.filter((k) => draft.conversions[k] !== null);
  const missing = CONVERSION_KINDS.filter((k) => draft.conversions[k] === null);
  const edit = (
    <div className="flex flex-col gap-3">
      {rows.length === 0 ? (
        <p className="text-base text-ink-muted">No tiene conversiones cargadas.</p>
      ) : (
        <table className="w-full border-collapse text-base">
          <caption className="sr-only">Conversiones</caption>
          <thead>
            <tr className="border-b border-line text-left text-sm text-ink-muted">
              <th scope="col" className="py-2 pr-3 font-medium">
                Conversión
              </th>
              <th scope="col" className="py-2 pr-3 font-medium">
                Valor
              </th>
              <th scope="col" className="py-2 pr-3 font-medium">
                De dónde sale
              </th>
              <th scope="col" className="py-2 pr-3 font-medium">
                Fecha de la medición
              </th>
              <th scope="col" className="py-2 pr-3 font-medium">
                Quién lo midió
              </th>
              <th scope="col" className="py-2 font-medium">
                <span className="sr-only">Quitar</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((k) => {
              const c = draft.conversions[k];
              if (!c) return null;
              const name = CONVERSION_LABEL[k];
              const ring = changed.conversions.includes(k) && changedRing;
              return (
                <tr key={k} className="border-b border-line">
                  <th scope="row" className="py-2 pr-3 text-left font-medium text-ink">
                    {name.name}
                    {changed.conversions.includes(k) ? (
                      <span className="sr-only"> (cambio sin guardar)</span>
                    ) : null}
                  </th>
                  <td className="py-2 pr-3">
                    <span className="flex items-center gap-2">
                      <Input
                        id={`${prefix}-conv-${k}-valor`}
                        aria-label={`${name.name}: valor (${name.unit})`}
                        aria-invalid={bad(`conv-${k}-valor`)}
                        inputMode="decimal"
                        value={c.factor}
                        onChange={(e) => patch(k, { factor: e.target.value })}
                        className={cn("w-28 text-right tabular-nums", ring)}
                      />
                      <span className="text-sm whitespace-nowrap text-ink-muted">{name.unit}</span>
                    </span>
                  </td>
                  <td className="py-2 pr-3">
                    <Select
                      id={`${prefix}-conv-${k}-fuente`}
                      aria-label={`${name.name}: de dónde sale`}
                      aria-invalid={bad(`conv-${k}-fuente`)}
                      value={c.source}
                      onChange={(e) => patch(k, { source: e.target.value as DataSource | "" })}
                      className={cn(ring)}
                    >
                      <option value="" disabled>
                        Elegí de dónde sale
                      </option>
                      {options.sources.map((s) => (
                        <option key={s.value} value={s.value}>
                          {s.label}
                        </option>
                      ))}
                    </Select>
                  </td>
                  <td className="py-2 pr-3">
                    <Input
                      type="date"
                      id={`${prefix}-conv-${k}-fecha`}
                      aria-label={`${name.name}: fecha de la medición`}
                      aria-invalid={bad(`conv-${k}-fecha`)}
                      value={c.measured_on}
                      max={today()}
                      onChange={(e) => patch(k, { measured_on: e.target.value })}
                      className={cn(ring)}
                    />
                  </td>
                  <td className="py-2 pr-3">
                    <Input
                      aria-label={`${name.name}: quién lo midió`}
                      value={c.measured_by}
                      maxLength={120}
                      onChange={(e) => patch(k, { measured_by: e.target.value })}
                      className={cn(ring)}
                    />
                  </td>
                  <td className="py-2">
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      aria-label={`Quitar la ${name.name.toLowerCase()}`}
                      onClick={() => set(k, null)}
                    >
                      <X aria-hidden="true" />
                    </Button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
      {missing.map((k) => (
        <Button
          key={k}
          type="button"
          variant="outline"
          className="self-start"
          onClick={() =>
            set(k, { factor: "", source: "measured", measured_on: today(), measured_by: "" })
          }
        >
          <Plus aria-hidden="true" />
          Agregar {CONVERSION_LABEL[k].name.toLowerCase()} ({CONVERSION_LABEL[k].unit})
        </Button>
      ))}
    </div>
  );
  return <Split edit={edit} read={read} />;
}

// ---------------------------------------------------------------------------
// Alérgenos: un segmentado por alérgeno (pocas opciones a la vista, ADR-0039)
// ---------------------------------------------------------------------------
export function AllergensSection() {
  const { prefix, draft, saved, setDraft, changed, options, invalid } = useSheet();
  const statusLabel = (v: string) =>
    v ? (options.statuses.find((s) => s.value === v)?.label ?? "") : "Sin dato";
  const badge = (v: string) =>
    v === "contains" ? "bad" : v === "may_contain" ? "warn" : v === "free_verified" ? "ok" : "none";
  const unvalidated = options.allergens.some((a) => !a.validated);
  const choices = [{ value: "", label: "Sin dato" }, ...options.statuses];

  const read = (
    <ul className="flex flex-col gap-2" aria-label="Alérgenos">
      {options.allergens.map((a) => {
        const v = saved.allergens[a.id]?.status ?? "";
        return (
          <li
            key={a.id}
            className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-2 last:border-0"
          >
            <span className="text-base text-ink">{a.name}</span>
            <Badge status={badge(v)}>{statusLabel(v)}</Badge>
          </li>
        );
      })}
    </ul>
  );

  const edit = (
    <ul className="flex flex-col" aria-label="Alérgenos">
      {options.allergens.map((a) => {
        const v = draft.allergens[a.id] ?? { status: "" as const, source: "" as const };
        const isChanged = changed.allergens.includes(a.id);
        return (
          <li
            key={a.id}
            className="grid grid-cols-[9rem_minmax(0,1fr)_13rem] items-center gap-3 border-b border-line py-2 last:border-0"
          >
            <span className="text-base font-medium text-ink">{a.name}</span>
            <Segmented
              name={`${prefix}-alergeno-${a.id}`}
              legend={`${a.name}: estado`}
              hideLegend
              options={choices}
              value={v.status}
              changed={isChanged}
              onChange={(status) =>
                setDraft((d) => ({
                  ...d,
                  allergens: {
                    ...d.allergens,
                    [a.id]: { status: status as AllergenStatus | "", source: v.source },
                  },
                }))
              }
            />
            {v.status ? (
              <Select
                id={`${prefix}-alergeno-${a.id}-fuente`}
                aria-label={`${a.name}: de dónde sale`}
                aria-invalid={invalid === `alergeno-${a.id}-fuente` ? true : undefined}
                value={v.source}
                onChange={(e) =>
                  setDraft((d) => ({
                    ...d,
                    allergens: {
                      ...d.allergens,
                      [a.id]: { status: v.status, source: e.target.value as DataSource | "" },
                    },
                  }))
                }
                className={cn(isChanged && changedRing)}
              >
                <option value="" disabled>
                  Elegí de dónde sale
                </option>
                {options.sources.map((s) => (
                  <option key={s.value} value={s.value}>
                    {s.label}
                  </option>
                ))}
              </Select>
            ) : (
              <span aria-hidden="true" className="text-sm text-ink-muted">
                —
              </span>
            )}
          </li>
        );
      })}
    </ul>
  );

  return (
    <div className="flex flex-col gap-3">
      {unvalidated ? (
        <p className="rounded-sm border border-line bg-warn p-3 text-base text-warn-ink">
          La lista de alérgenos todavía no está validada por un responsable.
        </p>
      ) : null}
      <Split edit={edit} read={read} />
    </div>
  );
}

// ---------------------------------------------------------------------------
// La barra fija: un solo guardado para toda la ficha (ADR-0039). Solo en la computadora.
// ---------------------------------------------------------------------------
export function SheetBar() {
  const { prefix, editable, count, reason, setReason, state, pending, discard, save, invalid } =
    useSheet();
  if (!editable) return null;
  return (
    <div className="sticky bottom-0 z-10 -mx-gutter hidden flex-col gap-2 border-t border-line bg-surface px-gutter py-3 desk:flex wide:-mx-gutter-wide wide:px-gutter-wide">
      <FormNotice state={state} />
      <div className="flex flex-wrap items-center gap-2">
        <span className="mr-auto text-base font-semibold text-ink" role="status">
          {changesLabel(count)}
        </span>
        <label htmlFor={`${prefix}-motivo`} className="text-sm font-medium text-ink">
          Motivo<span className="sr-only"> de los cambios</span>
        </label>
        {/* Obligatorio: la marca va fuera de la etiqueta, así el nombre del campo sigue siendo «Motivo de los cambios». */}
        <span aria-hidden="true" className="-ml-1 text-sm font-medium text-ink">
          *
        </span>
        <Input
          id={`${prefix}-motivo`}
          aria-invalid={invalid === "motivo" ? true : undefined}
          placeholder="Obligatorio: por qué cambia"
          aria-required="true"
          className="w-80"
          maxLength={500}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
        <Button type="button" variant="outline" disabled={pending || count === 0} onClick={discard}>
          Descartar
        </Button>
        <Button type="button" disabled={pending || count === 0} onClick={() => void save()}>
          {pending ? "Guardando…" : "Guardar cambios"}
        </Button>
      </div>
    </div>
  );
}
