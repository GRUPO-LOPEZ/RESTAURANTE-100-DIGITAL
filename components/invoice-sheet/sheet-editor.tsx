"use client";

import { createContext, useContext, useId, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Check, Plus, Trash2, X } from "lucide-react";

import { saveInvoiceAction } from "@/app/compras/facturas/actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { SidePanel } from "@/components/ui/dialog";
import { Input, Select } from "@/components/ui/field";
import { DateInput } from "@/components/ui/date-input";
import { InfoTip } from "@/components/ui/info-tip";
import { Notice } from "@/components/ui/notice";
import { Segmented } from "@/components/ui/segmented";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import {
  AMOUNT_FIELDS,
  AUTHORIZATION_KINDS,
  CHECK_LABELS,
  INVOICE_CLASSES,
  INVOICE_VAT_RATES,
  LINE_CLASS_LABELS,
  NEW_LINE_CLASSES,
  TAX_KIND_LABELS,
  countInvoiceChanges,
  headerAmounts,
  invoiceChanges,
  invoicePayload,
  isClassA,
  isFiscal,
  lineAmount,
  linesNet,
  readNumber,
  shortDate,
  totalsDifference,
  type CheckRow,
  type HeaderField,
  type InvoiceChanges,
  type InvoiceClass,
  type InvoiceDraft,
  type InvoiceLineClass,
  type InvoiceTaxKind,
  type LineDraft,
} from "@/lib/invoices";
import { formatMoney } from "@/lib/money";
import { changesLabel } from "@/lib/recipe-sheet";
import { formatCuit } from "@/lib/suppliers";
import { cn } from "@/lib/utils";

// Ficha de una factura (Fase 3, Prompt 5B, ADR-0058), con el patrón de las fichas sin scroll (ADR-0046): la página (del
// servidor) pone cada parte en su tarjeta; los datos, el pie, las líneas y las percepciones comparten un borrador y se
// guardan juntos, con un motivo, en una transacción (purchasing.save_invoice). Guardar la vuelve a «cargada»: hay que
// controlarla de nuevo. En el celular la ficha es de consulta (ADR-0036).

type Ctx = {
  invoiceId: string;
  prefix: string;
  editable: boolean;
  saved: InvoiceDraft;
  draft: InvoiceDraft;
  setDraft: (update: (d: InvoiceDraft) => InvoiceDraft) => void;
  changed: InvoiceChanges;
  count: number;
  reason: string;
  setReason: (v: string) => void;
  state: ActionState;
  pending: boolean;
  notice: { status: "ok" | "info" | "warn"; text: string } | null;
  lineChecks: Record<string, CheckRow[]>;
  discard: () => void;
  save: () => Promise<void>;
};

const SheetContext = createContext<Ctx | null>(null);

function useSheet(): Ctx {
  const ctx = useContext(SheetContext);
  if (!ctx) throw new Error("Falta InvoiceSheetProvider.");
  return ctx;
}

