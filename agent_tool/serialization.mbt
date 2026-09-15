///|
/// Serialize a complete file operation, including its checks and rollback.
/// Never hold this gate while waiting for a program that may call file tools.
pub async fn[T] FileStateMap::with_access(
  self : FileStateMap,
  operation : async () -> T,
) -> T {
  self.lock.acquire()
  defer self.lock.release()
  operation()
}

///|
/// Bind a definition to the session's shared file-operation gate. Both direct
/// and programmatic dispatch must use this same wrapped definition.
pub fn FileStateMap::serialize(
  self : FileStateMap,
  definition : AgentToolDefinition,
) -> AgentToolDefinition {
  {
    ..definition,
    execute: Async(arguments => {
      self.with_access(() => definition.execute.run(arguments))
    }),
  }
}

///|
/// Registered tools explicitly available to a program. Executors and their
/// captured session state are retained, rather than rebuilt for the client.
pub fn Tools::program_tools(self : Tools) -> Tools raise {
  Tools(
    [
      for tool in self.by_name.values() if tool.is_program_callable() => tool
    ],
  )
}
