"use client";

import { useEffect, useId, useState, useTransition, type ReactNode } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";

import { saveRubroAction } from "@/app/rubros/actions";
import { FormNotice } from "@/components/form-notice";
import { RubroIcon } from "@/components/rubro-icon";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input, Textarea } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { ScrollFocus } from "@/components/ui/scroll-focus";
import { ToggleField } from "@/components/ui/toggle-field";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { reasonField, schemas } from "@/lib/forms/schemas";
import { changesLabel } from "@/lib/recipe-sheet";
import {
  RUBRO_DESCRIPTION_MAX,
  RUBRO_ICONS,
  RUBRO_ICON_LABELS,
  rebaseDraft,
  rubroChanges,
  type RubroDraft,
  type RubroSheet,
} from "@/lib/rubros";
import { cn } from "@/lib/utils";

// La ficha de un rubro (pedido de Soy, ADR-0066): se edita donde se ve y se guarda junta, con motivo, con la barra de
// abajo. Quien no administra los rubros de esa clase la lee. El código no cambia.
const changedRing = "border-dashed border-ink";

export function RubroSheetCard({
  sheet,
  canManage,
  see,
  status,
  metrics,
  settingsHref,
}: {
  sheet: RubroSheet;
  canManage: boolean;
  // «Ver sus 41 materias primas».
  see: { href: string; label: string } | null;
  // Dar de baja o reactivar (solo quien administra).
  status: ReactNode;
  metrics: ReactNode;
  // Dónde se editan las subcategorías, si la sesión puede.
  settingsHref: string | null;
}) {
  const prefix = useId();
  const router = useRouter();
  const inUrl = useSearchParams().get("rubro");
  const saved: RubroDraft = {
    name: sheet.name,
    description: sheet.description ?? "",
    icon: sheet.icon,
    usedInRecipes: sheet.usedInRecipes,
  };
  const [draft, setDraft] = useState(saved);
  const [reason, setReason] = useState("");
  const [state, setState] = useState<ActionState>({});
  const [done, setDone] = useState(false);
  const [pending, startSave] = useTransition();
  const changes = rubroChanges(saved, draft);
  const count = Object.keys(changes).length;
  useUnsavedWarning(canManage && count > 0);

  const [errors, setErrors] = useState<{ name?: string; reason?: string }>({});

  // Vuelve la ficha con su sello nuevo: lo guardado es lo que dice la base. Si la cambió otra acción (una baja, otra
  // persona) y había algo sin guardar, se conserva solo lo que se estaba cambiando.
  const [seen, setSeen] = useState({ stamp: sheet.stamp, saved });
  if (sheet.stamp !== seen.stamp) {
    setSeen({ stamp: sheet.stamp, saved });
    setDraft(done ? saved : rebaseDraft(seen.saved, draft, saved));
  }

  // El rubro abierto queda en la dirección: buscar, ordenar, guardar o dar de baja no llevan a otro.
  useEffect(() => {
    const url = new URL(window.location.href);
    if (url.pathname !== "/rubros" || url.searchParams.get("rubro") === sheet.id) return;
    url.searchParams.set("rubro", sheet.id);
    window.history.replaceState(null, "", url);
  }, [sheet.id, inUrl]);

  function edit(patch: Partial<RubroDraft>) {
    setDone(false);
    setState({});
    if (patch.name !== undefined) setErrors((e) => ({ ...e, name: undefined }));
    setDraft((d) => ({ ...d, ...patch }));
  }

  function nameError(): string | undefined {
    const name = schemas.rubroName.safeParse({ name: draft.name });
    return name.success ? undefined : (name.error.issues[0]?.message ?? "Revisá el nombre.");
  }

  function save() {
    const found = {
      name: nameError(),
      reason: reasonField.min(3).safeParse(reason).success
        ? undefined
        : "Escribí el motivo de los cambios.",
    };
    setErrors(found);
    if (found.name || found.reason) {
      setState({ status: "bad", message: found.name ?? found.reason });
      document.getElementById(`${prefix}-${found.name ? "nombre" : "motivo"}`)?.focus();
      return;
    }
    startSave(async () => {
      try {
        const result = await saveRubroAction({
          rubroClass: sheet.rubroClass,
          id: sheet.id,
          expectedStamp: sheet.stamp,
          changes,
          reason,
        });
        if (result.status !== "ok") return setState(result);
        setState({});
        setReason("");
        setDone(true);
        router.refresh();
      } catch {
        // Sin conexión: el borrador queda y se puede reintentar.
        setState({
          status: "bad",
          message: "No pudimos guardar: revisá la conexión y probá de nuevo.",
        });
      }
    });
  }

  const label = "text-sm font-medium text-ink";
  const purchase = sheet.rubroClass === "purchase";
  return (
    <section
      aria-label={`Ficha de ${sheet.name}`}
      className="flex min-w-0 flex-col rounded-md border border-line bg-surface xl:min-h-0"
    >
      <div className="relative flex flex-col gap-4 p-4 xl:min-h-0 xl:flex-[1_1_0px] xl:overflow-y-auto">
        <ScrollFocus />
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
          <RubroIcon icon={draft.icon} className="size-6 shrink-0 text-ink" />
          <h2 className="text-xl font-semibold [overflow-wrap:anywhere] text-ink">{sheet.name}</h2>
          <span className="text-sm text-ink-muted tabular-nums">{sheet.code}</span>
          {sheet.isActive ? (
            <Badge status="ok">Activo</Badge>
          ) : (
            <Badge status="none">De baja</Badge>
          )}
          <div className="flex flex-wrap items-center gap-2 desk:ml-auto">
            {see ? (
              <Button asChild variant="outline">
                <Link href={see.href}>{see.label}</Link>
              </Button>
            ) : null}
            {status}
          </div>
        </div>
        {metrics}
        {canManage ? (
          <div className="grid gap-4 xl:grid-cols-2">
            <div className="flex min-w-0 flex-col gap-4">
              <div className="flex flex-col gap-1">
                <label htmlFor={`${prefix}-nombre`} className={label}>
                  Nombre <span aria-hidden="true">*</span>
                </label>
                <Input
                  id={`${prefix}-nombre`}
                  value={draft.name}
                  maxLength={80}
                  aria-required="true"
                  aria-invalid={errors.name ? "true" : undefined}
                  aria-describedby={
                    [
                      errors.name && `${prefix}-nombre-error`,
                      "name" in changes && `${prefix}-nombre-cambio`,
                    ]
                      .filter(Boolean)
                      .join(" ") || undefined
                  }
                  onChange={(e) => edit({ name: e.target.value })}
                  onBlur={() => setErrors((e) => ({ ...e, name: nameError() }))}
                  className={cn("name" in changes && changedRing)}
                />
                {errors.name ? (
                  <p id={`${prefix}-nombre-error`} className="text-sm text-bad-ink">
                    {errors.name}
                  </p>
                ) : null}
                <Unsaved id={`${prefix}-nombre-cambio`} show={"name" in changes} />
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor={`${prefix}-descripcion`} className={label}>
                  Descripción
                </label>
                <Textarea
                  id={`${prefix}-descripcion`}
                  rows={4}
                  value={draft.description}
                  maxLength={RUBRO_DESCRIPTION_MAX}
                  placeholder="Qué entra en este rubro y qué se controla al recibirlo."
                  aria-describedby={
                    "description" in changes ? `${prefix}-descripcion-cambio` : undefined
                  }
                  onChange={(e) => edit({ description: e.target.value })}
                  className={cn("description" in changes && changedRing)}
                />
                <Unsaved id={`${prefix}-descripcion-cambio`} show={"description" in changes} />
              </div>
            </div>
            <div className="flex min-w-0 flex-col gap-4">
              <fieldset
                className={cn(
                  "flex flex-col gap-1 rounded-sm border border-transparent",
                  "icon" in changes && changedRing,
                )}
              >
                <legend className={label}>
                  Ícono: <span className="font-normal">{RUBRO_ICON_LABELS[draft.icon]}</span>
                  {"icon" in changes ? (
                    <span className="sr-only"> (cambio sin guardar)</span>
                  ) : null}
                </legend>
                <div className="flex flex-wrap gap-1 p-1">
                  {RUBRO_ICONS.map((icon) => (
                    <label
                      key={icon}
                      className="inline-flex size-touch cursor-pointer items-center justify-center rounded-sm border border-line text-ink hover:border-primary has-checked:border-primary has-checked:bg-nav-active has-checked:text-nav-active-ink has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-primary desk:size-control"
                    >
                      <input
                        type="radio"
                        name={`${prefix}-icono`}
                        value={icon}
                        checked={draft.icon === icon}
                        onChange={() => edit({ icon })}
                        className="sr-only"
                      />
                      <RubroIcon icon={icon} className="size-5" />
                      <span className="sr-only">{RUBRO_ICON_LABELS[icon]}</span>
                    </label>
                  ))}
                </div>
              </fieldset>
              {purchase ? (
                <ToggleField
                  key={`${sheet.stamp}-recetas`}
                  id={`${prefix}-recetas`}
                  name="used_in_recipes"
                  label="¿Va a recetas?"
                  defaultValue={saved.usedInRecipes}
                  value={draft.usedInRecipes}
                  onChange={(usedInRecipes) => edit({ usedInRecipes })}
                />
              ) : null}
              <Subcategories names={sheet.subcategories} href={settingsHref} />
            </div>
          </div>
        ) : (
          <dl className="flex flex-col gap-3 text-base text-ink">
            <div>
              <dt className="text-sm text-ink-muted">Descripción</dt>
              <dd className="whitespace-pre-line">{sheet.description ?? "Sin descripción."}</dd>
            </div>
            {purchase ? (
              <div>
                <dt className="text-sm text-ink-muted">¿Va a recetas?</dt>
                <dd>{sheet.usedInRecipes ? "Sí" : "No"}</dd>
              </div>
            ) : null}
          </dl>
        )}
        {canManage ? null : <Subcategories names={sheet.subcategories} href={settingsHref} />}
      </div>
      {canManage ? (
        <div className="flex flex-col gap-2 rounded-b-md border-t border-line bg-surface p-3">
          <FormNotice state={state} />
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-base font-semibold text-ink" role="status">
              {pending ? "Guardando…" : changesLabel(count)}
            </span>
            <div className="mr-auto">
              {done && !pending && count === 0 ? (
                <Notice status="ok" className="items-center px-3 py-1 text-sm">
                  Cambios guardados.
                </Notice>
              ) : null}
            </div>
            <label htmlFor={`${prefix}-motivo`} className={label}>
              Motivo<span className="sr-only"> de los cambios</span>{" "}
              <span aria-hidden="true">*</span>
            </label>
            <Input
              id={`${prefix}-motivo`}
              placeholder="Obligatorio: por qué cambia"
              aria-required="true"
              className="w-full desk:w-64"
              maxLength={500}
              aria-invalid={errors.reason ? "true" : undefined}
              aria-describedby={errors.reason ? `${prefix}-motivo-error` : undefined}
              value={reason}
              onChange={(e) => {
                setReason(e.target.value);
                setErrors((found) => ({ ...found, reason: undefined }));
              }}
            />
            {errors.reason ? (
              <span id={`${prefix}-motivo-error`} className="sr-only">
                {errors.reason}
              </span>
            ) : null}
            <Button
              type="button"
              variant="outline"
              disabled={pending || count === 0}
              onClick={() => {
                setDraft(saved);
                setReason("");
                setErrors({});
                setState({});
              }}
            >
              Descartar
            </Button>
            <Button type="button" disabled={pending || count === 0} onClick={save}>
              {pending ? "Guardando…" : "Guardar cambios"}
            </Button>
          </div>
        </div>
      ) : null}
    </section>
  );
}

// El borde punteado es visual: el lector de pantalla lo escucha.
function Unsaved({ id, show }: { id: string; show: boolean }) {
  return show ? (
    <span id={id} className="sr-only">
      Cambio sin guardar
    </span>
  ) : null;
}

function Subcategories({ names, href }: { names: string[]; href: string | null }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-sm font-medium text-ink">Subcategorías</span>
      <div className="flex flex-wrap items-center gap-2 text-sm">
        {names.length === 0 ? <span className="text-ink-muted">Sin subcategorías.</span> : null}
        {names.map((n) => (
          <span key={n} className="rounded-sm bg-none px-2 py-0.5 text-none-ink">
            {n}
          </span>
        ))}
        {href ? (
          <Link
            href={href}
            className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline desk:min-h-8"
          >
            Editar en Configuración
          </Link>
        ) : null}
      </div>
    </div>
  );
}
