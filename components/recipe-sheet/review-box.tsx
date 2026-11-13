"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import { decideReviewAction } from "@/app/recetas/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Field, Textarea } from "@/components/ui/field";
import type { ActionState } from "@/lib/auth/results";

// Lo que ve quien revisa (ADR-0042): la ficha en solo lectura con los cambios marcados, y acá sus observaciones y
// «Aprobar» o «No aprobar». No edita nada: la base rechaza cualquier cambio a una versión en revisión.
export function ReviewBox({ recipeId, requestId }: { recipeId: string; requestId: string }) {
  const router = useRouter();
  const [comment, setComment] = useState("");
  const [state, setState] = useState<ActionState>({});
  const [pending, startTransition] = useTransition();

  function decide(decision: "approved" | "rejected") {
    startTransition(async () => {
      const result = await decideReviewAction({ recipeId, requestId, decision, comment });
      setState(result);
      // La versión deja de estar en revisión y el recuadro se va: el aviso queda arriba de la ficha.
      if (result.status === "ok")
        router.replace(
          `/recetas/${recipeId}?aviso=${decision === "approved" ? "aprobada" : "no-aprobada"}`,
        );
    });
  }

  return (
    <div className="flex flex-col gap-3 rounded-sm border border-line bg-app p-4">
      <h3 className="text-base font-semibold text-ink">Tu revisión</h3>
      <p className="text-sm text-ink-muted">
        Revisás la ficha en solo lectura, con los cambios marcados. No se puede editar nada.
      </p>
      <Field
        id={`revision-${requestId}`}
        label="Observaciones"
        hint="Para no aprobarla, son obligatorias."
      >
        <Textarea
          value={comment}
          maxLength={1000}
          placeholder="Por ejemplo: revisar la sal"
          onChange={(e) => setComment(e.target.value)}
        />
      </Field>
      <FormNotice state={state} />
      <div className="flex flex-wrap gap-2">
        <Button type="button" disabled={pending} onClick={() => decide("approved")}>
          Aprobar
        </Button>
        <Button
          type="button"
          variant="outline"
          className="text-bad-ink"
          disabled={pending}
          onClick={() => decide("rejected")}
        >
          No aprobar
        </Button>
      </div>
    </div>
  );
}
