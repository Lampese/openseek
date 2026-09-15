// Generated from client_source.md by moon dev_build. DO NOT EDIT.

///|
fn client_source() -> String {
  (
    #|///|
    #|enum PtcTools {
    #|  Host
    #|}
    #|
    #|///|
    #|let tools : PtcTools = Host
    #|
    #|///|
    #|struct PtcResult {
    #|  content : String
    #|  is_error : Bool
    #|  data : Json?
    #|}
    #|
    #|///|
    #|suberror PtcTransportError { PtcTransportError(String) }
    #|
    #|///|
    #|async fn PtcTools::call(_self : PtcTools, name : String, arguments : Json) -> PtcResult {
    #|  guard @ptc_env.get_env_var("OPENSEEK_PTC") is Some(raw) else {
    #|    raise PtcTransportError("No PTC host. Run with mbtx(ptc=true).")
    #|  }
    #|  guard @ptc_json.parse(raw) is { "version": 1, "url": String(url), "token": String(token), .. } else {
    #|    raise PtcTransportError("Invalid PTC host handoff")
    #|  }
    #|  let request : Json = { "version": 1, "name": name, "arguments": arguments }
    #|  // No retries: a lost response does not prove an edit failed to execute.
    #|  let result = try @ptc_async.with_timeout(125000, () => {
    #|    let (response, body) = @ptc_http.post(url, request, headers={ "Authorization": "Bearer \{token}" })
    #|    guard response.code == 200 else {
    #|      raise PtcTransportError("PTC transport failed (HTTP \{response.code}); execution outcome may be unknown")
    #|    }
    #|    body.json()
    #|  }) catch {
    #|    error if @ptc_async.is_being_cancelled() || @ptc_async.is_cancellation_error(error) => raise error
    #|    PtcTransportError(message) => raise PtcTransportError(message)
    #|    _ => raise PtcTransportError("PTC connection failed, timed out, or returned invalid JSON; execution outcome may be unknown")
    #|  }
    #|  guard result is { "version": 1, "content": String(content), "is_error": is_error_json, .. } else {
    #|    raise PtcTransportError("Invalid PTC response; execution outcome may be unknown")
    #|  }
    #|  let is_error = match is_error_json { True => true; False => false; _ => raise PtcTransportError("Invalid PTC error flag") }
    #|  let data = match result { { "data": data, .. } => Some(data); _ => None }
    #|  { content, is_error, data }
    #|}
    #|
    #|///|
    #|async fn PtcTools::edit(
    #|  self : PtcTools,
    #|  path~ : String,
    #|  old_string~ : String,
    #|  new_string~ : String,
    #|  start_line~ : Int,
    #|  end_line? : Int,
    #|  revert_on_parse_errors? : Bool = true,
    #|) -> PtcResult {
    #|  let fields : Map[String, Json] = {
    #|    "path": path.to_json(),
    #|    "old_string": old_string.to_json(),
    #|    "new_string": new_string.to_json(),
    #|    "start_line": start_line.to_json(),
    #|    "revert_on_parse_errors": revert_on_parse_errors.to_json(),
    #|  }
    #|  if end_line is Some(line) { fields["end_line"] = line.to_json() }
    #|  self.call("edit", Json::object(fields))
    #|}
    #|
    #|///|
    #|async fn PtcTools::multi_edit(
    #|  self : PtcTools,
    #|  edits : Array[Json],
    #|  revert_when_errors_above? : Int,
    #|  revert_on_parse_errors? : Bool = true,
    #|) -> PtcResult {
    #|  let fields : Map[String, Json] = {
    #|    "edits": edits.to_json(),
    #|    "revert_on_parse_errors": revert_on_parse_errors.to_json(),
    #|  }
    #|  if revert_when_errors_above is Some(limit) { fields["revert_when_errors_above"] = limit.to_json() }
    #|  self.call("multi_edit", Json::object(fields))
    #|}
    #|
    #|///|
    #|async fn PtcTools::web_search(self : PtcTools, query : String) -> PtcResult {
    #|  self.call("web_search", { "query": query })
    #|}
    #|
  )
}
