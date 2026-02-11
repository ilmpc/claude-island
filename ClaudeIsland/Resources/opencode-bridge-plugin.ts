import { createConnection } from "node:net";
import type { Hooks, Plugin } from "@opencode-ai/plugin";

type PermissionDecision = "allow" | "deny" | "ask";

type BridgePayload = {
  schemaVersion: "1.0";
  provider: "opencode";
  session_id: string;
  cwd: string;
  event: string;
  status: string;
  pid?: number;
  tty?: string;
  tool?: string;
  tool_input?: Record<string, unknown>;
  tool_use_id?: string;
  message?: string;
  notification_type?: string;
};

type BridgeOptions = {
  socketPath?: string;
};

const DEFAULT_SOCKET_PATH = "/tmp/claude-island.sock";

const HOOK_EVENT_NAMES = {
  sessionCreated: {
    expected: "session.created",
    aliases: ["sessionCreated"],
  },
  sessionUpdated: {
    expected: "session.updated",
    aliases: ["sessionUpdated"],
  },
  sessionIdle: {
    expected: "session.idle",
    aliases: ["sessionIdle"],
  },
  sessionError: {
    expected: "session.error",
    aliases: ["sessionError"],
  },
  sessionEnded: {
    expected: "session.ended",
    aliases: ["sessionEnded"],
  },
  toolExecuteBefore: {
    expected: "tool.execute.before",
    aliases: ["toolExecuteBefore"],
  },
  toolExecuteAfter: {
    expected: "tool.execute.after",
    aliases: ["toolExecuteAfter"],
  },
  permissionAsk: {
    expected: "permission.ask",
    aliases: ["permissionAsk"],
  },
} as const;

type HookEventConfig = (typeof HOOK_EVENT_NAMES)[keyof typeof HOOK_EVENT_NAMES];

function sendWithNodeSocket(
  payload: BridgePayload,
  socketPath: string,
  waitForResponse: boolean,
): Promise<PermissionDecision | void> {
  return new Promise((resolve, reject) => {
    const client = createConnection({ path: socketPath });
    let response = "";

    client.on("connect", () => {
      client.write(JSON.stringify(payload));
      if (!waitForResponse) {
        client.end();
      }
    });

    client.on("data", chunk => {
      response += chunk.toString("utf8");
    });

    client.on("end", () => {
      if (!waitForResponse) {
        resolve();
        return;
      }

      try {
        const parsed = JSON.parse(response) as { decision?: PermissionDecision };
        resolve(parsed.decision ?? "ask");
      } catch {
        resolve("ask");
      }
    });

    client.on("error", reject);
  });
}

async function sendToClaudeIsland(
  payload: BridgePayload,
  socketPath: string,
  waitForResponse = false,
): Promise<PermissionDecision | void> {
  if (typeof Bun !== "undefined" && typeof Bun.connect === "function") {
    // Bun supports Node's net module, but this branch keeps a Bun-native path available.
    try {
      return await new Promise((resolve, reject) => {
        let response = "";
        Bun.connect({
          unix: socketPath,
          socket: {
            open(socket) {
              socket.write(JSON.stringify(payload));
              if (!waitForResponse) {
                socket.end();
              }
            },
            data(_socket, data) {
              response += data.toString();
            },
            close() {
              if (!waitForResponse) {
                resolve();
                return;
              }

              try {
                const parsed = JSON.parse(response) as { decision?: PermissionDecision };
                resolve(parsed.decision ?? "ask");
              } catch {
                resolve("ask");
              }
            },
            error(_socket, error) {
              reject(error);
            },
          },
        });
      });
    } catch {
      // Fall through to Node net implementation as a portable fallback.
    }
  }

  return sendWithNodeSocket(payload, socketPath, waitForResponse);
}

function makePayload(
  event: string,
  context: {
    sessionID: string;
    cwd: string;
    status: string;
    pid?: number;
    tty?: string;
    tool?: string;
    toolInput?: Record<string, unknown>;
    callID?: string;
    message?: string;
    notificationType?: string;
  },
): BridgePayload {
  return {
    schemaVersion: "1.0",
    provider: "opencode",
    session_id: context.sessionID,
    cwd: context.cwd,
    event,
    status: context.status,
    pid: context.pid,
    tty: context.tty,
    tool: context.tool,
    tool_input: context.toolInput,
    tool_use_id: context.callID,
    message: context.message,
    notification_type: context.notificationType,
  };
}

