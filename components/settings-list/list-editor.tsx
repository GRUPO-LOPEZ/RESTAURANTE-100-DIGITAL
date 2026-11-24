"use client";

import {
  createContext,
  useContext,
  useEffect,
  useId,
  useMemo,
  useState,
  useTransition,
} from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Check, Plus, Undo2, X } from "lucide-react";

import { saveSettingsListAction } from "@/app/materias-primas/configuracion/actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input, Select } from "@/components/ui/field";
import { InfoTip } from "@/components/ui/info-tip";
import { Notice } from "@/components/ui/notice";
import { ScrollFocus } from "@/components/ui/scroll-focus";
import { Segmented } from "@/components/ui/segmented";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { reasonField } from "@/lib/forms/schemas";
import { changesLabel } from "@/lib/recipe-sheet";
import {
  CONTENT_UNITS,
  DIMENSIONS,
  IN_WORDS,
  LIST_INFO,
  changedKeys,
  inOrder,
  itemErrors,
  listPayload,
  newItem,
  readNumber,
  type FieldErrors,
  type ListFields,
  type ListItem,
  type SettingsListCode,
} from "@/lib/settings-lists";
import { cn } from "@/lib/utils";

// Una lista de Configuración del catálogo (ADR-0063): se edita en la tabla y se guarda junta, con motivo, con la barra
// de abajo (catalog.save_settings_list). Las 8 listas usan esta misma pieza. En el celular, de consulta.

export type UnitOption = { code: string; label: string; short: string };

type Ctx = {
  prefix: string;
  list: SettingsListCode;
  canEdit: boolean;
  units: UnitOption[];
  saved: ListItem[];
  draft: ListItem[];
  changed: Set<string>;
  errors: Map<string, FieldErrors>;
  showError: (key: string, field: keyof ListFields) => boolean;
  leave: (key: string, field: keyof ListFields) => void;
  setField: (key: string, patch: Partial<ListFields>) => void;
  setActive: (key: string, active: boolean) => void;
  undo: (key: string) => void;
  add: () => void;
  showInactive: boolean;
  setShowInactive: (v: boolean) => void;
  reason: string;
  setReason: (v: string) => void;
  state: ActionState;
  done: boolean;
  pending: boolean;
  discard: () => void;
  save: () => Promise<void>;
};

// El control con ese id o, si es un grupo (los botones del tipo de unidad), su primera opción.
function focusControl(id: string) {
  const el = document.getElementById(id);
  if (!el) return;
  (el.matches("input, select, button")
    ? el
    : (el.querySelector<HTMLElement>("input") ?? el)
  ).focus();
}

const ListContext = createContext<Ctx | null>(null);

function useList(): Ctx {
  const ctx = useContext(ListContext);
  if (!ctx) throw new Error("Falta SettingsListProvider.");
  return ctx;
}

