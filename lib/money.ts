// Cómo se muestra la plata. Sin acceso a la base: lo usan también los componentes del navegador.
const money = new Intl.NumberFormat("es-AR", {
  style: "currency",
  currency: "ARS",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});
export function formatMoney(value: number | null | undefined): string {
  return value === null || value === undefined ? "—" : money.format(value);
}
// Un costo por gramo se ve mejor por kilo (y por mililitro, por litro).
export function perBaseLabel(unit: string | null): { factor: number; label: string } {
  if (unit === "g") return { factor: 1000, label: "por kg" };
  if (unit === "ml") return { factor: 1000, label: "por litro" };
  return { factor: 1, label: "por unidad" };
}
