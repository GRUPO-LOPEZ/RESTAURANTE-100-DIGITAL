import { ChevronDown } from "lucide-react";

// Una acción plegada (como en la ficha de una persona): el título se toca para abrir el formulario.
export function Disclosure({ summary, children }: { summary: string; children: React.ReactNode }) {
  return (
    <details className="group rounded-sm border border-line">
      <summary className="flex min-h-touch cursor-pointer items-center justify-between gap-2 px-3 text-base font-medium text-primary underline-offset-4 hover:underline">
        {summary}
        <ChevronDown
          aria-hidden="true"
          className="size-5 shrink-0 transition-transform group-open:rotate-180"
        />
      </summary>
      <div className="flex flex-col gap-4 p-3">{children}</div>
    </details>
  );
}
