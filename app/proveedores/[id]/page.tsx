import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { setSupplierActiveAction } from "@/app/proveedores/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import {
  CategoriesSection,
  CustomerNumbers,
  IdentitySection,
  NotesField,
  OperationSection,
  PaymentSection,
  SheetBar,
  SupplierSheetProvider,
  SupplierStateBadge,
} from "@/components/supplier-sheet/sheet-editor";
import { FormTextarea } from "@/components/ui/form";
import { InfoTip } from "@/components/ui/info-tip";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { Tile } from "@/components/ui/tile";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { UUID, first, formatDate } from "@/lib/data";
import { getCurrentPriceList } from "@/lib/price-lists-data";
import { VAT_LABELS, formatCuit } from "@/lib/suppliers";
import { getGroupRestaurants, getPurchaseRubros, getSupplierSheet } from "@/lib/suppliers-data";

// Ficha de proveedor (Fase 3, Prompt 1, ADR-0050), con el patrón de las pantallas de carga sin scroll (ADR-0046): una
// línea de encabezado, 4 indicadores y tres columnas de tarjetas que se editan donde se ven; todo se guarda junto con la
// barra de abajo, con motivo. Quien no administra proveedores la ve en solo lectura, y sin el pago si no lo ve (lo
// decide la base). En el celular, de consulta.
export default function ProveedorPage({ params, searchParams }: PageProps<"/proveedores/[id]">) {
  return (
    <AppShell
      title="Proveedor"
      fill
      heading={
        <Suspense fallback="Proveedor">
          <SupplierName params={params} />
        </Suspense>
      }
      back={
        <Suspense fallback={null}>
          <Back searchParams={searchParams} />
        </Suspense>
      }
      meta={
        <Suspense fallback={null}>
          <Meta params={params} />
        </Suspense>
      }
      actions={
        <Suspense fallback={null}>
          <ActiveAction params={params} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Supplier params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const supplierById = cache(getSupplierSheet);

async function load(params: PageProps<"/proveedores/[id]">["params"]) {
  await requireMenu("suppliers");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  return supplierById(id);
}

async function SupplierName({ params }: { params: PageProps<"/proveedores/[id]">["params"] }) {
  const s = await load(params);
  return s ? s.tradeName || s.name : "Proveedor";
}

function backHref(volver: string | undefined): string {
  return volver && /^\/proveedores(\?|$)/.test(volver) ? volver : "/proveedores";
}

async function Back({
  searchParams,
}: {
  searchParams: PageProps<"/proveedores/[id]">["searchParams"];
}) {
  const query = await searchParams;
  return (
    <BackLink href={backHref(first(query.volver))} label="Volver a proveedores">
      Proveedores
    </BackLink>
  );
}

// La línea del nombre: razón social · CUIT · condición frente al IVA, y el estado con palabra.
async function Meta({ params }: { params: PageProps<"/proveedores/[id]">["params"] }) {
  const s = await load(params);
  if (!s) return null;
  const parts = [
    s.tradeName ? s.name : null,
    s.taxId ? `CUIT ${formatCuit(s.taxId)}` : "Sin CUIT",
    s.vatCondition ? VAT_LABELS[s.vatCondition] : null,
    s.code,
  ].filter(Boolean);
  return (
    <>
      <span className="text-sm text-ink-muted tabular-nums">{parts.join(" · ")}</span>
      <SupplierStateBadge active={s.isActive} />
    </>
  );
}

// Desactivar (o reactivar): un botón a la derecha del nombre, con motivo. En el celular la ficha es de consulta.
async function ActiveAction({ params }: { params: PageProps<"/proveedores/[id]">["params"] }) {
  const s = await load(params);
  if (!s || !s.canManage) return null;
  const label = s.isActive ? "Desactivar" : "Reactivar";
  return (
    <div className="hidden desk:block">
      <ActionModal
        label={label}
        icon="none"
        title={s.isActive ? "Desactivar el proveedor" : "Reactivar el proveedor"}
        description={
          s.isActive
            ? "No se borra nada: deja de ofrecerse para pedidos nuevos y su ficha y su historia quedan."
            : "Vuelve a ofrecerse para pedidos."
        }
      >
        <ActionForm
          action={setSupplierActiveAction}
          schema="reason"
          submitLabel={label}
          variant={s.isActive ? "destructive" : "default"}
        >
          <input type="hidden" name="supplierId" value={s.id} />
          <input type="hidden" name="active" value={s.isActive ? "false" : "true"} />
          <FormTextarea
            id="prov-motivo-activo"
            name="reason"
            label="Motivo"
            hint="Queda en el historial."
            required
            maxLength={500}
          />
        </ActionForm>
      </ActionModal>
    </div>
  );
}

// La lista vigente (ADR-0052): su fecha y si venció según la frecuencia de la ficha. «Ver la lista» lleva a su detalle;
// sin lista, quien carga listas va a «Cargar lista». Quien no ve listas (el cocinero) ve el motivo, sin precios.
async function CurrentListMetric({
  supplierId,
  canView,
  canManage,
}: {
  supplierId: string;
  canView: boolean;
  canManage: boolean;
}) {
  const current = canView ? await getCurrentPriceList(supplierId) : null;
  const back = encodeURIComponent(`/proveedores/${supplierId}`);
  const link =
    "inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8";
  if (!current) {
    return (
      <Metric
        compact
        label="Lista de precios vigente"
        value={null}
        missingReason={
          canView ? "Sin lista aceptada." : "La ven Compras y quienes controlan precios."
        }
        emptyLabel="Sin datos"
        status="none"
        statusLabel="Sin datos"
        action={
          canManage ? (
            <Link
              href={`/listas-de-precios/nueva?proveedor=${supplierId}&volver=${back}`}
              className={link}
            >
              Cargar lista
            </Link>
          ) : undefined
        }
      />
    );
  }
  const date = formatDate(current.validFrom);
  if (current.pending)
    return (
      <Metric
        compact
        label="Lista de precios vigente"
        value={null}
        missingReason={`Hay una recibida el ${date} sin aceptar.`}
        emptyLabel="Sin datos"
        status="none"
        statusLabel="Sin datos"
        action={
          <Link href={`/listas-de-precios/${current.id}?volver=${back}`} className={link}>
            Ver la lista
          </Link>
        }
      />
    );
  return (
    <Metric
      compact
      label="Lista de precios vigente"
      value={date}
      period={current.items === 1 ? "1 artículo" : `${current.items} artículos`}
      emptyLabel="Sin datos"
      // Vencida según la frecuencia de la ficha (design.md: dato vencido = Atención, con su fecha).
      status={current.expired ? "warn" : "ok"}
      statusLabel={current.expired ? "Vencida" : "Al día"}
      action={
        <Link href={`/listas-de-precios/${current.id}?volver=${back}`} className={link}>
          Ver la lista
        </Link>
      }
    />
  );
}

// Una tarjeta que, si no entra, se desplaza adentro (la página queda quieta). relative: el sr-only de adentro no escapa.
const scrolls = "relative desk:min-h-0 desk:overflow-y-auto";

const NOTICES: Record<string, { status: "ok" | "info"; text: string }> = {
  guardado: { status: "ok", text: "Cambios guardados." },
  creado: { status: "ok", text: "Proveedor creado. Completá su ficha y guardá." },
};

async function Supplier({
  params,
  searchParams,
}: {
  params: PageProps<"/proveedores/[id]">["params"];
  searchParams: PageProps<"/proveedores/[id]">["searchParams"];
}) {
  const [s, query, menus] = await Promise.all([load(params), searchParams, getMenus()]);
  if (!s) notFound();
  const [rubros, restaurants] = await Promise.all([
    menus.catalog ? getPurchaseRubros() : Promise.resolve([]),
    getGroupRestaurants(),
  ]);
  const editable = s.canManage && s.stamp !== null;
  const saved = NOTICES[first(query.aviso) ?? ""] ?? null;

  return (
    <>
      {saved ? (
        <Notice status={saved.status} className={editable ? "desk:hidden" : undefined}>
          {saved.text}
        </Notice>
      ) : null}
      {s.taxIdInvalid ? (
        <Notice status="warn">
          El CUIT cargado ({s.taxId}) no es válido. Corregilo en Identificación y contacto.
        </Notice>
      ) : null}
      <SupplierSheetProvider
        supplierId={s.id}
        stamp={s.stamp}
        editable={editable}
        initial={s.draft}
        options={{ rubros, restaurants }}
        notice={saved}
      >
        {/* 4 indicadores. Se llenan con los próximos prompts: hasta entonces, «—» con su motivo y Sin datos (nunca un
            estado positivo sin datos). En el celular, uno debajo del otro. */}
        <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4">
          <CurrentListMetric
            supplierId={s.id}
            canView={menus.priceLists}
            canManage={menus.priceListsManage}
          />
          <Metric
            compact
            label="Saldo de cuenta corriente"
            value={null}
            missingReason="Sin facturas ni pagos."
            emptyLabel="Sin datos"
            status="none"
            statusLabel="Sin datos"
          />
          <Metric
            compact
            label="Órdenes de compra abiertas"
            value={null}
            missingReason="Llegan con las órdenes de compra."
            emptyLabel="Sin datos"
            status="none"
            statusLabel="Sin datos"
          />
          <Metric
            compact
            label="Última compra"
            value={null}
            missingReason="Sin compras registradas."
            emptyLabel="Sin datos"
            status="none"
            statusLabel="Sin datos"
          />
        </div>

        {/* Tres columnas que ocupan el alto que queda (4,5 : 6 : 3,5: la operativa es la más cargada y la identificación
            necesita ancho para los nombres). La página no se mueve: si una pantalla es más baja (por ejemplo 1715 × 843,
            la de Soy), lo que sobra se desplaza dentro de su tarjeta. Cada eslabón lleva min-h-0 y base 0px (design.md).
            En el celular, una debajo de otra. */}
        <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[4.5fr_6fr_3.5fr] desk:grid-rows-[minmax(0,1fr)]">
          <Tile id="identificacion" title="Identificación y contacto" className={scrolls}>
            <IdentitySection />
          </Tile>
          <Tile
            id="operativa"
            title="Operativa"
            className={scrolls}
            aside={<CustomerNumbers />}
            titleExtra={
              <InfoTip label="operativa">
                Cuándo se le pide, cuándo entrega, por dónde se le manda la orden de compra (siempre
                desde la cuenta de la empresa) y cómo factura.
              </InfoTip>
            }
          >
            <OperationSection />
          </Tile>
          <div className="flex min-h-0 min-w-0 flex-col gap-4">
            {s.canSeePayment ? (
              <Tile id="pago" title="Pago" className={scrolls}>
                <PaymentSection />
              </Tile>
            ) : null}
            <Tile
              id="rubros"
              title={menus.catalog ? "Rubros y observaciones" : "Observaciones"}
              className={`${scrolls} desk:flex-[1_1_0px]`}
            >
              {menus.catalog ? <CategoriesSection /> : null}
              <NotesField />
            </Tile>
          </div>
        </div>

        <SheetBar />
      </SupplierSheetProvider>
    </>
  );
}
