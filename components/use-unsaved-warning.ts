"use client";

import { useEffect } from "react";

// Si hay cambios sin guardar, el navegador pregunta antes de cerrar o recargar la pestaña.
export function useUnsavedWarning(dirty: boolean) {
  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => event.preventDefault();
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);
}
