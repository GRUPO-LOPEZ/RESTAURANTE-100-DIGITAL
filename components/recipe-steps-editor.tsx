"use client";

import { useEffect, useId, useRef, useState, useTransition } from "react";
import { Plus, Trash2 } from "lucide-react";

import { saveStepsAction } from "@/app/recetas/actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { reasonField, recipeStepsSchema } from "@/lib/forms/schemas";
import { STEP_KIND_LABELS, type StepKind } from "@/lib/recipe-format";
import type { RecipeStep } from "@/lib/recipes";

type Step = {
  key: number;
  kind: StepKind;
  instructions: string;
  active_minutes: string;
  passive_minutes: string;
  // Las dependencias se guardan por clave interna, así sobreviven si se quita un paso de en medio.
  depends: number[];
};

// Lo que se guarda, con las dependencias por posición: sirve para saber si hay cambios sin guardar.
function payload(steps: Step[]) {
  const position = new Map(steps.map((s, i) => [s.key, i + 1]));
  return steps.map((s) => ({
    kind: s.kind,
    instructions: s.instructions,
    active_minutes: s.active_minutes,
    passive_minutes: s.passive_minutes,
    depends_on: s.depends
      .map((d) => position.get(d))
      .filter((n): n is number => typeof n === "number")
      .sort((a, b) => a - b),
  }));
}

const fromInitial = (initial: RecipeStep[]): Step[] =>
  initial.map((s) => ({
    key: s.number,
    kind: s.kind,
    instructions: s.instructions,
    active_minutes: String(s.activeMinutes),
    passive_minutes: String(s.passiveMinutes),
    depends: s.dependsOn,
  }));

