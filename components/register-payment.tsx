"use client";

import { useId, useRef, useState, useTransition } from "react";
import { Plus, X } from "lucide-react";

import { loadPayableAction, registerPaymentOrderAction } from "@/app/compras/pagos/actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { SidePanel } from "@/components/ui/dialog";
import { DateInput } from "@/components/ui/date-input";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { FileUpload } from "@/components/ui/file-upload";
import { Segmented } from "@/components/ui/segmented";
import type { ActionState } from "@/lib/auth/results";
import { todayInArgentina } from "@/lib/forms/schemas";
import { numberText, readNumber, shortDate } from "@/lib/invoices";
import { formatMoney } from "@/lib/money";
import {
  ORDER_METHODS,
  ORDER_METHOD_LABELS,
  accountKindFor,
  emptyLine,
  hasCheck,
  linesForBase,
  needsSupplierAccount,
  paymentOrderSchema,
  type OrderLine,
  type OrderMethod,
} from "@/lib/payment-orders";
import type { Payable } from "@/lib/payments-data";
import { DUE_LABELS, checkAllocations, distribute } from "@/lib/payments";
import { shrinkPhoto } from "@/lib/photos";

// «Registrar pago» (ADR-0070): una orden de pago en un panel de dos columnas, sin scroll (criterio 4 de Soy). A la
// izquierda, el proveedor, de qué caja o cuenta de la razón social sale la plata, los medios (de 1 a 5: efectivo,
// transferencia a la cuenta del proveedor, cheque propio o de terceros, e-cheq, tarjeta) y la fecha. A la derecha, qué
// facturas cancela (se reparte solo, de la que vence antes), lo que queda a cuenta, las retenciones (en 0 por ahora),
// el comprobante, las observaciones y el motivo. Al registrar, abre la orden de pago (imprimible). La base vuelve a
// controlar todo.
export function RegisterPayment({
  restaurant,
  suppliers,
  initialSupplierId,
}: {
  restaurant: { id: string; name: string };
  suppliers: { id: string; name: string; balance: number }[];
  initialSupplierId?: string;
}) {
  const prefix = useId();
  const opener = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [supplierId, setSupplierId] = useState(initialSupplierId ?? "");
  const [payable, setPayable] = useState<Payable | null>(null);
  const [loading, startLoading] = useTransition();
  const [lines, setLines] = useState<OrderLine[]>([emptyLine()]);
  const [paidOn, setPaidOn] = useState(todayInArgentina());
  const [notes, setNotes] = useState("");
  const [reason, setReason] = useState("");
  const [allocations, setAllocations] = useState<Record<string, string>>({});
  const [file, setFile] = useState<File | null>(null);
  const [state, setState] = useState<ActionState>({});
  const [pending, startSaving] = useTransition();

  function loadSupplier(id: string) {
    setSupplierId(id);
    setPayable(null);
    setAllocations({});
    setLines([emptyLine()]);
    setState({});
    if (!id) return;
    startLoading(async () => {
      const result = await loadPayableAction(restaurant.id, id);
      setPayable(result);
      if (!result)
        setState({ status: "bad", message: "No podés registrar pagos de ese proveedor acá." });
      else setLines([preset(emptyLine(), result)]);
    });
  }

  // Un medio nuevo arranca con la primera caja o cuenta del tipo que le toca y la primera cuenta del proveedor.
  function preset(line: OrderLine, p: Payable | null = payable): OrderLine {
    const kind = accountKindFor(line.method);
    const own = (p?.company_accounts ?? []).find((a) => a.kind === kind);
    const theirs = (p?.accounts ?? []).find((a) => a.method === "transfer");
    return {
      ...line,
      companyAccountId: kind ? (own?.id ?? "") : "",
      supplierAccountId: needsSupplierAccount(line.method) ? (theirs?.id ?? "") : "",
    };
  }

  const total = Math.round(lines.reduce((s, l) => s + (readNumber(l.amount) ?? 0), 0) * 100) / 100;
  // Al cambiar los importes, lo que se paga se reparte solo entre las facturas (de la que vence antes).
  function setLine(i: number, patch: Partial<OrderLine>) {
    setLines((all) => {
      const next = all.map((l, j) =>
        j === i ? (patch.method ? preset({ ...l, ...patch }) : { ...l, ...patch }) : l,
      );
      if ("amount" in patch && payable) {
        const sum = next.reduce((s, l) => s + (readNumber(l.amount) ?? 0), 0);
        const { allocations: split } = distribute(sum, payable.invoices);
        setAllocations(
          Object.fromEntries(
            payable.invoices.map((inv) => [inv.invoice_id, numberText(split[inv.invoice_id] ?? 0)]),
          ),
        );
      }
      return next;
    });
  }

  const balances = Object.fromEntries(
    (payable?.invoices ?? []).map((i) => [i.invoice_id, i.balance]),
  );
  const check = checkAllocations(total > 0 ? total : null, allocations, balances);

  function submit() {
    const base = linesForBase(lines);
    const fields = paymentOrderSchema.safeParse({ paidOn, notes, reason });
    const problem = !supplierId
      ? "Elegí el proveedor."
      : !base.ok
        ? base.message
        : !check.ok
          ? check.message
          : !fields.success
            ? (fields.error.issues[0]?.message ?? "Revisá el pago.")
            : null;
    if (problem || !base.ok || !check.ok) {
      setState({ status: "bad", message: problem ?? "Revisá el pago." });
      return;
    }
    startSaving(async () => {
      try {
        const form = new FormData();
        form.set("restaurantId", restaurant.id);
        form.set("supplierId", supplierId);
        if (payable?.payer) form.set("legalEntityId", payable.payer.id);
        form.set("paidOn", paidOn);
        form.set("notes", notes);
        form.set("reason", reason);
        form.set("lines", JSON.stringify(base.lines));
        form.set("allocations", JSON.stringify(check.lines));
        if (file) {
          form.set(
            "file",
            file.type === "application/pdf"
              ? file
              : new File([await shrinkPhoto(file)], "comprobante.jpg", { type: "image/jpeg" }),
          );
        }
        // Si sale bien, la acción abre la orden de pago; si no, vuelve con el motivo.
        const result = await registerPaymentOrderAction(form);
        setState(result);
      } catch (e) {
        if (e instanceof Error && e.message.includes("NEXT_REDIRECT")) throw e;
        setState({
          status: "bad",
          message: "No pudimos leer el comprobante: probá con otra foto o un PDF.",
        });
      }
    });
  }

  const companyAccounts = payable?.company_accounts ?? [];
  const transferAccounts = (payable?.accounts ?? []).filter((a) => a.method === "transfer");

  return (
    <>
      <Button
        ref={opener}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => {
          setOpen(true);
          if (supplierId && !payable) loadSupplier(supplierId);
        }}
      >
        <Plus aria-hidden="true" />
        Registrar pago
      </Button>
      <SidePanel
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) requestAnimationFrame(() => opener.current?.focus());
        }}
        title="Registrar pago"
        description={`En ${restaurant.name}${payable?.payer ? ` · paga ${payable.payer.name}` : ""}. Lo que no se aplica a facturas queda a cuenta del proveedor.`}
        className="desk:w-[64rem]"
      >
        <div className="grid gap-6 desk:grid-cols-2">
          {/* Columna 1: a quién, de dónde y cómo. */}
          <div className="flex flex-col gap-4">
            <Field id={`${prefix}-proveedor`} label="Proveedor" required>
              <Select value={supplierId} onChange={(e) => loadSupplier(e.target.value)}>
                <option value="">Elegí el proveedor</option>
                {suppliers.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name} ({formatMoney(s.balance)})
                  </option>
                ))}
              </Select>
            </Field>
            {loading ? <p className="text-base text-ink-muted">Cargando sus facturas…</p> : null}
            {payable && !payable.payer ? (
              <p className="text-sm text-bad-ink">
                El local no tiene razón social: cargala en el Panel de control para poder pagar.
              </p>
            ) : null}
            {payable && payable.payer && companyAccounts.length === 0 ? (
              <p className="text-sm text-ink">
                {payable.payer.name} no tiene cajas ni cuentas cargadas: las carga quien administra
                el grupo, en la ficha de la razón social.
              </p>
            ) : null}

            {payable ? (
              <>
                <ul
                  aria-label="Medios de pago"
                  // Con varios cheques, los medios se desplazan adentro y el panel no crece (criterio 4).
                  className="relative flex flex-col gap-3 desk:max-h-[23rem] desk:overflow-y-auto"
                >
                  {lines.map((l, i) => (
                    <li key={i} className="flex flex-col gap-3 rounded-sm border border-line p-3">
                      <div className="flex items-end gap-2">
                        <Field
                          id={`${prefix}-medio-${i}`}
                          label={lines.length > 1 ? `Medio ${i + 1}` : "Medio de pago"}
                          className="flex-1"
                        >
                          {/* Seis medios: un desplegable (más de 5 opciones, criterio 9). */}
                          <Select
                            value={l.method}
                            onChange={(e) => setLine(i, { method: e.target.value as OrderMethod })}
                          >
                            {ORDER_METHODS.map((m) => (
                              <option key={m} value={m}>
                                {ORDER_METHOD_LABELS[m]}
                              </option>
                            ))}
                          </Select>
                        </Field>
                        <Field id={`${prefix}-importe-${i}`} label="Importe" className="w-36">
                          <Input
                            inputMode="decimal"
                            className="text-right tabular-nums"
                            value={l.amount}
                            onChange={(e) => setLine(i, { amount: e.target.value })}
                          />
                        </Field>
                        {lines.length > 1 ? (
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon"
                            aria-label={`Quitar el medio ${i + 1}`}
                            onClick={() => setLines((all) => all.filter((_, j) => j !== i))}
                          >
                            <X aria-hidden="true" />
                          </Button>
                        ) : null}
                      </div>
                      <AccountPicker
                        id={`${prefix}-desde-${i}`}
                        line={l}
                        accounts={companyAccounts}
                        onChange={(v) => setLine(i, { companyAccountId: v })}
                      />
                      {needsSupplierAccount(l.method) ? (
                        <SupplierAccount
                          id={`${prefix}-cta-${i}`}
                          value={l.supplierAccountId}
                          accounts={transferAccounts}
                          onChange={(v) => setLine(i, { supplierAccountId: v })}
                        />
                      ) : null}
                      {hasCheck(l.method) ? (
                        <div className="grid gap-2 sm:grid-cols-2">
                          <Field id={`${prefix}-cheque-${i}`} label="N.º de cheque">
                            <Input
                              maxLength={30}
                              value={l.checkNumber}
                              onChange={(e) => setLine(i, { checkNumber: e.target.value })}
                            />
                          </Field>
                          <Field id={`${prefix}-banco-${i}`} label="Banco">
                            <Input
                              maxLength={80}
                              value={l.checkBank}
                              onChange={(e) => setLine(i, { checkBank: e.target.value })}
                            />
                          </Field>
                          <Field id={`${prefix}-cobro-${i}`} label="Fecha de cobro">
                            <DateInput
                              value={l.checkDueOn}
                              min={todayInArgentina()}
                              onChange={(v) => setLine(i, { checkDueOn: v })}
                            />
                          </Field>
                        </div>
                      ) : null}
                      {l.method === "third_party_check" ? (
                        <div className="grid gap-2 sm:grid-cols-2">
                          <Field id={`${prefix}-librador-${i}`} label="Quién lo libró">
                            <Input
                              maxLength={120}
                              value={l.drawerName}
                              onChange={(e) => setLine(i, { drawerName: e.target.value })}
                            />
                          </Field>
                          <Field id={`${prefix}-librador-cuit-${i}`} label="Su CUIT (opcional)">
                            <Input
                              inputMode="numeric"
                              maxLength={13}
                              value={l.drawerTaxId}
                              onChange={(e) => setLine(i, { drawerTaxId: e.target.value })}
                            />
                          </Field>
                        </div>
                      ) : null}
                      {l.method === "transfer" ? (
                        <Field id={`${prefix}-ref-${i}`} label="N.º de transferencia (opcional)">
                          <Input
                            maxLength={80}
                            value={l.reference}
                            onChange={(e) => setLine(i, { reference: e.target.value })}
                          />
                        </Field>
                      ) : null}
                    </li>
                  ))}
                </ul>
                {lines.length < 5 ? (
                  <Button
                    type="button"
                    variant="outline"
                    className="self-start"
                    onClick={() => setLines((all) => [...all, preset(emptyLine("own_check"))])}
                  >
                    <Plus aria-hidden="true" />
                    Otro medio
                  </Button>
                ) : null}
                <Field id={`${prefix}-fecha`} label="Fecha del pago" required>
                  <DateInput max={todayInArgentina()} value={paidOn} onChange={setPaidOn} />
                </Field>
              </>
            ) : null}
          </div>

          {/* Columna 2: qué cancela y lo demás. */}
          <div className="flex flex-col gap-4">
            {payable ? (
              <>
                <fieldset className="flex flex-col gap-2">
                  <legend className="mb-1 text-sm font-medium text-ink">Se aplica a</legend>
                  {payable.invoices.length === 0 ? (
                    <p className="text-sm text-ink-muted">
                      Sin facturas con saldo: el pago queda a cuenta.
                    </p>
                  ) : (
                    <ul
                      aria-label="Facturas con saldo"
                      className="relative flex max-h-40 flex-col divide-y divide-line overflow-y-auto rounded-sm border border-line"
                    >
                      {payable.invoices.map((inv) => (
                        <li
                          key={inv.invoice_id}
                          className="flex items-center justify-between gap-3 px-3 py-2"
                        >
                          <span className="min-w-0 text-sm">
                            <span className="block [overflow-wrap:break-word] text-ink">
                              {inv.label}
                            </span>
                            <span className="flex flex-wrap items-center gap-2 text-ink tabular-nums">
                              Vence el {shortDate(inv.due_on)} · saldo {formatMoney(inv.balance)}
                              <Badge status={DUE_LABELS[inv.due_state].status}>
                                {DUE_LABELS[inv.due_state].label}
                              </Badge>
                            </span>
                          </span>
                          <label className="sr-only" htmlFor={`${prefix}-a-${inv.invoice_id}`}>
                            Cuánto se cancela de {inv.label}
                          </label>
                          <Input
                            id={`${prefix}-a-${inv.invoice_id}`}
                            inputMode="decimal"
                            className="w-28 text-right tabular-nums"
                            value={allocations[inv.invoice_id] ?? ""}
                            onChange={(e) =>
                              setAllocations((a) => ({ ...a, [inv.invoice_id]: e.target.value }))
                            }
                          />
                        </li>
                      ))}
                    </ul>
                  )}
                  <p className="text-xs text-ink-muted">
                    Se reparte solo, de la que vence antes. Ya vienen descontadas las notas de
                    crédito.
                  </p>
                </fieldset>
                <dl className="flex flex-col gap-1 text-sm tabular-nums">
                  <div className="flex justify-between gap-2">
                    <dt className="text-ink-muted">Retenciones (Ganancias, IVA, IIBB)</dt>
                    <dd className="text-ink">— · sin cálculo por ahora</dd>
                  </div>
                  <div className="flex justify-between gap-2">
                    <dt className="text-ink-muted">Total de la orden</dt>
                    <dd className="text-base font-semibold text-ink">{formatMoney(total)}</dd>
                  </div>
                  <div className="flex justify-between gap-2" aria-live="polite">
                    <dt className="text-ink-muted">Queda a cuenta</dt>
                    <dd className="text-ink">{check.ok ? formatMoney(check.left) : "—"}</dd>
                  </div>
                </dl>
                {payable.credits.length > 0 ? (
                  <p className="text-sm text-ink">
                    Ya tiene {formatMoney(payable.credits.reduce((s, c) => s + c.unapplied, 0))} a
                    cuenta de pagos anteriores.
                  </p>
                ) : null}
                <Field
                  id={`${prefix}-comprobante`}
                  label="Comprobante (foto o PDF)"
                  hint="Opcional."
                >
                  <FileUpload accept="image/*,application/pdf" onFile={setFile} />
                </Field>
                <div className="grid gap-3 sm:grid-cols-2">
                  <Field id={`${prefix}-notas`} label="Observaciones">
                    <Textarea
                      rows={2}
                      maxLength={500}
                      value={notes}
                      onChange={(e) => setNotes(e.target.value)}
                    />
                  </Field>
                  <Field
                    id={`${prefix}-motivo`}
                    label="Motivo"
                    hint="Queda en el historial."
                    required
                  >
                    <Textarea
                      rows={2}
                      maxLength={500}
                      value={reason}
                      onChange={(e) => setReason(e.target.value)}
                    />
                  </Field>
                </div>
              </>
            ) : null}
            <FormNotice state={state} />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancelar
              </Button>
              <Button type="button" disabled={pending || !payable} onClick={submit}>
                {pending ? "Registrando…" : "Registrar pago"}
              </Button>
            </div>
          </div>
        </div>
      </SidePanel>
    </>
  );
}

