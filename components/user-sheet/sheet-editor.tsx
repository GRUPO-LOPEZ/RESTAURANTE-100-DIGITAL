"use client";

import { createContext, useContext, useId, useMemo, useRef, useState, useTransition } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Plus, Undo2 } from "lucide-react";

import { saveUserSheetAction } from "@/app/usuarios/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Input, Select } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { reasonField, userSheetSchema } from "@/lib/forms/schemas";
import { changesLabel } from "@/lib/recipe-sheet";
import {
  countUserChanges,
  hasRole,
  userChanges,
  userPayload,
  type UserChanges,
  type UserDraft,
  type UserField,
} from "@/lib/user-sheet";
import { cn } from "@/lib/utils";

// Ficha de la persona en una pantalla (Tanda 1 de Soy, ADR-0062), con el patrón de las fichas sin scroll (ADR-0046): un
// borrador con los datos y los roles que se guarda junto, con motivo (core.save_user_sheet). Qué puede hacer cada
// sesión lo dice la base (core.user_sheet_state). En el celular, de consulta.

export type UserSheetOptions = {
  areas: { id: string; label: string }[];
  roles: { code: string; name: string }[];
  places: { value: string; label: string }[];
  canEditProfile: boolean;
  // Puesto y área: no dan permisos, piden menos que el nombre.
  canEditJob: boolean;
  canAssign: boolean;
  revocable: string[];
};

type Ctx = {
  prefix: string;
  editable: boolean;
  options: UserSheetOptions;
  saved: UserDraft;
  draft: UserDraft;
  setDraft: (update: (d: UserDraft) => UserDraft) => void;
  changed: UserChanges;
  count: number;
  reason: string;
  setReason: (v: string) => void;
  state: ActionState;
  pending: boolean;
  notice: { status: "ok" | "info"; text: string } | null;
  discard: () => void;
  save: () => Promise<void>;
  // «Dar otro rol»: lo elegido y todavía no agregado (no se pierde al guardar sin avisar).
  pick: { role: string; place: string };
  setPick: (pick: { role: string; place: string }) => void;
  pickError: string;
  setPickError: (error: string) => void;
};

const SheetContext = createContext<Ctx | null>(null);

function useSheet(): Ctx {
  const ctx = useContext(SheetContext);
  if (!ctx) throw new Error("Falta UserSheetProvider.");
  return ctx;
}

