// Un texto que una planilla no ejecuta como fórmula: lo que empieza con =, +, - o @ lleva ' adelante.
// También las variantes de ancho completo, con espacios adelante, y lo que viene después de un separador:
// Excel en español corta por ";" al abrir un CSV, y lo de después quedaría solo en una celda.
export function safeText(value: string): string {
  const inner = value.replace(/([;,\t|]\s*)([=+\-@＝＋－＠])/g, "$1'$2");
  return /^[=+\-@\t\r\n＝＋－＠]/.test(inner.trimStart()) ? `'${inner}` : inner;
}

// Una celda de CSV.
export function csvCell(value: unknown): string {
  const text = value === null || value === undefined ? "" : String(value);
  return `"${safeText(text).replace(/"/g, '""')}"`;
}

// Un número ya formateado: el signo menos de una diferencia no es una fórmula.
export function csvNumber(value: string): string {
  return `"${value}"`;
}
