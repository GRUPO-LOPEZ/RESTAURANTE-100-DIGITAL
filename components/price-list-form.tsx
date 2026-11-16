"use client";

import * as React from "react";
import Link from "next/link";
import { Plus, Trash2 } from "lucide-react";

import { createPriceListAction, type CreatePriceListState } from "@/app/listas-de-precios/actions";
import { FormNotice } from "@/components/form-notice";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import { Button } from "@/components/ui/button";
import { Field, Input, Select } from "@/components/ui/field";
import {
  VAT_RATES,
  formatMoney,
  netListPrice,
  parseDecimal,
  priceListItemSchema,
} from "@/lib/price-lists";

// Cargar una lista de precios (ADR-0052): proveedor, fechas, el archivo (opcional) y una grilla con un renglón por
// artículo, como viene en la lista del proveedor. Se valida al enviar con el mismo esquema que el servidor. Lo que el
// sistema no reconoce va a la cola de mapeo (lo decide la base) y se le avisa al chef.

type Row = {
  key: number;
  name: string;
  sku: string;
  list: string;
  b1: string;
  b2: string;
  perUnit: string;
  vat: string;
};

// El mismo tope que la acción de servidor (que acepta hasta 4 MB por envío).
const FILE_MAX_BYTES = 3.5 * 1024 * 1024;

let next = 0;
const emptyRow = (): Row => ({
  key: ++next,
  name: "",
  sku: "",
  list: "",
  b1: "",
  b2: "",
  perUnit: "",
  vat: "21",
});
const isBlank = (r: Row) => !r.name.trim() && !r.sku.trim() && !r.list.trim();

function toItem(r: Row) {
  return {
    name: r.name,
    sku: r.sku.trim() || undefined,
    list_price: parseDecimal(r.list) ?? Number.NaN,
    bonus1_pct: parseDecimal(r.b1) ?? 0,
    bonus2_pct: parseDecimal(r.b2) ?? 0,
    bonus_per_unit_amount: parseDecimal(r.perUnit) ?? 0,
    vat_rate: Number(r.vat),
  };
}

const COLUMNS = [
  ["name", "Artículo (como viene)"],
  ["sku", "Código"],
  ["list", "Precio de lista ($)"],
  ["b1", "Bonif. 1 (%)"],
  ["b2", "Bonif. 2 (%)"],
  ["perUnit", "Bonif. ($ por unidad)"],
  ["vat", "IVA"],
] as const;
const FIELD_OF: Record<string, keyof Row> = {
  name: "name",
  sku: "sku",
  list_price: "list",
  bonus1_pct: "b1",
  bonus2_pct: "b2",
  bonus_per_unit_amount: "perUnit",
  vat_rate: "vat",
};

