import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";
import { Check, FileText, X } from "lucide-react";

import {
  approveInvoiceAction,
  cancelInvoiceAction,
  runInvoiceChecksAction,
} from "@/app/compras/facturas/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { InvoiceFileUpload, NoteForm } from "@/components/invoice-sheet/invoice-files";
import {
  FooterSection,
  HeaderSection,
  InvoiceSheetProvider,
  LinesSection,
  SheetBar,
} from "@/components/invoice-sheet/sheet-editor";
import { Badge } from "@/components/ui/badge";
import { FormTextarea } from "@/components/ui/form";
import { InfoTip } from "@/components/ui/info-tip";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { ShortList } from "@/components/ui/short-list";
import { Tile } from "@/components/ui/tile";
import { requireMenu } from "@/lib/auth/session";
import { UUID, first, formatDateTime } from "@/lib/data";
import { todayInArgentina } from "@/lib/forms/schemas";
import {
  CHECK_LABELS,
  INVOICE_STATUS,
  NOTE_KINDS,
  dueState,
  invoiceLabel,
  isClassA,
  priceDifference,
  shortDate,
  type CheckRow,
  type InvoiceCheckKind,
} from "@/lib/invoices";
import { getInvoiceDetail, type InvoiceDetail } from "@/lib/invoices-data";
import { METHOD_LABELS } from "@/lib/payments";
import { getInvoicePayments, type InvoicePayments } from "@/lib/payments-data";
import { formatMoney } from "@/lib/money";

