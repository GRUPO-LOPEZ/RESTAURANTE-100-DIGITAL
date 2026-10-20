import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    rules: {
      // Prompt maestro, sección 3: TypeScript strict, sin any.
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/ban-ts-comment": "error",
    },
  },
  {
    // Sección 7: ningún componente usa colores sueltos fuera de la paleta de app/globals.css.
    files: ["app/**/*.tsx", "components/**/*.tsx"],
    rules: {
      "no-restricted-syntax": [
        "error",
        {
          selector: "Literal[value=/#[0-9a-fA-F]{3,8}\\b|rgba?\\(|hsla?\\(|oklch\\(/]",
          message: "Usá los tokens de color de app/globals.css, no colores sueltos.",
        },
      ],
    },
  },
  {
    // El viewport necesita el color del fondo como texto para el navegador.
    files: ["app/layout.tsx"],
    rules: { "no-restricted-syntax": "off" },
  },
  globalIgnores([".next/**", "out/**", "build/**", "next-env.d.ts", "lib/database.types.ts"]),
]);

export default eslintConfig;
