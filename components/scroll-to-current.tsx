"use client";

import { useEffect, useRef } from "react";

// Dentro de una lista que se desplaza (el panel de rubros): lleva el elegido a la vista al llegar. Mueve solo la lista y
// su caja, nunca la página.
export function ScrollToCurrent({ current }: { current: string | undefined }) {
  const mark = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const root = mark.current?.closest("nav");
    const item = root?.querySelector<HTMLElement>('[aria-current="true"]');
    if (!root || !item) return;
    for (const box of [item.closest("ul"), root]) {
      if (!box) continue;
      const a = item.getBoundingClientRect();
      const b = box.getBoundingClientRect();
      if (box.scrollWidth > box.clientWidth) {
        if (a.right > b.right) box.scrollLeft += a.right - b.right + 8;
        else if (a.left < b.left) box.scrollLeft -= b.left - a.left + 8;
      }
      if (box.scrollHeight > box.clientHeight) {
        if (a.bottom > b.bottom) box.scrollTop += a.bottom - b.bottom + 8;
        else if (a.top < b.top) box.scrollTop -= b.top - a.top + 8;
      }
    }
  }, [current]);
  return <span ref={mark} hidden />;
}
