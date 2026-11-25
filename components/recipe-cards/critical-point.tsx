import { cn } from "@/lib/utils";

// Punto crítico de un paso (ADR-0065): el mismo aviso en la ficha de edición y en las fichas técnicas, con su palabra.
export function CriticalPoint({ text, className }: { text: string; className?: string }) {
  return (
    <span
      className={cn(
        "block rounded-sm bg-warn px-2 py-1 text-warn-ink print:border print:border-ink",
        className,
      )}
    >
      <span className="font-semibold">Punto crítico:</span> {text}
    </span>
  );
}
