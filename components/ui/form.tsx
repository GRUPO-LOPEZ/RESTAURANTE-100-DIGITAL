"use client";

import * as React from "react";
import { useActionState, useEffect, useRef, useTransition } from "react";
import { FormProvider, useForm, useFormContext, useFormState } from "react-hook-form";

import { Checkbox } from "@/components/ui/checkbox";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import { cn } from "@/lib/utils";
import type { ActionState } from "@/lib/auth/results";
import { schemas, type FormSchemaName } from "@/lib/forms/schemas";
import { zodResolver } from "@/lib/forms/resolver";

// Formularios con React Hook Form (ADR-0016): validan con el esquema de lib/forms/schemas.ts antes
// de enviar y muestran el error debajo de cada campo. Recién si está bien se llama a la acción con
// todos los campos del formulario (también los ocultos). La acción valida de nuevo y puede devolver
// errores por campo (fieldErrors), que se muestran igual.
export function useServerForm<S extends ActionState>({
  schema,
  action,
  initialState,
  check,
}: {
  // Sin esquema (un formulario que es solo un botón), no hay nada que validar antes de enviar.
  schema?: FormSchemaName;
  action: (state: Awaited<S>, formData: FormData) => S | Promise<S>;
  initialState?: Awaited<S>;
  // Una regla que depende del botón que se apretó (por ejemplo, "para rechazar, el motivo").
  check?: (formData: FormData) => Record<string, string> | undefined;
}) {
  const methods = useForm({
    resolver: schema ? zodResolver(schemas[schema]) : undefined,
    mode: "onTouched",
    // El foco se mueve recién cuando el error ya está dibujado (para que el lector lo lea).
    shouldFocusError: false,
  });
  const [state, formAction, pending] = useActionState<S, FormData>(
    action,
    initialState ?? ({} as Awaited<S>),
  );
  const [transitioning, startTransition] = useTransition();
  // El formulario que se envió (se guarda al enviar, no se lee al dibujar).
  const formRef = useRef<HTMLFormElement | null>(null);
  // Pedido de foco: se atiende cuando los errores ya están dibujados.
  const wantsFocus = useRef(false);
  const { setError, reset, setFocus, formState } = methods;

  // Lo que respondió la base: errores por campo, o el formulario limpio si salió bien.
  useEffect(() => {
    const errors = Object.entries(state.fieldErrors ?? {});
    errors.forEach(([name, message]) => setError(name, { type: "server", message }));
    if (errors[0]) wantsFocus.current = true;
    if ((state.status === "ok" || state.status === "info") && formRef.current) {
      formRef.current.reset();
      reset(Object.fromEntries(new FormData(formRef.current)));
    }
  }, [state, setError, reset]);

  // El foco va al primer campo con error, en el orden del formulario.
  useEffect(() => {
    const names = Object.keys(formState.errors);
    if (!wantsFocus.current || !formRef.current || names.length === 0) return;
    wantsFocus.current = false;
    const first = Array.from(formRef.current.elements).find(
      (el): el is HTMLInputElement => "name" in el && names.includes(String(el.name)),
    );
    if (first) setFocus(first.name);
  }, [formState.errors, setFocus]);

  const onSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    const form = event.currentTarget;
    formRef.current = form;
    const submitter = (event.nativeEvent as SubmitEvent).submitter;
    const data = () => new FormData(form, submitter);
    void methods.handleSubmit(
      () => {
        const extra = check?.(data());
        if (extra && Object.keys(extra).length > 0) {
          Object.entries(extra).forEach(([name, message]) =>
            setError(name, { type: "validate", message }),
          );
          wantsFocus.current = true;
          return;
        }
        startTransition(() => formAction(data()));
      },
      () => (wantsFocus.current = true),
    )(event);
  };

  return { methods, state, pending: pending || transitioning, onSubmit, formAction };
}

// Un aviso para lectores de pantalla, siempre presente: cuántos campos hay que revisar.
function ErrorSummary() {
  const { errors, submitCount } = useFormState();
  const count = Object.keys(errors).length;
  return (
    <p aria-live="polite" className="sr-only">
      {submitCount > 0 && count > 0
        ? count === 1
          ? "Revisá el campo marcado."
          : `Revisá los ${count} campos marcados.`
        : ""}
    </p>
  );
}

// El formulario con su contexto: los campos de abajo se registran solos. Lleva también la acción
// de servidor: si se envía antes de que cargue la página, va por POST (nunca por la dirección) y la
// acción valida igual.
export function ServerForm({
  form,
  className,
  children,
}: {
  form: Pick<ReturnType<typeof useServerForm>, "methods" | "onSubmit" | "formAction">;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <FormProvider {...form.methods}>
      <form action={form.formAction} onSubmit={form.onSubmit} className={className} noValidate>
        <ErrorSummary />
        {children}
      </form>
    </FormProvider>
  );
}

type FieldProps = { name: string; id: string; label: string; hint?: string; className?: string };

function useRegistered(name: string) {
  const context = useFormContext();
  const message = context?.formState.errors[name]?.message;
  return {
    props: context ? context.register(name) : { name },
    error: typeof message === "string" ? message : undefined,
  };
}

export function FormInput({
  name,
  id,
  label,
  hint,
  className,
  ...props
}: FieldProps & Omit<React.ComponentProps<"input">, "name" | "id">) {
  const { props: registered, error } = useRegistered(name);
  return (
    <Field id={id} label={label} hint={hint} error={error} className={className}>
      <Input {...props} {...registered} />
    </Field>
  );
}

export function FormSelect({
  name,
  id,
  label,
  hint,
  className,
  ...props
}: FieldProps & Omit<React.ComponentProps<"select">, "name" | "id">) {
  const { props: registered, error } = useRegistered(name);
  return (
    <Field id={id} label={label} hint={hint} error={error} className={className}>
      <Select {...props} {...registered} />
    </Field>
  );
}

export function FormTextarea({
  name,
  id,
  label,
  hint,
  className,
  ...props
}: FieldProps & Omit<React.ComponentProps<"textarea">, "name" | "id">) {
  const { props: registered, error } = useRegistered(name);
  return (
    <Field id={id} label={label} hint={hint} error={error} className={className}>
      <Textarea {...props} {...registered} />
    </Field>
  );
}

// Casilla registrada en el formulario: se valida con el esquema como los demás campos y muestra
// su error debajo. React Hook Form la entrega como true o false; enviada, llega como "on".
export function FormCheckbox({
  name,
  id,
  label,
  hint,
  className,
  ...props
}: FieldProps & Omit<React.ComponentProps<"input">, "name" | "id" | "type">) {
  const { props: registered, error } = useRegistered(name);
  const hintId = hint ? `${id}-ayuda` : undefined;
  const errorId = error ? `${id}-error` : undefined;
  return (
    <div data-slot="field" className={cn("flex flex-col gap-1", className)}>
      <Checkbox
        id={id}
        label={label}
        aria-describedby={[hintId, errorId].filter(Boolean).join(" ") || undefined}
        aria-invalid={error ? true : undefined}
        {...props}
        {...registered}
      />
      {hint ? (
        <p id={hintId} className="text-sm text-ink-muted">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={errorId} className="text-sm text-bad-ink">
          {error}
        </p>
      ) : null}
    </div>
  );
}
