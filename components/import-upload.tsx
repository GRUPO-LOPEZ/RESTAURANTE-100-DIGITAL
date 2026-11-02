"use client";

import { useId, useState, useTransition } from "react";
import { Upload } from "lucide-react";

import { readImportAction } from "@/app/recetas/importar/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import type { ActionState } from "@/lib/auth/results";
import { fieldErrors, schemas } from "@/lib/forms/schemas";
import { createClient } from "@/lib/supabase/client";

const XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
const MAX_BYTES = 15 * 1024 * 1024; // como el bucket

export type UploadBrand = { id: string; groupId: string; name: string; prefix: string | null };

// Subir el recetario: el navegador manda el Excel directo al bucket privado (los pedidos al servidor
// tienen un tope de 4,5 MB) y después el servidor lo lee con la sesión de la persona (ADR-0027).
export function ImportUpload({ brands }: { brands: UploadBrand[] }) {
  const prefix = useId();
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [state, setState] = useState<ActionState>({});
  const [phase, setPhase] = useState<"idle" | "upload" | "read">("idle");
  const [pending, startTransition] = useTransition();
  const [brandId, setBrandId] = useState(brands.length === 1 ? (brands[0]?.id ?? "") : "");
  const [codePrefix, setCodePrefix] = useState(
    brands.length === 1 ? (brands[0]?.prefix ?? "") : "",
  );
  const known = brands.find((b) => b.id === brandId)?.prefix ?? null;

  function showErrors(found: Record<string, string>) {
    setErrors(found);
    const first = Object.keys(found)[0];
    if (!first) return false;
    setState({ status: "bad", message: "Revisá los campos marcados." });
    document.getElementById(`${prefix}-${first}`)?.focus();
    return true;
  }

  function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const fields = schemas.importBook.safeParse({
      brand_id: data.get("brand_id") ?? "",
      code_prefix: data.get("code_prefix") ?? "",
      reason: data.get("reason") ?? "",
    });
    const found = fields.success ? {} : fieldErrors(fields.error);
    const file = data.get("file");
    if (!(file instanceof File) || file.size === 0) found.file = "Elegí el Excel.";
    else if (!file.name.toLowerCase().endsWith(".xlsx"))
      found.file = "Tiene que ser un Excel .xlsx («Libro de Excel»).";
    else if (file.size > MAX_BYTES) found.file = "El archivo pasa los 15 MB.";
    const brand = brands.find((b) => b.id === data.get("brand_id"));
    if (!brand && !found.brand_id) found.brand_id = "Elegí la marca.";
    if (showErrors(found) || !brand || !(file instanceof File)) return;
    setErrors({});
    setState({});
    startTransition(async () => {
      // Una falla de red, o una lectura que pasa el tiempo máximo, no se lleva el formulario.
      try {
        setPhase("upload");
        const path = `${brand.groupId}/${brand.id}/${crypto.randomUUID()}.xlsx`;
        const { error } = await createClient()
          .storage.from("imports")
          .upload(path, file, { contentType: XLSX, upsert: false });
        if (error) {
          setState({ status: "bad", message: "No pudimos subir el archivo. Probá de nuevo." });
          return;
        }
        setPhase("read");
        data.delete("file");
        data.set("path", path);
        data.set("file_name", file.name);
        // Si sale bien, la acción lleva a la vista previa.
        const result = await readImportAction({}, data);
        if (result.fieldErrors && showErrors(result.fieldErrors)) return;
        setState(result);
      } catch {
        setState({
          status: "bad",
          message: "No pudimos leer el Excel. Revisá la conexión y probá de nuevo.",
        });
      } finally {
        setPhase("idle");
      }
    });
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-4" noValidate>
      <Field id={`${prefix}-brand_id`} label="Marca" error={errors.brand_id}>
        <Select
          name="brand_id"
          value={brandId}
          onChange={(e) => {
            setBrandId(e.target.value);
            // El prefijo es de cada marca: nunca queda puesto el de otra.
            setCodePrefix(brands.find((b) => b.id === e.target.value)?.prefix ?? "");
          }}
        >
          <option value="" disabled>
            Elegí la marca
          </option>
          {brands.map((b) => (
            <option key={b.id} value={b.id}>
              {b.name}
            </option>
          ))}
        </Select>
      </Field>
      <Field
        id={`${prefix}-code_prefix`}
        label="Prefijo de los códigos"
        hint={
          known
            ? `Esta marca ya importó con ${known}: se usa el mismo, así no se duplican los códigos.`
            : "Va delante de cada código del Excel (190000 queda NON-190000). De 2 a 6 letras o números."
        }
        error={errors.code_prefix}
      >
        <Input
          name="code_prefix"
          value={codePrefix}
          onChange={(e) => setCodePrefix(e.target.value.toUpperCase())}
          maxLength={6}
          autoCapitalize="characters"
          autoComplete="off"
          spellCheck={false}
          readOnly={Boolean(known)}
          className={known ? "bg-app" : undefined}
        />
      </Field>
      <Field
        id={`${prefix}-file`}
        label="Recetario de Excel"
        hint="Con las solapas INSUMOS, pre-elaborado y PLATOS. Hasta 15 MB."
        error={errors.file}
      >
        <Input type="file" name="file" accept={`.xlsx,${XLSX}`} className="py-2" />
      </Field>
      <Field
        id={`${prefix}-reason`}
        label="Motivo"
        hint="Queda en el historial."
        error={errors.reason}
      >
        <Textarea name="reason" maxLength={500} />
      </Field>
      <FormNotice state={state} />
      {/* Siempre presente, para que el lector de pantalla anuncie cada cambio. */}
      <p role="status" className="text-base text-ink-muted empty:hidden">
        {phase === "upload"
          ? "Subiendo el Excel…"
          : phase === "read"
            ? "Leyendo el Excel. Puede tardar hasta un minuto: no cierres la pantalla."
            : ""}
      </p>
      <Button type="submit" disabled={pending} className="w-full sm:w-auto">
        <Upload aria-hidden="true" />
        {phase === "upload" ? "Subiendo…" : phase === "read" ? "Leyendo…" : "Subir y revisar"}
      </Button>
    </form>
  );
}
