"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { formatMoney } from "@/lib/money";
import {
  SPEND_KIND_LABELS,
  historyRows,
  lastChange,
  type HistoryInput,
  type SpendBar,
} from "@/lib/purchasing-board";

// Los gráficos del Tablero de compras (ADR-0060). Barras y líneas en los tonos fuertes (3:1 sobre el fondo, ADR-0015),
// hasta 4 series, el texto en el color de texto, y los mismos números en una tabla («Ver los números») y para lectores
// de pantalla: el color nunca es la única señal. Ocupan el alto que les deja la tarjeta (pantalla sin scroll).

const SPEND_COLORS: Record<SpendBar["kind"], string> = {
  recipes: "var(--color-chart-strong-1)",
  other: "var(--color-chart-strong-2)",
  rest: "var(--color-chart-strong-6)",
  freight: "var(--color-chart-strong-3)",
  perception: "var(--color-chart-strong-5)",
};
const LINE_COLORS = [
  "var(--color-chart-strong-1)",
  "var(--color-chart-strong-4)",
  "var(--color-chart-strong-2)",
  "var(--color-chart-strong-5)",
];
// Además del color, cada línea lleva su trazo (lleno, rayado, punteado), también en la leyenda: el color nunca es la
// única señal.
const LINE_DASH = [undefined, "6 3", "2 3", "10 4"];

const compact = new Intl.NumberFormat("es-AR", { notation: "compact", maximumFractionDigits: 1 });
const pct = new Intl.NumberFormat("es-AR", {
  maximumFractionDigits: 1,
  signDisplay: "exceptZero",
});

const tooltipStyle = {
  contentStyle: {
    background: "var(--color-surface)",
    border: "1px solid var(--color-line)",
    borderRadius: 8,
    color: "var(--color-ink)",
    fontSize: 14,
  },
  labelStyle: { color: "var(--color-ink)", fontWeight: 500 },
  itemStyle: { color: "var(--color-ink)" },
};
const tick = { fill: "var(--color-ink-muted)", fontSize: 12 };

function shortDay(day: string): string {
  const [, m, d] = day.slice(0, 10).split("-");
  return `${d}/${m}`;
}

// El alto que queda en la tarjeta; en el celular, uno fijo.
function ChartBox({ children }: { children: React.ReactElement }) {
  return (
    <div className="relative h-56 desk:h-auto desk:min-h-32 desk:flex-1" aria-hidden="true">
      <div className="absolute inset-0">
        <ResponsiveContainer width="100%" height="100%">
          {children}
        </ResponsiveContainer>
      </div>
    </div>
  );
}

function Numbers({ children }: { children: React.ReactNode }) {
  return (
    <details className="text-sm">
      <summary className="flex min-h-touch cursor-pointer items-center text-primary underline-offset-4 hover:underline desk:min-h-8">
        Ver los números
      </summary>
      {children}
    </details>
  );
}

