type SuperAdminParams = Record<string, unknown>;

type TerminalParams = SuperAdminParams & {
    command?: string;
    profileId?: string;
    background?: string | boolean;
    timeoutMs?: string | number;
    action?: string;
    channel?: string;
    interpreter?: string;
    sessionId?: string;
    input?: string;
    control?: string;
};

type TerminalSessionParams = SuperAdminParams & {
    sessionId: string;
};

type TerminalWaitParams = TerminalSessionParams & {
    timeoutMs?: string | number;
};

type TerminalInputParams = TerminalSessionParams & {
    input?: string;
    control?: string;
};

type PersistedTerminalOutput = {
    command: string;
    output: string;
    exitCode: unknown;
    sessionId: unknown;
    timedOut: boolean;
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
    "states": [
        {
            "id": "android",
            "condition": "platform.android",
            "inheritTools": false,
            "tools": [
                {
                    "name": "terminal",
                    "display": {
                        "label": {"zh": "运行终端命令", "en": "Run terminal command"},
                        "icon": "terminal",
                        "targetParameter": "command"
                    },
                    "description": {
                        "zh": "常规项目命令用 container，Android 系统操作或用户指定的真机命令用 device。同一任务涉及两边时，按当前步骤选择。",
                        "en": "Use container for ordinary project commands and device for Android system operations or commands explicitly requested on the device. If a task uses both, choose the channel for the current step."
                    },
                    "parameters": [
                        {"name":"action","description":{"zh":"run 执行（默认）、wait 等待、input 输入、cancel 停止。","en":"run (default), wait, input, or cancel."},"type":"string","required":false},
                        {"name":"channel","description":{"zh":"执行通道：container（默认）或 device。","en":"For run: container (default) or device."},"type":"string","required":false},
                        {"name":"command","description":{"zh":"执行时传入命令。","en":"Command to run."},"type":"string","required":false},
                        {"name":"interpreter","description":{"zh":"真机可选 shell（默认）或 bash。","en":"On device: shell (default) or bash."},"type":"string","required":false},
                        {"name":"background","description":{"zh":"true 在后台执行（最长 30 分钟）。","en":"true runs in the background (up to 30 minutes)."},"type":"string","required":false},
                        {"name":"timeoutMs","description":{"zh":"前台执行时限或单次等待时限，毫秒。","en":"Foreground execution or single-wait timeout, in milliseconds."},"type":"string","required":false},
                        {"name":"sessionId","description":{"zh":"等待、输入或停止时传入原会话 ID。","en":"Original session ID for wait, input, or cancel."},"type":"string","required":false},
                        {"name":"input","description":{"zh":"输入文本。","en":"Text to send."},"type":"string","required":false},
                        {"name":"control","description":{"zh":"终端控制键，例如 enter。","en":"Terminal control key, for example enter."},"type":"string","required":false}
                    ]
                }
            ]
        }
    ],
    "tools": [
        {
            "name": "list_terminals",
            "display": {
                "label": {
                    "zh": "列出终端配置",
                    "en": "List terminal profiles"
                },
                "icon": "terminal"
            },
            "description": {
                "zh": "查询终端能力和可用配置。",
                "en": "List terminal capabilities and available profiles."
            },
            "parameters": []
        },
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
                "zh": "在当前设备的终端中执行命令。",
                "en": "Run a command in the current runtime terminal."
            },
            "parameters": [
                {
                    "name": "command",
                    "description": {
                        "zh": "与所选终端语法匹配的命令",
                        "en": "Command matching the selected terminal syntax."
                    },
                    "type": "string",
                    "required": true
                },
                {
                    "name": "profileId",
                    "description": {
                        "zh": "非 Android 平台的终端配置 ID。",
                        "en": "Terminal profile ID on non-Android platforms."
                    },
                    "type": "string",
                    "required": false
                },
                {
                    "name": "background",
                    "description": {
                        "zh": "true 立即返回，命令在后台继续运行。",
                        "en": "true returns immediately while the command continues."
                    },
                    "type": "string",
                    "required": false
                },
                {
                    "name": "timeoutMs",
                    "description": {
                        "zh": "毫秒。Android 前台命令的执行时限，默认 60000；其他平台为等待时限，默认 20000。最低 1000。",
                        "en": "Milliseconds, minimum 1000. Android foreground execution defaults to 60000; other platforms wait for 20000 by default."
                    },
                    "type": "string",
                    "required": false
                }
            ]
        },
        {
            "name": "close",
            "display": {
                "label": {
                    "zh": "关闭终端会话",
                    "en": "Close terminal session"
                },
                "icon": "terminal",
                "targetParameter": "sessionId"
            },
            "description": {
                "zh": "关闭指定终端会话并释放资源，终止该会话中正在执行的命令。关闭后该会话 ID 不再可用；再次运行终端工具会创建新会话，原会话上下文不会保留。",
                "en": "Close the specified terminal session, release its resources, and terminate its running command. The closed session ID is no longer usable. Running a terminal tool again creates a new session without the previous context."
            },
            "parameters": [
                {
                    "name": "sessionId",
                    "description": {
                        "zh": "要关闭的终端会话ID。",
                        "en": "ID of the terminal session to close."
                    },
                    "type": "string",
                    "required": true
                }
            ]
        },
        {
            "name": "terminal_wait",
            "display": {
                "label": {
                    "zh": "等待终端命令",
                    "en": "Wait for command"
                },
                "icon": "terminal",
                "targetParameter": "sessionId"
            },
            "description": {
                "zh": "等待后台任务的执行结果，完成后立即返回。默认等待 20 秒，等待时限和命令执行时限分别计时；终止任务时用 close。",
                "en": "Wait until the previous command in the same terminal session finishes. Unlike sleep, this tool can return early as soon as the command actually completes. Waiting defaults to 20 seconds. When the wait expires, the command keeps running in its original session; wait again, read its screen, or close the session."
            },
            "parameters": [
                {
                    "name": "sessionId",
                    "description": {
                        "zh": "目标终端会话ID。",
                        "en": "Target terminal session ID."
                    },
                    "type": "string",
                    "required": true
                },
                {
                    "name": "timeoutMs",
                    "description": {
                        "zh": "可选前台等待时间（毫秒，最低1000ms）。未传时默认20000ms（20秒）。",
                        "en": "Optional foreground wait (ms, minimum 1000ms). Defaults to 20000ms (20 seconds) if omitted."
                    },
                    "type": "string",
                    "required": false
                }
            ]
        },
        {
            "name": "get_screen",
            "display": {
                "label": {
                    "zh": "读取终端屏幕",
                    "en": "Read terminal screen"
                },
                "icon": "terminal",
                "targetParameter": "sessionId"
            },
            "description": {
                "zh": "获取当前终端会话可见屏幕内容（仅一屏，不包含历史滚动缓冲）。",
                "en": "Get the current visible screen content for the active terminal session (single screen only, no scrollback history)."
            },
            "parameters": [
                {
                    "name": "sessionId",
                    "description": {
                        "zh": "目标终端会话ID。",
                        "en": "Target terminal session ID."
                    },
                    "type": "string",
                    "required": true
                }
            ]
        },
        {
            "name": "input",
            "display": {
                "label": {
                    "zh": "发送终端输入",
                    "en": "Send terminal input"
                },
                "icon": "terminal",
                "targetParameter": "sessionId"
            },
            "description": {
                "zh": "向当前终端会话写入输入。input 与 control 至少传一个。常见用法：先写 input，再写 control=enter 提交；control=ctrl 且 input=c 可发送 Ctrl+C。",
                "en": "Write input to the active terminal session. Provide at least one of input or control. Typical usage: send input first, then control=enter to submit; use control=ctrl with input=c for Ctrl+C."
            },
            "parameters": [
                {
                    "name": "sessionId",
                    "description": {
                        "zh": "目标终端会话ID。",
                        "en": "Target terminal session ID."
                    },
                    "type": "string",
                    "required": true
                },
                {
                    "name": "input",
                    "description": {
                        "zh": "写入终端的文本",
                        "en": "Text to write to terminal."
                    },
                    "type": "string",
                    "required": false
                },
                {
                    "name": "control",
                    "description": {
                        "zh": "控制键，例如 enter / tab / esc / ctrl",
                        "en": "Control key, e.g. enter / tab / esc / ctrl."
                    },
                    "type": "string",
                    "required": false
                }
            ]
        }
    ]
}*/

