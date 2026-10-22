import type { FieldErrors, FieldValues, Resolver } from "react-hook-form";
import type { z } from "zod";

import { fieldErrors } from "@/lib/forms/schemas";

// Adaptador de Zod para React Hook Form (ADR-0016). Reemplaza a @hookform/resolvers, que pide
// dependencias que chocan con las del proyecto: valida con el mismo esquema que usa el servidor y
// devuelve un error por campo.
export function zodResolver(schema: z.ZodType): Resolver<FieldValues> {
  return async (values) => {
    const parsed = schema.safeParse(values);
    if (parsed.success) return { values: values, errors: {} };
    const errors: FieldErrors<FieldValues> = {};
    for (const [name, message] of Object.entries(fieldErrors(parsed.error))) {
      errors[name] = { type: "validate", message };
    }
    return { values: {}, errors };
  };
}
