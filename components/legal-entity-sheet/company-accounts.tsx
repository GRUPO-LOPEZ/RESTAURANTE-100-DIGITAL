"use client";

import { useId, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Pencil, Plus, Undo2, X } from "lucide-react";

import { saveLegalEntityAccountsAction } from "@/app/configuracion/structure-actions";
import { FormNotice } from "@/components/form-notice";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { SidePanel } from "@/components/ui/dialog";
import { Field, Input, Textarea } from "@/components/ui/field";
import { Segmented } from "@/components/ui/segmented";
import { ShortList } from "@/components/ui/short-list";
import { ToggleField } from "@/components/ui/toggle-field";
import type { ActionState } from "@/lib/auth/results";
import type { CompanyAccount } from "@/lib/payment-orders-data";
import { ACCOUNT_KIND_LABELS, companyAccountSchema, type AccountKind } from "@/lib/payment-orders";
import { changesLabel } from "@/lib/recipe-sheet";

// «Cajas y cuentas» de la razón social (ADR-0070): de dónde sale la plata de una orden de pago. La tarjeta muestra las
// primeras; «Ver las N» (o «Editar») abre un panel con la lista entera, donde quien administra el grupo agrega, cambia y
// da de baja. Los cambios se cuentan y se guardan juntos, con motivo, en una transacción. Quien solo lee ve la lista.

type Row = {
  key: string;
  id?: string;
  kind: AccountKind;
  name: string;
  bank: string;
  accountNumber: string;
  cbu: string;
  alias: string;
  cardLast4: string;
  isActive: boolean;
  removed: boolean;
};

const fromAccount = (a: CompanyAccount): Row => ({
  key: a.id,
  id: a.id,
  kind: a.kind,
  name: a.name,
  bank: a.bank ?? "",
  accountNumber: a.account_number ?? "",
  cbu: a.cbu ?? "",
  alias: a.alias ?? "",
  cardLast4: a.card_last4 ?? "",
  isActive: a.is_active,
  removed: false,
});

const blank = (): Row => ({
  key: `nueva-${Math.random().toString(36).slice(2)}`,
  kind: "cash",
  name: "",
  bank: "",
  accountNumber: "",
  cbu: "",
  alias: "",
  cardLast4: "",
  isActive: true,
  removed: false,
});

function detail(r: Pick<Row, "kind" | "bank" | "cbu" | "alias" | "accountNumber" | "cardLast4">) {
  if (r.kind === "card") return r.cardLast4 ? `terminada en ${r.cardLast4}` : "";
  if (r.kind === "bank")
    return [
      r.bank,
      r.alias ? `alias ${r.alias}` : null,
      r.cbu ? `CBU …${r.cbu.slice(-4)}` : r.accountNumber ? `cuenta ${r.accountNumber}` : null,
    ]
      .filter(Boolean)
      .join(" · ");
  return "";
}

const same = (a: Row, b: Row) =>
  a.kind === b.kind &&
  a.name.trim() === b.name.trim() &&
  a.bank.trim() === b.bank.trim() &&
  a.accountNumber.trim() === b.accountNumber.trim() &&
  a.cbu.replace(/\D/g, "") === b.cbu.replace(/\D/g, "") &&
  a.alias.trim() === b.alias.trim() &&
  a.cardLast4.trim() === b.cardLast4.trim() &&
  a.isActive === b.isActive;

