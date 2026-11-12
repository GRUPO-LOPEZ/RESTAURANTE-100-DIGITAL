"use client";

import { useWatch } from "react-hook-form";

import { previewIngredientCodeAction } from "@/app/materias-primas/actions";
import { CodePreview } from "@/components/code-preview";
import { FormInput, FormSelect } from "@/components/ui/form";
import { baseUnitNote, type Dimension } from "@/lib/codes";

type UnitOption = { code: string; label: string; dimension: Dimension };

const UNIT_GROUPS: [Dimension, string][] = [
  ["mass", "Peso"],
  ["volume", "Volumen"],
  ["count", "Unidades"],
];

// Rubro, código, nombre y unidad del alta de una materia prima, en el orden del pedido de Soy (ADR-0041). El código
// sale del rubro; la unidad se elige de la lista completa del catálogo (sin envases) y la base guarda la de su tipo
// (g, ml o unidad), así que se avisa en qué la calculan las recetas.
export function NewIngredientFields({
  categories,
  units,
  columns,
}: {
  categories: { id: string; label: string }[];
  units: UnitOption[];
  columns: string;
}) {
  const unit = useWatch({ name: "recipe_unit" }) as string | undefined;
  const dimension = units.find((u) => u.code === unit)?.dimension ?? null;
  return (
    <>
      <div className={`${columns} items-end`}>
        <FormSelect
          id="mp-alta-categoria"
          label="Rubro"
          name="category_id"
          required
          defaultValue=""
        >
          <option value="" disabled>
            Elegí el rubro
          </option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.label}
            </option>
          ))}
        </FormSelect>
        <CodePreview
          id="mp-alta-codigo"
          fields={["category_id"]}
          explanation="Lo arma el sistema con el rubro y el número que sigue. Se confirma al crear y no cambia nunca."
          preview={(category) => previewIngredientCodeAction(category)}
        />
      </div>
      <div className={columns}>
        <FormInput id="mp-alta-nombre" label="Nombre" name="name" required maxLength={120} />
        <FormSelect
          id="mp-alta-unidad"
          label="Se usa en recetas en"
          hint={baseUnitNote(dimension) ?? "Peso, volumen o cantidad."}
          name="recipe_unit"
          required
          defaultValue=""
        >
          <option value="" disabled>
            Elegí la unidad
          </option>
          {UNIT_GROUPS.map(([d, label]) => {
            const list = units.filter((u) => u.dimension === d);
            return list.length === 0 ? null : (
              <optgroup key={d} label={label}>
                {list.map((u) => (
                  <option key={u.code} value={u.code}>
                    {u.label}
                  </option>
                ))}
              </optgroup>
            );
          })}
        </FormSelect>
      </div>
    </>
  );
}