// Procedimiento de un borrador: pasos en orden y a cuáles anteriores espera cada uno (para el camino
// crítico: los pasos en paralelo no se suman). Solo se ofrecen los pasos anteriores, así no se arman
// círculos. Mismo esquema en el navegador y en el servidor.
export function RecipeStepsEditor({
  recipeId,
  versionId,
  expectedUpdatedAt,
  initial,
}: {
  recipeId: string;
  versionId: string;
  expectedUpdatedAt: string;
  initial: RecipeStep[];
}) {
  const prefix = useId();
  const [steps, setSteps] = useState<Step[]>(() => fromInitial(initial));
  const [nextKey, setNextKey] = useState(() => Math.max(0, ...initial.map((s) => s.number)) + 1);
  const [saved, setSaved] = useState(() => JSON.stringify(payload(fromInitial(initial))));
  const [reason, setReason] = useState("");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [state, setState] = useState<ActionState>({});
  const [pending, startTransition] = useTransition();
  const focusNext = useRef<string | null>(null);
  const dirty = JSON.stringify(payload(steps)) !== saved;
  useUnsavedWarning(dirty);

  // El foco va a donde corresponde después de agregar o quitar (no se pierde en la página).
  useEffect(() => {
    if (!focusNext.current) return;
    document.getElementById(focusNext.current)?.focus();
    focusNext.current = null;
  });

  const id = (key: number, field: string) => `${prefix}-${field}-${key}`;
  const update = (key: number, change: Partial<Step>) =>
    setSteps((all) => all.map((s) => (s.key === key ? { ...s, ...change } : s)));

  function add() {
    const previous = steps.at(-1);
    setSteps((all) => [
      ...all,
      {
        key: nextKey,
        kind: "preparation",
        instructions: "",
        active_minutes: "0",
        passive_minutes: "0",
        // Por defecto espera al paso anterior: lo más común es una fila de pasos.
        depends: previous ? [previous.key] : [],
      },
    ]);
    focusNext.current = id(nextKey, "instructions");
    setNextKey((k) => k + 1);
  }

  function remove(key: number) {
    setSteps((all) =>
      all
        .filter((s) => s.key !== key)
        .map((s) => ({ ...s, depends: s.depends.filter((d) => d !== key) })),
    );
    focusNext.current = `${prefix}-agregar`;
  }

  function save() {
    const parsedReason = reasonField.safeParse(reason);
    const parsed = recipeStepsSchema.safeParse(payload(steps));
    const found: Record<string, string> = {};
    if (!parsed.success) {
      for (const issue of parsed.error.issues) {
        const [index, field] = issue.path;
        const step = typeof index === "number" ? steps[index] : undefined;
        if (step && typeof field === "string") found[id(step.key, field)] ??= issue.message;
      }
    }
    if (!parsedReason.success)
      found[`${prefix}-motivo`] = parsedReason.error.issues[0]?.message ?? "Escribí el motivo.";
    setErrors(found);
    const first = Object.keys(found)[0];
    if (first || !parsed.success) {
      setState({ status: "bad", message: "Revisá los campos marcados." });
      if (first) document.getElementById(first)?.focus();
      return;
    }
    startTransition(async () => {
      const result = await saveStepsAction({
        recipeId,
        versionId,
        expectedUpdatedAt,
        reason,
        steps: parsed.data,
      });
      setState(result);
      if (result.status === "ok") {
        setSaved(JSON.stringify(payload(steps)));
        setReason("");
      }
    });
  }

  return (
    <div className="flex flex-col gap-4">
      {dirty ? (
        <p className="flex flex-wrap items-center gap-2 text-base text-ink">
          <Badge status="warn">Cambios sin guardar</Badge> Guardalos antes de pedir la revisión.
        </p>
      ) : null}
      {steps.length === 0 ? (
        <p className="text-base text-ink-muted">Todavía no tiene pasos.</p>
      ) : (
        <ol className="flex flex-col gap-3" aria-label="Pasos del borrador">
          {steps.map((step, index) => {
            const previous = steps.slice(0, index);
            return (
              <li key={step.key} className="flex flex-col gap-3 rounded-sm border border-line p-3">
                <div className="flex items-start justify-between gap-2">
                  <span className="font-medium text-ink">Paso {index + 1}</span>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => remove(step.key)}
                    aria-label={`Quitar el paso ${index + 1}`}
                  >
                    <Trash2 aria-hidden="true" />
                    Quitar
                  </Button>
                </div>
                <Field
                  id={id(step.key, "instructions")}
                  label="Qué se hace"
                  error={errors[id(step.key, "instructions")]}
                >
                  <Textarea
                    value={step.instructions}
                    maxLength={2000}
                    onChange={(e) => update(step.key, { instructions: e.target.value })}
                  />
                </Field>
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                  <Field
                    id={id(step.key, "kind")}
                    label="Tipo"
                    className="col-span-2 sm:col-span-1"
                  >
                    <Select
                      value={step.kind}
                      onChange={(e) => update(step.key, { kind: e.target.value as StepKind })}
                    >
                      {(Object.keys(STEP_KIND_LABELS) as StepKind[]).map((k) => (
                        <option key={k} value={k}>
                          {STEP_KIND_LABELS[k]}
                        </option>
                      ))}
                    </Select>
                  </Field>
                  <Field
                    id={id(step.key, "active_minutes")}
                    label="Minutos trabajando"
                    hint="Con una persona encima."
                    error={errors[id(step.key, "active_minutes")]}
                  >
                    <Input
                      inputMode="numeric"
                      value={step.active_minutes}
                      onChange={(e) => update(step.key, { active_minutes: e.target.value })}
                    />
                  </Field>
                  <Field
                    id={id(step.key, "passive_minutes")}
                    label="Minutos de espera"
                    hint="Cocción, reposo, frío."
                    error={errors[id(step.key, "passive_minutes")]}
                  >
                    <Input
                      inputMode="numeric"
                      value={step.passive_minutes}
                      onChange={(e) => update(step.key, { passive_minutes: e.target.value })}
                    />
                  </Field>
                </div>
                {previous.length > 0 ? (
                  <fieldset className="flex flex-col gap-2">
                    <legend className="text-sm font-medium text-ink">
                      Empieza cuando terminan
                    </legend>
                    <div className="flex flex-wrap gap-x-4">
                      {previous.map((o, i) => (
                        <Checkbox
                          key={o.key}
                          id={`${prefix}-espera-${step.key}-${o.key}`}
                          label={`Paso ${i + 1}`}
                          checked={step.depends.includes(o.key)}
                          onChange={(e) =>
                            update(step.key, {
                              depends: e.target.checked
                                ? [...step.depends, o.key]
                                : step.depends.filter((d) => d !== o.key),
                            })
                          }
                        />
                      ))}
                    </div>
                  </fieldset>
                ) : null}
              </li>
            );
          })}
        </ol>
      )}
      <Button
        id={`${prefix}-agregar`}
        type="button"
        variant="outline"
        onClick={add}
        className="self-start"
      >
        <Plus aria-hidden="true" />
        Agregar un paso
      </Button>
      <Field
        id={`${prefix}-motivo`}
        label="Motivo de los cambios"
        hint="Queda en el historial."
        error={errors[`${prefix}-motivo`]}
      >
        <Textarea value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} />
      </Field>
      <FormNotice state={state} />
      <Button type="button" onClick={save} disabled={pending} className="w-full sm:w-auto">
        {pending ? "Guardando…" : "Guardar pasos"}
      </Button>
    </div>
  );
}
