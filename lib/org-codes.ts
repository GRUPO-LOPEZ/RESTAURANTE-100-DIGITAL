// Cómo se arman los códigos de marca y de local y el nombre del local (ADR-0061). La misma regla está en la base
// (org.code_word, org.brand_code, org.restaurant_code y org.restaurant_name): la pantalla la usa para la vista previa
// mientras se escribe, y la base es la que decide al guardar.

const ACCENTS: Record<string, string> = {
  Á: "A",
  À: "A",
  Ä: "A",
  Â: "A",
  É: "E",
  È: "E",
  Ë: "E",
  Ê: "E",
  Í: "I",
  Ì: "I",
  Ï: "I",
  Î: "I",
  Ó: "O",
  Ò: "O",
  Ö: "O",
  Ô: "O",
  Ú: "U",
  Ù: "U",
  Ü: "U",
  Û: "U",
  Ñ: "N",
  Ç: "C",
};

/** La palabra de un código: mayúsculas, sin tildes, solo letras y números, hasta 16 (Ragú → RAGU). */
export function codeWord(text: string): string {
  return text
    .trim()
    .toUpperCase()
    .replace(/[ÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇ]/g, (c) => ACCENTS[c] ?? c)
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 16);
}

/** El código de una marca: número de dos cifras y palabra (02-PADELLA). */
export function brandCode(number: number, word: string): string {
  return `${String(number).padStart(2, "0")}-${codeWord(word)}`;
}

/** El código de un local: la palabra del código de su marca (sin el número) y el número de tres cifras. */
export function restaurantCode(brandCodeText: string, number: number): string {
  return `${brandCodeText.replace(/^[0-9]{2}-/, "")}-${String(number).padStart(3, "0")}`;
}

/** El nombre de un local: el nombre corto de la marca y la zona (Ragú Leloir). */
export function restaurantName(shortName: string, zone: string): string {
  return `${shortName.trim()} ${zone.trim()}`;
}
