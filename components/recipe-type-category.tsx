"use client";

import * as React from "react";
import { useFormContext, useWatch } from "react-hook-form";

import { previewRecipeCodeAction } from "@/app/recetas/actions";
import { CodePreview } from "@/components/code-preview";
import { FormSelect } from "@/components/ui/form";
import { SegmentedField } from "@/components/ui/segmented-field";
import { NEW_RECIPE_TYPES, RECIPE_TYPE_LABELS, type NewRecipeType } from "@/lib/recipe-format";

type Option = { id: string; label: string; kind: "subrecipe" | "menu" };

// Tipo, rubro y código del alta de una receta (ADR-0038 y ADR-0041), en ese orden. El tipo son dos botones a la
// vista (Plato | Preparación); el rubro ofrece solo los de su clase (un plato, los de menú; una preparación, los de
// sub-recetas) y es obligatorio, porque de él sale el código. La base vuelve a controlarlo todo al crear.
export function RecipeTypeCategory({ categories }: { categories: Option[] }) {
  const form = useFormContext();
  const type = useWatch({ name: "type" }) as NewRecipeType | "" | undefined;
  const wanted = !type ? null : type === "dish" ? "menu" : "subrecipe";
  const options = React.useMemo(
    () => (wanted ? categories.filter((c) => c.kind === wanted) : []),
    [categories, wanted],
  );

  // Al cambiar el tipo, un rubro de la otra clase deja de valer.
  const categoryId = useWatch({ name: "category_id" }) as string | undefined;
  React.useEffect(() => {
    if (categoryId && !options.some((c) => c.id === categoryId)) form.setValue("category_id", "");
  }, [categoryId, options, form]);

  return (
    <>
      <SegmentedField
        id="rec-alta-tipo"
        name="type"
        label="Tipo"
        options={NEW_RECIPE_TYPES.map((t) => ({ value: t, label: RECIPE_TYPE_LABELS[t] }))}
      />
      <div className="grid items-end gap-4 sm:grid-cols-2">
        <FormSelect
          id="rec-alta-categoria"
          label="Rubro"
          hint={wanted ? undefined : "Elegí primero el tipo: cada tipo tiene sus rubros."}
          name="category_id"
          required
          disabled={!wanted}
          defaultValue=""
        >
          <option value="" disabled>
            {wanted ? "Elegí el rubro" : "Primero el tipo"}
          </option>
          {options.map((c) => (
            <option key={c.id} value={c.id}>
              {c.label}
            </option>
          ))}
        </FormSelect>
        <CodePreview
          id="rec-alta-codigo"
          fields={["category_id", "type"]}
          explanation="Lo arma el sistema con el tipo, el rubro y el número que sigue. Se confirma al crear y no cambia nunca."
          preview={(category, recipeType) =>
            previewRecipeCodeAction(category, recipeType as NewRecipeType)
          }
        />
      </div>
    </>
  );
}
