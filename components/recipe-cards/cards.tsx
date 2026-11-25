import Link from "next/link";

import { CriticalPoint } from "@/components/recipe-cards/critical-point";
import { RecipePhotoImage } from "@/components/recipe-photo-image";
import { Badge, type BadgeStatus } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/states";
import { Tile } from "@/components/ui/tile";
import { formatDate } from "@/lib/data";
import { measureText } from "@/lib/measures";
import {
  ALLERGEN_LABELS,
  BASIS_LABELS,
  MEDIA_KIND_LABELS,
  STEP_KIND_LABELS,
  formatMinutes,
  formatQuantity,
  versionLine,
} from "@/lib/recipe-format";
import {
  afterSteps,
  mainPhoto,
  recipeCardHref,
  serviceAmount,
  type RecipeCardKey,
} from "@/lib/recipe-cards";
import type { KitchenCard, PhotoSet, RecipePhoto } from "@/lib/recipes";
import { amountText, spoonEquivalent } from "@/lib/scaling-units";
import { cn } from "@/lib/utils";

// Las 4 fichas técnicas (pedido de Soy, ADR-0065). Se acomodan por el ancho de la pantalla, no por el aparato: desde
// 1.280 px (xl), en columnas y sin scroll de página (lo que sobra se desplaza en su tarjeta); entre 800 y 1.280 (una
// tablet, una ventana angosta, zoom), una columna con scroll de página; por debajo, además, con letra de 20 px. En el papel sale todo: ningún alto fijo ni recorte (una hoja A4 mide menos de 800 px, así que cada
// regla de la computadora que hace falta en el papel va también con print:). Sin ningún valor económico: la base no
// los manda (caso 24).

// Lo que se desplaza en la pantalla, entero en el papel.
const PAPER_TILE = "print:overflow-visible print:border-0 print:p-0";

export function cardVersionLine(card: KitchenCard): string {
  return versionLine({
    number: card.versionNumber,
    code: card.code,
    publishedOn: formatDate(card.publishedAt),
    approvedBy: card.approvedBy,
  });
}

// El encabezado del papel: en la pantalla, el nombre y la versión están arriba.
export function PaperHeader({ card, label }: { card: KitchenCard; label: string }) {
  return (
    <div className="hidden flex-col gap-1 border-b border-ink pb-2 print:flex">
      <span className="text-sm text-ink">{label}</span>
      <span className="text-2xl font-semibold text-ink">{card.name}</span>
      <span className="text-sm text-ink tabular-nums">{cardVersionLine(card)}</span>
    </div>
  );
}

const ALLERGEN_BADGE: Record<string, BadgeStatus> = { contains: "bad", may_contain: "warn" };

// Primero lo que sí contiene; lo no verificado, en una sola línea (que no tape lo importante).
function Allergens({ card }: { card: KitchenCard }) {
  const warnings = card.allergens.filter(
    (a) => a.status === "contains" || a.status === "may_contain",
  );
  const unverified = card.allergens.filter((a) => a.status === "not_verified");
  return (
    <div className="flex flex-wrap items-center gap-2">
      <h2 className="text-base font-medium text-ink">Alérgenos</h2>
      {card.allergens.length === 0 ? (
        <p className="text-base text-ink-muted">No hay alérgenos cargados en el catálogo.</p>
      ) : null}
      {warnings.length > 0 ? (
        <ul className="flex flex-wrap gap-2" aria-label="Alérgenos que contiene">
          {warnings.map((a) => (
            <li key={a.name}>
              <Badge
                status={ALLERGEN_BADGE[a.status]}
                className="text-base whitespace-normal print:border print:border-ink"
              >
                {a.name}: {ALLERGEN_LABELS[a.status]}
              </Badge>
            </li>
          ))}
        </ul>
      ) : null}
      {unverified.length > 0 ? (
        <p className="text-base text-ink desk:text-sm print:text-sm">
          <span className="font-medium">Sin verificar:</span>{" "}
          {unverified.map((a) => a.name).join(", ")}.
        </p>
      ) : null}
      {card.allergens.length > 0 && warnings.length === 0 && unverified.length === 0 ? (
        <Badge status="ok" className="text-base whitespace-normal">
          Todo verificado: no contiene ningún alérgeno de la lista
        </Badge>
      ) : null}
    </div>
  );
}

