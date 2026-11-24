import { Button } from "@/components/ui/button";
import { Field, Select } from "@/components/ui/field";

// En el celular, la lista se elige con un desplegable y «Ver» (en la computadora, con el panel de la izquierda). Es un
// formulario común: no navega al recorrerlo con el teclado (ADR-0048) y sirve sin JavaScript.
export function ListPicker({
  value,
  options,
}: {
  value: string;
  options: { slug: string; label: string }[];
}) {
  return (
    <form
      action="/materias-primas/configuracion"
      method="get"
      className="flex items-end gap-2 desk:hidden"
    >
      <Field id="cfg-lista" label="Lista" className="min-w-0 flex-1">
        <Select name="lista" key={value} defaultValue={value}>
          {options.map((o) => (
            <option key={o.slug} value={o.slug}>
              {o.label}
            </option>
          ))}
        </Select>
      </Field>
      <Button type="submit" variant="outline">
        Ver
      </Button>
    </form>
  );
}
