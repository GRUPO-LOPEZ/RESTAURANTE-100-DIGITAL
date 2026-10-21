import { Notice } from "@/components/ui/notice";

// Muestra el mensaje que devolvió una acción de servidor.
export function FormNotice({
  state,
}: {
  state: { status?: "ok" | "info" | "warn" | "bad"; message?: string };
}) {
  if (!state.message) return null;
  return <Notice status={state.status ?? "info"}>{state.message}</Notice>;
}
