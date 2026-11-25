"use client";

import { useId, useRef, useState, useTransition } from "react";

import {
  removeIngredientPhotoAction,
  setIngredientPhotoAction,
} from "@/app/materias-primas/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { FormNotice } from "@/components/form-notice";
import { RecipePhotoImage } from "@/components/recipe-photo-image";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/field";
import { FormInput } from "@/components/ui/form";
import { Notice } from "@/components/ui/notice";
import type { ActionState } from "@/lib/auth/results";
import { fieldErrors, schemas } from "@/lib/forms/schemas";
import { shrinkPhoto } from "@/lib/photos";
import { PHOTO_MAX_BYTES } from "@/lib/recipe-format";

// La foto del producto en la ficha de materia prima (pedido de Soy, ADR-0066): chica, en el renglón del título de «Datos
// generales» (así no le saca alto a la ficha); en un panel se ve grande, se cambia o se quita. Un archivo no viaja en el
// guardado en lote: se aplica al subirlo, con su motivo.
export function IngredientPhoto({
  ingredientId,
  name,
  photo,
  canManage,
}: {
  ingredientId: string;
  name: string;
  // url null: está cargada pero no se pudo abrir. photo null: no tiene. undefined: no se pudo leer.
  photo: { url: string | null } | null | undefined;
  canManage: boolean;
}) {
  const link = "desk:min-h-8";
  return (
    <div className="flex items-center gap-2">
      {photo ? (
        <>
          <RecipePhotoImage
            url={photo.url}
            alt={`Foto de ${name}`}
            className="size-11 shrink-0 object-cover desk:size-7"
            fallback={<span className="text-xs text-ink-muted">No se pudo abrir</span>}
          />
          <ActionModal
            label="Ver"
            accessibleName="Ver la foto"
            variant="link"
            icon="none"
            size="sm"
            title={`Foto de ${name}`}
            className={link}
          >
            <RecipePhotoImage
              url={photo.url}
              alt={`Foto de ${name}`}
              className="max-h-[60vh] w-full object-contain"
            />
          </ActionModal>
        </>
      ) : canManage && photo === null ? null : (
        <span className="text-xs text-ink-muted">
          {photo === null ? "Sin foto" : "No se pudo leer la foto"}
        </span>
      )}
      {/* Si no se pudo leer, no se ofrece agregar: reemplazaría una que quizá está. */}
      {canManage && photo !== undefined ? (
        <ActionModal
          label={photo ? "Cambiar" : "Agregar foto"}
          accessibleName={photo ? "Cambiar foto" : "Agregar foto"}
          variant="link"
          icon="none"
          size="sm"
          title="Foto del producto"
          description="Una por materia prima. La anterior queda en el historial."
          className={link}
        >
          <PhotoPanel ingredientId={ingredientId} hasPhoto={Boolean(photo)} />
        </ActionModal>
      ) : null}
    </div>
  );
}

// Al quitar la foto, el formulario de «Quitar» desaparece: el aviso queda en su lugar mientras el panel siga abierto.
function PhotoPanel({ ingredientId, hasPhoto }: { ingredientId: string; hasPhoto: boolean }) {
  const [seen, setSeen] = useState(hasPhoto);
  const [removed, setRemoved] = useState(false);
  if (seen !== hasPhoto) {
    setSeen(hasPhoto);
    setRemoved(!hasPhoto);
  }
  return (
    <div className="flex flex-col gap-6">
      <Upload ingredientId={ingredientId} />
      {hasPhoto ? (
        <ActionForm
          action={removeIngredientPhotoAction}
          schema="photoReason"
          submitLabel="Quitar foto"
          variant="destructive"
        >
          <input type="hidden" name="ingredientId" value={ingredientId} />
          <FormInput
            id="mp-foto-quitar-motivo"
            name="reason"
            label="Motivo para quitarla"
            required
            maxLength={500}
          />
        </ActionForm>
      ) : removed ? (
        <Notice status="ok">Foto quitada. Queda en el historial.</Notice>
      ) : null}
    </div>
  );
}

function Upload({ ingredientId }: { ingredientId: string }) {
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
    const data = new FormData(event.currentTarget);
    const fields = schemas.photoReason.safeParse({ reason: data.get("reason") ?? "" });
    const found: Record<string, string> = {};
    // Del archivo o de la cámara: lo último que se eligió.
    const file = [data.get("camera"), data.get("photo")].find(
      (f): f is File => f instanceof File && f.size > 0,
    );
    // Primero la foto: el foco va al primer campo con error.
    if (!file) found.photo = "Elegí una foto.";
    if (!fields.success) Object.assign(found, fieldErrors(fields.error));
    if (showErrors(found) || !file) return;
    startTransition(async () => {
      const payload = new FormData();
      payload.set("ingredientId", ingredientId);
      payload.set("reason", String(data.get("reason")));
      try {
        const photo = await shrinkPhoto(file);
        if (photo.size > PHOTO_MAX_BYTES) {
          showErrors({ photo: "La foto pesa demasiado aun achicada. Probá con otra." });
          return;
        }
        payload.set("photo", new File([photo], "foto.jpg", { type: "image/jpeg" }));
      } catch {
        showErrors({ photo: "No pudimos leer la foto. Probá con una JPG o PNG." });
        return;
      }
      const result = await setIngredientPhotoAction({}, payload);
      if (result.fieldErrors && showErrors(result.fieldErrors)) return;
      setErrors({});
      setState(result);
      if (result.status === "ok") formRef.current?.reset();
    });
  }

  return (
    <form ref={formRef} onSubmit={submit} className="flex flex-col gap-4" noValidate>
      <Field
        id={`${prefix}-photo`}
        label="Foto"
        required
        hint="En JPG, PNG o WebP (HEIC no). Se achica sola antes de subirla."
        error={errors.photo}
      >
        <Input type="file" name="photo" accept="image/jpeg,image/png,image/webp" className="py-2" />
      </Field>
      {/* En el celular abre la cámara; en la computadora no aporta nada sobre el campo de arriba. */}
      <div className="desk:hidden">
        <Field id={`${prefix}-camera`} label="O sacala con la cámara">
          <Input
            type="file"
            name="camera"
            accept="image/*"
            capture="environment"
            className="py-2"
          />
        </Field>
      </div>
      <Field id={`${prefix}-reason`} label="Motivo" required error={errors.reason}>
        <Input name="reason" required maxLength={500} />
      </Field>
      <FormNotice state={state} />
      <span role="status" className="sr-only">
        {pending ? "Subiendo la foto…" : ""}
      </span>
      <Button type="submit" disabled={pending} className="self-start">
        {pending ? "Subiendo…" : "Guardar foto"}
      </Button>
    </form>
  );
}
