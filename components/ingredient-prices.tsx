import Link from "next/link";

import { PriceProposal } from "@/components/price-proposal";
import { Badge } from "@/components/ui/badge";
import { CardDescription } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import type { IngredientDetail, Supplier } from "@/lib/catalog";
import { formatDate, getActiveRestaurantId, getMyScopes } from "@/lib/data";
import { todayInArgentina } from "@/lib/forms/schemas";
import {
  DOCUMENT_LABELS,
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
import { productDefaults } from "@/lib/price-proposal";

// Precios de una materia prima (ADR-0029): ¿cuánto cuesta en mi local y qué precios hay cargados?
// Solo para quien ve precios (la ficha no la muestra si no). Proponer un precio pide prices.propose;
// lo aprueba el Controller y, si cambia mucho, también Dirección General.
export async function IngredientPrices({
  part,
  ingredient,
  canPropose,
  canSeeImpact,
  suppliers,
}: {
  // Ficha sin scroll (ADR-0046): el detalle va en el panel «Ver los productos» y el formulario, en «Proponer precio».
  part: "detail" | "propose";
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
  const activeSuppliers = new Set(suppliers.map((x) => x.id));
  const showForm = canPropose && products.length > 0 && places.length > 0;

  if (part === "propose") {
    if (showForm)
      return (
        <PriceProposal
          ingredientId={ingredient.id}
          products={products.map((p) => ({
            id: p.id,
            label: `${p.description} (${p.contents})`,
            packageUnit: p.packageUnitName.toLowerCase(),
            ...productDefaults(p.id, p.supplierId, rows, activeSuppliers),
          }))}
          places={places}
          suppliers={suppliers.map((x) => ({ id: x.id, name: x.name }))}
          today={today}
        />
      );
    return (
      <p className="text-base text-ink-muted">
        {products.length === 0
          ? "Para proponer un precio, primero cargá cómo se compra."
          : "No tenés locales donde proponer precios."}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      {local ? (
        <LocalCostSummary cost={local} unitCode={ingredient.unitCode} />
      ) : !activeRestaurant && scopes.length > 1 ? (
        <CardDescription>Elegí un local arriba para ver cuánto cuesta ahí.</CardDescription>
      ) : null}
      {current.length === 0 ? (
        <EmptyState title="Todavía no hay precios aprobados.">
          {canPropose ? "Proponelo desde la tarjeta, con «Proponer precio»." : "Los carga Compras."}
        </EmptyState>
      ) : (
        <ul aria-label="Precios vigentes" className="flex flex-col divide-y divide-line">
          {current.map((r) => (
            <PriceItem key={r.id} row={r} impact={canSeeImpact} />
          ))}
        </ul>
      )}
      {rows.length > current.length ? (
        <section aria-labelledby="historial-precios" className="flex flex-col gap-2">
          <h3 id="historial-precios" className="text-base font-semibold text-ink">
            Historial de precios
          </h3>
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
        </section>
      ) : null}
    </div>
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
        {row.origin ? (
          row.origin.canOpen ? (
            <Link
              href={`/compras/facturas/${row.origin.invoiceId}`}
              className="text-primary underline-offset-4 hover:underline"
            >
              {originText(row.origin)}
            </Link>
          ) : (
            originText(row.origin)
          )
        ) : (
          DOCUMENT_LABELS[row.document]
        )}
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

// «Factura A 0003-00012345 · Proveedor» (sin el proveedor si la sesión no ve proveedores).
function originText(origin: { label: string; supplier: string | null }): string {
  return origin.supplier ? `${origin.label} · ${origin.supplier}` : origin.label;
}
