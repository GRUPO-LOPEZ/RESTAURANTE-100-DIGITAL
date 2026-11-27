"use client";

import * as React from "react";
import Link from "next/link";
import { Trash2 } from "lucide-react";

import {
  correctPriceListAction,
  createPriceListAction,
  previewPriceListAction,
  readPriceListFileAction,
  supplierProductsAction,
  type CreatePriceListState,
  type PreviewRow,
} from "@/app/listas-de-precios/actions";
import { FileViewer } from "@/components/file-viewer";
import { FormNotice } from "@/components/form-notice";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { DateInput } from "@/components/ui/date-input";
import { Field, Input, Select } from "@/components/ui/field";
import { FileUpload } from "@/components/ui/file-upload";
import { Segmented } from "@/components/ui/segmented";
import type { ReadListResult } from "@/lib/imports/price-list-file";
import {
  LIST_FIELDS,
  LIST_FIELD_LABELS,
  rowsFromTable,
  type ColumnMap,
  type ImportCell,
  type ImportedRow,
  type ListField,
} from "@/lib/price-list-columns";
import {
  VAT_RATES,
  checkBadge,
  formatMoney,
  netListPrice,
  parseDecimal,
  perUseLabel,
  priceListItemSchema,
} from "@/lib/price-lists";

// Cargar una lista de precios (ADR-0052; importar y controlar, ADR-0071), en una pantalla sin scroll:
// - arriba, el proveedor, las fechas y «Subir Excel, CSV, PDF o foto». Un Excel, un CSV o un PDF hecho por computadora
//   se leen solos y se vuelcan en la planilla (se elige la hoja y, si hace falta, la columna de cada dato); una foto o
//   un PDF escaneado abren la pantalla dividida: el archivo a la izquierda, con zoom, y la planilla a la derecha;
// - la planilla compacta: 8 renglones que crecen solos, con el neto, el control contra la lista vigente (la variación,
//   resaltada si pasa el umbral de Dirección; «Revisar» si es 10 veces mayor o menor), el precio por unidad de uso y el
//   artículo reconocido o elegido a mano («Es…»). Los controles los calcula la base (purchasing.price_list_preview);
//   - abajo, la barra fija: cuántos renglones, cuántos para revisar, el motivo, Descartar y Cargar.
// Con `correct`, la misma pantalla corrige la vigente: crea la versión siguiente con motivo.

type Row = ImportedRow & { key: number; productId: string };

let next = 0;
const blank = (): Row => ({
  key: ++next,
  name: "",
  sku: "",
  list: "",
  b1: "",
  b2: "",
  perUnit: "",
  vat: "21",
  productId: "",
});
const isBlank = (r: Row) => !r.name.trim() && !r.sku.trim() && !r.list.trim();
// Siempre queda un renglón vacío al final (y al menos 8 en total): al llenar el último aparece otro.
function withTail(rows: Row[]): Row[] {
  const out = [...rows];
  while (out.length < 8 || !isBlank(out[out.length - 1]!)) out.push(blank());
  return out;
}
const fromImported = (r: ImportedRow, productId = ""): Row => ({ ...r, key: ++next, productId });

function toItem(r: Row) {
  return {
    name: r.name,
    sku: r.sku.trim() || undefined,
    purchase_product_id: r.productId || undefined,
    list_price: parseDecimal(r.list) ?? Number.NaN,
    bonus1_pct: parseDecimal(r.b1) ?? 0,
    bonus2_pct: parseDecimal(r.b2) ?? 0,
    bonus_per_unit_amount: parseDecimal(r.perUnit) ?? 0,
    vat_rate: Number(r.vat),
  };
}

// El campo de la planilla al que va el error de cada dato del esquema.
const FIELD_OF: Record<string, keyof ImportedRow> = {
  name: "name",
  sku: "sku",
  list_price: "list",
  bonus1_pct: "b1",
  bonus2_pct: "b2",
  bonus_per_unit_amount: "perUnit",
  vat_rate: "vat",
};