export function UserSheetProvider({
  userId,
  stamp,
  editable,
  initial,
  options,
  notice = null,
  children,
}: {
  userId: string;
  stamp: string;
  editable: boolean;
  initial: UserDraft;
  options: UserSheetOptions;
  notice?: { status: "ok" | "info"; text: string } | null;
  children: React.ReactNode;
}) {
  const prefix = useId();
  const router = useRouter();
  const pathname = usePathname();
  const search = useSearchParams();
  const [saved, setSaved] = useState(initial);
  const [draft, setDraftState] = useState(initial);
  const [reason, setReason] = useState("");
  const [state, setState] = useState<ActionState>({});
  const [saving, setPending] = useState(false);
  // Hasta que vuelve la ficha guardada, sigue «Guardando…»: si no, diría «1 cambio sin guardar» con el cambio ya guardado.
  const [returning, startReturn] = useTransition();
  const pending = saving || returning;
  const [pick, setPick] = useState({ role: "", place: "" });
  const [pickError, setPickError] = useState("");
  const changed = useMemo(() => userChanges(saved, draft), [saved, draft]);
  const count = countUserChanges(changed);
  const picking = pick.role !== "" || pick.place !== "";
  useUnsavedWarning(editable && (count > 0 || picking));
  // Guardado: cuando vuelve la ficha con su sello nuevo, el borrador es lo que dice la base (un rol que espera una
  // aprobación no figura como dado, y uno nuevo llega con su id).
  const [refresh, setRefresh] = useState(false);
  const [seenStamp, setSeenStamp] = useState(stamp);
  if (stamp !== seenStamp) {
    setSeenStamp(stamp);
    setSaved(initial);
    if (count === 0 || refresh) setDraftState(initial);
    setRefresh(false);
  }

  function discard() {
    setDraftState(saved);
    setPick({ role: "", place: "" });
    setPickError("");
    setState({});
  }

  async function save() {
    if (picking) {
      setState({
        status: "bad",
        message:
          "Elegiste un rol y no lo agregaste: tocá «Agregar a los cambios» o dejalo en «Elegí el rol».",
      });
      document.getElementById(`${prefix}-rol`)?.focus();
      return;
    }
    const parsed = userSheetSchema.safeParse({
      userId,
      expectedStamp: stamp,
      reason,
      changes: userPayload(saved, draft),
    });
    if (!parsed.success) {
      const issue = parsed.error.issues[0];
      if (!reasonField.safeParse(reason).success && issue?.path[0] === "reason") {
        setState({ status: "bad", message: "Escribí el motivo de los cambios." });
        document.getElementById(`${prefix}-motivo`)?.focus();
      } else {
        setState({ status: "bad", message: issue?.message ?? "Revisá los datos." });
      }
      return;
    }
    setPending(true);
    try {
      const result = await saveUserSheetAction(parsed.data);
      const done = result.status === "ok" || result.status === "info";
      setState(done ? {} : result);
      if (done) {
        setReason("");
        if (result.gone) {
          // Se quedó sin roles en el alcance de esta sesión: su ficha ya no se ve desde acá.
          setDraftState(saved);
          router.replace("/usuarios/lista?aviso=fuera");
          return;
        }
        setRefresh(true);
        // Si solo se pidió un rol, la ficha no cambia (el sello es el mismo): se vuelve a lo guardado.
        setDraftState((d) => ({
          fields: d.fields,
          roles: saved.roles,
        }));
        const q = new URLSearchParams(search.toString());
        q.set("aviso", result.status === "ok" ? "guardado" : "pendiente");
        startReturn(() => router.replace(`${pathname}?${q}`, { scroll: false }));
      }
    } catch {
      // Sin conexión: el borrador queda y se puede reintentar.
      setState({
        status: "bad",
        message: "No pudimos guardar: revisá la conexión y probá de nuevo.",
      });
    } finally {
      setPending(false);
    }
  }

  const value: Ctx = {
    prefix,
    editable,
    options,
    saved,
    draft,
    setDraft: (update) => {
      // Si se sigue editando antes de que vuelva lo guardado, no se pisa.
      setRefresh(false);
      setDraftState((d) => update(d));
    },
    changed,
    count,
    reason,
    setReason,
    state,
    pending,
    notice,
    discard,
    save,
    pick,
    setPick,
    pickError,
    setPickError,
  };
  return <SheetContext.Provider value={value}>{children}</SheetContext.Provider>;
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------
const changedRing = "border-dashed border-ink";
const labelClass = "text-sm font-medium text-ink";
// Tarjetas angostas: controles de 32 px en la computadora (44 en el celular; ADR-0046).
const small = "desk:min-h-8";
const selectText = "text-sm";
const pickRow = "grid items-center gap-x-2 gap-y-1 desk:grid-cols-[4rem_1fr]";
const row = "grid items-center gap-x-3 gap-y-1 desk:grid-cols-[7rem_1fr]";

export function ReadRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className={row}>
      <dt className={labelClass}>{label}</dt>
      <dd className="min-w-0 text-sm break-words text-ink-muted">{value || "—"}</dd>
    </div>
  );
}

function TextRow({
  field,
  label,
  maxLength,
  required = false,
}: {
  field: UserField;
  label: string;
  maxLength: number;
  required?: boolean;
}) {
  const { prefix, saved, draft, setDraft, changed, options } = useSheet();
  const [left, setLeft] = useState(false);
  const id = `${prefix}-${field}`;
  const read = <ReadRow label={label} value={saved.fields[field]} />;
  const can = field === "job_title" ? options.canEditJob : options.canEditProfile;
  if (!can) return <dl>{read}</dl>;
  const invalid = required && left && draft.fields[field].trim() === "";
  return (
    <>
      <div className={cn(row, "hidden desk:grid")}>
        <label htmlFor={id} className={labelClass}>
          {label}
          {required ? <span aria-hidden="true"> *</span> : null}
        </label>
        <div className="flex min-w-0 flex-col">
          <Input
            id={id}
            value={draft.fields[field]}
            maxLength={maxLength}
            aria-required={required ? "true" : undefined}
            aria-invalid={invalid ? "true" : undefined}
            aria-describedby={invalid ? `${id}-falta` : undefined}
            onBlur={() => setLeft(true)}
            onChange={(e) =>
              setDraft((d) => ({ ...d, fields: { ...d.fields, [field]: e.target.value } }))
            }
            className={cn(small, changed.fields.includes(field) && changedRing)}
          />
          {invalid ? (
            <span id={`${id}-falta`} className="text-xs font-medium text-bad-ink">
              {field === "last_name" ? "Escribí el apellido." : "Escribí el nombre."}
            </span>
          ) : null}
        </div>
      </div>
      <dl className="desk:hidden">{read}</dl>
    </>
  );
}

