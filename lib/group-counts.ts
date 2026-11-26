// Panel izquierdo de los listados (criterio 7 de Soy, ADR-0068): cada grupo (proveedor o rubro) con su cantidad.
// Lo puro, sin base: se prueba en tests/unit/group-counts.test.ts.

export type GroupItem = { id: string; name: string; count: number };

const collator = new Intl.Collator("es-AR", { sensitivity: "base", numeric: true });

// Los grupos en orden alfabético (como se leen en castellano: «Ñ» después de «N», sin importar mayúsculas ni tildes).
// El elegido siempre aparece, aunque con los filtros de ahora no tenga nada (con 0): si no, la persona no ve qué está
// filtrando ni puede volver a «Todos» desde ahí.
export function panelGroups(
  items: GroupItem[],
  selected?: { id: string; name: string },
): GroupItem[] {
  const list = [...items];
  if (selected && !list.some((g) => g.id === selected.id)) {
    list.push({ id: selected.id, name: selected.name, count: 0 });
  }
  return list.sort((a, b) => collator.compare(a.name, b.name) || a.id.localeCompare(b.id));
}

// «Todos»: la suma, cuando cada registro está en un solo grupo (un proveedor por orden, factura o lista).
export function sumCounts(items: GroupItem[]): number {
  return items.reduce((sum, g) => sum + g.count, 0);
}
