import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { RubroCard, NewRubroCard } from "@/components/rubro-card";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Notice } from "@/components/ui/notice";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { cleanSearch } from "@/lib/catalog";
import { first } from "@/lib/data";
import { listHref, plainParams } from "@/lib/list-params";
import { getRubros } from "@/lib/recipes";
import {
  RUBRO_CLASSES,
  arrangeRubros,
  rubroClassFromTab,
  summarize,
  type RubroSort,
} from "@/lib/rubros";

const PATH = "/rubros";

// Rubros (ADR-0038, pedido de Soy): la tabla maestra del recetario en una sola pantalla. Tres pestañas
// (compra, sub-recetas y menú), un resumen y una grilla de tarjetas con conteos y porcentajes. Dar de
// alta, renombrar, dar de baja y reactivar pasan por funciones de la base que controlan el permiso.
export default function RubrosPage({ searchParams }: PageProps<"/rubros">) {
  return (
    <AppShell title="Rubros">
      <Suspense fallback={<Loading />}>
        <Rubros searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Rubros({ searchParams }: { searchParams: PageProps<"/rubros">["searchParams"] }) {
  await requireMenu("rubros");
  const raw = await searchParams;
  const params = plainParams(raw);
  const current = rubroClassFromTab(first(raw.clase));
  const query = cleanSearch(first(raw.q)) ?? "";
  const sort: RubroSort = first(raw.orden) === "az" ? "az" : "cantidad";
  const [data, menus] = await Promise.all([getRubros(), getMenus()]);

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
  const activeTargets = ofClass
    .filter((r) => r.isActive)
    .map((r) => ({ id: r.id, label: `${r.code} · ${r.name}` }))
    .sort((a, b) => a.label.localeCompare(b.label, "es"));

  return (
    <div className="flex flex-col gap-4">
      <dl
        aria-label={`Resumen de ${current.label.toLowerCase()}`}
        className="grid grid-cols-2 gap-px overflow-hidden rounded-md border border-line bg-line desk:grid-cols-4"
      >
        {[
          ["Total", summary.total],
          ["Activos", summary.active],
          ["Dados de baja", summary.inactive],
          ["Sin uso", summary.unused],
        ].map(([label, value]) => (
          <div
            key={label}
            className="flex items-baseline justify-between gap-2 bg-surface px-4 py-3"
          >
            <dt className="text-sm font-medium text-ink-muted">{label}</dt>
            <dd className="text-xl font-semibold text-ink tabular-nums">{value}</dd>
          </div>
        ))}
      </dl>

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

      <div className="flex flex-col gap-3 desk:flex-row desk:items-end desk:justify-between">
        <Tabs
          label="Clases de rubro"
          className="desk:flex-1"
          items={RUBRO_CLASSES.map((c) => ({
            href: listHref(PATH, params, { clase: c.tab === "compra" ? undefined : c.tab }),
            label: c.label,
            current: c.rubroClass === current.rubroClass,
            count: data.rubros.filter((r) => r.rubroClass === c.rubroClass).length,
          }))}
        />
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

      <h2 className="sr-only">{current.label}</h2>
      {shown.length === 0 && query ? (
        <p className="text-base text-ink">
          Ningún rubro coincide con «{query}».{" "}
          <Link
            href={listHref(PATH, params, { q: undefined })}
            className="text-primary underline underline-offset-4"
          >
            Ver todos
          </Link>
        </p>
      ) : null}
      {ofClass.length === 0 && !canManage ? (
        <EmptyState title={`Todavía no hay ${current.label.toLowerCase()}.`}>
          Los crea quien administra el catálogo o el recetario para todo el grupo.
        </EmptyState>
      ) : null}
      <ul
        aria-label={current.label}
        className="grid grid-cols-2 gap-3 desk:grid-cols-3 xl:grid-cols-5"
      >
        {shown.map((r) => (
          <li key={r.id}>
            <RubroCard
              rubro={r}
              total={summary.uses}
              canManage={canManage}
              targets={activeTargets.filter((t) => t.id !== r.id)}
            />
          </li>
        ))}
        {canManage ? (
          <li>
            <NewRubroCard
              groupId={data.groupId}
              rubroClass={current.rubroClass}
              classLabel={current.label}
              prefix={current.prefix}
            />
          </li>
        ) : null}
      </ul>
    </div>
  );
}
