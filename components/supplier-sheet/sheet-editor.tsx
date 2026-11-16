"use client";

import { createContext, useContext, useId, useMemo, useRef, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Check, Plus, Undo2, X } from "lucide-react";

import { requestLowerApprovalAction, saveSupplierSheetAction } from "@/app/proveedores/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { FormTextarea } from "@/components/ui/form";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/dialog";
import { Input, Select, Textarea } from "@/components/ui/field";
import { InfoTip } from "@/components/ui/info-tip";
import { Notice } from "@/components/ui/notice";
import { Segmented } from "@/components/ui/segmented";
import { ToggleField } from "@/components/ui/toggle-field";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { reasonField, supplierSheetSchema } from "@/lib/forms/schemas";
import { changesLabel } from "@/lib/recipe-sheet";
import {
  BILLING_LABELS,
  BILLING_ORDER,
  CHANNEL_LABELS,
  CHANNEL_TARGET_LABELS,
  FREQUENCY_LABELS,
  PAYMENT_METHOD_LABELS,
  PAYMENT_TERMS_LABELS,
  VAT_LABELS,
  WEEK_DAYS,
  accountLabel,
  countSupplierChanges,
  daysLongLabel,
  emptyAccount,
  formatCuit,
  paymentLabel,
  supplierChanges,
  supplierPayload,
  toggleDay,
  type BillingMode,
  type Channel,
  type ListFrequency,
  type PaymentMethod,
  type PaymentTerms,
  type SheetAccount,
  type SupplierChanges,
  type SupplierField,
  type SupplierSheetDraft,
} from "@/lib/suppliers";
import { cn } from "@/lib/utils";

// Ficha de proveedor (Fase 3, ADR-0050), con el patrón de las fichas sin scroll (ADR-0046): la página (del servidor)
// pone cada sección en su tarjeta; lo que se edita comparte un borrador y se guarda junto, con un motivo, en una
// transacción (purchasing.save_supplier_sheet). En el celular la ficha es de consulta (ADR-0036): se ve como texto.

export type SupplierSheetOptions = {
  rubros: { id: string; name: string }[];
  restaurants: { id: string; name: string }[];
};

type Ctx = {
  supplierId: string;
  prefix: string;
  editable: boolean;
  options: SupplierSheetOptions;
  saved: SupplierSheetDraft;
  draft: SupplierSheetDraft;
  setDraft: (update: (d: SupplierSheetDraft) => SupplierSheetDraft) => void;
  changed: SupplierChanges;
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
  if (!ctx) throw new Error("Falta SupplierSheetProvider.");
  return ctx;
}

