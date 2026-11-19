import Link from "next/link";

import { ActionModal } from "@/components/action-modal";
import { Badge } from "@/components/ui/badge";
import { Metric } from "@/components/ui/metric";
import { shortDate } from "@/lib/invoices";
import { formatMoney } from "@/lib/money";
import { MOVEMENT_LABELS } from "@/lib/payments";
import type { SupplierAccount } from "@/lib/payments-data";

// La cuenta corriente en la ficha del proveedor (Fase 3, Prompt 6, ADR-0060): el indicador «Saldo de cuenta corriente»
// con su estado y «Ver la cuenta corriente», que abre los movimientos con el saldo acumulado en un panel (pantallas sin
// scroll, ADR-0046: un indicador con su lista la abre en un panel). Al lado, el último saldo que informó el proveedor.

const link =
  "inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8";

// El estado del saldo: vencido (crítico), con saldo al día, sin deuda o a favor; siempre con palabra.
export function balanceState(a: SupplierAccount): {
  status: "ok" | "warn" | "bad" | "info";
  label: string;
} {
  if (a.overdue > 0.005) return { status: "bad", label: "Con vencidas" };
  if (a.balance < -0.005) return { status: "info", label: "A favor" };
  if (a.balance > 0.005) return { status: "ok", label: "Al día" };
  return { status: "ok", label: "Sin deuda" };
}

export function SupplierBalanceMetric({
  account,
  supplierName,
  placeName,
  canSee,
}: {
  account: SupplierAccount | null;
  supplierName: string;
  placeName: string | null;
  canSee: boolean;
}) {
  if (!canSee || !account) {
    return (
      <Metric
        compact
        label="Saldo de cuenta corriente"
        value={null}
        missingReason={canSee ? "Sin facturas ni pagos." : "Lo ven Compras y quienes ven pagos."}
        emptyLabel="Sin datos"
        status="none"
        statusLabel="Sin datos"
      />
    );
  }
  if (account.movement_count === 0) {
    return (
      <Metric
        compact
        label="Saldo de cuenta corriente"
        value={null}
        missingReason="Sin facturas ni pagos."
        emptyLabel="Sin datos"
        status="none"
        statusLabel="Sin datos"
      />
    );
  }
  const state = balanceState(account);
  // El saldo según el proveedor: se compara con el nuestro solo en un local (cada local es una cuenta).
  const theirs = account.supplier_balance;
  const differs = theirs !== null && Math.abs(theirs - account.balance) > 0.5;
  return (
    <Metric
      compact
      label="Saldo de cuenta corriente"
      value={formatMoney(account.balance)}
      period={placeName ?? "todos mis locales"}
      emptyLabel="Sin datos"
      status={differs && state.status === "ok" ? "warn" : state.status}
      statusLabel={differs && state.status === "ok" ? "No coincide" : state.label}
      action={
        <ActionModal
          label="Ver la cuenta corriente"
          variant="link"
          icon="none"
          size="sm"
          title={`Cuenta corriente de ${supplierName}`}
          description={
            placeName
              ? `En ${placeName}. Positivo: le debemos; negativo: a favor nuestro.`
              : "En todos tus locales. Positivo: le debemos; negativo: a favor nuestro."
          }
        >
          <AccountDetail account={account} />
        </ActionModal>
      }
    />
  );
}

function AccountDetail({ account }: { account: SupplierAccount }) {
  const theirs = account.supplier_balance;
  return (
    <div className="flex flex-col gap-4">
      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-base">
        {(
          [
            ["Facturado conforme", account.invoiced],
            ["Notas (crédito menos débito)", -account.credits],
            ["Pagado", -account.paid],
            ["Saldo", account.balance],
            ["Vencido", account.overdue],
            ["A cuenta (sin aplicar)", account.unapplied],
          ] as const
        ).map(([label, value]) => (
          <div key={label} className="contents">
            <dt className="text-ink">{label}</dt>
            <dd className="text-right text-ink tabular-nums">{formatMoney(value)}</dd>
          </div>
        ))}
      </dl>
      {theirs !== null ? (
        <p className="flex flex-wrap items-center gap-2 text-sm text-ink">
          <span className="tabular-nums">
            Saldo según el proveedor: {formatMoney(theirs)}
            {account.supplier_balance_on
              ? ` (factura del ${shortDate(account.supplier_balance_on)})`
              : ""}
          </span>
          {Math.abs(theirs - account.balance) > 0.5 ? (
            <Badge status="warn">
              No coincide por {formatMoney(Math.abs(theirs - account.balance))}
            </Badge>
          ) : (
            <Badge status="ok">Coincide</Badge>
          )}
        </p>
      ) : null}
      <div className="relative overflow-x-auto">
        <table className="w-full border-collapse text-base">
          <caption className="sr-only">Movimientos de la cuenta corriente</caption>
          <thead>
            <tr className="border-b border-line text-left text-sm text-ink-muted">
              <th scope="col" className="py-1 pr-2 font-medium">
                Fecha
              </th>
              <th scope="col" className="py-1 pr-2 font-medium">
                Movimiento
              </th>
              <th scope="col" className="py-1 pr-2 text-right font-medium">
                Importe
              </th>
              <th scope="col" className="py-1 text-right font-medium">
                Saldo
              </th>
            </tr>
          </thead>
          <tbody>
            {account.movements.map((m) => (
              <tr key={`${m.kind}-${m.source_id}`} className="border-b border-line">
                <td className="py-1 pr-2 whitespace-nowrap tabular-nums">
                  {shortDate(m.moved_on)}
                </td>
                <td className="py-1 pr-2">
                  {m.kind === "invoice" ? (
                    <Link href={`/compras/facturas/${m.source_id}`} className={link}>
                      {m.label}
                    </Link>
                  ) : (
                    <span>
                      {MOVEMENT_LABELS[m.kind]}
                      {m.label ? ` · ${m.label}` : ""}
                    </span>
                  )}
                </td>
                <td className="py-1 pr-2 text-right tabular-nums">{formatMoney(m.amount)}</td>
                <td className="py-1 text-right tabular-nums">{formatMoney(m.balance)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {account.movement_count > account.movements.length ? (
        <p className="text-sm text-ink-muted">
          Se ven los últimos {account.movements.length} de {account.movement_count} movimientos.
        </p>
      ) : null}
    </div>
  );
}
