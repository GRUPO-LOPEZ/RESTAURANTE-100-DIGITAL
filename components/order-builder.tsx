"use client";

import * as React from "react";
import { Minus, Plus, Search } from "lucide-react";

import {
  expectedDeliveryAction,
  saveOrderAction,
  supplierCatalogAction,
  type OrderState,
} from "@/app/compras/ordenes/actions";
import { FormNotice } from "@/components/form-notice";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DateInput } from "@/components/ui/date-input";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { Tile } from "@/components/ui/tile";
import { formatMoney } from "@/lib/money";
import {
  CHANNEL_NAMES,
  daysShort,
  estimatedKg,
  minimumNotice,
  orderDayLabel,
  orderEstimate,
  orderSchema,
  qtyText,
} from "@/lib/purchase-orders";
import type {
  CatalogProduct,
  OrderPlace,
  OrderSupplier,
  OrderSupplierInfo,
} from "@/lib/purchase-orders-data";
import { cn } from "@/lib/utils";

// Nueva orden de compra en una pantalla (ADR-0069, decisiones 1 a 3 de Soy; boceto Main). En la computadora, tres
// columnas: los proveedores (con sus días de pedido), sus artículos (primero lo pedido en los últimos 60 días en el
// local, con el precio de la lista vigente) y la orden (total estimado, pedido mínimo, cuándo llega, canal, nota y los
// botones). En el celular, una columna con la barra fija abajo. La cantidad arranca en 0: quien pide piensa cada
// cantidad (decisión 2). Solo artículos de ese proveedor (decisión 3). Los precios y el mínimo los decide la base: a
// quien no ve listas le llegan vacíos y la pantalla no los muestra.

type Catalog = { products: CatalogProduct[]; info: OrderSupplierInfo };
type Load =
  { state: "idle" } | { state: "loading" } | { state: "error" } | ({ state: "ok" } & Catalog);

