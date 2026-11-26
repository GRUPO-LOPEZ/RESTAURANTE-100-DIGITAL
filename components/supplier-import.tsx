"use client";

import { useActionState, useId, useState, useTransition } from "react";
import { Download, Upload } from "lucide-react";

import {
  confirmSupplierImportAction,
  previewSupplierImportAction,
  type ImportState,
  type PreviewRow,
} from "@/app/proveedores/importar/actions";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Input } from "@/components/ui/field";
import { InfoTip } from "@/components/ui/info-tip";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { EmptyState } from "@/components/ui/states";
import { reasonField } from "@/lib/forms/schemas";
import { formatCuit } from "@/lib/suppliers";
import { FileUpload } from "@/components/ui/file-upload";

const STATUS: Record<PreviewRow["status"], { label: string; badge: "ok" | "none" | "bad" }> = {
  create: { label: "Se crea", badge: "ok" },
  skip: { label: "Se omite", badge: "none" },
  error: { label: "Con error", badge: "bad" },
};

const columns: DataColumn<PreviewRow>[] = [
  {
    key: "row",
    header: "Fila",
    align: "right",
    mobile: "line",
    cell: (r) => <span className="tabular-nums">{r.row}</span>,
  },
  { key: "name", header: "Razón social", mobile: "title", cell: (r) => r.name ?? "—" },
  {
    key: "tax_id",
    header: "CUIT",
    mobile: "line",
    cell: (r) => (
      <span className="whitespace-nowrap tabular-nums">{formatCuit(r.tax_id) || "—"}</span>
    ),
  },
  {
    key: "status",
    header: "Qué pasa",
    mobile: "status",
    cell: (r) => <Badge status={STATUS[r.status].badge}>{STATUS[r.status].label}</Badge>,
  },
  {
    key: "message",
    header: "Motivo",
    mobile: "line",
    // El motivo es lo que hay que leer para corregir: se parte en renglones, nunca se corta en el borde.
    cell: (r) => <span className="whitespace-normal">{r.message}</span>,
  },
];

const NOT_YET = "Subí la planilla y tocá «Revisar».";
const STEP = "flex items-center gap-1 text-sm font-medium text-ink";

