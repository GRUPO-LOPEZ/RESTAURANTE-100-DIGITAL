import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { Slot } from "radix-ui";

import { cn } from "@/lib/utils";

// Todos los tamaños respetan el mínimo táctil de 44 px (design.md, "Celular primero").
const buttonVariants = cva(
  "inline-flex min-h-touch shrink-0 items-center justify-center gap-2 rounded-sm border border-transparent px-4 text-base font-medium whitespace-nowrap transition-colors select-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:pointer-events-none disabled:opacity-50 aria-invalid:border-bad-ink [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-5",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-ink hover:bg-primary/90",
        outline: "border-line bg-surface text-ink hover:bg-app",
        ghost: "text-ink hover:bg-app",
        destructive: "bg-bad text-bad-ink hover:bg-bad/80",
        link: "min-h-0 px-0 text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "",
        wide: "w-full",
        icon: "w-touch px-0",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

function Button({
  className,
  variant = "default",
  size = "default",
  asChild = false,
  ...props
}: React.ComponentProps<"button"> &
  VariantProps<typeof buttonVariants> & {
    asChild?: boolean;
  }) {
  const Comp = asChild ? Slot.Root : "button";

  return (
    <Comp
      data-slot="button"
      data-variant={variant}
      data-size={size}
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  );
}

export { Button, buttonVariants };
