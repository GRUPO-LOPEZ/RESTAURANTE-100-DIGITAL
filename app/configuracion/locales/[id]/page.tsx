import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { setPlaceOpenAction } from "@/app/configuracion/structure-actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import {
  AreasSection,
  LegalSection,
  LocationSection,
  PlaceSection,
  PlaceSheetProvider,
  SheetBar,
  SmallLink,
} from "@/components/place-sheet/sheet-editor";
import { Badge } from "@/components/ui/badge";
import { FormTextarea } from "@/components/ui/form";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { Tile } from "@/components/ui/tile";
import { requireMenu } from "@/lib/auth/session";
import { UUID, first, formatDate } from "@/lib/data";
import { formatTaxId, getLegalEntities, SITE_TYPE_LABELS } from "@/lib/org";
import {
  VAT_SHORT_LABELS,
  getPlaceSheet,
  getProvinces,
  placeState,
  todayAr,
  type PlaceSheet,
} from "@/lib/org-panel";
import { PLACE_REQUIRED, missingLabel, type RestaurantDraft } from "@/lib/org-sheet";
import { DOCUMENT_STATUS_LABEL, documentStatus } from "@/lib/legal-entity";
import { FocusTarget } from "@/components/focus-target";

// Ficha del local en una pantalla (Tanda 1 de Soy, ADR-0061), con el patrón de las pantallas de carga sin scroll
// (ADR-0046): una línea de encabezado, 4 indicadores y tres columnas de tarjetas que se editan donde se ven; todo se
// guarda junto con la barra de abajo, con motivo. Cerrar y reabrir van arriba, aparte. En el celular, de consulta.
export default function LocalPage({
  params,
  searchParams,
}: PageProps<"/configuracion/locales/[id]">) {
  return (
    <AppShell
      title="Local"
      fill
      heading={
        <Suspense fallback="Local">
          <PlaceName params={params} />
        </Suspense>
      }
      back={
        <BackLink href="/configuracion" label="Volver al Panel de control">
          Panel de control
        </BackLink>
      }
      meta={
        <Suspense fallback={null}>
          <Meta params={params} />
        </Suspense>
      }
      actions={
        <Suspense fallback={null}>
          <OpenAction params={params} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Place params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const placeById = cache(getPlaceSheet);

async function load(params: PageProps<"/configuracion/locales/[id]">["params"]) {
  await requireMenu("panel");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  return placeById(id);
}

async function PlaceName({
  params,
}: {
  params: PageProps<"/configuracion/locales/[id]">["params"];
}) {
  const p = await load(params);
  return p ? p.name : "Local";
}

// La línea del nombre: código · marca · tipo, y el estado con palabra.
async function Meta({ params }: { params: PageProps<"/configuracion/locales/[id]">["params"] }) {
  const p = await load(params);
  if (!p) return null;
  const state = placeState(p);
  const parts = [p.code, p.brand.name, SITE_TYPE_LABELS[p.siteType]].filter(Boolean);
  return (
    <>
      <span className="text-sm text-ink-muted tabular-nums">{parts.join(" · ")}</span>
      <Badge status={state.status}>{state.label}</Badge>
    </>
  );
}

// Cerrar (o reabrir) el local: un botón a la derecha del nombre, con motivo. Lo decide la marca (org.manage).
async function OpenAction({
  params,
}: {
  params: PageProps<"/configuracion/locales/[id]">["params"];
}) {
  const p = await load(params);
  if (!p || !p.canEditBrandLevel) return null;
  const open = p.status === "active";
  const label = open ? "Cerrar el local" : "Reabrir el local";
  return (
    <div className="hidden desk:block">
      <ActionModal
        label={label}
        icon="none"
        title={label}
        description={
          open
            ? "No se borra nada: deja de operar (y de dar permisos) y su historia queda."
            : "Vuelve a operar. Si estaba abierto, necesita sus 7 datos obligatorios."
        }
      >
        <ActionForm
          action={setPlaceOpenAction}
          schema="reason"
          submitLabel={label}
          variant={open ? "destructive" : "default"}
        >
          <input type="hidden" name="placeId" value={p.id} />
          <input type="hidden" name="action" value={open ? "close" : "reopen"} />
          <FormTextarea
            id="local-motivo-abrir"
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

function draftOf(p: PlaceSheet): RestaurantDraft {
  return {
    fields: {
      zone: p.zone ?? "",
      opened_on: p.openedOn ?? "",
      address: p.address ?? "",
      locality: p.locality ?? "",
      province: p.province ?? "",
      postal_code: p.postalCode ?? "",
      phone: p.phone ?? "",
    },
    geo: {
      status: p.geoStatus ?? "",
      latitude: p.latitude === null ? "" : String(p.latitude),
      longitude: p.longitude === null ? "" : String(p.longitude),
      label: p.geoLabel ?? "",
    },
    siteType: p.siteType,
    state: p.opening ? "opening" : "open",
    legalEntityId: p.legalEntityId ?? "",
    legalFrom: p.legalFrom ?? "",
    areas: p.areas.map((a) => ({ key: a.id, id: a.id, name: a.name, active: a.active })),
  };
}

const NOTICES: Record<string, { status: "ok" | "info"; text: string }> = {
  guardado: { status: "ok", text: "Cambios guardados." },
  creado: { status: "ok", text: "Local creado en apertura. Completá su ficha y guardá." },
};

async function Place({
  params,
  searchParams,
}: {
  params: PageProps<"/configuracion/locales/[id]">["params"];
  searchParams: PageProps<"/configuracion/locales/[id]">["searchParams"];
}) {
  const [p, query] = await Promise.all([load(params), searchParams]);
  if (!p) notFound();
  const [provinces, entities] = await Promise.all([getProvinces(), getLegalEntities()]);
  const editable = p.canEdit && p.stamp !== null;
  const saved = NOTICES[first(query.aviso) ?? ""] ?? null;
  // La razón social del local siempre está en la lista, aunque la sesión no vea las demás.
  const legalEntities = entities.map((e) => ({
    id: e.id,
    name: e.name,
    taxId: formatTaxId(e.taxId),
    vatLabel: VAT_SHORT_LABELS[e.vatCondition],
  }));
  if (p.legalEntity && !legalEntities.some((e) => e.id === p.legalEntity?.id))
    legalEntities.push({
      id: p.legalEntity.id,
      name: p.legalEntity.name,
      taxId: formatTaxId(p.legalEntity.taxId),
      vatLabel: VAT_SHORT_LABELS[p.legalEntity.vatCondition],
    });
  const completed = PLACE_REQUIRED - p.missing.length;
  const docStatus = documentStatus(p.document.issuedOn, todayAr());
  return (
    <>
      {saved ? (
        <Notice status={saved.status} className={editable ? "desk:hidden" : undefined}>
          {saved.text}
        </Notice>
      ) : null}
      <PlaceSheetProvider
        placeId={p.id}
        stamp={p.stamp}
        editable={editable}
        initial={draftOf(p)}
        options={{
          brandShortName: p.brand.shortName,
          provinces,
          legalEntities,
          canEditBrandLevel: p.canEditBrandLevel,
          canEditGroupLevel: p.canEditGroupLevel,
          closed: p.status !== "active",
        }}
        notice={saved}
      >
        <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4">
          <Metric
            compact
            label="Personas que trabajan acá"
            value={p.people}
            missingReason="Las ven quienes administran usuarios."
            emptyLabel="Sin personas"
            status={p.people === null ? "none" : p.people > 0 ? "ok" : "none"}
            statusLabel={p.people && p.people > 0 ? "Activas" : "Sin personas"}
            action={
              p.people !== null ? (
                <SmallLink href={`/usuarios/lista?local=${p.id}`}>Ver quiénes</SmallLink>
              ) : undefined
            }
          />
          <Metric
            compact
            label="Recetas asignadas"
            value={p.recipes}
            missingReason="Las ven quienes ven el recetario."
            emptyLabel="Sin recetas"
            status={p.recipes === null ? "none" : p.recipes > 0 ? "ok" : "none"}
            statusLabel={p.recipes && p.recipes > 0 ? "Asignadas" : "Sin recetas"}
            action={
              p.recipes ? (
                <SmallLink href={`/recetas?local=${p.id}`}>Ver cuáles</SmallLink>
              ) : undefined
            }
          />
          <Metric
            compact
            label="Constancia de la razón social"
            value={p.document.issuedOn ? formatDate(p.document.issuedOn) : null}
            missingReason={
              !p.legalEntity
                ? "Sin razón social: elegila en su tarjeta."
                : !p.document.visible
                  ? "La ven quienes administran el grupo o ven precios del local."
                  : "Sin constancia: subila en la ficha de la razón social."
            }
            emptyLabel="Sin constancia"
            status={docStatus === "current" ? "ok" : docStatus === "stale" ? "warn" : "none"}
            statusLabel={DOCUMENT_STATUS_LABEL[docStatus]}
          />
          <Metric
            compact
            label="Datos obligatorios"
            value={completed}
            unit={`de ${PLACE_REQUIRED}`}
            emptyLabel="Sin datos"
            status={p.missing.length === 0 ? "ok" : "warn"}
            statusLabel={p.missing.length === 0 ? "Completos" : missingLabel(p.missing)}
          />
        </div>

        {/* Tres columnas que ocupan el alto que queda. La página no se mueve: si una pantalla es más baja, lo que
            sobra se desplaza dentro de su tarjeta. Cada eslabón lleva min-h-0 y base 0px (design.md). */}
        <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-3 desk:grid-rows-[minmax(0,1fr)]">
          <Tile id="local" title="El local" scroll>
            <PlaceSection brandName={p.brand.name} code={p.code} />
          </Tile>
          <Tile id="ubicacion" title="Ubicación y contacto" scroll>
            <LocationSection placeName={p.name} />
          </Tile>
          <div className="flex min-h-0 min-w-0 flex-col gap-4">
            <Tile
              id="razon-social"
              title="Razón social"
              scroll
              aside={
                p.legalEntity ? (
                  <SmallLink href={`/configuracion/razones-sociales/${p.legalEntity.id}`}>
                    Abrir ficha
                  </SmallLink>
                ) : undefined
              }
            >
              <LegalSection todayIso={todayAr()} />
            </Tile>
            <Tile
              id="areas"
              title="Áreas"
              scroll
              className="desk:flex-[1_1_0px]"
              aside={`${p.areas.filter((a) => a.active).length} activas`}
            >
              <AreasSection />
            </Tile>
          </div>
        </div>

        <SheetBar />
      </PlaceSheetProvider>
      <FocusTarget />
    </>
  );
}