// «10 unidades · 4 porciones de 300 g». Nulo si la receta no tiene cargado cuánto rinde.
function yieldText(card: KitchenCard): string | null {
  const base =
    card.yieldQuantity === null || card.yieldUnitCode === null
      ? null
      : amountText({ value: card.yieldQuantity, unit: card.yieldUnitCode });
  const portions =
    card.portions === null
      ? null
      : `${amountText({ value: card.portions, unit: "portion" })}${card.portionGrams ? ` de ${formatQuantity(card.portionGrams)} g` : ""}`;
  return [base, portions].filter(Boolean).join(" · ") || null;
}

// Un dato chico al lado del título de una tarjeta, que en el celular también se lee.
function Aside({ children }: { children: string }) {
  return <span className="text-base text-ink tabular-nums desk:text-sm">{children}</span>;
}

type Line = KitchenCard["components"][number];

function IngredientName({ line, view }: { line: Line; view: RecipeCardKey }) {
  return (
    <span className="min-w-0 [overflow-wrap:anywhere] text-ink">
      {line.sub_recipe_id ? (
        <span className="flex flex-wrap items-center gap-x-2">
          <Link
            href={recipeCardHref(line.sub_recipe_id, view)}
            className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline desk:min-h-7 print:min-h-0"
          >
            {line.ingredient}
          </Link>
          <Badge status="info">Preparación</Badge>
        </span>
      ) : (
        line.ingredient
      )}
      {line.basis !== "purchase" && line.basis !== "finished" ? (
        <span className="text-sm text-ink-muted"> ({BASIS_LABELS[line.basis].toLowerCase()})</span>
      ) : null}
      {line.notes ? <span className="block text-sm text-ink-muted">{line.notes}</span> : null}
    </span>
  );
}

const lineAmount = (line: Line) => ({ value: line.quantity, unit: line.unit_code });

function StepList({ card, large = false }: { card: KitchenCard; large?: boolean }) {
  if (card.steps.length === 0)
    return <p className="text-base text-ink-muted">Esta versión no tiene pasos cargados.</p>;
  return (
    <ol
      className={cn(
        "flex flex-col gap-3 text-xl print:text-base",
        large ? "desk:gap-4" : "desk:gap-2 desk:text-base",
      )}
      aria-label="Paso a paso"
    >
      {card.steps.map((s) => {
        const after = afterSteps(s.depends_on);
        return (
          <li
            key={s.number}
            className="flex gap-3 border-b border-line pb-3 last:border-0 desk:pb-2 print:break-inside-avoid"
          >
            <span
              aria-hidden="true"
              className="flex size-8 shrink-0 items-center justify-center rounded-full bg-app text-base font-semibold text-ink tabular-nums"
            >
              {s.number}
            </span>
            <span className="flex min-w-0 flex-col gap-1">
              <span className="text-base text-ink-muted desk:text-sm print:text-sm">
                <span className="sr-only">Paso {s.number} · </span>
                {STEP_KIND_LABELS[s.kind]}
                {s.equipment ? ` · Equipo: ${s.equipment}` : ""}
                {s.active_minutes > 0 ? ` · ${formatMinutes(s.active_minutes)} trabajando` : ""}
                {s.passive_minutes > 0 ? ` · ${formatMinutes(s.passive_minutes)} de espera` : ""}
                {after ? ` · ${after}` : ""}
              </span>
              <span className="[overflow-wrap:anywhere] text-ink">{s.instructions}</span>
              {s.control_point ? <CriticalPoint text={s.control_point} /> : null}
            </span>
          </li>
        );
      })}
    </ol>
  );
}

function Fact({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col">
      <dt className="text-sm font-medium text-ink-muted">{label}</dt>
      <dd className="text-xl text-ink tabular-nums desk:text-base print:text-base">{children}</dd>
    </div>
  );
}

const photoAlt = (p: RecipePhoto) =>
  `Foto: ${MEDIA_KIND_LABELS[p.kind]}${p.description ? ` – ${p.description}` : ""}`;

