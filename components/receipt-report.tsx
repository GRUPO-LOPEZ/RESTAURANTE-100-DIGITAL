import { Badge } from "@/components/ui/badge";
import { formatDateTime } from "@/lib/data";
import { formatMoney } from "@/lib/money";
import { qtyText } from "@/lib/purchase-orders";
import { ISSUE_LABEL, PAPER_LABEL, RESULT } from "@/lib/receipts";
import type { Receipt } from "@/lib/receipts-data";

// El informe de una recepción cerrada (Fase 3, Prompt 4, ADR-0056): quién y cuándo recibió, el papel con sus dos fotos
// (y sus páginas), lo observado renglón por renglón y los lotes. El efectivo, con su importe solo para quien ve precios.
export function ReceiptReport({ receipt, heading }: { receipt: Receipt; heading?: string }) {
  const observed = receipt.done.filter((l) => !l.ok);
  const okCount = receipt.done.length - observed.length;
  const lots = receipt.done.filter((l) => l.lot);
  const result = receipt.result ? RESULT[receipt.result] : null;
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        {heading ? <h3 className="text-base font-semibold text-ink">{heading}</h3> : null}
        {result ? <Badge status={result.status}>{result.label}</Badge> : null}
      </div>
      <p className="text-sm text-ink tabular-nums">
        Recibió {receipt.receivedByName}
        {receipt.closedAt ? ` el ${formatDateTime(receipt.closedAt)}` : ""} ·{" "}
        {receipt.paperKind ? PAPER_LABEL[receipt.paperKind] : "Papel sin indicar"}
        {receipt.paperNumber ? ` ${receipt.paperNumber}` : ""}
      </p>
      {receipt.cashPaid ? (
        <p className="text-sm text-ink tabular-nums">
          Se pagó en efectivo
          {receipt.canSeeCash && receipt.cashAmount !== null
            ? `: ${formatMoney(receipt.cashAmount)}`
            : ""}
          . Lo confirma Compras.
        </p>
      ) : null}
      {receipt.photos.length > 0 ? (
        <ul aria-label="Fotos del papel" className="flex flex-wrap gap-2">
          {receipt.photos.map((p) => {
            const name = `${p.kind === "receipt_original" ? "Foto 1 (como llegó)" : "Foto 2 (firmado)"}, página ${p.page}`;
            return (
              <li key={p.id}>
                {p.url ? (
                  <a
                    href={p.url}
                    target="_blank"
                    rel="noreferrer"
                    className="flex flex-col gap-1 rounded-sm text-sm text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-primary"
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element -- enlace firmado de Storage, de 5 minutos */}
                    <img
                      src={p.url}
                      alt=""
                      className="h-24 w-20 rounded-sm border border-line bg-app object-cover"
                    />
                    <span className="max-w-24">
                      {name}
                      <span className="sr-only"> (se abre en otra pestaña)</span>
                    </span>
                  </a>
                ) : (
                  <span className="text-sm text-ink-muted">{name}: guardada</span>
                )}
              </li>
            );
          })}
        </ul>
      ) : null}
      <p className="text-sm text-ink">
        {okCount === 1 ? "1 renglón OK" : `${okCount} renglones OK`}
        {observed.length > 0
          ? ` · ${observed.length === 1 ? "1 observado" : `${observed.length} observados`}`
          : ""}
      </p>
      {observed.length > 0 ? (
        <ul aria-label="Renglones observados" className="flex flex-col divide-y divide-line">
          {observed.map((l) => (
            <li key={l.id} className="flex flex-col gap-1 py-2">
              <p className="flex flex-wrap items-center gap-2 text-base text-ink">
                <span className="font-medium">{l.name}</span>
                <Badge status="warn">
                  {l.fromOrder
                    ? l.issue
                      ? ISSUE_LABEL[l.issue]
                      : "Observado"
                    : "No estaba en la orden"}
                </Badge>
              </p>
              <p className="text-sm text-ink-muted tabular-nums">
                Llegó {qtyText(l.received)}
                {l.ordered !== null ? ` de ${qtyText(l.ordered)}` : ""}{" "}
                {l.packageName ?? l.unitName ?? ""}
                {l.weight !== null ? ` · ${qtyText(l.weight)} kg` : ""}
                {l.lot ? ` · Lote ${l.lot}` : ""}
                {l.unmapped ? " · El chef tiene que decir qué materia prima es" : ""}
                {l.note ? ` · ${l.note}` : ""}
              </p>
              {l.photos.length > 0 ? (
                <ul aria-label={`Fotos de ${l.name}`} className="flex flex-wrap gap-2">
                  {l.photos.map((p, i) =>
                    p.url ? (
                      <li key={p.id}>
                        <a
                          href={p.url}
                          target="_blank"
                          rel="noreferrer"
                          className="inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-control-sm"
                        >
                          Foto {i + 1}
                          <span className="sr-only"> de {l.name} (se abre en otra pestaña)</span>
                        </a>
                      </li>
                    ) : null,
                  )}
                </ul>
              ) : null}
            </li>
          ))}
        </ul>
      ) : null}
      {lots.length > 0 ? (
        <p className="text-sm text-ink">
          Lotes:{" "}
          {lots.map((l, i) => (
            <span key={l.id}>
              {i > 0 ? ", " : ""}
              {l.name} ({l.lot})
            </span>
          ))}
        </p>
      ) : null}
    </div>
  );
}
