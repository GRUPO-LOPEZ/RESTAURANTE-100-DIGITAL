import { Badge } from "@/components/ui/badge";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import {
  SCENARIO_RELIABILITY,
  formatDifference,
  formatMoneyDifference,
  type ScenarioRow,
} from "@/lib/cost-labels";
import { formatMoney } from "@/lib/money";

// El resultado de un escenario (ADR-0032), con la tabla común del rediseño (ADR-0036): en el celular, tarjetas.
// Un costo simulado nunca se lee como verificado: la columna de datos usa las etiquetas de simulación.
const columns: DataColumn<ScenarioRow>[] = [
  {
    key: "recipe",
    header: "Receta",
    mobile: "title",
    cell: (row) => <span className="font-medium text-ink">{row.recipe}</span>,
  },
  {
    key: "today",
    header: "Hoy",
    align: "right",
    cell: (row) => formatMoney(row.today),
  },
  {
    key: "simulated",
    header: "Simulado",
    align: "right",
    cell: (row) => formatMoney(row.simulated),
  },
  {
    key: "difference",
    header: "Diferencia",
    align: "right",
    cell: (row) =>
      row.difference === null
        ? "Sin diferencia: falta un costo"
        : `${formatMoneyDifference(row.difference)} (${formatDifference(row.differencePct)})`,
  },
  {
    key: "portion",
    header: "Por porción, simulado",
    align: "right",
    cell: (row) => formatMoney(row.portionSimulated),
  },
  {
    key: "reliability",
    header: "Datos de la simulación",
    mobile: "status",
    cell: (row) => {
      const r = SCENARIO_RELIABILITY[row.reliability];
      return <Badge status={r.status}>{r.label}</Badge>;
    },
  },
];

export function ScenarioTable({ rows }: { rows: ScenarioRow[] }) {
  return (
    <DataTable
      caption="Recetas alcanzadas"
      columns={columns}
      rows={rows}
      rowKey={(r) => r.recipeId}
    />
  );
}