// ---------------------------------------------------------------------------
// 1 · Completa, para capacitar
// ---------------------------------------------------------------------------
export function CompleteCard({ card, photos }: { card: KitchenCard; photos: PhotoSet }) {
  const photo = mainPhoto(photos.photos);
  const place = [card.sector, card.station].filter(Boolean).join(" · ") || "Sin cargar";
  return (
    <>
      <section
        aria-label="Datos"
        className={cn(
          "grid gap-4 rounded-md border border-line bg-surface p-4 desk:shrink-0 print:border-0 print:p-0",
          photo && "xl:grid-cols-[minmax(0,1fr)_15rem] print:grid-cols-[minmax(0,1fr)_12rem]",
        )}
      >
        <div className="flex min-w-0 flex-col gap-3">
          <dl className="grid gap-3 desk:grid-cols-3 print:grid-cols-3">
            <Fact label="Rinde">{yieldText(card) ?? "Sin cargar"}</Fact>
            <Fact label="Sector · Partida">{place}</Fact>
            <Fact label="Tiempo total">
              {formatMinutes(card.totalMinutes)}
              <span className="text-sm text-ink-muted">
                {" "}
                ({formatMinutes(card.activeMinutes)} trabajando)
              </span>
            </Fact>
          </dl>
          <Allergens card={card} />
          {card.variantOf ? (
            <p className="text-base text-ink-muted desk:text-sm">
              Variante de «{card.variantOf.name}» para este local.
            </p>
          ) : null}
          {photo ? null : (
            <p className="text-base text-ink-muted desk:text-sm print:hidden">
              {photos.failed
                ? "No pudimos cargar las fotos. Recargá la página."
                : "Esta versión no tiene fotos."}
            </p>
          )}
        </div>
        {photo ? (
          <RecipePhotoImage
            url={photo.url}
            alt={photoAlt(photo)}
            className="aspect-[4/3] w-full self-start object-cover"
          />
        ) : null}
      </section>

      <div className="grid gap-4 xl:min-h-64 xl:flex-[1_1_0px] xl:grid-cols-[minmax(0,1fr)_minmax(0,3fr)] xl:grid-rows-[minmax(0,1fr)] print:grid-cols-[minmax(0,1fr)_minmax(0,3fr)] print:grid-rows-none">
        <Tile title="Ingredientes" scroll className={PAPER_TILE}>
          <ul
            className="flex flex-col text-xl desk:text-sm print:text-sm"
            aria-label="Ingredientes"
          >
            {card.components.map((c) => (
              <li
                key={c.line}
                className="flex flex-wrap items-baseline justify-between gap-x-2 border-b border-line py-2 last:border-0 desk:py-1.5 print:break-inside-avoid"
              >
                <IngredientName line={c} view="completa" />
                <span className="ml-auto text-right text-ink tabular-nums">
                  <span className="font-semibold">{amountText(lineAmount(c))}</span>
                  {measureText(c.measure_count, c.measure_name)
                    ? ` · ${measureText(c.measure_count, c.measure_name)}`
                    : ""}
                </span>
              </li>
            ))}
            {card.components.length === 0 ? (
              <li className="text-base text-ink-muted">Sin ingredientes.</li>
            ) : null}
          </ul>
        </Tile>
        <Tile title="Paso a paso" scroll className={PAPER_TILE}>
          {card.description ? (
            <p className="text-xl text-ink desk:text-sm print:text-sm">{card.description}</p>
          ) : null}
          <StepList card={card} />
          {card.presentationNotes ? (
            <Note title="Presentación">{card.presentationNotes}</Note>
          ) : null}
          {card.storageNotes ? <Note title="Conservación">{card.storageNotes}</Note> : null}
        </Tile>
      </div>
    </>
  );
}

