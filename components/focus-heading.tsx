"use client";

import { useEffect } from "react";

// Después de una acción que cambia la ficha (suspender, cerrar sesiones), el botón que la abrió ya no está: el foco va
// al título de la pantalla, junto al aviso (WCAG 2.4.3). Solo con un aviso en la dirección y en la pantalla visible.
export function FocusHeading({ when }: { when: string | undefined }) {
  useEffect(() => {
    if (!when) return;
    const h1 = [...document.querySelectorAll("h1")].find((el) => el.offsetParent !== null);
    if (!h1) return;
    h1.setAttribute("tabindex", "-1");
    h1.focus({ preventScroll: true });
  }, [when]);
  return null;
}
