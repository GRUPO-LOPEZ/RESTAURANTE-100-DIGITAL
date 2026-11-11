"use client";

import { useWatch } from "react-hook-form";

import { FormSelect } from "@/components/ui/form";
import { RECIPE_TYPE_LABELS, type RecipeType } from "@/lib/recipe-format";

type Option = { id: string; label: string; kind: "subrecipe" | "menu" };

const GROUPS = [
  { kind: "menu", label: "Rubros de menú (platos)" },
  { kind: "subrecipe", label: "Sub-recetas (preparaciones y componentes)" },
] as const;

// Tipo y rubro del alta de una receta (ADR-0038): el rubro ofrece solo los de la clase del tipo elegido (un plato,
// los de menú; una preparación o un componente, los de sub-recetas). Antes de elegir el tipo, los dos grupos. La
// base vuelve a controlarlo al crear.
export function RecipeTypeCategory({ categories }: { categories: Option[] }) {
  const type = useWatch({ name: "type" }) as RecipeType | "" | undefined;
  const wanted = !type ? null : type === "dish" ? "menu" : "subrecipe";
  const groups = GROUPS.filter((g) => !wanted || g.kind === wanted)
    .map((g) => ({ ...g, options: categories.filter((c) => c.kind === g.kind) }))
    .filter((g) => g.options.length > 0);
  return (
    <div className="grid gap-4 sm:grid-cols-2">
      <FormSelect id="rec-alta-tipo" label="Tipo" name="type" required defaultValue="">
        <option value="" disabled>
          Elegí el tipo
        </option>
        {(Object.keys(RECIPE_TYPE_LABELS) as RecipeType[]).map((t) => (
          <option key={t} value={t}>
            {RECIPE_TYPE_LABELS[t]}
          </option>
        ))}
      </FormSelect>
      <FormSelect
        id="rec-alta-categoria"
        label="Categoría"
        hint={wanted ? undefined : "Elegí primero el tipo: cada tipo tiene sus rubros."}
        name="category_id"
        defaultValue=""
      >
        <option value="">Sin categoría</option>
        {groups.map((g) => (
          <optgroup key={g.kind} label={g.label}>
            {g.options.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </optgroup>
        ))}
      </FormSelect>
    </div>
  );
}