export function InvoiceSheetProvider({
  invoiceId,
  version,
  editable,
  initial,
  lineChecks,
  notice = null,
  children,
}: {
  invoiceId: string;
  // El último cambio de la factura: cuando cambia (después de guardar), llega lo guardado.
  version: string;
  editable: boolean;
  initial: InvoiceDraft;
  lineChecks: Record<string, CheckRow[]>;
  notice?: { status: "ok" | "info" | "warn"; text: string } | null;
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
  const changed = useMemo(() => invoiceChanges(saved, draft), [saved, draft]);
  const count = countInvoiceChanges(changed);
  useUnsavedWarning(editable && count > 0);
  // Después de guardar llega lo guardado con su versión nueva (las líneas, con sus ids nuevos): se toma.
  const [seenVersion, setSeenVersion] = useState(version);
  if (version !== seenVersion) {
    setSeenVersion(version);
    setSaved(initial);
    if (count === 0) setDraftState(initial);
  }

  function discard() {
    setDraftState(saved);
    setState({});
  }

  async function save() {
    if (reason.trim().length < 3) {
      setState({ status: "bad", message: "Escribí el motivo de los cambios." });
      document.getElementById(`${prefix}-motivo`)?.focus();
      return;
    }
    const built = invoicePayload(saved, draft);
    if (!built.ok) {
      setState({ status: "bad", message: built.message });
      return;
    }
    setPending(true);
    try {
      const result = await saveInvoiceAction({
        invoiceId,
        reason: reason.trim(),
        ...built.payload,
      });
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
    invoiceId,
    prefix,
    editable,
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
    lineChecks,
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
// Tarjetas angostas: controles de 32 px en la computadora (44 en el celular; ADR-0045 y ADR-0046).
const small = "desk:min-h-8 desk:px-2";

// Para leer: la etiqueta a la izquierda y el valor a la derecha, en un renglón (las tarjetas son angostas).
function ReadRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex min-w-0 flex-wrap items-baseline justify-between gap-x-3 border-b border-line py-1 last:border-b-0">
      <dt className="text-sm text-ink">{label}</dt>
      <dd className="ml-auto min-w-0 text-right text-base [overflow-wrap:anywhere] text-ink tabular-nums">
        {value || "—"}
      </dd>
    </div>
  );
}

// Un dato fijo dentro de la parte editable (no se cambia acá).
function FixedRow({
  label,
  value,
  half = false,
}: {
  label: string;
  value: string;
  half?: boolean;
}) {
  if (half)
    return (
      <p className="flex min-w-0 flex-col gap-1 text-sm text-ink">
        <span>{label}</span>
        <span className="flex min-h-control-sm items-center text-base whitespace-nowrap tabular-nums">
          {value || "—"}
        </span>
      </p>
    );
  return (
    <p className="col-span-2 flex items-baseline justify-between gap-3 text-sm text-ink">
      <span>{label}</span>
      <span className="text-base whitespace-nowrap tabular-nums">{value || "—"}</span>
    </p>
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

function HeaderInput({
  field,
  label,
  tip,
  inputMode = "text",
  type = "text",
  maxLength,
  className,
}: {
  field: HeaderField;
  label: string;
  tip?: string;
  inputMode?: React.HTMLAttributes<HTMLInputElement>["inputMode"];
  type?: string;
  maxLength?: number;
  className?: string;
}) {
  const { prefix, draft, setDraft, changed } = useSheet();
  const id = `${prefix}-${field}`;
  return (
    <div className={cn("flex min-w-0 flex-col gap-1", className)}>
      <span className="flex items-center gap-1">
        <label htmlFor={id} className={labelClass}>
          {label}
        </label>
        {tip ? <InfoTip label={label.toLowerCase()}>{tip}</InfoTip> : null}
      </span>
      {type === "date" ? (
        // dd/mm/aaaa, nunca el formato del idioma de Chrome (criterio 12 de Soy, ADR-0068).
        <DateInput
          id={id}
          value={draft.header[field]}
          onChange={(iso) => setDraft((d) => ({ ...d, header: { ...d.header, [field]: iso } }))}
          inputClassName={cn(small, changed.header.includes(field) && changedRing)}
        />
      ) : (
        <Input
          id={id}
          type={type}
          inputMode={inputMode}
          maxLength={maxLength}
          value={draft.header[field]}
          onChange={(e) =>
            setDraft((d) => ({ ...d, header: { ...d.header, [field]: e.target.value } }))
          }
          className={cn(
            small,
            inputMode === "decimal" && "text-right tabular-nums",
            changed.header.includes(field) && changedRing,
          )}
        />
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Datos de la factura
// ---------------------------------------------------------------------------
export function HeaderSection({ legalEntityTaxId }: { legalEntityTaxId: string | null }) {
  const { prefix, draft, setDraft, changed } = useSheet();
  const h = draft.header;
  const fiscal = isFiscal(h.invoice_class as InvoiceClass);
  const classLabel = INVOICE_CLASSES.find((c) => c.value === h.invoice_class)?.label ?? "";
  const cuit = (v: string) => (v ? formatCuit(v) : "");
  return (
    <Split
      edit={
        <div className="grid grid-cols-2 items-end gap-x-3 gap-y-2">
          <div className="col-span-2 flex min-w-0 flex-col gap-1">
            <label htmlFor={`${prefix}-clase`} className={labelClass}>
              Comprobante
            </label>
            <Select
              id={`${prefix}-clase`}
              value={h.invoice_class}
              onChange={(e) =>
                setDraft((d) => ({ ...d, header: { ...d.header, invoice_class: e.target.value } }))
              }
              className={cn(small, changed.header.includes("invoice_class") && changedRing)}
            >
              {INVOICE_CLASSES.map((c) => (
                <option key={c.value} value={c.value}>
                  {c.label}
                </option>
              ))}
            </Select>
          </div>
          {fiscal ? (
            <HeaderInput
              field="point_of_sale"
              label="Pto. de venta"
              inputMode="numeric"
              maxLength={5}
            />
          ) : null}
          <HeaderInput
            field="number"
            label="Número"
            inputMode="numeric"
            maxLength={8}
            className={fiscal ? undefined : "col-span-2"}
          />
          {/* Fecha y vencimiento en la misma fila: la columna entra sin scroll (criterio 4 de Soy, ADR-0068). */}
          <HeaderInput field="issued_on" label="Fecha" type="date" />
          <HeaderInput
            field="due_on"
            label="Vencimiento impreso"
            tip="El que dice el papel. Vacío: sale de la condición de pago del proveedor (contado, el mismo día; cuenta corriente, la fecha más los días)."
            type="date"
          />
          {fiscal ? (
            <>
              <Segmented
                name={`${prefix}-aut`}
                legend="Autorización"
                options={AUTHORIZATION_KINDS}
                value={h.authorization_kind}
                onChange={(v) =>
                  setDraft((d) => ({ ...d, header: { ...d.header, authorization_kind: v } }))
                }
                changed={changed.header.includes("authorization_kind")}
                compact
                // Desde 1700 px hay ancho para ponerlos en una fila: entra en 1715 × 843 (ADR-0068).
                className="col-span-2 -m-1 wide:col-span-1"
              />
              <HeaderInput
                field="authorization_code"
                label="Número de autorización"
                inputMode="numeric"
                maxLength={14}
                className="col-span-2 wide:col-span-1"
              />
            </>
          ) : null}
          <FixedRow label="CUIT del emisor" value={cuit(h.issuer_tax_id)} />
          {/* El CUIT del receptor al lado del de la razón social del local: se comparan de un vistazo y la columna
              entra sin scroll (ADR-0068). */}
          <HeaderInput
            field="receiver_tax_id"
            label="CUIT del receptor"
            inputMode="numeric"
            maxLength={13}
            className={legalEntityTaxId ? undefined : "col-span-2"}
          />
          {legalEntityTaxId ? (
            <FixedRow
              label="El de la razón social del local"
              value={formatCuit(legalEntityTaxId)}
              half
            />
          ) : null}
        </div>
      }
      read={
        <dl className="flex flex-col">
          <ReadRow label="Comprobante" value={classLabel} />
          <ReadRow
            label="Número"
            value={`${fiscal && h.point_of_sale ? `${h.point_of_sale.padStart(4, "0")}-` : ""}${h.number.padStart(8, "0")}`}
          />
          <ReadRow label="Fecha" value={shortDate(h.issued_on)} />
          <ReadRow
            label="Vencimiento impreso"
            value={h.due_on ? shortDate(h.due_on) : "No: según la condición de pago"}
          />
          {fiscal ? (
            <ReadRow
              label="Autorización"
              value={`${AUTHORIZATION_KINDS.find((a) => a.value === h.authorization_kind)?.label ?? ""} ${h.authorization_code}`}
            />
          ) : null}
          <ReadRow label="CUIT del emisor" value={cuit(h.issuer_tax_id)} />
          <ReadRow label="CUIT del receptor" value={cuit(h.receiver_tax_id)} />
        </dl>
      }
    />
  );
}

// ---------------------------------------------------------------------------
// El pie: importes, la cuenta y las percepciones
// ---------------------------------------------------------------------------
export function FooterSection() {
  const { prefix, draft, setDraft, changed, editable } = useSheet();
  const amounts = headerAmounts(draft.header);
  const diff = amounts ? totalsDifference(amounts) : null;
  const net = linesNet(draft.lines.filter((l) => l.line_class !== "free_of_charge"));
  const taxCount = draft.taxes.length;
  return (
    <div className="flex flex-col gap-2">
      <Split
        edit={
          <div className="grid grid-cols-2 gap-x-3 gap-y-2">
            {AMOUNT_FIELDS.map(({ field, label }) => (
              <HeaderInput key={field} field={field} label={label} inputMode="decimal" />
            ))}
          </div>
        }
        read={
          <dl className="flex flex-col">
            {AMOUNT_FIELDS.map(({ field, label }) => (
              <ReadRow
                key={field}
                label={label}
                value={formatMoney(
                  readNumber(draft.header[field], field === "rounding_amount") ?? 0,
                )}
              />
            ))}
          </dl>
        }
      />
      {/* La cuenta, con palabra: las partes suman el total (±0,01), como invoices_totals_check. */}
      <p className="flex flex-wrap items-center gap-2 text-sm text-ink">
        <span aria-live="polite">
          {diff === null ? (
            <Badge status="bad">Hay un importe que no se entiende</Badge>
          ) : Math.abs(diff) <= 0.01 ? (
            <Badge status="ok">La cuenta cierra</Badge>
          ) : (
            <Badge status="bad">No cierra</Badge>
          )}
        </span>
        {diff !== null && Math.abs(diff) > 0.01 ? (
          <span className="text-ink tabular-nums">Diferencia {formatMoney(Math.abs(diff))}</span>
        ) : null}
        <span className="text-ink-muted tabular-nums">Suma de las líneas {formatMoney(net)}</span>
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm text-ink">
          {taxCount === 0
            ? "Sin percepciones"
            : taxCount === 1
              ? "1 percepción"
              : `${taxCount} percepciones`}
        </span>
        <TaxesPanel prefix={prefix} editable={editable} changed={changed} setDraft={setDraft} />
      </div>
    </div>
  );
}

function TaxesPanel({
  prefix,
  editable,
  changed,
  setDraft,
}: {
  prefix: string;
  editable: boolean;
  changed: InvoiceChanges;
  setDraft: Ctx["setDraft"];
}) {
  const { draft } = useSheet();
  const [open, setOpen] = useState(false);
  const taxes = draft.taxes;
  if (!editable && taxes.length === 0) return null;
  return (
    <>
      <Button
        type="button"
        variant="link"
        className="min-h-touch px-0 desk:min-h-8"
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => setOpen(true)}
      >
        {editable ? "Editar percepciones" : "Ver percepciones"}
      </Button>
      <SidePanel
        open={open}
        onOpenChange={setOpen}
        title="Percepciones y otros tributos"
        description="No entran al costo (decisión 4 de Soy): suman al total y al pago. Se guardan con el resto de la ficha."
      >
        <ul className="flex flex-col gap-3" aria-label="Percepciones">
          {taxes.map((t, i) => {
            const id = `${prefix}-tax-${t.key}`;
            const isChanged = changed.taxes.includes(t.key);
            return (
              <li
                key={t.key}
                className={cn(
                  "flex flex-col gap-2 rounded-sm border border-line p-3",
                  isChanged && changedRing,
                )}
              >
                {editable ? (
                  <>
                    <Segmented
                      name={`${id}-kind`}
                      legend={`Qué es (percepción ${i + 1})`}
                      options={(Object.keys(TAX_KIND_LABELS) as InvoiceTaxKind[]).map((k) => ({
                        value: k,
                        label: TAX_KIND_LABELS[k],
                      }))}
                      value={t.tax_kind}
                      onChange={(v) =>
                        setDraft((d) => ({
                          ...d,
                          taxes: d.taxes.map((x, j) =>
                            j === i ? { ...x, tax_kind: v as InvoiceTaxKind } : x,
                          ),
                        }))
                      }
                      className="-m-1"
                    />
                    <div className="grid grid-cols-3 gap-2">
                      {(
                        [
                          ["jurisdiction", "Jurisdicción", "text"],
                          ["rate_pct", "Alícuota %", "decimal"],
                          ["tax_amount", "Importe", "decimal"],
                        ] as const
                      ).map(([field, label, mode]) => (
                        <div key={field} className="flex min-w-0 flex-col gap-1">
                          <label htmlFor={`${id}-${field}`} className={labelClass}>
                            {label}
                          </label>
                          <Input
                            id={`${id}-${field}`}
                            inputMode={mode}
                            value={t[field]}
                            maxLength={60}
                            className={mode === "decimal" ? "text-right tabular-nums" : undefined}
                            onChange={(e) =>
                              setDraft((d) => ({
                                ...d,
                                taxes: d.taxes.map((x, j) =>
                                  j === i ? { ...x, [field]: e.target.value } : x,
                                ),
                              }))
                            }
                          />
                        </div>
                      ))}
                    </div>
                    <Button
                      type="button"
                      variant="outline"
                      className="self-start"
                      onClick={() =>
                        setDraft((d) => ({ ...d, taxes: d.taxes.filter((_, j) => j !== i) }))
                      }
                    >
                      <Trash2 aria-hidden="true" />
                      Quitar<span className="sr-only"> la percepción {i + 1}</span>
                    </Button>
                  </>
                ) : (
                  <span className="text-base text-ink tabular-nums">
                    {TAX_KIND_LABELS[t.tax_kind]}
                    {t.jurisdiction ? ` · ${t.jurisdiction}` : ""}
                    {t.rate_pct ? ` · ${t.rate_pct} %` : ""} ·{" "}
                    {formatMoney(readNumber(t.tax_amount))}
                  </span>
                )}
              </li>
            );
          })}
        </ul>
        {editable ? (
          <Button
            type="button"
            variant="outline"
            className="self-start"
            onClick={() =>
              setDraft((d) => ({
                ...d,
                taxes: [
                  ...d.taxes,
                  {
                    key: `nueva-${Date.now()}`,
                    tax_kind: "iibb",
                    jurisdiction: "",
                    rate_pct: "",
                    tax_amount: "",
                  },
                ],
              }))
            }
          >
            <Plus aria-hidden="true" />
            Agregar percepción
          </Button>
        ) : null}
        <p className="text-sm text-ink-muted">
          Recordá que el pie lleva el total de percepciones en «Percepciones».
        </p>
      </SidePanel>
    </>
  );
}

// ---------------------------------------------------------------------------
// Las líneas, como planilla, con su control
// ---------------------------------------------------------------------------
function CheckMarks({ checks }: { checks: CheckRow[] }) {
  if (checks.length === 0) return null;
  const failed = checks.filter((c) => !c.passed);
  const text = checks.map((c) => `${CHECK_LABELS[c.kind]}: ${c.explanation}`).join(" ");
  return (
    <span className="inline-flex items-center gap-1">
      {failed.length === 0 ? (
        <Badge status="ok">
          <Check aria-hidden="true" className="size-4" />
          Pasa
        </Badge>
      ) : (
        <Badge status="bad">
          <X aria-hidden="true" className="size-4" />
          No pasa
        </Badge>
      )}
      <InfoTip label="el control de la línea">{text}</InfoTip>
    </span>
  );
}

export function LinesSection() {
  const { prefix, draft, setDraft, changed, editable, lineChecks } = useSheet();
  const fiscalVat =
    isFiscal(draft.header.invoice_class as InvoiceClass) &&
    draft.header.invoice_class !== "invoice_c";
  function update(i: number, patch: Partial<LineDraft>) {
    setDraft((d) => ({ ...d, lines: d.lines.map((l, j) => (j === i ? { ...l, ...patch } : l)) }));
  }
  const cellInput = cn(small, "w-full min-w-16 text-right tabular-nums");
  const columns = fiscalVat ? 4 : 3;
  // En A se compara el neto; en las demás, el precio final (como el control).
  const priceLabel = isClassA(draft.header.invoice_class as InvoiceClass)
    ? "Precio sin IVA"
    : "Precio";
  return (
    <div className="flex min-w-0 flex-col gap-2">
      {/* Cada línea en dos filas: arriba qué es (el papel y el producto reconocido); abajo los números y su control. Así
          el nombre se lee entero en una tarjeta angosta. */}
      <table className="w-full border-collapse text-base">
        <caption className="sr-only">Líneas de la factura</caption>
        <thead>
          <tr className="border-b border-line text-sm text-ink-muted">
            <th scope="col" className="py-1 pr-2 text-right font-medium">
              Cantidad
            </th>
            <th scope="col" className="py-1 pr-2 text-right font-medium">
              {priceLabel}
            </th>
            {fiscalVat ? (
              <th scope="col" className="py-1 pr-2 text-right font-medium">
                IVA
              </th>
            ) : null}
            <th scope="col" className="py-1 text-right font-medium">
              Importe
            </th>
          </tr>
        </thead>
        {draft.lines.map((l, i) => {
          const id = `${prefix}-l-${l.key}`;
          const isChanged = changed.lines.includes(l.key);
          const amount = lineAmount(readNumber(l.billed_quantity), readNumber(l.unit_price));
          const unit = l.by_weight ? "kg" : "u";
          const checks = l.id && !isChanged ? (lineChecks[l.id] ?? []) : [];
          const name = l.raw_name || "la línea nueva";
          return (
            <tbody
              key={l.key}
              className={cn(
                "border-b border-line",
                isChanged && "outline-1 outline-ink outline-dashed",
              )}
            >
              <tr>
                <th
                  scope="rowgroup"
                  colSpan={columns - 1}
                  className="pt-2 text-left align-top font-normal"
                >
                  <span className="block text-ink">{l.raw_name || "Línea nueva"}</span>
                  <span className="block text-sm text-ink-muted">
                    {l.line_class !== "product"
                      ? LINE_CLASS_LABELS[l.line_class]
                      : !l.product
                        ? "Sin reconocer: lo mapea el chef"
                        : l.product !== l.raw_name
                          ? l.product
                          : "Reconocido"}
                    {l.bonus1_pct > 0 || l.bonus2_pct > 0
                      ? ` · bonif. ${[l.bonus1_pct, l.bonus2_pct].filter((b) => b > 0).join(" + ")} %`
                      : ""}
                  </span>
                </th>
                <td className="pt-2 text-right align-top">
                  <div className="flex items-center justify-end gap-1">
                    {isChanged ? (
                      <span className="text-sm text-ink">Sin guardar</span>
                    ) : (
                      <CheckMarks checks={checks} />
                    )}
                    {editable ? (
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon"
                        className="hidden size-8 shrink-0 desk:inline-flex"
                        aria-label={`Quitar la línea ${i + 1}: ${l.raw_name || "nueva"}`}
                        onClick={() =>
                          setDraft((d) => ({ ...d, lines: d.lines.filter((_, j) => j !== i) }))
                        }
                      >
                        <Trash2 aria-hidden="true" />
                      </Button>
                    ) : null}
                  </div>
                </td>
              </tr>
              {editable && l.id === null ? (
                <tr className="hidden desk:table-row">
                  <td colSpan={columns} className="pt-1">
                    <div className="flex flex-col gap-2">
                      <div className="flex flex-col gap-1">
                        <label htmlFor={`${id}-nombre`} className={labelClass}>
                          Qué es (línea {i + 1})
                        </label>
                        <Input
                          id={`${id}-nombre`}
                          value={l.raw_name}
                          maxLength={200}
                          className={small}
                          onChange={(e) => update(i, { raw_name: e.target.value })}
                        />
                      </div>
                      <Segmented
                        name={`${id}-clase`}
                        legend={`Clase (línea ${i + 1})`}
                        options={NEW_LINE_CLASSES.map((c) => ({
                          value: c,
                          label: LINE_CLASS_LABELS[c],
                        }))}
                        value={l.line_class}
                        onChange={(v) => update(i, { line_class: v as InvoiceLineClass })}
                        compact
                        className="-m-1"
                      />
                    </div>
                  </td>
                </tr>
              ) : null}
              <tr className="align-top">
                <td className="py-1 pr-2 text-right tabular-nums">
                  <Split
                    edit={
                      <div className="flex items-center gap-1">
                        <label htmlFor={`${id}-cant`} className="sr-only">
                          Cantidad de {name} ({unit === "kg" ? "kilos" : "unidades"})
                        </label>
                        <Input
                          id={`${id}-cant`}
                          inputMode="decimal"
                          value={l.billed_quantity}
                          className={cellInput}
                          onChange={(e) => update(i, { billed_quantity: e.target.value })}
                        />
                        <span aria-hidden="true" className="text-sm text-ink-muted">
                          {unit}
                        </span>
                      </div>
                    }
                    read={
                      <span>
                        {l.billed_quantity} {unit}
                      </span>
                    }
                  />
                </td>
                <td className="py-1 pr-2 text-right tabular-nums">
                  <Split
                    edit={
                      <>
                        <label htmlFor={`${id}-precio`} className="sr-only">
                          {priceLabel} de {name}
                          {l.by_weight ? " por kilo" : ""}
                        </label>
                        <Input
                          id={`${id}-precio`}
                          inputMode="decimal"
                          value={l.unit_price}
                          className={cellInput}
                          onChange={(e) => update(i, { unit_price: e.target.value })}
                        />
                      </>
                    }
                    read={<span>{formatMoney(readNumber(l.unit_price))}</span>}
                  />
                </td>
                {fiscalVat ? (
                  <td className="py-1 pr-2 text-right tabular-nums">
                    <Split
                      edit={
                        <>
                          <label htmlFor={`${id}-iva`} className="sr-only">
                            IVA de {name}
                          </label>
                          <Select
                            id={`${id}-iva`}
                            value={l.vat_rate}
                            className={cn(small, "w-24")}
                            onChange={(e) => update(i, { vat_rate: e.target.value })}
                          >
                            <option value="">—</option>
                            {INVOICE_VAT_RATES.map((r) => (
                              <option key={r} value={r}>
                                {r.replace(".", ",")} %
                              </option>
                            ))}
                          </Select>
                        </>
                      }
                      read={<span>{l.vat_rate ? `${l.vat_rate.replace(".", ",")} %` : "—"}</span>}
                    />
                  </td>
                ) : null}
                <td className="py-1 text-right text-ink tabular-nums">
                  <span className="inline-flex min-h-8 items-center">{formatMoney(amount)}</span>
                </td>
              </tr>
            </tbody>
          );
        })}
      </table>
      {draft.lines.length === 0 ? (
        <p className="text-base text-ink-muted">Sin líneas. Sumá lo que dice el papel.</p>
      ) : null}
      {editable ? (
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="hidden self-start desk:inline-flex"
          onClick={() =>
            setDraft((d) => ({
              ...d,
              lines: [
                ...d.lines,
                {
                  key: `nueva-${Date.now()}`,
                  id: null,
                  line_class: "freight",
                  purchase_product_id: null,
                  purchase_order_line_id: null,
                  product: null,
                  raw_name: "",
                  supplier_sku: "",
                  units: "",
                  billed_quantity: "1",
                  list_price: null,
                  bonus1_pct: 0,
                  bonus2_pct: 0,
                  bonus_per_unit_amount: 0,
                  unit_price: "",
                  vat_rate:
                    d.header.invoice_class === "invoice_a" ||
                    d.header.invoice_class === "invoice_remito_a"
                      ? "21"
                      : "",
                  is_exempt: false,
                  internal_tax_amount: "",
                  by_weight: false,
                },
              ],
            }))
          }
        >
          <Plus aria-hidden="true" />
          Agregar línea
        </Button>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// La barra de abajo: contador, motivo, Descartar y Guardar
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
