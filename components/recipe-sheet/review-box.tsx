"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import { decideReviewAction } from "@/app/recetas/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Field, Input, Textarea } from "@/components/ui/field";
import type { ActionState } from "@/lib/auth/results";

// Lo que ve quien revisa (ADR-0042): la ficha en solo lectura con los cambios marcados, y acá sus observaciones y
// «Aprobar» o «No aprobar». No edita nada: la base rechaza cualquier cambio a una versión en revisión.
// En la computadora va en la barra fija de abajo, en lugar de Guardar (ficha sin scroll, ADR-0047); en el celular, una
// tarjeta arriba de la ficha.
export function ReviewBox({
  recipeId,
  requestId,
  variant = "card",
  versionNumber,
  changes = 0,
  removed = 0,
}: {
  recipeId: string;
  requestId: string;
  variant?: "card" | "bar";
  versionNumber?: number;
  // Filas nuevas o cambiadas (se ven marcadas en la planilla) y quitadas (no están: se ven en Versiones).
  changes?: number;
  removed?: number;
}) {
  const router = useRouter();
  const [comment, setComment] = useState("");
  const [state, setState] = useState<ActionState>({});
  const [pending, startTransition] = useTransition();
  const commentId = `revision-${requestId}-${variant}`;

  function decide(decision: "approved" | "rejected") {
    startTransition(async () => {
      const result = await decideReviewAction({ recipeId, requestId, decision, comment });
      setState(result);
      // La versión deja de estar en revisión y la barra se va: el aviso queda en la ficha.
      if (result.status === "ok")
        router.replace(
          `/recetas/${recipeId}?aviso=${decision === "approved" ? "aprobada" : "no-aprobada"}`,
          { scroll: false },
        );
    });
  }

  const buttons = (
    <>
      <Button
        type="button"
        variant="outline"
        className="text-bad-ink"
        disabled={pending}
        onClick={() => decide("rejected")}
      >
        No aprobar
      </Button>
      <Button type="button" disabled={pending} onClick={() => decide("approved")}>
        Aprobar
      </Button>
    </>
  );

  if (variant === "bar") {
    return (
      <div className="sticky bottom-0 z-10 -mx-gutter hidden flex-col gap-2 border-t border-line bg-surface px-gutter py-2 desk:flex wide:-mx-gutter-wide wide:px-gutter-wide">
        <FormNotice state={state} />
        <div className="flex flex-wrap items-center gap-2">
          <span className="mr-auto text-base font-semibold text-ink">
            Revisión{versionNumber ? ` de v${versionNumber}` : ""}
            {changes > 0
              ? ` · ${changes} ${changes === 1 ? "cambio marcado" : "cambios marcados"}`
              : ""}
            {removed > 0
              ? ` · ${removed} ${removed === 1 ? "ingrediente quitado" : "ingredientes quitados"} (en Versiones)`
              : ""}
          </span>
          <label htmlFor={commentId} className="text-sm font-medium text-ink">
            Observaciones
          </label>
          <span id={`${commentId}-ayuda`} className="sr-only">
            Para no aprobarla, son obligatorias.
          </span>
          <Input
            id={commentId}
            value={comment}
            maxLength={1000}
            aria-describedby={`${commentId}-ayuda`}
            placeholder="Obligatorias si no aprobás"
            className="w-80"
            onChange={(e) => setComment(e.target.value)}
          />
          {buttons}
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3 rounded-sm border border-line bg-app p-4">
      <h2 className="text-base font-semibold text-ink">Tu revisión</h2>
      <p className="text-sm text-ink-muted">
        Revisás la ficha en solo lectura, con los cambios marcados. No se puede editar nada.
      </p>
      <Field id={commentId} label="Observaciones" hint="Para no aprobarla, son obligatorias.">
        <Textarea
          value={comment}
          maxLength={1000}
          placeholder="Por ejemplo: revisar la sal"
          onChange={(e) => setComment(e.target.value)}
        />
      </Field>
      <FormNotice state={state} />
      <div className="flex flex-wrap gap-2">{buttons}</div>
    </div>
  );
}