// Importar proveedores desde planilla (ADR-0055): bajar la plantilla, subirla, ver qué va a pasar con cada fila y
// confirmar con un motivo. Si una fila tiene error no se crea nada: se corrige la planilla y se sube de nuevo.
// Es una carga de computadora: en el celular se avisa y no se muestra el formulario.
export function SupplierImport() {
  const prefix = useId();
  const [state, preview, reviewing] = useActionState<ImportState, FormData>(
    previewSupplierImportAction,
    {},
  );
  const [confirmState, setConfirmState] = useState<ImportState>({});
  const [reason, setReason] = useState("");
  const [reasonError, setReasonError] = useState<string | null>(null);
  const [creating, startCreating] = useTransition();

  // Lo que se muestra: el rechazo de la confirmación (si trajo filas) o la última vista previa.
  const rejectedRows = confirmState.status === "bad" && confirmState.rows ? confirmState : null;
  const shown = rejectedRows ?? state;
  const rows = shown.status === "preview" || shown.status === "bad" ? (shown.rows ?? []) : [];
  const totals = shown.status === "preview" || shown.status === "bad" ? shown.totals : undefined;
  // Sin filas en el rechazo (red, permiso, motivo): se puede reintentar con la misma vista previa.
  const payload = state.status === "preview" && !rejectedRows ? state.payload : null;
  const create = totals?.create ?? 0;
  const previewNotice = state.status === "bad" && !rejectedRows ? state.message : null;
  const confirmNotice = confirmState.status === "bad" ? confirmState.message : null;

  const summary = reviewing
    ? "Revisando la planilla…"
    : creating
      ? "Creando los proveedores…"
      : !totals
        ? ""
        : totals.error > 0
          ? "Corregí la planilla y subila de nuevo: con errores no se crea ninguno."
          : create === 0
            ? "No hay proveedores nuevos para crear."
            : `${create === 1 ? "1 proveedor nuevo" : `${create} proveedores nuevos`}.`;

  function confirm() {
    if (!payload) return;
    const why = reasonField.safeParse(reason);
    if (!why.success) {
      setReasonError(why.error.issues[0]?.message ?? "Escribí el motivo.");
      document.getElementById(`${prefix}-motivo`)?.focus();
      return;
    }
    setReasonError(null);
    startCreating(async () => {
      try {
        setConfirmState(await confirmSupplierImportAction(payload, why.data));
      } catch (e) {
        // La redirección al listado viaja como excepción: se deja pasar.
        if (e && typeof e === "object" && "digest" in e) throw e;
        setConfirmState({
          status: "bad",
          message: "No pudimos crear los proveedores. Probá de nuevo.",
        });
      }
    });
  }

  return (
    <>
      <div className="desk:hidden">
        <Notice status="info">La importación de proveedores se hace en la computadora.</Notice>
      </div>
      <div className="hidden min-h-0 flex-[1_1_0px] flex-col gap-4 desk:flex">
        <Card className="flex flex-row items-end gap-6">
          <div className="flex flex-col gap-2">
            <span className={STEP}>
              1. Bajá la plantilla
              <InfoTip label="Qué lleva la plantilla">
                Una fila por proveedor. Razón social y CUIT son obligatorios. Las cuentas de pago
                (CBU, alias) y los números de cliente no van: se cargan en la ficha de cada
                proveedor.
              </InfoTip>
            </span>
            <Button asChild variant="outline">
              <a href="/proveedores/importar/plantilla" download>
                <Download aria-hidden="true" />
                Bajar la plantilla
              </a>
            </Button>
          </div>
          <form
            action={(data) => {
              setConfirmState({});
              setReasonError(null);
              preview(data);
            }}
            className="flex flex-row items-end gap-2"
            aria-label="Subir la planilla"
          >
            <div className="flex w-96 flex-col gap-2">
              <span className={STEP}>
                <label htmlFor={`${prefix}-archivo`}>2. Subí la planilla completa (.xlsx)</label>
                <InfoTip label="Qué pasa al revisar">
                  Revisar no crea nada: muestra qué pasa con cada fila. Un CUIT que ya está cargado
                  se omite. Si una fila tiene error, no se crea ninguno.
                </InfoTip>
              </span>
              <FileUpload
                id={`${prefix}-archivo`}
                name="file"
                required
                accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
              />
            </div>
            <Button type="submit" disabled={reviewing || creating}>
              <Upload aria-hidden="true" />
              {reviewing ? "Revisando…" : "Revisar"}
            </Button>
          </form>
        </Card>

        {/* Siempre presente, así el lector de pantalla anuncia cada cambio (como la importación de recetas). */}
        <p role="status" className="sr-only">
          {summary}
        </p>

        {previewNotice ? <Notice status="bad">{previewNotice}</Notice> : null}
        {rejectedRows ? <Notice status="bad">{rejectedRows.message}</Notice> : null}

        <div className="grid grid-cols-4 gap-4">
          <Metric
            compact
            label="Filas"
            value={totals ? totals.rows : null}
            missingReason={NOT_YET}
            emptyLabel="Sin filas"
            status="info"
            statusLabel="Leídas"
            period={state.status === "preview" ? state.fileName : undefined}
          />
          <Metric
            compact
            label="Se crean"
            value={totals ? totals.create : null}
            total={totals?.rows}
            missingReason={NOT_YET}
            emptyLabel="Sin filas"
            status={create > 0 ? "ok" : "none"}
            statusLabel={create > 0 ? "Nuevos" : "Ninguno"}
          />
          <Metric
            compact
            label="Se omiten"
            value={totals ? totals.skip : null}
            total={totals?.rows}
            missingReason={NOT_YET}
            emptyLabel="Sin filas"
            status={totals && totals.skip > 0 ? "info" : "ok"}
            statusLabel={totals && totals.skip > 0 ? "Ya existen" : "Ninguno"}
          />
          <Metric
            compact
            label="Con error"
            value={totals ? totals.error : null}
            total={totals?.rows}
            missingReason={NOT_YET}
            emptyLabel="Sin filas"
            status={totals && totals.error > 0 ? "bad" : "ok"}
            statusLabel={totals && totals.error > 0 ? "Corregir" : "Sin errores"}
          />
        </div>

        <Card className="relative flex min-h-0 flex-[1_1_0px] flex-col gap-3">
          <h2 className="text-base font-semibold text-ink">Qué pasa con cada fila</h2>
          {totals ? (
            <DataTable
              caption="Vista previa de la importación"
              columns={columns}
              rows={rows}
              rowKey={(r) => String(r.row)}
              scroll
            />
          ) : (
            <EmptyState title="Todavía no subiste la planilla.">{NOT_YET}</EmptyState>
          )}
        </Card>

        {totals ? (
          <div className="sticky bottom-0 z-10 -mx-gutter flex flex-col gap-2 border-t border-line bg-surface px-gutter py-2 wide:-mx-gutter-wide wide:px-gutter-wide">
            {confirmNotice && !rejectedRows ? <Notice status="bad">{confirmNotice}</Notice> : null}
            <div className="flex flex-row items-center gap-2">
              <span aria-hidden="true" className="mr-auto text-base font-semibold text-ink">
                {summary}
              </span>
              {payload ? (
                <>
                  <label htmlFor={`${prefix}-motivo`} className="text-sm font-medium text-ink">
                    Motivo
                    <span aria-hidden="true" className="text-bad-ink">
                      {" "}
                      *
                    </span>
                    <span className="sr-only"> de la importación</span>
                  </label>
                  <Input
                    id={`${prefix}-motivo`}
                    placeholder="Por ejemplo, carga inicial"
                    aria-required="true"
                    aria-invalid={reasonError ? true : undefined}
                    aria-describedby={reasonError ? `${prefix}-motivo-error` : undefined}
                    className="w-80"
                    maxLength={500}
                    value={reason}
                    onChange={(e) => {
                      setReason(e.target.value);
                      if (reasonError) setReasonError(null);
                    }}
                  />
                  {reasonError ? (
                    <span id={`${prefix}-motivo-error`} className="text-sm text-bad-ink">
                      {reasonError}
                    </span>
                  ) : null}
                  <Button type="button" disabled={creating} onClick={confirm}>
                    {creating
                      ? "Creando…"
                      : create === 1
                        ? "Crear 1 proveedor"
                        : `Crear ${create} proveedores`}
                  </Button>
                </>
              ) : null}
            </div>
          </div>
        ) : null}
      </div>
    </>
  );
}
