"use client";

import { useEffect, useState, useTransition } from "react";

import {
  confirmEnrollment,
  startEnrollment,
  verifyCode,
  type EnrollState,
} from "@/app/ingresar/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { FormInput, ServerForm, useServerForm } from "@/components/ui/form";

function CodeInput() {
  return (
    <FormInput
      id="code"
      label="Código de 6 números"
      name="code"
      inputMode="numeric"
      autoComplete="one-time-code"
      pattern="[0-9]{6}"
      maxLength={6}
      required
    />
  );
}

export function VerifyForm({ next }: { next: string }) {
  const form = useServerForm({ schema: "code", action: verifyCode });
  return (
    <ServerForm form={form} className="flex flex-col gap-4">
      <input type="hidden" name="next" value={next} />
      <CodeInput />
      <FormNotice state={form.state} />
      <Button type="submit" size="wide" disabled={form.pending}>
        {form.pending ? "Verificando…" : "Verificar"}
      </Button>
    </ServerForm>
  );
}

export function EnrollForm({ next }: { next: string }) {
  const [enrollment, setEnrollment] = useState<EnrollState>({});
  const [starting, startTransition] = useTransition();
  const form = useServerForm({ schema: "code", action: confirmEnrollment });

  useEffect(() => {
    startTransition(async () => setEnrollment(await startEnrollment()));
  }, []);

  if (starting || (!enrollment.factorId && !enrollment.message)) {
    return (
      <p role="status" className="text-base text-ink-muted">
        Preparando el registro…
      </p>
    );
  }
  if (!enrollment.factorId) return <FormNotice state={enrollment} />;

  return (
    <ServerForm form={form} className="flex flex-col gap-4">
      {enrollment.qrCode ? (
        // El código QR lo genera Supabase Auth como imagen SVG.
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={enrollment.qrCode}
          alt="Código QR para tu app de autenticación"
          className="mx-auto size-48 rounded-sm border border-line bg-surface"
        />
      ) : null}
      <p className="text-sm text-ink-muted">
        Si no podés escanearlo, cargá esta clave a mano:{" "}
        <span className="font-medium break-all text-ink">{enrollment.secret}</span>
      </p>
      <input type="hidden" name="factorId" value={enrollment.factorId} />
      <input type="hidden" name="next" value={next} />
      <CodeInput />
      <FormNotice state={form.state} />
      <Button type="submit" size="wide" disabled={form.pending}>
        {form.pending ? "Registrando…" : "Registrar y entrar"}
      </Button>
    </ServerForm>
  );
}
