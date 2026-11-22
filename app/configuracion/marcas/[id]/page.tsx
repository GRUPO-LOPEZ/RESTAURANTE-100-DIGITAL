import { redirect } from "next/navigation";
import { Suspense } from "react";

import { UUID } from "@/lib/data";

// La ficha de una marca es un panel del Panel de control (ADR-0061): el enlace de antes lo abre ahí. Los parámetros
// se leen dentro de un Suspense (Next 16, componentes en caché).
export default function MarcaPage({ params }: PageProps<"/configuracion/marcas/[id]">) {
  return (
    <Suspense fallback={null}>
      <ToPanel params={params} />
    </Suspense>
  );
}

async function ToPanel({
  params,
}: {
  params: PageProps<"/configuracion/marcas/[id]">["params"];
}): Promise<never> {
  const { id } = await params;
  redirect(UUID.test(id) ? `/configuracion?marca=${id}#marcas` : "/configuracion#marcas");
}