function Note({ title, children }: { title: string; children: string }) {
  return (
    <div className="flex flex-col gap-1 border-t border-line pt-2 print:break-inside-avoid">
      <h3 className="text-base font-semibold text-ink">{title}</h3>
      <p className="text-xl text-ink desk:text-base print:text-base">{children}</p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 2 · Servicio: la medida práctica, grande, y el gramaje chico abajo; al revés si la medida no da entera
// ---------------------------------------------------------------------------
export function ServiceCard({ card }: { card: KitchenCard }) {
  const yields = yieldText(card);
  return (
    <>
      <section
        aria-label="Alérgenos"
        className="rounded-md border border-line bg-surface p-4 desk:shrink-0 desk:py-3 print:border-0 print:p-0"
      >
        <Allergens card={card} />
      </section>
      <Tile
        title="Ingredientes"
        aside={yields ? <Aside>{`1 receta = ${yields}`}</Aside> : undefined}
        scroll
        className={cn(PAPER_TILE, "desk:shrink-0 xl:min-h-64 xl:flex-[1_1_0px]")}
      >
        <ul
          className="gap-x-12 text-xl xl:columns-2 print:columns-1 print:text-base"
          aria-label="Ingredientes"
        >
          {card.components.map((c) => {
            const { big, small } = serviceAmount({
              count: c.measure_count,
              measure: measureText(c.measure_count, c.measure_name),
              amount: amountText(lineAmount(c)),
              equivalent: spoonEquivalent(lineAmount(c)),
            });
            return (
              <li
                key={c.line}
                className="flex min-h-14 break-inside-avoid items-center justify-between gap-3 border-b border-line py-2 print:min-h-0"
              >
                <IngredientName line={c} view="servicio" />
                <span className="flex max-w-[60%] shrink-0 flex-col items-end text-right text-ink tabular-nums">
                  <span className="text-2xl font-semibold print:text-xl">{big}</span>
                  {small ? <span className="text-sm">{small}</span> : null}
                </span>
              </li>
            );
          })}
          {card.components.length === 0 ? (
            <li className="text-base text-ink-muted">Sin ingredientes.</li>
          ) : null}
        </ul>
      </Tile>
    </>
  );
}

// ---------------------------------------------------------------------------
// 3 · Foto
// ---------------------------------------------------------------------------
export function PhotoCard({ photos }: { photos: PhotoSet }) {
  const photo = mainPhoto(photos.photos);
  if (!photo)
    return (
      <EmptyState
        title={
          photos.failed ? "No pudimos cargar las fotos." : "Esta versión no tiene fotos cargadas."
        }
      >
        {photos.failed
          ? "Recargá la página."
          : "Se agregan en la ficha de la receta, antes de publicarla."}
      </EmptyState>
    );
  const others = photos.photos.filter((p) => p.id !== photo.id);
  return (
    <div
      className={cn(
        "grid gap-4 xl:min-h-64 xl:flex-[1_1_0px] xl:grid-rows-[minmax(0,1fr)] print:block",
        others.length > 0 && "xl:grid-cols-[minmax(0,1fr)_15rem]",
      )}
    >
      <figure className="flex min-w-0 flex-col gap-2 xl:min-h-0">
        <RecipePhotoImage
          url={photo.url}
          alt={photoAlt(photo)}
          className="min-h-48 w-full bg-surface object-contain xl:h-0 xl:min-h-0 xl:flex-[1_1_0px] print:h-auto print:max-h-[60vh] print:flex-none"
        />
        <figcaption aria-hidden="true" className="text-base text-ink">
          <span className="font-medium">{MEDIA_KIND_LABELS[photo.kind]}</span>
          {photo.description ? ` · ${photo.description}` : ""}
        </figcaption>
      </figure>
      {others.length > 0 ? (
        <Tile title="Más fotos" scroll className={cn(PAPER_TILE, "print:mt-4")}>
          <ul className="grid gap-4 print:grid-cols-3" aria-label="Más fotos">
            {others.map((p) => (
              <li key={p.id} className="flex flex-col gap-1 print:break-inside-avoid">
                <RecipePhotoImage url={p.url} alt={photoAlt(p)} />
                <span aria-hidden="true" className="text-sm text-ink">
                  {MEDIA_KIND_LABELS[p.kind]}
                  {p.description ? ` · ${p.description}` : ""}
                </span>
              </li>
            ))}
          </ul>
        </Tile>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// 4 · Procedimiento
// ---------------------------------------------------------------------------
export function StepsCard({ card }: { card: KitchenCard }) {
  return (
    <Tile
      title="Paso a paso"
      aside={
        <Aside>
          {`${formatMinutes(card.totalMinutes)} en total · ${formatMinutes(card.activeMinutes)} trabajando`}
        </Aside>
      }
      scroll
      className={cn(PAPER_TILE, "desk:shrink-0 xl:min-h-64 xl:flex-[1_1_0px]")}
    >
      <StepList card={card} large />
    </Tile>
  );
}
