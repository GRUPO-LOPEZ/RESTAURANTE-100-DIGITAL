import { Scale } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { PrintButton } from "@/components/print-button";
import {
  CompleteCard,
  PaperHeader,
  PhotoCard,
  ServiceCard,
  StepsCard,
  cardVersionLine,
} from "@/components/recipe-cards/cards";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/kpi";
import { requireMenu } from "@/lib/auth/session";
import { UUID, first } from "@/lib/data";
import { RECIPE_CARDS, recipeCardHref, recipeCardKey } from "@/lib/recipe-cards";
import { getKitchenCard, getPublishedPhotos, getRecipe, type PhotoSet } from "@/lib/recipes";
import { cn } from "@/lib/utils";

// Fichas técnicas (pedido de Soy, ADR-0065): 1 Completa, 2 Servicio, 3 Foto y 4 Procedimiento, de la versión vigente.
// Reemplazan a la vista de cocina (/cocina redirige acá). Sin ningún valor económico: la base no los manda (caso 24).
type Props = PageProps<"/recetas/[id]/fichas">;

export default function FichasPage({ params, searchParams }: Props) {
  return (
    <AppShell
      title="Fichas técnicas"
      fill
      heading={
        <Suspense fallback="Fichas técnicas">
          <Name params={params} />
        </Suspense>
      }
      back={
        <Suspense fallback={null}>
          <Back params={params} />
        </Suspense>
      }
      meta={
        <Suspense fallback={null}>
          <Version params={params} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Cards params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const cardOnce = cache(getKitchenCard);

async function cardOf(params: Props["params"]) {
  await requireMenu("recipes");
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  return { id, card: await cardOnce(id) };
}

async function Name({ params }: { params: Props["params"] }) {
  return (await cardOf(params)).card?.name ?? "Fichas técnicas";
}

async function Version({ params }: { params: Props["params"] }) {
  const { card } = await cardOf(params);
  if (!card) return null;
  return <span className="text-sm text-ink-muted tabular-nums">{cardVersionLine(card)}</span>;
}

// Quien trabaja la receta vuelve a su ficha de edición; a quien solo la ve, esa ficha lo traería de nuevo acá.
async function Back({ params }: { params: Props["params"] }) {
  await requireMenu("recipes");
  const { id } = await params;
  const recipe = UUID.test(id) ? await getRecipe(id) : null;
  const works = recipe && (recipe.can.draft || recipe.can.review || recipe.can.publish);
  return works ? (
    <BackLink href={`/recetas/${id}`} label="Volver a la receta">
      Receta
    </BackLink>
  ) : (
    <BackLink href="/recetas" label="Volver a recetas">
      Recetas
    </BackLink>
  );
}

async function Cards({ params, searchParams }: Props) {
  const { id, card } = await cardOf(params);
  if (!card)
    return (
      <EmptyState title="Esta receta no tiene una versión vigente para tu cocina.">
        Puede estar en preparación, archivada o no asignada a tu local.
      </EmptyState>
    );
  const view = recipeCardKey(first((await searchParams).ver));
  const number = RECIPE_CARDS.findIndex((c) => c.key === view);
  const current = RECIPE_CARDS[number] ?? RECIPE_CARDS[0];
  const photos: PhotoSet =
    view === "completa" || view === "foto"
      ? await getPublishedPhotos(id)
      : { photos: [], failed: false };
  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-2 print:hidden">
        <nav aria-label="Fichas técnicas" className="flex w-full gap-1.5 desk:w-auto">
          {RECIPE_CARDS.map((c, i) => (
            <Link
              key={c.key}
              href={recipeCardHref(id, c.key)}
              aria-current={c.key === view ? "page" : undefined}
              scroll={false}
              className={cn(
                "inline-flex min-h-touch flex-1 items-center justify-center gap-1 rounded-sm border px-3 text-base desk:min-h-control desk:flex-none desk:text-sm",
                c.key === view
                  ? "border-primary bg-nav-active font-medium text-nav-active-ink"
                  : "border-line bg-surface text-ink hover:bg-line/50",
              )}
            >
              {i + 1}
              {/* En el celular entran los cuatro: con su nombre, solo la que se está viendo. */}
              <span className={cn(c.key !== view && "sr-only desk:not-sr-only")}>
                <span className="sr-only desk:not-sr-only">· </span>
                {c.label}
              </span>
            </Link>
          ))}
        </nav>
        <div className="flex flex-wrap gap-2">
          <Button asChild variant="outline" className="hidden desk:inline-flex">
            <Link href={`/recetas/${id}/escalar`}>
              <Scale aria-hidden="true" />
              Hacer varias recetas
            </Link>
          </Button>
          <PrintButton label="Imprimir esta ficha" />
        </div>
      </div>

      <div className="flex flex-col gap-4 xl:min-h-0 xl:flex-[1_1_0px] print:block print:space-y-4">
        <PaperHeader
          card={card}
          label={`Ficha técnica ${number + 1} · ${current.label}, ${current.purpose}`}
        />
        {view === "completa" ? <CompleteCard card={card} photos={photos} /> : null}
        {view === "servicio" ? <ServiceCard card={card} /> : null}
        {view === "foto" ? <PhotoCard photos={photos} /> : null}
        {view === "procedimiento" ? <StepsCard card={card} /> : null}
      </div>

      <Button asChild variant="outline" className="desk:hidden print:hidden">
        <Link href={`/recetas/${id}/escalar`}>
          <Scale aria-hidden="true" />
          Hacer varias recetas
        </Link>
      </Button>
    </>
  );
}