// Ficha de una factura (Fase 3, Prompt 5B, ADR-0058), con el patrón de las pantallas de carga sin scroll (ADR-0046):
// una línea de encabezado con las acciones (Controlar, Dar por conforme, Cancelar), 4 indicadores y tres tarjetas: los
// datos y el pie, las líneas como planilla con su control, y «Todo junto» (el papel, la recepción, los controles y las
// notas). Lo que se edita se guarda junto con la barra de abajo, con motivo. Una conforme es de solo lectura.
export default function FacturaPage({ params, searchParams }: PageProps<"/compras/facturas/[id]">) {
  return (
    <AppShell
      title="Factura"
      fill
      heading={
        <Suspense fallback="Factura">
          <Heading params={params} />
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
          <Actions params={params} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Invoice params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const invoiceById = cache(getInvoiceDetail);

async function load(params: PageProps<"/compras/facturas/[id]">["params"]) {
  await requireMenu("invoices");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  return invoiceById(id);
}

async function Heading({ params }: { params: PageProps<"/compras/facturas/[id]">["params"] }) {
  const inv = await load(params);
  return inv ? invoiceLabel(inv.invoiceClass, inv.pointOfSale, inv.number) : "Factura";
}

function backHref(volver: string | undefined): string {
  return volver && /^\/(compras\/facturas(\?|$)|materias-primas\/|costos\/)/.test(volver)
    ? volver
    : "/compras/facturas";
}

async function Back({
  searchParams,
}: {
  searchParams: PageProps<"/compras/facturas/[id]">["searchParams"];
}) {
  const query = await searchParams;
  const href = backHref(first(query.volver));
  if (!href.startsWith("/compras/facturas")) return <BackLink href={href}>Volver</BackLink>;
  return (
    <BackLink href={href} label="Volver a facturas">
      Facturas
    </BackLink>
  );
}

// Proveedor · local · fecha, y el estado con palabra.
async function Meta({ params }: { params: PageProps<"/compras/facturas/[id]">["params"] }) {
  const inv = await load(params);
  if (!inv) return null;
  const state = INVOICE_STATUS[inv.status];
  return (
    <>
      <span className="text-sm text-ink-muted tabular-nums">
        {[inv.supplierName, inv.restaurantName, shortDate(inv.issuedOn)].join(" · ")}
      </span>
      <Badge status={state.status}>{state.label}</Badge>
    </>
  );
}

// Las acciones según el estado y lo que la persona puede hacer (lo decide la base: purchasing.invoice_access). En el
// celular la ficha es de consulta.
async function Actions({ params }: { params: PageProps<"/compras/facturas/[id]">["params"] }) {
  const inv = await load(params);
  if (!inv) return null;
  const a = inv.access;
  if (!a.can_edit && !a.can_approve) return null;
  return (
    <div className="flex items-center gap-2">
      {a.can_edit ? (
        <ActionModal
          className="hidden desk:inline-flex"
          label="Cancelar"
          accessibleName="Cancelar la factura"
          icon="none"
          title="Cancelar la factura"
          description="Para una factura cargada por error. No se borra: queda en la historia, y el mismo número se puede volver a cargar."
        >
          <ActionForm
            action={cancelInvoiceAction}
            schema="invoiceReason"
            submitLabel="Cancelar la factura"
            variant="destructive"
          >
            <input type="hidden" name="invoiceId" value={inv.id} />
            <FormTextarea
              id="fc-cancelar-motivo"
              name="reason"
              label="Motivo"
              hint="Queda en el historial."
              required
              maxLength={500}
            />
          </ActionForm>
        </ActionModal>
      ) : null}
      {a.can_approve ? (
        <ActionModal
          label="Dar por conforme"
          icon="none"
          variant="default"
          className="min-h-touch desk:min-h-control"
          title="Dar por conforme"
          description="No pasó el control. Si la revisaste y está bien, queda conforme y liberada a pago, y su precio pasa a ser el costo."
        >
          <ActionForm
            action={approveInvoiceAction}
            schema="invoiceReason"
            submitLabel="Dar por conforme"
          >
            <input type="hidden" name="invoiceId" value={inv.id} />
            <input type="hidden" name="version" value={inv.version} />
            <FormTextarea
              id="fc-conforme-motivo"
              name="reason"
              label="Por qué la das por conforme"
              hint="Queda en el historial, con tu nombre."
              required
              maxLength={500}
            />
          </ActionForm>
        </ActionModal>
      ) : null}
      {a.can_edit ? (
        <ActionForm
          action={runInvoiceChecksAction}
          submitLabel="Controlar"
          pendingLabel="Controlando…"
          variant={a.can_approve ? "outline" : "default"}
          className="hidden desk:flex desk:flex-col desk:gap-2"
        >
          <input type="hidden" name="invoiceId" value={inv.id} />
        </ActionForm>
      ) : null}
    </div>
  );
}

const NOTICES: Record<string, { status: "ok" | "info" | "warn"; text: string }> = {
  observada: { status: "warn", text: "Quedó observada: mirá qué no pasó en «Controles»." },
  conforme: {
    status: "ok",
    text: "Quedó conforme y liberada a pago. Su precio pasa a ser el costo.",
  },
  cancelada: { status: "info", text: "Factura cancelada. Queda en la historia." },
  archivo: { status: "ok", text: "Archivo guardado." },
  "nota-observada": {
    status: "warn",
    text: "Foto de la nota guardada. Se volvió a controlar: quedó observada.",
  },
  "nota-conforme": {
    status: "ok",
    text: "Foto de la nota guardada. Se volvió a controlar: quedó conforme y liberada a pago.",
  },
  guardado: { status: "ok", text: "Cambios guardados. Controlala de nuevo." },
  creada: {
    status: "info",
    text: "Factura cargada: subí la foto y controlala.",
  },
};

async function Invoice({
  params,
  searchParams,
}: {
  params: PageProps<"/compras/facturas/[id]">["params"];
  searchParams: PageProps<"/compras/facturas/[id]">["searchParams"];
}) {
  const [inv, query] = await Promise.all([load(params), searchParams]);
  if (!inv) notFound();
  // El saldo y los pagos: solo de una conforme o pagada, y solo para quien ve pagos (si no, la base devuelve nulo).
  const payments =
    inv.status === "released" || inv.status === "paid" ? await getInvoicePayments(inv.id) : null;
  const editable = inv.access.can_edit;
  const saved = NOTICES[first(query.aviso) ?? ""] ?? null;
  const lineChecks: Record<string, CheckRow[]> = {};
  for (const c of inv.checks) {
    if (c.lineId) (lineChecks[c.lineId] ??= []).push(c);
  }

  return (
    <>
      {saved ? (
        <Notice status={saved.status} className={editable ? "desk:hidden" : undefined}>
          {saved.text}
        </Notice>
      ) : null}
      {inv.status === "cancelled" ? (
        <Notice status="warn">Cancelada: {inv.cancelledReason}</Notice>
      ) : null}
      <InvoiceSheetProvider
        invoiceId={inv.id}
        version={inv.version}
        editable={editable}
        initial={inv.draft}
        lineChecks={lineChecks}
        notice={saved}
      >
        <Metrics inv={inv} />

        {/* Tres columnas que ocupan el alto que queda (3,5 : 8 : 4,5: las líneas necesitan ancho). Si la pantalla es más
            baja, lo que sobra se desplaza dentro de su tarjeta (ADR-0051). En el celular, una debajo de otra. */}
        <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[3.5fr_8fr_4.5fr] desk:grid-rows-[minmax(0,1fr)]">
          <Tile id="datos" title="Datos de la factura" scroll>
            <HeaderSection legalEntityTaxId={inv.legalEntityTaxId} />
            <h3 className="mt-2 text-sm font-semibold text-ink">Pie</h3>
            <FooterSection />
          </Tile>
          <Tile
            id="lineas"
            title={inv.draft.lines.length === 1 ? "1 línea" : `${inv.draft.lines.length} líneas`}
            scroll
            titleExtra={
              <InfoTip label="las líneas">
                Salen de lo recibido en las órdenes, con el precio de la lista vigente a la fecha de
                la factura. Ajustalas a lo que dice el papel. Lo que va por kilo, en kilos y a
                precio por kilo.
              </InfoTip>
            }
          >
            <LinesSection />
          </Tile>
          <Tile id="todo-junto" title="Todo junto" scroll>
            <Together inv={inv} payments={payments} />
          </Tile>
        </div>

        <SheetBar />
      </InvoiceSheetProvider>
    </>
  );
}

// ---------------------------------------------------------------------------
// Los 4 indicadores
// ---------------------------------------------------------------------------
function Metrics({ inv }: { inv: InvoiceDetail }) {
  const controlled = inv.checks.length > 0;
  const failed = (kind: InvoiceCheckKind) => inv.checks.filter((c) => c.kind === kind && !c.passed);
  const totals = inv.checks.find((c) => c.kind === "totals");
  const quantityRows = inv.checks.filter((c) => c.kind === "quantity");
  const quantityFails = failed("quantity").length;
  const price = priceDifference(inv.checks, inv.quantities);
  const noList =
    price.withoutList === 1
      ? "1 línea sin lista de precios."
      : `${price.withoutList} líneas sin lista de precios.`;
  const notControlled = "Se ve al controlar la factura.";
  const due = dueState(inv.dueOn, todayInArgentina(), inv.status);
  return (
    <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4">
      <Metric
        compact
        label="Total"
        value={formatMoney(inv.totalAmount)}
        emptyLabel="Sin datos"
        status={!totals ? "info" : totals.passed ? "ok" : "bad"}
        statusLabel={!totals ? "Sin controlar" : totals.passed ? "Cierra" : "No cierra"}
      />
      <Metric
        compact
        label="Contra lo recibido"
        value={
          !controlled || quantityRows.length === 0
            ? null
            : quantityFails === 0
              ? "Igual"
              : quantityFails === 1
                ? "1 línea"
                : `${quantityFails} líneas`
        }
        missingReason={
          !controlled
            ? notControlled
            : inv.orders.length === 0
              ? "Sin orden de compra."
              : "Sin líneas para comparar."
        }
        emptyLabel="Sin datos"
        status={quantityFails === 0 ? "ok" : "warn"}
        statusLabel={quantityFails === 0 ? "Coincide" : "Con diferencias"}
      />
      <Metric
        compact
        label="Contra la lista"
        // Si una línea no tiene lista, no hay con qué decir «igual»: falta el dato (métricas confiables).
        value={
          !controlled || price.value === null || (price.value === 0 && price.withoutList > 0)
            ? null
            : formatMoney(price.value)
        }
        missingReason={
          !controlled
            ? notControlled
            : price.withoutList > 0
              ? noList
              : "Sin lista de precios para comparar."
        }
        period={price.value !== null && price.value > 0 ? "de más" : undefined}
        emptyLabel="Sin datos"
        status={price.value === 0 && price.withoutList === 0 ? "ok" : "warn"}
        statusLabel={
          price.value === 0 && price.withoutList === 0
            ? "Igual a la lista"
            : price.withoutList > 0
              ? "Sin lista"
              : "Con diferencias"
        }
      />
      <Metric
        compact
        label="Vence el"
        value={shortDate(inv.dueOn)}
        period={inv.dueOnPrinted ? "impreso" : "por la condición de pago"}
        emptyLabel="Sin datos"
        status={due}
        statusLabel={
          due === "bad"
            ? "Vencida"
            : due === "warn"
              ? "Por vencer"
              : due === "ok"
                ? "Al día"
                : "No aplica"
        }
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Todo junto: el papel, las órdenes y su recepción, los controles y las notas
// ---------------------------------------------------------------------------
const link =
  "inline-flex min-h-touch items-center gap-1 text-sm text-primary underline-offset-4 hover:underline desk:min-h-8";

// Los controles de la factura (no de cada línea), en el orden en que se leen, y cuántas líneas no pasaron cada uno.
const HEADER_KINDS: InvoiceCheckKind[] = ["order", "legal_entity", "totals", "notes"];
const LINE_KINDS: InvoiceCheckKind[] = ["mapping", "quantity", "price"];

function Together({ inv, payments }: { inv: InvoiceDetail; payments: InvoicePayments | null }) {
  const a = inv.access;
  const isA = isClassA(inv.invoiceClass);
  const rows: { kind: InvoiceCheckKind; title: string; passed: boolean; text: string }[] = [];
  for (const kind of LINE_KINDS) {
    const all = inv.checks.filter((c) => c.kind === kind && c.lineId);
    if (all.length === 0) continue;
    const bad = all.filter((c) => !c.passed);
    rows.push({
      kind,
      title: CHECK_LABELS[kind],
      passed: bad.length === 0,
      text:
        bad.length === 0
          ? all.length === 1
            ? "La línea pasa."
            : `Las ${all.length} líneas pasan.`
          : bad.length === 1
            ? `1 línea no pasa: ${bad[0]?.explanation ?? ""}`
            : `${bad.length} líneas no pasan. Mirá el control de cada una.`,
    });
  }
  for (const kind of HEADER_KINDS) {
    const own = inv.checks.filter((x) => x.kind === kind && !x.lineId);
    for (const [i, c] of own.entries()) {
      // Si el mismo control tiene otra fila (las notas cubren, pero las sumó quien controla), esa es la doble firma.
      rows.push({
        kind,
        title: i > 0 && !c.passed ? "Doble firma" : CHECK_LABELS[kind],
        passed: c.passed,
        text: c.explanation,
      });
    }
  }
  // Una regla de la factura que no es de una línea: la doble firma (quien controla cargó o aceptó la lista).
  for (const c of inv.checks.filter((x) => LINE_KINDS.includes(x.kind) && !x.lineId)) {
    rows.push({ kind: c.kind, title: "Doble firma", passed: c.passed, text: c.explanation });
  }

  return (
    <div className="flex flex-col gap-3">
      <section aria-labelledby="fc-papel" className="flex flex-col gap-1">
        <h3 id="fc-papel" className="text-sm font-semibold text-ink">
          El papel
        </h3>
        {inv.files.length === 0 ? (
          <p className="text-sm text-ink">
            <Badge status="warn">Falta</Badge> la foto o el PDF de la factura.
          </p>
        ) : (
          <ul className="flex flex-wrap gap-x-3">
            {inv.files.map((f) => (
              <li key={f.id}>
                {f.url ? (
                  <a href={f.url} target="_blank" rel="noreferrer" className={link}>
                    <FileText aria-hidden="true" className="size-4" />
                    {f.pdf ? "Ver el PDF" : "Ver la foto"}
                    {inv.files.length > 1 ? ` (página ${f.page})` : ""}
                    <span className="sr-only"> (se abre en otra pestaña)</span>
                  </a>
                ) : (
                  <span className="text-sm text-ink-muted">Página {f.page}: no se pudo abrir</span>
                )}
              </li>
            ))}
          </ul>
        )}
        {a.can_edit ? (
          <InvoiceFileUpload
            invoiceId={inv.id}
            sourceTable="invoices"
            sourceId={inv.id}
            label={inv.files.length === 0 ? "Subir la foto o el PDF" : "Cambiar la foto"}
            className="hidden desk:flex"
          />
        ) : null}
      </section>

      <section aria-labelledby="fc-ordenes" className="flex flex-col gap-1">
        <h3 id="fc-ordenes" className="text-sm font-semibold text-ink">
          Orden y recepción
        </h3>
        {inv.orders.length === 0 ? (
          <p className="text-sm text-ink">Sin orden de compra: la da por conforme otra persona.</p>
        ) : (
          <ul className="flex flex-col">
            {inv.orders.map((o) => (
              <li key={o.id}>
                <Link href={`/compras/ordenes/${o.id}?seccion=recepcion`} className={link}>
                  {o.number} · ver lo recibido y sus fotos
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section aria-labelledby="fc-controles" className="flex flex-col gap-1">
        <h3 id="fc-controles" className="text-sm font-semibold text-ink">
          Controles
        </h3>
        {rows.length === 0 ? (
          <p className="text-sm text-ink">
            {inv.status === "loaded"
              ? "Sin controlar desde el último cambio. Apretá «Controlar»."
              : "Sin controles."}
          </p>
        ) : (
          <ul className="flex flex-col gap-1" aria-label="Resultado del último control">
            {rows.map((r, i) => (
              <li key={`${r.kind}-${i}`} className="flex items-start gap-2 text-sm text-ink">
                <Badge status={r.passed ? "ok" : "bad"} className="shrink-0">
                  {r.passed ? (
                    <Check aria-hidden="true" className="size-4" />
                  ) : (
                    <X aria-hidden="true" className="size-4" />
                  )}
                  {r.passed ? "Pasa" : "No pasa"}
                </Badge>
                <span>
                  <span className="font-medium">{r.title}.</span> {r.text}
                </span>
              </li>
            ))}
          </ul>
        )}
        {inv.checks.length > 0 && inv.status !== "loaded" ? (
          <p className="text-xs text-ink-muted">
            Controlada el {inv.checkedAt ? formatDateTime(inv.checkedAt) : "—"}.
          </p>
        ) : null}
        {a.approve_blocked ? <Notice status="info">{a.approve_blocked}</Notice> : null}
      </section>

      <section aria-labelledby="fc-notas" className="flex flex-col gap-1">
        <div className="flex items-center justify-between gap-2">
          <h3 id="fc-notas" className="text-sm font-semibold text-ink">
            Notas de crédito y débito
          </h3>
          {a.can_add_note ? (
            <ActionModal
              label="Agregar nota"
              size="sm"
              title="Nota de crédito, débito o descuento"
              description="Cuenta para el control recién con su foto. Una conforme se corrige así."
              className="hidden desk:inline-flex"
            >
              <NoteForm invoiceId={inv.id} invoiceIsA={isA} />
            </ActionModal>
          ) : null}
        </div>
        <ShortList
          label="Notas de crédito y débito"
          items={inv.notes}
          limit={4}
          itemKey={(n) => n.id}
          empty={<p className="text-sm text-ink-muted">Sin notas.</p>}
          renderItem={(n) => (
            <div className="flex flex-col gap-1 py-1 text-sm text-ink">
              <span className="flex flex-wrap items-center gap-2">
                <span className="font-medium">
                  {NOTE_KINDS.find((k) => k.value === n.kind)?.label}
                  {n.number ? ` ${n.number}` : ""}
                </span>
                <span className="tabular-nums">{formatMoney(n.netAmount)}</span>
                <span className="text-ink-muted tabular-nums">{shortDate(n.issuedOn)}</span>
                {n.files.length > 0 ? (
                  <Badge status="ok">Con foto</Badge>
                ) : (
                  <Badge status="warn">Sin foto</Badge>
                )}
              </span>
              {n.files[0]?.url ? (
                <a href={n.files[0].url} target="_blank" rel="noreferrer" className={link}>
                  Ver la foto de la nota<span className="sr-only"> (se abre en otra pestaña)</span>
                </a>
              ) : null}
              {a.can_add_note && n.files.length === 0 ? (
                <InvoiceFileUpload
                  invoiceId={inv.id}
                  sourceTable="credit_debit_notes"
                  sourceId={n.id}
                  label="Subir la foto de la nota"
                  className="hidden desk:flex"
                />
              ) : null}
            </div>
          )}
        />
      </section>

      {payments ? (
        <section aria-labelledby="fc-pagos" className="flex flex-col gap-1">
          <div className="flex items-center justify-between gap-2">
            <h3 id="fc-pagos" className="text-sm font-semibold text-ink">
              Saldo y pagos
            </h3>
            <Link
              href={`/compras/pagos?proveedor=${inv.supplierId}&estado=${payments.balance > 0.005 ? (inv.dueOn < todayInArgentina() ? "vencidas" : "") : "pagadas"}`.replace(
                /&estado=$/,
                "",
              )}
              className={link}
            >
              Ver los pagos del proveedor
            </Link>
          </div>
          <p className="flex flex-wrap items-center gap-2 text-sm text-ink tabular-nums">
            Saldo {formatMoney(payments.balance)}
            {payments.balance > 0.005 ? (
              inv.dueOn < todayInArgentina() ? (
                <Badge status="bad">Vencida</Badge>
              ) : (
                <Badge status={payments.payments.length > 0 ? "warn" : "info"}>
                  {payments.payments.length > 0 ? "Pagada en parte" : "Sin pagos"}
                </Badge>
              )
            ) : (
              <Badge status="ok">Pagada</Badge>
            )}
          </p>
          {payments.payments.length > 0 ? (
            <ShortList
              label="Pagos de la factura"
              items={payments.payments}
              limit={4}
              itemKey={(p) => p.payment_id}
              empty={null}
              more={
                <p className="text-sm text-ink">
                  Y {payments.payments.length - 4} pagos más: están en «Ver los pagos del
                  proveedor».
                </p>
              }
              renderItem={(p) => (
                <span className="flex flex-wrap items-center gap-2 py-1 text-sm text-ink tabular-nums">
                  <span>{shortDate(p.paid_on)}</span>
                  <span className="font-medium">{METHOD_LABELS[p.method]}</span>
                  {p.reference ? <span>{p.reference}</span> : null}
                  <span>{formatMoney(p.allocated)}</span>
                  {p.payment_amount - p.allocated > 0.005 ? (
                    <span>de un pago de {formatMoney(p.payment_amount)}</span>
                  ) : null}
                </span>
              )}
            />
          ) : null}
        </section>
      ) : null}

      <p className="text-xs text-ink-muted">
        La cargó {a.loaded_by_name}.
        {a.approved_by_name
          ? ` La dio por conforme ${a.approved_by_name}${inv.approvedAt ? ` el ${formatDateTime(inv.approvedAt)}` : ""}.`
          : ""}
      </p>
    </div>
  );
}
