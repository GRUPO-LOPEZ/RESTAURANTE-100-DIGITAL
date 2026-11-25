"use client";

import { useState } from "react";
import Image from "next/image";

import { cn } from "@/lib/utils";

// Una foto de receta. Si no carga (por ejemplo, el enlace firmado venció con la página abierta mucho
// tiempo), se ve un aviso con qué hacer, no el ícono de imagen rota del navegador.
// className reemplaza el recorte 4:3 (por ejemplo, la foto grande de la ficha, que se ve entera).
export function RecipePhotoImage({
  url,
  alt,
  className = "aspect-[4/3] w-full object-cover",
}: {
  url: string | null;
  alt: string;
  className?: string;
}) {
  const [broken, setBroken] = useState(false);
  if (!url || broken) {
    return (
      <div
        role="img"
        aria-label={`${alt}: no se pudo cargar`}
        className={cn(
          className,
          "flex items-center justify-center rounded-sm border border-line p-4 text-center text-base text-ink-muted",
        )}
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
      className={cn("rounded-sm border border-line", className)}
    />
  );
}
