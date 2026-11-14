"use client";

import { useEffect } from "react";

// Pantallas sin scroll (ADR-0046): los enlaces de antes (Calidad, ?seccion=, #ancla) ya no bajan a una sección, porque
// todo está a la vista. Llevan el foco a su tarjeta, que se marca con el borde de :target (la tarjeta tiene
// tabIndex=-1). Solo busca dentro de la pantalla visible: Next guarda ocultas las anteriores.
export function FocusTarget() {
  useEffect(() => {
    function focusHash() {
      // Una dirección mal armada (#%E0) no rompe la pantalla: no se enfoca nada.
      let id = "";
      try {
        id = decodeURIComponent(window.location.hash.slice(1));
      } catch {
        return;
      }
      if (!id) return;
      const el = document.getElementById(id);
      if (el && el.offsetParent !== null) el.focus({ preventScroll: false });
    }
    focusHash();
    // Un enlace de Next cambia la dirección sin «hashchange»: también se escucha «popstate» (volver y avanzar).
    window.addEventListener("hashchange", focusHash);
    window.addEventListener("popstate", focusHash);
    return () => {
      window.removeEventListener("hashchange", focusHash);
      window.removeEventListener("popstate", focusHash);
    };
  }, []);
  return null;
}
