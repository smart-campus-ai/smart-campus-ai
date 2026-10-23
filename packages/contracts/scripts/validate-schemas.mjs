// Compiles every shared JSON Schema and resolves all cross-file $ref.
// Fails (exit 1) on any malformed schema or unresolved reference, so the
// contract cannot be merged with a broken schema. No network, no cache.
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const here = dirname(fileURLToPath(import.meta.url));
const schemasDir = join(here, "..", "schemas");

const files = readdirSync(schemasDir).filter((f) => f.endsWith(".json"));
if (files.length === 0) {
  console.error("validate-schemas: no schema files found in schemas/");
  process.exit(1);
}

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);

// Register every schema under its $id so cross-file $ref (e.g. "common.json#/$defs/Id") resolve.
const schemas = [];
for (const file of files) {
  const schema = JSON.parse(readFileSync(join(schemasDir, file), "utf8"));
  if (!schema.$id) {
    console.error(`validate-schemas: ${file} is missing a top-level $id`);
    process.exit(1);
  }
  ajv.addSchema(schema);
  schemas.push({ file, schema });
}

// Compile every $def through a ref wrapper: this forces Ajv to resolve all
// references reachable from each definition.
let compiled = 0;
let failed = 0;
for (const { file, schema } of schemas) {
  for (const def of Object.keys(schema.$defs ?? {})) {
    const ref = `${schema.$id}#/$defs/${def}`;
    try {
      ajv.compile({ $ref: ref });
      compiled += 1;
    } catch (err) {
      failed += 1;
      console.error(`FAIL  ${file} -> ${def}: ${err.message}`);
    }
  }
}

if (failed > 0) {
  console.error(`validate-schemas: ${failed} definition(s) failed to compile`);
  process.exit(1);
}

console.log(`validate-schemas: ${compiled} definition(s) compiled, all cross-file $ref resolved`);
