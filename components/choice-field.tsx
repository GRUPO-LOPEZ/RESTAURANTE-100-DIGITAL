"use client";

import { FormSelect } from "@/components/ui/form";
import { SegmentedField } from "@/components/ui/segmented-field";
import { CHOICE_MAX } from "@/lib/price-proposal";

// Una elección de un formulario: hasta 5 opciones, botones a la vista; más, un desplegable (edición directa, ADR-0039).
export function ChoiceField({
  id,
  name,
  label,
  options,
  defaultValue = "",
  hint,
  placeholder,
}: {
  id: string;
  name: string;
  label: string;
  options: { value: string; label: string }[];
  defaultValue?: string;
  hint?: string;
  // Lo que dice el desplegable sin elegir.
  placeholder: string;
}) {
  if (options.length <= CHOICE_MAX)
    return (
      <SegmentedField
        id={id}
        name={name}
        label={label}
        options={options}
        defaultValue={defaultValue || undefined}
        hint={hint}
      />
    );
  return (
    <FormSelect id={id} name={name} label={label} hint={hint} required defaultValue={defaultValue}>
      <option value="" disabled>
        {placeholder}
      </option>
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </FormSelect>
  );
}
