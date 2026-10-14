def nonempty: type == "string" and length > 0;
def kebab: nonempty and test("^[a-z0-9][a-z0-9-]*$");
def safe_path:
  nonempty
  and test("^[A-Za-z0-9._/-]+$")
  and (startswith("/") | not)
  and (test("(^|/)\\.\\.(/|$)") | not);
def string_list: type == "array" and length > 0 and all(.[]; nonempty);
def exit_codes:
  type == "array"
  and length > 0
  and (length == (unique | length))
  and all(.[]; type == "number" and floor == . and . >= 0 and . <= 255);
def action_ops:
  type == "array"
  and (length == (unique | length))
  and all(.[]; nonempty and test("^[a-z_]+$"));
def command_check($mode):
  type == "object"
  and (keys | sort) == (["accepted_exit_codes", "mode", "required_action_ops"] | sort)
  and .mode == $mode
  and (.accepted_exit_codes | exit_codes)
  and (.required_action_ops | action_ops);
def media_types:
  type == "array"
  and length > 0
  and (length == (unique | length))
  and all(.[]; IN("image/png", "image/jpeg", "video/quicktime", "video/mp4"));

[
  if type != "object" then "$: must be an object" else empty end,
  if .["$schema"] != "https://raw.githubusercontent.com/lucamaraschi/nix-me/main/packages/app-state/evidence/procedures/t3-procedure.schema.json"
    then "$.$schema: must identify the versioned T3 procedure schema" else empty end,
  if .schema_version != 1 then "$.schema_version: must equal 1" else empty end,
  if (.id | kebab | not) then "$.id: must be a kebab-case id" else empty end,
  if (.version | type != "number") or (.version | floor != .) or .version < 1
    then "$.version: must be a positive integer" else empty end,
  if (.title | nonempty | not) then "$.title: must be a non-empty string" else empty end,
  if (.recipe.id | kebab | not) then "$.recipe.id: must be a kebab-case id" else empty end,
  if (.recipe.path | safe_path | not) then "$.recipe.path: must be a safe repository path" else empty end,
  if (.recipe.values_path | safe_path | not) then "$.recipe.values_path: must be a safe repository path" else empty end,
  if (.recipe.bundle_id | nonempty | not) then "$.recipe.bundle_id: must be non-empty" else empty end,
  if (.recipe.app_path | test("^/Applications/[A-Za-z0-9 ._-]+[.]app$") | not)
    then "$.recipe.app_path: must identify an application under /Applications" else empty end,
  if .environment.kind != "disposable_vm" then "$.environment.kind: must be disposable_vm" else empty end,
  if (.execution.apply | command_check("apply") | not) then "$.execution.apply: invalid apply check" else empty end,
  if (.execution.idempotence | command_check("diff") | not) then "$.execution.idempotence: invalid diff check" else empty end,
  if (.operator.instructions | string_list | not) then "$.operator.instructions: must be a non-empty string array" else empty end,
  if (.operator.acceptance | string_list | not) then "$.operator.acceptance: must be a non-empty string array" else empty end,
  if .operator.artifact.required != true then "$.operator.artifact.required: must be true" else empty end,
  if (.operator.artifact.allowed_media_types | media_types | not)
    then "$.operator.artifact.allowed_media_types: contains an unsupported media type" else empty end,
  if (.operator.artifact.description | nonempty | not) then "$.operator.artifact.description: must be non-empty" else empty end,
  if (.cleanup | string_list | not) then "$.cleanup: must be a non-empty string array" else empty end
]
