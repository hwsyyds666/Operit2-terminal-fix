import { manageSessions } from "./sessions";

type SuperAdminParams = Record<string, unknown>;

type TerminalParams = SuperAdminParams & {
    command?: string;
    profileId?: string;
    channel?: "container" | "device";
    interpreter?: "shell" | "bash";
    action?: "run" | "wait" | "input" | "screen" | "cancel" | "info";
    sessionId?: string;
    input?: string;
    control?: string;
    timeoutMs?: number;
};

type TerminalSessionParams = SuperAdminParams & {
    sessionId: string;
};

type PersistedTerminalOutput = {
    command: string;
    output: string;
    exitCode: unknown;
    sessionId: unknown;
    timedOut: boolean;
    context_preserved: boolean;
    output_saved_to: string;
    output_chars: number;
    operit_clean_on_exit_dir: string;
    hint: string;
    platform: string;
    terminal: string;
    terminalType: string;
    terminalEnvironment?: unknown;
    timeoutMsUsed?: number;
};

/* METADATA
{
  "api_version": "2.0.0",
  "name": "super_admin",
  "display_name": {
    "zh": "超级管理员",
    "en": "Super Admin"
  },
  "description": {
    "zh": "提供终端命令和会话控制。每次获取会话必须进入当前文件目录 `.`：已绑定的主工作区，或未绑定时这组父子对话固定的产出目录；进入失败则终止，不在主目录继续执行。附件和产出直接使用提供的相对路径，无需翻根目录、主目录或全盘查找。跨挂载访问时，终端使用 Host 解析的路径，不直接套用 VFS 绝对路径。请按实际权限操作。",
    "en": "Runs terminal commands and manages sessions. Each session acquisition must enter the current file directory `.`: the bound primary workspace, or the conversation family's persistent output area when unbound. Failure stops execution instead of continuing in the home directory. Use supplied relative attachment and output paths directly without root/home scans or global searches. For other mounts, use the Host-resolved terminal path instead of a VFS absolute path. Respect actual permissions."
  },
  "enabledByDefault": true,
  "category": "System",
  "tools": [
    {
      "name": "terminal",
      "display": {
        "label": {
          "zh": "运行终端命令",
          "en": "Run terminal command"
        },
        "icon": "terminal",
        "targetParameter": "command"
      },
      "description": {
        "zh": "常规项目命令用 container，Android 系统操作或用户明确指定的真机命令用 device。同一任务涉及两边时，按当前步骤选择。使用 action=wait、input、screen 或 cancel 操作原会话。",
        "en": "Use container for ordinary project commands and device for Android system operations or commands explicitly requested on the phone. When a task uses both, choose the channel for the current step. Use action=wait, input, screen or cancel to control the original session."
      },
      "parameters": [
        {
          "name": "command",
          "description": {
            "zh": "与所选终端语法匹配的命令",
            "en": "Command matching the selected terminal syntax."
          },
          "type": "string",
          "required": false
        },
        {
          "name": "profileId",
          "description": {
            "zh": "list_terminals 返回的配置 ID；省略使用默认配置。",
            "en": "Profile ID from list_terminals; omission uses the default."
          },
          "type": "string",
          "required": false
        },
        {
          "name": "channel",
          "description": {
            "zh": "Android 上的执行通道：container 或 device；省略时按 container 处理。",
            "en": "Android execution channel: container or device. Omission defaults to container."
          },
          "type": "string",
          "required": false
        },
        {
          "name": "interpreter",
          "description": {
            "zh": "仅 device 通道使用：shell 或 bash；省略使用 shell。",
            "en": "For device only: shell or bash. Omission uses shell."
          },
          "type": "string",
          "required": false
        },
        {
          "name": "action",
          "description": {
            "zh": "run 执行新命令；wait、input、screen、cancel 操作 sessionId；info 查询当前终端。默认 run。",
            "en": "run starts a command; wait, input, screen and cancel operate on sessionId; info reports terminal details. Defaults to run."
          },
          "type": "string",
          "required": false
        },
        {
          "name": "sessionId",
          "description": {
            "zh": "wait、input、screen、cancel 操作的原终端会话 ID。",
            "en": "Existing terminal session ID for wait, input, screen or cancel."
          },
          "type": "string",
          "required": false
        },
        {
          "name": "input",
          "description": {
            "zh": "发送到终端的文本；可与 control 组合。",
            "en": "Text to send to the terminal, optionally combined with control."
          },
          "type": "string",
          "required": false
        },
        {
          "name": "control",
          "description": {
            "zh": "终端控制键，例如 enter、tab、esc 或 ctrl。",
            "en": "Terminal control key such as enter, tab, esc or ctrl."
          },
          "type": "string",
          "required": false
        },
        {
          "name": "timeoutMs",
          "description": {
            "zh": "wait 动作等待时长，毫秒，至少 1000。",
            "en": "Wait duration in milliseconds for action=wait; minimum 1000."
          },
          "type": "number",
          "required": false
        }
      ]
    }
  ]
}
*/