export function CompanyAccounts({
  legalEntityId,
  accounts,
  editable,
}: {
  legalEntityId: string;
  accounts: CompanyAccount[];
  editable: boolean;
}) {
  const prefix = useId();
  const router = useRouter();
  const opener = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const saved = accounts.map(fromAccount);
  const [rows, setRows] = useState<Row[]>(saved);
  const [editing, setEditing] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [state, setState] = useState<ActionState>({});
  const [pending, start] = useTransition();
  // Si la página trae otras cuentas (se guardó), el borrador vuelve a lo guardado.
  const [seen, setSeen] = useState(accounts);
  if (seen !== accounts) {
    setSeen(accounts);
    setRows(saved);
  }

  type Change = { row: Row; kind: "new" | "edit" | "remove" };
  const changes = rows.flatMap((r): Change[] => {
    const before = saved.find((s) => s.id === r.id);
    if (!r.id) return r.removed ? [] : [{ row: r, kind: "new" as const }];
    if (r.removed) return [{ row: r, kind: "remove" as const }];
    return before && !same(before, r) ? [{ row: r, kind: "edit" as const }] : [];
  });
  const count = changes.length;
  const active = accounts.filter((a) => a.is_active);
  const set = (key: string, patch: Partial<Row>) =>
    setRows((all) => all.map((r) => (r.key === key ? { ...r, ...patch } : r)));

  function save() {
    for (const c of changes) {
      if (c.kind === "remove") continue;
      const check = companyAccountSchema.safeParse(c.row);
      if (!check.success) {
        setEditing(c.row.key);
        setState({
          status: "bad",
          message: `${c.row.name || "La nueva"}: ${check.error.issues[0]?.message ?? "revisá los datos."}`,
        });
        return;
      }
    }
    if (reason.trim().length < 3) {
      setState({ status: "bad", message: "Escribí el motivo de los cambios." });
      document.getElementById(`${prefix}-motivo`)?.focus();
      return;
    }
    const payload = changes.map(({ row: r, kind }) =>
      kind === "remove"
        ? { id: r.id, remove: true }
        : {
            ...(r.id ? { id: r.id } : {}),
            kind: r.kind,
            name: r.name.trim(),
            bank: r.kind === "bank" ? r.bank.trim() : "",
            account_number: r.kind === "bank" ? r.accountNumber.trim() : "",
            cbu: r.kind === "bank" ? r.cbu.replace(/\D/g, "") : "",
            alias: r.kind === "bank" ? r.alias.trim() : "",
            card_last4: r.kind === "card" ? r.cardLast4.trim() : "",
            is_active: r.isActive,
          },
    );
    start(async () => {
      const result = await saveLegalEntityAccountsAction({
        legalEntityId,
        reason,
        changes: payload,
      });
      setState(result);
      if (result.status === "ok") {
        setReason("");
        setEditing(null);
        router.refresh();
      }
    });
  }

  const trigger = (label: string, accessible: string) => (
    <button
      ref={opener}
      type="button"
      aria-haspopup="dialog"
      onClick={() => setOpen(true)}
      className="inline-flex min-h-touch items-center gap-1 self-start text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
    >
      {label}
      <span className="sr-only">{accessible}</span>
    </button>
  );

  return (
    <>
      <ShortList
        label="Cajas y cuentas"
        items={active}
        limit={3}
        itemKey={(a) => a.id}
        empty={
          <p className="text-sm text-ink">
            {accounts.length > 0
              ? "Ninguna se usa para pagar: activá una para registrar pagos."
              : "Sin cajas ni cuentas: hacen falta para registrar pagos a nombre de esta razón social."}
          </p>
        }
        renderItem={(a) => (
          <div className="flex items-baseline justify-between gap-2 py-1 text-sm">
            <span className="min-w-0 [overflow-wrap:break-word] text-ink">{a.name}</span>
            <span className="text-ink-muted">{ACCOUNT_KIND_LABELS[a.kind]}</span>
          </div>
        )}
      />
      {accounts.length > 3
        ? trigger(`Ver las ${accounts.length}`, " cajas y cuentas")
        : editable
          ? accounts.length === 0
            ? trigger("+ Agregar", " una caja o cuenta")
            : trigger("Editar", " las cajas y cuentas")
          : null}

      <SidePanel
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) requestAnimationFrame(() => opener.current?.focus());
        }}
        title="Cajas y cuentas"
        description="De dónde sale la plata de cada orden de pago. Una baja no borra nada: los pagos viejos la siguen mostrando."
      >
        {/* La lista se desplaza adentro; el motivo y los botones quedan a la vista (criterio 4). */}
        <ul
          aria-label="Cajas y cuentas"
          className="relative flex flex-col gap-2 desk:max-h-[28rem] desk:overflow-y-auto"
        >
          {rows.map((r) => {
            const label = r.name || "Nueva caja o cuenta";
            const changed = changes.some((c) => c.row.key === r.key);
            if (editable && editing === r.key && !r.removed)
              return (
                <li
                  key={r.key}
                  className="flex flex-col gap-3 rounded-sm border border-primary p-3"
                >
                  <Segmented
                    name={`${prefix}-tipo-${r.key}`}
                    legend="Qué es"
                    options={(["cash", "bank", "card"] as const).map((k) => ({
                      value: k,
                      label: ACCOUNT_KIND_LABELS[k],
                    }))}
                    value={r.kind}
                    onChange={(v) => set(r.key, { kind: v as AccountKind })}
                  />
                  <Field id={`${prefix}-nombre-${r.key}`} label="Nombre" required>
                    <Input
                      maxLength={80}
                      value={r.name}
                      placeholder={
                        r.kind === "cash"
                          ? "Caja Centro"
                          : r.kind === "card"
                            ? "Visa empresa"
                            : "Galicia CC"
                      }
                      onChange={(e) => set(r.key, { name: e.target.value })}
                    />
                  </Field>
                  {r.kind === "bank" ? (
                    <div className="grid grid-cols-2 gap-2">
                      <Field id={`${prefix}-banco-${r.key}`} label="Banco" required>
                        <Input
                          maxLength={80}
                          value={r.bank}
                          onChange={(e) => set(r.key, { bank: e.target.value })}
                        />
                      </Field>
                      <Field id={`${prefix}-nro-${r.key}`} label="N.º de cuenta">
                        <Input
                          maxLength={40}
                          value={r.accountNumber}
                          onChange={(e) => set(r.key, { accountNumber: e.target.value })}
                        />
                      </Field>
                      <Field id={`${prefix}-cbu-${r.key}`} label="CBU">
                        <Input
                          inputMode="numeric"
                          maxLength={26}
                          className="tabular-nums"
                          value={r.cbu}
                          onChange={(e) => set(r.key, { cbu: e.target.value })}
                        />
                      </Field>
                      <Field id={`${prefix}-alias-${r.key}`} label="Alias">
                        <Input
                          maxLength={20}
                          value={r.alias}
                          onChange={(e) => set(r.key, { alias: e.target.value })}
                        />
                      </Field>
                    </div>
                  ) : null}
                  {r.kind === "card" ? (
                    <Field id={`${prefix}-tarjeta-${r.key}`} label="Últimos 4 números" required>
                      <Input
                        inputMode="numeric"
                        maxLength={4}
                        className="w-24 tabular-nums"
                        value={r.cardLast4}
                        onChange={(e) =>
                          set(r.key, { cardLast4: e.target.value.replace(/\D/g, "") })
                        }
                      />
                    </Field>
                  ) : null}
                  {/* Sí/no, de un clic (ADR-0039). «No» la saca de los pagos pero la deja en la lista; la baja la saca. */}
                  <ToggleField
                    id={`${prefix}-activa-${r.key}`}
                    name={`${prefix}-activa-${r.key}`}
                    label="¿Se usa para pagar?"
                    hint="«No» la deja en la lista sin ofrecerla al pagar; «Dar de baja» la saca."
                    defaultValue={r.isActive}
                    value={r.isActive}
                    onChange={(v) => set(r.key, { isActive: v })}
                  />
                  <Button
                    type="button"
                    variant="outline"
                    className="self-end"
                    onClick={() => setEditing(null)}
                  >
                    Listo
                  </Button>
                </li>
              );
            return (
              <li
                key={r.key}
                className={
                  changed
                    ? "flex items-center justify-between gap-2 rounded-sm border border-dashed border-primary px-3 py-2"
                    : "flex items-center justify-between gap-2 rounded-sm border border-line px-3 py-2"
                }
              >
                <span className="min-w-0 text-sm">
                  <span className="block font-medium [overflow-wrap:break-word] text-ink">
                    {r.removed ? <s>{label}</s> : label}
                  </span>
                  <span className="text-ink">
                    {[ACCOUNT_KIND_LABELS[r.kind], detail(r)].filter(Boolean).join(" · ")}
                  </span>
                </span>
                <span className="flex shrink-0 items-center gap-1">
                  {r.removed ? (
                    <Badge status="bad">De baja</Badge>
                  ) : !r.isActive ? (
                    <Badge status="none">No se usa</Badge>
                  ) : null}
                  {editable ? (
                    r.removed ? (
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon"
                        aria-label={`Deshacer la baja de ${label}`}
                        onClick={() => set(r.key, { removed: false })}
                      >
                        <Undo2 aria-hidden="true" />
                      </Button>
                    ) : (
                      <>
                        <Button
                          type="button"
                          variant="ghost"
                          size="icon"
                          aria-label={`Editar ${label}`}
                          onClick={() => setEditing(r.key)}
                        >
                          <Pencil aria-hidden="true" />
                        </Button>
                        <Button
                          type="button"
                          variant="ghost"
                          size="icon"
                          aria-label={`Dar de baja ${label}`}
                          onClick={() =>
                            r.id
                              ? set(r.key, { removed: true })
                              : setRows((all) => all.filter((x) => x.key !== r.key))
                          }
                        >
                          <X aria-hidden="true" />
                        </Button>
                      </>
                    )
                  ) : null}
                </span>
              </li>
            );
          })}
        </ul>
        {editable ? (
          <div className="mt-4 flex flex-col gap-3">
            <Button
              type="button"
              variant="outline"
              className="self-start"
              onClick={() => {
                const row = blank();
                setRows((all) => [...all, row]);
                setEditing(row.key);
              }}
            >
              <Plus aria-hidden="true" />
              Agregar caja o cuenta
            </Button>
            <Field id={`${prefix}-motivo`} label="Motivo" hint="Queda en el historial." required>
              <Textarea
                rows={2}
                maxLength={500}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              />
            </Field>
            <FormNotice state={state} />
            <div className="flex items-center justify-end gap-2">
              <span className="mr-auto text-sm text-ink tabular-nums" aria-live="polite">
                {changesLabel(count)}
              </span>
              <Button
                type="button"
                variant="outline"
                disabled={pending || count === 0}
                onClick={() => {
                  setRows(saved);
                  setEditing(null);
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
      </SidePanel>
    </>
  );
}
