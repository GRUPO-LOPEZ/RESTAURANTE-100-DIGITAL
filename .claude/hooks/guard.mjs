// PreToolUse: protege secretos y ambientes remotos (prompt maestro, secciones 4 y 10).
// - Ninguna herramienta lee ni escribe archivos .env* (salvo .env.example).
// - Ningún comando apunta a un proyecto remoto de Supabase ni fuerza un push.
import { block, readEvent, relativePath } from "./lib.mjs";

const event = readEvent();
const tool = event.tool_name ?? "";
const input = event.tool_input ?? {};

const ENV_FILE = /(^|[\\/\s"'=])\.env(?!\.example\b)[\w.-]*/;

if (["Read", "Edit", "Write", "MultiEdit", "NotebookEdit"].includes(tool)) {
  const rel = relativePath(event, input.file_path ?? input.notebook_path);
  if (ENV_FILE.test(`/${rel}`)) {
    block(`no se leen ni editan archivos de variables de entorno (${rel}). Usá .env.example.`);
  }
}

if (tool === "Grep" || tool === "Glob") {
  // En Grep, "pattern" es el texto a buscar; solo se miran la ruta y el filtro de archivos.
  const target = [input.path, input.glob, tool === "Glob" ? input.pattern : ""].join(" ");
  if (ENV_FILE.test(` ${target}`)) {
    block("no se buscan archivos de variables de entorno.");
  }
}

if (tool === "Bash" || tool === "PowerShell") {
  const cmd = String(input.command ?? "");
  if (ENV_FILE.test(` ${cmd}`)) {
    block("el comando toca un archivo .env*. Las claves no pasan por Claude Code.");
  }
  if (/\bsupabase\b/.test(cmd) && /(\blink\b|--linked\b|--project-ref\b|--db-url\b|\bprojects\b|\bsecrets\b)/.test(cmd)) {
    block("Claude Code trabaja solo con Supabase local. Nada contra proyectos remotos.");
  }
  if (/\bgit\s+push\b/.test(cmd) && /(--force\b|-f\b|--force-with-lease\b|--mirror\b|--delete\b|\s:\S)/.test(cmd)) {
    block("no se fuerza ni se borra nada en el repositorio remoto.");
  }
  if (/\bvercel\b/.test(cmd) && /(--prod\b|\bdeploy\b|\benv\b)/.test(cmd)) {
    block("la publicación la hace solo GitHub Actions.");
  }
}
