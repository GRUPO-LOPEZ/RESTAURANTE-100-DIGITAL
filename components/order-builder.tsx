"use client";

import * as React from "react";
import { Minus, Plus, X } from "lucide-react";

import {
  expectedDeliveryAction,
  ingredientSearchAction,
  rankingAction,
  saveOrderAction,
  type OrderState,
} from "@/app/compras/ordenes/actions";
import { FormNotice } from "@/components/form-notice";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Field, Input, Textarea } from "@/components/ui/field";
import { estimatedKg, daysLong, daysShort, orderSchema, qtyText } from "@/lib/purchase-orders";
import type { OrderPlace, OrderSupplier, RankedProduct } from "@/lib/purchase-orders-data";
import { cn } from "@/lib/utils";

// Nueva orden de compra (ADR-0053), celular primero: 1) el proveedor, 2) las cantidades con − / + grandes (44 px) y un
// buscador, 3) la entrega esperada y las observaciones. «Mandar OC» (o «Enviar a aprobación», si el proveedor la
// requiere) va en la barra de abajo. Sin precios: el cocinero no los ve y hoy no se cargan.

type Extra = { id: string; code: string; name: string; unit_name: string };

export function OrderBuilder({
  place,
  suppliers,
  today,
}: {
  place: OrderPlace;
  suppliers: OrderSupplier[];
  today: string;
}) {
  const [supplier, setSupplier] = React.useState<OrderSupplier | null>(null);
  const [products, setProducts] = React.useState<RankedProduct[] | null>(null);
  const [loadFailed, setLoadFailed] = React.useState(false);
  const [qty, setQty] = React.useState<Record<string, number>>({});
  const [extras, setExtras] = React.useState<(Extra & { quantity: number })[]>([]);
  const [query, setQuery] = React.useState("");
  const [found, setFound] = React.useState<{ query: string; rows: Extra[]; failed: boolean }>({
    query: "",
    rows: [],
    failed: false,
  });
  // Para volver a pedir los artículos si falló la carga.
  const [attempt, setAttempt] = React.useState(0);
  const [expected, setExpected] = React.useState("");
  const [notes, setNotes] = React.useState("");
  const [clientError, setClientError] = React.useState<string | null>(null);
  const [state, action, pending] = React.useActionState<OrderState, FormData>(saveOrderAction, {});

  // Al elegir el proveedor: sus artículos según el ranking del local y la entrega esperada.
  React.useEffect(() => {
    if (!supplier) return;
    let alive = true;
    rankingAction(supplier.id, place.id)
      .then((rows) => alive && setProducts(rows))
      .catch(() => alive && setLoadFailed(true));
    expectedDeliveryAction(supplier.id, today)
      .then((d) => alive && d && setExpected(d))
      .catch(() => undefined);
    return () => {
      alive = false;
    };
  }, [supplier, place.id, today, attempt]);

  // Materias primas que el proveedor no tiene (para pedirlas «sin nombre de factura»).
  React.useEffect(() => {
    const q = query.trim();
    if (q.length < 2) return;
    const timer = setTimeout(() => {
      ingredientSearchAction(place.id, q)
        .then((rows) => setFound({ query: q, rows, failed: false }))
        .catch(() => setFound({ query: q, rows: [], failed: true }));
    }, 300);
    return () => clearTimeout(timer);
  }, [query, place.id]);

  const lines = [
    ...Object.entries(qty)
      .filter(([, q]) => q > 0)
      .map(([id, quantity]) => ({ purchase_product_id: id, quantity })),
    ...extras
      .filter((e) => e.quantity > 0)
      .map((e) => ({ ingredient_id: e.id, quantity: e.quantity })),
  ];
  const dirty = lines.length > 0 || notes.trim().length > 0;
  useUnsavedWarning(dirty && !pending);

  function pickSupplier(s: OrderSupplier | null) {
    if (
      dirty &&
      s?.id !== supplier?.id &&
      !window.confirm("Se borran las cantidades cargadas. ¿Cambiar de proveedor?")
    )
      return;
    setSupplier(s);
    setProducts(null);
    setLoadFailed(false);
    setQty({});
    setExtras([]);
    setQuery("");
    setExpected("");
  }

  const q = query.trim().toLowerCase();
  const shown = (products ?? []).filter(
    (p) =>
      q.length < 2 ||
      p.description.toLowerCase().includes(q) ||
      (p.supplier_sku ?? "").toLowerCase().includes(q),
  );
  const ingredientMatches =
    q.length >= 2 && found.query === query.trim()
      ? found.rows.filter((r) => !extras.some((e) => e.id === r.id))
      : [];

  function submit(event: React.FormEvent<HTMLFormElement>) {
    const parsed = orderSchema.safeParse({
      restaurant_id: place.id,
      supplier_id: supplier?.id,
      lines,
      notes: notes.trim() || undefined,
      expected_on: expected || undefined,
    });
    if (!parsed.success) {
      event.preventDefault();
      setClientError(parsed.error.issues[0]?.message ?? "Revisá la orden.");
      return;
    }
    setClientError(null);
  }

  if (!supplier) {
    return (
      <section aria-labelledby="oc-paso-1" className="flex flex-col gap-3">
        <h2 id="oc-paso-1" className="text-base font-semibold text-ink">
          1. ¿A qué proveedor le pedís?
        </h2>
        {suppliers.length === 0 ? (
          <p className="text-base text-ink">
            No hay proveedores activos para pedir. Los carga Compras en Proveedores.
          </p>
        ) : null}
        <ul className="grid gap-3 sm:grid-cols-2 desk:grid-cols-3">
          {suppliers.map((s) => (
            <li key={s.id}>
              <button
                type="button"
                onClick={() => pickSupplier(s)}
                className="flex min-h-touch w-full flex-col gap-1 rounded-md border border-line bg-surface p-4 text-left hover:border-primary focus-visible:outline-2 focus-visible:outline-primary"
              >
                <span className="text-base font-medium text-ink">{s.name}</span>
                <span className="text-sm text-ink-muted">
                  <span aria-hidden="true">
                    Pide: {daysShort(s.orderDays)} · Entrega: {daysShort(s.deliveryDays)}
                  </span>
                  <span className="sr-only">
                    Se le pide {daysLong(s.orderDays)} y entrega {daysLong(s.deliveryDays)}.
                  </span>
                </span>
                {s.requiresApproval ? (
                  <Badge status="review" className="self-start">
                    Requiere aprobación de Compras
                  </Badge>
                ) : null}
              </button>
            </li>
          ))}
        </ul>
      </section>
    );
  }

  return (
    <form action={action} onSubmit={submit} className="flex flex-col gap-4">
      <input
        type="hidden"
        name="order"
        value={JSON.stringify({
          restaurant_id: place.id,
          supplier_id: supplier.id,
          lines,
          notes: notes.trim() || undefined,
          expected_on: expected || undefined,
        })}
      />

      <div className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-line bg-surface p-3">
        <p className="text-base text-ink">
          <span className="font-medium">{supplier.name}</span>
          <span className="text-ink-muted"> · entrega {daysLong(supplier.deliveryDays)}</span>
        </p>
        <Button type="button" variant="outline" onClick={() => pickSupplier(null)}>
          Cambiar de proveedor
        </Button>
      </div>

      <section aria-labelledby="oc-paso-2" className="flex flex-col gap-3">
        <h2 id="oc-paso-2" className="text-base font-semibold text-ink">
          2. ¿Qué le pedís?
        </h2>
        <Field id="oc-buscar" label="Buscar" hint="En sus artículos y en las materias primas.">
          <Input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            autoComplete="off"
            placeholder="Nombre o código"
          />
        </Field>
        {loadFailed ? (
          <div role="alert" className="flex flex-wrap items-center gap-2 text-sm text-bad-ink">
            No pudimos cargar los artículos del proveedor.
            <Button
              type="button"
              variant="outline"
              onClick={() => {
                setLoadFailed(false);
                setAttempt((n) => n + 1);
              }}
            >
              Reintentar
            </Button>
          </div>
        ) : products === null ? (
          <p className="text-sm text-ink-muted">Cargando los artículos…</p>
        ) : products.length === 0 ? (
          <p className="text-sm text-ink">
            Este proveedor todavía no tiene artículos. Buscá la materia prima arriba para pedirla
            sin nombre de factura.
          </p>
        ) : (
          <ul
            aria-label="Artículos del proveedor"
            className="flex flex-col divide-y divide-line rounded-md border border-line bg-surface"
          >
            {shown.map((p) => {
              const value = qty[p.purchase_product_id] ?? 0;
              const kg = p.billed_by_weight
                ? estimatedKg(
                    value,
                    p.units_per_package,
                    p.estimated_weight_per_unit,
                    p.content_unit,
                  )
                : null;
              return (
                <li
                  key={p.purchase_product_id}
                  className="flex flex-wrap items-center justify-between gap-2 p-3"
                >
                  <div className="min-w-0 flex-1">
                    <p className="text-base text-ink">{p.description}</p>
                    <p className="text-sm text-ink-muted">
                      {p.package_name}
                      {p.supplier_sku ? ` · ${p.supplier_sku}` : ""}
                      {kg !== null ? ` · ≈ ${qtyText(kg)} kg` : ""}
                    </p>
                  </div>
                  <Stepper
                    label={p.description}
                    value={value}
                    onChange={(v) => setQty((all) => ({ ...all, [p.purchase_product_id]: v }))}
                  />
                </li>
              );
            })}
            {shown.length === 0 ? (
              <li className="p-3 text-sm text-ink-muted">
                Ningún artículo del proveedor con ese nombre.
              </li>
            ) : null}
          </ul>
        )}
        {q.length >= 2 && found.query === query.trim() && found.failed ? (
          <p role="alert" className="text-sm text-bad-ink">
            No pudimos buscar en las materias primas. Probá de nuevo.
          </p>
        ) : null}
        {ingredientMatches.length > 0 ? (
          <div className="flex flex-col gap-2">
            <p className="text-sm text-ink">
              Materias primas que el proveedor no tiene como artículo (van «sin nombre de factura»):
            </p>
            <ul className="flex flex-col gap-1">
              {ingredientMatches.map((r) => (
                <li key={r.id}>
                  <button
                    type="button"
                    onClick={() => setExtras((all) => [...all, { ...r, quantity: 1 }])}
                    className="flex min-h-touch w-full items-center gap-2 rounded-sm px-2 text-left text-sm text-primary underline-offset-4 hover:underline"
                  >
                    <Plus aria-hidden="true" className="size-4" />
                    Agregar {r.name}
                    <span className="text-ink-muted"> ({r.unit_name})</span>
                  </button>
                </li>
              ))}
            </ul>
          </div>
        ) : null}
        {extras.length > 0 ? (
          <ul
            aria-label="Sin nombre de factura"
            className="flex flex-col divide-y divide-line rounded-md border border-line bg-surface"
          >
            {extras.map((e) => (
              <li key={e.id} className="flex flex-wrap items-center justify-between gap-2 p-3">
                <div className="min-w-0 flex-1">
                  <p className="text-base text-ink">{e.name}</p>
                  <p className="text-sm text-ink-muted">
                    Sin nombre de factura · en {e.unit_name}. Al facturarse, el chef lo mapea.
                  </p>
                </div>
                <div className="flex items-center gap-1">
                  <Stepper
                    label={e.name}
                    value={e.quantity}
                    onChange={(v) =>
                      setExtras((all) =>
                        all.map((x) => (x.id === e.id ? { ...x, quantity: v } : x)),
                      )
                    }
                  />
                  <Button
                    type="button"
                    variant="outline"
                    aria-label={`Quitar ${e.name}`}
                    onClick={() => setExtras((all) => all.filter((x) => x.id !== e.id))}
                  >
                    <X aria-hidden="true" className="size-4" />
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        ) : null}
      </section>

      <section aria-labelledby="oc-paso-3" className="flex flex-col gap-3">
        <h2 id="oc-paso-3" className="text-base font-semibold text-ink">
          3. Entrega y observaciones
        </h2>
        <div className="grid gap-3 desk:grid-cols-[16rem_1fr]">
          <Field
            id="oc-entrega"
            label="Entrega esperada"
            hint="El próximo día de entrega del proveedor. Si lo cambiás, queda en el historial."
          >
            <Input
              type="date"
              value={expected}
              min={today}
              onChange={(e) => setExpected(e.target.value)}
            />
          </Field>
          <Field id="oc-notas" label="Observaciones para el proveedor">
            <Textarea
              value={notes}
              rows={2}
              maxLength={1000}
              onChange={(e) => setNotes(e.target.value)}
            />
          </Field>
        </div>
      </section>

      {/* Barra fija abajo: cuántos artículos y el botón principal. */}
      <div className="sticky bottom-[calc(var(--spacing-bottom-nav)+env(safe-area-inset-bottom))] z-40 -mx-4 flex flex-col gap-2 border-t border-line bg-surface px-4 py-3 desk:bottom-0 desk:-mx-gutter desk:flex-row desk:items-center desk:justify-between desk:px-gutter wide:-mx-gutter-wide wide:px-gutter-wide">
        <p className="text-sm text-ink tabular-nums" aria-live="polite">
          {lines.length === 1 ? "1 artículo" : `${lines.length} artículos`}
          {supplier.requiresApproval ? " · la aprueba Compras antes de mandarla" : ""}
        </p>
        {clientError ? (
          <p role="alert" className="text-sm text-bad-ink">
            {clientError}
          </p>
        ) : null}
        <FormNotice state={state} />
        <div className="flex flex-col gap-2 sm:flex-row">
          <Button type="submit" name="mode" value="draft" variant="outline" disabled={pending}>
            Guardar borrador
          </Button>
          <Button type="submit" name="mode" value="send" disabled={pending}>
            {pending
              ? "Enviando…"
              : supplier.requiresApproval
                ? "Enviar a aprobación"
                : "Mandar OC"}
          </Button>
        </div>
      </div>
    </form>
  );
}

// Cantidad con − / + grandes (44 px, para la cocina) y el campo para escribirla. Lo escrito se guarda tal cual (para
// poder tipear «1,5»); el número sale de ahí. Si no es un número, el campo lo marca.
function Stepper({
  label,
  value,
  onChange,
}: {
  label: string;
  value: number;
  onChange: (value: number) => void;
}) {
  const id = React.useId();
  const [text, setText] = React.useState(value === 0 ? "" : String(value).replace(".", ","));
  const [invalid, setInvalid] = React.useState(false);
  // Si el valor cambia por los botones, el texto lo sigue.
  const shown =
    Number(text.replace(",", ".")) === value || (text === "" && value === 0)
      ? text
      : String(value).replace(".", ",");
  function set(v: number) {
    setText(v === 0 ? "" : String(v).replace(".", ","));
    setInvalid(false);
    onChange(v);
  }
  return (
    <div role="group" aria-label={`Cantidad de ${label}`} className="flex items-center gap-1">
      <button
        type="button"
        aria-label={`Uno menos de ${label}`}
        disabled={value <= 0}
        onClick={() => set(Math.max(0, Math.round((value - 1) * 1000) / 1000))}
        className="flex size-touch items-center justify-center rounded-sm border border-line bg-surface text-ink hover:bg-line/50 disabled:opacity-40"
      >
        <Minus aria-hidden="true" className="size-5" />
      </button>
      <label htmlFor={id} className="sr-only">
        Cantidad de {label}
      </label>
      <input
        id={id}
        inputMode="decimal"
        value={shown}
        placeholder="0"
        aria-invalid={invalid ? true : undefined}
        aria-describedby={invalid ? `${id}-error` : undefined}
        onChange={(e) => {
          const t = e.target.value;
          setText(t);
          if (t.trim() === "") {
            setInvalid(false);
            onChange(0);
            return;
          }
          const n = Number(t.replace(",", "."));
          const ok = /^\d+([.,]\d*)?$/.test(t.trim()) && Number.isFinite(n) && n >= 0;
          setInvalid(!ok);
          if (ok) onChange(n);
        }}
        className={cn(
          "h-touch w-16 rounded-sm border border-line bg-surface text-center text-base text-ink tabular-nums",
          value > 0 && "border-primary font-medium",
          invalid && "border-bad-ink",
        )}
      />
      {invalid ? (
        <span id={`${id}-error`} className="sr-only">
          Va un número
        </span>
      ) : null}
      <button
        type="button"
        aria-label={`Uno más de ${label}`}
        onClick={() => set(Math.round((value + 1) * 1000) / 1000)}
        className="flex size-touch items-center justify-center rounded-sm border border-line bg-surface text-ink hover:bg-line/50"
      >
        <Plus aria-hidden="true" className="size-5" />
      </button>
    </div>
  );
}
