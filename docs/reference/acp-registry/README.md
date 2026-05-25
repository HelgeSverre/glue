# ACP registry prep

This directory holds the local artifacts needed to prepare Glue's ACP registry PR without publishing anything from this repository.

## Files

- `icon.svg` — 16×16 monochrome icon for `agentclientprotocol/registry/glue/icon.svg`
- `../../agent.json` — source manifest to copy to `agentclientprotocol/registry/glue/agent.json`

## Dry-run checklist

1. Verify the pinned release assets exist:

   ```sh
   gh release view v0.6.0 --repo HelgeSverre/glue --json assets --jq '.assets[].name'
   ```

2. Validate the local manifest against the registry schema:

   ```sh
   curl -sS https://raw.githubusercontent.com/agentclientprotocol/registry/main/agent.schema.json -o /tmp/acp-agent.schema.json
   uv run --with jsonschema python -c "import json, jsonschema; schema=json.load(open('/tmp/acp-agent.schema.json')); agent=json.load(open('agent.json')); jsonschema.Draft7Validator.check_schema(schema); jsonschema.validate(agent, schema); print('agent.json validates')"
   ```

3. In a checkout of `agentclientprotocol/registry`, copy the files:

   ```sh
   mkdir -p glue
   cp /Users/helge/code/glue/agent.json glue/agent.json
   cp /Users/helge/code/glue/docs/reference/acp-registry/icon.svg glue/icon.svg
   ```

4. Run the registry repo's validation command there before opening a PR.

## Notes

- Keep `agent.json` pinned to a real versioned release URL.
- Do not advertise MCP, `session/list`, or draft transports until Glue actually supports them through ACP.