export function createClaudeIslandOpenCodePlugin(options: BridgeOptions = {}): Plugin {
  const socketPath = options.socketPath ?? DEFAULT_SOCKET_PATH;

  const hooks: Hooks = {};
  const runtimeBindingDiagnostics: string[] = [];

  const registerHookVariants = <TContext>(
    eventConfig: HookEventConfig,
    handler: (context: TContext) => Promise<unknown>,
    options: { returnsDecision?: boolean } = {},
  ): void => {
    const eventNames = [eventConfig.expected, ...eventConfig.aliases];

    for (const eventName of eventNames) {
      hooks[eventName] = async context => {
        const isAlias = eventName !== eventConfig.expected;

        if (isAlias) {
          const deprecationMessage = `[claude-island-opencode-bridge] Hook alias '${eventName}' is deprecated and will be removed in the next release. Prefer '${eventConfig.expected}'.`;
          runtimeBindingDiagnostics.push(`alias:${eventName}`);
          console.warn(deprecationMessage);
          await sendToClaudeIsland(
            makePayload("Notification", {
              sessionID: (context as { sessionID?: string }).sessionID ?? "opencode-plugin",
              cwd: (context as { cwd?: string }).cwd ?? process.cwd(),
              status: "bridge_warning",
              message: deprecationMessage,
              notificationType: "bridge_deprecation",
            }),
            socketPath,
          );
        }

        const safeContext = context as TContext | undefined;
        if (!safeContext) {
          runtimeBindingDiagnostics.push(`noop:${eventName}`);
          return options.returnsDecision ? { decision: "ask" as const } : undefined;
        }

        return handler(safeContext);
      };
    }

    runtimeBindingDiagnostics.push(`bound:${eventConfig.expected}`);
  };

  registerHookVariants<{ sessionID: string; cwd: string; pid?: number; tty?: string }>(
    HOOK_EVENT_NAMES.sessionCreated,
    async context => {
      await sendToClaudeIsland(makePayload("SessionStart", { ...context, status: "starting" }), socketPath);
    },
  );

  registerHookVariants<{ sessionID: string; cwd: string; pid?: number; tty?: string }>(
    HOOK_EVENT_NAMES.sessionUpdated,
    async context => {
      await sendToClaudeIsland(makePayload("SessionUpdate", { ...context, status: "processing" }), socketPath);
    },
  );

  registerHookVariants<{ sessionID: string; cwd: string; pid?: number; tty?: string }>(
    HOOK_EVENT_NAMES.sessionIdle,
    async context => {
      await sendToClaudeIsland(
        makePayload("Notification", {
          ...context,
          status: "idle",
          notificationType: "idle_prompt",
        }),
        socketPath,
      );
    },
  );

  registerHookVariants<{ sessionID: string; cwd: string; error?: unknown; pid?: number; tty?: string }>(
    HOOK_EVENT_NAMES.sessionError,
    async context => {
      await sendToClaudeIsland(
        makePayload("SessionError", {
          ...context,
          status: "error",
          message: context.error instanceof Error ? context.error.message : String(context.error ?? "unknown_error"),
        }),
        socketPath,
      );
    },
  );

  registerHookVariants<{ sessionID: string; cwd: string; pid?: number; tty?: string }>(
    HOOK_EVENT_NAMES.sessionEnded,
    async context => {
      await sendToClaudeIsland(makePayload("SessionEnd", { ...context, status: "ended" }), socketPath);
    },
  );

  registerHookVariants<{ sessionID: string; cwd: string; tool: string; input?: unknown; callID?: string }>(
    HOOK_EVENT_NAMES.toolExecuteBefore,
    async context => {
      await sendToClaudeIsland(
        makePayload("PreToolUse", {
          ...context,
          status: "running_tool",
          tool: context.tool,
          toolInput: context.input as Record<string, unknown>,
          callID: context.callID,
        }),
        socketPath,
      );
    },
  );

  registerHookVariants<{ sessionID: string; cwd: string; tool: string; input?: unknown; callID?: string; error?: unknown }>(
    HOOK_EVENT_NAMES.toolExecuteAfter,
    async context => {
      await sendToClaudeIsland(
        makePayload("PostToolUse", {
          ...context,
          status: context.error ? "error" : "idle",
          tool: context.tool,
          toolInput: context.input as Record<string, unknown>,
          callID: context.callID,
          message: context.error ? String(context.error) : undefined,
        }),
        socketPath,
      );
    },
  );

  registerHookVariants<{ sessionID: string; cwd: string; tool: string; input?: unknown; callID?: string }>(
    HOOK_EVENT_NAMES.permissionAsk,
    async context => {
      const decision = await sendToClaudeIsland(
        makePayload("PermissionRequest", {
          ...context,
          status: "waiting_for_approval",
          tool: context.tool,
          toolInput: context.input as Record<string, unknown>,
          callID: context.callID,
        }),
        socketPath,
        true,
      );

      if (decision === "allow") {
        return { decision: "allow" as const };
      }

      if (decision === "deny") {
        return { decision: "deny" as const, reason: "Denied in Claude Island" };
      }

      return { decision: "ask" as const };
    },
    { returnsDecision: true },
  );

  const startupMessage = `Bridge hook bindings ready: ${runtimeBindingDiagnostics.join(", ")}`;
  console.info(`[claude-island-opencode-bridge] ${startupMessage}`);
  void sendToClaudeIsland(
    makePayload("Notification", {
      sessionID: "opencode-plugin",
      cwd: process.cwd(),
      status: "bridge_ready",
      message: startupMessage,
      notificationType: "bridge_startup",
    }),
    socketPath,
  );

  return {
    name: "claude-island-opencode-bridge",
    hooks,
  };
}

export default createClaudeIslandOpenCodePlugin;
