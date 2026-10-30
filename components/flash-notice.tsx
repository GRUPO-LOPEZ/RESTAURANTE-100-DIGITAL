"use client";

import { useEffect, useRef } from "react";

import { Notice } from "@/components/ui/notice";

// Aviso de una sola vez, después de volver a la pantalla con un parámetro (por ejemplo, "?baja=…").
// Lleva el foco al aviso para que el lector de pantalla lo lea, y saca el parámetro de la dirección:
// así no vuelve a aparecer al recargar ni junto al aviso de la acción siguiente.
export function FlashNotice({ children }: { children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    ref.current?.focus();
    window.history.replaceState(null, "", window.location.pathname);
  }, []);
  return (
    <Notice ref={ref} status="ok" tabIndex={-1}>
      {children}
    </Notice>
  );
}
