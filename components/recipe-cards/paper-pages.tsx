import type { ReactNode } from "react";

import { cn } from "@/lib/utils";

// Lo impreso repite su encabezado en todas las hojas (pedido de Joaco): una hoja suelta dice de qué receta y versión es.
// Solo en el papel se arma como una tabla, que es lo que el navegador sabe repetir; en la pantalla no cambia nada.
export function PaperPages({
  header,
  className = "contents",
  children,
}: {
  header: ReactNode;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className={cn(className, "print:table print:w-full print:table-fixed")}>
      <div className="hidden print:table-header-group print:break-inside-avoid">
        <div className="pb-4">
          <div className="flex flex-col gap-1 border-b border-ink pb-2">{header}</div>
        </div>
      </div>
      <div className="contents print:table-row-group">
        <div className="contents print:table-row">
          <div className="contents print:table-cell print:space-y-4">{children}</div>
        </div>
      </div>
    </div>
  );
}
