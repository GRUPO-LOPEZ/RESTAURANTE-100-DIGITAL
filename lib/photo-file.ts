import { PHOTO_MAX_BYTES, PHOTO_TYPES } from "@/lib/recipe-format";

// Control de una foto que llega al servidor (recetas y materias primas): tipo, peso y contenido real del archivo.
export type PhotoType = (typeof PHOTO_TYPES)[number];

export const PHOTO_EXTENSIONS: Record<PhotoType, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

/** El contenido real tiene que ser la imagen que dice ser (no solo el tipo que declara el navegador). */
export function matchesType(head: Uint8Array, type: PhotoType): boolean {
  const ascii = (from: number, to: number) => String.fromCharCode(...head.slice(from, to));
  if (type === "image/jpeg") return head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff;
  if (type === "image/png") return head[0] === 0x89 && ascii(1, 4) === "PNG";
  return ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP";
}

/** La foto lista para subir, o por qué no se puede. */
export async function checkPhoto(
  photo: FormDataEntryValue | null,
): Promise<{ file: File; type: PhotoType } | { error: string }> {
  if (!(photo instanceof File) || photo.size === 0) return { error: "Elegí una foto." };
  const type = PHOTO_TYPES.find((t) => t === photo.type);
  if (!type) return { error: "La foto tiene que ser JPG, PNG o WebP." };
  if (photo.size > PHOTO_MAX_BYTES) return { error: "La foto pesa más de 3 MB." };
  if (!matchesType(new Uint8Array(await photo.slice(0, 12).arrayBuffer()), type))
    return { error: "El archivo no es una imagen JPG, PNG o WebP." };
  return { file: photo, type };
}
