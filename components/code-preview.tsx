"use client";

import * as React from "react";
import { useFormContext, useWatch } from "react-hook-form";

import { Input } from "@/components/ui/field";
import { InfoTip } from "@/components/ui/info-tip";
import { codePreviewText } from "@/lib/codes";

// El código de un alta (ADR-0041): no se escribe, lo arma la base. Cuando el formulario ya tiene lo que hace falta
// (tipo y rubro, o solo el rubro), le pide a la base la vista previa y la muestra en solo lectura. Lo que se mostró
// viaja oculto como expected_code: si al crear salió otro (alguien creó otra en el medio), la ficha lo avisa.
export function CodePreview({
  id,
  fields,
  preview,
  explanation,
}: {
  id: string;
  // El tooltip: de qué sale el código (en recetas, el tipo y el rubro; en materias primas, el rubro).
  explanation: string;
  // Los campos del formulario de los que depende el código, en orden (por ejemplo, ["category_id", "type"]).
  fields: string[];
  preview: (...values: string[]) => Promise<string | null>;
}) {
  const form = useFormContext();
  const watched = useWatch({ name: fields }) as (string | undefined)[];
  const values = fields.map((_, i) => watched[i] ?? "");
  const ready = values.every((v) => v !== "");
  const key = values.join("|");
  const [result, setResult] = React.useState<{ key: string; code: string | null } | null>(null);
  // La función puede llegar nueva en cada dibujo: se pide la vista previa solo cuando cambian los valores.
  const previewRef = React.useRef(preview);
  React.useEffect(() => {
    previewRef.current = preview;
  }, [preview]);

  React.useEffect(() => {
    if (!ready) return;
    let current = true;
    previewRef.current(...key.split("|")).then(
      (code) => current && setResult({ key, code }),
      () => current && setResult({ key, code: null }),
    );
    return () => {
      current = false;
    };
  }, [key, ready]);

  const loading = ready && result?.key !== key;
  const code = ready && !loading ? (result?.code ?? null) : null;
  React.useEffect(() => {
    form.setValue("expected_code", code ?? "");
  }, [code, form]);

  return (
    <div data-slot="field" className="flex flex-col gap-2">
      <div className="flex items-center gap-1">
        <label htmlFor={id} className="text-sm font-medium text-ink">
          Código
        </label>
        <InfoTip label="Código">{explanation}</InfoTip>
      </div>
      <Input
        id={id}
        readOnly
        value={codePreviewText({ ready, loading, code })}
        className="bg-app tabular-nums"
      />
      {/* Un lector de pantalla no anuncia el valor de un campo que cambia: se anuncia aparte. */}
      <span className="sr-only" aria-live="polite">
        {ready ? `Código: ${codePreviewText({ ready, loading, code })}` : ""}
      </span>
      <input type="hidden" {...form.register("expected_code")} />
    </div>
  );
}
