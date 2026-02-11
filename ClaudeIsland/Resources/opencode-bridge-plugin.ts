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

  const hooks: Hooks = {
    "session.created": async context => {
      await sendToClaudeIsland(makePayload("SessionStart", { ...context, status: "starting" }), socketPath);
    },
    "session.updated": async context => {
      await sendToClaudeIsland(makePayload("SessionUpdate", { ...context, status: "processing" }), socketPath);
    },
    "session.idle": async context => {
      await sendToClaudeIsland(
        makePayload("Notification", {
          ...context,
          status: "idle",
          notificationType: "idle_prompt",
        }),
        socketPath,
      );
    },
    "session.error": async context => {
      await sendToClaudeIsland(
        makePayload("SessionError", {
          ...context,
          status: "error",
          message: context.error instanceof Error ? context.error.message : String(context.error ?? "unknown_error"),
        }),
        socketPath,
      );
    },
    "session.ended": async context => {
      await sendToClaudeIsland(makePayload("SessionEnd", { ...context, status: "ended" }), socketPath);
    },
    "tool.execute.before": async context => {
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
    "tool.execute.after": async context => {
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
    "permission.ask": async context => {
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
  };

  return {
    name: "claude-island-opencode-bridge",
    hooks,
  };
}

export default createClaudeIslandOpenCodePlugin;