/**
 * Creates the super admin terminal tool exports.
 */
const superAdmin = (function () {
    const MAX_INLINE_TERMINAL_OUTPUT_CHARS = 12000;
    const DEFAULT_FOREGROUND_TIMEOUT_MS = 20000;
    const DEFAULT_WAIT_TIMEOUT_MS = DEFAULT_FOREGROUND_TIMEOUT_MS;
    const ANDROID_FOREGROUND_TIMEOUT_MS = 60000;
    const ANDROID_MAX_COMMAND_TIMEOUT_MS = 1800000;
    const MIN_TIMEOUT_MS = 1000;
    const DEFAULT_TERMINAL_SESSION_PREFIX = "super_admin_default_session";
    const BACKGROUND_TERMINAL_SESSION_PREFIX = "super_admin_background";

    /**
     * Returns a stable foreground session name scoped to the chat and interpreter type.
     */
    function getDefaultTerminalSessionName(profileId: string): string {
        return `${DEFAULT_TERMINAL_SESSION_PREFIX}_${profileId}_${getChatId()}`;
    }

    /**
     * Returns a distinct background session name scoped to the chat and interpreter type.
     */
    function getBackgroundTerminalSessionName(profileId: string): string {
        return `${BACKGROUND_TERMINAL_SESSION_PREFIX}_${profileId}_${getChatId()}_${Date.now()}`;
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
            output_saved_to: filePath,
            output_chars: outputStr.length,
            operit_clean_on_exit_dir: OPERIT_CLEAN_ON_EXIT_DIR,
            hint: "Output is large and saved to file. Use read_file_part or grep_code to inspect it.",
        };
    }
    /**
     * Executes a terminal command and returns output plus terminal environment details.
     * @param command - Command to execute.
     * @param background - "true" starts a background terminal command and returns immediately.
     * @param timeoutMs - Optional timeout in milliseconds, with a minimum of 1000ms.
     */
    async function runCommand(params: TerminalParams) {
        try {
            if (typeof params.command !== "string" || !params.command.trim()) {
                throw new Error("命令不能为空");
            }
            const command = params.command;
            const background = params.background;
            const timeoutMs = params.timeoutMs;
            const terminalInfo = await Tools.System.terminal.info();
            const android = terminalInfo.platform === "android";
            const channel = params.channel ?? "container";
            const interpreter = params.interpreter ?? "shell";
            if (android && channel !== "container" && channel !== "device") {
                throw new Error("channel must be container or device");
            }
            if (android && params.interpreter !== undefined
                && (channel !== "device" || (interpreter !== "shell" && interpreter !== "bash"))) {
                throw new Error("interpreter must be shell or bash on the device channel");
            }
            const profileId = android ? undefined : (params.profileId ?? terminalInfo.defaultProfileId);
            if (!android) {
                const profile = terminalInfo.profiles.find(entry => entry.id === profileId);
                if (!profile) throw new Error(`Terminal profile is not registered: ${profileId}`);
                if (!profile.available) throw new Error(`Terminal profile is unavailable: ${profileId}`);
            }
            const isBackground = background === "true" || background === true;
            let timeout;
            if (!isBackground) {
                if (timeoutMs !== undefined) {
                    const parsedTimeout = Number(timeoutMs);
                    if (!Number.isSafeInteger(parsedTimeout) || parsedTimeout < MIN_TIMEOUT_MS) {
                        throw new Error(`timeoutMs必须是整数且不少于${MIN_TIMEOUT_MS}毫秒`);
                    }
                    timeout = android ? Math.min(parsedTimeout, ANDROID_MAX_COMMAND_TIMEOUT_MS) : parsedTimeout;
                }
                else {
                    timeout = android ? ANDROID_FOREGROUND_TIMEOUT_MS : DEFAULT_FOREGROUND_TIMEOUT_MS;
                }
            }
            const kind = channel === "device" ? "shell" : "bash";
            const sessionKey = profileId ?? kind;
            const nativeBash = android && channel === "device" && interpreter === "bash";
            const result = await Tools.System.terminal.run({
                sessionName: isBackground
                    ? getBackgroundTerminalSessionName(sessionKey) : getDefaultTerminalSessionName(sessionKey),
                ...(android ? { terminalType: kind } : { profileId }),
                command: nativeBash ? "bash -c '" + command.replace(/'/g, "'\\''") + "'" : command,
                waitMs: isBackground ? 0 : timeout
            });
            const terminalEnvironment = {
                ...(android ? {} : terminalInfo),
                platform: result.platform,
                terminal: result.terminal,
                terminalType: result.terminalType
            };
            const running = result.commandRunning === true;
            const expired = result.timedOut === true && !running;
            const persistedResult = await persistTerminalOutputIfTooLong(command, result);
            return {
                ...(persistedResult || result),
                ...(android ? { channel: androidChannel(result) } : {}),
                command,
                exitCode: running ? null : result.exitCode,
                background: running,
                commandRunning: running,
                started: true,
                status: running ? "running" : expired ? "timed_out" : "completed",
                timeoutMsUsed: isBackground ? 0 : timeout,
                terminalEnvironment,
                context_preserved: !expired && !nativeBash,
                next_command_uses_new_session: running && !isBackground,
                message: running
                    ? (android
                        ? "命令仍在运行。使用 action=wait 和原 sessionId 获取结果。"
                        : isBackground
                        ? "命令已在独立后台会话中启动。请用 sessionId 调用 get_screen 阅读输出、terminal_wait 等待完成，或 close 终止并关闭会话。"
                        : "命令仍在运行。使用 terminal_wait 获取执行结果。")
                    : expired ? "命令已到执行时限并停止。" : "命令已完成。"
            };
        }
        catch (error) {
            console.error(`[terminal] 错误: ${error.message}`);
            console.error(error.stack);
            throw error;
        }
    }

    function androidChannel(result: { terminal: string }) {
        return result.terminal === "android-system" ? "device" : "container";
    }

    async function terminal(params: TerminalParams) {
        const action = params.action ?? "run";
        if (action === "run") return runCommand(params);
        if (action !== "wait" && action !== "input" && action !== "cancel") {
            throw new Error("action must be run, wait, input, or cancel");
        }
        const sessionId = params.sessionId;
        if (typeof sessionId !== "string" || !sessionId.trim()) {
            throw new Error("sessionId is required for wait, input, or cancel");
        }
        if (action === "wait") return terminal_wait({ sessionId, timeoutMs: params.timeoutMs });

        // Use the managed observation to identify the original channel and verify ownership.
        const receipt = await Tools.System.terminal.wait(sessionId, 0);
        const details = {
            sessionId,
            channel: androidChannel(receipt),
            output: receipt.output.slice(-MAX_INLINE_TERMINAL_OUTPUT_CHARS),
            exitCode: receipt.commandRunning ? null : receipt.exitCode,
        };
        if (action === "input") {
            if (!receipt.commandRunning) throw new Error("The command is no longer running");
            const result = await input({ sessionId, input: params.input, control: params.control });
            return { ...result, ...details, status: "running", commandRunning: true };
        }
        if (!receipt.commandRunning && receipt.timedOut) {
            return { ...details, status: "timed_out", commandRunning: false };
        }
        const result = await close({ sessionId });
        if (!result.success) throw new Error(result.message);
        return { ...result, ...details, status: receipt.commandRunning ? "cancelled" : "completed", commandRunning: false };
    }

    /** Lists user-managed profiles and their default without platform assumptions. */
    async function list_terminals() {
        return Tools.System.terminal.info();
    }

    /**
     * Waits until prior work in the same terminal session has completed.
     * @param sessionId - Target session ID.
     * @param timeoutMs - Optional timeout in milliseconds, with a minimum of 1000ms.
     */
    async function terminal_wait(params: TerminalWaitParams) {
        try {
            const timeoutMs = params.timeoutMs;
            let timeout = DEFAULT_WAIT_TIMEOUT_MS;
            if (timeoutMs !== undefined) {
                const parsedTimeout = Number(timeoutMs);
                if (!Number.isSafeInteger(parsedTimeout) || parsedTimeout < MIN_TIMEOUT_MS) {
                    throw new Error(`timeoutMs必须是整数且不少于${MIN_TIMEOUT_MS}毫秒`);
                }
                timeout = parsedTimeout;
            }
            const sessionId = params.sessionId;
            const startedAt = Date.now();
            const result = await Tools.System.terminal.wait(sessionId, timeout);
            const running = result.commandRunning === true;
            const expired = result.timedOut === true && !running;
            const persistedResult = await persistTerminalOutputIfTooLong(result.command, result);
            return {
                ...(persistedResult || result),
                ...(result.platform === "android" ? { channel: androidChannel(result) } : {}),
                sessionId,
                exitCode: running ? null : result.exitCode,
                background: running,
                commandRunning: running,
                timedOut: result.timedOut,
                status: running ? "running" : expired ? "timed_out" : "completed",
                timeoutMsUsed: timeout,
                elapsedMs: Date.now() - startedAt,
                waitCompleted: !running,
                context_preserved: !expired,
                message: running ? "命令仍在运行，可继续等待。" : expired ? "命令已到执行时限并停止。" : "命令已完成。"
            };
        }
        catch (error) {
            console.error(`[terminal_wait] 错误: ${error.message}`);
            console.error(error.stack);
            throw error;
        }
    }
    /** Closes the specified terminal session through the host terminal API. */
    async function close(params: TerminalSessionParams) {
        return Tools.System.terminal.close(params.sessionId);
    }
    /**
     * Gets the visible screen content for a terminal session.
     * @param sessionId - Target session ID.
     */
    async function get_screen(params: TerminalSessionParams) {
        try {
            const sessionId = params.sessionId;
            const result = await Tools.System.terminal.screen(sessionId);
            return {
                sessionId: result.sessionId,
                terminalType: result.terminalType,
                rows: result.rows,
                cols: result.cols,
                content: result.content,
                commandRunning: result.commandRunning
            };
        }
        catch (error) {
            console.error(`[get_screen] 错误: ${error.message}`);
            console.error(error.stack);
            throw error;
        }
    }
    /**
     * Writes input or a control key to a terminal session.
     * @param sessionId - Target session ID.
     * @param input - Text input.
     * @param control - Control key.
     */
    async function input(params: TerminalInputParams) {
        try {
            if (params.input === undefined && params.control === undefined) {
                throw new Error("input和control至少需要提供一个");
            }
            const sessionId = params.sessionId;
            const result = await Tools.System.terminal.input(sessionId, {
                input: params.input,
                control: params.control
            });
            return {
                sessionId: sessionId,
                input: params.input,
                control: params.control,
                result
            };
        }
        catch (error) {
            console.error(`[input] 错误: ${error.message}`);
            console.error(error.stack);
            throw error;
        }
    }
    return {
        terminal,
        list_terminals,
        close,
        terminal_wait,
        get_screen,
        input
    };
})();
// 逐个导出
exports.terminal = superAdmin.terminal;
exports.list_terminals = superAdmin.list_terminals;
exports.close = superAdmin.close;
exports.terminal_wait = superAdmin.terminal_wait;
exports.get_screen = superAdmin.get_screen;
exports.input = superAdmin.input;
