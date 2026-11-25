"use client";

import { useEffect, useId, useRef, useState } from "react";

import {
  quickIngredientAction,
  quickListItemAction,
  similarIngredientsAction,
  type QuickIngredient,
  type QuickList,
  type SimilarIngredient,
} from "@/app/recetas/actions";
import { FormNotice } from "@/components/form-notice";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/dialog";
import { Field, Input, Select } from "@/components/ui/field";
import type { ActionState } from "@/lib/auth/results";
import { LINE_UNITS, unitGroups, unitOptionLabel } from "@/lib/recipe-format";

// Altas cortas sin salir de la receta (ADR-0064): una materia prima, o un sector, una partida o un equipo de las listas.
// Se crean en el momento, con su motivo: no son parte del borrador de la receta. La base controla quién puede.

type Errors = Record<string, string>;

const OFFLINE: ActionState = {
  status: "bad",
  message: "No pudimos guardar: revisá la conexión y probá de nuevo.",
};

export function QuickIngredientModal({
  open,
  onClose,
  name,
  groupId,
  categories,
  onUse,
}: {
  open: boolean;
  onClose: () => void;
  // Lo que ya se escribió en el renglón.
  name: string;
  groupId: string;
  // Solo los rubros que van a recetas.
  categories: { id: string; label: string }[];
  onUse: (item: QuickIngredient) => void;
}) {
  return (
    <Modal
      open={open}
      onOpenChange={(next) => (next ? undefined : onClose())}
      title="Nueva materia prima"
      description="Se crea ahora, sin precio, aunque después descartes los cambios de la receta. Compras recibe un aviso para completarla."
    >
      <IngredientForm
        initialName={name}
        groupId={groupId}
        categories={categories}
        onUse={onUse}
        onClose={onClose}
      />
    </Modal>
  );
}

