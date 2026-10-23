import * as React from "react";

import { cn } from "@/lib/utils";

// Casilla con su texto al lado, toda el área se puede tocar (mínimo 44 px de alto).
function Checkbox({
  id,
  label,
  className,
  ...props
}: Omit<React.ComponentProps<"input">, "type"> & { id: string; label: string }) {
  return (
    <label
      htmlFor={id}
      data-slot="checkbox"
      className={cn(
        "flex min-h-touch cursor-pointer items-center gap-3 text-base text-ink",
        className,
      )}
    >
      <input
        id={id}
        type="checkbox"
        className="size-5 shrink-0 accent-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        {...props}
      />
      {label}
    </label>
  );
}

export { Checkbox };
