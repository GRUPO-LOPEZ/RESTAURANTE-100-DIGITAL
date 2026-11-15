"use client";

import { useState, useTransition } from "react";

import { setActiveRestaurantAction } from "@/app/shell-actions";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/states";

// Una pantalla que se ve de a un local, con «Todos mis locales» arriba (ADR-0036: el selector es único y global). Lo dice
// claro y cada botón aplica ese local en la barra de arriba (ADR-0048): lo que muestra el selector es lo aplicado.
// Si el local aplicado no sirve para esta pantalla (por ejemplo, no ves sus costos), lo dice en vez de pedir uno.
export function PlacePrompt({
  title,
  places,
  activeName,
}: {
  // «Costos se ve de a un local.»
  title: string;
  places: { id: string; name: string }[];
  // Lo que se sabe del local aplicado arriba: un nombre (está aplicado pero esta pantalla no lo puede mostrar), null
  // («Todos mis locales») o nada (la pantalla no lo sabe: el texto no afirma nada).
  activeName?: string | null;
}) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function pick(id: string) {
    setError(null);
    startTransition(async () => {
      const form = new FormData();
      form.set("restaurant", id);
      const result = await setActiveRestaurantAction({}, form);
      if (result.status === "bad") setError(result.message ?? "No pudimos cambiar el local.");
    });
  }

  return (
    <EmptyState title={title}>
      <p>
        {activeName
          ? `Arriba está elegido ${activeName}, y acá no lo podés ver. Elegí otro:`
          : activeName === null
            ? "Arriba está elegido «Todos mis locales». Elegí cuál ver:"
            : "Elegí cuál ver (queda elegido también arriba):"}
      </p>
      <ul className="mt-2 flex flex-wrap justify-center gap-2" aria-label="Tus locales">
        {places.map((p) => (
          <li key={p.id}>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={pending}
              onClick={() => pick(p.id)}
            >
              {p.name}
            </Button>
          </li>
        ))}
      </ul>
      {error ? (
        <p role="alert" className="mt-2 text-sm text-bad-ink">
          {error}
        </p>
      ) : null}
    </EmptyState>
  );
}
