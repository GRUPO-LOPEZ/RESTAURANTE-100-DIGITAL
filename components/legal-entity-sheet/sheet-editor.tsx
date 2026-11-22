"use client";

import { createContext, useContext, useId, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Plus, Undo2, X } from "lucide-react";

import { saveLegalEntitySheetAction } from "@/app/configuracion/structure-actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input, Select } from "@/components/ui/field";
import { InfoTip } from "@/components/ui/info-tip";
import { Notice } from "@/components/ui/notice";
import { Segmented } from "@/components/ui/segmented";
import { ToggleField } from "@/components/ui/toggle-field";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { legalEntitySheetSchema, reasonField } from "@/lib/forms/schemas";
import {
  countLegalEntityChanges,
  legalEntityChanges,
  legalEntityPayload,
  type LegalEntityChanges,
  type LegalEntityDraft,
  type LegalEntityField,
  type LegalEntityFlag,
} from "@/lib/org-sheet";
import { changesLabel } from "@/lib/recipe-sheet";
import { validCuit } from "@/lib/suppliers";
import { cn } from "@/lib/utils";

// Ficha de la razón social con los datos de la constancia de inscripción de ARCA (Tanda 1 de Soy, ADR-0061), con el
// patrón de las fichas sin scroll (ADR-0046): un borrador compartido que se guarda junto, con motivo, en una
// transacción (org.save_legal_entity_sheet). La edita solo quien administra todo el grupo (lo decide la base).

type Ctx = {
  legalEntityId: string;
  prefix: string;
  editable: boolean;
  provinces: { code: string; name: string }[];
  saved: LegalEntityDraft;
  draft: LegalEntityDraft;
  setDraft: (update: (d: LegalEntityDraft) => LegalEntityDraft) => void;
  changed: LegalEntityChanges;
  count: number;
  reason: string;
  setReason: (v: string) => void;
  state: ActionState;
  pending: boolean;
  notice: { status: "ok" | "info"; text: string } | null;
  discard: () => void;
  save: () => Promise<void>;
};

const SheetContext = createContext<Ctx | null>(null);

function useSheet(): Ctx {
  const ctx = useContext(SheetContext);
  if (!ctx) throw new Error("Falta LegalEntitySheetProvider.");
  return ctx;
}

export function LegalEntitySheetProvider({
  legalEntityId,
  stamp,
  editable,
  initial,
  provinces,
  notice = null,
  children,
}: {
  legalEntityId: string;
  stamp: string | null;
  editable: boolean;
  initial: LegalEntityDraft;
  provinces: { code: string; name: string }[];
  notice?: { status: "ok" | "info"; text: string } | null;
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
  const changed = useMemo(() => legalEntityChanges(saved, draft), [saved, draft]);
  const count = countLegalEntityChanges(changed);
  useUnsavedWarning(editable && count > 0);
  const [seenStamp, setSeenStamp] = useState(stamp);
  if (stamp !== seenStamp) {
    setSeenStamp(stamp);
    setSaved(initial);
    if (count === 0) setDraftState(initial);
  }

  function discard() {
    setDraftState(saved);
    setState({});
  }

  async function save() {
    const parsed = legalEntitySheetSchema.safeParse({
      legalEntityId,
      expectedStamp: stamp ?? "",
      reason,
      changes: legalEntityPayload(saved, draft),
    });
    if (!parsed.success) {
      const issue = parsed.error.issues[0];
      if (!reasonField.safeParse(reason).success && issue?.path[0] === "reason") {
        setState({ status: "bad", message: "Escribí el motivo de los cambios." });
        document.getElementById(`${prefix}-motivo`)?.focus();
      } else {
        setState({ status: "bad", message: issue?.message ?? "Revisá los datos." });
      }
      return;
    }
    setPending(true);
    try {
      const result = await saveLegalEntitySheetAction(parsed.data);
      setState(result.status === "ok" ? {} : result);
      if (result.status === "ok") {
        setSaved(draft);
        setReason("");
        const q = new URLSearchParams(search.toString());
        q.set("aviso", "guardado");
        router.replace(`${pathname}?${q}`, { scroll: false });
      }
    } finally {
      setPending(false);
    }
  }

  const value: Ctx = {
    legalEntityId,
    prefix,
    editable,
    provinces,
    saved,
    draft,
    setDraft: (update) => setDraftState((d) => update(d)),
    changed,
    count,
    reason,
    setReason,
    state,
    pending,
    notice,
    discard,
    save,
  };
  return <SheetContext.Provider value={value}>{children}</SheetContext.Provider>;
}

// ---------------------------------------------------------------------------
// Piezas comunes
// ---------------------------------------------------------------------------
const changedRing = "border-dashed border-ink";
const labelClass = "text-sm font-medium text-ink";
const small = "desk:min-h-control-sm";

function ReadRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex min-w-0 flex-col">
      <dt className={labelClass}>{label}</dt>
      <dd className="text-base break-words text-ink-muted">{value || "—"}</dd>
    </div>
  );
}

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

