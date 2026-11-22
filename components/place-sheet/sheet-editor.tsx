"use client";

import { createContext, useContext, useId, useMemo, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Check, MapPin, Plus, Search, Undo2, X } from "lucide-react";

import { findAddressAction, savePlaceSheetAction } from "@/app/configuracion/structure-actions";
import { FormNotice } from "@/components/form-notice";
import { OrgMap } from "@/components/org-map";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input, Select } from "@/components/ui/field";
import { InfoTip } from "@/components/ui/info-tip";
import { Notice } from "@/components/ui/notice";
import { Segmented } from "@/components/ui/segmented";
import { useUnsavedWarning } from "@/components/use-unsaved-warning";
import type { ActionState } from "@/lib/auth/results";
import { placeSheetSchema, reasonField } from "@/lib/forms/schemas";
import {
  OPEN_STATE_OPTIONS,
  SITE_TYPE_OPTIONS,
  countRestaurantChanges,
  restaurantChanges,
  restaurantMissing,
  restaurantPayload,
  type OpenState,
  type RestaurantChanges,
  type RestaurantDraft,
  type RestaurantField,
  type SiteType,
} from "@/lib/org-sheet";
import { restaurantName } from "@/lib/org-codes";
import { changesLabel } from "@/lib/recipe-sheet";
import { cn } from "@/lib/utils";

// Ficha del local en una pantalla (Tanda 1 de Soy, ADR-0061), con el patrón de las fichas sin scroll (ADR-0046): la
// página pone cada sección en su tarjeta; lo que se edita comparte un borrador y se guarda junto, con motivo, en una
// transacción (org.save_restaurant_sheet). Qué puede cambiar cada persona lo decide la base (los mismos permisos de
// siempre); la pantalla solo oculta lo que no le toca. En el celular, de consulta.

export type PlaceSheetOptions = {
  brandShortName: string;
  provinces: { code: string; name: string }[];
  legalEntities: { id: string; name: string; taxId: string; vatLabel: string }[];
  canEditBrandLevel: boolean;
  canEditGroupLevel: boolean;
  closed: boolean;
};

type Ctx = {
  placeId: string;
  prefix: string;
  editable: boolean;
  options: PlaceSheetOptions;
  saved: RestaurantDraft;
  draft: RestaurantDraft;
  setDraft: (update: (d: RestaurantDraft) => RestaurantDraft) => void;
  changed: RestaurantChanges;
  count: number;
  reason: string;
  setReason: (v: string) => void;
  state: ActionState;
  pending: boolean;
  notice: { status: "ok" | "info"; text: string } | null;
  discard: () => void;
  save: () => Promise<void>;
};

const SheetContext = createContext<Ctx | null>(null);

function useSheet(): Ctx {
  const ctx = useContext(SheetContext);
  if (!ctx) throw new Error("Falta PlaceSheetProvider.");
  return ctx;
}

export function PlaceSheetProvider({
  placeId,
  stamp,
  editable,
  initial,
  options,
  notice = null,
  children,
}: {
  placeId: string;
  stamp: string | null;
  editable: boolean;
  initial: RestaurantDraft;
  options: PlaceSheetOptions;
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
  const [pending, setPending] = useState(false);
  const changed = useMemo(() => restaurantChanges(saved, draft), [saved, draft]);
  const count = countRestaurantChanges(changed);
  useUnsavedWarning(editable && count > 0);
  // Después de guardar llega lo guardado con su sello nuevo: si no se empezó a editar otra cosa, se toma.
  const [seenStamp, setSeenStamp] = useState(stamp);
  if (stamp !== seenStamp) {
    setSeenStamp(stamp);
    setSaved(initial);
    if (count === 0) setDraftState(initial);
  }

  function discard() {
    setDraftState(saved);
    setState({});
  }

  async function save() {
    const parsed = placeSheetSchema.safeParse({
      placeId,
      expectedStamp: stamp ?? "",
      reason,
      changes: restaurantPayload(saved, draft),
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
      const result = await savePlaceSheetAction(parsed.data);
      setState(result.status === "ok" ? {} : result);
      if (result.status === "ok") {
        setSaved(draft);
        setReason("");
        const q = new URLSearchParams(search.toString());
        q.set("aviso", "guardado");
        router.replace(`${pathname}?${q}`, { scroll: false });
      }
    } finally {
      setPending(false);
    }
  }

  const value: Ctx = {
    placeId,
    prefix,
    editable,
    options,
    saved,
    draft,
    setDraft: (update) => setDraftState((d) => update(d)),
    changed,
    count,
    reason,
    setReason,
    state,
    pending,
    notice,
    discard,
    save,
  };
  return <SheetContext.Provider value={value}>{children}</SheetContext.Provider>;
}

// ---------------------------------------------------------------------------
// Piezas comunes
// ---------------------------------------------------------------------------
const changedRing = "border-dashed border-ink";
const labelClass = "text-sm font-medium text-ink";
// Tarjetas angostas: controles de 36 px en la computadora (44 en el celular; ADR-0046).
const small = "desk:min-h-control-sm";

function ReadRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex min-w-0 flex-col">
      <dt className={labelClass}>{label}</dt>
      <dd className="text-base break-words text-ink-muted">{value || "—"}</dd>
    </div>
  );
}

