"use client";

import { useEffect, useId, useRef, useState, useTransition } from "react";
import { Plus, Trash2 } from "lucide-react";

import { saveLinesAction, searchIngredientsAction } from "@/app/recetas/actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { reasonField, recipeLinesSchema } from "@/lib/forms/schemas";
import { BASIS_LABELS, LINE_UNITS, type QuantityBasis } from "@/lib/recipe-format";
import type { RecipeLine } from "@/lib/recipes";

type Line = {
  key: number;
  ingredient_id: string | null;
  sub_recipe_id: string | null;
  ingredient: string;
  quantity: string;
  unit: (typeof LINE_UNITS)[number]["code"];
  basis: QuantityBasis;
  no_scale: boolean;
  notes: string;
};
type Found = { id: string; name: string; code: string; unit: string };
type Search = { status: "idle" | "searching" | "error" | "done"; results: Found[] };

const toLine = (l: RecipeLine, key: number): Line => ({
  key,
  ingredient_id: l.ingredientId,
  sub_recipe_id: l.subRecipeId,
  ingredient: l.ingredient,
  quantity: String(l.quantity).replace(".", ","),
  unit: (LINE_UNITS.find((u) => u.code === l.unit)?.code ?? "g") as Line["unit"],
  basis: l.basis,
  no_scale: l.noScale,
  notes: l.notes ?? "",
});

// Lo que se guarda (sin la clave interna): sirve para saber si hay cambios sin guardar.
const snapshot = (lines: Line[]) =>
  JSON.stringify(
    lines.map((l) => [
      l.ingredient_id,
      l.sub_recipe_id,
      l.quantity,
      l.unit,
      l.basis,
      l.no_scale,
      l.notes,
    ]),
  );

// La unidad sugerida para una materia prima nueva: la que usa en las recetas.
function suggestedUnit(unitName: string): Line["unit"] {
  if (unitName === "ml") return "ml";
  if (unitName === "unidad") return "unit";
  return "g";
}