const weekday = new Intl.DateTimeFormat("es-AR", { weekday: "long", timeZone: "UTC" });
// «martes 24/11» (dd/mm, criterio 12; el separador de Intl en es-AR es un guion).
function dayText(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${weekday.format(new Date(`${iso}T12:00:00Z`))} ${d}/${m}`;
}

// «Pide Lu, Mi y Vi · Hoy pide»: sus días de pedido y si hoy pide (boceto).
function supplierDays(orderDays: number[], today: string): string {
  const label = orderDayLabel(orderDays, today);
  if (orderDays.length === 0 || orderDays.length === 7) return label;
  return `Pide ${daysShort(orderDays)} · ${label}`;
}

export function OrderBuilder({
  place,
  suppliers,
  today,
}: {
  place: OrderPlace;
  suppliers: OrderSupplier[];
  today: string;
}) {
  const [supplierId, setSupplierId] = React.useState<string | null>(null);
  const [load, setLoad] = React.useState<Load>({ state: "idle" });
  const [attempt, setAttempt] = React.useState(0);
  const [qty, setQty] = React.useState<Record<string, number>>({});
  const [query, setQuery] = React.useState("");
  const [expected, setExpected] = React.useState("");
  const [changingDate, setChangingDate] = React.useState(false);
  const [notes, setNotes] = React.useState("");
  const [clientError, setClientError] = React.useState<string | null>(null);
  const [state, action, pending] = React.useActionState<OrderState, FormData>(saveOrderAction, {});
  const supplier = suppliers.find((s) => s.id === supplierId) ?? null;

  // Al elegir el proveedor: su catálogo, los datos de la orden y la próxima entrega.
  React.useEffect(() => {
    if (!supplierId) return;
    let alive = true;
    supplierCatalogAction(supplierId, place.id)
      .then((c) => {
        if (!alive) return;
        if (!c) {
          setLoad({ state: "error" });
          return;
        }
        setLoad({ state: "ok", ...c });
        setExpected((prev) => prev || c.info.nextDelivery || "");
      })
      .catch(() => alive && setLoad({ state: "error" }));
    return () => {
      alive = false;
    };
  }, [supplierId, place.id, attempt]);

  const products = load.state === "ok" ? load.products : [];
  const info = load.state === "ok" ? load.info : null;
  const lines = Object.entries(qty)
    .filter(([, q]) => q > 0)
    .map(([id, quantity]) => ({ purchase_product_id: id, quantity }));
  const byId = new Map(products.map((p) => [p.purchase_product_id, p]));
  const estimate = orderEstimate(
    lines.map((l) => ({
      quantity: l.quantity,
      price: byId.get(l.purchase_product_id)?.list_price ?? null,
    })),
    info?.canSeePrices ?? false,
  );
  // Métricas confiables: si ningún artículo pedido tiene precio en la lista, no hay total (nunca «$ 0»); si faltan
  // algunos, el total es «desde» y el mínimo no se da por cumplido ni se cuenta lo que falta como exacto.
  const priced = estimate !== null && lines.length > 0 && estimate.missing < lines.length;
  const partial = priced && estimate !== null && estimate.missing > 0;
  const totalText = !estimate
    ? null
    : !priced
      ? "—"
      : `${partial ? "desde " : ""}${formatMoney(estimate.total)}`;
  const minimum =
    estimate && priced ? minimumNotice(estimate.total, info?.minimumOrderAmount ?? null) : null;
  const dirty = lines.length > 0 || notes.trim().length > 0;
  useUnsavedWarning(dirty && !pending);

  function pickSupplier(id: string) {
    if (id === supplierId) return;
    if (dirty && !window.confirm("Se borran las cantidades cargadas. ¿Cambiar de proveedor?"))
      return;
    setSupplierId(id);
    setLoad({ state: "loading" });
    setQty({});
    setQuery("");
    setExpected("");
    setChangingDate(false);
    setClientError(null);
  }

  // Cambiar la entrega a mano: la base la vuelve a controlar (no antes de hoy).
  function resetDate() {
    if (!supplierId) return;
    expectedDeliveryAction(supplierId, today)
      .then((d) => d && setExpected(d))
      .catch(() => undefined);
    setChangingDate(false);
  }

  const q = query.trim().toLowerCase();
  const shown = products.filter(
    (p) =>
      q.length < 2 ||
      p.description.toLowerCase().includes(q) ||
      (p.supplier_sku ?? "").toLowerCase().includes(q) ||
      p.code.toLowerCase().includes(q),
  );
  const recent = shown.filter((p) => p.recent);
  const rest = shown.filter((p) => !p.recent);

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

  const sendLabel = pending
    ? "Enviando…"
    : (info?.requiresApproval ?? supplier?.requiresApproval)
      ? "Enviar a aprobación"
      : "Enviar orden";
  const count = lines.length === 1 ? "1 artículo" : `${lines.length} artículos`;

  return (
    <form
      action={action}
      onSubmit={submit}
      className="flex flex-col gap-4 desk:min-h-0 desk:flex-[1_1_0px]"
    >
      <input
        type="hidden"
        name="order"
        value={JSON.stringify({
          restaurant_id: place.id,
          supplier_id: supplier?.id,
          lines,
          notes: notes.trim() || undefined,
          expected_on: expected || undefined,
        })}
      />

      <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[15.625rem_minmax(0,1fr)_20rem] desk:grid-rows-[minmax(0,1fr)]">
        {/* 1. El proveedor. En el celular, un desplegable arriba. */}
        {suppliers.length === 0 ? (
          <p className="text-sm text-ink desk:hidden">
            No hay proveedores activos para pedir. Los carga Compras en Proveedores.
          </p>
        ) : null}
        <Field id="oc-proveedor" label="Proveedor" className="desk:hidden">
          <Select
            value={supplierId ?? ""}
            onChange={(e) => e.target.value && pickSupplier(e.target.value)}
          >
            <option value="" disabled>
              Elegí el proveedor
            </option>
            {suppliers.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name} · {supplierDays(s.orderDays, today)}
              </option>
            ))}
          </Select>
        </Field>
        <Tile title="Proveedores" scroll className="hidden desk:flex">
          {suppliers.length === 0 ? (
            <p className="text-sm text-ink">
              No hay proveedores activos para pedir. Los carga Compras en Proveedores.
            </p>
          ) : (
            <ul aria-label="A quién le pedís" className="flex flex-col gap-1">
              {suppliers.map((s) => {
                const current = s.id === supplierId;
                return (
                  <li key={s.id}>
                    <button
                      type="button"
                      aria-pressed={current}
                      onClick={() => pickSupplier(s.id)}
                      className={cn(
                        "flex min-h-control-sm w-full flex-col items-start gap-1 rounded-sm px-2 py-2 text-left text-sm text-ink hover:bg-line/50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                        current &&
                          "bg-nav-active font-medium text-nav-active-ink hover:bg-nav-active",
                      )}
                    >
                      <span className="[overflow-wrap:anywhere]">{s.name}</span>
                      {/* Sobre el fondo del elegido, su tono oscuro: ink-muted no llega a 4,5:1 (design.md). */}
                      <span
                        className={cn(
                          "text-xs font-normal",
                          current ? "text-nav-active-ink" : "text-ink-muted",
                        )}
                      >
                        {supplierDays(s.orderDays, today)}
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </Tile>

        {/* 2. Sus artículos. */}
        <Tile
          title={supplier ? `Artículos de ${supplier.name}` : "Artículos"}
          scroll
          aside={
            load.state === "ok" && info && !info.canSeePrices
              ? "Sin precios: los ve Compras"
              : undefined
          }
        >
          {!supplier ? (
            <p className="text-base text-ink">Elegí a qué proveedor le pedís.</p>
          ) : load.state === "loading" || load.state === "idle" ? (
            <p className="text-sm text-ink-muted">Cargando los artículos…</p>
          ) : load.state === "error" ? (
            <div role="alert" className="flex flex-wrap items-center gap-2 text-sm text-bad-ink">
              No pudimos cargar los artículos del proveedor.
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  setLoad({ state: "loading" });
                  setAttempt((n) => n + 1);
                }}
              >
                Reintentar
              </Button>
            </div>
          ) : products.length === 0 ? (
            <p className="text-base text-ink">
              Este proveedor no tiene artículos para pedir. Compras los suma desde su ficha o desde
              una lista de precios.
            </p>
          ) : (
            <div className="flex flex-col gap-3">
              <div className="relative">
                <label htmlFor="oc-buscar" className="sr-only">
                  Buscar en los artículos
                </label>
                <Search
                  aria-hidden="true"
                  className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-ink-muted"
                />
                <Input
                  id="oc-buscar"
                  type="search"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  autoComplete="off"
                  placeholder="Buscar por nombre o código"
                  className="pl-9 desk:min-h-control-sm"
                />
              </div>
              <ProductList
                title="Pedidos en los últimos 60 días"
                products={recent}
                qty={qty}
                setQty={setQty}
                canSeePrices={info?.canSeePrices ?? false}
              />
              <ProductList
                title={recent.length > 0 ? "El resto de sus artículos" : "Sus artículos"}
                products={rest}
                qty={qty}
                setQty={setQty}
                canSeePrices={info?.canSeePrices ?? false}
              />
              {shown.length === 0 ? (
                <p className="text-sm text-ink-muted">Ningún artículo con ese nombre o código.</p>
              ) : null}
            </div>
          )}
        </Tile>

        {/* 3. La orden. En la computadora, la columna de la derecha con los botones abajo. */}
        <div className="contents desk:flex desk:min-h-0 desk:flex-col desk:gap-3">
          <Tile title="La orden" scroll className="desk:flex-[1_1_0px]">
            {lines.length === 0 ? (
              <p className="text-sm text-ink-muted">
                Todavía no pediste nada. Las cantidades arrancan en 0.
              </p>
            ) : (
              <ul aria-label="Lo que se pide" className="flex flex-col gap-1 text-sm">
                {lines.map((l) => {
                  const p = byId.get(l.purchase_product_id);
                  return (
                    <li key={l.purchase_product_id} className="flex justify-between gap-2">
                      <span className="min-w-0 [overflow-wrap:break-word] text-ink">
                        {p?.description ?? "Artículo"}
                      </span>
                      <span className="flex shrink-0 flex-col items-end text-ink tabular-nums">
                        {qtyText(l.quantity)} × {p?.package_name ?? "envase"}
                        {estimate && p && p.list_price !== null ? (
                          <span className="text-xs text-ink-muted">
                            {formatMoney(l.quantity * p.list_price)}
                          </span>
                        ) : null}
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}
            <dl className="flex flex-col gap-2 border-t border-line pt-2 text-sm">
              {estimate ? (
                <div className="flex items-baseline justify-between gap-2">
                  <dt className="text-ink-muted">Total estimado</dt>
                  <dd className="text-base font-semibold text-ink tabular-nums">{totalText}</dd>
                </div>
              ) : null}
              {minimum && info?.minimumOrderAmount ? (
                <div className="flex items-center justify-between gap-2">
                  <dt className="text-ink-muted">Pedido mínimo</dt>
                  <dd>
                    {minimum.reached && !partial ? (
                      <Badge status="ok">
                        {estimate?.total === info.minimumOrderAmount ? "Llega a" : "Supera"}{" "}
                        {formatMoney(info.minimumOrderAmount)}
                      </Badge>
                    ) : minimum.reached ? (
                      <Badge status="ok">Supera {formatMoney(info.minimumOrderAmount)}</Badge>
                    ) : (
                      <Badge status="warn">
                        Faltan {partial ? "hasta " : ""}
                        {formatMoney(minimum.short)}
                      </Badge>
                    )}
                  </dd>
                </div>
              ) : null}
              {supplier ? (
                <div className="flex items-center justify-between gap-2">
                  <dt className="text-ink-muted">Llega</dt>
                  <dd className="flex items-center gap-2 text-ink">
                    {expected
                      ? dayText(expected)
                      : "Elegila: el proveedor no tiene días de entrega"}
                    <button
                      type="button"
                      onClick={() => (changingDate ? resetDate() : setChangingDate(true))}
                      className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline desk:min-h-control-sm"
                    >
                      {/* Lo que se ve empieza el nombre accesible (WCAG 2.5.3); lo oculto le da contexto. */}
                      {changingDate ? (
                        <>
                          Volver a la del proveedor
                          <span className="sr-only"> (fecha de entrega)</span>
                        </>
                      ) : (
                        <>
                          Cambiar
                          <span className="sr-only"> la fecha de entrega</span>
                        </>
                      )}
                    </button>
                  </dd>
                </div>
              ) : null}
              {info?.channel ? (
                <div className="flex items-center justify-between gap-2">
                  <dt className="text-ink-muted">Se manda por</dt>
                  <dd className="text-ink">{CHANNEL_NAMES[info.channel] ?? info.channel}</dd>
                </div>
              ) : null}
            </dl>
            {/* Fuera de la lista de datos (dl solo lleva pares título y valor). */}
            {estimate && estimate.missing > 0 && !priced ? (
              <p className="text-xs text-ink-muted">
                Sin precio en la lista vigente: no hay total.
              </p>
            ) : estimate && estimate.missing > 0 ? (
              <p className="text-xs text-ink-muted">
                {estimate.missing === 1
                  ? "Un artículo no tiene precio en la lista vigente: no suma."
                  : `${estimate.missing} artículos no tienen precio en la lista vigente: no suman.`}
              </p>
            ) : null}
            {supplier && changingDate ? (
              <Field id="oc-entrega" label="Entrega esperada">
                <DateInput value={expected} min={today} onChange={setExpected} />
              </Field>
            ) : null}
            {supplier ? (
              <Field id="oc-notas" label="Nota para el proveedor">
                <Textarea
                  value={notes}
                  rows={2}
                  maxLength={1000}
                  onChange={(e) => setNotes(e.target.value)}
                  className="min-h-16"
                />
              </Field>
            ) : null}
            {(info?.requiresApproval ?? supplier?.requiresApproval) ? (
              <p className="text-sm text-ink">La aprueba Compras antes de salir.</p>
            ) : null}
          </Tile>

          {/* Los botones: en la computadora, al pie de la orden; en el celular, en la barra fija de abajo. */}
          <div className="sticky bottom-[calc(var(--spacing-bottom-nav)+env(safe-area-inset-bottom))] z-30 -mx-4 flex flex-col gap-2 border-t border-line bg-surface px-4 py-3 desk:static desk:mx-0 desk:rounded-md desk:border desk:p-3">
            <p className="flex justify-between text-sm text-ink tabular-nums" aria-live="polite">
              <span>{count}</span>
              {totalText ? <span className="font-medium">{totalText}</span> : null}
            </p>
            {clientError ? (
              <p role="alert" className="text-sm text-bad-ink">
                {clientError}
              </p>
            ) : null}
            <FormNotice state={state} />
            <div className="flex gap-2">
              <Button
                type="submit"
                name="mode"
                value="draft"
                variant="outline"
                disabled={pending || !supplier}
                className="flex-1"
              >
                Guardar borrador
              </Button>
              <Button
                type="submit"
                name="mode"
                value="send"
                disabled={pending || !supplier}
                className="flex-1"
              >
                {sendLabel}
              </Button>
            </div>
          </div>
        </div>
      </div>
    </form>
  );
}

// Una sección de artículos: nombre, envase, precio de lista (si se ve), cantidad y subtotal.
function ProductList({
  title,
  products,
  qty,
  setQty,
  canSeePrices,
}: {
  title: string;
  products: CatalogProduct[];
  qty: Record<string, number>;
  setQty: React.Dispatch<React.SetStateAction<Record<string, number>>>;
  canSeePrices: boolean;
}) {
  const id = React.useId();
  if (products.length === 0) return null;
  return (
    <section aria-labelledby={id} className="flex flex-col gap-1">
      <h3 id={id} className="text-sm font-medium text-ink-muted">
        {title}
      </h3>
      <ul className="flex flex-col divide-y divide-line rounded-sm border border-line">
        {products.map((p) => {
          const value = qty[p.purchase_product_id] ?? 0;
          const kg = p.billed_by_weight
            ? estimatedKg(value, p.units_per_package, p.estimated_weight_per_unit, p.content_unit)
            : null;
          return (
            <li
              key={p.purchase_product_id}
              className={cn(
                "flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 desk:grid",
                canSeePrices
                  ? "desk:grid-cols-[minmax(0,1fr)_7rem_auto]"
                  : "desk:grid-cols-[minmax(0,1fr)_auto]",
              )}
            >
              <div className="min-w-0 flex-1">
                <p className="text-base [overflow-wrap:break-word] text-ink">{p.description}</p>
                <p className="text-xs text-ink-muted">
                  {p.package_name}
                  {p.supplier_sku ? ` · ${p.supplier_sku}` : ""}
                  {kg !== null ? ` · ≈ ${qtyText(kg)} kg` : ""}
                </p>
              </div>
              {canSeePrices ? (
                <p className="text-right text-sm text-ink tabular-nums">
                  {p.list_price === null ? (
                    <span className="text-xs text-ink-muted">Sin precio en la lista</span>
                  ) : (
                    <>
                      {formatMoney(p.list_price)}
                      <span className="block text-xs text-ink-muted">
                        {p.list_includes_vat ? "con IVA" : "sin IVA"}
                      </span>
                    </>
                  )}
                </p>
              ) : null}
              {/* El subtotal va en «La orden», al lado de cada renglón: así el nombre tiene lugar. */}
              <Stepper
                label={p.description}
                value={value}
                onChange={(v) => setQty((all) => ({ ...all, [p.purchase_product_id]: v }))}
              />
            </li>
          );
        })}
      </ul>
    </section>
  );
}

// Cantidad con − / +: 44 px en el celular (la cocina), 36 en la computadora. Lo escrito se guarda tal cual (para poder
// tipear «1,5»); el número sale de ahí. Si no es un número, el campo lo marca.
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
  // Si el valor cambia por los botones, el texto lo sigue.
  const shown =
    Number(text.replace(",", ".")) === value || (text === "" && value === 0)
      ? text
      : String(value).replace(".", ",");
  function set(v: number) {
    setText(v === 0 ? "" : String(v).replace(".", ","));
    onChange(v);
  }
  const button =
    "flex size-touch items-center justify-center rounded-sm border border-line bg-surface text-ink hover:bg-line/50 disabled:opacity-40 desk:size-control-sm";
  return (
    <div role="group" aria-label={`Cantidad de ${label}`} className="flex items-center gap-1">
      <button
        type="button"
        aria-label={`Uno menos de ${label}`}
        disabled={value <= 0}
        onClick={() => set(Math.max(0, Math.round((value - 1) * 1000) / 1000))}
        className={button}
      >
        <Minus aria-hidden="true" className="size-4" />
      </button>
      <label htmlFor={id} className="sr-only">
        Cantidad de {label}
      </label>
      <input
        id={id}
        inputMode="decimal"
        value={shown}
        placeholder="0"
        onChange={(e) => {
          // Solo números y una coma (o punto) decimal: lo demás no entra (nunca un número viejo marcado en rojo).
          const [whole = "", ...decimals] = e.target.value.replace(/[^\d.,]/g, "").split(/[.,]/);
          const t = decimals.length > 0 ? `${whole},${decimals.join("").slice(0, 3)}` : whole;
          setText(t);
          const n = Number(t.replace(",", "."));
          onChange(t === "" || !Number.isFinite(n) ? 0 : Math.min(n, 100000));
        }}
        className={cn(
          "h-touch w-14 rounded-sm border border-line bg-surface text-center text-base text-ink tabular-nums placeholder:text-ink-muted desk:h-control-sm",
          value > 0 && "border-primary font-medium",
        )}
      />
      <button
        type="button"
        aria-label={`Uno más de ${label}`}
        onClick={() => set(Math.round((value + 1) * 1000) / 1000)}
        className={button}
      >
        <Plus aria-hidden="true" className="size-4" />
      </button>
    </div>
  );
}
