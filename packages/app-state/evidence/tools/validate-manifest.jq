def message($path; $detail): "\($path): \($detail)";
def required($value; $names; $path):
  $names[] as $name
  | select(($value | has($name)) | not)
  | message("\($path).\($name)"; "is required");
def no_extra($value; $names; $path):
  $value
  | keys_unsorted[] as $name
  | select(($names | index($name)) == null)
  | message("\($path).\($name)"; "is not allowed");
def object_shape($value; $names; $required_names; $path):
  if ($value | type) != "object" then
    message($path; "must be an object")
  else
    required($value; $required_names; $path),
    no_extra($value; $names; $path)
  end;
def nonempty_string($value): ($value | type) == "string" and ($value | length) > 0;
def matches($value; $pattern): nonempty_string($value) and ($value | test($pattern));
def utc_timestamp($value):
  matches($value; "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  and (try ($value | fromdateiso8601 | type == "number") catch false);
def enum_value($value; $allowed): ($allowed | index($value)) != null;
def integer_at_least($value; $minimum):
  ($value | type) == "number" and ($value | floor) == $value and $value >= $minimum;
def string_array($value; $pattern):
  ($value | type) == "array"
  and ($value | length) > 0
  and ([$value[] | matches(.; $pattern)] | all);

def check_errors($check; $path):
  object_shape($check; ["status", "note", "artifact_ids"]; ["status", "note", "artifact_ids"]; $path),
  if ($check | type) == "object" then
    if enum_value($check.status; ["passed", "failed"]) | not then
      message("\($path).status"; "must be passed or failed")
    else empty end,
    if nonempty_string($check.note) | not then
      message("\($path).note"; "must be a non-empty string")
    else empty end,
    if string_array($check.artifact_ids; "^[a-z0-9][a-z0-9-]*$") | not then
      message("\($path).artifact_ids"; "must be a non-empty array of artifact ids")
    elif (($check.artifact_ids | unique | length) != ($check.artifact_ids | length)) then
      message("\($path).artifact_ids"; "must not contain duplicates")
    else empty end
  else empty end;

def artifact_errors($artifact; $index):
  ("$.artifacts[\($index)]") as $path
  | object_shape(
      $artifact;
      ["id", "kind", "path", "media_type", "sha256", "bytes", "captured_at", "description"];
      ["id", "kind", "path", "media_type", "sha256", "bytes", "captured_at", "description"];
      $path
    ),
    if ($artifact | type) == "object" then
      if matches($artifact.id; "^[a-z0-9][a-z0-9-]*$") | not then
        message("\($path).id"; "must be a kebab-case id")
      else empty end,
      if enum_value($artifact.kind; ["screenshot", "video", "log", "report", "export"]) | not then
        message("\($path).kind"; "must be screenshot, video, log, report, or export")
      else empty end,
      if matches($artifact.path; "^[A-Za-z0-9._/-]+$") | not then
        message("\($path).path"; "must be a safe repository-relative path")
      elif ($artifact.path | startswith("/")) or ($artifact.path | test("(^|/)\\.\\.(/|$)")) then
        message("\($path).path"; "must not be absolute or contain '..'")
      elif ($artifact.path | startswith("packages/app-state/evidence/") | not) then
        message("\($path).path"; "must be retained under packages/app-state/evidence")
      else empty end,
      if matches($artifact.media_type; "^[a-z0-9.+-]+/[A-Za-z0-9.+-]+$") | not then
        message("\($path).media_type"; "must be a media type")
      else empty end,
      if matches($artifact.sha256; "^[0-9a-f]{64}$") | not then
        message("\($path).sha256"; "must be a lowercase SHA-256 digest")
      else empty end,
      if integer_at_least($artifact.bytes; 1) | not then
        message("\($path).bytes"; "must be a positive integer")
      else empty end,
      if utc_timestamp($artifact.captured_at) | not then
        message("\($path).captured_at"; "must be an RFC 3339 UTC timestamp")
      else empty end,
      if nonempty_string($artifact.description) | not then
        message("\($path).description"; "must be a non-empty string")
      else empty end
    else empty end;

[
  object_shape(
    .;
    ["$schema", "schema_version", "recipe", "environment", "application", "procedure", "run", "result", "artifacts"];
    ["$schema", "schema_version", "recipe", "environment", "application", "procedure", "run", "result", "artifacts"];
    "$"
  ),
  if type == "object" then
    if .["$schema"] != "https://raw.githubusercontent.com/lucamaraschi/nix-me/main/packages/app-state/evidence/t3-evidence-manifest.schema.json" then
      message("$.$schema"; "must identify the versioned T3 evidence schema")
    else empty end,
    if .schema_version != 1 then message("$.schema_version"; "must equal 1") else empty end,

    object_shape(.recipe; ["id", "path", "sha256"]; ["id", "path", "sha256"]; "$.recipe"),
    if (.recipe | type) == "object" then
      if matches(.recipe.id; "^[a-z0-9][a-z0-9-]*$") | not then
        message("$.recipe.id"; "must be a kebab-case recipe id")
      else empty end,
      if matches(.recipe.path; "^[A-Za-z0-9._/-]+$") | not then
        message("$.recipe.path"; "must be a safe repository-relative path")
      elif (.recipe.path | startswith("/")) or (.recipe.path | test("(^|/)\\.\\.(/|$)")) then
        message("$.recipe.path"; "must not be absolute or contain '..'")
      else empty end,
      if matches(.recipe.sha256; "^[0-9a-f]{64}$") | not then
        message("$.recipe.sha256"; "must be a lowercase SHA-256 digest")
      else empty end
    else empty end,

    object_shape(.environment; ["kind", "identifier", "macos", "architecture"]; ["kind", "identifier", "macos", "architecture"]; "$.environment"),
    if (.environment | type) == "object" then
      if enum_value(.environment.kind; ["disposable_vm", "dedicated_host"]) | not then
        message("$.environment.kind"; "must be disposable_vm or dedicated_host")
      else empty end,
      if nonempty_string(.environment.identifier) | not then
        message("$.environment.identifier"; "must be a non-empty string")
      else empty end,
      if enum_value(.environment.architecture; ["arm64", "x86_64"]) | not then
        message("$.environment.architecture"; "must be arm64 or x86_64")
      else empty end,
      object_shape(.environment.macos; ["version", "build"]; ["version", "build"]; "$.environment.macos"),
      if (.environment.macos | type) == "object" then
        if matches(.environment.macos.version; "^[0-9]+([.][0-9]+){1,2}$") | not then
          message("$.environment.macos.version"; "must be a dotted macOS version")
        else empty end,
        if matches(.environment.macos.build; "^[A-Za-z0-9.-]+$") | not then
          message("$.environment.macos.build"; "must be a macOS build identifier")
        else empty end
      else empty end
    else empty end,

    object_shape(.application; ["bundle_id", "version", "build"]; ["bundle_id", "version", "build"]; "$.application"),
    if (.application | type) == "object" then
      if matches(.application.bundle_id; "^[A-Za-z0-9.-]+$") | not then
        message("$.application.bundle_id"; "must be a bundle identifier")
      else empty end,
      if nonempty_string(.application.version) | not then
        message("$.application.version"; "must be a non-empty string")
      else empty end,
      if nonempty_string(.application.build) | not then
        message("$.application.build"; "must be a non-empty string")
      else empty end
    else empty end,

    object_shape(.procedure; ["id", "version", "harness_revision"]; ["id", "version", "harness_revision"]; "$.procedure"),
    if (.procedure | type) == "object" then
      if matches(.procedure.id; "^[a-z0-9][a-z0-9-]*$") | not then
        message("$.procedure.id"; "must be a kebab-case procedure id")
      else empty end,
      if integer_at_least(.procedure.version; 1) | not then
        message("$.procedure.version"; "must be a positive integer")
      else empty end,
      if matches(.procedure.harness_revision; "^[0-9a-f]{40}$") | not then
        message("$.procedure.harness_revision"; "must be a full lowercase Git commit")
      else empty end
    else empty end,

    object_shape(.run; ["id", "started_at", "finished_at"]; ["id", "started_at", "finished_at"]; "$.run"),
    if (.run | type) == "object" then
      if matches(.run.id; "^[A-Za-z0-9][A-Za-z0-9._-]*$") | not then
        message("$.run.id"; "must be a stable run id")
      else empty end,
      if utc_timestamp(.run.started_at) | not then
        message("$.run.started_at"; "must be an RFC 3339 UTC timestamp")
      else empty end,
      if utc_timestamp(.run.finished_at) | not then
        message("$.run.finished_at"; "must be an RFC 3339 UTC timestamp")
      elif (.run.started_at | type) == "string" and .run.finished_at < .run.started_at then
        message("$.run.finished_at"; "must not precede started_at")
      else empty end
    else empty end,

    object_shape(.result; ["status", "summary", "checks"]; ["status", "summary", "checks"]; "$.result"),
    if (.result | type) == "object" then
      if enum_value(.result.status; ["passed", "failed"]) | not then
        message("$.result.status"; "must be passed or failed")
      else empty end,
      if nonempty_string(.result.summary) | not then
        message("$.result.summary"; "must be a non-empty string")
      else empty end,
      object_shape(.result.checks; ["apply", "visible_behavior", "idempotence"]; ["apply", "visible_behavior", "idempotence"]; "$.result.checks"),
      if (.result.checks | type) == "object" then
        check_errors(.result.checks.apply; "$.result.checks.apply"),
        check_errors(.result.checks.visible_behavior; "$.result.checks.visible_behavior"),
        check_errors(.result.checks.idempotence; "$.result.checks.idempotence")
      else empty end
    else empty end,

    if (.artifacts | type) != "array" or (.artifacts | length) == 0 then
      message("$.artifacts"; "must be a non-empty array")
    else
      (.artifacts | to_entries[] | artifact_errors(.value; .key)),
      if ([.artifacts[].id] | unique | length) != (.artifacts | length) then
        message("$.artifacts"; "artifact ids must be unique")
      else empty end
    end
  else empty end
]
