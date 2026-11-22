import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../../', import.meta.url);
const androidImplementations = { bash: 'proot', shell: 'android-system' };

/** Reads current production source rather than generated package artifacts. */
function source(path) {
  return readFileSync(new URL(path, root), 'utf8');
}

/** Loads Super Admin with strict, explicitly typed terminal tools and complete host results. */
function fixture({ platform = 'android', defaultType = 'bash', implementations = androidImplementations, output = 'ok\n', timedOut = false, closeError } = {}) {
  const sessions = new Map();
  const calls = [];
  const files = new Map();
  const errors = [];
  let chatId = 'chat-a';
  let sessionSequence = 0;
  const terminalInfo = {
    platform,
    terminal: implementations[defaultType],
    terminalType: defaultType,
    types: Object.entries(implementations).map(([terminalType, terminal]) => ({ terminal, terminalType, available: true })),
  };
  const context = vm.createContext({
    exports: {},
    OPERIT_CLEAN_ON_EXIT_DIR: '/operitapp/data/temp/clean_on_exit',
    /** Supplies the active chat identity without a platform-dependent branch. */
    getChatId() { return chatId; },
    console: {
      /** Keeps command logging out of test output. */
      log() {},
      /** Records errors without changing their propagation. */
      error(...args) { errors.push(args); },
    },
    Tools: {
      Files: {
        /** Records creation of the virtual temporary output directory. */
        async mkdir(path, parents) { calls.push({ operation: 'mkdir', path, parents }); },
        /** Saves oversized command output inside the mocked virtual filesystem. */
        async write(path, content, append) {
          assert.equal(append, false);
          files.set(path, content);
        },
      },
      System: {
        terminal: {
          /** Models session-owned execution through the public managed terminal SDK. */
          async run(request) {
            calls.push({ operation: 'observe', observation: { op: 'run', ...structuredClone(request) } });
            const terminalType = request.terminalType;
            let nameToUse = request.sessionName;
            for (let generation = 1; sessions.get(`${terminalType}:${nameToUse}`)?.commandRunning; generation++) {
              nameToUse = `${request.sessionName}_generation_${generation}`;
            }
            const created = await this.create(nameToUse, terminalType);
            const result = await this.execStreaming(created.sessionId, request.command, { timeoutMs: request.waitMs });
            result.timedOut = timedOut || request.waitMs === 0;
            result.commandRunning = request.waitMs === 0;
            const session = [...sessions.values()].find(value => value.sessionId === created.sessionId);
            session.commandRunning = result.commandRunning;
            return result;
          },
          /** Waits without writing a second command into the running session. */
          async wait(sessionId, waitMs) {
            calls.push({ operation: 'observe', observation: { op: 'wait', sessionId, waitMs } });
            const session = [...sessions.values()].find(value => value.sessionId === sessionId);
            assert.ok(session);
            return { ...session, command: 'original command', output, exitCode: 0,
              timedOut, commandRunning: waitMs === 0 && session.commandRunning === true };
          },
          async input(sessionId, options) {
            calls.push({ operation: 'input', sessionId, options });
            return 'accepted';
          },
          /** Returns capabilities whose default may differ from the selected session. */
          async info() { return terminalInfo; },
          /** Requires exact interpreter selection and keys reusable sessions by name and type. */
          async create(name, terminalType) {
            calls.push({ operation: 'create', name, terminalType });
            if (!Object.hasOwn(implementations, terminalType)) {
              throw new Error(`Unsupported terminal type: ${terminalType}`);
            }
            const key = `${terminalType}:${name}`;
            const isNewSession = !sessions.has(key);
            if (isNewSession) {
              sessions.set(key, { sessionId: `session-${++sessionSequence}`, sessionName: name, platform, terminal: implementations[terminalType], terminalType });
            }
            return { ...sessions.get(key), isNewSession };
          },
          /** Closes only the requested session and preserves host failures. */
          async close(sessionId) {
            calls.push({ operation: 'close', sessionId });
            if (closeError) throw closeError;
            for (const [key, session] of sessions) {
              if (session.sessionId === sessionId) {
                sessions.delete(key);
                return { sessionId, success: true, message: 'Session closed' };
              }
            }
            throw new Error(`Terminal session not found: ${sessionId}`);
          },
          /** Returns the actual selected session's identity with the command output. */
          async exec(...args) {
            const [sessionId, command] = args;
            calls.push({ operation: 'exec', args });
            const session = [...sessions.values()].find(value => value.sessionId === sessionId);
            assert.ok(session, 'Execution must target an explicitly created session');
            return { ...session, command, output, exitCode: 0, timedOut };
          },
          /** Uses the cancellable observation transport for foreground commands. */
          async execStreaming(...args) {
            const [sessionId, command] = args;
            calls.push({ operation: 'execStreaming', args });
            const session = [...sessions.values()].find(value => value.sessionId === sessionId);
            assert.ok(session, 'Execution must target an explicitly created session');
            return { ...session, command, output, exitCode: 0, timedOut };
          },
        },
      },
    },
  });
  vm.runInContext(stripTypeScriptTypes(source('plugins/packages/buildin/super_admin.ts')), context);
  return {
    context, tools: context.exports, sessions, calls, files, errors, terminalInfo,
    /** Changes the active chat to exercise session identity isolation. */
    setChatId(value) { chatId = value; },
  };
}