export function SettingsListProvider({
  groupId,
  list,
  stamp,
  canEdit,
  initial,
  units,
  children,
}: {
  groupId: string;
  list: SettingsListCode;
  stamp: string;
  canEdit: boolean;
  initial: ListItem[];
  units: UnitOption[];
  children: React.ReactNode;
}) {
  const prefix = useId();
  const router = useRouter();
  const [saved, setSaved] = useState(initial);
  const [draft, setDraft] = useState(initial);
  const [counter, setCounter] = useState(0);
  // A dónde va el foco después de agregar, deshacer o quitar una fila (n: aunque sea el mismo lugar dos veces).
  const [focus, setFocus] = useState<{ id: string; n: number } | null>(null);
  const [left, setLeft] = useState<Set<string>>(new Set());
  const [tried, setTried] = useState(false);
  const [showInactive, setShowInactive] = useState(false);
  const [reason, setReason] = useState("");
  const [state, setState] = useState<ActionState>({});
  const [done, setDone] = useState(false);
  const [saving, setSaving] = useState(false);
  // Hasta que vuelve la lista guardada, sigue «Guardando…».
  const [returning, startReturn] = useTransition();
  const pending = saving || returning;
  const changed = useMemo(() => changedKeys(list, saved, draft), [list, saved, draft]);
  const errors = useMemo(
    () =>
      new Map(
        draft.filter((d) => changed.has(d.key)).map((d) => [d.key, itemErrors(list, d)] as const),
      ),
    [list, draft, changed],
  );
  useUnsavedWarning(canEdit && changed.size > 0);

  // Guardado: cuando vuelve la lista con su sello nuevo, el borrador es lo que dice la base.
  const [refresh, setRefresh] = useState(false);
  const [seenStamp, setSeenStamp] = useState(stamp);
  if (stamp !== seenStamp) {
    setSeenStamp(stamp);
    setSaved(initial);
    if (changed.size === 0 || refresh) setDraft(initial);
    setRefresh(false);
  }

  useEffect(() => {
    if (focus) focusControl(focus.id);
  }, [focus]);

  function edit(update: (d: ListItem[]) => ListItem[]) {
    setRefresh(false);
    setDone(false);
    setState({});
    setDraft(update);
  }

  async function save() {
    const firstBad = inOrder(list, draft).find(
      (d) => Object.keys(errors.get(d.key) ?? {}).length > 0,
    );
    if (firstBad) {
      const field = Object.keys(errors.get(firstBad.key) ?? {})[0];
      setTried(true);
      setState({ status: "bad", message: "Revisá los campos marcados." });
      focusControl(`${prefix}-${firstBad.key}-${field}`);
      return;
    }
    if (!reasonField.min(3).safeParse(reason).success) {
      setState({ status: "bad", message: "Escribí el motivo de los cambios." });
      document.getElementById(`${prefix}-motivo`)?.focus();
      return;
    }
    setSaving(true);
    try {
      const result = await saveSettingsListAction({
        groupId,
        list,
        expectedStamp: stamp,
        items: listPayload(list, saved, draft),
        reason,
      });
      if (result.status === "ok") {
        setState({});
        setReason("");
        setTried(false);
        setLeft(new Set());
        setRefresh(true);
        setDone(true);
        startReturn(() => router.refresh());
      } else {
        setState(result);
      }
    } catch {
      // Sin conexión: el borrador queda y se puede reintentar.
      setState({
        status: "bad",
        message: "No pudimos guardar: revisá la conexión y probá de nuevo.",
      });
    } finally {
      setSaving(false);
    }
  }

  const value: Ctx = {
    prefix,
    list,
    canEdit,
    units,
    saved,
    draft,
    changed,
    errors,
    showError: (key, field) =>
      Boolean(errors.get(key)?.[field]) && (tried || left.has(`${key}-${field}`)),
    leave: (key, field) => setLeft((s) => new Set(s).add(`${key}-${field}`)),
    setField: (key, patch) =>
      edit((d) => d.map((i) => (i.key === key ? { ...i, fields: { ...i.fields, ...patch } } : i))),
    // Al desactivar, los textos vuelven a lo guardado: la celda deja de editarse y no puede quedar con un error.
    setActive: (key, active) =>
      edit((d) =>
        d.map((i) => {
          if (i.key !== key) return i;
          const before = saved.find((x) => x.key === key);
          return { ...i, active, fields: active || !before ? i.fields : before.fields };
        }),
      ),
    undo: (key) => {
      const before = saved.find((s) => s.key === key);
      edit((d) =>
        before ? d.map((i) => (i.key === key ? before : i)) : d.filter((i) => i.key !== key),
      );
      // El botón desaparece: el foco va al nombre de la fila, o a «Agregar» si la fila ya no está.
      setFocus((f) => ({
        id: before ? `${prefix}-${key}-name` : `${prefix}-agregar`,
        n: (f?.n ?? 0) + 1,
      }));
    },
    add: () => {
      const item = newItem(counter + 1);
      setCounter(counter + 1);
      edit((d) => [...d, item]);
      setFocus((f) => ({ id: `${prefix}-${item.key}-name`, n: (f?.n ?? 0) + 1 }));
    },
    showInactive,
    setShowInactive,
    reason,
    setReason,
    state,
    done,
    pending,
    discard: () => {
      setDraft(saved);
      setState({});
      setTried(false);
      setLeft(new Set());
    },
    save,
  };
  return <ListContext.Provider value={value}>{children}</ListContext.Provider>;
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------
const changedRing = "border-dashed border-ink";
const cell = "border-b border-line px-3 py-1.5 align-middle text-sm text-ink";
const head =
  "sticky top-0 z-10 border-b border-line bg-app px-3 py-2 text-left text-sm font-medium text-none-ink";
// Tabla de carga: controles de 32 px en la computadora (44 en el celular; ADR-0046).
const small = "desk:min-h-8 text-sm";

function rowName(item: ListItem, list: SettingsListCode): string {
  return item.fields.name.trim() || LIST_INFO[list].newItem;
}

function TextCell({
  item,
  field,
  label,
  className,
  ...props
}: {
  item: ListItem;
  field: keyof ListFields;
  label: string;
  className?: string;
} & Omit<React.ComponentProps<"input">, "value" | "onChange" | "id">) {
  const { prefix, list, saved, errors, showError, leave, setField } = useList();
  const id = `${prefix}-${item.key}-${field}`;
  const bad = showError(item.key, field);
  const before = saved.find((s) => s.key === item.key);
  const dirty = !before || before.fields[field].trim() !== item.fields[field].trim();
  return (
    <div className="flex flex-col gap-0.5">
      <Input
        id={id}
        aria-label={`${label}: ${rowName(item, list)}`}
        aria-invalid={bad ? "true" : undefined}
        aria-required={REQUIRED.includes(field) ? "true" : undefined}
        aria-describedby={describe(bad && `${id}-error`, dirty && `${id}-cambio`)}
        value={item.fields[field]}
        onChange={(e) => setField(item.key, { [field]: e.target.value })}
        onBlur={() => leave(item.key, field)}
        className={cn(small, dirty && changedRing, className)}
        {...props}
      />
      <CellError id={`${id}-error`} show={bad} text={errors.get(item.key)?.[field]} />
      <Unsaved id={`${id}-cambio`} show={dirty} />
    </div>
  );
}

// El borde punteado es visual: el lector de pantalla lo escucha.
function Unsaved({ id, show }: { id: string; show: boolean }) {
  return show ? (
    <span id={id} className="sr-only">
      Cambio sin guardar
    </span>
  ) : null;
}

function describe(...ids: (string | false)[]): string | undefined {
  return ids.filter(Boolean).join(" ") || undefined;
}

const REQUIRED: (keyof ListFields)[] = [
  "name",
  "parentId",
  "content",
  "abbreviation",
  "code",
  "factor",
];

function CellError({ id, show, text }: { id: string; show: boolean; text: string | undefined }) {
  if (!show || !text) return null;
  return (
    <span id={id} className="text-xs font-medium text-bad-ink">
      {text}
    </span>
  );
}

function SelectCell({
  item,
  field,
  label,
  className,
  children,
}: {
  item: ListItem;
  field: keyof ListFields;
  label: string;
  className?: string;
  children: React.ReactNode;
}) {
  const { prefix, list, saved, errors, showError, leave, setField } = useList();
  const id = `${prefix}-${item.key}-${field}`;
  const bad = showError(item.key, field);
  const before = saved.find((s) => s.key === item.key);
  const dirty = before?.fields[field] !== item.fields[field];
  return (
    <div className="flex flex-col gap-0.5">
      <Select
        id={id}
        aria-label={`${label}: ${rowName(item, list)}`}
        aria-invalid={bad ? "true" : undefined}
        aria-required={REQUIRED.includes(field) ? "true" : undefined}
        aria-describedby={describe(bad && `${id}-error`, dirty && `${id}-cambio`)}
        value={item.fields[field]}
        onChange={(e) => setField(item.key, { [field]: e.target.value })}
        onBlur={() => leave(item.key, field)}
        className={cn(
          small,
          before?.fields[field] !== item.fields[field] && changedRing,
          className,
        )}
      >
        {children}
      </Select>
      <CellError id={`${id}-error`} show={bad} text={errors.get(item.key)?.[field]} />
      <Unsaved id={`${id}-cambio`} show={dirty} />
    </div>
  );
}

function capacityText(item: ListItem, units: UnitOption[]): string {
  const f = item.fields;
  if (f.capacity === "") return "—";
  if (f.capacityUnit === IN_WORDS) return `${readNumber(f.capacity)} ${f.capacityLabel}`;
  return `${readNumber(f.capacity)} ${units.find((u) => u.code === f.capacityUnit)?.short ?? f.capacityUnit}`;
}

function contentText(item: ListItem): string {
  const unit = CONTENT_UNITS.find((u) => u.value === item.fields.contentUnit)?.label ?? "";
  return `${readNumber(item.fields.content)} ${unit}`;
}

function factorText(item: ListItem): string {
  if (item.isBase) return "Base";
  return item.fields.factor
    ? `= ${readNumber(item.fields.factor)} ${item.baseUnit}`
    : "Sin equivalencia fija";
}

const BASE_UNIT: Record<string, string> = { mass: "g", volume: "ml", count: "u" };

function dimensionLabel(value: string): string {
  return DIMENSIONS.find((d) => d.value === value)?.label ?? "";
}

function isCategory(list: SettingsListCode): boolean {
  return list === "ingredient_categories" || list === "recipe_categories";
}

function NameCell({ item, editable }: { item: ListItem; editable: boolean }) {
  const { prefix, list, draft, saved } = useList();
  const before = saved.find((x) => x.key === item.key);
  // El sector y la partida no son datos de la versión: el nombre nuevo se ve en todas las recetas que lo usan.
  const renames =
    (list === "sectors" || list === "stations") &&
    before !== undefined &&
    item.uses > 0 &&
    before.fields.name.trim() !== item.fields.name.trim();
  const sub = isCategory(list) && (item.fields.parentId !== "" || item.id === null);
  return (
    <td className={cn(cell, sub && "pl-8")}>
      {editable ? (
        <div className="flex flex-wrap items-start gap-2">
          <div className="min-w-40 flex-1">
            <TextCell
              item={item}
              field="name"
              label="Nombre"
              maxLength={LIST_INFO[list].nameMax}
              placeholder={item.id === null ? LIST_INFO[list].newItem : undefined}
              className={isCategory(list) && !sub ? "font-semibold" : undefined}
            />
          </div>
          {isCategory(list) && item.id === null ? (
            <SelectCell item={item} field="parentId" label="Rubro" className="w-48">
              <option value="">Elegí el rubro</option>
              {draft
                .filter((d) => d.id !== null && d.fields.parentId === "")
                .map((d) => (
                  <option key={d.key} value={d.id ?? ""}>
                    {d.fields.name}
                  </option>
                ))}
            </SelectCell>
          ) : null}
        </div>
      ) : (
        <span
          id={`${prefix}-${item.key}-texto`}
          className={cn(isCategory(list) && !sub && "font-semibold")}
        >
          {item.fields.name}
        </span>
      )}
      {renames ? (
        <p role="status" className="text-xs text-warn-ink">
          {item.uses === 1
            ? "El nombre cambia en 1 receta, también si está publicada."
            : `El nombre cambia en ${item.uses} recetas, también en las publicadas.`}
        </p>
      ) : null}
    </td>
  );
}

// Activa o no, de un clic. Bloqueado (con el motivo al lado) si la base no lo va a aceptar.
function ActiveCell({ item }: { item: ListItem }) {
  const { prefix, list, canEdit, saved, setActive } = useList();
  const info = LIST_INFO[list];
  const word = item.active ? info.activeLabel : `In${info.activeLabel.toLowerCase()}`;
  const before = saved.find((s) => s.key === item.key);
  // El motivo bloquea la baja, no la reactivación.
  const blocked = item.why !== null && before?.active !== false;
  const toggled = before !== undefined && before.active !== item.active;
  if (!canEdit)
    return (
      <td className={cell}>
        <Badge status={item.active ? "ok" : "none"}>{word}</Badge>
      </td>
    );
  if (isCategory(list) && item.id !== null && item.fields.parentId === "")
    return (
      <td className={cell}>
        <Link
          href="/rubros"
          aria-label={`En Rubros: se da de baja ${item.fields.name}`}
          className="inline-flex min-h-touch items-center text-sm text-primary underline underline-offset-4 desk:min-h-8"
        >
          En Rubros
        </Link>
      </td>
    );
  // La base no lo va a aceptar: se dice, sin un botón que no hace nada.
  if (blocked && item.why)
    return (
      <td className={cell}>
        <div className="flex items-center gap-1">
          <Badge status="ok">{word}</Badge>
          <InfoTip label={`por qué no se da de baja ${item.fields.name}`} className="desk:size-8">
            No se puede dar de baja. {item.why}
          </InfoTip>
        </div>
      </td>
    );
  return (
    <td className={cell}>
      <div className="flex items-center gap-2">
        <button
          type="button"
          id={`${prefix}-${item.key}-activa`}
          aria-pressed={item.active}
          aria-label={`${info.activeLabel}: ${rowName(item, list)}`}
          aria-describedby={toggled ? `${prefix}-${item.key}-activa-cambio` : undefined}
          disabled={item.id === null}
          onClick={() => setActive(item.key, !item.active)}
          className={cn(
            "inline-flex size-touch shrink-0 items-center justify-center rounded-sm border-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed desk:size-8",
            item.active ? "border-ok bg-ok text-ok-ink" : "border-line bg-none text-none-ink",
            toggled && changedRing,
          )}
        >
          {item.active ? (
            <Check aria-hidden="true" className="size-4" />
          ) : (
            <X aria-hidden="true" className="size-4" />
          )}
        </button>
        <span aria-hidden="true" className="text-sm text-ink">
          {word}
        </span>
        <Unsaved id={`${prefix}-${item.key}-activa-cambio`} show={toggled} />
      </div>
    </td>
  );
}

function UndoCell({ item }: { item: ListItem }) {
  const { list, changed, undo } = useList();
  return (
    <td className={cn(cell, "w-12 px-1")}>
      {changed.has(item.key) ? (
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="desk:min-h-8 desk:w-8"
          aria-label={
            item.id === null
              ? `Quitar ${rowName(item, list)}`
              : `Deshacer los cambios de ${rowName(item, list)}`
          }
          onClick={() => undo(item.key)}
        >
          {item.id === null ? (
            <X aria-hidden="true" className="size-4" />
          ) : (
            <Undo2 aria-hidden="true" className="size-4" />
          )}
        </Button>
      ) : null}
    </td>
  );
}

function Cells({ item, editable }: { item: ListItem; editable: boolean }) {
  const { prefix, list, units, saved, errors, showError, setField } = useList();
  const fresh = item.id === null;
  const before = saved.find((s) => s.key === item.key);
  if (isCategory(list))
    return <td className={cn(cell, "text-ink-muted")}>{item.fields.code || "—"}</td>;
  if (list === "equipment")
    return (
      <td className={cell}>
        {editable ? (
          <div className="flex items-start gap-2">
            <TextCell
              item={item}
              field="capacity"
              label="Capacidad"
              inputMode="decimal"
              className="w-16 text-right tabular-nums"
            />
            <SelectCell item={item} field="capacityUnit" label="En qué" className="w-36">
              <option value="">Sin capacidad</option>
              {units.map((u) => (
                <option key={u.code} value={u.code}>
                  {u.label}
                </option>
              ))}
              <option value={IN_WORDS}>En palabras…</option>
            </SelectCell>
            {item.fields.capacityUnit === IN_WORDS ? (
              <TextCell
                item={item}
                field="capacityLabel"
                label="Capacidad en palabras"
                placeholder="canastos"
                maxLength={40}
                className="w-36"
              />
            ) : null}
          </div>
        ) : (
          capacityText(item, units)
        )}
      </td>
    );
  if (list === "measures")
    return (
      <>
        <td className={cell}>
          {editable ? (
            <div className="flex items-start gap-1">
              <TextCell
                item={item}
                field="content"
                label="Contiene"
                inputMode="decimal"
                className="w-20 text-right tabular-nums"
              />
              <Segmented
                name={`${prefix}-${item.key}-contentUnit`}
                legend={`Unidad: ${rowName(item, list)}`}
                hideLegend
                compact
                options={[...CONTENT_UNITS]}
                value={item.fields.contentUnit}
                onChange={(v) => setField(item.key, { contentUnit: v })}
                changed={Boolean(before) && before?.fields.contentUnit !== item.fields.contentUnit}
                className="min-w-40 p-0"
              />
            </div>
          ) : (
            <span className="tabular-nums">{contentText(item)}</span>
          )}
        </td>
        <td className={cell}>
          {editable ? (
            <TextCell
              item={item}
              field="usageNote"
              label="Se usa con"
              maxLength={120}
              placeholder={fresh ? "Salsas, sopas…" : undefined}
            />
          ) : (
            item.fields.usageNote || "—"
          )}
        </td>
      </>
    );
  if (list === "units")
    return (
      <>
        <td className={cell}>
          {editable ? (
            <TextCell
              item={item}
              field="abbreviation"
              label="Abreviatura"
              maxLength={12}
              className="w-24"
            />
          ) : (
            item.fields.abbreviation
          )}
        </td>
        <td className={cn(cell, !fresh && "text-ink-muted")}>
          {fresh ? (
            <TextCell
              item={item}
              field="code"
              label="Código"
              maxLength={20}
              autoCapitalize="none"
              placeholder="cucharon"
              className="w-32"
            />
          ) : (
            item.fields.code
          )}
        </td>
        <td className={cell}>
          {fresh ? (
            <div id={`${prefix}-${item.key}-dimension`} className="flex flex-col">
              <Segmented
                name={`${prefix}-${item.key}-tipo`}
                legend={`Tipo (obligatorio): ${rowName(item, list)}`}
                describedBy={
                  showError(item.key, "dimension")
                    ? `${prefix}-${item.key}-dimension-error`
                    : undefined
                }
                hideLegend
                compact
                options={[...DIMENSIONS]}
                value={item.fields.dimension}
                onChange={(v) =>
                  setField(item.key, {
                    dimension: v,
                    ...(v === "package" ? { factor: "" } : {}),
                  })
                }
                className="p-0"
              />
              <CellError
                id={`${prefix}-${item.key}-dimension-error`}
                show={showError(item.key, "dimension")}
                text={errors.get(item.key)?.dimension}
              />
            </div>
          ) : (
            dimensionLabel(item.fields.dimension)
          )}
        </td>
        <td className={cn(cell, "tabular-nums")}>
          {fresh ? (
            item.fields.dimension === "package" ? (
              "Sin equivalencia fija"
            ) : (
              <div className="flex items-center gap-1">
                <TextCell
                  item={item}
                  field="factor"
                  label="Equivale a (g, ml o unidades)"
                  inputMode="decimal"
                  placeholder="60"
                  className="w-24 text-right tabular-nums"
                />
                <span>{BASE_UNIT[item.fields.dimension] ?? ""}</span>
              </div>
            )
          ) : (
            factorText(item)
          )}
        </td>
      </>
    );
  if (list === "processes")
    return (
      <td className={cn(cell, !fresh && "text-ink-muted")}>
        {fresh ? (
          <TextCell
            item={item}
            field="code"
            label="Código"
            maxLength={30}
            autoCapitalize="characters"
            placeholder="PELADO"
            className="w-40 uppercase"
          />
        ) : (
          item.fields.code
        )}
      </td>
    );
  return null;
}

const EXTRA_HEADERS: Record<SettingsListCode, string[]> = {
  ingredient_categories: ["Código"],
  recipe_categories: ["Código"],
  sectors: [],
  stations: [],
  equipment: ["Capacidad"],
  measures: ["Contiene", "Se usa con"],
  units: ["Abreviatura", "Código", "Tipo", "Equivale a"],
  processes: ["Código"],
};

function visibleItems(ctx: Ctx): ListItem[] {
  const rows = ctx.draft.filter((d) => {
    const before = ctx.saved.find((s) => s.key === d.key);
    return ctx.showInactive || d.active || before?.active !== false;
  });
  return inOrder(ctx.list, rows);
}

// La tarjeta de la lista: título, ayuda, «Agregar» y la tabla, que se desplaza adentro con el encabezado fijo.
export function SettingsListCard() {
  const ctx = useList();
  const { prefix, list, canEdit, saved, changed, add, showInactive, setShowInactive, units } = ctx;
  const info = LIST_INFO[list];
  const rows = visibleItems(ctx);
  const inactive = saved.filter((s) => !s.active).length;
  const inactiveWord = info.activeLabel === "Activo" ? "los inactivos" : "las inactivas";
  return (
    <section
      aria-label={info.label}
      className="flex min-w-0 flex-col gap-3 rounded-md border border-line bg-surface p-4 desk:min-h-0"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-1">
          <h2 className="text-base font-semibold text-ink">{info.label}</h2>
          <InfoTip label={info.label.toLowerCase()}>{info.description}</InfoTip>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {inactive > 0 ? (
            <Button
              type="button"
              variant="outline"
              size="sm"
              aria-pressed={showInactive}
              onClick={() => setShowInactive(!showInactive)}
            >
              {showInactive ? `Ocultar ${inactiveWord}` : `Ver ${inactiveWord} (${inactive})`}
            </Button>
          ) : null}
          {canEdit ? (
            <Button
              id={`${prefix}-agregar`}
              type="button"
              variant="outline"
              size="sm"
              className="hidden desk:inline-flex"
              onClick={add}
            >
              <Plus aria-hidden="true" />
              {info.add}
            </Button>
          ) : null}
        </div>
      </div>
      {canEdit ? (
        <p className="text-sm text-ink-muted desk:hidden">
          Para editar, entrá desde la computadora.
        </p>
      ) : (
        <p className="text-sm text-ink-muted">Solo lectura. {info.owner}</p>
      )}
      {rows.length === 0 ? (
        <p className="text-base text-ink">
          {inactive > 0
            ? `No hay nada activo: mirá ${inactiveWord}.`
            : canEdit
              ? `La lista está vacía: empezá con «${info.add}».`
              : "La lista todavía está vacía."}
        </p>
      ) : (
        <>
          <div
            role="region"
            aria-label={`Tabla de ${info.label.toLowerCase()}`}
            className="relative hidden min-h-0 flex-[1_1_0px] scroll-pt-12 overflow-auto focus-visible:outline-2 focus-visible:outline-primary desk:block"
          >
            <ScrollFocus />
            <table className="w-full border-separate border-spacing-0">
              <caption className="sr-only">{info.label}</caption>
              <thead>
                <tr>
                  <th scope="col" className={head}>
                    Nombre{canEdit ? <span aria-hidden="true"> *</span> : null}
                  </th>
                  {EXTRA_HEADERS[list].map((h) => (
                    <th key={h} scope="col" className={head}>
                      {h}
                    </th>
                  ))}
                  {info.uses ? (
                    <th scope="col" className={cn(head, "text-right")}>
                      {info.uses}
                    </th>
                  ) : null}
                  <th scope="col" className={head}>
                    {info.activeLabel}
                  </th>
                  {canEdit ? (
                    <th scope="col" className={cn(head, "w-12 px-1")}>
                      <span className="sr-only">Deshacer</span>
                    </th>
                  ) : null}
                </tr>
              </thead>
              <tbody>
                {rows.map((item) => {
                  // Lo dado de baja no se edita: primero se reactiva.
                  const editable = canEdit && item.editable && item.active;
                  return (
                    <tr
                      key={item.key}
                      data-changed={changed.has(item.key) ? "" : undefined}
                      className={cn(item.id === null && "bg-app")}
                    >
                      <NameCell item={item} editable={editable} />
                      <Cells item={item} editable={editable} />
                      {info.uses ? (
                        <td className={cn(cell, "text-right tabular-nums")}>
                          {item.id === null ? "—" : item.uses}
                        </td>
                      ) : null}
                      <ActiveCell item={item} />
                      {canEdit ? <UndoCell item={item} /> : null}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          {/* En el celular, de consulta. */}
          <ul className="flex flex-col gap-2 desk:hidden" aria-label={info.label}>
            {rows
              .filter((i) => i.id !== null)
              .map((item) => (
                <li
                  key={item.key}
                  className={cn(
                    "flex min-h-touch items-center justify-between gap-2 rounded-sm border border-line px-3 py-2",
                    isCategory(list) && item.fields.parentId !== "" && "ml-4",
                  )}
                >
                  <div className="flex min-w-0 flex-1 flex-col break-words">
                    <span
                      className={cn(
                        "text-base text-ink",
                        isCategory(list) && item.fields.parentId === "" && "font-semibold",
                      )}
                    >
                      {item.fields.name}
                    </span>
                    <span className="text-sm text-ink-muted">
                      {[
                        list === "equipment" ? capacityText(item, units) : null,
                        list === "measures" ? contentText(item) : null,
                        list === "measures" ? item.fields.usageNote : null,
                        list === "units" ? item.fields.abbreviation : null,
                        list === "units" ? factorText(item) : null,
                        list === "processes" ? item.fields.code : null,
                        info.uses ? `${info.uses}: ${item.uses}` : null,
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                    </span>
                  </div>
                  <Badge status={item.active ? "ok" : "none"}>
                    {item.active ? info.activeLabel : `In${info.activeLabel.toLowerCase()}`}
                  </Badge>
                </li>
              ))}
          </ul>
        </>
      )}
    </section>
  );
}

export function SettingsListBar() {
  const { prefix, canEdit, changed, reason, setReason, state, done, pending, discard, save } =
    useList();
  if (!canEdit) return null;
  const count = changed.size;
  return (
    <div className="sticky bottom-0 z-20 -mx-gutter hidden flex-col gap-2 border-t border-line bg-surface px-gutter py-2 desk:col-span-2 desk:flex wide:-mx-gutter-wide wide:px-gutter-wide">
      <FormNotice state={state} />
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-base font-semibold text-ink" role="status">
          {pending && done ? "Guardando…" : changesLabel(count)}
        </span>
        <div className="mr-auto">
          {done && !pending && count === 0 ? (
            <Notice status="ok" className="items-center px-3 py-1 text-sm">
              Cambios guardados.
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
