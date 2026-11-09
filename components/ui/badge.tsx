import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { Slot } from "radix-ui";

import { cn } from "@/lib/utils";

// Etiqueta de estado: fondo pastel + texto oscuro del mismo tono (design.md).
// El color nunca es la única señal: siempre lleva texto, y opcionalmente un ícono.
const badgeVariants = cva(
  "inline-flex w-fit shrink-0 items-center gap-1 rounded-sm px-2 py-0.5 text-sm font-medium whitespace-nowrap [&>svg]:pointer-events-none [&>svg]:size-4",
  {
    variants: {
      status: {
        neutral: "border border-line bg-surface text-ink",
        ok: "bg-ok text-ok-ink",
        warn: "bg-warn text-warn-ink",
        bad: "bg-bad text-bad-ink",
        info: "bg-info text-info-ink",
        // Sin datos o no aplicable (ADR-0036): nunca un estado positivo cuando no hay datos.
        none: "bg-none text-none-ink",
        review: "bg-review text-review-ink",
        draft: "bg-draft text-draft-ink",
      },
    },
    defaultVariants: {
      status: "neutral",
    },
  },
);

type BadgeStatus = NonNullable<VariantProps<typeof badgeVariants>["status"]>;

function Badge({
  className,
  status = "neutral",
  asChild = false,
  ...props
}: React.ComponentProps<"span"> & VariantProps<typeof badgeVariants> & { asChild?: boolean }) {
  const Comp = asChild ? Slot.Root : "span";

  return (
    <Comp
      data-slot="badge"
      data-status={status}
      className={cn(badgeVariants({ status }), className)}
      {...props}
    />
  );
}

export { Badge, badgeVariants, type BadgeStatus };
