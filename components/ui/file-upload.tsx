"use client";

import * as React from "react";
import { Camera, Upload } from "lucide-react";

import { cn } from "@/lib/utils";

// Subir un archivo con un botón propio (criterio 12 de Soy, ADR-0068): el control del navegador dice «Choose File No
// file chosen» si Chrome está en inglés. Acá el input sigue siendo el control (se enfoca con Tab, abre el selector con
// Enter, Espacio o un clic, lo nombra solo la etiqueta del Field y valida «required»), pero transparente y encima del
// botón que se ve («Subir foto o PDF»), que lo describe. Al lado, el nombre del archivo elegido. En el celular, con
// imágenes, suma «Sacar foto» (abre la cámara).

type FileUploadProps = {
  id?: string;
  name?: string;
  accept?: string;
  required?: boolean;
  disabled?: boolean;
  // El texto del botón; si no, sale de lo que acepta («Subir foto o PDF», «Subir planilla», «Subir PDF»).
  label?: string;
  // En el celular, «Sacar foto»: el nombre de su campo. Siempre otro nombre (la acción lo lee aparte): con el mismo, el
  // formulario mandaría dos archivos y el servidor leería el vacío.
  camera?: string;
  // Para los formularios controlados: el archivo elegido (o null si se sacó).
  onFile?: (file: File | null) => void;
  className?: string;
  "aria-describedby"?: string;
  "aria-invalid"?: boolean;
};

export function uploadLabel(accept: string | undefined): string {
  const a = (accept ?? "").toLowerCase();
  const image = a.includes("image");
  const pdf = a.includes("pdf");
  const sheet = a.includes(".xlsx") || a.includes("spreadsheet") || a.includes(".csv");
  if (sheet) return "Subir planilla";
  if (image && pdf) return "Subir foto o PDF";
  if (image) return "Subir foto";
  if (pdf) return "Subir PDF";
  return "Subir archivo";
}

// El input, del tamaño del botón y encima: el clic cae en el control de verdad.
const INPUT =
  "peer absolute inset-0 z-10 size-full cursor-pointer opacity-0 disabled:cursor-not-allowed";
const BUTTON =
  "pointer-events-none inline-flex min-h-touch items-center justify-center gap-2 rounded-sm border border-line bg-surface px-4 text-sm font-medium text-ink peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-primary peer-hover:bg-line/50 peer-aria-invalid:border-bad-ink peer-disabled:opacity-50 desk:min-h-control [&_svg]:size-4 [&_svg]:shrink-0";

function FileUpload({
  id,
  name,
  accept,
  required,
  disabled,
  label,
  camera,
  onFile,
  className,
  "aria-describedby": describedBy,
  "aria-invalid": invalid,
}: FileUploadProps) {
  const autoId = React.useId();
  const inputId = id ?? autoId;
  const statusId = `${inputId}-archivo`;
  const actionId = `${inputId}-accion`;
  const [fileName, setFileName] = React.useState<string | null>(null);
  const withCamera = Boolean(camera) && (accept ?? "").includes("image");

  const main = React.useRef<HTMLInputElement>(null);
  const cam = React.useRef<HTMLInputElement>(null);

  function picked(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    // Viaja solo lo último que se eligió: el otro campo (archivo o cámara) se vacía.
    const other = e.target === main.current ? cam.current : main.current;
    if (file && other) other.value = "";
    setFileName(file?.name ?? null);
    onFile?.(file);
  }

  function clear() {
    if (main.current) main.current.value = "";
    if (cam.current) cam.current.value = "";
    setFileName(null);
    onFile?.(null);
    main.current?.focus();
  }

  return (
    <span className={cn("flex flex-col gap-2", className)}>
      <span className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <span className="relative inline-flex">
          <input
            ref={main}
            id={inputId}
            type="file"
            name={name}
            accept={accept}
            required={required}
            disabled={disabled}
            aria-invalid={invalid}
            aria-describedby={[describedBy, actionId, statusId].filter(Boolean).join(" ")}
            onChange={picked}
            className={INPUT}
          />
          <span id={actionId} aria-hidden="true" className={BUTTON}>
            <Upload aria-hidden="true" />
            {fileName ? "Cambiar archivo" : (label ?? uploadLabel(accept))}
          </span>
        </span>
        <span id={statusId} className="min-w-0 text-sm [overflow-wrap:anywhere] text-ink-muted">
          {fileName ?? "Ningún archivo elegido"}
        </span>
        {fileName ? (
          // Para arrepentirse de un archivo opcional (por ejemplo, el comprobante de un pago).
          <button
            type="button"
            onClick={clear}
            disabled={disabled}
            className="inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:min-h-8"
          >
            Quitar
            <span className="sr-only"> {fileName}</span>
          </button>
        ) : null}
      </span>
      {withCamera ? (
        <span className="relative inline-flex desk:hidden">
          <input
            ref={cam}
            id={`${inputId}-camara`}
            type="file"
            name={camera}
            accept="image/*"
            capture="environment"
            disabled={disabled}
            aria-label="Sacar foto"
            onChange={picked}
            className={INPUT}
          />
          <span aria-hidden="true" className={BUTTON}>
            <Camera aria-hidden="true" />
            Sacar foto
          </span>
        </span>
      ) : null}
    </span>
  );
}

export { FileUpload };