export function SupplierSheetProvider({
  supplierId,
  stamp,
  editable,
  initial,
  options,
  notice = null,
  children,
}: {
  supplierId: string;
  // El último cambio de la ficha: la base rechaza el guardado si alguien la cambió en el medio.
  stamp: string | null;
  editable: boolean;
  initial: SupplierSheetDraft;
  options: SupplierSheetOptions;
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
  const changed = useMemo(() => supplierChanges(saved, draft), [saved, draft]);
  const count = countSupplierChanges(changed);
  useUnsavedWarning(editable && count > 0);
  // Después de guardar llega lo guardado con su sello nuevo: si no se empezó a editar otra cosa, se toma.
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
    const parsed = supplierSheetSchema.safeParse({
      supplierId,
      expectedStamp: stamp ?? "",
      reason,
      changes: supplierPayload(saved, draft),
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
      const result = await saveSupplierSheetAction(parsed.data);
      setState(result.status === "ok" ? {} : result);
      if (result.status === "ok") {
        // Las cuentas nuevas reciben su id de la base al volver la ficha: hasta entonces queda lo de la pantalla.
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
    supplierId,
    prefix,
    editable,
    options,
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
// Las tarjetas son angostas: controles de 36 px en la computadora (44 en el celular, como siempre; ADR-0046).
const small = "desk:min-h-control-sm";

function ReadRow({ label, value, wide = false }: { label: string; value: string; wide?: boolean }) {
  return (
    <div className={cn("flex min-w-0 flex-col", wide && "desk:col-span-2")}>
      <dt className={labelClass}>{label}</dt>
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

function TextField({
  field,
  label,
  required = false,
  maxLength,
  type = "text",
  inputMode,
  placeholder,
}: {
  field: SupplierField;
  label: string;
  required?: boolean;
  maxLength: number;
  type?: string;
  inputMode?: React.HTMLAttributes<HTMLInputElement>["inputMode"];
  placeholder?: string;
}) {
  const { prefix, draft, setDraft, changed } = useSheet();
  const id = `${prefix}-${field}`;
  return (
    <div className="flex min-w-0 flex-col gap-1">
      <label htmlFor={id} className={labelClass}>
        {label}
        {required ? <span aria-hidden="true"> *</span> : null}
      </label>
      <Input
        id={id}
        type={type}
        inputMode={inputMode}
        value={draft.supplier[field]}
        maxLength={maxLength}
        placeholder={placeholder}
        aria-required={required ? "true" : undefined}
        onChange={(e) =>
          setDraft((d) => ({ ...d, supplier: { ...d.supplier, [field]: e.target.value } }))
        }
        className={cn(small, changed.supplier.includes(field) && changedRing)}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// a. Identificación y contacto
// ---------------------------------------------------------------------------
export function IdentitySection() {
  const { saved, draft, setDraft, changed } = useSheet();
  const s = saved.supplier;
  const read = (
    <dl className="flex flex-col gap-2 desk:grid desk:grid-cols-2 desk:gap-x-3">
      <ReadRow label="Razón social" value={s.name} wide />
      <ReadRow label="Nombre de fantasía" value={s.trade_name} />
      <ReadRow label="CUIT" value={formatCuit(s.tax_id)} />
      <ReadRow
        label="Condición frente al IVA"
        value={s.vat_condition ? VAT_LABELS[s.vat_condition as keyof typeof VAT_LABELS] : ""}
      />
      <ReadRow label="Domicilio" value={[s.address, s.city].filter(Boolean).join(", ")} wide />
      <ReadRow label="Teléfono" value={s.phone} />
      <ReadRow label="WhatsApp" value={s.whatsapp} />
      <ReadRow label="Correo" value={s.email} wide />
      <ReadRow label="Contacto de ventas" value={s.sales_contact} />
      <ReadRow label="Contacto de pagos" value={s.admin_contact} />
    </dl>
  );
  const edit = (
    <div className="flex min-h-0 flex-1 flex-col gap-1.5">
      <TextField field="name" label="Razón social" required maxLength={120} />
      <div className="grid grid-cols-2 gap-3">
        <TextField field="trade_name" label="Nombre de fantasía" maxLength={120} />
        <TextField
          field="tax_id"
          label="CUIT"
          maxLength={15}
          inputMode="numeric"
          placeholder="30-12345678-9"
        />
      </div>
      <Segmented
        name="vat"
        compact
        inline
        legend="IVA"
        options={Object.entries(VAT_LABELS).map(([value, label]) => ({
          value,
          label: value === "registered" ? "RI" : label,
        }))}
        value={draft.supplier.vat_condition}
        changed={changed.supplier.includes("vat_condition")}
        onChange={(v) => setDraft((d) => ({ ...d, supplier: { ...d.supplier, vat_condition: v } }))}
      />
      <div className="grid grid-cols-[3fr_2fr] gap-3">
        <TextField field="address" label="Domicilio" maxLength={200} />
        <TextField field="city" label="Localidad" maxLength={120} />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <TextField field="phone" label="Teléfono" maxLength={30} type="tel" />
        <TextField field="whatsapp" label="WhatsApp" maxLength={30} type="tel" />
      </div>
      <TextField field="email" label="Correo" maxLength={320} type="email" />
      <div className="grid grid-cols-2 gap-3">
        <TextField field="sales_contact" label="Contacto de ventas" maxLength={120} />
        <TextField field="admin_contact" label="Contacto de pagos" maxLength={120} />
      </div>
    </div>
  );
  return <Split edit={edit} read={read} />;
}

// ---------------------------------------------------------------------------
// b. Operativa
// ---------------------------------------------------------------------------
function DayButtons({ which, legend }: { which: "orderDays" | "deliveryDays"; legend: string }) {
  const { draft, setDraft, changed } = useSheet();
  const days = draft.terms[which];
  return (
    <fieldset
      className={cn(
        "flex flex-col gap-1 rounded-sm border border-transparent p-1 desk:flex-row desk:items-center desk:py-0",
        changed.terms.includes(which) && changedRing,
      )}
    >
      <legend className={cn(labelClass, "mb-1 desk:float-left desk:mb-0 desk:w-28")}>
        {legend}
        {changed.terms.includes(which) ? (
          <span className="sr-only"> (cambio sin guardar)</span>
        ) : null}
      </legend>
      <div className="flex flex-wrap gap-1">
        {WEEK_DAYS.map((d) => {
          const on = days.includes(d.day);
          return (
            <button
              key={d.day}
              type="button"
              aria-pressed={on}
              title={d.name}
              onClick={() =>
                setDraft((x) => ({
                  ...x,
                  terms: { ...x.terms, [which]: toggleDay(x.terms[which], d.day) },
                }))
              }
              className={cn(
                "inline-flex size-touch items-center justify-center rounded-sm border text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:size-7 desk:text-xs",
                // Elegido: como las opciones segmentadas, y además en negrita y subrayado (no solo color).
                on
                  ? "border-primary bg-nav-active font-semibold text-nav-active-ink underline decoration-2 underline-offset-2"
                  : "border-line bg-surface text-ink-muted hover:bg-line/50",
              )}
            >
              {/* La abreviatura se ve; el lector de pantalla dice el día completo (nombre = «lunes»). */}
              <span aria-hidden="true">{d.letter}</span>
              <span className="sr-only">{d.name}</span>
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

function BillingButtons() {
  const { draft, setDraft, changed } = useSheet();
  const modes = draft.terms.billingModes;
  const toggle = (m: BillingMode) =>
    setDraft((d) => ({
      ...d,
      terms: {
        ...d.terms,
        billingModes: modes.includes(m)
          ? modes.filter((x) => x !== m)
          : BILLING_ORDER.filter((x) => x === m || modes.includes(x)),
      },
    }));
  return (
    <fieldset
      className={cn(
        "flex flex-col gap-1 rounded-sm border border-transparent p-1",
        changed.terms.includes("billingModes") && changedRing,
      )}
    >
      <legend className={cn(labelClass, "flex items-center gap-1")}>
        Cómo factura
        <InfoTip label="cómo factura">
          Puede ser más de una forma. Sirve para saber qué papel llega con la mercadería y qué
          factura esperar.
        </InfoTip>
      </legend>
      <div className="flex flex-wrap gap-1">
        {BILLING_ORDER.map((m) => {
          const on = modes.includes(m);
          return (
            <button
              key={m}
              type="button"
              aria-pressed={on}
              onClick={() => toggle(m)}
              className={cn(
                "inline-flex min-h-touch items-center gap-1 rounded-sm border px-2 text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:min-h-7",
                on
                  ? "border-primary bg-nav-active font-medium text-nav-active-ink"
                  : "border-line bg-surface text-ink hover:bg-line/50",
              )}
            >
              {on ? <Check aria-hidden="true" className="size-4" /> : null}
              {BILLING_LABELS[m]}
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

export function OperationSection() {
  const { prefix, saved, draft, setDraft, changed, options } = useSheet();
  const t = draft.terms;
  const setTerm = <K extends keyof SupplierSheetDraft["terms"]>(
    k: K,
    v: SupplierSheetDraft["terms"][K],
  ) => setDraft((d) => ({ ...d, terms: { ...d.terms, [k]: v } }));
  const restaurantName = (id: string) =>
    options.restaurants.find((r) => r.id === id)?.name ?? "Local";
  const st = saved.terms;
  const read = (
    <dl className="flex flex-col gap-2">
      <ReadRow label="Días de pedido" value={daysLongLabel(st.orderDays)} />
      <ReadRow label="Días de entrega" value={daysLongLabel(st.deliveryDays)} />
      <ReadRow
        label="Horario de recepción"
        value={
          st.receivingFrom && st.receivingTo ? `De ${st.receivingFrom} a ${st.receivingTo}` : ""
        }
      />
      <ReadRow
        label="Pedidos por"
        value={st.poChannel ? `${CHANNEL_LABELS[st.poChannel]}: ${st.poChannelTarget}` : ""}
      />
      <ReadRow
        label="Requiere aprobación antes de enviar la OC"
        value={st.requiresPoApproval ? "Sí" : "No"}
      />
      <ReadRow
        label="Cómo factura"
        value={st.billingModes.map((m) => BILLING_LABELS[m]).join(", ")}
      />
      <ReadRow
        label="Lista de precios"
        value={st.priceListFrequency ? FREQUENCY_LABELS[st.priceListFrequency] : ""}
      />
      <ReadRow
        label="Números de cliente"
        value={saved.customerNumbers
          // Solo los locales que la persona ve (de los otros no tiene el nombre).
          .filter((n) => options.restaurants.some((r) => r.id === n.restaurantId))
          .map((n) => `${restaurantName(n.restaurantId)}: ${n.number}`)
          .join(" · ")}
      />
    </dl>
  );
  // Una fila por dato, con la etiqueta a la izquierda (pantalla sin scroll, ADR-0046).
  const rowLabel = cn(labelClass, "w-28 shrink-0");
  const edit = (
    <div className="flex shrink-0 flex-col gap-1">
      <DayButtons which="orderDays" legend="Días de pedido" />
      <DayButtons which="deliveryDays" legend="Días de entrega" />
      <fieldset
        className={cn(
          "flex flex-wrap items-center gap-2 rounded-sm border border-transparent px-1",
          (changed.terms.includes("receivingFrom") || changed.terms.includes("receivingTo")) &&
            changedRing,
        )}
      >
        <legend className={cn(rowLabel, "float-left")}>Recepción</legend>
        <label htmlFor={`${prefix}-desde`} className="sr-only">
          Recibe desde
        </label>
        <Input
          id={`${prefix}-desde`}
          type="time"
          value={t.receivingFrom}
          onChange={(e) => setTerm("receivingFrom", e.target.value)}
          className="w-28 desk:min-h-8"
        />
        <span aria-hidden="true" className="text-sm text-ink-muted">
          a
        </span>
        <label htmlFor={`${prefix}-hasta`} className="sr-only">
          Recibe hasta
        </label>
        <Input
          id={`${prefix}-hasta`}
          type="time"
          value={t.receivingTo}
          onChange={(e) => setTerm("receivingTo", e.target.value)}
          className="w-28 desk:min-h-8"
        />
      </fieldset>
      <Segmented
        name="canal"
        compact
        inline
        legend="Pedidos por"
        labelClassName="w-28 shrink-0"
        className="desk:py-0"
        options={(Object.keys(CHANNEL_LABELS) as Channel[]).map((c) => ({
          value: c,
          label: CHANNEL_LABELS[c],
        }))}
        value={t.poChannel}
        changed={changed.terms.includes("poChannel")}
        onChange={(v) => setTerm("poChannel", v as Channel)}
      />
      {t.poChannel ? (
        <div className="flex items-center gap-2 px-1">
          <label htmlFor={`${prefix}-canal-dato`} className={rowLabel}>
            {CHANNEL_TARGET_LABELS[t.poChannel]}
          </label>
          <Input
            id={`${prefix}-canal-dato`}
            type={
              t.poChannel === "email" ? "email" : t.poChannel === "supplier_portal" ? "url" : "tel"
            }
            value={t.poChannelTarget}
            maxLength={320}
            onChange={(e) => setTerm("poChannelTarget", e.target.value)}
            className={cn(
              "min-w-0 flex-1 desk:min-h-8",
              changed.terms.includes("poChannelTarget") && changedRing,
            )}
          />
        </div>
      ) : null}
      <ApprovalToggle />
      <BillingButtons />
      <Segmented
        name="frecuencia"
        compact
        inline
        legend="Lista de precios"
        labelClassName="w-28 shrink-0"
        className="desk:py-0"
        options={(Object.keys(FREQUENCY_LABELS) as ListFrequency[]).map((f) => ({
          value: f,
          label: FREQUENCY_LABELS[f],
        }))}
        value={t.priceListFrequency}
        changed={changed.terms.includes("priceListFrequency")}
        onChange={(v) => setTerm("priceListFrequency", v as ListFrequency)}
      />
    </div>
  );
  return <Split edit={edit} read={read} />;
}

// Números de cliente: una fila por local con número; se editan en un panel que trabaja sobre el mismo borrador.
// Va al lado del título de Operativa (Tile aside): una línea, sin ocupar un renglón de la tarjeta.
export function CustomerNumbers() {
  const { prefix, draft, setDraft, changed, options, editable } = useSheet();
  const [open, setOpen] = useState(false);
  const opener = useRef<HTMLButtonElement>(null);
  function toggle(next: boolean) {
    setOpen(next);
    if (!next) requestAnimationFrame(() => opener.current?.focus());
  }
  const numberOf = (id: string) =>
    draft.customerNumbers.find((n) => n.restaurantId === id)?.number ?? "";
  const filled = draft.customerNumbers.filter((n) => n.number.trim() !== "");
  const name = (id: string) => options.restaurants.find((r) => r.id === id)?.name ?? "Local";
  function setNumber(restaurantId: string, number: string) {
    setDraft((d) => {
      const others = d.customerNumbers.filter((n) => n.restaurantId !== restaurantId);
      return {
        ...d,
        customerNumbers: number === "" ? others : [...others, { restaurantId, number }],
      };
    });
  }
  // Quien no edita, y el celular, los ven en la lectura de Operativa.
  if (!editable) return null;
  return (
    <div
      className={cn(
        "hidden items-center gap-1 rounded-sm border border-transparent px-1 desk:flex",
        changed.customerNumbers && changedRing,
      )}
    >
      <span className="text-sm text-ink-muted">
        N.º de cliente:{" "}
        {filled.length === 0
          ? "sin cargar"
          : filled.length === 1
            ? `${name(filled[0]!.restaurantId)} ${filled[0]!.number}`
            : `${filled.length} locales`}
        {changed.customerNumbers ? <span className="sr-only"> (cambio sin guardar)</span> : null}
      </span>
      <InfoTip label="números de cliente">
        Cada proveedor nos tiene con su número, distinto en cada local. Va en el mensaje de la orden
        de compra.
      </InfoTip>
      <Button
        type="button"
        variant="link"
        size="sm"
        className="desk:min-h-8"
        ref={opener}
        onClick={() => setOpen(true)}
      >
        Editar<span className="sr-only"> los números de cliente</span>
      </Button>
      <Modal
        open={open}
        onOpenChange={toggle}
        title="Números de cliente"
        description="Con qué número nos tiene este proveedor en cada local. Vacío: sin número. Se guarda con «Guardar cambios»."
      >
        <div className="flex flex-col gap-3">
          {options.restaurants.map((r) => (
            <div key={r.id} className="flex flex-col gap-1">
              <label htmlFor={`${prefix}-cliente-${r.id}`} className={labelClass}>
                {r.name}
              </label>
              <Input
                id={`${prefix}-cliente-${r.id}`}
                value={numberOf(r.id)}
                maxLength={30}
                onChange={(e) => setNumber(r.id, e.target.value)}
              />
            </div>
          ))}
          <Button type="button" className="self-end" onClick={() => toggle(false)}>
            Listo
          </Button>
        </div>
      </Modal>
    </div>
  );
}

// ---------------------------------------------------------------------------
// c. Pago (solo quien lo ve), permisos y rubros
// ---------------------------------------------------------------------------
export function PaymentSection() {
  const { prefix, saved, draft, setDraft, changed } = useSheet();
  if (!draft.payment || !saved.payment) return null;
  const p = draft.payment;
  const setPay = (patch: Partial<NonNullable<SupplierSheetDraft["payment"]>>) =>
    setDraft((d) => ({ ...d, payment: d.payment ? { ...d.payment, ...patch } : d.payment }));
  const read = (
    <dl className="flex flex-col gap-2">
      <ReadRow
        label="Condición de pago"
        value={paymentLabel(saved.payment.paymentTerms || null, Number(saved.payment.paymentDays))}
      />
      <ReadRow
        label="Pedido mínimo"
        value={
          saved.payment.minimumOrderAmount
            ? `$ ${Number(saved.payment.minimumOrderAmount).toLocaleString("es-AR")}`
            : ""
        }
      />
      <ReadRow
        label="Cuentas"
        value={(saved.accounts ?? [])
          .filter((a) => a.isActive)
          .map(accountLabel)
          .join(" · ")}
      />
    </dl>
  );
  const edit = (
    <div className="flex flex-col gap-1.5">
      <Segmented
        name="pago"
        compact
        // La tarjeta ya se llama «Pago»: la leyenda queda para el lector de pantalla (columna angosta, ADR-0046).
        hideLegend
        legend="Condición de pago"
        options={(Object.keys(PAYMENT_TERMS_LABELS) as PaymentTerms[]).map((v) => ({
          value: v,
          label: PAYMENT_TERMS_LABELS[v],
        }))}
        value={p.paymentTerms}
        changed={changed.payment && p.paymentTerms !== saved.payment.paymentTerms}
        onChange={(v) =>
          setPay({
            paymentTerms: v as PaymentTerms,
            paymentDays: v === "account" ? (p.paymentDays === "0" ? "30" : p.paymentDays) : "0",
          })
        }
      />
      {/* Una fila por dato, con la etiqueta al costado: el monto entra entero en la columna angosta. */}
      {p.paymentTerms === "account" ? (
        <div className="flex items-center gap-2 px-1">
          <label htmlFor={`${prefix}-dias-pago`} className={cn(labelClass, "w-24 shrink-0")}>
            Días de pago
          </label>
          <Input
            id={`${prefix}-dias-pago`}
            inputMode="numeric"
            value={p.paymentDays}
            maxLength={3}
            aria-describedby={`${prefix}-dias-pago-ayuda`}
            onChange={(e) => setPay({ paymentDays: e.target.value })}
            className={cn(
              "w-16 tabular-nums desk:min-h-8",
              p.paymentDays !== saved.payment.paymentDays && changedRing,
            )}
          />
          <span id={`${prefix}-dias-pago-ayuda`} className="sr-only">
            desde la fecha de la factura
          </span>
        </div>
      ) : null}
      <div className="flex items-center gap-2 px-1">
        <label htmlFor={`${prefix}-minimo`} className={cn(labelClass, "w-24 shrink-0")}>
          Mínimo ($)<span className="sr-only"> del pedido</span>
        </label>
        <Input
          id={`${prefix}-minimo`}
          inputMode="decimal"
          value={p.minimumOrderAmount}
          maxLength={15}
          placeholder="Sin mínimo"
          onChange={(e) => setPay({ minimumOrderAmount: e.target.value })}
          className={cn(
            "w-28 min-w-0 flex-1 tabular-nums desk:min-h-8",
            p.minimumOrderAmount !== saved.payment.minimumOrderAmount && changedRing,
          )}
        />
      </div>
      <Accounts />
    </div>
  );
  return <Split edit={edit} read={read} />;
}

function Accounts() {
  const { prefix, draft, setDraft, changed } = useSheet();
  const [editing, setEditing] = useState<string | null>(null);
  const [showAll, setShowAll] = useState(false);
  const opener = useRef<HTMLButtonElement>(null);
  function close() {
    setShowAll(false);
    setEditing(null);
    requestAnimationFrame(() => opener.current?.focus());
  }
  const accounts = draft.accounts ?? [];
  const current = accounts.find((a) => a.key === editing) ?? null;
  const active = accounts.filter((a) => !a.remove && a.isActive);
  const setAccount = (key: string, patch: Partial<SheetAccount>) =>
    setDraft((d) => ({
      ...d,
      accounts: (d.accounts ?? []).map((a) => (a.key === key ? { ...a, ...patch } : a)),
    }));
  function add() {
    const key = `nueva-${Date.now()}`;
    setDraft((d) => ({ ...d, accounts: [...(d.accounts ?? []), emptyAccount(key)] }));
    setEditing(key);
  }
  function removeNew(key: string) {
    setDraft((d) => ({ ...d, accounts: (d.accounts ?? []).filter((a) => a.key !== key) }));
    setEditing(null);
    setShowAll(true);
  }
  return (
    <div
      className={cn(
        "flex flex-col gap-1 rounded-sm border border-transparent p-1",
        changed.accounts && changedRing,
      )}
    >
      {/* Una línea con el resumen; la lista, editar y agregar van en el panel (pantalla sin scroll, ADR-0046). */}
      <div className="flex items-center gap-2">
        <span className={labelClass}>Cuentas</span>
        <span className="min-w-0 flex-1 truncate text-sm text-ink-muted">
          {active.length === 0
            ? "Sin cuentas cargadas"
            : active.length === 1
              ? `1 cuenta: ${active[0]!.method ? PAYMENT_METHOD_LABELS[active[0]!.method] : "sin medio"}`
              : `${active.length} cuentas`}
          {changed.accounts ? <span className="sr-only"> (cambio sin guardar)</span> : null}
        </span>
        <Button
          ref={opener}
          type="button"
          variant="link"
          size="sm"
          className="shrink-0 desk:min-h-8"
          onClick={() => setShowAll(true)}
        >
          {accounts.length === 0 ? "Agregar" : "Editar"}
          <span className="sr-only"> las cuentas para pagarle</span>
        </Button>
      </div>
      <Modal
        open={showAll || current !== null}
        onOpenChange={(open) => (open ? null : close())}
        title={
          current ? (current.id ? "Cuenta del proveedor" : "Nueva cuenta") : "Cuentas para pagarle"
        }
        description="Se guarda con «Guardar cambios», junto con el resto de la ficha."
      >
        {current ? null : (
          <>
            <Button
              type="button"
              variant="outline"
              className="self-start"
              onClick={() => {
                setShowAll(false);
                add();
              }}
            >
              <Plus aria-hidden="true" />
              Agregar cuenta
            </Button>
            {accounts.length === 0 ? (
              <p className="text-base text-ink-muted">Sin cuentas cargadas.</p>
            ) : null}
            <ul className="flex flex-col divide-y divide-line" aria-label="Todas las cuentas">
              {accounts.map((a) => (
                <li key={a.key} className="flex items-center justify-between gap-2 py-2">
                  <span
                    className={cn(
                      "min-w-0 text-base",
                      a.remove ? "text-ink-muted line-through" : "text-ink",
                    )}
                  >
                    {accountLabel(a)}
                  </span>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => {
                      setShowAll(false);
                      setEditing(a.key);
                    }}
                  >
                    Editar<span className="sr-only"> {accountLabel(a)}</span>
                  </Button>
                </li>
              ))}
            </ul>
          </>
        )}
        {current ? (
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1">
              <label htmlFor={`${prefix}-medio`} className={labelClass}>
                Medio de pago
              </label>
              <Select
                id={`${prefix}-medio`}
                value={current.method}
                onChange={(e) =>
                  setAccount(current.key, { method: e.target.value as PaymentMethod })
                }
              >
                {(Object.keys(PAYMENT_METHOD_LABELS) as PaymentMethod[]).map((m) => (
                  <option key={m} value={m}>
                    {PAYMENT_METHOD_LABELS[m]}
                  </option>
                ))}
              </Select>
            </div>
            {current.method === "electronic_code" ? (
              <AccountInput
                account={current}
                field="electronicCode"
                label="Código de pago electrónico"
                maxLength={40}
                onChange={setAccount}
              />
            ) : null}
            {current.method === "transfer" || current.method === "echeq" ? (
              <>
                <AccountInput
                  account={current}
                  field="cbu"
                  label="CBU o CVU (22 números)"
                  maxLength={22}
                  numeric
                  onChange={setAccount}
                />
                <AccountInput
                  account={current}
                  field="alias"
                  label="Alias"
                  maxLength={20}
                  onChange={setAccount}
                />
              </>
            ) : null}
            {current.method !== "cash" ? (
              <>
                <AccountInput
                  account={current}
                  field="bank"
                  label="Banco o billetera"
                  maxLength={80}
                  onChange={setAccount}
                />
                <AccountInput
                  account={current}
                  field="holderName"
                  label="A nombre de"
                  maxLength={120}
                  onChange={setAccount}
                />
                <AccountInput
                  account={current}
                  field="holderTaxId"
                  label="CUIT del titular"
                  maxLength={15}
                  numeric
                  onChange={setAccount}
                />
              </>
            ) : null}
            {current.id ? (
              <ToggleField
                name="cuenta-activa"
                id={`${prefix}-cuenta-activa`}
                label="¿Se sigue usando?"
                defaultValue={current.isActive}
                value={current.isActive}
                onChange={(v) => setAccount(current.key, { isActive: v })}
              />
            ) : null}
            <div className="flex flex-wrap justify-between gap-2">
              {current.id ? (
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setAccount(current.key, { remove: !current.remove })}
                >
                  {current.remove ? <Undo2 aria-hidden="true" /> : <X aria-hidden="true" />}
                  {current.remove ? "No quitarla" : "Quitar la cuenta"}
                </Button>
              ) : (
                <Button type="button" variant="outline" onClick={() => removeNew(current.key)}>
                  <X aria-hidden="true" />
                  Descartar la cuenta
                </Button>
              )}
              <Button
                type="button"
                onClick={() => {
                  setEditing(null);
                  setShowAll(true);
                }}
              >
                Listo
              </Button>
            </div>
          </div>
        ) : null}
      </Modal>
    </div>
  );
}

function AccountInput({
  account,
  field,
  label,
  maxLength,
  onChange,
  numeric = false,
}: {
  account: SheetAccount;
  field: "cbu" | "alias" | "bank" | "holderName" | "holderTaxId" | "electronicCode";
  label: string;
  maxLength: number;
  onChange: (key: string, patch: Partial<SheetAccount>) => void;
  numeric?: boolean;
}) {
  const { prefix } = useSheet();
  const id = `${prefix}-cuenta-${field}`;
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className={labelClass}>
        {label}
      </label>
      <Input
        id={id}
        value={account[field]}
        maxLength={maxLength}
        inputMode={numeric ? "numeric" : undefined}
        className={numeric ? "tabular-nums" : undefined}
        onChange={(e) => onChange(account.key, { [field]: e.target.value })}
      />
    </div>
  );
}

// «Requiere aprobación de administración antes de enviar la OC»: sí o no de un clic (ADR-0039).
export function ApprovalToggle() {
  const { supplierId, prefix, saved, draft, setDraft, editable } = useSheet();
  const label = "Requiere aprobación de la OC";
  const tip = (
    <InfoTip label="aprobación de la orden de compra">
      Si está en Sí, cada orden de compra a este proveedor la aprueba Compras antes de enviarse.
      Nunca la aprueba quien la pidió.
    </InfoTip>
  );
  if (!editable)
    return (
      <p className="flex items-center gap-1 text-base text-ink">
        {label}: <span className="font-medium">{saved.terms.requiresPoApproval ? "Sí" : "No"}</span>
        {tip}
      </p>
    );
  // Marcada, no se desmarca directo: lo aprueba Dirección (ADR-0053). Si no, Compras podría saltear la aprobación de
  // su propia OC.
  if (saved.terms.requiresPoApproval)
    return (
      <div className="flex flex-wrap items-center gap-2">
        <p className="flex items-center gap-1 text-base text-ink">
          {label}: <span className="font-medium">Sí</span>
          {tip}
        </p>
        <ActionModal
          label="Pedir que deje de requerir"
          icon="none"
          title="Que este proveedor deje de requerir aprobación"
          description="Lo aprueba Dirección, nunca quien lo pide: si no, Compras podría saltear la aprobación de su propia orden."
        >
          <ActionForm action={requestLowerApprovalAction} schema="reason" submitLabel="Pedir">
            <input type="hidden" name="supplierId" value={supplierId} />
            <FormTextarea
              id={`${prefix}-bajar-aprobacion-motivo`}
              name="reason"
              label="Motivo"
              hint="Lo ve Dirección al decidir."
              required
              maxLength={500}
            />
          </ActionForm>
        </ActionModal>
      </div>
    );
  return (
    <Split
      edit={
        <div className="flex items-center gap-1">
          <ToggleField
            name="requiere-aprobacion"
            id={`${prefix}-aprobacion`}
            label={label}
            defaultValue={saved.terms.requiresPoApproval}
            value={draft.terms.requiresPoApproval}
            onChange={(v) =>
              setDraft((d) => ({ ...d, terms: { ...d.terms, requiresPoApproval: v } }))
            }
          />
          {tip}
        </div>
      }
      read={
        <p className="text-base text-ink">
          {label}:{" "}
          <span className="font-medium">{saved.terms.requiresPoApproval ? "Sí" : "No"}</span>
        </p>
      }
    />
  );
}

// Rubros que provee: chips con ✕ y «+ Agregar».
export function CategoriesSection() {
  const { prefix, saved, draft, setDraft, changed, options } = useSheet();
  const name = (id: string) => options.rubros.find((r) => r.id === id)?.name ?? "Rubro";
  const remaining = options.rubros.filter((r) => !draft.categories.includes(r.id));
  const read = (
    <p className="text-base text-ink-muted">
      {saved.categories.length > 0 ? saved.categories.map(name).join(", ") : "Sin rubros cargados."}
    </p>
  );
  const edit = (
    <div
      className={cn(
        "flex flex-wrap items-center gap-2 rounded-sm border border-transparent p-1",
        changed.categories && changedRing,
      )}
    >
      <ul className="contents" aria-label="Rubros que provee">
        {draft.categories.map((id) => (
          <li
            key={id}
            className="inline-flex items-center gap-1 rounded-sm bg-none pl-2 text-sm text-none-ink"
          >
            {name(id)}
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label={`Quitar «${name(id)}»`}
              className="desk:min-h-8 desk:w-8"
              onClick={() =>
                setDraft((d) => ({ ...d, categories: d.categories.filter((c) => c !== id) }))
              }
            >
              <X aria-hidden="true" />
            </Button>
          </li>
        ))}
      </ul>
      {remaining.length > 0 ? (
        <>
          <label htmlFor={`${prefix}-rubro-nuevo`} className="sr-only">
            Agregar un rubro
          </label>
          <Select
            id={`${prefix}-rubro-nuevo`}
            value=""
            className={cn(small, "w-32")}
            onChange={(e) => {
              const v = e.target.value;
              if (v) setDraft((d) => ({ ...d, categories: [...d.categories, v] }));
            }}
          >
            <option value="">+ Rubro</option>
            {remaining.map((r) => (
              <option key={r.id} value={r.id}>
                {r.name}
              </option>
            ))}
          </Select>
        </>
      ) : null}
      {changed.categories ? (
        <span className="sr-only" role="status">
          Rubros: cambio sin guardar
        </span>
      ) : null}
    </div>
  );
  return <Split edit={edit} read={read} />;
}

export function NotesField() {
  const { prefix, saved, draft, setDraft, changed } = useSheet();
  return (
    <Split
      edit={
        // En una fila, con la etiqueta al costado (pantalla sin scroll, ADR-0046): ocupa lo que sobra de la tarjeta.
        <div className="flex min-h-0 flex-1 items-start gap-2 px-1 pt-1">
          <label htmlFor={`${prefix}-notas`} className={cn(labelClass, "w-28 shrink-0 pt-1.5")}>
            Observaciones
          </label>
          <Textarea
            id={`${prefix}-notas`}
            value={draft.supplier.notes}
            maxLength={1000}
            rows={1}
            onChange={(e) =>
              setDraft((d) => ({ ...d, supplier: { ...d.supplier, notes: e.target.value } }))
            }
            className={cn(
              "min-h-8 flex-1 resize-none self-stretch py-1",
              changed.supplier.includes("notes") && changedRing,
            )}
          />
        </div>
      }
      read={
        <dl>
          <ReadRow label="Observaciones" value={saved.supplier.notes} />
        </dl>
      }
    />
  );
}

// ---------------------------------------------------------------------------
// Barra fija: contador, motivo, Descartar y Guardar cambios
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

// El estado de la ficha para el encabezado (lo usa la página).
export function SupplierStateBadge({ active }: { active: boolean }) {
  return active ? <Badge status="ok">Activo</Badge> : <Badge status="none">Inactivo</Badge>;
}