/**
 * Creates the super admin terminal tool exports.
 */
const superAdmin = (function () {
    const MAX_INLINE_TERMINAL_OUTPUT_CHARS = 12000;
    const DEFAULT_TERMINAL_SESSION_PREFIX = "super_admin_default_session";

    /**
     * Returns a stable foreground session name scoped to the chat and interpreter type.
     */
    function getDefaultTerminalSessionName(profileId: string): string {
        return `${DEFAULT_TERMINAL_SESSION_PREFIX}_${profileId}_${getChatId()}`;
    }

    /**
     * Saves oversized terminal output to a temporary file and returns its summary.
     */
    async function persistTerminalOutputIfTooLong(command: string, result: any): Promise<PersistedTerminalOutput | null> {
        const outputStr = typeof result?.output === "string"
            ? result.output
            : String(result?.output ?? "");
        if (outputStr.length <= MAX_INLINE_TERMINAL_OUTPUT_CHARS) {
            return null;
        }
        await Tools.Files.mkdir(OPERIT_CLEAN_ON_EXIT_DIR, true);
        const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
        const rand = Math.floor(Math.random() * 1000000);
        const filePath = `${OPERIT_CLEAN_ON_EXIT_DIR}/terminal_output_${timestamp}_${rand}.log`;
        await Tools.Files.write(filePath, outputStr, false);
        return {
            command,
            output: "(saved_to_file)",
            exitCode: result?.exitCode,
            sessionId: result?.sessionId,
            platform: result.platform,
            terminal: result.terminal,
            terminalType: result.terminalType,
            timedOut: result?.timedOut === true,
            context_preserved: true,
            output_saved_to: filePath,
            output_chars: outputStr.length,
            operit_clean_on_exit_dir: OPERIT_CLEAN_ON_EXIT_DIR,
            hint: "Output is large and saved to file. Use read_file_part or grep_code to inspect it.",
        };
    }
    /**
     * Executes a terminal command and returns output plus terminal environment details.
     * @param command - Command to execute.
     */
    async function terminal(params: TerminalParams) {
        const action = params.action ?? "run";
        if (action === "info") return Tools.System.terminal.info();
        if (action !== "run") {
            const sessionId = params.sessionId;
            if (typeof sessionId !== "string" || !sessionId.trim()) {
                throw new Error("sessionId is required for terminal session actions");
            }
            if (action === "cancel") return close({ sessionId });
            if (!["wait", "input", "screen"].includes(action)) {
                throw new Error("action must be run, wait, input, screen, cancel, or info");
            }
            await manageSessions({ action: "acquire_session", sessionId });
            try {
                if (action === "screen") return await Tools.System.terminal.screen(sessionId);
                if (action === "input") {
                    if (params.input === undefined && params.control === undefined) {
                        throw new Error("input or control is required for terminal action=input");
                    }
                    const message = await Tools.System.terminal.input(sessionId, {
                        input: params.input,
                        control: params.control,
                    });
                    const screen = await Tools.System.terminal.screen(sessionId);
                    return {
                        ...screen,
                        status: screen.commandRunning ? "running" : "completed",
                        message,
                    };
                }
                const timeoutMs = params.timeoutMs ?? 20_000;
                if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1_000) {
                    throw new Error("timeoutMs must be an integer of at least 1000");
                }
                const result = await Tools.System.terminal.wait(sessionId, timeoutMs);
                const persistedResult = await persistTerminalOutputIfTooLong(result.command, result);
                const running = result.commandRunning === true;
                return {
                    ...(persistedResult || result),
                    status: running ? "running" : result.timedOut ? "timed_out" : "completed",
                    waitCompleted: !running,
                    context_preserved: true,
                };
            } finally {
                await manageSessions({ action: "release_session", sessionId });
            }
        }
        let acquiredFamily: string | undefined;
        let activeSession: string | undefined;
        try {
            if (typeof params.command !== "string" || !params.command.trim()) {
                throw new Error("命令不能为空");
            }
            let command = params.command;
            const terminalInfo = await Tools.System.terminal.info();
            const android = terminalInfo.platform === "android";
            const channel = params.channel ?? "container";
            const interpreter = params.interpreter ?? "shell";
            if (android && channel !== "container" && channel !== "device") {
                throw new Error("channel must be container or device");
            }
            if (android && channel === "device" && interpreter !== "shell" && interpreter !== "bash") {
                throw new Error("interpreter must be shell or bash on the device channel");
            }
            if (!android && channel === "device") {
                throw new Error("device channel is available only on Android");
            }
            let profileId: string | undefined;
            let terminalType: "shell" | undefined;
            if (android && channel === "device") {
                terminalType = "shell";
                if (interpreter === "bash") {
                    command = "bash -c '" + command.replace(/'/g, "'\\''") + "'";
                }
            } else {
                const containerProfiles = terminalInfo.profiles.filter(entry =>
                    entry.terminalType === "bash" &&
                    (entry.terminal === "proot" || entry.terminal === "chroot")
                );
                const availableContainers = containerProfiles.filter(entry => entry.available);
                const requestedProfileId = android
                    ? (params.profileId ?? (availableContainers.some(entry => entry.id === terminalInfo.defaultProfileId)
                        ? terminalInfo.defaultProfileId
                        : availableContainers[0]?.id))
                    : (params.profileId ?? terminalInfo.defaultProfileId);
                if (android && !requestedProfileId) {
                    throw new Error("No available Linux container profile; install or configure a container first");
                }
                const profile = terminalInfo.profiles.find(entry => entry.id === requestedProfileId);
                if (!profile) throw new Error(`Terminal profile is not registered: ${requestedProfileId}`);
                if (!profile.available) throw new Error(`Terminal profile is unavailable: ${profile.id}`);
                if (android && !containerProfiles.some(entry => entry.id === profile.id)) {
                    throw new Error(`Linux container profile is unavailable: ${profile.id}`);
                }
                profileId = profile.id;
            }
            const selector = profileId ?? `android_${channel}_${interpreter}`;
            const sessionName = getDefaultTerminalSessionName(selector);
            const sessionFamily = `${sessionName}_${profileId ? "profile_" + profileId : channel}`;
            await manageSessions({ action: "acquire_family", sessionName: sessionFamily });
            acquiredFamily = sessionFamily;
            console.log(`执行终端命令: ${command}`);
            const stream = Tools.System.terminal.runStream({
                sessionName,
                ...(profileId ? { profileId } : { terminalType }),
                command
            });
            for await (const event of stream) {
                if (event.type === "start") {
                    await manageSessions({ action: "track", sessionId: event.sessionId, sessionName: sessionFamily });
                    activeSession = event.sessionId;
                    await manageSessions({ action: "release_family", sessionName: sessionFamily });
                    acquiredFamily = undefined;
                }
                if (event.type !== "completed") {
                    sendIntermediateResult(event);
                    continue;
                }
                const result = event.result;
                const persistedResult = await persistTerminalOutputIfTooLong(command, result);
                const timedOut = result.timedOut === true;
                return {
                    ...(persistedResult || result), command,
                    ...(android ? { channel } : {}),
                    background: false, commandRunning: false, started: true,
                    status: timedOut ? "timed_out" : "completed",
                    terminalEnvironment: { ...terminalInfo, platform: result.platform, terminal: result.terminal, terminalType: result.terminalType },
                    context_preserved: !timedOut,
                    message: timedOut ? "命令已到执行时限并停止。" : "命令已完成。"
                };
            }
            throw new Error("Terminal stream ended without a completion result");
        }
        catch (error) {
            console.error(`[terminal] 错误: ${error.message}`);
            console.error(error.stack);
            throw error;
        }
        finally {
            if (activeSession !== undefined) await manageSessions({ action: "release_session", sessionId: activeSession });
            if (acquiredFamily !== undefined) await manageSessions({ action: "release_family", sessionName: acquiredFamily });
        }
    }

    /** Closes the specified terminal session through the host terminal API. */
    async function close(params: TerminalSessionParams) {
        await manageSessions({ action: "acquire_session", sessionId: params.sessionId });
        try {
            const result = await Tools.System.terminal.close(params.sessionId);
            if (result.success) await manageSessions({ action: "forget", sessionId: params.sessionId });
            return result;
        } finally {
            await manageSessions({ action: "release_session", sessionId: params.sessionId });
        }
    }
    return {
        terminal,
        close
    };
})();
// 逐个导出
exports.terminal = superAdmin.terminal;