export function SpendChart({ bars }: { bars: SpendBar[] }) {
  const kinds = [...new Set(bars.map((b) => b.kind))];
  return (
    <figure className="flex min-h-0 flex-1 flex-col gap-2">
      <figcaption className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-ink">
        {kinds.map((k) => (
          <span key={k} className="inline-flex items-center gap-1">
            <span
              aria-hidden="true"
              className="inline-block size-3 rounded-sm"
              style={{ background: SPEND_COLORS[k] }}
            />
            {SPEND_KIND_LABELS[k]}
          </span>
        ))}
      </figcaption>
      <ChartBox>
        <BarChart
          accessibilityLayer={false}
          data={bars}
          layout="vertical"
          margin={{ top: 0, right: 16, bottom: 0, left: 0 }}
        >
          <CartesianGrid horizontal={false} stroke="var(--color-line)" />
          <XAxis
            type="number"
            tickLine={false}
            axisLine={false}
            tick={tick}
            tickFormatter={(v: number) => compact.format(v)}
          />
          <YAxis
            type="category"
            dataKey="label"
            width={128}
            tickLine={false}
            axisLine={{ stroke: "var(--color-line)" }}
            tick={tick}
            interval={0}
          />
          <Tooltip
            cursor={{ fill: "var(--color-line)", opacity: 0.4 }}
            formatter={(v) => [formatMoney(Number(v)), "Gasto"]}
            {...tooltipStyle}
          />
          <Bar dataKey="amount" radius={[0, 4, 4, 0]} isAnimationActive={false}>
            {bars.map((b) => (
              <Cell key={b.label} fill={SPEND_COLORS[b.kind]} />
            ))}
          </Bar>
        </BarChart>
      </ChartBox>
      <Numbers>
        <table className="w-full text-left tabular-nums">
          <caption className="sr-only">Gasto por rubro del mes</caption>
          <thead>
            <tr className="border-b border-line text-ink-muted">
              <th scope="col" className="py-1 font-medium">
                Rubro
              </th>
              <th scope="col" className="py-1 font-medium">
                Tipo
              </th>
              <th scope="col" className="py-1 text-right font-medium">
                Gasto
              </th>
            </tr>
          </thead>
          <tbody>
            {bars.map((b) => (
              <tr key={b.label} className="border-b border-line last:border-0">
                <th scope="row" className="py-1 font-normal text-ink">
                  {b.label}
                </th>
                <td className="py-1 text-ink">{SPEND_KIND_LABELS[b.kind]}</td>
                <td className="py-1 text-right text-ink">{formatMoney(b.amount)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Numbers>
    </figure>
  );
}

export function CostHistoryChart({ series }: { series: HistoryInput[] }) {
  const rows = historyRows(series);
  return (
    <figure className="flex min-h-0 flex-1 flex-col gap-2">
      <figcaption className="text-sm text-ink">
        Variación del costo desde su primer precio de los últimos 90 días, de las que más se compran
      </figcaption>
      <ChartBox>
        <LineChart
          accessibilityLayer={false}
          data={rows}
          margin={{ top: 8, right: 16, bottom: 0, left: 0 }}
        >
          <CartesianGrid vertical={false} stroke="var(--color-line)" />
          <XAxis
            dataKey="on"
            tickLine={false}
            axisLine={{ stroke: "var(--color-line)" }}
            tick={tick}
            tickFormatter={shortDay}
            minTickGap={24}
          />
          <YAxis
            tickLine={false}
            axisLine={false}
            width={48}
            tick={tick}
            tickFormatter={(v: number) => `${pct.format(v)} %`}
          />
          <Tooltip
            labelFormatter={(l) => shortDay(String(l))}
            formatter={(v, name) => [v === null ? "—" : `${pct.format(Number(v))} %`, name]}
            {...tooltipStyle}
          />
          <Legend
            verticalAlign="top"
            align="left"
            wrapperStyle={{ fontSize: 14, paddingBottom: 4 }}
            formatter={(value: string) => <span className="text-ink">{value}</span>}
          />
          {series.map((s, i) => (
            <Line
              key={s.ingredient_id}
              dataKey={s.ingredient_id}
              name={s.name}
              stroke={LINE_COLORS[i % LINE_COLORS.length]}
              strokeDasharray={LINE_DASH[i % LINE_DASH.length]}
              strokeWidth={2}
              dot={{ r: 3 }}
              legendType="plainline"
              connectNulls
              isAnimationActive={false}
            />
          ))}
        </LineChart>
      </ChartBox>
      <Numbers>
        <table className="w-full text-left tabular-nums">
          <caption className="sr-only">Cómo subieron los insumos</caption>
          <thead>
            <tr className="border-b border-line text-ink-muted">
              <th scope="col" className="py-1 font-medium">
                Materia prima
              </th>
              <th scope="col" className="py-1 text-right font-medium">
                Variación
              </th>
            </tr>
          </thead>
          <tbody>
            {series.map((s) => {
              const change = lastChange(s);
              return (
                <tr key={s.ingredient_id} className="border-b border-line last:border-0">
                  <th scope="row" className="py-1 font-normal text-ink">
                    {s.name}
                  </th>
                  <td className="py-1 text-right text-ink">
                    {change === null ? "Sin precios" : `${pct.format(change)} %`}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </Numbers>
    </figure>
  );
}
