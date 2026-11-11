"use client";

import { useWatch } from "react-hook-form";

import { formatMoney } from "@/lib/money";
import { formatNetYield, previewNetYield } from "@/lib/yields";

// La vista previa del formulario de mermas (ADR-0040): «Rinde 72,0 % neto · Costo neto $ X por kg», con lo que se
// escribe y, si un campo queda vacío, con lo que ya está aprobado. Es solo una guía: el costo real lo calcula la base
// cuando se aprueban las mermas. Va dentro del formulario (lee sus campos) y se anuncia al cambiar.
export function WastePreview({
  requiresThawing,
  approvedCleaning,
  approvedThawing,
  grossCost,
  per,
}: {
  requiresThawing: boolean;
  approvedCleaning: number | null;
  approvedThawing: number | null;
  grossCost: number | null;
  per: string;
}) {
  const [cleaningLoss, thawingLoss] = useWatch({ name: ["cleaning_loss", "thawing_loss"] }) as [
    string | undefined,
    string | undefined,
  ];
  const preview = previewNetYield({
    cleaningLoss: cleaningLoss ?? "",
    thawingLoss: thawingLoss ?? "",
    requiresThawing,
    approvedCleaning,
    approvedThawing,
  });
  const cost =
    preview.value === null
      ? ""
      : grossCost !== null
        ? ` · Costo neto ${formatMoney(grossCost / preview.value)} ${per}`
        : " · Sin precio para calcular el costo";
  return (
    <p
      role="status"
      aria-live="polite"
      className="rounded-sm bg-info px-3 py-2 text-base text-info-ink tabular-nums"
    >
      {preview.value === null
        ? `Vista previa: ${preview.missing}`
        : `Vista previa: ${formatNetYield(preview.value)}${cost}`}
    </p>
  );
}
