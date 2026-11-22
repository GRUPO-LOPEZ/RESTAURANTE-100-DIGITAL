import { redirect } from "next/navigation";

// Las marcas se ven y se editan en el Panel de control, en una pantalla (ADR-0061). Los enlaces de antes llevan ahí.
export default function MarcasPage(): never {
  redirect("/configuracion#marcas");
}
