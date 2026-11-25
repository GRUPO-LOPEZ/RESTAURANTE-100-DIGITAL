import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { NewRubro, RubroStatusDialog } from "@/components/rubro-card";
import { SegmentedLinks } from "@/components/rubro-filter";
import { RubroPanel } from "@/components/rubro-panel";
import { RubroSheetCard } from "@/components/rubro-sheet";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { cleanSearch } from "@/lib/catalog";
import { resolvePricePlace } from "@/lib/costs";
import { first } from "@/lib/data";
import { listHref, plainParams } from "@/lib/list-params";
import { missingState } from "@/lib/metrics";
import { getRubroPrices, getRubroSheet, getRubros } from "@/lib/recipes";
import {
  RUBRO_CLASSES,
  arrangeRubros,
  rubroClassFromTab,
  summarize,
  type RubroSheet,
  type RubroSort,
} from "@/lib/rubros";

const PATH = "/rubros";

// Rubros (ADR-0038; ficha en ADR-0066, pedido de Soy): la tabla maestra del recetario en una pantalla. La clase como
// botones, los rubros en un panel fijo y, a la derecha, la ficha del elegido. Dar de alta, editar, dar de baja y
// reactivar pasan por funciones de la base que controlan el permiso.
export default function RubrosPage({ searchParams }: PageProps<"/rubros">) {
  return (
    <AppShell
      title="Rubros"
      fill
      meta={
        <span className="text-sm text-ink-muted">
          Cómo se agrupan las materias primas y las recetas
        </span>
      }
      actions={
        <Suspense fallback={null}>
          <Actions searchParams={searchParams} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Rubros searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

type Search = { searchParams: PageProps<"/rubros">["searchParams"] };

// Las clases que la sesión ve: los rubros de compra, con el catálogo; los demás, con las recetas. Si la pedida no está,
// la primera que sí.
function visibleClasses(menus: Awaited<ReturnType<typeof getMenus>>) {
  return RUBRO_CLASSES.filter((c) => (c.rubroClass === "purchase" ? menus.catalog : menus.recipes));
}
function classFrom(tab: string | undefined, menus: Awaited<ReturnType<typeof getMenus>>) {
  const classes = visibleClasses(menus);
  return classes.find((c) => c.tab === tab) ?? classes[0] ?? rubroClassFromTab(tab);
}

async function Actions({ searchParams }: Search) {
  const [raw, menus, data] = await Promise.all([searchParams, getMenus(), getRubros()]);
  const current = classFrom(first(raw.clase), menus);
  const canManage = current.rubroClass === "purchase" ? menus.rubrosPurchase : menus.rubrosRecipes;
  if (!canManage || !data) return null;
  return (
    <NewRubro
      groupId={data.groupId}
      rubroClass={current.rubroClass}
      classLabel={current.label}
      prefix={current.prefix}
    />
  );
}

async function Rubros({ searchParams }: Search) {
  const session = await requireMenu("rubros");
  const raw = await searchParams;
  const params = plainParams(raw);
  const query = cleanSearch(first(raw.q)) ?? "";
  const sort: RubroSort = first(raw.orden) === "az" ? "az" : "cantidad";
  const [data, menus] = await Promise.all([getRubros(), getMenus()]);
  const current = classFrom(first(raw.clase), menus);

  if (!data) {
    return (
      <EmptyState title="Todavía no hay rubros para mostrar.">
        Los rubros se cargan con el grupo. Si esperabas verlos, avisale a quien administra el
        sistema.
      </EmptyState>
    );
  }

  // La interfaz oculta lo que no se puede hacer; la base vuelve a controlarlo.
  const canManage = current.rubroClass === "purchase" ? menus.rubrosPurchase : menus.rubrosRecipes;
  const ofClass = data.rubros.filter((r) => r.rubroClass === current.rubroClass);
  const summary = summarize(ofClass);
  const shown = arrangeRubros(ofClass, query, sort);
  // El elegido, aunque la búsqueda no lo muestre: buscar u ordenar no cambia la ficha abierta. Sin elegido (u otra
  // clase), el primero de siempre, que no depende del orden ni de la búsqueda.
  const selected =
    ofClass.find((r) => r.id === first(raw.rubro)) ?? arrangeRubros(ofClass, "", "cantidad")[0];
  const [sheet, place] = await Promise.all([
    selected ? getRubroSheet(current.rubroClass, selected.id) : null,
    menus.pricesView && current.rubroClass === "purchase"
      ? resolvePricePlace(session.user_id)
      : null,
  ]);
  const prices = sheet && place?.place ? await getRubroPrices(sheet.id, place.place.id) : null;
  const targets = ofClass
    .filter((r) => r.isActive && r.id !== selected?.id)
    .map((r) => ({ id: r.id, label: `${r.code} · ${r.name}` }))
    .sort((a, b) => a.label.localeCompare(b.label, "es"));
  const words =
    current.rubroClass === "purchase"
      ? { one: "materia prima", many: "materias primas" }
      : { one: current.one, many: current.many };

  return (
    <>
      <div className="flex flex-col gap-3 desk:flex-row desk:items-end desk:justify-between">
        <div className="flex flex-col gap-2">
          <SegmentedLinks
            label="Clases de rubro"
            unit="rubros"
            items={visibleClasses(menus).map((c) => ({
              href: listHref(PATH, params, {
                clase: c.tab === "compra" ? undefined : c.tab,
                rubro: undefined,
              }),
              label: c.short,
              count: data.rubros.filter((r) => r.rubroClass === c.rubroClass).length,
              current: c.rubroClass === current.rubroClass,
            }))}
          />
          <p
            aria-label={`Resumen de ${current.label.toLowerCase()}`}
            role="group"
            className="hidden text-sm text-ink-muted tabular-nums desk:block"
          >
            {current.short}: {summary.active} activos · {summary.inactive} dados de baja ·{" "}
            {summary.unused} sin uso
          </p>
        </div>
        <FilterBar label="Buscar y ordenar rubros">
          <Field id="rub-buscar" label="Buscar" className="w-full desk:w-56">
            <Input type="search" name="q" defaultValue={query} placeholder="Nombre o código" />
          </Field>
          <Field id="rub-orden" label="Ordenar" className="w-full desk:w-40">
            <Select name="orden" defaultValue={sort === "az" ? "az" : ""}>
              <option value="">Por cantidad</option>
              <option value="az">De la A a la Z</option>
            </Select>
          </Field>
        </FilterBar>
      </div>

      {summary.mismatched > 0 ? (
        <Notice status="warn">
          {summary.mismatched === 1
            ? "1 receta cargada antes de los rubros está en un rubro de la otra clase"
            : `${summary.mismatched} recetas cargadas antes de los rubros están en un rubro de la otra clase`}{" "}
          (un plato va en un rubro de menú; una preparación, en uno de sub-recetas). Corregilas
          desde su ficha, en{" "}
          <Link href="/recetas" className="text-primary underline underline-offset-4">
            Recetas
          </Link>
          .
        </Notice>
      ) : null}

      {ofClass.length === 0 ? (
        <EmptyState title={`Todavía no hay ${current.label.toLowerCase()}.`}>
          {canManage
            ? "Cargá el primero con «Nuevo rubro»."
            : "Los crea quien administra el catálogo o el recetario para todo el grupo."}
        </EmptyState>
      ) : null}

      {selected ? (
        <div className="flex flex-col gap-4 xl:grid xl:min-h-112 xl:flex-[1_1_0px] xl:grid-cols-[250px_minmax(0,1fr)] xl:grid-rows-[minmax(0,1fr)]">
          <RubroPanel
            label={current.label}
            rubros={shown}
            selectedId={selected.id}
            hrefFor={(id) => listHref(PATH, params, { rubro: id })}
            words={words}
            foldEmpty={query === ""}
            empty={
              <>
                Ningún rubro coincide con «{query}».{" "}
                <Link
                  href={listHref(PATH, params, { q: undefined })}
                  className="text-primary underline underline-offset-4"
                >
                  Ver todos
                </Link>
              </>
            }
          />
          {sheet ? (
            <RubroSheetCard
              key={sheet.id}
              sheet={sheet}
              canManage={canManage}
              see={seeLink(sheet, menus)}
              settingsHref={
                (sheet.rubroClass === "purchase" ? menus.catalogManage : menus.rubrosRecipes)
                  ? `/materias-primas/configuracion?lista=${sheet.rubroClass === "purchase" ? "categorias" : "categorias-de-recetas"}`
                  : null
              }
              status={
                canManage ? (
                  <RubroStatusDialog
                    rubro={{
                      id: sheet.id,
                      name: sheet.name,
                      rubroClass: sheet.rubroClass,
                      isActive: sheet.isActive,
                      uses: selected.uses,
                    }}
                    targets={targets}
                  />
                ) : null
              }
              metrics={
                <Metrics
                  sheet={sheet}
                  // Sin precios a la vista, el indicador no está.
                  prices={
                    place
                      ? {
                          summary: prices,
                          place: place.place?.name ?? null,
                          why: place.blockedActive
                            ? `No ves precios de ${place.blockedActive}.`
                            : "Elegí un local arriba.",
                        }
                      : null
                  }
                />
              }
            />
          ) : (
            <EmptyState title="No encontramos ese rubro." />
          )}
        </div>
      ) : null}
    </>
  );
}

// «Ver sus 41 materias primas»: la lista, filtrada por el rubro.
function seeLink(
  sheet: RubroSheet,
  menus: Awaited<ReturnType<typeof getMenus>>,
): { href: string; label: string } | null {
  if (sheet.ingredients) {
    const n = sheet.ingredients.total;
    if (!menus.catalog || n === 0) return null;
    return {
      href: `/materias-primas?rubro=${sheet.id}`,
      label: n === 1 ? "Ver su materia prima" : `Ver sus ${n} materias primas`,
    };
  }
  const n = sheet.recipes.total;
  if (!menus.recipes || n === 0) return null;
  const tab = sheet.rubroClass === "menu" ? "" : "tipo=preparaciones&";
  return {
    href: `/recetas?${tab}rubro=${sheet.id}`,
    label: n === 1 ? "Ver su receta" : `Ver sus ${n} recetas`,
  };
}

// Un cero real es 0, sin estado positivo.
const inUse = (n: number) =>
  n > 0
    ? ({ status: "info", statusLabel: "En uso" } as const)
    : ({ status: "none", statusLabel: "Sin uso" } as const);

// Cada número sale de una regla: sin denominador, «Sin …» (nunca 0 %).
function Metrics({
  sheet,
  prices,
}: {
  sheet: RubroSheet;
  prices: {
    summary: { total: number; current: number } | null;
    place: string | null;
    // Por qué no hay número.
    why: string;
  } | null;
}) {
  const { recipes, ingredients } = sheet;
  if (ingredients) {
    const inactive = ingredients.total - ingredients.active;
    const state = missingState(
      prices?.summary ? prices.summary.total - prices.summary.current : 0,
      prices?.summary?.total ?? 0,
    );
    return (
      <div className="grid gap-3 desk:grid-cols-3">
        <Metric
          compact
          label="Materias primas"
          value={ingredients.total}
          comparison={
            inactive > 0
              ? `${inactive} ${inactive === 1 ? "desactivada" : "desactivadas"}`
              : undefined
          }
          emptyLabel="Sin datos"
          {...inUse(ingredients.total)}
        />
        {prices ? (
          <Metric
            compact
            label="Con precio al día"
            period={prices.place ?? undefined}
            value={prices.summary ? prices.summary.current : null}
            total={prices.summary ? prices.summary.total : null}
            comparison={prices.summary ? `de ${prices.summary.total} activas` : undefined}
            missingReason={prices.why}
            emptyLabel="Sin materias primas activas."
            status={state.status}
            statusLabel={state.label}
          />
        ) : null}
        <Metric
          compact
          label="Recetas que las usan"
          value={recipes.total}
          comparison={
            recipes.total > 0
              ? `${recipes.published} ${recipes.published === 1 ? "vigente" : "vigentes"}`
              : undefined
          }
          emptyLabel="Sin datos"
          {...inUse(recipes.total)}
        />
      </div>
    );
  }
  return (
    <div className="grid gap-3 desk:grid-cols-3">
      <Metric
        compact
        label="Recetas"
        value={recipes.total}
        emptyLabel="Sin datos"
        {...inUse(recipes.total)}
      />
      <Metric
        compact
        label="Publicadas"
        value={recipes.published}
        total={recipes.total}
        comparison={`de ${recipes.total}`}
        emptyLabel="Sin recetas."
        status="info"
        statusLabel="Vigentes"
      />
      <Metric
        compact
        label="En borrador o en revisión"
        value={recipes.open}
        total={recipes.total}
        comparison={`de ${recipes.total}`}
        emptyLabel="Sin recetas."
        status="info"
        statusLabel="En preparación"
      />
    </div>
  );
}
