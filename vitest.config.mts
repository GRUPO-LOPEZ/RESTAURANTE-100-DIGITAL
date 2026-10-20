import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: { "@": import.meta.dirname },
  },
  test: {
    include: ["tests/unit/**/*.test.ts", "tests/hooks/**/*.test.ts"],
    environment: "node",
  },
});
