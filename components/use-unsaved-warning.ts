"use client";

import { useEffect } from "react";

const QUESTION = "Tenés cambios sin guardar. ¿Salir igual?";

// Lo que se usa del evento «navigate» (Navigation API).
type NavigateLike = Event & { navigationType?: string; destination?: { url: string } };

// Si hay cambios sin guardar, se pregunta antes de irse: al cerrar o recargar la pestaña (lo pregunta el
// navegador), al tocar un enlace de la aplicación, como las pestañas de la ficha (ADR-0036), y con «Atrás» o «Adelante»
// (ADR-0066).
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
    // «Atrás» y «Adelante»: se frenan antes de que la pantalla cambie (con popstate, Next ya la cambió). Donde el
    // navegador no tiene este evento o no deja frenarlo, se va sin preguntar, como antes.
    const back = (event: Event) => {
      const { navigationType, destination } = event as NavigateLike;
      if (event.defaultPrevented || !event.cancelable) return;
      if (navigationType !== "traverse" || !destination) return;
      const url = new URL(destination.url);
      if (url.pathname === window.location.pathname && url.search === window.location.search)
        return;
      if (!window.confirm(QUESTION)) event.preventDefault();
    };
    const navigation = (window as Window & { navigation?: EventTarget }).navigation;
    navigation?.addEventListener("navigate", back);
    window.addEventListener("beforeunload", warn);
    // En la fase de captura: antes de que el enlace de Next navegue.
    document.addEventListener("click", leave, true);
    return () => {
      navigation?.removeEventListener("navigate", back);
      window.removeEventListener("beforeunload", warn);
      document.removeEventListener("click", leave, true);
    };
  }, [dirty]);
}
