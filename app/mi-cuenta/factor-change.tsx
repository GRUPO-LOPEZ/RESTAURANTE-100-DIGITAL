"use client";

import { useState, useTransition } from "react";

import {
  confirmFactorChangeAction,
  startFactorChangeAction,
  type FactorState,
} from "@/app/mi-cuenta/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { FormInput, ServerForm, useServerForm } from "@/components/ui/form";

// Cambiar de app de autenticación (por ejemplo, celular nuevo). La anterior se da de baja recién
// cuando el código de la nueva es correcto.
export function FactorChange() {
  const [enrollment, setEnrollment] = useState<FactorState>({});
  const [starting, startTransition] = useTransition();
  const form = useServerForm({ schema: "code", action: confirmFactorChangeAction });

  if (form.state.status === "ok") return <FormNotice state={form.state} />;

  if (!enrollment.factorId) {
    return (
      <div className="flex flex-col gap-2">
        <FormNotice state={enrollment} />
        <Button
          type="button"
          variant="outline"
          className="w-full sm:w-auto"
          disabled={starting}
          onClick={() =>
            startTransition(async () => setEnrollment(await startFactorChangeAction()))
          }
        >
          {starting ? "Preparando…" : "Cambiar de app o de celular"}
        </Button>
      </div>
    );
  }

  return (
    <ServerForm form={form} className="flex flex-col gap-4">
      {enrollment.qrCode ? (
        // El código QR lo genera Supabase Auth como imagen SVG.
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={enrollment.qrCode}
          alt="Código QR para tu app de autenticación nueva"
          className="mx-auto size-48 rounded-sm border border-line bg-surface"
        />
      ) : null}
      <p className="text-sm text-ink-muted">
        Si no podés escanearlo, cargá esta clave a mano:{" "}
        <span className="font-medium break-all text-ink">{enrollment.secret}</span>
      </p>
      <input type="hidden" name="factorId" value={enrollment.factorId} />
      <FormInput
        id="code-new"
        label="Código de 6 números de la app nueva"
        name="code"
        inputMode="numeric"
        autoComplete="one-time-code"
        pattern="[0-9]{6}"
        maxLength={6}
        required
      />
      <FormNotice state={form.state} />
      <div className="flex flex-col gap-2 sm:flex-row">
        <Button type="submit" disabled={form.pending} className="w-full sm:w-auto">
          {form.pending ? "Verificando…" : "Usar la app nueva"}
        </Button>
        {/* Cancelar no cambia nada: la app anterior sigue activa. */}
        <Button
          type="button"
          variant="outline"
          className="w-full sm:w-auto"
          onClick={() => setEnrollment({})}
        >
          Cancelar
        </Button>
      </div>
    </ServerForm>
  );
}
