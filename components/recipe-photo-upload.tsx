"use client";

import { useId, useRef, useState, useTransition } from "react";
import { Camera } from "lucide-react";

import { uploadPhotoAction } from "@/app/recetas/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Field, Input, Select, Textarea } from "@/components/ui/field";
import type { ActionState } from "@/lib/auth/results";
import { fieldErrors, schemas } from "@/lib/forms/schemas";
import { shrinkPhoto } from "@/lib/photos";
import { MEDIA_KIND_LABELS, PHOTO_MAX_BYTES, type MediaKind } from "@/lib/recipe-format";

// Subir una foto de la receta: elegirla (o sacarla con el celular), decir qué muestra y el motivo.
export function RecipePhotoUpload({ recipeId }: { recipeId: string }) {
  const prefix = useId();
  const formRef = useRef<HTMLFormElement>(null);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [state, setState] = useState<ActionState>({});
  const [pending, startTransition] = useTransition();

  // Cualquier error de campo (del navegador o del servidor) se anuncia y lleva el foco a ese campo.
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
    const form = event.currentTarget;
    const data = new FormData(form);
    const fields = schemas.recipePhoto.safeParse({
      kind: data.get("kind"),
      description: data.get("description") ?? "",
      reason: data.get("reason") ?? "",
    });
    const found = fields.success ? {} : fieldErrors(fields.error);
    const file = data.get("photo");
    if (!(file instanceof File) || file.size === 0) found.photo = "Elegí una foto.";
    if (showErrors(found)) return;
    startTransition(async () => {
      try {
        const photo = await shrinkPhoto(file as File);
        if (photo.size > PHOTO_MAX_BYTES) {
          showErrors({ photo: "La foto pesa demasiado aun achicada. Probá con otra." });
          return;
        }
        data.set("photo", new File([photo], "foto.jpg", { type: "image/jpeg" }));
      } catch {
        showErrors({ photo: "No pudimos leer la foto. Probá con una JPG o PNG." });
        return;
      }
      const result = await uploadPhotoAction({}, data);
      if (result.fieldErrors && showErrors(result.fieldErrors)) return;
      setErrors({});
      setState(result);
      if (result.status === "ok") formRef.current?.reset();
    });
  }

  return (
    <form ref={formRef} onSubmit={submit} className="flex flex-col gap-4" noValidate>
      <input type="hidden" name="recipeId" value={recipeId} />
      <Field
        id={`${prefix}-photo`}
        label="Foto"
        hint="Del celular o de la compu, en JPG, PNG o WebP (HEIC no). Se achica sola antes de subirla."
        error={errors.photo}
      >
        <Input type="file" name="photo" accept="image/jpeg,image/png,image/webp" className="py-2" />
      </Field>
      <Field id={`${prefix}-kind`} label="Qué muestra" error={errors.kind}>
        <Select name="kind" defaultValue="">
          <option value="" disabled>
            Elegí qué muestra
          </option>
          {(Object.keys(MEDIA_KIND_LABELS) as MediaKind[]).map((k) => (
            <option key={k} value={k}>
              {MEDIA_KIND_LABELS[k]}
            </option>
          ))}
        </Select>
      </Field>
      <Field id={`${prefix}-description`} label="Descripción (opcional)" error={errors.description}>
        <Input name="description" maxLength={300} />
      </Field>
      <Field
        id={`${prefix}-reason`}
        label="Motivo de la foto"
        hint="Queda en el historial."
        error={errors.reason}
      >
        <Textarea name="reason" maxLength={500} />
      </Field>
      <FormNotice state={state} />
      <Button type="submit" disabled={pending} className="w-full sm:w-auto">
        <Camera aria-hidden="true" />
        {pending ? "Subiendo…" : "Subir foto"}
      </Button>
    </form>
  );
}
