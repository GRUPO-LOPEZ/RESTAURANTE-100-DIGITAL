"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useFormContext } from "react-hook-form";

import { previewPriceAction, proposePriceAction } from "@/app/materias-primas/actions";
import { ActionForm } from "@/components/action-form";
import { ChoiceField } from "@/components/choice-field";
import { MoreData } from "@/components/more-data";
import { Button } from "@/components/ui/button";
import { schemas } from "@/lib/forms/schemas";
import { FormInput, FormSelect, FormTextarea, FormDate } from "@/components/ui/form";
import { ToggleField } from "@/components/ui/toggle-field";
import {
  VAT_RATES,
  approversText,
  previewText,
  proposalSummary,
  type PricePreview,
  type ProposalProduct,
} from "@/lib/price-proposal";
import { cn } from "@/lib/utils";

// «Proponer precio» (pedido de Soy, ADR-0067): cinco datos, el resultado mientras se completa y el resto en «Más datos».
// El resultado lo calcula la base con la misma cuenta de la propuesta; lo que vale es lo que se guarda al proponer.
export function PriceProposal({
  ingredientId,
  products,
  places,
  suppliers,
  today,
}: {
  ingredientId: string;
  products: ProposalProduct[];
  places: { value: string; label: string }[];
  suppliers: { id: string; name: string }[];
  // AAAA-MM-DD, en la Argentina.
  today: string;
}) {
  return (
    <ActionForm
      action={proposePriceAction}
      schema="priceProposal"
      submitLabel="Proponer precio"
      pendingLabel="Proponiendo…"
      stickySubmit
      className="flex flex-1 flex-col gap-4"
    >
      <input type="hidden" name="ingredientId" value={ingredientId} />
      <Fields products={products} places={places} suppliers={suppliers} today={today} />
    </ActionForm>
  );
}

type Values = Record<string, string>;

const MORE = ["discount_amount", "document_type", "vat_rate", "supplier_id", "source", "notes"];

