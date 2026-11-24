import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { ListPicker } from "@/components/settings-list/list-picker";
import {
  SettingsListBar,
  SettingsListCard,
  SettingsListProvider,
} from "@/components/settings-list/list-editor";
import { EmptyState } from "@/components/ui/states";
import { requireMenu } from "@/lib/auth/session";
import { getUnits } from "@/lib/catalog";
import { first } from "@/lib/data";
import { getSettingsGroup, getSettingsList, getSettingsLists } from "@/lib/settings-data";
import { LIST_INFO, listFromSlug } from "@/lib/settings-lists";
import { cn } from "@/lib/utils";

// Configuración del catálogo en una pantalla (Tanda 2 de Soy, ADR-0063): a la izquierda, las 8 listas que usan las
// materias primas y las recetas; a la derecha, la elegida, que se edita en la tabla y se guarda junta, con motivo. Quién
// edita cada lista lo dice la base; las demás se ven en lectura.
export default function ConfiguracionCatalogoPage({
  searchParams,
}: PageProps<"/materias-primas/configuracion">) {
  return (
    <AppShell
      title="Configuración del catálogo"
      fill
      back={
        <BackLink href="/materias-primas" label="Volver a materias primas">
          Materias primas
        </BackLink>
      }
      meta={
        <span className="text-sm text-ink-muted">
          Las listas que usan las recetas y las materias primas
        </span>
      }
    >
      <Suspense fallback={<Loading />}>
        <Settings searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Settings({
  searchParams,
}: {
  searchParams: PageProps<"/materias-primas/configuracion">["searchParams"];
}) {
  await requireMenu("catalogSettings");
  const query = await searchParams;
  const groupId = await getSettingsGroup();
  if (!groupId)
    return (
      <EmptyState title="No tenés listas para configurar.">
        Las categorías de materias primas y las unidades las configura Compras; los procesos y las
        categorías de recetas, un Chef de todo el grupo.
      </EmptyState>
    );
  const lists = await getSettingsLists(groupId);
  // Al entrar, la primera que la sesión edita. Los avisos de baja de antes (?baja=) llevan a su lista.
  const old: Record<string, string> = {
    categoria: "categorias",
    proceso: "procesos",
    "categoria-receta": "categorias-de-recetas",
  };
  const asked = first(query.lista) ?? old[first(query.baja) ?? ""];
  const list =
    listFromSlug(asked) ?? lists.find((l) => l.can_edit)?.list ?? "ingredient_categories";
  const [data, units] = await Promise.all([
    getSettingsList(groupId, list),
    list === "equipment" ? getUnits() : [],
  ]);
  return (
    <>
      <ListPicker
        value={LIST_INFO[list].slug}
        options={lists.map((l) => ({
          slug: LIST_INFO[l.list].slug,
          label: `${LIST_INFO[l.list].label} (${l.active})`,
        }))}
      />
      <div className="flex min-h-0 flex-col gap-4 desk:grid desk:flex-[1_1_0px] desk:grid-cols-[270px_minmax(0,1fr)] desk:grid-rows-[minmax(0,1fr)]">
        {/* Fuera de la lista elegida: al cambiar de lista, el foco sigue en el enlace. */}
        <nav
          aria-label="Listas"
          className="relative hidden flex-col gap-1 overflow-y-auto rounded-md border border-line bg-surface p-3 desk:flex desk:min-h-0"
        >
          <p className="px-2 pb-1 text-sm text-ink-muted">Listas</p>
          {lists.map((l) => {
            const current = l.list === list;
            return (
              <Link
                key={l.list}
                href={`/materias-primas/configuracion?lista=${LIST_INFO[l.list].slug}`}
                aria-current={current ? "page" : undefined}
                className={cn(
                  "flex min-h-control items-center justify-between gap-2 rounded-sm px-2 py-1 text-sm text-ink focus-visible:outline-2 focus-visible:outline-primary",
                  current ? "bg-nav-active font-medium text-nav-active-ink" : "hover:bg-line/50",
                )}
              >
                {LIST_INFO[l.list].label}
                <span className="text-sm tabular-nums">
                  {l.active}
                  <span className="sr-only"> sin contar las bajas</span>
                </span>
              </Link>
            );
          })}
          <p className="mt-auto px-2 pt-3 text-xs text-ink-muted">
            Todas se editan igual: en la tabla, con un motivo al guardar. Dar de baja no borra.
          </p>
        </nav>
        <SettingsListProvider
          key={list}
          groupId={groupId}
          list={list}
          stamp={data.stamp}
          canEdit={data.canEdit}
          initial={data.items}
          units={units
            .filter((u) => u.dimension !== "package")
            .map((u) => ({ code: u.code, label: u.label, short: u.name }))}
        >
          <SettingsListCard />
          <SettingsListBar />
        </SettingsListProvider>
      </div>
    </>
  );
}