/** Exercises the shared profile tools independently of platform-specific names. */
test('Android advertises one tool without a profile selector', () => {
  const metadata = JSON.parse(source('plugins/packages/buildin/super_admin.ts').match(/\/\* METADATA\s*([\s\S]*?)\*\//)[1]);
  const state = metadata.states.find(state => state.condition === 'platform.android');
  assert.equal(state.inheritTools, false);
  assert.deepEqual(state.tools.map(tool => tool.name), ['terminal']);
  assert.ok(metadata.tools.some(tool => tool.name === 'terminal'));
  assert.ok(metadata.tools.some(tool => tool.name === 'list_terminals'));
  assert.ok(metadata.tools.some(tool => tool.name === 'close'));
  assert.ok(!state.tools[0].parameters.some(parameter => parameter.name === 'profileId'));
});

/** Builds independent profiles sharing Bash to catch accidental interpreter-only selection. */
function profiles() {
  return [
    {id:'ubuntu_a',name:'Ubuntu A',terminal:'proot',terminalType:'bash',available:true},
    {id:'ubuntu_b',name:'Ubuntu B',terminal:'proot',terminalType:'bash',available:true},
    {id:'system',name:'System shell',terminal:'android-system',terminalType:'shell',available:true},
  ];
}

/** Creates a production-plugin fixture whose mock host routes by exact profile ID. */
function managedFixture(options = {}) {
  const f = fixture({ platform: 'linux', ...options });
  f.terminalInfo.defaultProfileId = 'ubuntu_a';
  f.terminalInfo.profiles = profiles();
  // The fixture's old interpreter model remains useful for session lifetime and output handling.
  const originalRun = f.context.Tools.System.terminal.run;
  f.context.Tools.System.terminal.run = async function(request) {
    const profile = f.terminalInfo.profiles.find(value => value.id === request.profileId);
    f.calls.push({operation:'selectedProfile', profileId:request.profileId});
    return originalRun.call(this, {...request, terminalType:profile.terminalType});
  };
  return f;
}

/** Verifies default changes affect new commands and separate same-shell configurations keep context isolated. */
test('default and explicit profiles select separate same-interpreter sessions', async () => {
  const f = managedFixture();
  const a = await f.tools.terminal({command:'pwd'});
  const b = await f.tools.terminal({command:'pwd',profileId:'ubuntu_b'});
  const again = await f.tools.terminal({command:'pwd',profileId:'ubuntu_a'});
  assert.notEqual(a.sessionId,b.sessionId);
  assert.equal(a.sessionId,again.sessionId);
  f.terminalInfo.defaultProfileId = 'ubuntu_b';
  assert.equal((await f.tools.terminal({command:'pwd'})).sessionId,b.sessionId);
  assert.deepEqual(f.calls.filter(call => call.operation === 'selectedProfile').map(call => call.profileId),
    ['ubuntu_a','ubuntu_b','ubuntu_a','ubuntu_b']);
  const discovered = await f.tools.list_terminals();
  assert.equal(discovered.profiles.length,3);
  assert.equal(discovered.defaultProfileId,'ubuntu_b');
});

/** Checks unknown and unavailable IDs fail before any execution reaches the host. */
test('invalid profile selection fails without starting a command', async () => {
  const f = managedFixture();
  await assert.rejects(f.tools.terminal({command:'id',profileId:'missing'}),/not registered/);
  f.terminalInfo.profiles[0].available = false;
  await assert.rejects(f.tools.terminal({command:'id'}),/unavailable/);
  assert.equal(f.calls.length,0);
});

/** Retains foreground timeout, background, large-output, and close behavior through the unified entry point. */
test('profile execution retains command ownership and file-backed output', async () => {
  const f = managedFixture({output:'x'.repeat(12001)});
  const first = await f.tools.terminal({command:'printf large'});
  assert.equal(first.timeoutMsUsed,20000);
  assert.equal(f.files.get(first.output_saved_to).length,12001);
  const background = await f.tools.terminal({command:'sleep 30',background:'true',profileId:'system'});
  assert.equal(background.background,true);
  assert.equal(background.terminal,'android-system');
  const result = await f.tools.close({sessionId:first.sessionId});
  assert.equal(result.success,true);
  assert.notEqual((await f.tools.terminal({command:'pwd'})).sessionId,first.sessionId);
  await assert.rejects(f.tools.terminal({command:'pwd',timeoutMs:999}),/1000/);
});

test('Android picks the container by default and uses the native session for device Shell and Bash', async () => {
  const f = fixture();
  f.terminalInfo.defaultProfileId = 'ubuntu_a';
  f.terminalInfo.profiles = profiles();
  const build = await f.tools.terminal({command: 'make', profileId: 'system'});
  const shell = await f.tools.terminal({command: 'getprop ro.product.model', channel: 'device'});
  const bash = await f.tools.terminal({command: "printf '%s' a\nprintf b", channel: 'device', interpreter: 'bash'});
  assert.equal(shell.sessionId, bash.sessionId);
  assert.notEqual(shell.sessionId, build.sessionId);
  assert.equal(build.channel, 'container');
  assert.equal(shell.channel, 'device');
  assert.equal(shell.terminal, 'android-system');
  const runs = f.calls.filter(call => call.operation === 'observe').map(call => call.observation);
  assert.equal(runs[0].waitMs, 60000);
  assert.equal(runs[2].command, "bash -c 'printf '\\''%s'\\'' a\nprintf b'");
  assert.deepEqual(runs.map(run => run.terminalType), ['bash', 'shell', 'shell']);
  assert.ok(runs.every(run => !Object.hasOwn(run, 'profileId')));
});

test('Android reports a stopped timeout separately from a running background job', async () => {
  const f = fixture({timedOut: true});
  const stopped = await f.tools.terminal({command: 'sleep 5', timeoutMs: 1000});
  assert.equal(stopped.status, 'timed_out');
  assert.equal(stopped.commandRunning, false);
  const running = await f.tools.terminal({command: 'sleep 50', channel: 'device', background: 'true'});
  assert.equal(running.status, 'running');
  const result = await f.tools.terminal({action: 'wait', sessionId: running.sessionId});
  assert.equal(result.channel, 'device');
  assert.equal(result.status, 'timed_out');
  assert.equal(result.commandRunning, false);
});

test('Android uses the existing session for input and cancellation', async () => {
  const f = fixture();
  const running = await f.tools.terminal({command: 'read answer', channel: 'device', background: true});
  const received = await f.tools.terminal({action: 'input', sessionId: running.sessionId, input: 'yes', control: 'enter'});
  assert.equal(received.channel, 'device');
  assert.equal(received.commandRunning, true);
  assert.equal(received.exitCode, null);
  assert.equal(typeof received.output, 'string');
  const cancelled = await f.tools.terminal({action: 'cancel', sessionId: running.sessionId});
  assert.equal(cancelled.channel, 'device');
  assert.equal(cancelled.status, 'cancelled');
  const completed = await f.tools.terminal({command: 'pwd'});
  const alreadyDone = await f.tools.terminal({action: 'cancel', sessionId: completed.sessionId});
  assert.equal(alreadyDone.status, 'completed');
  assert.equal(alreadyDone.exitCode, 0);
  assert.deepEqual(f.calls.filter(call => call.operation === 'close' || call.operation === 'input')
    .map(call => call.sessionId), [running.sessionId, running.sessionId, completed.sessionId]);
});

test('Android propagates workspace and permission failures without switching channels', async () => {
  const f = fixture();
  const attempts = [];
  f.context.Tools.System.terminal.run = async request => {
    attempts.push(request.terminalType);
    throw new Error(request.terminalType === 'bash' ? 'Container workspace unavailable' : 'Permission denied');
  };
  await assert.rejects(f.tools.terminal({command: 'pwd'}), /workspace unavailable/);
  await assert.rejects(f.tools.terminal({command: 'pm list packages', channel: 'device'}), /Permission denied/);
  assert.deepEqual(attempts, ['bash', 'shell']);
});
