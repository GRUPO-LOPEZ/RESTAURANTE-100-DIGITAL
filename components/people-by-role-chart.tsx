"use client";

import { Bar, BarChart, LabelList, ResponsiveContainer, XAxis, YAxis } from "recharts";

// Gráfico principal del tablero de usuarios: personas por rol. Una sola serie, con la
// cantidad escrita al lado de cada barra (el color nunca es la única señal). Para lectores de
// pantalla, la misma información va como lista; el gráfico queda fuera del recorrido con Tab.
export function PeopleByRoleChart({ data }: { data: { role_name: string; people: number }[] }) {
  const height = data.length * 40 + 16;
  return (
    <figure className="flex flex-col gap-2">
      <figcaption className="text-sm text-ink-muted">Personas con cada rol</figcaption>
      <div style={{ height }} className="w-full" aria-hidden="true">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart
            data={data}
            layout="vertical"
            margin={{ top: 8, right: 40, bottom: 8, left: 8 }}
            accessibilityLayer={false}
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
              barSize={24}
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