const NUMBER_FIELDS: { field: "list" | "b1" | "b2" | "perUnit"; label: string; width: string }[] = [
  { field: "list", label: "Precio de lista", width: "w-28" },
  { field: "b1", label: "Bonif. 1 %", width: "w-16" },
  { field: "b2", label: "Bonif. 2 %", width: "w-16" },
  { field: "perUnit", label: "Bonif. $", width: "w-20" },
];

type Imported = Extract<ReadListResult, { ok: true }>;

export function PriceListForm({
  suppliers,
  supplierId: initialSupplier,
  today,
  correct,
}: {
  suppliers: { id: string; name: string }[];
  supplierId?: string;
  today: string;
  correct?: {
    priceListId: string;
    supplierId: string;
    supplierName: string;
    receivedOn: string;
    validFrom: string;
    version: number;
    rows: (ImportedRow & { productId: string })[];
  };
}) {
  const [supplierId, setSupplierId] = React.useState(correct?.supplierId ?? initialSupplier ?? "");
  const [rows, setRows] = React.useState<Row[]>(() =>
    withTail((correct?.rows ?? []).map((r) => fromImported(r, r.productId))),
  );
  const [file, setFile] = React.useState<File | null>(null);
  const [imported, setImported] = React.useState<Imported | null>(null);
  const [split, setSplit] = React.useState<{ url: string; kind: "image" | "pdf" } | null>(null);
  const [reading, startReading] = React.useTransition();
  const [checks, setChecks] = React.useState<Map<number, PreviewRow>>(new Map());
  const [products, setProducts] = React.useState<
    { id: string; code: string; description: string }[]
  >([]);
  const [reason, setReason] = React.useState("");
  const [confirmReview, setConfirmReview] = React.useState(false);
  const [errors, setErrors] = React.useState<Record<string, string>>({});
  const [state, setState] = React.useState<CreatePriceListState>({});
  // Lo que pasó al leer el archivo: va arriba, con las columnas; la barra de abajo queda para guardar.
  const [readNote, setReadNote] = React.useState<CreatePriceListState>({});
  const [pending, startSaving] = React.useTransition();
  const formRef = React.useRef<HTMLFormElement>(null);

  const filled = rows.filter((r) => !isBlank(r));
  const dirty = filled.length > 0 || file !== null;
  useUnsavedWarning(dirty && !pending);

  // Los artículos del proveedor, para «Es…».
  React.useEffect(() => {
    let alive = true;
    if (!supplierId) return;
    void supplierProductsAction(supplierId).then((p) => alive && setProducts(p));
    return () => {
      alive = false;
    };
  }, [supplierId]);

  // Los controles de la base, un momento después de dejar de escribir.
  const itemsKey = JSON.stringify(filled.map(toItem));
  React.useEffect(() => {
    if (!supplierId || filled.length === 0) return;
    const keys = filled.map((r) => r.key);
    const items = filled
      .map(toItem)
      .map((i) => ({ ...i, list_price: Number.isFinite(i.list_price) ? i.list_price : undefined }));
    const timer = setTimeout(() => {
      void previewPriceListAction(supplierId, items).then((res) => {
        if (!res) return;
        setChecks(new Map(res.map((c) => [keys[c.line - 1] ?? -1, c])));
      });
    }, 500);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- itemsKey resume los renglones
  }, [supplierId, itemsKey]);

  // El archivo de la vista dividida se libera al cambiarlo o al salir.
  React.useEffect(() => () => (split ? URL.revokeObjectURL(split.url) : undefined), [split]);

  function update(key: number, patch: Partial<Row>) {
    setRows((all) => withTail(all.map((r) => (r.key === key ? { ...r, ...patch } : r))));
  }

  function read(chosen: File | null, sheet?: string) {
    setFile(chosen);
    setImported(null);
    setSplit(null);
    setState({});
    setReadNote({});
    if (!chosen) return;
    if (chosen.type.startsWith("image/")) {
      setSplit({ url: URL.createObjectURL(chosen), kind: "image" });
      return;
    }
    startReading(async () => {
      const data = new FormData();
      data.set("file", chosen);
      if (sheet) data.set("sheet", sheet);
      let res: ReadListResult;
      try {
        res = await readPriceListFileAction(data);
      } catch {
        setReadNote({ status: "bad", message: "No pudimos leer el archivo: probá de nuevo." });
        return;
      }
      if (res.ok) {
        setImported(res);
        setRows(withTail(res.rows.map((r) => fromImported(r))));
        setReadNote({
          status: res.truncated ? "warn" : "info",
          message:
            `Leímos ${res.rows.length === 1 ? "1 renglón" : `${res.rows.length} renglones`}` +
            (res.skipped > 0 ? `; salteamos ${res.skipped} (títulos o totales)` : "") +
            (res.truncated ? ". Pasaba de 500: el resto, en otra carga." : ". Revisalos."),
        });
      } else if (res.scanned) {
        setSplit({ url: URL.createObjectURL(chosen), kind: res.kind });
        setReadNote({ status: "info", message: res.message });
      } else setReadNote({ status: "bad", message: res.message });
    });
  }

  // Cambiar la columna de un dato vuelve a armar los renglones desde la tabla leída.
  function remap(field: ListField, column: string) {
    if (!imported) return;
    const map: ColumnMap = { ...imported.map };
    if (column === "") delete map[field];
    else map[field] = Number(column);
    const table: ImportCell[][] = [imported.header, ...imported.table];
    const out = rowsFromTable(table, 0, map);
    setImported({ ...imported, map });
    setRows(withTail(out.rows.map((r) => fromImported(r))));
  }

  function discard() {
    formRef.current?.reset();
    setRows(withTail((correct?.rows ?? []).map((r) => fromImported(r, r.productId))));
    setFile(null);
    setImported(null);
    setSplit(null);
    setErrors({});
    setState({});
    setReason("");
    setConfirmReview(false);
    setReadNote({});
  }

  const review = filled.filter((r) => checks.get(r.key)?.review).length;
  const over = filled.filter((r) => checks.get(r.key)?.over_threshold).length;

  function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const found: Record<string, string> = {};
    // El error de cada renglón, en el campo que corresponde (no solo en el artículo).
    for (const r of filled) {
      const parsed = priceListItemSchema.safeParse(toItem(r));
      if (!parsed.success) {
        const issue = parsed.error.issues[0];
        const field = FIELD_OF[String(issue?.path[0] ?? "")] ?? "name";
        found[`${r.key}`] = issue?.message ?? "Revisá el renglón.";
        found[`${r.key}-field`] = field;
      }
    }
    if (!supplierId) found.supplier_id = "Elegí el proveedor.";
    if (reason.trim().length < 3) found.reason = "Escribí el motivo (al menos 3 letras).";
    if (filled.length === 0) found.items = "Cargá al menos un renglón.";
    if (review > 0 && !confirmReview)
      found.confirm = "Confirmá que revisaste los precios marcados «Revisar».";
    setErrors(found);
    if (Object.keys(found).length > 0) {
      setState({ status: "bad", message: "Revisá los campos marcados." });
      return;
    }
    startSaving(async () => {
      try {
        if (correct) {
          const result = await correctPriceListAction({
            price_list_id: correct.priceListId,
            items: filled.map(toItem),
            reason,
            confirm_review: confirmReview,
          });
          setState(result);
          return;
        }
        data.set("supplier_id", supplierId);
        data.set("items", JSON.stringify(filled.map(toItem)));
        data.set("reason", reason);
        if (file) data.set("file", file);
        const result = await createPriceListAction({}, data);
        setState(result);
        if (result.fieldErrors) setErrors(result.fieldErrors);
        if (result.status === "ok" || result.status === "warn") {
          setRows(withTail([]));
          setFile(null);
          setImported(null);
          setSplit(null);
          setReason("");
          setConfirmReview(false);
          setReadNote({});
        }
      } catch (e) {
        if (e instanceof Error && e.message.includes("NEXT_REDIRECT")) throw e;
        setState({
          status: "bad",
          message: "No pudimos guardar la lista. Tus renglones siguen acá: probá de nuevo.",
        });
      }
    });
  }

  const productName = (id: string) => products.find((p) => p.id === id)?.description ?? "";

  const grid = (
    <section
      aria-label="Renglones de la lista"
      className="relative flex min-h-0 flex-col gap-2 overflow-auto rounded-md border border-line bg-surface p-3 desk:flex-[1_1_0px]"
    >
      <table className="w-full border-separate border-spacing-0 text-sm">
        <caption className="sr-only">Renglones de la lista</caption>
        <thead className="sticky top-0 z-10 bg-surface">
          <tr className="text-left text-xs font-medium text-ink-muted">
            <th scope="col" className="border-b border-line px-1 py-1.5 font-medium">
              Artículo (como viene)
            </th>
            <th scope="col" className="border-b border-line px-1 py-1.5 font-medium">
              Código
            </th>
            {NUMBER_FIELDS.map((f) => (
              <th
                key={f.field}
                scope="col"
                className="border-b border-line px-1 py-1.5 text-right font-medium"
              >
                {f.label}
              </th>
            ))}
            <th scope="col" className="border-b border-line px-1 py-1.5 font-medium">
              IVA
            </th>
            <th scope="col" className="border-b border-line px-1 py-1.5 text-right font-medium">
              Neto
            </th>
            <th scope="col" className="border-b border-line px-1 py-1.5 font-medium">
              Control y por unidad de uso
            </th>
            <th scope="col" className="border-b border-line px-1 py-1.5 font-medium">
              Es…
            </th>
            <th scope="col" className="border-b border-line px-1 py-1.5">
              <span className="sr-only">Quitar</span>
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r, index) => {
            const n = index + 1;
            const item = toItem(r);
            const net = Number.isFinite(item.list_price)
              ? netListPrice(
                  item.list_price,
                  item.bonus1_pct,
                  item.bonus2_pct,
                  item.bonus_per_unit_amount,
                )
              : null;
            const c = isBlank(r) ? undefined : checks.get(r.key);
            const badge = c
              ? checkBadge({
                  changePct: c.change_pct,
                  overThreshold: c.over_threshold,
                  review: c.review,
                  perUsePrice: c.per_use_price,
                  perUseUnit: c.per_use_unit,
                })
              : null;
            const error = errors[`${r.key}`];
            const errorField = errors[`${r.key}-field`];
            const errorId = `lp-error-${r.key}`;
            // El campo con el error lo dice con aria-invalid y apunta al texto del error (columna «Control»).
            const invalid = (f: string) =>
              error && errorField === f
                ? { "aria-invalid": true as const, "aria-describedby": errorId }
                : {};
            const cell = "border-b border-line px-1 py-1 align-middle";
            return (
              <tr key={r.key} data-blank={isBlank(r) || undefined}>
                <td className={cell}>
                  <Input
                    aria-label={`Artículo, renglón ${n}`}
                    {...invalid("name")}
                    value={r.name}
                    maxLength={200}
                    onChange={(e) => update(r.key, { name: e.target.value })}
                    className="min-w-48 desk:min-h-8"
                  />
                </td>
                <td className={cell}>
                  <Input
                    aria-label={`Código, renglón ${n}`}
                    value={r.sku}
                    maxLength={40}
                    onChange={(e) => update(r.key, { sku: e.target.value })}
                    className="w-24 desk:min-h-8"
                  />
                </td>
                {NUMBER_FIELDS.map((f) => (
                  <td key={f.field} className={cell}>
                    <Input
                      aria-label={`${f.label}, renglón ${n}`}
                      {...invalid(f.field)}
                      inputMode="decimal"
                      value={r[f.field]}
                      maxLength={20}
                      onChange={(e) => update(r.key, { [f.field]: e.target.value })}
                      className={`${f.width} text-right tabular-nums desk:min-h-8`}
                    />
                  </td>
                ))}
                <td className={cell}>
                  <Select
                    aria-label={`IVA, renglón ${n}`}
                    {...invalid("vat")}
                    value={r.vat}
                    onChange={(e) => update(r.key, { vat: e.target.value })}
                    className="w-28 desk:min-h-8"
                  >
                    {VAT_RATES.map((v) => (
                      <option key={v} value={String(v)}>
                        {v.toLocaleString("es-AR")} %
                      </option>
                    ))}
                  </Select>
                </td>
                <td className={`${cell} text-right whitespace-nowrap tabular-nums`}>
                  {net === null ? "—" : formatMoney(net)}
                </td>
                <td className={cell}>
                  {error ? (
                    <p id={errorId} className="max-w-56 text-xs text-bad-ink">
                      Error: {error}
                    </p>
                  ) : (
                    <span className="flex flex-col items-start gap-0.5">
                      {badge ? <Badge status={badge.status}>{badge.label}</Badge> : null}
                      {c ? (
                        <span className="text-xs whitespace-nowrap text-ink tabular-nums">
                          {perUseLabel(c.per_use_price, c.per_use_unit)}
                        </span>
                      ) : null}
                    </span>
                  )}
                </td>
                <td className={cell}>
                  {isBlank(r) ? null : (
                    <div className="flex flex-col gap-0.5">
                      <Select
                        aria-label={`Es…, renglón ${n}`}
                        value={r.productId}
                        onChange={(e) => update(r.key, { productId: e.target.value })}
                        className="w-40 desk:min-h-8"
                      >
                        <option value="">
                          {c?.purchase_product_id && !r.productId ? "Reconocido" : "Sin reconocer"}
                        </option>
                        {products.map((p) => (
                          <option key={p.id} value={p.id}>
                            {p.description}
                          </option>
                        ))}
                      </Select>
                      {c?.purchase_product_id && !r.productId ? (
                        <span className="max-w-40 text-xs text-ink">
                          {c.product_name || productName(c.purchase_product_id)}
                        </span>
                      ) : !r.productId ? (
                        <span className="text-xs text-ink">Va a la cola de mapeo</span>
                      ) : null}
                    </div>
                  )}
                </td>
                <td className={cell}>
                  {isBlank(r) ? null : (
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      className="desk:size-8"
                      aria-label={`Quitar el renglón ${n}`}
                      onClick={() => setRows((all) => withTail(all.filter((x) => x.key !== r.key)))}
                    >
                      <Trash2 aria-hidden="true" />
                    </Button>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      <Button
        type="button"
        variant="outline"
        className="self-start"
        onClick={() => setRows((all) => [...all, blank()])}
      >
        + Agregar renglón
      </Button>
    </section>
  );

  return (
    <form
      ref={formRef}
      onSubmit={submit}
      noValidate
      className="flex flex-col gap-3 desk:min-h-0 desk:flex-[1_1_0px]"
    >
      {correct ? null : (
        <div className="grid items-end gap-3 desk:grid-cols-[2fr_10rem_10rem_3fr]">
          <Field id="lp-supplier_id" label="Proveedor" error={errors.supplier_id}>
            <Select value={supplierId} onChange={(e) => setSupplierId(e.target.value)}>
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
          <Field id="lp-received_on" label="Llegó el">
            <DateInput name="received_on" defaultValue={today} max={today} />
          </Field>
          <Field id="lp-valid_from" label="Vale desde">
            <DateInput name="valid_from" defaultValue={today} />
          </Field>
          <Field
            id="lp-file"
            label="La lista del proveedor"
            hint="Excel, CSV o PDF se leen solos. Hasta 3,5 MB."
          >
            <FileUpload
              accept=".xlsx,.csv,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/pdf,image/jpeg,image/png,image/webp"
              label={reading ? "Leyendo…" : "Subir Excel, CSV, PDF o foto"}
              onFile={(f) => read(f)}
            />
          </Field>
        </div>
      )}

      {imported ? (
        <div className="flex flex-wrap items-end gap-3 rounded-md border border-line bg-surface px-3 py-2">
          {imported.sheets.length > 1 ? (
            imported.sheets.length <= 5 ? (
              <Segmented
                name="lp-hoja"
                legend="Hoja"
                options={imported.sheets.map((s) => ({ value: s, label: s }))}
                value={imported.sheet ?? ""}
                onChange={(v) => read(file, v)}
                compact
              />
            ) : (
              <Field id="lp-hoja" label="Hoja" className="w-48">
                <Select value={imported.sheet ?? ""} onChange={(e) => read(file, e.target.value)}>
                  {imported.sheets.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </Select>
              </Field>
            )
          ) : null}
          {/* La columna de cada dato: la reconocimos sola; se cambia si el proveedor la llama de otra forma. */}
          {LIST_FIELDS.map((f) => (
            <Field key={f} id={`lp-col-${f}`} label={LIST_FIELD_LABELS[f]} className="w-36">
              <Select
                value={imported.map[f] === undefined ? "" : String(imported.map[f])}
                onChange={(e) => remap(f, e.target.value)}
                className="desk:min-h-8"
              >
                <option value="">—</option>
                {imported.header.map((h, i) => (
                  <option key={i} value={String(i)}>
                    {h || `Columna ${i + 1}`}
                  </option>
                ))}
              </Select>
            </Field>
          ))}
        </div>
      ) : null}
      {readNote.message ? <FormNotice state={readNote} /> : null}

      {split ? (
        <div className="grid gap-3 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[2fr_3fr] desk:grid-rows-[minmax(0,1fr)]">
          <div className="flex min-h-80 flex-col desk:min-h-0">
            <FileViewer url={split.url} kind={split.kind} name={file?.name ?? "archivo"} />
          </div>
          {grid}
        </div>
      ) : (
        grid
      )}
      {errors.items ? (
        <p role="alert" className="text-sm text-bad-ink">
          {errors.items}
        </p>
      ) : null}

      {/* Barra fija abajo: cuántos renglones, los controles, el motivo, Descartar y Cargar. */}
      <div className="sticky bottom-[calc(var(--spacing-bottom-nav)+env(safe-area-inset-bottom))] z-40 flex flex-col gap-2 border-t border-line bg-surface px-4 py-2 desk:bottom-0 desk:flex-row desk:items-end">
        <div className="flex flex-col text-sm text-ink tabular-nums desk:pb-2" aria-live="polite">
          <span>{filled.length === 1 ? "1 renglón" : `${filled.length} renglones`}</span>
          {review > 0 || over > 0 ? (
            <span className="flex gap-1">
              {review > 0 ? (
                <Badge status="bad">
                  {review === 1 ? "1 para revisar" : `${review} para revisar`}
                </Badge>
              ) : null}
              {over > 0 ? (
                <Badge status="warn">
                  {over === 1 ? "1 sobre el umbral" : `${over} sobre el umbral`}
                </Badge>
              ) : null}
            </span>
          ) : null}
        </div>
        {review > 0 ? (
          <div className="flex flex-col desk:pb-2">
            <Checkbox
              id="lp-confirm"
              label="Revisé los precios para revisar"
              checked={confirmReview}
              onChange={(e) => setConfirmReview(e.target.checked)}
            />
            {errors.confirm ? <span className="text-xs text-bad-ink">{errors.confirm}</span> : null}
          </div>
        ) : null}
        <Field
          id="lp-reason"
          label="Motivo"
          error={errors.reason}
          className="desk:min-w-72 desk:flex-1"
        >
          <Input
            value={reason}
            maxLength={500}
            placeholder="Queda en el historial"
            onChange={(e) => setReason(e.target.value)}
          />
        </Field>
        <div className="flex flex-col gap-2 desk:flex-row desk:items-end">
          <div className="min-w-0 desk:max-w-96">
            <FormNotice state={state} />
          </div>
          {state.status === "ok" && state.priceListId ? (
            <Link
              href={`/listas-de-precios/${state.priceListId}`}
              className="inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-control"
            >
              Ver la lista cargada
            </Link>
          ) : null}
          <Button type="button" variant="outline" disabled={pending || !dirty} onClick={discard}>
            Descartar
          </Button>
          <Button type="submit" disabled={pending || reading}>
            {pending
              ? "Guardando…"
              : correct
                ? `Guardar la versión ${correct.version + 1}`
                : "Cargar lista"}
          </Button>
        </div>
      </div>
    </form>
  );
}
