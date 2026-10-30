"use client";

import { useState } from "react";
import Image from "next/image";

// Una foto de receta. Si no carga (por ejemplo, el enlace firmado venció con la página abierta mucho
// tiempo), se ve un aviso con qué hacer, no el ícono de imagen rota del navegador.
export function RecipePhotoImage({ url, alt }: { url: string | null; alt: string }) {
  const [broken, setBroken] = useState(false);
  if (!url || broken) {
    return (
      <div
        role="img"
        aria-label={`${alt}: no se pudo cargar`}
        className="flex aspect-[4/3] w-full items-center justify-center rounded-sm border border-line p-4 text-center text-base text-ink-muted"
      >
        No pudimos cargar la foto. Recargá la página.
      </div>
    );
  }
  return (
    <Image
      src={url}
      alt={alt}
      width={800}
      height={600}
      unoptimized
      onError={() => setBroken(true)}
      className="aspect-[4/3] w-full rounded-sm border border-line object-cover"
    />
  );
}