function IngredientForm({
  initialName,
  groupId,
  categories,
  onUse,
  onClose,
}: {
  initialName: string;
  groupId: string;
  categories: { id: string; label: string }[];
  onUse: (item: QuickIngredient) => void;
  onClose: () => void;
}) {
  const id = useId();
  const [name, setName] = useState(initialName);
  const [categoryId, setCategoryId] = useState("");
  const [unit, setUnit] = useState("");
  const [reason, setReason] = useState("");
  const [errors, setErrors] = useState<Errors>({});
  const [state, setState] = useState<ActionState>({});
  const [pending, setPending] = useState(false);
  const [similar, setSimilar] = useState<SimilarIngredient[]>([]);

  // Solo cuenta la última respuesta.
  const seq = useRef(0);
  async function look(text: string) {
    const mine = ++seq.current;
    const found = await similarIngredientsAction(groupId, text).catch(() => []);
    if (mine === seq.current) setSimilar(found);
  }
  // Con el nombre ya escrito en el renglón, se buscan al abrir.
  useEffect(() => {
    if (initialName === "") return;
    let live = true;
    similarIngredientsAction(groupId, initialName)
      .then((found) => (live ? setSimilar(found) : undefined))
      .catch(() => undefined);
    return () => {
      live = false;
    };
  }, [groupId, initialName]);

  async function submit() {
    const next: Errors = {};
    if (name.trim() === "") next.name = "Escribí el nombre.";
    if (categoryId === "") next.categoryId = "Elegí el rubro.";
    if (unit === "") next.unit = "Elegí la unidad.";
    if (reason.trim().length < 3) next.reason = "Escribí el motivo.";
    setErrors(next);
    const first = ["name", "categoryId", "unit", "reason"].find((f) => next[f]);
    if (first) {
      document.getElementById(`${id}-${first}`)?.focus();
      return;
    }
    setPending(true);
    try {
      const result = await quickIngredientAction({ groupId, name, categoryId, unit, reason });
      if (result.ingredient) onUse(result.ingredient);
      else {
        setState(result);
        setErrors(result.fieldErrors ?? {});
      }
    } catch {
      setState(OFFLINE);
    } finally {
      setPending(false);
    }
  }

  return (
    <form
      className="flex flex-col gap-4"
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        void submit();
      }}
    >
      <Field id={`${id}-name`} label="Nombre" required error={errors.name}>
        <Input
          value={name}
          maxLength={120}
          autoComplete="off"
          aria-required="true"
          onChange={(e) => setName(e.target.value)}
          onBlur={() => void look(name)}
        />
      </Field>
      {/* La región está siempre: así el lector de pantalla anuncia las parecidas cuando llegan. */}
      <div role="status">
        {similar.length > 0 ? (
          <div className="flex flex-col gap-2 rounded-sm border border-line bg-warn p-3 text-warn-ink">
            <p className="text-sm font-medium">
              {similar.length === 1
                ? "¿Es esta? Ya hay una parecida:"
                : "¿Es una de estas? Ya hay parecidas:"}
            </p>
            <ul className="flex flex-col gap-1">
              {similar.map((s) => (
                <li
                  key={s.id}
                  className="flex flex-wrap items-center justify-between gap-2 text-sm"
                >
                  <span>
                    {s.name} · <span className="tabular-nums">{s.code}</span>
                  </span>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    aria-label={`Usar esta: ${s.name}`}
                    onClick={() => onUse(s)}
                  >
                    Usar esta
                  </Button>
                </li>
              ))}
            </ul>
          </div>
        ) : null}
      </div>
      <Field id={`${id}-categoryId`} label="Rubro" required error={errors.categoryId}>
        <Select
          value={categoryId}
          aria-required="true"
          onChange={(e) => setCategoryId(e.target.value)}
        >
          <option value="">Elegí el rubro</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.label}
            </option>
          ))}
        </Select>
      </Field>
      <Field
        id={`${id}-unit`}
        label="Se usa en recetas en"
        hint="Las recetas la calculan en g, ml o unidades."
        required
        error={errors.unit}
      >
        <Select value={unit} aria-required="true" onChange={(e) => setUnit(e.target.value)}>
          <option value="">Elegí la unidad</option>
          {unitGroups().map((g) => (
            <optgroup key={g.label} label={g.label}>
              {g.units.map((u) => (
                <option key={u.code} value={u.code}>
                  {unitOptionLabel(u.code)}
                </option>
              ))}
            </optgroup>
          ))}
        </Select>
      </Field>
      <Field id={`${id}-reason`} label="Motivo" required error={errors.reason}>
        <Input
          value={reason}
          maxLength={500}
          aria-required="true"
          onChange={(e) => setReason(e.target.value)}
        />
      </Field>
      <FormNotice state={state} />
      <div className="flex flex-wrap justify-end gap-2">
        <Button type="button" variant="outline" onClick={onClose}>
          Cancelar
        </Button>
        <Button type="submit" disabled={pending}>
          {pending ? "Creando…" : "Crear y usar"}
        </Button>
      </div>
    </form>
  );
}

const LIST_TITLES: Record<QuickList, { title: string; name: string }> = {
  sectors: { title: "Nuevo sector", name: "Nombre del sector" },
  stations: { title: "Nueva partida", name: "Nombre de la partida" },
  equipment: { title: "Nuevo equipo", name: "Nombre del equipo" },
};
const IN_WORDS = "palabras";

export type NewListItem = {
  id: string;
  name: string;
  capacity: string;
  capacityUnit: string;
  capacityLabel: string;
};

export function QuickListModal({
  list,
  onClose,
  groupId,
  onUse,
}: {
  // La lista a la que se agrega; nulo, cerrado.
  list: QuickList | null;
  onClose: () => void;
  groupId: string;
  onUse: (list: QuickList, item: NewListItem) => void;
}) {
  return (
    <Modal
      open={list !== null}
      onOpenChange={(next) => (next ? undefined : onClose())}
      title={list ? LIST_TITLES[list].title : ""}
      description="Se agrega ahora a la lista del grupo, aunque después descartes los cambios de la receta."
    >
      {list ? (
        <ListForm key={list} list={list} groupId={groupId} onUse={onUse} onClose={onClose} />
      ) : null}
    </Modal>
  );
}