function Fields({
  products,
  places,
  suppliers,
  today,
}: {
  products: ProposalProduct[];
  places: { value: string; label: string }[];
  suppliers: { id: string; name: string }[];
  today: string;
}) {
  const { setValue, formState } = useFormContext();
  const only = products.length === 1 ? products[0] : undefined;
  const root = useRef<HTMLDivElement>(null);
  const [values, setValues] = useState<Values>({});
  const [includesVat, setIncludesVat] = useState(true);
  const [changeDate, setChangeDate] = useState(false);

  // Lo que tiene el formulario ahora (también los campos ocultos): de ahí salen el resumen y la vista previa.
  const read = useCallback(() => {
    const form = root.current?.closest("form");
    if (!form) return;
    const next: Values = {};
    for (const [key, value] of new FormData(form).entries())
      if (typeof value === "string") next[key] = value;
    setValues(next);
  }, []);
  useEffect(() => {
    const frame = requestAnimationFrame(read);
    return () => cancelAnimationFrame(frame);
  }, [read, includesVat, changeDate, formState.isSubmitSuccessful]);

  // Al elegir un producto, su alícuota y su proveedor.
  const product = products.find((p) => p.id === values.product_id) ?? only;
  const productId = product?.id;
  const applied = useRef<string | undefined>(only?.id);
  useEffect(() => {
    if (!product) {
      // El formulario se limpió: si se vuelve a elegir el mismo, se completa otra vez.
      applied.current = undefined;
      return;
    }
    if (applied.current === product.id) return;
    applied.current = product.id;
    setValue("vat_rate", product.vatRate);
    setValue("supplier_id", product.supplierId);
    const frame = requestAnimationFrame(read);
    return () => cancelAnimationFrame(frame);
  }, [product, setValue, read]);

  // Se envió bien y el formulario se limpió: la fecha vuelve a «hoy» y se leen los valores de nuevo.
  useEffect(() => {
    const form = root.current?.closest("form");
    if (!form) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const back = () => {
      timer = setTimeout(() => {
        setChangeDate(false);
        read();
      });
    };
    form.addEventListener("reset", back);
    return () => {
      clearTimeout(timer);
      form.removeEventListener("reset", back);
    };
  }, [read]);

  const invoice = (values.document_type ?? "invoice") !== "no_invoice";
  const validFrom = values.valid_from || today;
  const dateOpen = changeDate || formState.errors.valid_from !== undefined;
  const supplier = suppliers.find((s) => s.id === values.supplier_id)?.name ?? null;
  return (
    <div ref={root} onInput={read} onChange={read} className="flex flex-col gap-4">
      <ChoiceField
        id="precio-producto"
        name="product_id"
        label="Qué producto"
        options={products.map((p) => ({ value: p.id, label: p.label }))}
        defaultValue={only?.id}
        placeholder="Elegí el producto"
      />
      <div className="grid items-start gap-4 sm:grid-cols-2">
        <FormInput
          id="precio-envase"
          label={product ? `Precio por ${product.packageUnit} ($)` : "Precio del envase ($)"}
          name="package_price"
          required
          inputMode="decimal"
          autoComplete="off"
          className="[&_input]:text-xl [&_input]:font-semibold [&_input]:tabular-nums"
        />
        {/* Sin factura, no aplica: sigue en el formulario, pero no se ve ni cuenta. */}
        <ToggleField
          id="precio-incluye-iva"
          name="price_includes_vat"
          label="¿Incluye IVA?"
          defaultValue
          value={includesVat}
          onChange={setIncludesVat}
          className={cn("min-h-touch sm:mt-7", invoice ? undefined : "hidden")}
        />
      </div>
      <ChoiceField
        id="precio-lugar"
        name="place"
        label="Para quién vale"
        hint="Un local sin precio propio usa el de su marca, y si no, el del grupo."
        options={places}
        defaultValue={places.length === 1 ? places[0]?.value : ""}
        placeholder="Elegí para quién vale"
      />
      <div>
        {dateOpen ? null : (
          <p className="flex flex-wrap items-center gap-x-2 text-base text-ink">
            Desde {validFrom === today ? "hoy, " : "el "}
            {validFrom.split("-").reverse().join("/")}
            <Button
              type="button"
              variant="link"
              size="sm"
              className="px-0"
              onClick={() => {
                setChangeDate(true);
                requestAnimationFrame(() => document.getElementById("precio-desde")?.focus());
              }}
            >
              Cambiar<span className="sr-only"> la fecha</span>
            </Button>
          </p>
        )}
        <div className={dateOpen ? undefined : "hidden"}>
          <FormDate
            id="precio-desde"
            label="Vale desde"
            name="valid_from"
            required
            defaultValue={today}
          />
        </div>
      </div>
      <Preview key={productId ?? "ninguno"} values={values} invoice={invoice} />
      <MoreData
        names={MORE}
        summary={proposalSummary({
          invoice,
          vatRate: values.vat_rate ?? only?.vatRate ?? "21",
          supplier,
          discount: values.discount_amount ?? "",
          testValue: values.source === "test_value",
          notes: values.notes ?? "",
        })}
      >
        <div className="grid gap-4 sm:grid-cols-2">
          <FormInput
            id="precio-descuento"
            label="Descuento por envase ($)"
            name="discount_amount"
            inputMode="decimal"
            autoComplete="off"
          />
          <FormSelect
            id="precio-proveedor"
            label="Proveedor"
            name="supplier_id"
            defaultValue={only?.supplierId ?? ""}
          >
            <option value="">Sin indicar</option>
            {suppliers.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </FormSelect>
        </div>
        <ChoiceField
          id="precio-comprobante"
          name="document_type"
          label="Comprobante"
          options={[
            { value: "invoice", label: "Factura con IVA" },
            { value: "no_invoice", label: "Sin factura" },
          ]}
          defaultValue="invoice"
          placeholder="Elegí el comprobante"
        />
        <FormSelect
          id="precio-iva"
          label="Alícuota de IVA"
          hint="La del último precio aprobado de este producto; si no hay, 21 %."
          name="vat_rate"
          defaultValue={only?.vatRate ?? "21"}
          className={invoice ? undefined : "hidden"}
        >
          {VAT_RATES.map((v) => (
            <option key={v} value={v}>
              {v.replace(".", ",")} %
            </option>
          ))}
        </FormSelect>
        <ChoiceField
          id="precio-origen"
          name="source"
          label="Origen"
          options={[
            { value: "manual", label: "Carga manual" },
            { value: "test_value", label: "Valor de prueba" },
          ]}
          defaultValue="manual"
          placeholder="Elegí el origen"
        />
        <FormTextarea
          id="precio-notas"
          label="Observaciones"
          hint="No escribas montos acá: las observaciones se ven aunque el precio esté oculto."
          name="notes"
          maxLength={1000}
        />
      </MoreData>
      <FormTextarea
        id="precio-motivo"
        label="Motivo"
        hint="Queda en el historial. No escribas montos: el motivo lo ve quien no ve precios."
        name="reason"
        required
        maxLength={500}
        rows={2}
      />
    </div>
  );
}

// Los campos que cambian la cuenta: con los demás no se vuelve a pedir.
const COUNTED = [
  "product_id",
  "place",
  "valid_from",
  "package_price",
  "document_type",
  "vat_rate",
  "price_includes_vat",
  "discount_amount",
  "supplier_id",
  "source",
];

const FIELD_WORDS: Record<string, string> = {
  package_price: "el precio",
  discount_amount: "el descuento",
  valid_from: "la fecha",
  vat_rate: "la alícuota",
  notes: "las observaciones",
};

// El primer campo que el formulario no acepta, en palabras. El motivo todavía puede faltar.
function badField(values: Values): string | null {
  const result = schemas.priceProposal.safeParse({ ...values, reason: "Vista previa" });
  if (result.success) return null;
  return FIELD_WORDS[String(result.error.issues[0]?.path[0])] ?? "los datos";
}

function Preview({ values, invoice }: { values: Values; invoice: boolean }) {
  const [shown, setShown] = useState<{
    key: string;
    preview?: PricePreview;
    message?: string;
    failed?: boolean;
  } | null>(null);
  const [retry, setRetry] = useState(0);
  const ready = Boolean(values.product_id && values.place && values.package_price?.trim());
  // Lo que está mal escrito se dice acá, sin ir a la base (el campo muestra su error).
  const bad = ready ? badField(values) : null;
  const key = ready && !bad ? JSON.stringify([...COUNTED.map((c) => values[c] ?? ""), retry]) : "";
  const payload = useRef(values);
  useEffect(() => {
    payload.current = values;
  }, [values]);
  useEffect(() => {
    if (!key) return;
    let current = true;
    // Espera a que la persona termine de escribir.
    const timer = setTimeout(() => {
      previewPriceAction(payload.current).then(
        (r) => {
          if (current) setShown({ key, ...r });
        },
        () => {
          if (current) setShown({ key, message: "No pudimos calcular cómo queda.", failed: true });
        },
      );
    }, 400);
    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [key]);

  const fresh = ready && shown?.key === key ? shown : null;
  const failed = Boolean(fresh?.failed);
  // Al volver a calcular, el botón sigue (si no, el foco se pierde) hasta que hay una respuesta.
  const [retried, setRetried] = useState(false);
  if (retried && fresh && !failed) setRetried(false);
  return (
    <div
      className={cn(
        "flex min-h-touch flex-col justify-center rounded-sm px-3 py-2 text-base tabular-nums",
        bad || fresh?.message || fresh?.preview?.direction
          ? "bg-warn text-warn-ink"
          : "bg-info text-info-ink",
      )}
    >
      <div role="status" aria-live="polite">
        {!ready ? (
          <p>Completá el producto, el precio y para quién vale para ver cómo queda.</p>
        ) : bad ? (
          <p>Revisá {bad} para ver cómo queda.</p>
        ) : !fresh ? (
          <p>Calculando cómo queda…</p>
        ) : fresh.preview ? (
          <>
            <p className="font-medium">{previewText(fresh.preview, invoice)}</p>
            <p>{approversText(fresh.preview)}</p>
          </>
        ) : (
          <p>{fresh.message}</p>
        )}
      </div>
      {failed || (retried && ready && !bad && !fresh) ? (
        <button
          type="button"
          aria-disabled={failed ? undefined : true}
          onClick={() => {
            if (!failed) return;
            setRetried(true);
            setRetry(retry + 1);
          }}
          className="inline-flex min-h-touch items-center self-start text-sm font-medium underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:min-h-8"
        >
          Volver a calcular
        </button>
      ) : null}
    </div>
  );
}
