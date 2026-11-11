"use client";

import * as React from "react";
import { Tooltip as RadixTooltip } from "radix-ui";

// Tooltip (regla de edición directa: las explicaciones van en un tooltip, no en texto largo). Se abre con el
// mouse y con el foco del teclado; Radix lo anuncia al lector de pantalla con aria-describedby. El disparador
// tiene que poder recibir foco (un botón, o un elemento con tabIndex={0}).
function TooltipProvider({ children }: { children: React.ReactNode }) {
  return (
    <RadixTooltip.Provider delayDuration={200} skipDelayDuration={100}>
      {children}
    </RadixTooltip.Provider>
  );
}

function Tooltip({
  content,
  children,
  side = "top",
}: {
  content: React.ReactNode;
  children: React.ReactElement;
  side?: "top" | "right" | "bottom" | "left";
}) {
  return (
    <RadixTooltip.Root>
      <RadixTooltip.Trigger asChild>{children}</RadixTooltip.Trigger>
      <RadixTooltip.Portal>
        <RadixTooltip.Content
          side={side}
          sideOffset={6}
          collisionPadding={16}
          className="z-50 flex max-w-xs flex-col gap-1 rounded-sm border border-line bg-surface px-3 py-2 text-sm text-ink"
        >
          {content}
        </RadixTooltip.Content>
      </RadixTooltip.Portal>
    </RadixTooltip.Root>
  );
}

export { Tooltip, TooltipProvider };