export function PriceListForm({
  suppliers,
  supplierId,
  today,
}: {
  suppliers: { id: string; name: string }[];
  supplierId?: string;
  today: string;
}) {
  const [rows, setRows] = React.useState<Row[]>(() => [emptyRow(), emptyRow(), emptyRow()]);
  const [cellErrors, setCellErrors] = React.useState<Record<string, string>>({});
  const [state, setState] = React.useState<CreatePriceListState>({});
  const [pending, startTransition] = React.useTransition();
  const formRef = React.useRef<HTMLFormElement>(null);

  function update(key: number, field: keyof Row, value: string) {
    setRows((all) => all.map((r) => (r.key === key ? { ...r, [field]: value } : r)));
  }

  // Hay algo escrito: se pregunta antes de irse (design.md, tipo B).
  const dirty = rows.some((r) => !isBlank(r));
  useUnsavedWarning(dirty && !pending);

  // Los errores de un renglón, con el mismo esquema que el servidor.
  function rowErrors(r: Row): Record<string, string> {
    const errors: Record<string, string> = {};
    if (isBlank(r)) return errors;
    const parsed = priceListItemSchema.safeParse(toItem(r));
    if (!parsed.success)
      for (const issue of parsed.error.issues) {
        const field = FIELD_OF[String(issue.path[0])] ?? "list";
        errors[`${r.key}-${field}`] ??= issue.message;
      }
    return errors;
  }

  // Validación al salir del renglón: se marcan sus celdas sin tocar las de los demás.
  function validateRow(r: Row) {
    setCellErrors((all) => {
      const kept = Object.fromEntries(
        Object.entries(all).filter(([k]) => !k.startsWith(`${r.key}-`)),
      );
      return { ...kept, ...rowErrors(r) };
    });
  }

  function discard() {
    formRef.current?.reset();
    setRows([emptyRow(), emptyRow(), emptyRow()]);
    setCellErrors({});
    setState({});
  }

  function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const filled = rows.filter((r) => !isBlank(r));
    const errors: Record<string, string> = {};
    filled.forEach((r) => Object.assign(errors, rowErrors(r)));
    // El archivo se controla acá: uno más pesado que lo que acepta el servidor no llegaría a la acción.
    const file = data.get("file");
    if (file instanceof File && file.size > FILE_MAX_BYTES)
      errors.file = "El archivo pesa más de 3,5 MB. Probá con una foto más liviana.";
    if (!data.get("supplier_id")) errors.supplier_id = "Elegí el proveedor.";
    if (String(data.get("reason") ?? "").trim().length < 3)
      errors.reason = "Escribí el motivo (al menos 3 letras).";
    if (filled.length === 0) errors.items = "Cargá al menos un renglón.";
    setCellErrors(errors);
    const firstKey = Object.keys(errors)[0];
    if (firstKey) {
      setState({ status: "bad", message: "Revisá los campos marcados." });
      document.getElementById(`lp-${firstKey}`)?.focus();
      return;
    }
    data.set("items", JSON.stringify(filled.map(toItem)));
    startTransition(async () => {
      // Si se corta la red o el servidor no responde, los renglones quedan como estaban.
      let result: CreatePriceListState;
      try {
        result = await createPriceListAction({}, data);
      } catch {
        setState({
          status: "bad",
          message: "No pudimos cargar la lista. Tus renglones siguen acá: probá de nuevo.",
        });
        return;
      }
      setState(result);
      if (result.fieldErrors) setCellErrors(result.fieldErrors);
      if (result.status === "ok" || result.status === "warn") {
        formRef.current?.reset();
        setRows([emptyRow(), emptyRow(), emptyRow()]);
      }
    });
  }

  const err = (id: string) => cellErrors[id];
  return (
    <form ref={formRef} onSubmit={submit} noValidate className="flex flex-col gap-4">
      <div className="grid gap-4 desk:grid-cols-[2fr_1fr_1fr_2fr]">
        <Field id="lp-supplier_id" label="Proveedor" error={err("supplier_id")}>
          <Select name="supplier_id" defaultValue={supplierId ?? ""}>
            <option value="" disabled>
              Elegí el proveedor
            </option>
            {suppliers.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field id="lp-received_on" label="Llegó el" error={err("received_on")}>
          <Input type="date" name="received_on" defaultValue={today} max={today} />
        </Field>
        <Field id="lp-valid_from" label="Vale desde" error={err("valid_from")}>
          <Input type="date" name="valid_from" defaultValue={today} />
        </Field>
        <Field
          id="lp-file"
          label="Archivo de la lista"
          hint="Opcional: foto o PDF, hasta 3,5 MB."
          error={err("file")}
        >
          <Input type="file" name="file" accept="image/jpeg,image/png,image/webp,application/pdf" />
        </Field>
      </div>

      <div className="relative overflow-x-auto">
        <table className="w-full border-collapse text-sm">
          <caption className="sr-only">Renglones de la lista</caption>
          <thead>
            <tr className="border-b border-line text-left text-xs font-medium text-ink-muted">
              {COLUMNS.map(([key, label]) => (
                <th key={key} scope="col" className="px-1 py-2 font-medium">
                  {label}
                </th>
              ))}
              <th scope="col" className="px-1 py-2 text-right font-medium">
                Neto
              </th>
              <th scope="col" className="px-1 py-2">
                <span className="sr-only">Quitar</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, index) => {
              const item = toItem(r);
              const net = Number.isFinite(item.list_price)
                ? netListPrice(
                    item.list_price,
                    item.bonus1_pct,
                    item.bonus2_pct,
                    item.bonus_per_unit_amount,
                  )
                : null;
              return (
                <tr
                  key={r.key}
                  className="border-b border-line align-top"
                  onBlur={(e) => {
                    // Al salir del renglón (no al pasar de una celda a otra del mismo).
                    if (!e.currentTarget.contains(e.relatedTarget as Node | null)) validateRow(r);
                  }}
                >
                  {COLUMNS.map(([field, label]) => {
                    const id = `lp-${r.key}-${field}`;
                    const error = err(`${r.key}-${field}`);
                    const common = {
                      id,
                      "aria-label": `${label}, renglón ${index + 1}`,
                      "aria-invalid": error ? true : undefined,
                      "aria-describedby": error ? `${id}-error` : undefined,
                    };
                    return (
                      <td key={field} className="px-1 py-1">
                        {field === "vat" ? (
                          <Select
                            {...common}
                            value={r.vat}
                            onChange={(e) => update(r.key, "vat", e.target.value)}
                            className="w-28"
                          >
                            {VAT_RATES.map((v) => (
                              <option key={v} value={String(v)}>
                                {v.toLocaleString("es-AR")} %
                              </option>
                            ))}
                          </Select>
                        ) : (
                          <Input
                            {...common}
                            value={r[field]}
                            inputMode={field === "name" || field === "sku" ? undefined : "decimal"}
                            maxLength={field === "name" ? 200 : 40}
                            onChange={(e) => update(r.key, field, e.target.value)}
                            className={
                              field === "name"
                                ? "min-w-56"
                                : field === "sku"
                                  ? "w-28"
                                  : "w-28 text-right tabular-nums"
                            }
                          />
                        )}
                        {error ? (
                          <p id={`${id}-error`} className="mt-1 text-xs text-bad-ink">
                            {error}
                          </p>
                        ) : null}
                      </td>
                    );
                  })}
                  <td className="px-1 py-1 text-right align-middle tabular-nums">
                    {net === null ? "—" : formatMoney(net)}
                  </td>
                  <td className="px-1 py-1 align-middle">
                    <Button
                      type="button"
                      variant="outline"
                      aria-label={`Quitar el renglón ${index + 1}`}
                      disabled={rows.length === 1}
                      onClick={() => setRows((all) => all.filter((x) => x.key !== r.key))}
                    >
                      <Trash2 aria-hidden="true" className="size-4" />
                    </Button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {cellErrors.items ? (
        <p id="lp-items" tabIndex={-1} role="alert" className="text-sm text-bad-ink">
          {cellErrors.items}
        </p>
      ) : null}
      <div>
        <Button
          type="button"
          variant="outline"
          onClick={() => setRows((all) => [...all, emptyRow()])}
        >
          <Plus aria-hidden="true" className="size-4" />
          Agregar renglón
        </Button>
      </div>
      {state.status === "ok" && state.priceListId ? (
        <Link
          href={`/listas-de-precios/${state.priceListId}`}
          className="text-sm text-primary underline-offset-4 hover:underline"
        >
          Ver la lista cargada
        </Link>
      ) : null}

      {/* Barra fija abajo, como en las fichas: cuántos renglones, el motivo, Descartar y Cargar lista. */}
      <div className="sticky bottom-0 z-10 -mx-4 flex flex-col gap-3 border-t border-line bg-surface px-4 py-3 desk:flex-row desk:items-end">
        <p className="text-sm text-ink tabular-nums desk:pb-2" aria-live="polite">
          {rows.filter((r) => !isBlank(r)).length === 1
            ? "1 renglón"
            : `${rows.filter((r) => !isBlank(r)).length} renglones`}
        </p>
        <Field
          id="lp-reason"
          label="Motivo"
          error={err("reason")}
          className="desk:min-w-80 desk:flex-1"
        >
          <Input name="reason" maxLength={500} placeholder="Queda en el historial" />
        </Field>
        <div className="flex flex-col gap-2 desk:flex-row">
          <FormNotice state={state} />
          <Button type="button" variant="outline" disabled={pending || !dirty} onClick={discard}>
            Descartar
          </Button>
          <Button type="submit" disabled={pending}>
            {pending ? "Cargando…" : "Cargar lista"}
          </Button>
        </div>
      </div>
    </form>
  );
}
