import * as React from "react";

import { cn } from "@/lib/utils";

// Encabezado de página (ADR-0036): título, una línea de contexto y la acción principal a la derecha.
// Mismo lugar para los botones en todo el sistema. Los títulos no compiten con los números.
// En las pantallas de carga sin scroll (ADR-0046) va todo en una línea: «← Volver», el nombre, sus datos (meta) y la
// acción a la derecha. Criterios de Soy (ADR-0068): el título es de 20 px en todas las pantallas (los números importan,
// los títulos no) y las acciones van en fila a la derecha, nunca apiladas: si no entra, se acomoda lo de la izquierda.
// En el celular se acomodan en varias líneas; en la computadora, en una sola fila que no se achica.
const ACTIONS = "flex flex-wrap items-center gap-2 desk:shrink-0 desk:flex-nowrap";

function PageHeader({
  title,
  heading,
  description,
  back,
  meta,
  actions,
  className,
}: {
  title: string;
  // Lo que dice el h1 si no es el título (una ficha: el nombre del registro, que llega después).
  heading?: React.ReactNode;
  description?: React.ReactNode;
  // «← Materias primas», en la misma línea del nombre.
  back?: React.ReactNode;
  // Lo que acompaña al nombre en la misma línea: código, rubro, estado.
  meta?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
}) {
  if (back || meta) {
    return (
      <div
        data-slot="page-header"
        className={cn(
          "flex flex-col gap-2 desk:flex-row desk:items-center desk:justify-between print:hidden",
          className,
        )}
      >
        <div className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
          {back}
          <h1 className="text-xl font-semibold [overflow-wrap:anywhere] text-ink">
            {heading ?? title}
          </h1>
          {meta}
        </div>
        {actions ? <div className={ACTIONS}>{actions}</div> : null}
      </div>
    );
  }
  return (
    <div
      data-slot="page-header"
      className={cn(
        "flex flex-col gap-3 desk:flex-row desk:items-start desk:justify-between print:hidden",
        className,
      )}
    >
      <div className="flex min-w-0 flex-col gap-1">
        <h1 className="text-xl font-semibold [overflow-wrap:anywhere] text-ink">
          {heading ?? title}
        </h1>
        {/* empty:hidden: una línea que llega vacía (en streaming) no deja hueco. */}
        {description ? (
          <p className="text-base text-ink-muted empty:hidden">{description}</p>
        ) : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}

export { PageHeader };