// De qué caja o cuenta sale: botones si son hasta 5, desplegable si son más (criterio 9). El cheque de terceros no sale
// de una cuenta nuestra.
function AccountPicker({
  id,
  line,
  accounts,
  onChange,
}: {
  id: string;
  line: OrderLine;
  accounts: { id: string; kind: "cash" | "bank" | "card"; name: string }[];
  onChange: (id: string) => void;
}) {
  const kind = accountKindFor(line.method);
  if (!kind)
    return (
      <p className="text-sm text-ink-muted">Cheque de terceros: no sale de una cuenta propia.</p>
    );
  const options = accounts.filter((a) => a.kind === kind);
  const label =
    kind === "cash"
      ? "De qué caja sale"
      : kind === "card"
        ? "Con qué tarjeta"
        : "De qué cuenta sale";
  if (options.length === 0)
    return (
      <p className="text-sm text-bad-ink">
        {kind === "cash"
          ? "No hay cajas cargadas."
          : kind === "card"
            ? "No hay tarjetas cargadas."
            : "No hay cuentas bancarias cargadas."}{" "}
        Las carga quien administra el grupo, en la ficha de la razón social.
      </p>
    );
  if (options.length <= 5)
    return (
      <Segmented
        name={id}
        legend={label}
        options={options.map((a) => ({ value: a.id, label: a.name }))}
        value={line.companyAccountId}
        onChange={onChange}
      />
    );
  return (
    <Field id={id} label={label}>
      <Select value={line.companyAccountId} onChange={(e) => onChange(e.target.value)}>
        {options.map((a) => (
          <option key={a.id} value={a.id}>
            {a.name}
          </option>
        ))}
      </Select>
    </Field>
  );
}

