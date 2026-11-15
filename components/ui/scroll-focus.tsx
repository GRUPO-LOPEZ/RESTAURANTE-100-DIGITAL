"use client";

import { useEffect, useRef } from "react";

// Una tarjeta que se desplaza adentro (ADR-0051) tiene que poder recorrerse con el teclado aunque abajo solo haya
// texto: mientras de verdad se desplaza, entra en el orden de Tab (tabIndex 0) y las flechas la mueven. Cuando todo
// entra, vuelve a como estaba (tabIndex -1 si es el destino de un enlace de antes, o nada).
export function ScrollFocus() {
  const ref = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const box = ref.current?.parentElement;
    if (!box) return;
    const original = box.getAttribute("tabindex");
    function update() {
      if (!box) return;
      const overflows = box.scrollHeight > box.clientHeight + 1;
      if (overflows) box.setAttribute("tabindex", "0");
      else if (original === null) box.removeAttribute("tabindex");
      else box.setAttribute("tabindex", original);
    }
    update();
    const observer = new ResizeObserver(update);
    observer.observe(box);
    for (const child of Array.from(box.children)) observer.observe(child);
    return () => {
      observer.disconnect();
      if (original === null) box.removeAttribute("tabindex");
      else box.setAttribute("tabindex", original);
    };
  }, []);
  return <span ref={ref} hidden />;
}
