import * as React from "react";

import { cn } from "@/lib/utils";

// Tarjeta plana: fondo blanco, borde fino de 1 px, radio de 10 px, sin sombras (design.md).
function Card({ className, ...props }: React.ComponentProps<"section">) {
  return (
    <section
      data-slot="card"
      className={cn("rounded-md border border-line bg-surface p-4 desk:p-6", className)}
      {...props}
    />
  );
}

function CardTitle({ className, ...props }: React.ComponentProps<"h2">) {
  return <h2 data-slot="card-title" className={cn("text-xl text-ink", className)} {...props} />;
}

function CardDescription({ className, ...props }: React.ComponentProps<"p">) {
  return (
    <p
      data-slot="card-description"
      className={cn("text-sm text-ink-muted", className)}
      {...props}
    />
  );
}

export { Card, CardDescription, CardTitle };