// Componentes de un borrador: la persona arma la lista (buscando materias primas desde 3 letras) y
// la guarda entera. Se valida con el mismo esquema en el navegador y en el servidor; la base controla
// unidades, permisos y que nadie haya cambiado el borrador mientras tanto.
export function RecipeLinesEditor({
  recipeId,
  versionId,
  expectedUpdatedAt,
  initial,
}: {
  recipeId: string;
  versionId: string;
  expectedUpdatedAt: string;
  initial: RecipeLine[];
}) {
  const prefix = useId();
  const [lines, setLines] = useState<Line[]>(() => initial.map((l, i) => toLine(l, i + 1)));
  const [nextKey, setNextKey] = useState(initial.length + 1);
  const [saved, setSaved] = useState(() => snapshot(initial.map((l, i) => toLine(l, i + 1))));
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState<Search>({ status: "idle", results: [] });
  const [reason, setReason] = useState("");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [state, setState] = useState<ActionState>({});
  const [pending, startTransition] = useTransition();
  const lastQuery = useRef("");
  const focusNext = useRef<string | null>(null);
  const dirty = snapshot(lines) !== saved;
  useUnsavedWarning(dirty);

  // Buscador: desde 3 letras, con una pausa corta. Solo cuenta la respuesta de la última búsqueda.
  const searching = query.trim().length >= 3;
  useEffect(() => {
    if (query.trim().length < 3) return;
    lastQuery.current = query;
    const timer = setTimeout(() => {
      setSearch((s) => ({ ...s, status: "searching" }));
      void searchIngredientsAction(query).then((r) => {
        if (lastQuery.current !== query) return;
        setSearch(
          r.status === "ok"
            ? { status: "done", results: r.results }
            : { status: "error", results: [] },
        );
      });
    }, 300);
    return () => clearTimeout(timer);
  }, [query]);

  // El foco va a donde corresponde después de agregar o quitar (no se pierde en la página).
  useEffect(() => {
    if (!focusNext.current) return;
    document.getElementById(focusNext.current)?.focus();
    focusNext.current = null;
  });

  const id = (key: number, field: string) => `${prefix}-${field}-${key}`;
  const update = (key: number, change: Partial<Line>) =>
    setLines((all) => all.map((l) => (l.key === key ? { ...l, ...change } : l)));

  function add(r: Found) {
    setLines((all) => [
      ...all,
      {
        key: nextKey,
        ingredient_id: r.id,
        sub_recipe_id: null,
        ingredient: r.name,
        quantity: "",
        unit: suggestedUnit(r.unit),
        basis: "purchase",
        no_scale: false,
        notes: "",
      },
    ]);
    focusNext.current = id(nextKey, "quantity");
    setNextKey((k) => k + 1);
    setQuery("");
    setSearch({ status: "idle", results: [] });
  }

  function remove(key: number) {
    setLines((all) => all.filter((l) => l.key !== key));
    focusNext.current = `${prefix}-buscar`;
  }

  function save() {
    const parsedReason = reasonField.safeParse(reason);
    const parsed = recipeLinesSchema.safeParse(lines);
    const found: Record<string, string> = {};
    if (!parsed.success) {
      for (const issue of parsed.error.issues) {
        const [index, field] = issue.path;
        const line = typeof index === "number" ? lines[index] : undefined;
        if (line && typeof field === "string") found[id(line.key, field)] ??= issue.message;
      }
    }
    if (!parsedReason.success)
      found[`${prefix}-motivo`] = parsedReason.error.issues[0]?.message ?? "Escribí el motivo.";
    setErrors(found);
    const first = Object.keys(found)[0];
    if (first || !parsed.success) {
      setState({ status: "bad", message: "Revisá los campos marcados." });
      if (first) document.getElementById(first)?.focus();
      return;
    }
    startTransition(async () => {
      const result = await saveLinesAction({
        recipeId,
        versionId,
        expectedUpdatedAt,
        reason,
        lines: parsed.data,
      });
      setState(result);
      if (result.status === "ok") {
        setSaved(snapshot(lines));
        setReason("");
      }
    });
  }

  return (
    <div className="flex flex-col gap-4">
      {dirty ? (
        <p className="flex flex-wrap items-center gap-2 text-base text-ink">
          <Badge status="warn">Cambios sin guardar</Badge> Guardalos antes de pedir la revisión.
        </p>
      ) : null}
      {lines.length === 0 ? (
        <p className="text-base text-ink-muted">
          Todavía no tiene componentes. Buscá una materia prima para agregarla.
        </p>
      ) : (
        <ol className="flex flex-col gap-3" aria-label="Componentes del borrador">
          {lines.map((line, index) => (
            <li key={line.key} className="flex flex-col gap-3 rounded-sm border border-line p-3">
              <div className="flex items-start justify-between gap-2">
                <span className="font-medium text-ink">
                  {index + 1}. {line.ingredient}
                </span>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => remove(line.key)}
                  aria-label={`Quitar ${line.ingredient}`}
                >
                  <Trash2 aria-hidden="true" />
                  Quitar
                </Button>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Field
                  id={id(line.key, "quantity")}
                  label="Cantidad"
                  error={errors[id(line.key, "quantity")]}
                >
                  <Input
                    inputMode="decimal"
                    value={line.quantity}
                    onChange={(e) => update(line.key, { quantity: e.target.value })}
                  />
                </Field>
                <Field
                  id={id(line.key, "unit")}
                  label="Unidad"
                  error={errors[id(line.key, "unit")]}
                >
                  <Select
                    value={line.unit}
                    onChange={(e) => update(line.key, { unit: e.target.value as Line["unit"] })}
                  >
                    {LINE_UNITS.map((u) => (
                      <option key={u.code} value={u.code}>
                        {u.label}
                      </option>
                    ))}
                  </Select>
                </Field>
              </div>
              <details
                open={
                  (line.basis !== "purchase" && line.basis !== "finished") ||
                  line.notes !== "" ||
                  undefined
                }
              >
                <summary className="flex min-h-touch cursor-pointer items-center text-base text-primary underline-offset-4 hover:underline">
                  Base de la cantidad y observaciones
                </summary>
                <div className="flex flex-col gap-3 pt-2">
                  {/* Una preparación va siempre en cantidad terminada. */}
                  {line.sub_recipe_id ? null : (
                    <Field id={id(line.key, "basis")} label="La cantidad es">
                      <Select
                        value={line.basis}
                        onChange={(e) =>
                          update(line.key, { basis: e.target.value as QuantityBasis })
                        }
                      >
                        {(Object.keys(BASIS_LABELS) as QuantityBasis[])
                          .filter((b) => b !== "finished")
                          .map((b) => (
                            <option key={b} value={b}>
                              {BASIS_LABELS[b]}
                            </option>
                          ))}
                      </Select>
                    </Field>
                  )}
                  <Field
                    id={id(line.key, "notes")}
                    label="Observaciones (opcional)"
                    error={errors[id(line.key, "notes")]}
                  >
                    <Input
                      value={line.notes}
                      maxLength={500}
                      onChange={(e) => update(line.key, { notes: e.target.value })}
                    />
                  </Field>
                </div>
              </details>
            </li>
          ))}
        </ol>
      )}

      <Field
        id={`${prefix}-buscar`}
        label="Agregar materia prima"
        hint="Escribí al menos 3 letras del nombre, un alias o el código."
      >
        <Input value={query} onChange={(e) => setQuery(e.target.value)} autoComplete="off" />
      </Field>
      {/* Lo que pasa con la búsqueda se anuncia (lectores de pantalla). */}
      <p role="status" aria-live="polite" className="text-sm text-ink-muted">
        {!searching
          ? ""
          : search.status === "searching" || search.status === "idle"
            ? "Buscando…"
            : search.status === "error"
              ? "No pudimos buscar. Probá de nuevo."
              : search.results.length === 0
                ? `No encontramos materias primas con «${query.trim()}».`
                : `${search.results.length} ${search.results.length === 1 ? "resultado" : "resultados"}.`}
      </p>
      {searching && search.status === "done" && search.results.length > 0 ? (
        <ul className="flex flex-col gap-1" aria-label="Materias primas encontradas">
          {search.results.map((r) => (
            <li key={r.id}>
              <Button
                type="button"
                variant="outline"
                className="h-auto w-full justify-start py-2 text-left whitespace-normal"
                onClick={() => add(r)}
              >
                <Plus aria-hidden="true" />
                <span className="flex flex-col">
                  <span>{r.name}</span>
                  <span className="text-sm text-ink-muted">{r.code}</span>
                </span>
              </Button>
            </li>
          ))}
        </ul>
      ) : null}

      <Field
        id={`${prefix}-motivo`}
        label="Motivo de los cambios"
        hint="Queda en el historial."
        error={errors[`${prefix}-motivo`]}
      >
        <Textarea value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} />
      </Field>
      <FormNotice state={state} />
      <Button type="button" onClick={save} disabled={pending} className="w-full sm:w-auto">
        {pending ? "Guardando…" : "Guardar componentes"}
      </Button>
    </div>
  );
}