function TextField({
  field,
  label,
  required = false,
  maxLength,
  type = "text",
  inputMode,
  placeholder,
}: {
  field: LegalEntityField;
  label: string;
  required?: boolean;
  maxLength?: number;
  type?: string;
  inputMode?: React.HTMLAttributes<HTMLInputElement>["inputMode"];
  placeholder?: string;
}) {
  const { prefix, draft, saved, setDraft, changed } = useSheet();
  const [left, setLeft] = useState(false);
  const id = `${prefix}-${field}`;
  const invalid = required && left && draft.fields[field].trim() === "";
  return (
    <Split
      edit={
        <div className="flex min-w-0 flex-col gap-1">
          <label htmlFor={id} className={labelClass}>
            {label}
            {required ? <span aria-hidden="true"> *</span> : null}
          </label>
          {invalid ? (
            <span id={`${id}-falta`} className="sr-only">
              Falta {label}
            </span>
          ) : null}
          <Input
            aria-invalid={invalid ? "true" : undefined}
            aria-describedby={invalid ? `${id}-falta` : undefined}
            onBlur={() => setLeft(true)}
            id={id}
            type={type}
            inputMode={inputMode}
            value={draft.fields[field]}
            maxLength={maxLength}
            placeholder={placeholder}
            aria-required={required ? "true" : undefined}
            onChange={(e) =>
              setDraft((d) => ({ ...d, fields: { ...d.fields, [field]: e.target.value } }))
            }
            className={cn(small, changed.fields.includes(field) && changedRing)}
          />
        </div>
      }
      read={
        <dl>
          <ReadRow
            label={label}
            value={type === "date" ? formatDay(saved.fields[field]) : saved.fields[field]}
          />
        </dl>
      }
    />
  );
}

function ChoiceField({
  field,
  legend,
  options,
  required = false,
}: {
  field: LegalEntityField;
  legend: string;
  options: { value: string; label: string }[];
  required?: boolean;
}) {
  const { prefix, draft, saved, setDraft, changed } = useSheet();
  return (
    <Split
      edit={
        <Segmented
          name={`${prefix}-${field}`}
          legend={required ? `${legend} *` : legend}
          compact
          options={options}
          value={draft.fields[field]}
          changed={changed.fields.includes(field)}
          onChange={(v) => setDraft((d) => ({ ...d, fields: { ...d.fields, [field]: v } }))}
        />
      }
      read={
        <dl>
          <ReadRow
            label={legend}
            value={options.find((o) => o.value === saved.fields[field])?.label ?? ""}
          />
        </dl>
      }
    />
  );
}

function ProvinceField({
  field,
  label,
  required = false,
}: {
  field: LegalEntityField;
  label: string;
  required?: boolean;
}) {
  const { prefix, draft, saved, setDraft, changed, provinces } = useSheet();
  const id = `${prefix}-${field}`;
  return (
    <Split
      edit={
        <div className="flex min-w-0 flex-col gap-1">
          <label htmlFor={id} className={labelClass}>
            {label}
            {required ? <span aria-hidden="true"> *</span> : null}
          </label>
          <Select
            id={id}
            value={draft.fields[field]}
            onChange={(e) =>
              setDraft((d) => ({ ...d, fields: { ...d.fields, [field]: e.target.value } }))
            }
            className={cn(small, "w-full", changed.fields.includes(field) && changedRing)}
          >
            <option value="">Elegí</option>
            {provinces.map((p) => (
              <option key={p.code} value={p.code}>
                {p.name}
              </option>
            ))}
          </Select>
        </div>
      }
      read={
        <dl>
          <ReadRow
            label={label}
            value={provinces.find((p) => p.code === saved.fields[field])?.name ?? ""}
          />
        </dl>
      }
    />
  );
}

function FlagField({ flag, label }: { flag: LegalEntityFlag; label: string }) {
  const { prefix, draft, saved, setDraft, changed } = useSheet();
  return (
    <Split
      edit={
        <div
          className={cn(
            "flex items-center justify-between gap-2 rounded-sm border border-transparent p-1",
            changed.flags.includes(flag) && changedRing,
          )}
        >
          <ToggleField
            key={String(saved.flags[flag])}
            name={`${prefix}-${flag}`}
            id={`${prefix}-${flag}`}
            label={label}
            defaultValue={saved.flags[flag]}
            value={draft.flags[flag]}
            onChange={(v) => setDraft((d) => ({ ...d, flags: { ...d.flags, [flag]: v } }))}
          />
        </div>
      }
      read={
        <dl>
          <ReadRow label={label} value={saved.flags[flag] ? "Sí" : "No"} />
        </dl>
      }
    />
  );
}