// Lo editable solo en la computadora; en el celular, lo mismo como texto (ADR-0036). Quien no edita ve el texto.
function Split({
  edit,
  read,
  can = true,
}: {
  edit: React.ReactNode;
  read: React.ReactNode;
  can?: boolean;
}) {
  const { editable } = useSheet();
  if (!editable || !can) return <>{read}</>;
  return (
    <>
      <div className="hidden desk:contents">{edit}</div>
      <div className="desk:hidden">{read}</div>
    </>
  );
}

function FieldInput({
  field,
  label,
  required = false,
  maxLength,
  type = "text",
  inputMode,
  placeholder,
}: {
  field: RestaurantField;
  label: string;
  required?: boolean;
  maxLength?: number;
  type?: string;
  inputMode?: React.HTMLAttributes<HTMLInputElement>["inputMode"];
  placeholder?: string;
}) {
  const { prefix, draft, setDraft, changed } = useSheet();
  const [left, setLeft] = useState(false);
  const id = `${prefix}-${field}`;
  const invalid = required && left && draft.fields[field].trim() === "";
  return (
    <div className="flex min-w-0 flex-col gap-1">
      <label htmlFor={id} className={labelClass}>
        {label}
        {required ? <span aria-hidden="true"> *</span> : null}
      </label>
      <Input
        id={id}
        type={type}
        inputMode={inputMode}
        value={draft.fields[field]}
        maxLength={maxLength}
        placeholder={placeholder}
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
          Falta
        </span>
      ) : null}
    </div>
  );
}

