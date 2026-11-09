import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Card, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/kpi";
import { getMenus, requireOperable } from "@/lib/auth/session";
import { cleanSearch, getIngredients } from "@/lib/catalog";
import { first } from "@/lib/data";
import { getRecipes } from "@/lib/recipes";

// Búsqueda global (ADR-0036; decisión de Joaco, 2026-11-09): recetas y materias primas, con las mismas
// lecturas de sus listas y la sesión de la persona. La base decide qué ve cada uno; cada bloque aparece
// solo si la persona tiene ese menú.
export default function BuscarPage({ searchParams }: PageProps<"/buscar">) {
  return (
    <AppShell title="Búsqueda" description="Recetas y materias primas que podés ver.">
      <Suspense fallback={<Loading />}>
        <Results searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const SHOWN = 8;

async function Results({ searchParams }: { searchParams: PageProps<"/buscar">["searchParams"] }) {
  await requireOperable();
  const [params, menus] = await Promise.all([searchParams, getMenus()]);
  const search = cleanSearch(first(params.q));
  // La búsqueda también en la pantalla: en el celular el buscador está dentro de "Menú", y así se afina.
  const form = (
    <form
      action="/buscar"
      method="get"
      role="search"
      aria-label="Buscar en esta pantalla"
      className="flex max-w-xl flex-col gap-3 desk:flex-row desk:items-end"
    >
      <Field id="buscar-pagina" label="Buscar" className="flex-1">
        <Input
          type="search"
          name="q"
          enterKeyHint="search"
          maxLength={60}
          defaultValue={search ?? ""}
          placeholder="Nombre o código"
        />
      </Field>
      <Button type="submit">Buscar</Button>
    </form>
  );
  if (!search) {
    return (
      <>
        {form}
        <EmptyState title="Escribí qué buscás.">
          Por nombre o código de una receta o una materia prima.
        </EmptyState>
      </>
    );
  }
  const [recipes, ingredients] = await Promise.all([
    menus.recipes ? getRecipes({ search, page: 0 }) : null,
    menus.catalog ? getIngredients({ search, page: 0 }) : null,
  ]);
  const query = encodeURIComponent(search);
  return (
    <>
      {form}
      <p className="text-base text-ink">
        Resultados para <span className="font-medium">«{search}»</span>
      </p>
      <div className="grid gap-6 desk:grid-cols-2">
        {recipes ? (
          <Block
            title="Recetas"
            total={recipes.total}
            more={`/recetas?q=${query}`}
            items={recipes.rows.slice(0, SHOWN).map((r) => ({
              id: r.id,
              href: `/recetas/${r.id}`,
              name: r.name,
              detail: r.code,
              inactive: !r.isActive,
            }))}
          />
        ) : null}
        {ingredients ? (
          <Block
            title="Materias primas"
            total={ingredients.total}
            more={`/materias-primas?q=${query}`}
            items={ingredients.rows.slice(0, SHOWN).map((i) => ({
              id: i.id,
              href: `/materias-primas/${i.id}`,
              name: i.name,
              detail: [i.code, i.category].filter(Boolean).join(" · "),
              inactive: !i.isActive,
            }))}
          />
        ) : null}
      </div>
    </>
  );
}

function Block({
  title,
  total,
  more,
  items,
}: {
  title: string;
  total: number;
  more: string;
  items: { id: string; href: string; name: string; detail: string; inactive: boolean }[];
}) {
  return (
    <Card className="flex flex-col gap-3">
      <div className="flex items-baseline justify-between gap-2">
        <CardTitle>{title}</CardTitle>
        <span className="text-sm text-ink-muted tabular-nums">
          {total === 1 ? "1 resultado" : `${total.toLocaleString("es-AR")} resultados`}
        </span>
      </div>
      {items.length === 0 ? (
        <p className="text-base text-ink-muted">
          No encontramos {title.toLowerCase()} con ese nombre o código.
        </p>
      ) : (
        <ul className="flex flex-col divide-y divide-line" aria-label={title}>
          {items.map((i) => (
            <li key={i.id}>
              <Link
                href={i.href}
                className="flex min-h-touch items-center justify-between gap-3 py-2 underline-offset-4 hover:underline desk:min-h-control"
              >
                <span className="min-w-0 text-base [overflow-wrap:anywhere] text-primary">
                  {i.name}
                </span>
                <span className="flex shrink-0 items-center gap-2 text-sm text-ink-muted tabular-nums">
                  {i.inactive ? <Badge status="none">Archivada</Badge> : null}
                  {i.detail}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
      {total > items.length ? (
        <Link
          href={more}
          className="inline-flex min-h-touch w-fit items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-control-sm"
        >
          Ver {total.toLocaleString("es-AR")} en {title}
        </Link>
      ) : null}
    </Card>
  );
}
