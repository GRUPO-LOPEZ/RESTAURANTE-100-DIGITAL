import Link from "next/link";

import { proposePriceAction } from "@/app/materias-primas/actions";
import { ActionForm } from "@/components/action-form";
import { Disclosure } from "@/components/disclosure";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormCheckbox, FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import type { IngredientDetail, Supplier } from "@/lib/catalog";
import { formatDate, getActiveRestaurantId, getMyScopes } from "@/lib/data";
import { todayInArgentina } from "@/lib/forms/schemas";
import {
  DOCUMENT_LABELS,
  SOURCE_LABELS,
  VAT_RATES,
  currentByProductAndPlace,
  formatMoney,
  getIngredientPrices,
  getLocalCost,
  getProposalPlaces,
  perBaseLabel,
  type LocalCost,
  type PriceRecordRow,
} from "@/lib/prices";
import { getMySession } from "@/lib/auth/session";

// Precios de una materia prima (ADR-0029): ¿cuánto cuesta en mi local y qué precios hay cargados?
// Solo para quien ve precios (la ficha no la muestra si no). Proponer un precio pide prices.propose;
// lo aprueba el Controller y, si cambia mucho, también Dirección General.
export async function IngredientPrices({
  ingredient,
  canPropose,
  canSeeImpact,
  suppliers,
}: {
  ingredient: IngredientDetail;
  canPropose: boolean;
  // Quien ve costos de recetas puede ver a qué platos les pegó cada precio.
  canSeeImpact: boolean;
  suppliers: Supplier[];
}) {
  const session = await getMySession();
  const [rows, activeId, scopes, places] = await Promise.all([
    getIngredientPrices(ingredient.id),
    getActiveRestaurantId(session.user_id),
    getMyScopes(),
    canPropose ? getProposalPlaces() : Promise.resolve([]),
  ]);
  // El local elegido arriba; quien tiene un solo local no ve el selector y usa ese.
  const activeRestaurant = scopes.some((s) => s.restaurant_id === activeId)
    ? activeId
    : scopes.length === 1
      ? (scopes[0]?.restaurant_id ?? null)
      : null;
  const local = activeRestaurant ? await getLocalCost(ingredient.id, activeRestaurant) : null;
  const current = currentByProductAndPlace(rows);
  const currentIds = new Set(current.map((r) => r.id));
  const today = todayInArgentina();
  const products = ingredient.products.filter((p) => p.isActive);
  const showForm = canPropose && products.length > 0 && places.length > 0;

  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>Precios</CardTitle>
      {local ? (
        <LocalCostSummary cost={local} unitCode={ingredient.unitCode} />
      ) : !activeRestaurant && scopes.length > 1 ? (
        <CardDescription>Elegí un local arriba para ver cuánto cuesta ahí.</CardDescription>
      ) : null}
      {current.length === 0 ? (
        <EmptyState title="Todavía no hay precios aprobados.">
          {showForm ? "Proponé el primero con «Proponer precio»." : "Los carga Compras."}
        </EmptyState>
      ) : (
        <ul aria-label="Precios vigentes" className="flex flex-col divide-y divide-line">
          {current.map((r) => (
            <PriceItem key={r.id} row={r} impact={canSeeImpact} />
          ))}
        </ul>
      )}
      {rows.length > current.length ? (
        <Disclosure summary="Ver el historial de precios">
          {rows.length > 10 ? <CardDescription>Se muestran los últimos 10.</CardDescription> : null}
          <ul aria-label="Historial de precios" className="flex flex-col divide-y divide-line">
            {rows.slice(0, 10).map((r) => (
              <PriceItem
                key={r.id}
                row={r}
                when={
                  currentIds.has(r.id) ? "current" : r.validFrom > today ? "scheduled" : "previous"
                }
              />
            ))}
          </ul>
        </Disclosure>
      ) : null}
      {showForm ? (
        <Disclosure summary="Proponer precio">
          <ActionForm
            action={proposePriceAction}
            schema="priceProposal"
            submitLabel="Proponer precio"
            pendingLabel="Proponiendo…"
          >
            <input type="hidden" name="ingredientId" value={ingredient.id} />
            <FormSelect
              id="precio-producto"
              label="Producto"
              name="product_id"
              required
              defaultValue={products.length === 1 ? products[0]?.id : ""}
            >
              <option value="" disabled>
                Elegí el producto
              </option>
              {products.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.description} ({p.contents})
                </option>
              ))}
            </FormSelect>
            <div className="grid gap-4 sm:grid-cols-2">
              <FormSelect
                id="precio-lugar"
                label="Para quién vale"
                hint="Un local sin precio propio usa el de su marca, y si no, el del grupo."
                name="place"
                required
                defaultValue={places.length === 1 ? places[0]?.value : ""}
              >
                <option value="" disabled>
                  Elegí para quién vale
                </option>
                {places.map((p) => (
                  <option key={p.value} value={p.value}>
                    {p.label}
                  </option>
                ))}
              </FormSelect>
              <FormInput
                id="precio-desde"
                label="Vale desde"
                name="valid_from"
                type="date"
                required
                defaultValue={todayInArgentina()}
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <FormInput
                id="precio-envase"
                label="Precio del envase ($)"
                hint="El precio del producto completo, como lo cotizó el proveedor."
                name="package_price"
                required
                inputMode="decimal"
                autoComplete="off"
              />
              <FormInput
                id="precio-descuento"
                label="Descuento por envase ($, opcional)"
                name="discount_amount"
                inputMode="decimal"
                autoComplete="off"
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <FormSelect
                id="precio-comprobante"
                label="Comprobante"
                name="document_type"
                required
                defaultValue="invoice"
              >
                <option value="invoice">{DOCUMENT_LABELS.invoice}</option>
                <option value="no_invoice">{DOCUMENT_LABELS.no_invoice}</option>
              </FormSelect>
              <FormSelect
                id="precio-iva"
                label="Alícuota de IVA"
                hint="Solo con factura."
                name="vat_rate"
                defaultValue="21"
              >
                {VAT_RATES.map((v) => (
                  <option key={v} value={v}>
                    {v.replace(".", ",")} %
                  </option>
                ))}
              </FormSelect>
            </div>
            <FormCheckbox
              id="precio-incluye-iva"
              label="El precio ya incluye el IVA"
              hint="Solo con factura."
              name="price_includes_vat"
              defaultChecked
            />
            <div className="grid gap-4 sm:grid-cols-2">
              <FormSelect
                id="precio-proveedor"
                label="Proveedor (opcional)"
                name="supplier_id"
                defaultValue=""
              >
                <option value="">Sin indicar</option>
                {suppliers.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </FormSelect>
              <FormSelect
                id="precio-origen"
                label="Origen"
                hint="Hasta que lleguen las facturas, los precios son valores de prueba."
                name="source"
                required
                defaultValue="test_value"
              >
                <option value="test_value">{SOURCE_LABELS.test_value}</option>
                <option value="manual">{SOURCE_LABELS.manual}</option>
              </FormSelect>
            </div>
            <FormTextarea
              id="precio-notas"
              label="Observaciones (opcional)"
              hint="No escribas montos acá: las observaciones se ven aunque el precio esté oculto."
              name="notes"
              maxLength={1000}
            />
            <FormTextarea
              id="precio-motivo"
              label="Motivo"
              hint="Queda en el historial. No escribas montos: el motivo lo ve quien no ve precios."
              name="reason"
              required
              maxLength={500}
            />
          </ActionForm>
        </Disclosure>
      ) : null}
      {canPropose && products.length === 0 ? (
        <CardDescription>Para proponer un precio, primero cargá cómo se compra.</CardDescription>
      ) : null}
    </Card>
  );
}