function formatDay(iso: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return "";
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

// ---------------------------------------------------------------------------
// «El local»: marca fija, zona, nombre automático, código fijo, tipo, estado y fecha de apertura
// ---------------------------------------------------------------------------
export function PlaceSection({ brandName, code }: { brandName: string; code: string | null }) {
  const { prefix, draft, saved, setDraft, changed, options, editable } = useSheet();
  const name = draft.fields.zone.trim()
    ? restaurantName(options.brandShortName, draft.fields.zone)
    : "";
  const siteLabel = SITE_TYPE_OPTIONS.find((o) => o.value === saved.siteType)?.label ?? "";
  const stateLabel = options.closed
    ? "Cerrado"
    : (OPEN_STATE_OPTIONS.find((o) => o.value === saved.state)?.label ?? "");
  return (
    <div className="flex flex-col gap-3">
      <dl className="grid grid-cols-2 gap-3">
        <ReadRow label="Marca" value={brandName} />
        <div className="flex min-w-0 flex-col">
          <dt className={cn(labelClass, "flex items-center gap-1")}>
            Código
            <InfoTip label="código del local">
              El código no cambia nunca: lo usan las órdenes de compra y el historial. Si el local
              se muda, cambia la zona y el nombre.
            </InfoTip>
          </dt>
          <dd>
            {code ? (
              <Badge status="neutral" className="tabular-nums">
                {code}
              </Badge>
            ) : (
              <span className="text-base text-ink-muted">Sin código</span>
            )}
          </dd>
        </div>
      </dl>
      <Split
        edit={<FieldInput field="zone" label="Zona o ubicación" required maxLength={80} />}
        read={
          <dl>
            <ReadRow label="Zona o ubicación" value={saved.fields.zone} />
          </dl>
        }
      />
      <p className="text-sm text-ink-muted">
        <span className="font-medium text-ink">Nombre:</span> {name || "—"}{" "}
        <span className="text-xs">(automático)</span>
      </p>
      <Split
        can={options.canEditBrandLevel}
        edit={
          <Segmented
            name={`${prefix}-tipo`}
            legend="Tipo"
            compact
            options={SITE_TYPE_OPTIONS}
            value={draft.siteType}
            changed={changed.siteType}
            onChange={(v) => setDraft((d) => ({ ...d, siteType: v as SiteType }))}
          />
        }
        read={
          <dl>
            <ReadRow label="Tipo" value={siteLabel} />
          </dl>
        }
      />
      <Split
        can={options.canEditBrandLevel && !options.closed}
        edit={
          <Segmented
            name={`${prefix}-estado`}
            legend="Estado"
            compact
            options={OPEN_STATE_OPTIONS}
            value={draft.state}
            changed={changed.state}
            onChange={(v) => setDraft((d) => ({ ...d, state: v as OpenState }))}
          />
        }
        read={
          <dl>
            <ReadRow label="Estado" value={stateLabel} />
          </dl>
        }
      />
      {editable && draft.state === "open" && saved.state === "opening" ? <OpenWarning /> : null}
      <Split
        edit={<FieldInput field="opened_on" label="Fecha de apertura" required type="date" />}
        read={
          <dl>
            <ReadRow label="Fecha de apertura" value={formatDay(saved.fields.opened_on)} />
          </dl>
        }
      />
    </div>
  );
}

// Antes de guardar, lo que falta para abrir (la base lo controla igual).
function OpenWarning() {
  const { draft } = useSheet();
  const missing = restaurantMissing(draft);
  if (missing.length === 0) return null;
  return (
    <Notice status="warn" className="px-3 py-2 text-sm">
      Para abrir el local falta: {missing.join(", ")}.
    </Notice>
  );
}

// ---------------------------------------------------------------------------
// «Ubicación y contacto»: dirección con Georef, localidad, provincia, CP, teléfono y mini mapa
// ---------------------------------------------------------------------------
export function LocationSection({ placeName }: { placeName: string }) {
  const { prefix, draft, saved, setDraft, changed, options, editable } = useSheet();
  const [searching, setSearching] = useState(false);
  const [lookup, setLookup] = useState<"" | "unavailable" | "not_found" | "short">("");

  async function search() {
    if (draft.fields.address.trim().length < 3) {
      setLookup("short");
      return;
    }
    setSearching(true);
    setLookup("");
    try {
      const result = await findAddressAction({
        address: draft.fields.address,
        locality: draft.fields.locality,
        province: draft.fields.province,
      });
      if (result.status === "found") {
        const m = result.match;
        setDraft((d) => ({
          ...d,
          fields: {
            ...d.fields,
            locality: d.fields.locality.trim() ? d.fields.locality : (m.locality ?? ""),
            province: m.provinceCode ?? d.fields.province,
          },
          geo: {
            status: "found",
            latitude: String(m.latitude),
            longitude: String(m.longitude),
            label: m.label,
          },
        }));
      } else {
        // No se encontró (o Georef no respondió): se guarda igual, «Sin ubicar en el mapa».
        setDraft((d) => ({
          ...d,
          geo: { status: "not_found", latitude: "", longitude: "", label: "" },
        }));
        setLookup(result.status === "unavailable" ? "unavailable" : "not_found");
      }
    } finally {
      setSearching(false);
    }
  }

  const geo = editable ? draft.geo : saved.geo;
  const provinceName = (code: string) => options.provinces.find((p) => p.code === code)?.name ?? "";
  const point =
    geo.status === "found" && geo.latitude && geo.longitude
      ? [
          {
            id: "local",
            name: placeName,
            latitude: Number(geo.latitude),
            longitude: Number(geo.longitude),
            kind: "restaurant" as const,
          },
        ]
      : [];

  return (
    <div className="flex h-full min-h-0 flex-col gap-3">
      <Split
        edit={
          <div className="flex flex-col gap-1">
            <label htmlFor={`${prefix}-address`} className={labelClass}>
              Dirección<span aria-hidden="true"> *</span>
            </label>
            <div className="flex gap-2">
              <Input
                id={`${prefix}-address`}
                value={draft.fields.address}
                maxLength={200}
                aria-required="true"
                placeholder="Calle y número"
                onChange={(e) =>
                  setDraft((d) => ({
                    ...d,
                    fields: { ...d.fields, address: e.target.value },
                    // Otra dirección: hay que volver a buscarla.
                    geo:
                      d.geo.status === ""
                        ? d.geo
                        : { status: "not_found", latitude: "", longitude: "", label: "" },
                  }))
                }
                className={cn(small, "flex-1", changed.fields.includes("address") && changedRing)}
              />
              <Button
                type="button"
                variant="outline"
                className={small}
                disabled={searching}
                onClick={() => void search()}
              >
                <Search aria-hidden="true" />
                {searching ? "Buscando…" : "Buscar"}
              </Button>
            </div>
          </div>
        }
        read={
          <dl>
            <ReadRow label="Dirección" value={saved.fields.address} />
          </dl>
        }
      />
      <div className="flex flex-wrap items-center gap-2" role="status">
        {geo.status === "found" ? (
          <>
            <Badge status="ok">
              <Check aria-hidden="true" className="size-3" />
              Encontrada
            </Badge>
            <span className="text-sm text-ink-muted">{geo.label}</span>
          </>
        ) : geo.status === "not_found" ? (
          <Badge status="none">
            <MapPin aria-hidden="true" className="size-3" />
            Sin ubicar en el mapa
          </Badge>
        ) : (
          <span className="text-sm text-ink-muted">Todavía no se buscó la dirección.</span>
        )}
        {lookup === "unavailable" ? (
          <span className="text-sm text-ink-muted">
            El buscador de direcciones no respondió: se guarda igual.
          </span>
        ) : lookup === "not_found" ? (
          <span className="text-sm text-ink-muted">No la encontramos: se guarda igual.</span>
        ) : lookup === "short" ? (
          <span className="text-sm text-ink-muted">Escribí la calle y el número.</span>
        ) : null}
      </div>
      <div className="grid grid-cols-2 gap-3">
        <Split
          edit={<FieldInput field="locality" label="Localidad" required maxLength={120} />}
          read={
            <dl>
              <ReadRow label="Localidad" value={saved.fields.locality} />
            </dl>
          }
        />
        <Split
          edit={
            <FieldInput field="phone" label="Teléfono" required maxLength={30} inputMode="tel" />
          }
          read={
            <dl>
              <ReadRow label="Teléfono" value={saved.fields.phone} />
            </dl>
          }
        />
      </div>
      <div className="grid grid-cols-[1fr_7rem] gap-3">
        <Split
          edit={
            <div className="flex min-w-0 flex-col gap-1">
              <label htmlFor={`${prefix}-province`} className={labelClass}>
                Provincia
              </label>
              <Select
                id={`${prefix}-province`}
                value={draft.fields.province}
                onChange={(e) =>
                  setDraft((d) => ({ ...d, fields: { ...d.fields, province: e.target.value } }))
                }
                className={cn(small, "w-full", changed.fields.includes("province") && changedRing)}
              >
                <option value="">Elegí</option>
                {options.provinces.map((p) => (
                  <option key={p.code} value={p.code}>
                    {p.name}
                  </option>
                ))}
              </Select>
            </div>
          }
          read={
            <dl>
              <ReadRow label="Provincia" value={provinceName(saved.fields.province)} />
            </dl>
          }
        />
        <Split
          edit={
            <FieldInput
              field="postal_code"
              label="Código postal"
              maxLength={8}
              placeholder="B1713"
            />
          }
          read={
            <dl>
              <ReadRow label="Código postal" value={saved.fields.postal_code} />
            </dl>
          }
        />
      </div>
      {point.length > 0 ? (
        <OrgMap
          points={point}
          label={`Mapa con la ubicación de ${placeName}`}
          className="desk:min-h-32 desk:flex-[1_1_0px]"
        />
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// «Razón social»: a nombre de quién factura y desde qué fecha
// ---------------------------------------------------------------------------
export function LegalSection({ todayIso }: { todayIso: string }) {
  const { prefix, draft, saved, setDraft, changed, options, editable } = useSheet();
  const current = options.legalEntities.find(
    (e) => e.id === (editable ? draft : saved).legalEntityId,
  );
  const savedEntity = options.legalEntities.find((e) => e.id === saved.legalEntityId);
  return (
    <div className="flex flex-col gap-3">
      <Split
        can={options.canEditGroupLevel}
        edit={
          <div className={cn("grid gap-3", changed.legalEntity && "desk:grid-cols-[1fr_9rem]")}>
            <div className="flex min-w-0 flex-col gap-1">
              <label htmlFor={`${prefix}-razon`} className={labelClass}>
                Factura a nombre de<span aria-hidden="true"> *</span>
              </label>
              <Select
                id={`${prefix}-razon`}
                value={draft.legalEntityId}
                aria-required="true"
                onChange={(e) =>
                  setDraft((d) => ({
                    ...d,
                    legalEntityId: e.target.value,
                    legalFrom: e.target.value === saved.legalEntityId ? saved.legalFrom : todayIso,
                  }))
                }
                className={cn(small, "w-full", changed.legalEntity && changedRing)}
              >
                <option value="">Elegí la razón social</option>
                {options.legalEntities.map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.name}
                  </option>
                ))}
              </Select>
            </div>
            {changed.legalEntity ? (
              <div className="flex min-w-0 flex-col gap-1">
                <label htmlFor={`${prefix}-desde`} className={labelClass}>
                  Desde
                </label>
                <Input
                  id={`${prefix}-desde`}
                  type="date"
                  max={todayIso}
                  value={draft.legalFrom}
                  onChange={(e) => setDraft((d) => ({ ...d, legalFrom: e.target.value }))}
                  className={cn(small, changedRing)}
                />
              </div>
            ) : null}
          </div>
        }
        read={
          <dl>
            <ReadRow label="Factura a nombre de" value={savedEntity?.name ?? ""} />
          </dl>
        }
      />
      {current ? (
        <dl className="grid grid-cols-2 gap-3">
          <ReadRow label="CUIT" value={current.taxId} />
          <div className="flex min-w-0 flex-col">
            <dt className={labelClass}>IVA</dt>
            <dd>
              <Badge status="info">{current.vatLabel}</Badge>
            </dd>
          </div>
          {!changed.legalEntity ? (
            <ReadRow label="Desde" value={formatDay(saved.legalFrom)} />
          ) : null}
        </dl>
      ) : (
        <p className="text-sm text-ink-muted">
          Sin razón social: su costo sin IVA queda incompleto.
        </p>
      )}
      {changed.legalEntity ? (
        <p className="text-xs text-ink-muted">
          Las facturas de antes siguen con la razón social anterior.
        </p>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// «Áreas»: chips que se renombran con un clic, se agregan acá y se quitan sin borrar
// ---------------------------------------------------------------------------
export function AreasSection() {
  const { prefix, draft, saved, setDraft, changed, editable } = useSheet();
  const [newName, setNewName] = useState("");
  const [editing, setEditing] = useState<string | null>(null);
  const [before, setBefore] = useState("");
  const [addError, setAddError] = useState("");
  const areas = editable ? draft.areas : saved.areas;
  const active = areas.filter((a) => a.active);
  const inactive = areas.filter((a) => !a.active && a.id);

  function add() {
    const name = newName.trim();
    if (!name) {
      setAddError("Escribí el nombre del área.");
      return;
    }
    setAddError("");
    const same = draft.areas.find((a) => a.name.trim().toLowerCase() === name.toLowerCase());
    setDraft((d) => ({
      ...d,
      areas: same
        ? d.areas.map((a) => (a.key === same.key ? { ...a, active: true } : a))
        : [...d.areas, { key: `nueva-${Date.now()}`, id: null, name, active: true }],
    }));
    setNewName("");
  }

  const setArea = (key: string, patch: Partial<{ name: string; active: boolean }>) =>
    setDraft((d) => ({
      ...d,
      areas: d.areas
        .map((a) => (a.key === key ? { ...a, ...patch } : a))
        // Una nueva que se quita, desaparece.
        .filter((a) => a.id !== null || a.active),
    }));

  if (!editable)
    return active.length === 0 ? (
      <p className="text-sm text-ink-muted">Sin áreas cargadas.</p>
    ) : (
      <ul aria-label="Áreas" className="flex flex-wrap gap-2">
        {active.map((a) => (
          <li key={a.key}>
            <Badge status="neutral">{a.name}</Badge>
          </li>
        ))}
      </ul>
    );

  return (
    <div className="flex flex-col gap-3">
      <ul aria-label="Áreas" className="flex flex-wrap gap-2">
        {active.map((a) =>
          editing === a.key ? (
            <li key={a.key} className="flex items-center gap-1">
              <label htmlFor={`${prefix}-area-${a.key}`} className="sr-only">
                Nombre del área
              </label>
              <Input
                id={`${prefix}-area-${a.key}`}
                autoFocus
                value={a.name}
                maxLength={120}
                onChange={(e) => setArea(a.key, { name: e.target.value })}
                onBlur={() => {
                  // Un nombre vacío no queda: vuelve al de antes.
                  if (!a.name.trim()) setArea(a.key, { name: before });
                  setEditing(null);
                }}
                onKeyDown={(e) => {
                  if (e.key === "Escape") setArea(a.key, { name: before });
                  if (e.key === "Enter" || e.key === "Escape") setEditing(null);
                }}
                className="w-40 desk:min-h-8"
              />
            </li>
          ) : (
            <li
              key={a.key}
              className={cn(
                "flex items-center rounded-sm border border-line bg-app text-sm text-ink",
                changed.areas.includes(a.key) && changedRing,
              )}
            >
              <button
                type="button"
                className="min-h-touch px-2 desk:min-h-8"
                aria-label={`Cambiar el nombre de ${a.name}`}
                onClick={() => {
                  setBefore(a.name);
                  setEditing(a.key);
                }}
              >
                {a.name || "Sin nombre"}
                {changed.areas.includes(a.key) ? (
                  <span className="sr-only"> (cambio sin guardar)</span>
                ) : null}
              </button>
              <button
                type="button"
                className="flex min-h-touch min-w-touch items-center justify-center text-ink-muted hover:text-ink desk:min-h-8 desk:min-w-8"
                aria-label={`Quitar ${a.name}`}
                onClick={() => setArea(a.key, { active: false })}
              >
                <X aria-hidden="true" className="size-4" />
              </button>
            </li>
          ),
        )}
      </ul>
      <div className="hidden gap-2 desk:flex">
        <label htmlFor={`${prefix}-area-nueva`} className="sr-only">
          Nueva área
        </label>
        <Input
          id={`${prefix}-area-nueva`}
          placeholder="Nueva área"
          value={newName}
          maxLength={120}
          aria-invalid={addError ? "true" : undefined}
          aria-describedby={addError ? `${prefix}-area-error` : undefined}
          onChange={(e) => setNewName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              add();
            }
          }}
          className={cn(small, "flex-1")}
        />
        <Button type="button" variant="outline" className={small} onClick={add}>
          <Plus aria-hidden="true" />
          Agregar
        </Button>
      </div>
      {addError ? (
        <p id={`${prefix}-area-error`} className="text-sm text-bad-ink">
          {addError}
        </p>
      ) : null}
      {inactive.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2 text-sm text-ink-muted">
          <span>Quitadas:</span>
          {inactive.map((a) => (
            <button
              key={a.key}
              type="button"
              className="inline-flex min-h-touch items-center gap-1 text-primary underline-offset-4 hover:underline desk:min-h-8"
              aria-label={`Volver a usar ${a.name}`}
              onClick={() => setArea(a.key, { active: true })}
            >
              <Undo2 aria-hidden="true" className="size-4" />
              {a.name}
            </button>
          ))}
        </div>
      ) : null}
      <p className="text-xs text-ink-muted">
        Clic en un área para cambiarle el nombre. Quitar no borra: la deja inactiva con su historia.
      </p>
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

// Enlace chico de las tarjetas y los indicadores.
export function SmallLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
    >
      {children}
    </Link>
  );
}
