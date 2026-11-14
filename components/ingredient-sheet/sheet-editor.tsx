"use client";

import { createContext, useContext, useEffect, useId, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Plus, X } from "lucide-react";

import { saveIngredientSheetAction } from "@/app/materias-primas/actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input, Select, Textarea } from "@/components/ui/field";
import { Modal } from "@/components/ui/dialog";
import { InfoTip } from "@/components/ui/info-tip";
import { Notice } from "@/components/ui/notice";
import { ToggleField } from "@/components/ui/toggle-field";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { ingredientSheetSchema, reasonField } from "@/lib/forms/schemas";
import {
  CONVERSION_KINDS,
  applyAllergenSource,
  cycleAllergen,
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
  notice: { status: "ok" | "info"; text: string } | null;
  prefix: string;
  editable: boolean;
  hasPrices: boolean;
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
    return { key: "alergenos-origen", label: `Alérgeno ${name}: origen de estos cambios` };
  }
  return null;
}

export function IngredientSheetProvider({
  ingredientId,
  stamp,
  editable,
  hasPrices,
  initial,
  options,
  notice = null,
  children,
}: {
  // El aviso del último guardado: va en la barra de abajo (la pantalla no tiene una fila de más para él).
  notice?: { status: "ok" | "info"; text: string } | null;
  ingredientId: string;
  // El último cambio de la ficha: la base rechaza el guardado si alguien la cambió en el medio.
  stamp: string | null;
  editable: boolean;
  hasPrices: boolean;
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
    notice,
    prefix,
    editable,
    hasPrices,
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
    <div className="flex flex-col">
      <dt className="text-sm font-medium text-ink">{label}</dt>
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
// middle: lo que va entre «Se compra en» y «Otros nombres» (el interruptor de congelada, ADR-0046).
// readExtra: lo que se suma a la lectura del celular de quien edita (por ejemplo, un pedido pendiente).
export function DataSection({
  middle,
  readExtra,
}: { middle?: React.ReactNode; readExtra?: React.ReactNode } = {}) {
  const {
    prefix,
    draft,
    saved,
    setDraft,
    changed,
    options,
    hasPrices,
    aliasText: alias,
    setAliasText: setAlias,
    invalid,
    editable,
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
  if (!editable)
    return (
      <div className="flex flex-col gap-2">
        {read}
        {middle}
      </div>
    );

  // Una sola columna compacta (ficha sin scroll, ADR-0046): Nombre; Rubro y unidad en una fila; Se compra en; lo que la
  // página ponga en el medio (¿Se compra congelada?); Otros nombres en chips; Observaciones ocupa lo que sobra.
  const label = "text-sm font-medium whitespace-nowrap text-ink";
  // La tarjeta es angosta: controles de 36 px en la computadora (44 en el celular, como siempre).
  const small = "desk:min-h-control-sm";
  const edit = (
    <div className="flex min-h-0 flex-1 flex-col gap-2">
      <div className="flex flex-col gap-1">
        <label htmlFor={id("nombre")} className={label}>
          Nombre <span aria-hidden="true">*</span>
        </label>
        <Input
          id={id("nombre")}
          aria-invalid={bad("nombre")}
          value={draft.data.name}
          maxLength={120}
          aria-required="true"
          onChange={(e) => set("name", e.target.value)}
          className={cn(small, is("name") && changedRing)}
        />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div className="flex min-w-0 flex-col gap-1">
          <label htmlFor={id("rubro")} className={label}>
            Rubro
          </label>
          <Select
            id={id("rubro")}
            aria-invalid={bad("rubro")}
            value={draft.data.category_id}
            onChange={(e) => set("category_id", e.target.value)}
            className={cn(small, is("category_id") && changedRing)}
          >
            {options.categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </Select>
        </div>
        <div className="flex min-w-0 flex-col gap-1">
          <label htmlFor={id("unidad")} className={label}>
            Se usa en recetas en
          </label>
          <Select
            id={id("unidad")}
            aria-invalid={bad("unidad")}
            value={draft.data.recipe_unit}
            disabled={hasPrices}
            aria-describedby={id("unidad-base")}
            onChange={(e) => set("recipe_unit", e.target.value)}
            className={cn(small, is("recipe_unit") && changedRing)}
          >
            <UnitSelectOptions units={options.units} packages={false} />
          </Select>
        </div>
      </div>
      {/* La explicación de la unidad, a la vista y en una línea (la columna es angosta para un tooltip al lado). */}
      <p id={id("unidad-base")} className="text-xs text-ink-muted empty:hidden">
        {/* Corta, para que entre en un renglón: con precios la unidad queda fija. */}
        {recipeUnit && BASE_NAME[recipeUnit.dimension]
          ? hasPrices
            ? `Fija: tiene precios. Se calcula en ${BASE_NAME[recipeUnit.dimension]}.`
            : `Las recetas la calculan en ${BASE_NAME[recipeUnit.dimension]}.`
          : hasPrices
            ? "Fija: tiene precios."
            : ""}
      </p>
      <div className="flex flex-col gap-1">
        <label htmlFor={id("compra")} className={label}>
          Se compra en
        </label>
        <Select
          id={id("compra")}
          aria-invalid={bad("compra")}
          value={draft.data.purchase_unit}
          onChange={(e) => set("purchase_unit", e.target.value)}
          className={cn(small, is("purchase_unit") && changedRing)}
        >
          <option value="">Sin indicar</option>
          <UnitSelectOptions units={options.units} packages />
        </Select>
      </div>
      {middle}
      <div className="flex flex-col gap-1">
        <span className="flex items-center gap-1">
          <label htmlFor={id("alias")} className={label}>
            Otros nombres
          </label>
          <InfoTip label="otros nombres">
            Sirven para buscar e importar sin duplicar. Separá varios con coma.
          </InfoTip>
        </span>
        <div
          className={cn(
            "flex flex-wrap items-center gap-2 rounded-sm border border-transparent",
            changed.aliases && changedRing,
          )}
        >
          <ul className="contents" aria-label="Otros nombres cargados">
            {draft.aliases.map((a, i) => (
              <li
                key={`${a}-${i}`}
                className="inline-flex items-center gap-1 rounded-sm bg-none pl-2 text-sm text-none-ink"
              >
                {a}
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  aria-label={`Quitar «${a}»`}
                  className="desk:min-h-8 desk:w-8"
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
            className={cn("w-24 min-w-24 flex-1", small)}
            maxLength={200}
            placeholder="Otro nombre"
            onChange={(e) => setAlias(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                addAliases();
              }
            }}
          />
          <Button
            type="button"
            variant="outline"
            size="icon"
            aria-label="Agregar"
            title="Agregar otro nombre"
            className="desk:min-h-control-sm desk:w-control-sm"
            onClick={addAliases}
          >
            <Plus aria-hidden="true" />
          </Button>
        </div>
        {changed.aliases ? (
          <span className="sr-only" role="status">
            Otros nombres: cambio sin guardar
          </span>
        ) : null}
      </div>
      <div className="flex min-h-0 flex-1 flex-col gap-1">
        <label htmlFor={id("notas")} className={label}>
          Observaciones
        </label>
        <Textarea
          id={id("notas")}
          aria-invalid={bad("notas")}
          value={draft.data.notes}
          maxLength={1000}
          rows={2}
          onChange={(e) => set("notes", e.target.value)}
          className={cn("min-h-14 flex-1 resize-none", is("notes") && changedRing)}
        />
      </div>
    </div>
  );
  return (
    <Split
      edit={edit}
      read={
        // En el celular quien edita también consulta: la congelada, como texto (el interruptor va solo en la edición).
        <div className="flex flex-col gap-2">
          <p className="text-base text-ink">
            ¿Se compra congelada?{" "}
            <span className="font-medium">{saved.requiresThawing ? "Sí" : "No"}</span>
          </p>
          {readExtra}
          {read}
        </div>
      }
    />
  );
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
      {/* Quien edita la ve en la edición (solo en la computadora); la lectura del celular la dice en «Datos generales». */}
      {editable ? edit : read}
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
  const [editing, setEditing] = useState<ConversionKind | null>(null);
  // Si el guardado marca un dato de una conversión, se abre su panel y el campo recibe el foco.
  const invalidKind = CONVERSION_KINDS.find((k) => invalid?.startsWith(`conv-${k}-`)) ?? null;
  const [seenInvalid, setSeenInvalid] = useState<string | null>(null);
  if (invalid !== seenInvalid) {
    setSeenInvalid(invalid);
    if (invalidKind) setEditing(invalidKind);
  }
  useEffect(() => {
    if (invalidKind && invalid) {
      requestAnimationFrame(() => document.getElementById(`${prefix}-${invalid}`)?.focus());
    }
  }, [invalid, invalidKind, prefix]);

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
  const summary = (c: SheetConversion, k: ConversionKind) =>
    [
      c.factor.trim()
        ? `${number.format(Number(c.factor.replace(",", ".")))} ${CONVERSION_LABEL[k].unit}`
        : "Falta el valor",
      sourceLabel(c.source) || null,
      c.measured_on ? c.measured_on.split("-").reverse().join("/") : null,
    ]
      .filter(Boolean)
      .join(" · ");
  const open = editing ? draft.conversions[editing] : null;
  // Al cerrar el panel, el foco vuelve a la fila de esa conversión; si se quitó, al botón para agregarla (WCAG 2.4.3).
  function closeEditor() {
    const kind = editing;
    setEditing(null);
    if (!kind) return;
    requestAnimationFrame(() =>
      (
        document.getElementById(`${prefix}-conv-${kind}-editar`) ??
        document.getElementById(`${prefix}-conv-${kind}-agregar`)
      )?.focus(),
    );
  }
  const edit = (
    <div className="flex flex-col gap-2">
      {rows.length === 0 ? (
        <p className="flex flex-wrap items-center gap-2 text-sm text-ink">
          <Badge status="none">No aplica</Badge>
          Se compra y se usa en la misma medida.
        </p>
      ) : (
        <ul className="flex flex-col divide-y divide-line" aria-label="Conversiones">
          {rows.map((k) => {
            const c = draft.conversions[k];
            if (!c) return null;
            const isChanged = changed.conversions.includes(k);
            return (
              <li
                key={k}
                className={cn(
                  "flex min-h-8 items-center justify-between gap-2 rounded-sm border border-transparent text-sm",
                  isChanged && changedRing,
                )}
              >
                <span className="min-w-0 text-ink">
                  <span className="font-medium">{CONVERSION_LABEL[k].name}</span>{" "}
                  <span className="text-ink-muted tabular-nums">{summary(c, k)}</span>
                  {isChanged ? <span className="sr-only"> (cambio sin guardar)</span> : null}
                </span>
                <Button
                  id={`${prefix}-conv-${k}-editar`}
                  type="button"
                  variant="ghost"
                  size="sm"
                  aria-label={`Editar la ${CONVERSION_LABEL[k].name.toLowerCase()}`}
                  onClick={() => setEditing(k)}
                >
                  Editar
                </Button>
              </li>
            );
          })}
        </ul>
      )}
      {missing.length > 0 ? (
        <div className="flex flex-wrap gap-2">
          {missing.map((k) => (
            <Button
              key={k}
              id={`${prefix}-conv-${k}-agregar`}
              type="button"
              variant="outline"
              size="sm"
              aria-label={`Agregar ${CONVERSION_LABEL[k].name.toLowerCase()} (${CONVERSION_LABEL[k].unit})`}
              title={`${CONVERSION_LABEL[k].name} (${CONVERSION_LABEL[k].unit})`}
              onClick={() => {
                set(k, { factor: "", source: "measured", measured_on: today(), measured_by: "" });
                setEditing(k);
              }}
            >
              <Plus aria-hidden="true" />
              {CONVERSION_LABEL[k].name}
            </Button>
          ))}
        </div>
      ) : null}
      {/* El panel edita el mismo borrador: lo cambiado cuenta en la barra y se guarda junto (ADR-0046). */}
      <Modal
        open={editing !== null && open !== null}
        onOpenChange={(next) => {
          if (!next) closeEditor();
        }}
        title={editing ? CONVERSION_LABEL[editing].name : "Conversión"}
        description="Se guarda con «Guardar cambios», junto con el resto de la ficha."
      >
        {editing && open ? (
          <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
              <label
                htmlFor={`${prefix}-conv-${editing}-valor`}
                className="text-sm font-medium text-ink"
              >
                Valor ({CONVERSION_LABEL[editing].unit})
              </label>
              <Input
                id={`${prefix}-conv-${editing}-valor`}
                aria-invalid={bad(`conv-${editing}-valor`)}
                inputMode="decimal"
                value={open.factor}
                onChange={(e) => patch(editing, { factor: e.target.value })}
                className="tabular-nums"
              />
            </div>
            <div className="flex flex-col gap-1">
              <label
                htmlFor={`${prefix}-conv-${editing}-fuente`}
                className="text-sm font-medium text-ink"
              >
                De dónde sale
              </label>
              <Select
                id={`${prefix}-conv-${editing}-fuente`}
                aria-invalid={bad(`conv-${editing}-fuente`)}
                value={open.source}
                onChange={(e) => patch(editing, { source: e.target.value as DataSource | "" })}
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
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="flex flex-col gap-1">
                <label
                  htmlFor={`${prefix}-conv-${editing}-fecha`}
                  className="text-sm font-medium text-ink"
                >
                  Fecha de la medición
                </label>
                <Input
                  type="date"
                  id={`${prefix}-conv-${editing}-fecha`}
                  aria-invalid={bad(`conv-${editing}-fecha`)}
                  value={open.measured_on}
                  max={today()}
                  onChange={(e) => patch(editing, { measured_on: e.target.value })}
                />
              </div>
              <div className="flex flex-col gap-1">
                <label
                  htmlFor={`${prefix}-conv-${editing}-quien`}
                  className="text-sm font-medium text-ink"
                >
                  Quién lo midió
                </label>
                <Input
                  id={`${prefix}-conv-${editing}-quien`}
                  value={open.measured_by}
                  maxLength={120}
                  onChange={(e) => patch(editing, { measured_by: e.target.value })}
                />
              </div>
            </div>
            <div className="flex flex-wrap justify-between gap-2">
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  set(editing, null);
                  closeEditor();
                }}
              >
                <X aria-hidden="true" />
                Quitar la {CONVERSION_LABEL[editing].name.toLowerCase()}
              </Button>
              <Button type="button" onClick={closeEditor}>
                Listo
              </Button>
            </div>
          </div>
        ) : null}
      </Modal>
    </div>
  );
  return <Split edit={edit} read={read} />;
}

// ---------------------------------------------------------------------------
// Alérgenos (ADR-0046, pedido de Soy del 2026-11-13): un botón por alérgeno que cambia de estado en cada clic
// (Sin dato → No contiene → Puede contener → Contiene), cada estado con su color y su palabra. El origen del dato es
// uno para todos los cambiados («Origen de estos cambios»); el de cada uno, guardado, se ve en el tooltip.
const ALLERGEN_WORD: Record<AllergenStatus | "", string> = {
  "": "Sin dato",
  free_verified: "No contiene",
  may_contain: "Puede contener",
  contains: "Contiene",
};
const ALLERGEN_TONE: Record<AllergenStatus | "", string> = {
  "": "bg-none text-none-ink",
  free_verified: "bg-ok text-ok-ink",
  may_contain: "bg-warn text-warn-ink",
  contains: "bg-bad text-bad-ink",
};

export function AllergensSection() {
  const { prefix, draft, saved, setDraft, changed, options, invalid } = useSheet();
  const badge = (v: string) =>
    v === "contains" ? "bad" : v === "may_contain" ? "warn" : v === "free_verified" ? "ok" : "none";
  const sourceLabel = (v: string) => options.sources.find((s) => s.value === v)?.label ?? "";
  // El origen común: el que comparten los cambiados con estado (si todavía no se eligió, vacío).
  const pendingWithStatus = changed.allergens.filter((id) => draft.allergens[id]?.status);
  const sources = [...new Set(pendingWithStatus.map((id) => draft.allergens[id]?.source ?? ""))];
  const common: DataSource | "" = sources.length === 1 ? (sources[0] ?? "") : "";

  // Lectura (quien no edita, y el celular): la misma grilla de 2 columnas que la edición en la computadora, con el estado en
  // palabra. Así entra en la pantalla también para quien solo lee.
  const read = (
    <ul className="grid grid-cols-1 gap-1 desk:grid-cols-2" aria-label="Alérgenos">
      {options.allergens.map((a) => {
        const v = saved.allergens[a.id]?.status ?? "";
        return (
          <li
            key={a.id}
            className="flex min-h-touch items-center justify-between gap-2 border-b border-line text-sm desk:min-h-7"
          >
            <span className="min-w-0 leading-tight text-ink">{a.name}</span>
            <Badge status={badge(v)}>{ALLERGEN_WORD[v]}</Badge>
          </li>
        );
      })}
    </ul>
  );

  const edit = (
    <div className="flex flex-col gap-2">
      <div role="group" aria-label="Estado de cada alérgeno" className="grid grid-cols-2 gap-1">
        {options.allergens.map((a) => {
          const v = draft.allergens[a.id] ?? { status: "" as const, source: "" as const };
          const before = saved.allergens[a.id];
          const isChanged = changed.allergens.includes(a.id);
          const origin = before?.status ? sourceLabel(before.source) : "";
          const originId = `${prefix}-alergeno-${a.id}-origen`;
          return (
            <button
              key={a.id}
              type="button"
              // El nombre empieza con lo que se ve (WCAG 2.5.3), dice qué hace el clic y si es un cambio sin guardar.
              aria-label={`${a.name} ${ALLERGEN_WORD[v.status]}. Cambiar${isChanged ? ". Cambio sin guardar" : ""}`}
              aria-describedby={origin ? originId : undefined}
              onClick={() =>
                setDraft((d) => ({
                  ...d,
                  allergens: {
                    ...d.allergens,
                    [a.id]: cycleAllergen(before, d.allergens[a.id], common),
                  },
                }))
              }
              className={cn(
                "flex min-h-touch items-center justify-between gap-2 rounded-sm border border-transparent px-2 text-left text-xs desk:min-h-7",
                ALLERGEN_TONE[v.status],
                isChanged && "border-dashed border-ink",
              )}
            >
              {/* El espacio entre las dos partes cuenta: el texto visible es «Soja Sin dato» (WCAG 2.5.3). Un nombre
                  largo pasa a dos renglones; no se corta. */}
              <span className="min-w-0 leading-tight">{a.name}</span>{" "}
              <span className="shrink-0 font-medium">{ALLERGEN_WORD[v.status]}</span>
              {/* De dónde sale el dato guardado: lo anuncia el lector de pantalla (y no hace falta pasar el mouse). */}
              {origin ? (
                <span id={originId} className="sr-only">
                  Guardado: {ALLERGEN_WORD[before?.status ?? ""]}, {origin}.
                </span>
              ) : null}
            </button>
          );
        })}
      </div>
      {pendingWithStatus.length > 0 ? (
        <div className="flex items-center gap-2">
          <label htmlFor={`${prefix}-alergenos-origen`} className="text-sm font-medium text-ink">
            Origen de estos cambios <span aria-hidden="true">*</span>
          </label>
          <Select
            id={`${prefix}-alergenos-origen`}
            aria-invalid={invalid === "alergenos-origen" ? true : undefined}
            aria-required="true"
            value={common}
            onChange={(e) =>
              setDraft((d) => ({
                ...d,
                allergens: applyAllergenSource(saved, d, e.target.value as DataSource | ""),
              }))
            }
            className="min-w-0 flex-1 border-dashed border-ink"
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
        </div>
      ) : null}
    </div>
  );

  return (
    <div className="flex flex-col gap-2">
      <Split edit={edit} read={read} />
    </div>
  );
}

// Cuántos alérgenos tienen dato, para el título de la tarjeta. Si la lista todavía no la validó un responsable, se dice
// al lado (un chip, con la explicación en el tooltip de ayuda).
export function AllergenSummary() {
  const { draft, options } = useSheet();
  const n = options.allergens.filter((a) => draft.allergens[a.id]?.status).length;
  const unvalidated = options.allergens.some((a) => !a.validated);
  return (
    <span className="flex flex-wrap items-center justify-end gap-x-2 gap-y-1">
      <span className="text-xs whitespace-nowrap text-ink-muted tabular-nums">
        {n} de {options.allergens.length} con dato
      </span>
      {unvalidated ? (
        <span className="flex items-center gap-1">
          <Badge status="warn">Sin validar</Badge>
          <InfoTip label="lista sin validar">
            La lista de alérgenos todavía no está validada por un responsable.
          </InfoTip>
        </span>
      ) : null}
    </span>
  );
}

// ---------------------------------------------------------------------------
// La barra fija: un solo guardado para toda la ficha (ADR-0039). Solo en la computadora.
// ---------------------------------------------------------------------------
export function SheetBar() {
  const {
    prefix,
    editable,
    count,
    reason,
    setReason,
    state,
    pending,
    discard,
    save,
    invalid,
    notice,
  } = useSheet();
  if (!editable) return null;
  return (
    <div className="sticky bottom-0 z-10 -mx-gutter hidden flex-col gap-2 border-t border-line bg-surface px-gutter py-2 desk:flex wide:-mx-gutter-wide wide:px-gutter-wide">
      <FormNotice state={state} />
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-base font-semibold text-ink" role="status">
          {changesLabel(count)}
        </span>
        {/* El último guardado, al lado del contador (se va con el próximo cambio). */}
        <div className="mr-auto">
          {notice && count === 0 ? (
            <Notice status={notice.status} className="items-center px-3 py-1 text-sm">
              {notice.text}
            </Notice>
          ) : null}
        </div>
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
