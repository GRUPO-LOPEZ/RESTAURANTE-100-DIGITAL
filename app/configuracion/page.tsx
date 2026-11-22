import Link from "next/link";
import { Plus } from "lucide-react";
import { Suspense } from "react";

import { createLegalEntityAction } from "@/app/configuracion/structure-actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { CreateModal } from "@/components/create-modal";
import { FocusTarget } from "@/components/focus-target";
import { buttonVariants } from "@/components/ui/button";
import { NewPlaceForm } from "@/components/new-place-form";
import { OrgMap, type MapPoint } from "@/components/org-map";
import { BrandPanelButton, MissingPanelButton, NewBrandRow } from "@/components/structure-panel";
import { Badge } from "@/components/ui/badge";
import { FormInput, FormTextarea } from "@/components/ui/form";
import { Metric } from "@/components/ui/metric";
import { SegmentedField } from "@/components/ui/segmented-field";
import { EmptyState } from "@/components/ui/states";
import { Tile } from "@/components/ui/tile";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { first } from "@/lib/data";
import { documentStatus } from "@/lib/legal-entity";
import { SITE_TYPE_LABELS, formatTaxId, getOrgPermissions } from "@/lib/org";
import {
  VAT_SHORT_LABELS,
  getStructurePanel,
  placeState,
  todayAr,
  type PlaceRow,
} from "@/lib/org-panel";
import { missingLabel } from "@/lib/org-sheet";