function formatDay(iso: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return "";
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

// ---------------------------------------------------------------------------
// Identidad y domicilio fiscal
// ---------------------------------------------------------------------------
export function IdentitySection() {
  const { draft } = useSheet();
  const cuit = draft.fields.tax_id.trim();
  return (
    <div className="flex flex-col gap-3">
      <TextField field="name" label="Razón social" required maxLength={200} />
      <div className="flex items-end gap-2">
        <div className="flex-1">
          <TextField field="tax_id" label="CUIT" required maxLength={13} inputMode="numeric" />
        </div>
        {cuit ? (
          validCuit(cuit) ? (
            <Badge status="ok">Válido</Badge>
          ) : (
            <Badge status="bad">No es válido</Badge>
          )
        ) : null}
      </div>
      <ChoiceField
        field="legal_form"
        legend="Forma jurídica"
        required
        options={[
          { value: "srl", label: "S.R.L." },
          { value: "sa", label: "S.A." },
          { value: "sas", label: "S.A.S." },
          { value: "person", label: "Persona" },
        ]}
      />
      <div className="grid grid-cols-2 gap-3">
        <TextField field="activity_start" label="Inicio de actividades" required type="date" />
        <TextField field="trade_name" label="Nombre de fantasía" maxLength={200} />
      </div>
    </div>
  );
}

export function FiscalAddressSection() {
  return (
    <div className="flex flex-col gap-3">
      <TextField field="fiscal_street" label="Calle y número" required maxLength={200} />
      <div className="grid grid-cols-[1fr_7rem] gap-3">
        <TextField field="fiscal_locality" label="Localidad" required maxLength={120} />
        <TextField
          field="fiscal_postal_code"
          label="CP"
          required
          maxLength={8}
          placeholder="B1713"
        />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <ProvinceField field="fiscal_province" label="Provincia" required />
        <TextField
          field="electronic_domicile"
          label="Domicilio fiscal electrónico"
          type="email"
          maxLength={320}
          placeholder="fiscal@empresa.com"
        />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Impuestos
// ---------------------------------------------------------------------------
export function TaxesSection() {
  const { draft } = useSheet();
  return (
    <div className="flex flex-col gap-3">
      <ChoiceField
        field="vat_condition"
        legend="IVA"
        required
        options={[
          { value: "registered", label: "Resp. inscripto" },
          { value: "monotax", label: "Monotributo" },
          { value: "exempt", label: "Exento" },
        ]}
      />
      <ChoiceField
        field="income_tax"
        legend="Ganancias"
        required
        options={[
          { value: "registered", label: "Inscripta" },
          { value: "exempt", label: "Exenta" },
          { value: "not_subject", label: "No alcanzada" },
        ]}
      />
      <ChoiceField
        field="gross_income_regime"
        legend="Ingresos Brutos"
        required
        options={[
          { value: "multilateral", label: "Conv. Multilateral" },
          { value: "local", label: "Local" },
          { value: "exempt", label: "Exento" },
        ]}
      />
      {draft.fields.gross_income_regime !== "exempt" ? (
        <div className="grid grid-cols-2 gap-3">
          <TextField field="gross_income_number" label="N.º IIBB" required maxLength={20} />
          <ProvinceField field="gross_income_province" label="Jurisdicción sede" />
        </div>
      ) : null}
      <div className="grid grid-cols-2 gap-x-3 gap-y-1">
        <FlagField flag="is_employer" label="Empleadora" />
        <FlagField flag="is_perception_agent" label="Agente de percepción" />
        <div className="col-span-2 flex items-center gap-1">
          <FlagField flag="is_withholding_agent" label="Agente de retención" />
          <InfoTip label="agente de retención">
            Si es agente de retención, los pagos a proveedores tienen que calcularla. Quedó
            preparado en Pagos; el cálculo todavía no está.
          </InfoTip>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Actividades en ARCA: una principal y las secundarias
// ---------------------------------------------------------------------------
export function ActivitiesSection() {
  const { prefix, draft, saved, setDraft, changed, editable } = useSheet();
  const [code, setCode] = useState("");
  const [description, setDescription] = useState("");
  const [addError, setAddError] = useState("");
  const list = (editable ? draft : saved).activities.filter((a) => !a.removed);
  const removed = editable ? draft.activities.filter((a) => a.removed && a.id) : [];

  function add() {
    if (!/^[0-9]{6}$/.test(code.trim()) || !description.trim()) {
      setAddError("La actividad lleva su código de 6 cifras y su descripción.");
      return;
    }
    setAddError("");
    setDraft((d) => ({
      ...d,
      activities: [
        ...d.activities,
        {
          key: `nueva-${Date.now()}`,
          id: null,
          code: code.trim(),
          description: description.trim(),
          primary: !d.activities.some((a) => !a.removed && a.primary),
          removed: false,
        },
      ],
    }));
    setCode("");
    setDescription("");
  }

  const makePrimary = (key: string) =>
    setDraft((d) => ({
      ...d,
      activities: d.activities.map((a) => ({ ...a, primary: a.key === key })),
    }));
  const remove = (key: string, value: boolean) =>
    setDraft((d) => ({
      ...d,
      activities: d.activities
        .map((a) =>
          a.key === key ? { ...a, removed: value, primary: value ? false : a.primary } : a,
        )
        .filter((a) => a.id !== null || !a.removed),
    }));

  return (
    <div className="flex flex-col gap-2">
      {list.length === 0 ? (
        <p className="text-sm text-ink-muted">Sin actividades cargadas.</p>
      ) : null}
      <ul className="flex flex-col gap-1" aria-label="Actividades en ARCA">
        {list.map((a) => (
          <li
            key={a.key}
            className={cn(
              "flex items-center gap-2 rounded-sm border border-transparent px-1 py-1 text-sm",
              changed.activities.includes(a.key) && changedRing,
            )}
          >
            <span className="font-medium text-ink tabular-nums">{a.code}</span>
            <span className="min-w-0 flex-1 text-ink-muted">{a.description}</span>
            {a.primary ? (
              <Badge status="info">Principal</Badge>
            ) : editable ? (
              <button
                type="button"
                className="hidden min-h-8 text-sm text-primary underline-offset-4 hover:underline desk:inline"
                onClick={() => makePrimary(a.key)}
              >
                Hacer principal
              </button>
            ) : (
              <Badge status="neutral">Secundaria</Badge>
            )}
            {editable ? (
              <button
                type="button"
                aria-label={`Quitar la actividad ${a.code}`}
                className="hidden min-h-8 min-w-8 items-center justify-center text-ink-muted hover:text-ink desk:flex"
                onClick={() => remove(a.key, true)}
              >
                <X aria-hidden="true" className="size-4" />
              </button>
            ) : null}
          </li>
        ))}
      </ul>
      {removed.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2 text-sm text-ink-muted">
          <span>Quitadas:</span>
          {removed.map((a) => (
            <button
              key={a.key}
              type="button"
              className="inline-flex min-h-8 items-center gap-1 text-primary underline-offset-4 hover:underline"
              aria-label={`Volver a usar la actividad ${a.code}`}
              onClick={() => remove(a.key, false)}
            >
              <Undo2 aria-hidden="true" className="size-4" />
              {a.code}
            </button>
          ))}
        </div>
      ) : null}
      {editable ? (
        <div className="hidden gap-2 desk:flex">
          <label htmlFor={`${prefix}-act-code`} className="sr-only">
            Código de la actividad
          </label>
          <Input
            id={`${prefix}-act-code`}
            placeholder="561011"
            inputMode="numeric"
            maxLength={6}
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/[^0-9]/g, ""))}
            className={cn(small, "w-24")}
          />
          <label htmlFor={`${prefix}-act-desc`} className="sr-only">
            Descripción de la actividad
          </label>
          <Input
            id={`${prefix}-act-desc`}
            placeholder="Descripción"
            aria-invalid={addError ? "true" : undefined}
            aria-describedby={addError ? `${prefix}-act-error` : undefined}
            maxLength={200}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className={cn(small, "flex-1")}
          />
          <Button type="button" variant="outline" className={small} onClick={add}>
            <Plus aria-hidden="true" />
            Agregar
          </Button>
        </div>
      ) : null}
      {addError ? (
        <p id={`${prefix}-act-error`} className="text-sm text-bad-ink">
          {addError}
        </p>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Barra fija
// ---------------------------------------------------------------------------
export function SheetBar() {
  const { prefix, editable, count, reason, setReason, state, pending, discard, save, notice } =
    useSheet();
  if (!editable) return null;
  return (
    <div className="sticky bottom-0 z-10 -mx-gutter hidden flex-col gap-2 border-t border-line bg-surface px-gutter py-2 desk:flex wide:-mx-gutter-wide wide:px-gutter-wide">
      <FormNotice state={state} />
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-base font-semibold text-ink" role="status">
          {changesLabel(count)}
        </span>
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
