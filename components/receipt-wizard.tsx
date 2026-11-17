"use client";

import Link from "next/link";
import { useEffect, useId, useMemo, useRef, useState, useTransition } from "react";
import { Camera, Check, ChevronLeft, Plus, RotateCcw, Trash2, X } from "lucide-react";

import {
  closeReceiptAction,
  uploadLinePhotoAction,
  uploadReceiptPhotoAction,
} from "@/app/compras/recepcion/actions";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Field, Input, Textarea } from "@/components/ui/field";
import { InfoTip } from "@/components/ui/info-tip";
import { Notice } from "@/components/ui/notice";
import { Segmented } from "@/components/ui/segmented";
import { ToggleField } from "@/components/ui/toggle-field";
import { shrinkPhoto } from "@/lib/photos";
import { qtyText } from "@/lib/purchase-orders";
import {
  ISSUES,
  ISSUE_LABEL,
  PAPER_KINDS,
  buildCloseLines,
  decisionError,
  readNumber,
  receiptSummary,
  type ExtraLine,
  type LineDecision,
  type PaperKind,
  type PendingLine,
  type ReceiptIssue,
} from "@/lib/receipts";
import type { Receipt, ReceiptPendingLine, ReceiptPhoto } from "@/lib/receipts-data";
import { cn } from "@/lib/utils";

// Los pasos de la recepción (Fase 3, Prompt 4, ADR-0056), uno por pantalla y con botones de 44 px: se usa en la puerta
// de la cocina, con el celular en una mano. Las fotos se guardan apenas se sacan (si se corta, se retoma con ellas); los
// renglones se mandan juntos al cerrar, en una sola transacción de la base.

type Photo = { path?: string; url: string | null };
type LineForm = {
  mode?: "ok" | "observe";
  issue?: ReceiptIssue;
  received: string;
  weight: string;
  lot: string;
  note: string;
  photos: Photo[];
};
type ExtraForm = {
  key: string;
  name: string;
  received: string;
  weight: string;
  lot: string;
  note: string;
  photos: Photo[];
};

const EMPTY_LINE: LineForm = { received: "", weight: "", lot: "", note: "", photos: [] };

// La última foto de cada página, en orden.
function pages(photos: ReceiptPhoto[], kind: ReceiptPhoto["kind"]): ReceiptPhoto[] {
  return photos.filter((p) => p.kind === kind).sort((a, b) => a.page - b.page);
}

function unitOf(line: ReceiptPendingLine): string {
  return (line.withoutInvoiceName ? line.unitName : line.packageName) ?? "";
}

// Lo que la persona escribió en un renglón, como decisión (o null si todavía no decidió).
function toDecision(form: LineForm): LineDecision | null {
  const weight = readNumber(form.weight);
  const w = weight === null ? undefined : weight;
  if (form.mode === "ok") return { ok: true, weight: w, lot: form.lot };
  if (form.mode === "observe" && form.issue) {
    const received = readNumber(form.received);
    return {
      ok: false,
      issue: form.issue,
      received: received === null ? Number.NaN : received,
      weight: w,
      lot: form.lot,
      note: form.note,
      photoPaths: form.photos.map((p) => p.path).filter((p): p is string => Boolean(p)),
    };
  }
  return null;
}

