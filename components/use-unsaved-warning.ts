"use client";

import { useEffect } from "react";

const QUESTION = "Tenés cambios sin guardar. ¿Salir igual?";

// Si hay cambios sin guardar, se pregunta antes de irse: al cerrar o recargar la pestaña (lo pregunta el
// navegador) y al tocar un enlace de la aplicación, como las pestañas de la ficha (ADR-0036).
export function useUnsavedWarning(dirty: boolean) {
  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => event.preventDefault();
    const leave = (event: MouseEvent) => {
      if (event.defaultPrevented || event.button !== 0) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const link = (event.target as Element | null)?.closest?.("a[href]");
      if (!(link instanceof HTMLAnchorElement) || link.target === "_blank") return;
      const url = new URL(link.href, window.location.href);
      if (url.origin !== window.location.origin) return;
      if (url.pathname === window.location.pathname && url.search === window.location.search)
        return;
      if (!window.confirm(QUESTION)) {
        event.preventDefault();
        event.stopPropagation();
      }
    };
    window.addEventListener("beforeunload", warn);
    // En la fase de captura: antes de que el enlace de Next navegue.
    document.addEventListener("click", leave, true);
    return () => {
      window.removeEventListener("beforeunload", warn);
      document.removeEventListener("click", leave, true);
    };
  }, [dirty]);
}