function ListForm({
  list,
  groupId,
  onUse,
  onClose,
}: {
  list: QuickList;
  groupId: string;
  onUse: (list: QuickList, item: NewListItem) => void;
  onClose: () => void;
}) {
  const id = useId();
  const [name, setName] = useState("");
  const [capacity, setCapacity] = useState("");
  const [unit, setUnit] = useState("");
  const [label, setLabel] = useState("");
  const [reason, setReason] = useState("");
  const [errors, setErrors] = useState<Errors>({});
  const [state, setState] = useState<ActionState>({});
  const [pending, setPending] = useState(false);

  async function submit() {
    const next: Errors = {};
    if (name.trim() === "") next.name = "Escribí el nombre.";
    if (capacity.trim() !== "" && unit === "") next.unit = "Elegí en qué.";
    if (capacity.trim() === "" && unit !== "") next.capacity = "Escribí cuánto entra.";
    if (unit === IN_WORDS && label.trim() === "")
      next.label = "Escribí en qué, por ejemplo canastos.";
    if (reason.trim().length < 3) next.reason = "Escribí el motivo.";
    setErrors(next);
    const first = ["name", "capacity", "unit", "label", "reason"].find((f) => next[f]);
    if (first) {
      document.getElementById(`${id}-${first}`)?.focus();
      return;
    }
    const words = unit === IN_WORDS;
    setPending(true);
    try {
      const result = await quickListItemAction({
        groupId,
        list,
        name,
        capacity,
        capacityUnit: words ? "" : unit,
        capacityLabel: words ? label : "",
        reason,
      });
      if (result.item)
        onUse(list, {
          ...result.item,
          capacity,
          capacityUnit: words ? "" : unit,
          capacityLabel: words ? label : "",
        });
      else if (result.status === "ok")
        // Se guardó, pero no se pudo leer: se cierra para no repetirlo.
        onClose();
      else {
        setState(result);
        setErrors(result.fieldErrors ?? {});
      }
    } catch {
      setState(OFFLINE);
    } finally {
      setPending(false);
    }
  }

  return (
    <form
      className="flex flex-col gap-4"
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        void submit();
      }}
    >
      <Field id={`${id}-name`} label={LIST_TITLES[list].name} required error={errors.name}>
        <Input
          value={name}
          maxLength={list === "equipment" ? 120 : 60}
          autoComplete="off"
          aria-required="true"
          onChange={(e) => setName(e.target.value)}
        />
      </Field>
      {list === "equipment" ? (
        <div className="grid gap-4 desk:grid-cols-2">
          <Field
            id={`${id}-capacity`}
            label="Capacidad (opcional)"
            hint="Cuánto entra de una vez."
            error={errors.capacity}
          >
            <Input
              inputMode="decimal"
              value={capacity}
              onChange={(e) => setCapacity(e.target.value)}
            />
          </Field>
          <Field id={`${id}-unit`} label="En qué" error={errors.unit}>
            <Select value={unit} onChange={(e) => setUnit(e.target.value)}>
              <option value="">Sin capacidad</option>
              {LINE_UNITS.map((u) => (
                <option key={u.code} value={u.code}>
                  {unitOptionLabel(u.code)}
                </option>
              ))}
              <option value={IN_WORDS}>En palabras…</option>
            </Select>
          </Field>
          {unit === IN_WORDS ? (
            <Field id={`${id}-label`} label="En palabras" error={errors.label}>
              <Input
                value={label}
                maxLength={40}
                placeholder="canastos"
                onChange={(e) => setLabel(e.target.value)}
              />
            </Field>
          ) : null}
        </div>
      ) : null}
      <Field id={`${id}-reason`} label="Motivo" required error={errors.reason}>
        <Input
          value={reason}
          maxLength={500}
          aria-required="true"
          onChange={(e) => setReason(e.target.value)}
        />
      </Field>
      <FormNotice state={state} />
      <div className="flex flex-wrap justify-end gap-2">
        <Button type="button" variant="outline" onClick={onClose}>
          Cancelar
        </Button>
        <Button type="submit" disabled={pending}>
          {pending ? "Agregando…" : "Agregar y usar"}
        </Button>
      </div>
    </form>
  );
}
