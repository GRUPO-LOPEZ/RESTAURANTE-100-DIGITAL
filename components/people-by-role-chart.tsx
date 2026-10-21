"use client";

import { Bar, BarChart, LabelList, ResponsiveContainer, XAxis, YAxis } from "recharts";

// Gráfico principal del tablero de usuarios: personas por rol. Una sola serie, con la
// cantidad escrita al lado de cada barra (el color nunca es la única señal).
export function PeopleByRoleChart({ data }: { data: { role_name: string; people: number }[] }) {
  const height = Math.max(160, data.length * 40);
  return (
    <figure className="flex flex-col gap-2">
      <figcaption className="text-sm text-ink-muted">Personas con cada rol</figcaption>
      <div style={{ height }} className="w-full">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart
            data={data}
            layout="vertical"
            margin={{ top: 4, right: 40, bottom: 4, left: 8 }}
          >
            <XAxis type="number" hide allowDecimals={false} />
            <YAxis
              type="category"
              dataKey="role_name"
              width={160}
              tickLine={false}
              axisLine={false}
              tick={{ fill: "var(--color-ink)", fontSize: 14 }}
            />
            <Bar
              dataKey="people"
              name="Personas"
              fill="var(--color-chart-1)"
              radius={[0, 8, 8, 0]}
              isAnimationActive={false}
            >
              <LabelList
                dataKey="people"
                position="right"
                style={{ fill: "var(--color-ink)", fontSize: 14 }}
              />
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
      {/* Para lectores de pantalla y sin JavaScript: la misma información como lista. */}
      <ul className="sr-only">
        {data.map((d) => (
          <li key={d.role_name}>
            {d.role_name}: {d.people}
          </li>
        ))}
      </ul>
    </figure>
  );
}