function LocalCostSummary({ cost, unitCode }: { cost: LocalCost; unitCode: string }) {
  const { factor, label } = perBaseLabel(cost.base_unit ?? unitCode);
  if (cost.status === "missing_price")
    return <Notice status="warn">En {cost.restaurant} todavía no hay un precio que valga.</Notice>;
  return (
    <div className="flex flex-col gap-2 rounded-sm border border-line p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-base font-medium text-ink">Costo en {cost.restaurant}</span>
        {cost.inherited ? (
          <Badge status="info">
            {cost.price_level === "brand" ? "Heredado de la marca" : "Heredado del grupo"}
          </Badge>
        ) : (
          <Badge status="neutral">Precio propio del local</Badge>
        )}
        {cost.stale ? <Badge status="warn">Desactualizado</Badge> : null}
      </div>
      <p className="text-kpi font-semibold text-ink tabular-nums">
        {cost.unit_cost === null ? (
          "Incompleto"
        ) : (
          <>
            {formatMoney(Number(cost.unit_cost) * factor)}{" "}
            <span className="ml-2 text-base font-normal text-ink-muted">{label}</span>
          </>
        )}
      </p>
      {cost.unit_cost === null ? (
        <p className="text-sm text-ink-muted">
          Falta un dato para calcular el costo (por ejemplo, cuánto trae el envase).
        </p>
      ) : null}
      {cost.status === "missing_legal_entity" ? (
        <Notice status="warn">
          El local no tiene razón social: no se sabe si el IVA se recupera. El precio con IVA es{" "}
          {formatMoney(Number(cost.gross_unit_cost) * factor)} {label}.
        </Notice>
      ) : (
        <p className="text-sm text-ink-muted tabular-nums">
          Sin IVA {formatMoney(Number(cost.net_unit_cost) * factor)} · Con IVA{" "}
          {formatMoney(Number(cost.gross_unit_cost) * factor)} · {cost.product_description} · desde
          el {cost.valid_from ? formatDate(cost.valid_from) : "—"}
        </p>
      )}
    </div>
  );
}

const WHEN = {
  current: { status: "ok", label: "Vigente" },
  scheduled: { status: "info", label: "Programado" },
  previous: { status: "neutral", label: "Anterior" },
} as const;

function PriceItem({
  row,
  when,
  impact,
}: {
  row: PriceRecordRow;
  when?: keyof typeof WHEN;
  impact?: boolean;
}) {
  return (
    <li className="flex flex-col gap-1 py-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-base font-medium text-ink">{row.product}</span>
        <Badge status="neutral">{row.place}</Badge>
        {when ? <Badge status={WHEN[when].status}>{WHEN[when].label}</Badge> : null}
        {row.source === "test_value" ? <Badge status="draft">Valor de prueba</Badge> : null}
      </div>
      <span className="text-base text-ink tabular-nums">
        {formatMoney(row.packagePrice)} el envase · sin IVA {formatMoney(row.netPackagePrice)} · con
        IVA {formatMoney(row.grossPackagePrice)}
      </span>
      <span className="text-sm text-ink-muted tabular-nums">
        {DOCUMENT_LABELS[row.document]}
        {row.vatRate !== null ? ` (${String(row.vatRate).replace(".", ",")} %)` : ""} · desde el{" "}
        {formatDate(row.validFrom)}
      </span>
      {impact ? (
        <Link
          href={`/costos/impacto/${row.id}`}
          className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
        >
          Ver el impacto
          <span className="sr-only">
            {" "}
            de {row.product} en {row.place}
          </span>
        </Link>
      ) : null}
    </li>
  );
}
