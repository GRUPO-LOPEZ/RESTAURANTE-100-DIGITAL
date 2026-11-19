"use client";

import { useId, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";

import { loadPayableAction, registerPaymentAction } from "@/app/compras/pagos/actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { SidePanel } from "@/components/ui/dialog";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { Segmented } from "@/components/ui/segmented";
import type { ActionState } from "@/lib/auth/results";
import { todayInArgentina } from "@/lib/forms/schemas";
import { numberText, readNumber, shortDate } from "@/lib/invoices";
import { formatMoney } from "@/lib/money";
import type { Payable } from "@/lib/payments-data";
import {
  DUE_LABELS,
  METHOD_LABELS,
  accountLabel,
  checkAllocations,
  distribute,
  paymentSchema,
  type PaymentMethod,
} from "@/lib/payments";
import { shrinkPhoto } from "@/lib/photos";

// «Registrar pago» (ADR-0060), en un panel lateral: el proveedor, sus facturas con saldo (el importe se reparte solo, de
// la que vence antes, y cada una se corrige a mano), el medio (las cuentas de su ficha), la fecha, la referencia, el
// comprobante y el motivo. Lo que no se aplica queda a cuenta. La base vuelve a controlar todo.
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
  const router = useRouter();
  const opener = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [supplierId, setSupplierId] = useState(initialSupplierId ?? "");
  const [payable, setPayable] = useState<Payable | null>(null);
  const [loading, startLoading] = useTransition();
  const [method, setMethod] = useState<PaymentMethod>("cash");
  const [accountId, setAccountId] = useState("");
  const [paidOn, setPaidOn] = useState(todayInArgentina());
  const [amount, setAmount] = useState("");
  const [reference, setReference] = useState("");
  const [reason, setReason] = useState("");
  const [allocations, setAllocations] = useState<Record<string, string>>({});
  const [file, setFile] = useState<File | null>(null);
  const [state, setState] = useState<ActionState>({});
  // El error de cada campo, junto al campo (además del aviso de abajo).
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [pending, startSaving] = useTransition();

  function loadSupplier(id: string) {
    setSupplierId(id);
    setPayable(null);
    setAllocations({});
    setAccountId("");
    setMethod("cash");
    setState({});
    setErrors({});
    if (!id) return;
    startLoading(async () => {
      const result = await loadPayableAction(restaurant.id, id);
      setPayable(result);
      if (!result)
        setState({ status: "bad", message: "No podés registrar pagos de ese proveedor acá." });
    });
  }

  // Al escribir el importe, se reparte solo entre las facturas (de la que vence antes).
  function changeAmount(text: string) {
    setAmount(text);
    const n = readNumber(text);
    if (payable && n !== null) {
      const { allocations: split } = distribute(n, payable.invoices);
      setAllocations(
        Object.fromEntries(
          payable.invoices.map((i) => [i.invoice_id, numberText(split[i.invoice_id] ?? 0)]),
        ),
      );
    }
  }

  const balances = Object.fromEntries(
    (payable?.invoices ?? []).map((i) => [i.invoice_id, i.balance]),
  );
  const check = checkAllocations(readNumber(amount), allocations, balances);
  // Los medios: efectivo y los de las cuentas activas de la ficha del proveedor.
  const methods: PaymentMethod[] = [
    "cash",
    ...[...new Set((payable?.accounts ?? []).map((a) => a.method))].filter((m) => m !== "cash"),
  ];
  const accounts = (payable?.accounts ?? []).filter((a) => a.method === method);

  function submit() {
    const fields = paymentSchema.safeParse({
      method,
      accountId,
      paidOn,
      amount,
      reference,
      reason,
    });
    const found: Record<string, string> = {};
    if (!supplierId) found.supplier = "Elegí el proveedor.";
    if (!fields.success) {
      for (const issue of fields.error.issues) {
        const key = String(issue.path[0] ?? "");
        if (key && !found[key]) found[key] = issue.message;
      }
    }
    if (fields.success && !check.ok) found.allocations = check.message;
    setErrors(found);
    const first = Object.values(found)[0];
    if (first || !check.ok)
      return setState({ status: "bad", message: "Revisá los campos marcados." });
    startSaving(async () => {
      try {
        const form = new FormData();
        form.set("restaurantId", restaurant.id);
        form.set("supplierId", supplierId);
        form.set("method", method);
        form.set("accountId", accountId);
        form.set("paidOn", paidOn);
        form.set("amount", amount);
        form.set("reference", reference);
        form.set("reason", reason);
        form.set("allocations", JSON.stringify(check.lines));
        if (file) {
          form.set(
            "file",
            file.type === "application/pdf"
              ? file
              : new File([await shrinkPhoto(file)], "comprobante.jpg", { type: "image/jpeg" }),
          );
        }
        const result = await registerPaymentAction(form);
        setState(result);
        if (result.status !== "bad") {
          router.refresh();
          loadSupplier(supplierId);
          setAmount("");
          setReference("");
          setReason("");
          setFile(null);
          setState(result);
        }
      } catch {
        setState({
          status: "bad",
          message: "No pudimos leer el comprobante: probá con otra foto o un PDF.",
        });
      }
    });
  }

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
        description={`En ${restaurant.name}. Un pago es de un local: lo que no se aplica a facturas queda a cuenta del proveedor.`}
      >
        <div className="flex flex-col gap-4">
          <Field id={`${prefix}-proveedor`} label="Proveedor" required error={errors.supplier}>
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

          {payable ? (
            <>
              <Field
                id={`${prefix}-importe`}
                label="Importe del pago"
                hint="Se reparte solo entre las facturas, de la que vence antes. Podés corregir cada una."
                required
                error={errors.amount}
              >
                <Input
                  inputMode="decimal"
                  value={amount}
                  onChange={(e) => changeAmount(e.target.value)}
                />
              </Field>

              <fieldset className="flex flex-col gap-2">
                <legend className="mb-1 text-sm font-medium text-ink">
                  Facturas con saldo
                  {payable.invoice_count > payable.invoices.length
                    ? ` (las ${payable.invoices.length} que vencen antes de ${payable.invoice_count})`
                    : ""}
                </legend>
                {payable.invoices.length === 0 ? (
                  <p className="text-base text-ink-muted">
                    Sin facturas con saldo: el pago queda a cuenta.
                  </p>
                ) : (
                  <ul
                    className="flex flex-col divide-y divide-line"
                    aria-label="Facturas con saldo"
                  >
                    {payable.invoices.map((i) => (
                      <li
                        key={i.invoice_id}
                        className="flex items-center justify-between gap-3 py-2"
                      >
                        <span className="min-w-0">
                          <span className="block text-base text-ink">{i.label}</span>
                          <span className="flex flex-wrap items-center gap-2 text-sm text-ink tabular-nums">
                            Vence el {shortDate(i.due_on)} · saldo {formatMoney(i.balance)}
                            <Badge status={DUE_LABELS[i.due_state].status}>
                              {DUE_LABELS[i.due_state].label}
                            </Badge>
                          </span>
                        </span>
                        <label className="sr-only" htmlFor={`${prefix}-a-${i.invoice_id}`}>
                          Cuánto se paga de {i.label}
                        </label>
                        <Input
                          id={`${prefix}-a-${i.invoice_id}`}
                          inputMode="decimal"
                          className="w-32 text-right tabular-nums"
                          value={allocations[i.invoice_id] ?? ""}
                          onChange={(e) =>
                            setAllocations((a) => ({ ...a, [i.invoice_id]: e.target.value }))
                          }
                        />
                      </li>
                    ))}
                  </ul>
                )}
                <p className="text-sm text-ink tabular-nums" aria-live="polite">
                  {check.ok
                    ? check.left > 0
                      ? `Quedan ${formatMoney(check.left)} a cuenta.`
                      : "Todo el pago se aplica a facturas."
                    : readNumber(amount) !== null || errors.allocations
                      ? check.message
                      : ""}
                </p>
              </fieldset>

              {payable.credits.length > 0 ? (
                <p className="text-sm text-ink">
                  Este proveedor ya tiene{" "}
                  {formatMoney(payable.credits.reduce((s, c) => s + c.unapplied, 0))} a cuenta de
                  pagos anteriores.
                </p>
              ) : null}

              <Segmented
                name={`${prefix}-medio`}
                legend="Medio de pago"
                options={methods.map((m) => ({ value: m, label: METHOD_LABELS[m] }))}
                value={method}
                onChange={(v) => {
                  setMethod(v as PaymentMethod);
                  setAccountId((payable.accounts.find((a) => a.method === v) ?? { id: "" }).id);
                }}
              />
              {method !== "cash" ? (
                <Field
                  id={`${prefix}-cuenta`}
                  label="Cuenta del proveedor"
                  required
                  error={errors.accountId}
                >
                  <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                    {accounts.map((a) => (
                      <option key={a.id} value={a.id}>
                        {accountLabel(a)}
                      </option>
                    ))}
                  </Select>
                </Field>
              ) : null}
              <div className="grid gap-4 sm:grid-cols-2">
                <Field id={`${prefix}-fecha`} label="Fecha del pago" required error={errors.paidOn}>
                  <Input
                    type="date"
                    max={todayInArgentina()}
                    value={paidOn}
                    onChange={(e) => setPaidOn(e.target.value)}
                  />
                </Field>
                <Field
                  id={`${prefix}-ref`}
                  label="Referencia"
                  hint="Número de transferencia o de cheque."
                >
                  <Input
                    maxLength={80}
                    value={reference}
                    onChange={(e) => setReference(e.target.value)}
                  />
                </Field>
              </div>
              <Field id={`${prefix}-comprobante`} label="Comprobante (foto o PDF)" hint="Opcional.">
                <Input
                  type="file"
                  accept="image/*,application/pdf"
                  onChange={(e) => setFile(e.target.files?.[0] ?? null)}
                />
              </Field>
              <Field
                id={`${prefix}-motivo`}
                label="Motivo"
                hint="Queda en el historial."
                required
                error={errors.reason}
              >
                <Textarea
                  maxLength={500}
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                />
              </Field>
            </>
          ) : null}

          <FormNotice state={state} />
          <Button
            type="button"
            disabled={pending || !payable}
            onClick={submit}
            className="self-start"
          >
            {pending ? "Registrando…" : "Registrar pago"}
          </Button>
        </div>
      </SidePanel>
    </>
  );
}
