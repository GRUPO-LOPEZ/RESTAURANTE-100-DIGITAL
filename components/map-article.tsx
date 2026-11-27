"use client";

import * as React from "react";

import {
  discardArticleAction,
  linkArticleAction,
  resolveArticleAction,
  searchIngredientsAction,
  supplierProductsAction,
} from "@/app/materias-primas/sin-mapear/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/dialog";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { Segmented } from "@/components/ui/segmented";
import type { ActionState } from "@/lib/auth/results";
import { packageFactorWords, parseDecimal } from "@/lib/price-lists";

// Mapear un artículo de la cola (ADR-0052), en una ventana corta: es una materia prima (con su envase, y el factor en
// palabras antes de confirmar), es el mismo que un producto que el proveedor ya tenía, o se descarta. La base controla
// el permiso, pide el motivo y lo hace en una transacción.

type Mode = "ingredient" | "same" | "discard";
const MODES: { value: Mode; label: string }[] = [
  { value: "ingredient", label: "Es una materia prima" },
  { value: "same", label: "Es el mismo que…" },
  { value: "discard", label: "Descartar" },
];
const CONTENT_UNITS = [
  { value: "g", label: "g", base: "g", factor: 1 },
  { value: "kg", label: "kg", base: "g", factor: 1000 },
  { value: "ml", label: "ml", base: "ml", factor: 1 },
  { value: "l", label: "l", base: "ml", factor: 1000 },
  { value: "unit", label: "unidades", base: "unit", factor: 1 },
] as const;

export type ArticleToMap = {
  id: string;
  supplierId: string;
  supplierName: string;
  rawName: string;
  sku: string | null;
  packageHint: string | null;
  // Lo que sugirió Compras en una lista («Es…»): arranca en «Es el mismo que…» con ese producto elegido.
  suggested?: { id: string; description: string } | null;
};

export function MapArticle({
  article,
  packageUnits,
}: {
  article: ArticleToMap;
  // Cómo puede venir (bolsa, caja, kg…): código y nombre.
  packageUnits: { code: string; name: string }[];
}) {
  const [open, setOpen] = React.useState(false);
  const [mode, setMode] = React.useState<Mode>(article.suggested ? "same" : "ingredient");
  return (
    <Modal
      open={open}
      onOpenChange={setOpen}
      trigger={
        <Button type="button" variant="outline" aria-label={`Mapear «${article.rawName}»`}>
          Mapear
        </Button>
      }
      title={`Mapear «${article.rawName}»`}
      description={`${article.supplierName}${article.sku ? ` · código ${article.sku}` : ""}${
        article.packageHint ? ` · ${article.packageHint}` : ""
      }`}
    >
      <div className="flex flex-col gap-4">
        <Segmented
          name={`modo-${article.id}`}
          legend="Qué es"
          value={mode}
          onChange={(v) => setMode(v as Mode)}
          options={MODES}
        />
        {mode === "ingredient" ? (
          <IngredientForm article={article} packageUnits={packageUnits} />
        ) : mode === "same" ? (
          <SameForm article={article} />
        ) : (
          <DiscardForm article={article} />
        )}
      </div>
    </Modal>
  );
}

function Reason({ id, error }: { id: string; error?: string }) {
  return (
    <Field id={id} label="Motivo" hint="Queda en el historial." error={error}>
      <Textarea name="reason" maxLength={500} rows={2} />
    </Field>
  );
}

