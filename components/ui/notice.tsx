import * as React from "react";
import { CircleAlert, CircleCheck, Info, TriangleAlert } from "lucide-react";

import { cn } from "@/lib/utils";

const styles = {
  ok: { box: "bg-ok text-ok-ink", Icon: CircleCheck },
  warn: { box: "bg-warn text-warn-ink", Icon: TriangleAlert },
  bad: { box: "bg-bad text-bad-ink", Icon: CircleAlert },
  info: { box: "bg-info text-info-ink", Icon: Info },
} as const;

// Aviso en pastel con su texto oscuro y un ícono: el color nunca es la única señal.
function Notice({
  status = "info",
  className,
  children,
  ...props
}: React.ComponentProps<"div"> & { status?: keyof typeof styles }) {
  const { box, Icon } = styles[status];
  return (
    <div
      data-slot="notice"
      data-status={status}
      role={status === "bad" || status === "warn" ? "alert" : "status"}
      className={cn("flex items-start gap-2 rounded-sm px-4 py-3 text-base", box, className)}
      {...props}
    >
      <Icon aria-hidden="true" className="mt-0.5 size-5 shrink-0" />
      <div>{children}</div>
    </div>
  );
}

export { Notice };
