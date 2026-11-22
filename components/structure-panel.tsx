"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";

import {
  createBrandAction,
  peekBrandCodeAction,
  updateBrandAction,
} from "@/app/configuracion/structure-actions";
import { ActionForm } from "@/components/action-form";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { SidePanel } from "@/components/ui/dialog";
import { Input } from "@/components/ui/field";
import { FormInput, FormTextarea } from "@/components/ui/form";
import { SegmentedField } from "@/components/ui/segmented-field";
import type { ActionState } from "@/lib/auth/results";
import { codeWord } from "@/lib/org-codes";

// Piezas del Panel de control en una pantalla (Tanda 1 de Soy, ADR-0061) que viven en el navegador: la fila «Nueva
// marca» al final de la lista (con el código que va a tener), el panel de una marca (su ficha: nombre, nombre corto,
// estado y sus locales) y el panel de los datos que faltan. La base controla cada cambio.

const linkClass =
  "inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8";

// ---------------------------------------------------------------------------
// «Nueva marca», en la misma lista
// ---------------------------------------------------------------------------
export function NewBrandRow({ groupId, nextNumber }: { groupId: string; nextNumber: number }) {
  const router = useRouter();
  const [name, setName] = useState("");
  const [short, setShort] = useState("");
  const [reason, setReason] = useState("");
  const [preview, setPreview] = useState<string | null>(null);
  const [state, setState] = useState<ActionState>({});
  const [pending, setPending] = useState(false);
  // El nombre corto sale de la palabra distintiva del nombre; se puede cambiar.
  const shortName = short || name.trim().split(/\s+/).at(-1) || "";
  const number = String(nextNumber).padStart(2, "0");

  useEffect(() => {
    if (!shortName) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      void peekBrandCodeAction(groupId, shortName).then((code) => {
        if (!cancelled) setPreview(code);
      });
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [groupId, shortName]);

  async function create() {
    const data = new FormData();
    data.set("groupId", groupId);
    data.set("name", name);
    data.set("short_name", shortName);
    data.set("code_word", "");
    data.set("reason", reason);
    setPending(true);
    try {
      const result = await createBrandAction({}, data);
      setState(result);
      if (result.status === "ok") {
        setName("");
        setShort("");
        setReason("");
        router.refresh();
      }
    } finally {
      setPending(false);
    }
  }

  const code = shortName ? (preview ?? `${number}-${codeWord(shortName)}`) : `${number}-`;
  return (
    <div className="flex flex-col gap-2 border-t border-line pt-3">
      <FormNotice state={state} />
      <div className="flex flex-wrap items-end gap-2">
        <Badge status="neutral" className="tabular-nums">
          {code}
        </Badge>
        <div className="flex min-w-40 flex-1 flex-col gap-1">
          <label htmlFor="marca-nueva-nombre" className="text-sm font-medium text-ink">
            Nueva marca
          </label>
          <Input
            id="marca-nueva-nombre"
            placeholder="Nombre de la marca"
            value={name}
            maxLength={120}
            onChange={(e) => setName(e.target.value)}
            className="desk:min-h-8"
          />
        </div>
        <div className="flex w-32 flex-col gap-1">
          <label htmlFor="marca-nueva-corto" className="text-sm font-medium text-ink">
            Nombre corto
          </label>
          <Input
            id="marca-nueva-corto"
            placeholder={shortName || "Ragú"}
            value={short}
            maxLength={40}
            onChange={(e) => setShort(e.target.value)}
            className="desk:min-h-8"
          />
        </div>
        <div className="flex min-w-40 flex-1 flex-col gap-1">
          <label htmlFor="marca-nueva-motivo" className="text-sm font-medium text-ink">
            Motivo<span aria-hidden="true"> *</span>
          </label>
          <Input
            id="marca-nueva-motivo"
            placeholder="Por qué se crea"
            aria-required="true"
            value={reason}
            maxLength={500}
            onChange={(e) => setReason(e.target.value)}
            className="desk:min-h-8"
          />
        </div>
        <Button
          type="button"
          variant="outline"
          className="desk:min-h-8"
          disabled={pending || !name.trim()}
          onClick={() => void create()}
        >
          <Plus aria-hidden="true" />
          {pending ? "Creando…" : "Crear marca"}
        </Button>
      </div>
      <p className="text-xs text-ink-muted">
        El número se pone solo. El nombre corto arma el nombre de sus locales («Ragú Leloir») y el
        código.
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// La ficha de una marca, en un panel lateral
// ---------------------------------------------------------------------------
export function BrandPanelButton({
  brand,
  places,
  canEditStatus,
  startOpen = false,
}: {
  brand: {
    id: string;
    name: string;
    shortName: string;
    code: string;
    status: "active" | "inactive";
  };
  places: { id: string; code: string | null; name: string; state: string }[];
  canEditStatus: boolean;
  startOpen?: boolean;
}) {
  const [open, setOpen] = useState(startOpen);
  const opener = useRef<HTMLButtonElement>(null);
  return (
    <>
      <button
        ref={opener}
        type="button"
        className={linkClass}
        aria-haspopup="dialog"
        aria-label={`Editar la marca ${brand.name}`}
        onClick={() => setOpen(true)}
      >
        Editar
      </button>
      <SidePanel
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) requestAnimationFrame(() => opener.current?.focus());
        }}
        title={brand.name}
        description={`Código ${brand.code}. El código no cambia: arma los códigos de sus locales.`}
      >
        <ActionForm action={updateBrandAction} schema="brandUpdate" submitLabel="Guardar marca">
          <input type="hidden" name="brandId" value={brand.id} />
          <FormInput
            id="marca-editar-nombre"
            name="name"
            label="Nombre"
            defaultValue={brand.name}
            required
            maxLength={120}
          />
          <FormInput
            id="marca-editar-corto"
            name="short_name"
            label="Nombre corto"
            defaultValue={brand.shortName}
            required
            maxLength={40}
            hint="Arma el nombre de sus locales: si cambia, cambian sus nombres (sus códigos, no)."
          />
          {canEditStatus ? (
            <SegmentedField
              id="marca-editar-estado"
              name="status"
              label="Estado"
              options={[
                { value: "active", label: "Activa" },
                { value: "inactive", label: "Inactiva" },
              ]}
              defaultValue={brand.status}
            />
          ) : null}
          <FormTextarea
            id="marca-editar-motivo"
            name="reason"
            label="Motivo"
            hint="Queda en el historial."
            required
            maxLength={500}
          />
        </ActionForm>
        <section aria-label="Sus locales" className="flex flex-col gap-2">
          <h3 className="text-base font-semibold text-ink">Sus locales</h3>
          {places.length === 0 ? (
            <p className="text-sm text-ink-muted">Todavía no tiene locales.</p>
          ) : (
            <ul className="flex flex-col gap-1">
              {places.map((p) => (
                <li key={p.id} className="flex items-baseline justify-between gap-2 text-sm">
                  <Link href={`/configuracion/locales/${p.id}`} className={linkClass}>
                    {p.code ? `${p.code} · ${p.name}` : p.name}
                  </Link>
                  <span className="text-ink-muted">{p.state}</span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </SidePanel>
    </>
  );
}

// ---------------------------------------------------------------------------
// «Completar»: los locales con datos obligatorios sin cargar
// ---------------------------------------------------------------------------
export function MissingPanelButton({
  places,
}: {
  places: { id: string; name: string; missing: string[] }[];
}) {
  const [open, setOpen] = useState(false);
  const opener = useRef<HTMLButtonElement>(null);
  return (
    <>
      <button
        ref={opener}
        type="button"
        className={linkClass}
        aria-haspopup="dialog"
        onClick={() => setOpen(true)}
      >
        Completar
      </button>
      <SidePanel
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) requestAnimationFrame(() => opener.current?.focus());
        }}
        title="Datos que faltan"
        description="Los locales que ya están abiertos no se traban, pero para volver a abrir o abrir uno nuevo hacen falta."
      >
        <ul className="flex flex-col gap-3">
          {places.map((p) => (
            <li key={p.id} className="flex flex-col gap-1 border-b border-line pb-2">
              <Link href={`/configuracion/locales/${p.id}`} className={linkClass}>
                {p.name}
              </Link>
              <span className="text-sm text-ink-muted">Falta: {p.missing.join(", ")}.</span>
            </li>
          ))}
        </ul>
      </SidePanel>
    </>
  );
}
