import { redirect } from "next/navigation";

// Las razones sociales se listan en el Panel de control y cada una tiene su ficha (ADR-0061). El enlace de antes lleva
// a la lista del Panel.
export default function RazonesSocialesPage(): never {
  redirect("/configuracion#razones-sociales");
}