// Panel de control en una pantalla (Tanda 1 de Soy, ADR-0061): «¿Cómo está armado el grupo?». Tipo A (design.md): 4
// indicadores, las marcas con sus locales a la izquierda y el mapa y las razones sociales a la derecha; lo demás que se
// administra, en una línea abajo. Cada fila abre su ficha. Lo que se muestra para editar sale de los permisos de cada
// persona; la base vuelve a controlar cada cambio.
export default function PanelPage({ searchParams }: PageProps<"/configuracion">) {
  return (
    <AppShell
      title="Panel de control"
      heading="¿Cómo está armado el grupo?"
      meta={<span className="text-sm text-ink-muted">marcas, locales y razones sociales</span>}
      fill
      actions={
        <Suspense fallback={null}>
          <Actions />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Panel searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const link =
  "inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8";

async function Actions() {
  await requireMenu("panel");
  const [menus, panel, perms] = await Promise.all([
    getMenus(),
    getStructurePanel(),
    getOrgPermissions(),
  ]);
  if (!menus.orgManage) return null;
  const brands = panel.brands.filter(
    (b) =>
      b.status === "active" && (perms.groups.includes(b.groupId) || perms.brands.includes(b.id)),
  );
  const groupAdmin = panel.groupId !== null && perms.groups.includes(panel.groupId);
  return (
    <div className="hidden items-center gap-2 desk:flex">
      {groupAdmin ? (
        <a href="#marca-nueva-nombre" className={buttonVariants({ variant: "outline" })}>
          <Plus aria-hidden="true" />
          Nueva marca
        </a>
      ) : null}
      {brands.length > 0 ? (
        <CreateModal
          href="/configuracion/locales/nuevo"
          label="Nuevo local"
          title="Nuevo local"
          description="Después completás el resto en su ficha."
        >
          <NewPlaceForm brands={brands.map((b) => ({ id: b.id, name: b.name }))} />
        </CreateModal>
      ) : null}
    </div>
  );
}

// «4 restaurantes y 1 cocina central»; sin cocinas, solo los restaurantes.
function placesLabel(restaurants: number, others: number): string {
  const r = restaurants === 1 ? "1 restaurante" : `${restaurants} restaurantes`;
  if (others === 0) return r;
  return `${r} y ${others === 1 ? "1 cocina o producción" : `${others} cocinas o producción`}`;
}

function PlaceLine({ place }: { place: PlaceRow }) {
  const state = placeState(place);
  return (
    <li className="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-line py-2 pl-4 text-sm">
      <Badge status="neutral" className="tabular-nums">
        {place.code ?? "Sin código"}
      </Badge>
      <Link href={`/configuracion/locales/${place.id}`} className={`${link} font-medium`}>
        {place.name}
      </Link>
      <span className="hidden min-w-0 flex-1 truncate text-ink-muted desk:inline">
        {[place.address, place.locality].filter(Boolean).join(", ") || "Sin dirección"}
      </span>
      <span className="hidden text-ink-muted desk:inline">{SITE_TYPE_LABELS[place.siteType]}</span>
      <Badge status={state.status}>{state.label}</Badge>
      {place.status === "active" && place.missing.length > 0 ? (
        <Badge status="warn">{missingLabel(place.missing)}</Badge>
      ) : null}
    </li>
  );
}

async function Panel({
  searchParams,
}: {
  searchParams: PageProps<"/configuracion">["searchParams"];
}) {
  await requireMenu("panel");
  const [menus, panel, perms, query] = await Promise.all([
    getMenus(),
    getStructurePanel(),
    getOrgPermissions(),
    searchParams,
  ]);
  const openBrand = first(query.marca);
  const groupAdmin = panel.groupId !== null && perms.groups.includes(panel.groupId);
  const places = panel.brands.flatMap((b) => b.places);
  const operating = places.filter((p) => p.status === "active");
  const restaurants = operating.filter((p) => p.siteType === "restaurant").length;
  const kitchens = operating.length - restaurants;
  const opening = operating.filter((p) => p.opening).length;
  const incomplete = operating.filter((p) => p.missing.length > 0);
  const activeBrands = panel.brands.filter((b) => b.status === "active");
  const today = todayAr();
  const docs = panel.legalEntities.map((e) => documentStatus(e.documentIssuedOn, today));
  const stale = docs.filter((d) => d === "stale").length;
  const missingDocs = docs.filter((d) => d === "missing").length;
  const points: MapPoint[] = operating
    .filter((p) => p.latitude !== null && p.longitude !== null)
    .map((p) => ({
      id: p.id,
      name:
        p.siteType === "restaurant"
          ? p.name
          : `${p.name} (${SITE_TYPE_LABELS[p.siteType].toLowerCase()})`,
      latitude: p.latitude as number,
      longitude: p.longitude as number,
      kind: p.siteType === "restaurant" ? "restaurant" : "other",
    }));
  const unplaced = operating.length - points.length;

  if (panel.brands.length === 0 && !groupAdmin)
    return <EmptyState title="Todavía no hay marcas cargadas en el grupo." />;

  return (
    <>
      <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4">
        <Metric
          compact
          label="Marcas"
          value={activeBrands.length}
          total={panel.brands.length}
          emptyLabel="Sin marcas"
          status={activeBrands.length === panel.brands.length ? "ok" : "info"}
          statusLabel={
            activeBrands.length === panel.brands.length
              ? "Todas activas"
              : `${panel.brands.length - activeBrands.length} inactivas`
          }
        />
        <Metric
          compact
          label="Locales"
          value={operating.length}
          total={places.length}
          period={placesLabel(restaurants, kitchens)}
          emptyLabel="Sin locales"
          status={opening === 0 ? "ok" : "info"}
          statusLabel={opening === 0 ? "Todos abiertos" : `${opening} en apertura`}
        />
        <Metric
          compact
          label="Razones sociales"
          value={panel.legalEntities.length}
          total={panel.legalEntities.length}
          emptyLabel="Sin razones sociales"
          status={stale > 0 || missingDocs > 0 ? "warn" : "ok"}
          statusLabel={
            stale > 0
              ? stale === 1
                ? "1 constancia vencida"
                : `${stale} constancias vencidas`
              : missingDocs > 0
                ? missingDocs === 1
                  ? "1 sin constancia"
                  : `${missingDocs} sin constancia`
                : "Constancias al día"
          }
        />
        <Metric
          compact
          label="Datos que faltan"
          value={incomplete.length}
          total={operating.length}
          unit={incomplete.length === 1 ? "local" : "locales"}
          period={
            incomplete.length === 1 && incomplete[0]
              ? `${incomplete[0].name}: ${incomplete[0].missing.join(", ")}`
              : undefined
          }
          emptyLabel="Sin locales"
          status={incomplete.length === 0 ? "ok" : "warn"}
          statusLabel={incomplete.length === 0 ? "Completos" : "Atención"}
          action={
            incomplete.length > 0 ? (
              <MissingPanelButton
                places={incomplete.map((p) => ({ id: p.id, name: p.name, missing: p.missing }))}
              />
            ) : undefined
          }
        />
      </div>

      {/* Dos columnas (1,25 : 1) que ocupan el alto que queda; lo que no entra se desplaza dentro de su tarjeta. */}
      <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[5fr_4fr] desk:grid-rows-[minmax(0,1fr)]">
        <Tile
          id="marcas"
          title="Marcas y locales"
          aside="clic en un local para abrir su ficha"
          scroll
        >
          <ul className="flex flex-col gap-3" aria-label="Marcas y locales">
            {panel.brands.map((b) => {
              const canEdit = perms.groups.includes(b.groupId) || perms.brands.includes(b.id);
              return (
                <li key={b.id} className="flex flex-col">
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1 py-1">
                    <Badge status="info" className="tabular-nums">
                      {b.code}
                    </Badge>
                    <span className="text-base font-semibold text-ink">{b.name}</span>
                    <span className="text-sm text-ink-muted">
                      {b.places.length === 1 ? "1 local" : `${b.places.length} locales`}
                    </span>
                    <Badge status={b.status === "active" ? "ok" : "none"}>
                      {b.status === "active" ? "Activa" : "Inactiva"}
                    </Badge>
                    {canEdit ? (
                      <span className="ml-auto hidden desk:inline">
                        <BrandPanelButton
                          brand={{
                            id: b.id,
                            name: b.name,
                            shortName: b.shortName,
                            code: b.code,
                            status: b.status,
                          }}
                          places={b.places.map((p) => ({
                            id: p.id,
                            code: p.code,
                            name: p.name,
                            state: placeState(p).label,
                          }))}
                          canEditStatus={perms.groups.includes(b.groupId)}
                          startOpen={openBrand === b.id}
                        />
                      </span>
                    ) : null}
                  </div>
                  {b.places.length > 0 ? (
                    <ul aria-label={`Locales de ${b.name}`}>
                      {b.places.map((p) => (
                        <PlaceLine key={p.id} place={p} />
                      ))}
                    </ul>
                  ) : (
                    <p className="pl-4 text-sm text-ink-muted">Todavía no tiene locales.</p>
                  )}
                </li>
              );
            })}
          </ul>
          {groupAdmin && panel.groupId ? (
            <div className="hidden desk:block">
              <NewBrandRow
                groupId={panel.groupId}
                nextNumber={Math.max(0, ...panel.brands.map((b) => b.number)) + 1}
              />
            </div>
          ) : null}
        </Tile>

        <div className="flex min-h-0 min-w-0 flex-col gap-4">
          <Tile
            id="mapa"
            title="Dónde están"
            aside={
              unplaced > 0
                ? `${unplaced} sin ubicar en el mapa`
                : "sale de la dirección de cada local"
            }
            className="desk:min-h-0 desk:flex-[1_1_0px]"
          >
            <OrgMap
              points={points}
              label={`Mapa con ${points.length === 1 ? "1 local" : `${points.length} locales`}`}
              className="min-h-56 desk:min-h-0 desk:flex-[1_1_0px]"
            />
          </Tile>
          <Tile
            id="razones-sociales"
            title="Razones sociales"
            scroll
            className="desk:max-h-[45%]"
            aside={
              groupAdmin && panel.groupId ? (
                <span className="hidden desk:inline">
                  <ActionModal
                    label="Nueva razón social"
                    variant="link"
                    size="sm"
                    title="Nueva razón social"
                    description="Después completás los datos de la constancia de ARCA en su ficha."
                  >
                    <ActionForm
                      action={createLegalEntityAction}
                      schema="legalEntity"
                      submitLabel="Crear y completar la ficha"
                    >
                      <input type="hidden" name="groupId" value={panel.groupId} />
                      <FormInput
                        id="razon-nueva-nombre"
                        name="name"
                        label="Razón social"
                        required
                        maxLength={200}
                      />
                      <FormInput
                        id="razon-nueva-cuit"
                        name="tax_id"
                        label="CUIT"
                        required
                        maxLength={13}
                        inputMode="numeric"
                        hint="Con o sin guiones. Se controla el dígito verificador."
                      />
                      <SegmentedField
                        id="razon-nueva-iva"
                        name="vat_condition"
                        label="Condición frente al IVA"
                        options={[
                          { value: "registered", label: "Resp. inscripto" },
                          { value: "monotax", label: "Monotributo" },
                          { value: "exempt", label: "Exento" },
                        ]}
                      />
                      <FormTextarea
                        id="razon-nueva-motivo"
                        name="reason"
                        label="Motivo"
                        hint="Queda en el historial."
                        required
                        maxLength={500}
                      />
                    </ActionForm>
                  </ActionModal>
                </span>
              ) : undefined
            }
          >
            {panel.legalEntities.length === 0 ? (
              <p className="text-sm text-ink-muted">
                {menus.orgManageGroup
                  ? "Todavía no hay razones sociales."
                  : "Las ven quienes administran el grupo o ven precios."}
              </p>
            ) : (
              <ul className="flex flex-col" aria-label="Razones sociales">
                {panel.legalEntities.map((e) => (
                  <li
                    key={e.id}
                    className="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-line py-2 text-sm first:border-t-0"
                  >
                    <Link
                      href={`/configuracion/razones-sociales/${e.id}`}
                      className={`${link} font-medium`}
                    >
                      {e.name}
                    </Link>
                    <span className="text-ink-muted tabular-nums">{formatTaxId(e.taxId)}</span>
                    <span className="text-ink-muted">
                      {e.places === 1 ? "1 local" : `${e.places} locales`}
                    </span>
                    <Badge status="info" className="ml-auto">
                      {VAT_SHORT_LABELS[e.vatCondition]}
                    </Badge>
                  </li>
                ))}
              </ul>
            )}
          </Tile>
        </div>
      </div>

      <nav
        aria-label="También en el Panel"
        className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm"
      >
        <span className="text-ink-muted">También en el Panel:</span>
        {menus.pricesConfigure ? (
          <Link href="/configuracion/precios" className={link}>
            Configuración de precios
          </Link>
        ) : null}
        {menus.users ? (
          <Link href="/usuarios" className={link}>
            Usuarios
          </Link>
        ) : null}
        {menus.roles ? (
          <Link href="/roles" className={link}>
            Roles y permisos
          </Link>
        ) : null}
        {menus.catalogSettings ? (
          <Link href="/materias-primas/configuracion" className={link}>
            Configuración del catálogo
          </Link>
        ) : null}
      </nav>
      <FocusTarget />
    </>
  );
}
