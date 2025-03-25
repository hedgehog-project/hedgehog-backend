import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  out: './db/migrations',
  schema: './db/schema/index.ts',
  dialect: 'sqlite',
  dbCredentials: {
    url: "./local-store/sqlite/sqlite.db",
  }
});