export function ProfileFields() {
  const { prefix, saved, draft, setDraft, changed, options } = useSheet();
  const areaName = options.areas.find((a) => a.id === saved.fields.area_id)?.label ?? "";
  return (
    <div className="flex flex-col gap-1">
      <TextRow field="first_name" label="Nombre" maxLength={80} required />
      <TextRow field="last_name" label="Apellido" maxLength={80} required />
      <TextRow field="job_title" label="Puesto" maxLength={80} />
      {options.canEditJob ? (
        <>
          <div className="hidden flex-col gap-1 desk:flex">
            <label htmlFor={`${prefix}-area`} className={labelClass}>
              Área
            </label>
            <Select
              id={`${prefix}-area`}
              value={draft.fields.area_id}
              onChange={(e) =>
                setDraft((d) => ({ ...d, fields: { ...d.fields, area_id: e.target.value } }))
              }
              className={cn(
                small,
                selectText,
                "w-full",
                changed.fields.includes("area_id") && changedRing,
              )}
            >
              <option value="">Sin área</option>
              {options.areas.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.label}
                </option>
              ))}
            </Select>
          </div>
          <dl className="desk:hidden">
            <ReadRow label="Área" value={areaName} />
          </dl>
        </>
      ) : (
        <dl>
          <ReadRow label="Área" value={areaName} />
        </dl>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Roles y dónde los usa, con «Dar otro rol» en la misma tarjeta
// ---------------------------------------------------------------------------
export function RolesSection() {
  const {
    prefix,
    draft,
    setDraft,
    changed,
    options,
    pick,
    setPick,
    pickError: error,
    setPickError: setError,
  } = useSheet();
  const { role, place } = pick;
  const next = useRef(1);
  const shown = draft.roles.filter((r) => r.assignmentId || !r.removed);

  function add() {
    const r = options.roles.find((x) => x.code === role);
    const p = options.places.find((x) => x.value === place);
    if (!r || !p) {
      setError("Elegí el rol y dónde lo va a usar.");
      return;
    }
    if (hasRole(draft, r.code, p.label)) {
      setError("Ese rol ya está en ese lugar.");
      return;
    }
    setError("");
    setDraft((d) => ({
      ...d,
      roles: [
        ...d.roles,
        {
          key: `nuevo-${next.current++}`,
          assignmentId: null,
          roleCode: r.code,
          roleName: r.name,
          place: p.value,
          placeLabel: p.label,
          removed: false,
        },
      ],
    }));
    setPick({ role: "", place: "" });
  }

  const setRemoved = (key: string, removed: boolean) =>
    setDraft((d) => ({
      ...d,
      roles: d.roles
        .map((r) => (r.key === key ? { ...r, removed } : r))
        // Uno nuevo que se quita, desaparece.
        .filter((r) => r.assignmentId || !r.removed),
    }));

  return (
    <div className="flex flex-col gap-3">
      {shown.length === 0 ? (
        <p className="text-sm text-ink-muted">No tiene roles vigentes.</p>
      ) : null}
      <ul aria-label="Roles" className="flex flex-col gap-1">
        {shown.map((r) => {
          const isChange = changed.roles.includes(r.key);
          const label = `${r.roleName} · ${r.placeLabel}`;
          const canRemove = !r.assignmentId || options.revocable.includes(r.assignmentId);
          return (
            <li
              key={r.key}
              className={cn(
                "flex items-center justify-between gap-2 rounded-sm border border-transparent px-2 py-1 text-sm",
                isChange && changedRing,
              )}
            >
              <span className="min-w-0 text-ink">
                <span className={cn(r.removed && "line-through")}>
                  <span className="font-medium">{r.roleName}</span>{" "}
                  <span className="text-ink-muted">· {r.placeLabel}</span>
                </span>
                {isChange ? (
                  <span className="text-xs text-ink-muted">
                    {" "}
                    {r.removed ? "(se quita al guardar)" : "(nuevo, sin guardar)"}
                  </span>
                ) : null}
              </span>
              {canRemove ? (
                <button
                  type="button"
                  aria-label={r.removed ? `Volver a dejar ${label}` : `Quitar ${label}`}
                  className="hidden min-h-8 shrink-0 items-center gap-1 text-sm text-primary underline-offset-4 hover:underline desk:inline-flex"
                  onClick={() => {
                    setRemoved(r.key, !r.removed);
                    if (!r.assignmentId) document.getElementById(`${prefix}-rol`)?.focus();
                  }}
                >
                  {r.removed ? (
                    <>
                      <Undo2 aria-hidden="true" className="size-4" />
                      Dejar
                    </>
                  ) : (
                    "Quitar"
                  )}
                </button>
              ) : null}
            </li>
          );
        })}
      </ul>
      {options.canAssign ? (
        <fieldset className="hidden flex-col gap-2 rounded-sm border border-line p-3 desk:flex">
          <legend className="px-1 text-sm font-medium text-ink">Dar otro rol</legend>
          <div className={pickRow}>
            <label htmlFor={`${prefix}-rol`} className={labelClass}>
              Rol
            </label>
            <Select
              id={`${prefix}-rol`}
              value={role}
              aria-invalid={error ? "true" : undefined}
              aria-describedby={error ? `${prefix}-rol-error` : undefined}
              onChange={(e) => {
                setError("");
                setPick({ role: e.target.value, place });
              }}
              className={cn(small, selectText, "w-full")}
            >
              <option value="">Elegí el rol</option>
              {options.roles.map((r) => (
                <option key={r.code} value={r.code}>
                  {r.name}
                </option>
              ))}
            </Select>
          </div>
          <div className={pickRow}>
            <label htmlFor={`${prefix}-lugar`} className={labelClass}>
              Dónde
            </label>
            <Select
              id={`${prefix}-lugar`}
              value={place}
              aria-invalid={error ? "true" : undefined}
              aria-describedby={error ? `${prefix}-rol-error` : undefined}
              onChange={(e) => {
                setError("");
                setPick({ role, place: e.target.value });
              }}
              className={cn(small, selectText, "w-full")}
            >
              <option value="">Elegí el lugar</option>
              {options.places.map((p) => (
                <option key={p.value} value={p.value}>
                  {p.label}
                </option>
              ))}
            </Select>
          </div>
          {error ? (
            <p id={`${prefix}-rol-error`} role="alert" className="text-sm text-bad-ink">
              {error}
            </p>
          ) : null}
          <Button type="button" variant="outline" className={cn(small, "self-start")} onClick={add}>
            <Plus aria-hidden="true" />
            Agregar a los cambios
          </Button>
        </fieldset>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Barra fija: contador, motivo, Descartar y Guardar cambios
// ---------------------------------------------------------------------------
export function SheetBar() {
  const { prefix, editable, count, reason, setReason, state, pending, discard, save, notice } =
    useSheet();
  if (!editable) return null;
  return (
    <div className="sticky bottom-0 z-10 -mx-gutter hidden flex-col gap-2 border-t border-line bg-surface px-gutter py-2 desk:flex wide:-mx-gutter-wide wide:px-gutter-wide">
      <FormNotice state={state} />
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-base font-semibold text-ink" role="status">
          {changesLabel(count)}
        </span>
        <div className="mr-auto">
          {notice && count === 0 ? (
            <Notice status={notice.status} className="items-center px-3 py-1 text-sm">
              {notice.text}
            </Notice>
          ) : null}
        </div>
        <label htmlFor={`${prefix}-motivo`} className="text-sm font-medium text-ink">
          Motivo<span className="sr-only"> de los cambios</span>
        </label>
        <span aria-hidden="true" className="-ml-1 text-sm font-medium text-ink">
          *
        </span>
        <Input
          id={`${prefix}-motivo`}
          placeholder="Obligatorio: por qué cambia"
          aria-required="true"
          className="w-80"
          maxLength={500}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
        <Button type="button" variant="outline" disabled={pending || count === 0} onClick={discard}>
          Descartar
        </Button>
        <Button type="button" disabled={pending || count === 0} onClick={() => void save()}>
          {pending ? "Guardando…" : "Guardar cambios"}
        </Button>
      </div>
    </div>
  );
}