export function ReceiptWizard({ receipt }: { receipt: Receipt }) {
  const prefix = useId();
  const hasOrder = receipt.orderId !== null;
  const steps = hasOrder
    ? ["Foto del papel", "Renglón por renglón", "Firmar el papel", "Resumen"]
    : ["Foto del papel", "Lo que llegó", "Firmar el papel", "Resumen"];
  const [step, setStep] = useState(0);
  const [paperKind, setPaperKind] = useState<PaperKind | "">("");
  const [paperNumber, setPaperNumber] = useState("");
  const [photos, setPhotos] = useState<ReceiptPhoto[]>(receipt.photos);
  const [forms, setForms] = useState<Record<string, LineForm>>({});
  const [extras, setExtras] = useState<ExtraForm[]>([]);
  const [cash, setCash] = useState(false);
  const [cashText, setCashText] = useState("");
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [closing, startClosing] = useTransition();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const errorRef = useRef<HTMLDivElement>(null);
  const firstRender = useRef(true);

  // Al cambiar de paso, el foco va al título del paso (quien usa lector de pantalla sabe dónde está).
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    headingRef.current?.focus();
  }, [step]);

  const lines: PendingLine[] = receipt.pending.map((l) => ({
    purchaseOrderLineId: l.purchaseOrderLineId,
    name: l.name,
    pending: l.pending,
    billedByWeight: l.billedByWeight,
  }));
  const decisions = useMemo(() => {
    const out: Record<string, LineDecision | undefined> = {};
    for (const l of receipt.pending) {
      const d = toDecision(forms[l.purchaseOrderLineId] ?? EMPTY_LINE);
      if (d) out[l.purchaseOrderLineId] = d;
    }
    return out;
  }, [forms, receipt.pending]);
  const extraLines: ExtraLine[] = extras.map((e) => {
    const received = readNumber(e.received);
    const weight = readNumber(e.weight);
    return {
      key: e.key,
      name: e.name,
      received: received === null ? Number.NaN : received,
      weight: weight === null ? undefined : weight,
      lot: e.lot,
      note: e.note,
      photoPaths: e.photos.map((p) => p.path).filter((p): p is string => Boolean(p)),
    };
  });
  const summary = receiptSummary(lines, decisions, extraLines, hasOrder);
  const originals = pages(photos, "receipt_original");
  const signed = pages(photos, "receipt_signed");

  function setLine(id: string, patch: Partial<LineForm>) {
    setForms((f) => ({ ...f, [id]: { ...(f[id] ?? EMPTY_LINE), ...patch } }));
  }
  function setExtra(key: string, patch: Partial<ExtraForm>) {
    setExtras((xs) => xs.map((x) => (x.key === key ? { ...x, ...patch } : x)));
  }

  // Lo que falta para pasar de cada paso, con palabras.
  const lineErrors = receipt.pending
    .map((l) => {
      const d = decisions[l.purchaseOrderLineId];
      const form = forms[l.purchaseOrderLineId];
      if (form?.mode === "observe" && !form.issue) return `${l.name}: elegí qué pasó.`;
      return d
        ? decisionError(d, l.pending)
          ? `${l.name}: ${decisionError(d, l.pending)}`
          : null
        : null;
    })
    .filter((x): x is string => x !== null);
  const extraErrors = extraLines
    .map((e, i) =>
      !e.name.trim()
        ? `Lo que no estaba, renglón ${i + 1}: escribí qué llegó.`
        : !(e.received > 0)
          ? `${e.name}: escribí cuánto llegó.`
          : e.weight !== undefined && !(e.weight > 0)
            ? `${e.name}: el peso tiene que ser mayor que cero.`
            : null,
    )
    .filter((x): x is string => x !== null);
  const blockers: string[][] = [
    [
      ...(paperKind ? [] : ["Elegí qué papel trajo el proveedor."]),
      ...(originals.length > 0 ? [] : ["Sacale una foto al papel como llegó."]),
    ],
    [
      ...summary.undecided.map((n) => `Falta decidir: ${n}.`),
      ...lineErrors,
      ...extraErrors,
      ...(!hasOrder && extras.length === 0 ? ["Anotá lo que llegó."] : []),
    ],
    signed.length > 0 ? [] : ["Sacale una foto al papel firmado."],
    [],
  ];
  const cashAmount = cash ? readNumber(cashText) : null;
  const closeBlockers = [
    ...blockers.slice(0, 3).flat(),
    ...(cash && !(cashAmount !== null && cashAmount > 0)
      ? ["Escribí cuánto se pagó en efectivo."]
      : []),
    ...(summary.needsReason && reason.trim().length < 3
      ? ["Hubo observaciones: escribí el motivo."]
      : []),
  ];

  function next() {
    const missing = blockers[step] ?? [];
    if (missing.length > 0) {
      setError(missing.join(" "));
      errorRef.current?.focus();
      return;
    }
    setError(null);
    setStep((s) => Math.min(s + 1, steps.length - 1));
  }
  function back() {
    setError(null);
    setStep((s) => Math.max(s - 1, 0));
  }

  function close() {
    if (closeBlockers.length > 0) {
      setError(closeBlockers.join(" "));
      errorRef.current?.focus();
      return;
    }
    setError(null);
    startClosing(async () => {
      const result = await closeReceiptAction({
        receipt_id: receipt.id,
        paper_kind: paperKind,
        paper_number: paperNumber.trim() || undefined,
        cash_paid_amount: cash ? cashAmount : null,
        reason: reason.trim() || undefined,
        lines: buildCloseLines(lines, decisions, extraLines),
      });
      // Si cerró bien, la acción lleva a la recepción cerrada (con el aviso «Listo»): acá solo llegan los errores.
      if (result.status !== "ok") {
        setError(result.message ?? "No pudimos cerrar la recepción. Probá de nuevo.");
        errorRef.current?.focus();
      }
    });
  }

  return (
    <div className="flex flex-col gap-4 desk:max-w-3xl">
      <nav aria-label="Pasos de la recepción">
        <ol className="flex flex-wrap gap-x-3 gap-y-1 text-sm text-ink-muted">
          {steps.map((s, i) => (
            <li
              key={s}
              aria-current={i === step ? "step" : undefined}
              className={cn(i === step && "font-medium text-ink")}
            >
              {i + 1}. {s}
              {i < step ? <span className="sr-only"> (hecho)</span> : null}
            </li>
          ))}
        </ol>
      </nav>
      <h2 ref={headingRef} tabIndex={-1} className="text-xl font-semibold text-ink outline-none">
        Paso {step + 1} de {steps.length} · {steps[step]}
      </h2>

      {step === 0 ? (
        <Card className="flex flex-col gap-4">
          <Segmented
            name={`${prefix}-papel`}
            legend="¿Qué papel trajo?"
            options={PAPER_KINDS}
            value={paperKind}
            onChange={(v) => setPaperKind(v as PaperKind)}
          />
          <Field id={`${prefix}-numero`} label="Número del papel (si se ve)" className="desk:w-72">
            <Input
              value={paperNumber}
              maxLength={40}
              onChange={(e) => setPaperNumber(e.target.value)}
              placeholder="Por ejemplo, 0001-00001234"
            />
          </Field>
          <PhotoPages
            receiptId={receipt.id}
            kind="receipt_original"
            label="Sacar foto del remito o la factura"
            name="Foto 1"
            photos={originals}
            onSaved={(p) =>
              setPhotos((ps) => [...ps.filter((x) => !(x.kind === p.kind && x.page === p.page)), p])
            }
          />
        </Card>
      ) : null}

      {step === 1 && hasOrder ? (
        <div className="flex flex-col gap-3">
          <p aria-live="polite" className="text-base font-medium text-ink tabular-nums">
            {summary.decided} de {summary.total} renglones revisados
          </p>
          <ul aria-label="Renglones de la orden" className="flex flex-col gap-3">
            {receipt.pending.map((l) => (
              <LineCard
                key={l.purchaseOrderLineId}
                receiptId={receipt.id}
                line={l}
                form={forms[l.purchaseOrderLineId] ?? EMPTY_LINE}
                onChange={(patch) => setLine(l.purchaseOrderLineId, patch)}
              />
            ))}
          </ul>
          <ExtraList
            receiptId={receipt.id}
            title="¿Llegó algo que no estaba en la orden?"
            extras={extras}
            onAdd={() =>
              setExtras((xs) => [
                ...xs,
                {
                  key: crypto.randomUUID(),
                  name: "",
                  received: "",
                  weight: "",
                  lot: "",
                  note: "",
                  photos: [],
                },
              ])
            }
            onChange={setExtra}
            onRemove={(key) => setExtras((xs) => xs.filter((x) => x.key !== key))}
            addLabel="Llegó algo que no estaba"
          />
        </div>
      ) : null}

      {step === 1 && !hasOrder ? (
        <ExtraList
          receiptId={receipt.id}
          title={`Lo que llegó de ${receipt.supplierName}`}
          extras={extras}
          onAdd={() =>
            setExtras((xs) => [
              ...xs,
              {
                key: crypto.randomUUID(),
                name: "",
                received: "",
                weight: "",
                lot: "",
                note: "",
                photos: [],
              },
            ])
          }
          onChange={setExtra}
          onRemove={(key) => setExtras((xs) => xs.filter((x) => x.key !== key))}
          addLabel="Agregar lo que llegó"
        />
      ) : null}

      {step === 2 ? (
        <Card className="flex flex-col gap-4">
          <p className="text-base text-ink">
            Firmá el papel con tu nombre y la fecha, y sacale una foto. Es la prueba de lo que se
            recibió.
          </p>
          <PhotoPages
            receiptId={receipt.id}
            kind="receipt_signed"
            label="Sacar foto del papel firmado"
            name="Foto 2"
            photos={signed}
            onSaved={(p) =>
              setPhotos((ps) => [...ps.filter((x) => !(x.kind === p.kind && x.page === p.page)), p])
            }
          />
        </Card>
      ) : null}

      {step === 3 ? (
        <Card className="flex flex-col gap-4">
          {hasOrder ? (
            summary.observed === 0 ? (
              <p className="text-base text-ink">
                {summary.result === "complete" ? "Todo llegó bien." : "Sin observaciones."}
              </p>
            ) : (
              <div className="flex flex-col gap-2">
                <p className="text-base font-medium text-ink">
                  {summary.observed === 1 ? "1 observación" : `${summary.observed} observaciones`}
                </p>
                <ul className="flex flex-col divide-y divide-line">
                  {receipt.pending.map((l) => {
                    const d = decisions[l.purchaseOrderLineId];
                    if (!d || d.ok) return null;
                    return (
                      <li key={l.purchaseOrderLineId} className="py-2 text-base text-ink">
                        <span className="font-medium">{l.name}</span> · {ISSUE_LABEL[d.issue]} ·
                        llegó {qtyText(d.received)} de {qtyText(l.pending)} {unitOf(l)}
                      </li>
                    );
                  })}
                  {extraLines.map((e) => (
                    <li key={e.key} className="py-2 text-base text-ink">
                      <span className="font-medium">{e.name}</span> · No estaba en la orden ·{" "}
                      {qtyText(e.received)}
                    </li>
                  ))}
                </ul>
              </div>
            )
          ) : (
            <p className="text-base text-ink">
              {extras.length === 1 ? "1 renglón" : `${extras.length} renglones`} de{" "}
              {receipt.supplierName}, sin orden de compra.
            </p>
          )}
          {summary.result === "partial" ? (
            <Notice status="warn">
              La orden queda recibida en parte: lo que falta se puede recibir cuando llegue.
            </Notice>
          ) : null}
          <div className="flex flex-col gap-2">
            <ToggleField
              id={`${prefix}-efectivo`}
              name="cash"
              label="Se pagó en efectivo"
              defaultValue={false}
              value={cash}
              onChange={setCash}
            />
            {cash ? (
              <Field
                id={`${prefix}-importe`}
                label="Importe pagado"
                hint="Queda para que Compras lo confirme."
                className="desk:w-72"
              >
                <Input
                  inputMode="decimal"
                  value={cashText}
                  onChange={(e) => setCashText(e.target.value)}
                  placeholder="Por ejemplo, 15.000"
                />
              </Field>
            ) : null}
          </div>
          {summary.needsReason ? (
            <Field
              id={`${prefix}-motivo`}
              label="Motivo de las observaciones *"
              hint="Queda en el historial y lo ve Compras."
            >
              <Textarea
                value={reason}
                maxLength={500}
                aria-required="true"
                onChange={(e) => setReason(e.target.value)}
                placeholder="Por ejemplo, faltó un cajón de tomate"
              />
            </Field>
          ) : null}
        </Card>
      ) : null}

      <div ref={errorRef} tabIndex={-1} className="outline-none" aria-live="assertive">
        {error ? <Notice status="bad">{error}</Notice> : null}
      </div>

      <div className="flex flex-col-reverse gap-2 desk:flex-row desk:justify-between">
        <div className="flex flex-col gap-2 desk:flex-row">
          {step > 0 ? (
            <Button type="button" variant="outline" onClick={back}>
              <ChevronLeft aria-hidden="true" />
              Anterior
            </Button>
          ) : null}
          <Button asChild variant="ghost">
            <Link href="/compras/recepcion">Seguir después</Link>
          </Button>
        </div>
        {step < steps.length - 1 ? (
          <Button type="button" onClick={next}>
            Siguiente: {steps[step + 1]?.toLowerCase()}
          </Button>
        ) : (
          <Button type="button" onClick={close} disabled={closing}>
            {closing ? "Cerrando…" : "Cerrar recepción"}
          </Button>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Fotos del papel: la 1 (como llegó) o la 2 (firmado), con «Rehacer» y «+ Otra página»
// ---------------------------------------------------------------------------
function PhotoPages({
  receiptId,
  kind,
  label,
  name,
  photos,
  onSaved,
}: {
  receiptId: string;
  kind: ReceiptPhoto["kind"];
  label: string;
  name: string;
  photos: ReceiptPhoto[];
  onSaved: (photo: ReceiptPhoto) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [page, setPage] = useState(1);
  const [pending, startUpload] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function pick(p: number) {
    setPage(p);
    setError(null);
    inputRef.current?.click();
  }

  function upload(file: File | undefined) {
    if (!file) return;
    startUpload(async () => {
      try {
        const blob = await shrinkPhoto(file);
        const form = new FormData();
        form.set("receiptId", receiptId);
        form.set("kind", kind);
        form.set("page", String(page));
        form.set("file", new File([blob], "foto.jpg", { type: "image/jpeg" }));
        const result = await uploadReceiptPhotoAction(form);
        if (result.status === "ok" && result.photo) onSaved(result.photo);
        else setError(result.message ?? "No pudimos guardar la foto. Probá de nuevo.");
      } catch {
        setError("No pudimos leer la foto. Probá de nuevo.");
      } finally {
        if (inputRef.current) inputRef.current.value = "";
      }
    });
  }

  const nextPage = photos.reduce((m, p) => Math.max(m, p.page), 0) + 1;
  return (
    <div className="flex flex-col gap-3">
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        capture="environment"
        hidden
        aria-label={`${name}: ${label}`}
        onChange={(e) => upload(e.target.files?.[0])}
      />
      {photos.length === 0 ? (
        <Button
          type="button"
          onClick={() => pick(1)}
          disabled={pending}
          className="text-lg min-h-24 w-full desk:min-h-24"
        >
          <Camera aria-hidden="true" className="size-6" />
          {pending ? "Guardando la foto…" : label}
        </Button>
      ) : (
        <>
          <ul aria-label={name} className="grid grid-cols-2 gap-3 desk:grid-cols-3">
            {photos.map((p) => (
              <li key={p.page} className="flex flex-col gap-2">
                {p.url ? (
                  // eslint-disable-next-line @next/next/no-img-element -- enlace firmado de Storage, de 5 minutos
                  <img
                    src={p.url}
                    alt={`${name}, página ${p.page}`}
                    className="aspect-[3/4] w-full rounded-sm border border-line bg-app object-cover"
                  />
                ) : (
                  <p className="flex aspect-[3/4] items-center justify-center rounded-sm border border-line bg-app p-2 text-center text-sm text-ink-muted">
                    {name}, página {p.page}: guardada (no se puede mostrar)
                  </p>
                )}
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => pick(p.page)}
                  disabled={pending}
                  aria-label={`Rehacer ${name.toLowerCase()}, página ${p.page}`}
                >
                  <RotateCcw aria-hidden="true" />
                  Rehacer
                </Button>
              </li>
            ))}
          </ul>
          <Button
            type="button"
            variant="outline"
            onClick={() => pick(nextPage)}
            disabled={pending || nextPage > 20}
          >
            <Plus aria-hidden="true" />
            {pending ? "Guardando la foto…" : "Otra página"}
          </Button>
        </>
      )}
      <p aria-live="polite" className="sr-only">
        {pending ? "Guardando la foto…" : ""}
      </p>
      {error ? <Notice status="bad">{error}</Notice> : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Un renglón de la orden: ✓ OK o ✕ Observar
// ---------------------------------------------------------------------------
function LineCard({
  receiptId,
  line,
  form,
  onChange,
}: {
  receiptId: string;
  line: ReceiptPendingLine;
  form: LineForm;
  onChange: (patch: Partial<LineForm>) => void;
}) {
  const id = useId();
  const unit = unitOf(line);
  const decision = toDecision(form);
  const problem = decision ? decisionError(decision, line.pending) : null;
  return (
    <li>
      <Card className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <p id={`${id}-nombre`} className="text-base font-medium text-ink">
            {line.name}
          </p>
          <p className="text-sm text-ink-muted tabular-nums">
            Pedido: {qtyText(line.pending)} {unit}
            {line.alreadyReceived > 0
              ? ` (de ${qtyText(line.ordered)}; ya llegó ${qtyText(line.alreadyReceived)})`
              : ""}
            {line.estimatedKg !== null ? ` · ≈ ${qtyText(line.estimatedKg)} kg` : ""}
            {line.withoutInvoiceName ? " · Sin nombre de factura" : ""}
            {line.note ? ` · ${line.note}` : ""}
          </p>
        </div>
        <div role="group" aria-labelledby={`${id}-nombre`} className="grid grid-cols-2 gap-2">
          <Button
            type="button"
            variant="outline"
            aria-pressed={form.mode === "ok"}
            onClick={() => onChange({ mode: "ok" })}
            className="min-h-12 aria-pressed:border-ok-ink aria-pressed:bg-ok aria-pressed:text-ok-ink desk:min-h-12"
          >
            <Check aria-hidden="true" />
            OK
          </Button>
          <Button
            type="button"
            variant="outline"
            aria-pressed={form.mode === "observe"}
            aria-expanded={form.mode === "observe"}
            aria-controls={`${id}-observar`}
            onClick={() => onChange({ mode: "observe" })}
            className="min-h-12 aria-pressed:border-bad-ink aria-pressed:bg-bad aria-pressed:text-bad-ink desk:min-h-12"
          >
            <X aria-hidden="true" />
            Observar
          </Button>
        </div>
        {form.mode === "ok" && line.billedByWeight ? (
          <Field
            id={`${id}-peso-ok`}
            label="Peso recibido en kg (si se pesó)"
            className="desk:w-72"
          >
            <Input
              inputMode="decimal"
              value={form.weight}
              onChange={(e) => onChange({ weight: e.target.value })}
            />
          </Field>
        ) : null}
        {form.mode === "observe" ? (
          <div id={`${id}-observar`} className="flex flex-col gap-3">
            <Segmented
              name={`${id}-que-paso`}
              legend="¿Qué pasó?"
              options={ISSUES}
              value={form.issue ?? ""}
              onChange={(v) =>
                onChange({
                  issue: v as ReceiptIssue,
                  // Otro producto: lo pedido no llegó.
                  ...(v === "different_product" ? { received: "0" } : {}),
                })
              }
            />
            <div className="grid gap-3 desk:grid-cols-2">
              <Field id={`${id}-recibido`} label={`Cuánto llegó (${unit || "cantidad"})`}>
                <Input
                  inputMode="decimal"
                  value={form.received}
                  aria-invalid={problem ? true : undefined}
                  onChange={(e) => onChange({ received: e.target.value })}
                  placeholder="0 si no llegó"
                />
              </Field>
              {line.billedByWeight ? (
                <Field id={`${id}-peso`} label="Peso recibido en kg (si se pesó)">
                  <Input
                    inputMode="decimal"
                    value={form.weight}
                    onChange={(e) => onChange({ weight: e.target.value })}
                  />
                </Field>
              ) : null}
            </div>
            <Field id={`${id}-nota`} label="Nota (opcional)">
              <Input
                value={form.note}
                maxLength={300}
                onChange={(e) => onChange({ note: e.target.value })}
              />
            </Field>
            <ProductPhotos
              receiptId={receiptId}
              name={line.name}
              photos={form.photos}
              onChange={(photos) => onChange({ photos })}
            />
            {problem ? <p className="text-sm text-bad-ink">{problem}</p> : null}
          </div>
        ) : null}
        {form.mode ? (
          <Field id={`${id}-lote`} label="Lote (opcional)" className="desk:w-72">
            <Input
              value={form.lot}
              maxLength={60}
              onChange={(e) => onChange({ lot: e.target.value })}
            />
          </Field>
        ) : null}
      </Card>
    </li>
  );
}

// ---------------------------------------------------------------------------
// Lo que llegó y no estaba en la orden (o, sin orden, todo lo que llegó)
// ---------------------------------------------------------------------------
function ExtraList({
  receiptId,
  title,
  extras,
  onAdd,
  onChange,
  onRemove,
  addLabel,
}: {
  receiptId: string;
  title: string;
  extras: ExtraForm[];
  onAdd: () => void;
  onChange: (key: string, patch: Partial<ExtraForm>) => void;
  onRemove: (key: string) => void;
  addLabel: string;
}) {
  const id = useId();
  return (
    <section aria-labelledby={`${id}-titulo`} className="flex flex-col gap-3">
      <h3 id={`${id}-titulo`} className="flex items-center gap-1 text-base font-semibold text-ink">
        {title}
        <InfoTip label="Qué pasa con lo que no estaba">
          Si el sistema reconoce el artículo del proveedor, entra al stock. Si no, queda para que el
          chef diga qué materia prima es.
        </InfoTip>
      </h3>
      {extras.length > 0 ? (
        <ul className="flex flex-col gap-3">
          {extras.map((e, i) => (
            <li key={e.key}>
              <Card className="flex flex-col gap-3">
                <div className="grid gap-3 desk:grid-cols-[2fr_1fr]">
                  <Field id={`${id}-${e.key}-nombre`} label={`Qué llegó (renglón ${i + 1})`}>
                    <Input
                      value={e.name}
                      maxLength={200}
                      onChange={(ev) => onChange(e.key, { name: ev.target.value })}
                      placeholder="Como figura en el papel"
                    />
                  </Field>
                  <Field id={`${id}-${e.key}-cantidad`} label="Cuántos (envases o unidades)">
                    <Input
                      inputMode="decimal"
                      value={e.received}
                      onChange={(ev) => onChange(e.key, { received: ev.target.value })}
                    />
                  </Field>
                </div>
                <div className="grid gap-3 desk:grid-cols-2">
                  <Field id={`${id}-${e.key}-lote`} label="Lote (opcional)">
                    <Input
                      value={e.lot}
                      maxLength={60}
                      onChange={(ev) => onChange(e.key, { lot: ev.target.value })}
                    />
                  </Field>
                  <Field id={`${id}-${e.key}-nota`} label="Nota (opcional)">
                    <Input
                      value={e.note}
                      maxLength={300}
                      onChange={(ev) => onChange(e.key, { note: ev.target.value })}
                    />
                  </Field>
                </div>
                <ProductPhotos
                  receiptId={receiptId}
                  name={e.name || `renglón ${i + 1}`}
                  photos={e.photos}
                  onChange={(photos) => onChange(e.key, { photos })}
                />
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => onRemove(e.key)}
                  className="self-start"
                  aria-label={`Quitar ${e.name || `el renglón ${i + 1}`}`}
                >
                  <Trash2 aria-hidden="true" />
                  Quitar
                </Button>
              </Card>
            </li>
          ))}
        </ul>
      ) : null}
      <Button
        type="button"
        variant="outline"
        onClick={onAdd}
        className="self-stretch desk:self-start"
      >
        <Plus aria-hidden="true" />
        {addLabel}
      </Button>
    </section>
  );
}

// Foto opcional de un producto observado (hasta 5): se sube ya y se registra al cerrar, con su renglón.
function ProductPhotos({
  receiptId,
  name,
  photos,
  onChange,
}: {
  receiptId: string;
  name: string;
  photos: Photo[];
  onChange: (photos: Photo[]) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [pending, startUpload] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function upload(file: File | undefined) {
    if (!file) return;
    setError(null);
    startUpload(async () => {
      try {
        const blob = await shrinkPhoto(file);
        const form = new FormData();
        form.set("receiptId", receiptId);
        form.set("file", new File([blob], "foto.jpg", { type: "image/jpeg" }));
        const result = await uploadLinePhotoAction(form);
        if (result.status === "ok" && result.path)
          onChange([...photos, { path: result.path, url: result.url ?? null }]);
        else setError(result.message ?? "No pudimos guardar la foto. Probá de nuevo.");
      } catch {
        setError("No pudimos leer la foto. Probá de nuevo.");
      } finally {
        if (inputRef.current) inputRef.current.value = "";
      }
    });
  }

  return (
    <div className="flex flex-col gap-2">
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        capture="environment"
        hidden
        aria-label={`Foto del producto: ${name}`}
        onChange={(e) => upload(e.target.files?.[0])}
      />
      {photos.length > 0 ? (
        <ul aria-label={`Fotos de ${name}`} className="flex flex-wrap gap-2">
          {photos.map((p, i) => (
            <li key={p.path ?? i}>
              {p.url ? (
                // eslint-disable-next-line @next/next/no-img-element -- enlace firmado de Storage, de 5 minutos
                <img
                  src={p.url}
                  alt={`Foto ${i + 1} de ${name}`}
                  className="size-20 rounded-sm border border-line object-cover"
                />
              ) : (
                <span className="text-sm text-ink-muted">Foto {i + 1} guardada</span>
              )}
            </li>
          ))}
        </ul>
      ) : null}
      {photos.length < 5 ? (
        <Button
          type="button"
          variant="outline"
          onClick={() => inputRef.current?.click()}
          disabled={pending}
          className="self-stretch desk:self-start"
        >
          <Camera aria-hidden="true" />
          {pending ? "Guardando la foto…" : "Foto del producto (opcional)"}
        </Button>
      ) : null}
      {error ? <Notice status="bad">{error}</Notice> : null}
    </div>
  );
}
