// PreToolUse: protege secretos y ambientes remotos (prompt maestro, secciones 4 y 10).
// Es una ayuda, no la única barrera: la defensa real es que en esta máquina no haya
// claves ni tokens de staging o producción (ver .claude/rules/security.md).
import { block, readEvent, relativePath } from "./lib.mjs";

const event = readEvent();
const tool = event.tool_name ?? "";
const input = event.tool_input ?? {};

// Archivos de variables de entorno (salvo .env.example), también como "HEAD:.env".
const ENV_FILE = /(^|[\\/\s"'=:])\.env(?!\.example\b)[\w.-]*/i;
// Credenciales de herramientas que nunca se leen.
const SECRET_PATH =
  /(\.supabase[\\/]|[\\/]\.vercel[\\/]|^\.vercel[\\/]|\.config[\\/]gh[\\/]|\.npmrc\b|\.pem\b|\.netrc\b|\.git-credentials\b|id_(rsa|ed25519)\b)/i;
// Banderas que apuntan a un proyecto o base remota, en cualquier comando.
const REMOTE_FLAGS = /(--linked\b|--db-url\b|--project-ref\b|--project-id\b)/;
// Lo único que Claude Code puede hacer con la CLI de Supabase: trabajo local.
const SUPABASE_LOCAL =
  /^(--version|-v|help|--help|init|start|stop|status|db reset|db lint|test db|migration new|migration list --local|gen types typescript --local)\b/;

function checkPath(raw) {
  const rel = relativePath(event, raw);
  if (ENV_FILE.test(`/${rel}`)) {
    block(`no se leen ni editan archivos de variables de entorno (${rel}). Usá .env.example.`);
  }
  if (SECRET_PATH.test(`/${rel}`) || SECRET_PATH.test(String(raw))) {
    block(`no se leen credenciales de herramientas (${raw}).`);
  }
}

if (["Read", "Edit", "Write", "MultiEdit", "NotebookEdit"].includes(tool)) {
  checkPath(input.file_path ?? input.notebook_path ?? "");
}

if (tool === "Grep" || tool === "Glob") {
  // En Grep, "pattern" es el texto a buscar; solo se miran la ruta y el filtro de archivos.
  const target = [input.path, input.glob, tool === "Glob" ? input.pattern : ""].join(" ");
  if (ENV_FILE.test(` ${target}`) || SECRET_PATH.test(target)) {
    block("no se buscan archivos de variables de entorno ni credenciales.");
  }
}

if (tool === "Bash" || tool === "PowerShell") {
  const cmd = String(input.command ?? "");

  if (ENV_FILE.test(` ${cmd}`)) {
    block("el comando toca un archivo .env*. Las claves no pasan por Claude Code.");
  }
  if (SECRET_PATH.test(cmd)) {
    block("el comando toca credenciales de herramientas.");
  }
  if (REMOTE_FLAGS.test(cmd)) {
    block("Claude Code trabaja solo con Supabase local. Nada contra proyectos remotos.");
  }

  // Cada invocación de la CLI de Supabase tiene que ser un subcomando local.
  for (const match of cmd.matchAll(/\bsupabase(?:\.cmd)?\s+([^|;&\n]*)/g)) {
    const args = (match[1] ?? "").trim().replace(/\s+/g, " ");
    if (!SUPABASE_LOCAL.test(args)) {
      block(`"supabase ${args}" no es un comando local permitido. Ver .claude/rules/security.md.`);
    }
  }

  // Conexiones directas a bases que no son locales.
  for (const match of cmd.matchAll(/postgres(?:ql)?:\/\/[^\s"']*/g)) {
    if (!/@(127\.0\.0\.1|localhost)(:\d+)?\//.test(match[0])) {
      block("no se conecta a bases de datos remotas.");
    }
  }

  // Push forzado o destructivo, en cualquier forma (-f, -fu, --force, +refspec, :rama, git -C).
  if (/\bgit\b[^|;&\n]*\bpush\b/.test(cmd)) {
    const push = cmd.slice(cmd.search(/\bpush\b/));
    if (
      /(\s-\w*f\w*\b|--force\b|--force-with-lease\b|--mirror\b|--delete\b|--prune\b|\s\+\S|\s:\S)/.test(
        push,
      )
    ) {
      block("no se fuerza ni se borra nada en el repositorio remoto.");
    }
  }

  // Vercel: la publicación y los secretos los maneja solo GitHub Actions.
  if (/\bvercel\b/.test(cmd) && !/\bvercel\s+--version\b/.test(cmd)) {
    block("la CLI de Vercel no se usa desde Claude Code: publica solo GitHub Actions.");
  }
}
