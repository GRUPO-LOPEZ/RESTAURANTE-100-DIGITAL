// Fotos que se suben desde el navegador (recetas y recepción): se achican antes de subir, sin dependencias nuevas, para
// que pesen poco en el celular y entren en el tope de la acción de servidor (4 MB) y del bucket.

// Lado más largo de la foto que se sube: suficiente para leer un remito o ver un plato, liviana para el celular.
export const PHOTO_MAX_SIDE = 1600;

// El tamaño de una foto achicada: el lado más largo hasta max, sin agrandar.
export function fitSize(
  width: number,
  height: number,
  max: number = PHOTO_MAX_SIDE,
): { width: number; height: number } {
  const scale = Math.min(1, max / Math.max(width, height));
  return { width: Math.round(width * scale), height: Math.round(height * scale) };
}

// Achica la foto en el navegador y la pasa a JPEG. Solo en el navegador (usa canvas).
export async function shrinkPhoto(file: File, max: number = PHOTO_MAX_SIDE): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const size = fitSize(bitmap.width, bitmap.height, max);
  const canvas = document.createElement("canvas");
  canvas.width = size.width;
  canvas.height = size.height;
  // Sin contexto (celular con poca memoria y foto enorme) no se sube una imagen en blanco.
  const context = canvas.getContext("2d");
  if (!context) throw new Error("foto");
  context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  return new Promise((resolve, reject) =>
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("foto"))), "image/jpeg", 0.82),
  );
}
