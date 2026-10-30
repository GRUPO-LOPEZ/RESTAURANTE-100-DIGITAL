import Link from "next/link";
import { Suspense } from "react";

import {
  archiveCategoryAction,
  archiveProcessAction,
  createCategoryAction,
  createProcessAction,
  renameCategoryAction,
  renameProcessAction,
} from "@/app/materias-primas/actions";
import {
  archiveRecipeCategoryAction,
  createRecipeCategoryAction,
  renameRecipeCategoryAction,
} from "@/app/recetas/actions";
import { ActionForm } from "@/components/action-form";
import { AppShell, Loading } from "@/components/app-shell";
import { Disclosure } from "@/components/disclosure";
import { FlashNotice } from "@/components/flash-notice";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { FormInput, FormSelect, FormTextarea } from "@/components/ui/form";
import { EmptyState } from "@/components/ui/kpi";
import {
  getSettingsCategories,
  getSettingsGroups,
  getSettingsProcesses,
  type SettingsCategory,
  type SettingsProcess,
} from "@/lib/catalog";
import { getRecipeSettingsCategories } from "@/lib/recipes";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Configuración del catálogo (ADR-0022): las listas que se eligen al cargar materias primas. Las
// define el grupo; nada viene fijo. La base controla quién puede y que no se dé de baja algo en uso.
export default function ConfiguracionCatalogoPage({
  searchParams,
}: PageProps<"/materias-primas/configuracion">) {
  return (
    <AppShell
      title="Configuración del catálogo"
      description="Las listas que se eligen al cargar materias primas: categorías y procesos de rendimiento."
    >
      <Suspense fallback={<Loading />}>
        <Settings searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

function Reason({ id, label }: { id: string; label: string }) {
  return (
    <FormTextarea
      id={id}
      name="reason"
      label={label}
      hint="Queda en el historial."
      required
      maxLength={500}
    />
  );
}

function count(n: number, one: string, many: string) {
  return n === 0 ? `Sin ${many}` : `${n} ${n === 1 ? one : many}`;
}

// El aviso después de una baja (la dirección trae "?baja=…"). Solo estos dos valores.
function archivedMessage(baja: string | string[] | undefined) {
  switch (baja) {
    case "categoria":
      return "Categoría dada de baja. Queda en el historial.";
    case "proceso":
      return "Proceso dado de baja. Queda en el historial.";
    case "categoria-receta":
      return "Categoría de recetas dada de baja. Queda en el historial.";
    default:
      return null;
  }
}

async function Settings({
  searchParams,
}: {
  searchParams: PageProps<"/materias-primas/configuracion">["searchParams"];
}) {
  await requireMenu("catalogSettings");
  const archived = archivedMessage((await searchParams).baja);
  const menus = await getMenus();
  const [categoryGroups, processGroups, recipeGroups] = await Promise.all([
    menus.catalogManage ? getSettingsGroups("catalog.manage") : [],
    menus.yieldsApprove ? getSettingsGroups("yields.approve") : [],
    menus.recipesSettings ? getSettingsGroups("recipes.draft") : [],
  ]);
  // Hoy hay un solo grupo. Si se suman otros, cada sección va a tener que elegir el grupo.
  const categoryGroup = categoryGroups[0];
  const processGroup = processGroups[0];
  const recipeGroup = recipeGroups[0];
  const [categories, processes, recipeCategories] = await Promise.all([
    categoryGroup ? getSettingsCategories(categoryGroup) : [],
    processGroup ? getSettingsProcesses(processGroup) : [],
    recipeGroup ? getRecipeSettingsCategories(recipeGroup) : [],
  ]);
  return (
    <>
      <Link
        href="/materias-primas"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver a materias primas
      </Link>
      {archived ? <FlashNotice>{archived}</FlashNotice> : null}
      {categoryGroup ? (
        <Categories kind={INGREDIENT_CATEGORIES} groupId={categoryGroup} categories={categories} />
      ) : null}
      {recipeGroup ? (
        <Categories kind={RECIPE_CATEGORIES} groupId={recipeGroup} categories={recipeCategories} />
      ) : null}
      {processGroup ? <Processes groupId={processGroup} processes={processes} /> : null}
      {!categoryGroup && !processGroup && !recipeGroup ? (
        <EmptyState title="No tenés listas para configurar.">
          Las categorías de materias primas las configura Compras; los procesos y las categorías de
          recetas, un Chef de todo el grupo.
        </EmptyState>
      ) : null}
    </>
  );
}

// Las dos listas de categorías (materias primas y recetas) se manejan igual; cambian los textos y
// las acciones. Cada una la administra quien tiene el permiso de su tema para todo el grupo.
type CategoryKind = {
  key: "mp" | "rec";
  title: string;
  description: string;
  empty: string;
  usedOne: string;
  usedMany: string;
  create: typeof createCategoryAction;
  rename: typeof renameCategoryAction;
  archive: typeof archiveCategoryAction;
};

const INGREDIENT_CATEGORIES: CategoryKind = {
  key: "mp",
  title: "Categorías",
  description:
    "Cada materia prima va en una categoría, y si querés, en una subcategoría (por ejemplo, Lácteos › Quesos).",
  empty:
    "Todavía no hay categorías. Creá la primera, por ejemplo «Verduras y frutas», «Carnes» o «Lácteos».",
  usedOne: "materia prima",
  usedMany: "materias primas",
  create: createCategoryAction,
  rename: renameCategoryAction,
  archive: archiveCategoryAction,
};

const RECIPE_CATEGORIES: CategoryKind = {
  key: "rec",
  title: "Categorías de recetas",
  description: "Para ordenar el recetario: por ejemplo, Salsas, Pastas › Rellenas o Postres.",
  empty: "Todavía no hay categorías de recetas. Creá la primera, por ejemplo «Salsas» o «Postres».",
  usedOne: "receta",
  usedMany: "recetas",
  create: createRecipeCategoryAction,
  rename: renameRecipeCategoryAction,
  archive: archiveRecipeCategoryAction,
};

function Categories({
  kind,
  groupId,
  categories,
}: {
  kind: CategoryKind;
  groupId: string;
  categories: SettingsCategory[];
}) {
  const prefix = `cfg-${kind.key}-cat`;
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>{kind.title}</CardTitle>
      <CardDescription>{kind.description}</CardDescription>
      {categories.length === 0 ? (
        <p className="text-base text-ink">{kind.empty}</p>
      ) : (
        <ul className="flex flex-col gap-2" aria-label={kind.title}>
          {categories.map((c) => (
            <li key={c.id} className="flex flex-col gap-2 rounded-sm border border-line p-3">
              <CategoryItem
                kind={kind}
                id={c.id}
                name={c.name}
                uses={c.uses}
                total={c.children.reduce((sum, s) => sum + s.uses, c.uses)}
                subcategories={c.children.length}
              />
              {c.children.length > 0 ? (
                <ul
                  className="flex flex-col gap-2 border-l border-line pl-3"
                  aria-label={`Subcategorías de ${c.name}`}
                >
                  {c.children.map((s) => (
                    <li key={s.id} className="flex flex-col gap-2">
                      <CategoryItem
                        kind={kind}
                        id={s.id}
                        name={s.name}
                        uses={s.uses}
                        total={s.uses}
                        subcategories={0}
                      />
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      <Disclosure summary={kind.key === "mp" ? "Nueva categoría" : "Nueva categoría de recetas"}>
        <ActionForm
          action={kind.create}
          schema="category"
          submitLabel="Crear categoría"
          pendingLabel="Creando…"
        >
          <input type="hidden" name="groupId" value={groupId} />
          <div className="grid gap-4 sm:grid-cols-2">
            <FormInput id={`${prefix}-nombre`} label="Nombre" name="name" required maxLength={80} />
            <FormSelect
              id={`${prefix}-madre`}
              label="Va dentro de"
              hint="Dejalo en «Ninguna» para una categoría principal."
              name="parent_id"
              defaultValue=""
            >
              <option value="">Ninguna (categoría principal)</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </FormSelect>
          </div>
          <Reason id={`${prefix}-motivo`} label="Motivo" />
        </ActionForm>
      </Disclosure>
    </Card>
  );
}

const ARCHIVE_NOTE =
  "Deja de aparecer en las listas y no se puede volver a activar desde acá: si hace falta, se crea de nuevo. La historia se conserva.";

// uses: lo que tiene esta categoría (materias primas o recetas); total: con lo de sus subcategorías.
function CategoryItem({
  kind,
  id,
  name,
  uses,
  total,
  subcategories,
}: {
  kind: CategoryKind;
  id: string;
  name: string;
  uses: number;
  total: number;
  subcategories: number;
}) {
  const prefix = `cfg-${kind.key}-cat`;
  const inUse = uses > 0 || subcategories > 0;
  return (
    <>
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="font-medium text-ink">{name}</span>
        <span className="text-sm text-ink-muted tabular-nums">
          {count(total, kind.usedOne, kind.usedMany)}
          {subcategories > 0 ? " con sus subcategorías" : ""}
        </span>
      </div>
      <Disclosure summary={`Cambiar el nombre de «${name}»`}>
        <ActionForm action={kind.rename} schema="rename" submitLabel="Cambiar nombre">
          <input type="hidden" name="categoryId" value={id} />
          <FormInput
            id={`${prefix}-renombrar-${id}`}
            label="Nombre nuevo"
            name="name"
            required
            maxLength={80}
            defaultValue={name}
          />
          <Reason id={`${prefix}-renombrar-motivo-${id}`} label="Motivo del cambio de nombre" />
        </ActionForm>
      </Disclosure>
      {inUse ? (
        <p className="text-sm text-ink-muted">
          No se puede dar de baja: tiene{" "}
          {[uses > 0 ? kind.usedMany : null, subcategories > 0 ? "subcategorías" : null]
            .filter(Boolean)
            .join(" y ")}
          .
        </p>
      ) : (
        <Disclosure summary={`Dar de baja «${name}»`}>
          <p className="text-base text-ink">{ARCHIVE_NOTE}</p>
          <ActionForm
            action={kind.archive}
            schema="reason"
            submitLabel="Dar de baja"
            variant="destructive"
          >
            <input type="hidden" name="categoryId" value={id} />
            <Reason id={`${prefix}-baja-motivo-${id}`} label="Motivo de la baja" />
          </ActionForm>
        </Disclosure>
      )}
    </>
  );
}

function Processes({ groupId, processes }: { groupId: string; processes: SettingsProcess[] }) {
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>Procesos de rendimiento</CardTitle>
      <CardDescription>
        Lo que cambia el peso de una materia prima: pelado, desgrasado, hervido… Se usan en los
        ensayos y en el rendimiento estándar.
      </CardDescription>
      {processes.length === 0 ? (
        <p className="text-base text-ink">
          Todavía no hay procesos. Creá el primero, por ejemplo «Pelado» o «Hervido».
        </p>
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Procesos de rendimiento">
          {processes.map((p) => (
            <li key={p.id} className="flex flex-col gap-2 rounded-sm border border-line p-3">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <span className="font-medium text-ink">
                  {p.name} <span className="text-sm font-normal text-ink-muted">{p.code}</span>
                </span>
                <span className="text-sm text-ink-muted tabular-nums">
                  {count(p.standards, "estándar vigente", "estándares vigentes")}
                </span>
              </div>
              <Disclosure summary={`Cambiar el nombre de «${p.name}»`}>
                <ActionForm
                  action={renameProcessAction}
                  schema="rename"
                  submitLabel="Cambiar nombre"
                >
                  <input type="hidden" name="processId" value={p.id} />
                  <FormInput
                    id={`cfg-proc-renombrar-${p.id}`}
                    label="Nombre nuevo"
                    hint="El código no cambia."
                    name="name"
                    required
                    maxLength={80}
                    defaultValue={p.name}
                  />
                  <Reason
                    id={`cfg-proc-renombrar-motivo-${p.id}`}
                    label="Motivo del cambio de nombre"
                  />
                </ActionForm>
              </Disclosure>
              {p.standards > 0 ? (
                <p className="text-sm text-ink-muted">
                  No se puede dar de baja: tiene estándares vigentes.
                </p>
              ) : (
                <Disclosure summary={`Dar de baja «${p.name}»`}>
                  <p className="text-base text-ink">{ARCHIVE_NOTE}</p>
                  <ActionForm
                    action={archiveProcessAction}
                    schema="reason"
                    submitLabel="Dar de baja"
                    variant="destructive"
                  >
                    <input type="hidden" name="processId" value={p.id} />
                    <Reason id={`cfg-proc-baja-motivo-${p.id}`} label="Motivo de la baja" />
                  </ActionForm>
                </Disclosure>
              )}
            </li>
          ))}
        </ul>
      )}
      <Disclosure summary="Nuevo proceso">
        <ActionForm
          action={createProcessAction}
          schema="yieldProcess"
          submitLabel="Crear proceso"
          pendingLabel="Creando…"
        >
          <input type="hidden" name="groupId" value={groupId} />
          <div className="grid gap-4 sm:grid-cols-2">
            <FormInput
              id="cfg-proc-codigo"
              label="Código"
              hint="No cambia nunca. Por ejemplo, PELADO."
              name="code"
              required
              maxLength={30}
              autoCapitalize="characters"
            />
            <FormInput id="cfg-proc-nombre" label="Nombre" name="name" required maxLength={80} />
          </div>
          <Reason id="cfg-proc-motivo" label="Motivo" />
        </ActionForm>
      </Disclosure>
    </Card>
  );
}