// La cuenta del proveedor a la que va la transferencia, completa: banco, titular, CUIT, CBU y alias (decisión 7).
function SupplierAccount({
  id,
  value,
  accounts,
  onChange,
}: {
  id: string;
  value: string;
  accounts: Payable["accounts"];
  onChange: (id: string) => void;
}) {
  if (accounts.length === 0)
    return (
      <p className="text-sm text-bad-ink">
        El proveedor no tiene cuenta para transferencias en su ficha: cargala ahí.
      </p>
    );
  const chosen = accounts.find((a) => a.id === value) ?? accounts[0];
  return (
    <div className="flex flex-col gap-1">
      {accounts.length > 1 ? (
        <Field id={id} label="A qué cuenta del proveedor">
          <Select value={value} onChange={(e) => onChange(e.target.value)}>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>
                {[a.bank, a.alias, a.cbu_end ? `CBU …${a.cbu_end}` : null]
                  .filter(Boolean)
                  .join(" · ")}
              </option>
            ))}
          </Select>
        </Field>
      ) : (
        <span className="text-sm font-medium text-ink">A la cuenta del proveedor</span>
      )}
      {chosen ? (
        <p className="text-sm text-ink">
          {[
            chosen.bank,
            chosen.holder_name ? `titular ${chosen.holder_name}` : null,
            chosen.holder_tax_id ? `CUIT ${chosen.holder_tax_id}` : null,
            chosen.cbu ? `CBU ${chosen.cbu}` : chosen.cbu_end ? `CBU …${chosen.cbu_end}` : null,
            chosen.alias ? `alias ${chosen.alias}` : null,
          ]
            .filter(Boolean)
            .join(" · ")}
        </p>
      ) : null}
    </div>
  );
}