function IngredientForm({
  article,
  packageUnits,
}: {
  article: ArticleToMap;
  packageUnits: { code: string; name: string }[];
}) {
  const [state, action, pending] = React.useActionState<ActionState, FormData>(
    resolveArticleAction,
    {},
  );
  const [query, setQuery] = React.useState("");
  // Los resultados guardan la búsqueda que los trajo: solo se muestran si coincide con lo escrito.
  const [found, setFound] = React.useState<{
    query: string;
    rows: { id: string; code: string; name: string }[];
    failed: boolean;
  }>({ query: "", rows: [], failed: false });
  const [chosen, setChosen] = React.useState<{ id: string; code: string; name: string } | null>(
    null,
  );
  const [pkg, setPkg] = React.useState(packageUnits[0]?.code ?? "");
  const [units, setUnits] = React.useState("1");
  const [content, setContent] = React.useState("");
  const [unit, setUnit] = React.useState<(typeof CONTENT_UNITS)[number]["value"]>("kg");

  // Busca mientras se escribe (desde 2 letras), con una pausa corta.
  React.useEffect(() => {
    const q = query.trim();
    if (q.length < 2) return;
    const timer = setTimeout(() => {
      searchIngredientsAction(q)
        .then((rows) => setFound({ query: q, rows, failed: false }))
        .catch(() => setFound({ query: q, rows: [], failed: true }));
    }, 250);
    return () => clearTimeout(timer);
  }, [query]);

  // Con menos de 2 letras, o mientras llega la respuesta, no se muestra lo de una búsqueda anterior.
  const q = query.trim();
  const searching = q.length >= 2 && found.query !== q;
  const shown = q.length >= 2 && !searching ? found.rows : [];
  const u = CONTENT_UNITS.find((c) => c.value === unit) ?? CONTENT_UNITS[0];
  const amount = parseDecimal(content);
  const pkgName = packageUnits.find((p) => p.code === pkg)?.name ?? "";
  // Las unidades por envase son enteras: «1,5» o «1.5» no arman un factor.
  const unitsOk = /^[0-9]+$/.test(units.trim()) && Number(units) >= 1;
  const words =
    amount !== null && unitsOk
      ? packageFactorWords(pkgName, Number(units), amount * u.factor, u.base)
      : null;
  const errors = state.fieldErrors ?? {};
  const prefix = `map-${article.id}`;

  return (
    <form action={action} className="flex flex-col gap-4">
      <input type="hidden" name="articleId" value={article.id} />
      <input type="hidden" name="ingredient_id" value={chosen?.id ?? ""} />
      <Field
        id={`${prefix}-buscar`}
        label="Materia prima"
        hint="Buscá por nombre o código (también las de Limpieza o Descartables)."
        error={errors.ingredient_id}
      >
        <Input
          type="search"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setChosen(null);
          }}
          autoComplete="off"
        />
      </Field>
      {chosen ? (
        <p className="text-sm text-ink">
          Elegida: <span className="font-medium">{chosen.name}</span>{" "}
          <span className="text-ink-muted tabular-nums">({chosen.code})</span>
        </p>
      ) : shown.length > 0 ? (
        <ul aria-label="Materias primas encontradas" className="flex flex-col gap-1">
          {shown.map((r) => (
            <li key={r.id}>
              <button
                type="button"
                onClick={() => {
                  setChosen(r);
                  setQuery(r.name);
                  setFound({ query: "", rows: [], failed: false });
                }}
                className="flex min-h-touch w-full items-center justify-between gap-2 rounded-sm px-2 text-left text-sm text-ink hover:bg-line/50 desk:min-h-control-sm"
              >
                {r.name}
                <span className="text-xs text-ink-muted tabular-nums">{r.code}</span>
              </button>
            </li>
          ))}
        </ul>
      ) : searching ? (
        <p className="text-sm text-ink-muted">Buscando…</p>
      ) : q.length >= 2 && found.failed ? (
        <p role="alert" className="text-sm text-bad-ink">
          No pudimos buscar. Probá de nuevo.
        </p>
      ) : q.length >= 2 ? (
        <p className="text-sm text-ink-muted">No encontramos materias primas con ese nombre.</p>
      ) : null}
      {/* Para el lector de pantalla: cuántas encontró. */}
      <p className="sr-only" aria-live="polite">
        {!chosen && q.length >= 2 && !searching && !found.failed
          ? shown.length === 1
            ? "1 materia prima encontrada"
            : `${shown.length} materias primas encontradas`
          : ""}
      </p>
      <div className="grid grid-cols-2 gap-3">
        <Field id={`${prefix}-envase`} label="Viene en" error={errors.package_unit}>
          <Select name="package_unit" value={pkg} onChange={(e) => setPkg(e.target.value)}>
            {packageUnits.map((p) => (
              <option key={p.code} value={p.code}>
                {p.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field
          id={`${prefix}-unidades`}
          label="Unidades por envase"
          error={errors.units_per_package}
        >
          <Input
            name="units_per_package"
            inputMode="numeric"
            value={units}
            onChange={(e) => setUnits(e.target.value)}
          />
        </Field>
        <Field
          id={`${prefix}-contenido`}
          label="Contenido de cada una"
          error={errors.content_per_unit}
        >
          <Input
            name="content_per_unit"
            inputMode="decimal"
            value={content}
            onChange={(e) => setContent(e.target.value)}
          />
        </Field>
        <Field id={`${prefix}-unidad`} label="Unidad" error={errors.content_unit}>
          <Select
            name="content_unit"
            value={unit}
            onChange={(e) => setUnit(e.target.value as typeof unit)}
          >
            {CONTENT_UNITS.map((c) => (
              <option key={c.value} value={c.value}>
                {c.label}
              </option>
            ))}
          </Select>
        </Field>
      </div>
      <p className="rounded-sm bg-info px-3 py-2 text-sm text-info-ink" aria-live="polite">
        {words
          ? `Queda así: ${words}.`
          : !unitsOk
            ? "Las unidades por envase van enteras (1, 12, 30…)."
            : "Completá el envase y el contenido para ver el factor."}
      </p>
      <Reason id={`${prefix}-motivo`} error={errors.reason} />
      <FormNotice state={state} />
      <Button type="submit" disabled={pending}>
        {pending ? "Guardando…" : "Crear el producto de compra"}
      </Button>
    </form>
  );
}

function SameForm({ article }: { article: ArticleToMap }) {
  const [state, action, pending] = React.useActionState<ActionState, FormData>(
    linkArticleAction,
    {},
  );
  const [products, setProducts] = React.useState<
    { id: string; code: string; description: string }[] | null
  >(null);
  const [failed, setFailed] = React.useState(false);
  React.useEffect(() => {
    supplierProductsAction(article.supplierId)
      .then(setProducts)
      .catch(() => setFailed(true));
  }, [article.supplierId]);
  const errors = state.fieldErrors ?? {};
  const prefix = `mismo-${article.id}`;
  return (
    <form action={action} className="flex flex-col gap-4">
      <input type="hidden" name="articleId" value={article.id} />
      {failed ? (
        <p role="alert" className="text-sm text-bad-ink">
          No pudimos cargar los productos del proveedor. Cerrá la ventana y probá de nuevo.
        </p>
      ) : products === null ? (
        <p className="text-sm text-ink-muted">Cargando los productos del proveedor…</p>
      ) : products.length === 0 ? (
        <p className="text-sm text-ink">
          {article.supplierName} todavía no tiene productos de compra. Usá «Es una materia prima».
        </p>
      ) : (
        <Field
          id={`${prefix}-producto`}
          label={`Producto de ${article.supplierName}`}
          hint="El nombre y el código nuevos quedan guardados para reconocerlo la próxima vez."
          error={errors.purchase_product_id}
        >
          <Select name="purchase_product_id" defaultValue={article.suggested?.id ?? ""}>
            <option value="" disabled>
              Elegí el producto
            </option>
            {products.map((p) => (
              <option key={p.id} value={p.id}>
                {p.description} ({p.code})
              </option>
            ))}
          </Select>
        </Field>
      )}
      <Reason id={`${prefix}-motivo`} error={errors.reason} />
      <FormNotice state={state} />
      <Button type="submit" disabled={pending || !products || products.length === 0}>
        {pending ? "Guardando…" : "Vincular"}
      </Button>
    </form>
  );
}

function DiscardForm({ article }: { article: ArticleToMap }) {
  const [state, action, pending] = React.useActionState<ActionState, FormData>(
    discardArticleAction,
    {},
  );
  return (
    <form action={action} className="flex flex-col gap-4">
      <input type="hidden" name="articleId" value={article.id} />
      <p className="text-sm text-ink">
        Sale de la cola. Los renglones de lista quedan como vinieron. Si vuelve a llegar, entra de
        nuevo.
      </p>
      <Reason id={`descartar-${article.id}-motivo`} error={state.fieldErrors?.reason} />
      <FormNotice state={state} />
      <Button type="submit" variant="destructive" disabled={pending}>
        {pending ? "Descartando…" : "Descartar"}
      </Button>
    </form>
  );
}
