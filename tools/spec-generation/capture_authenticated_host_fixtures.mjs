#!/usr/bin/env node
/** Capture deterministic, secret-free behavior from an authenticated local Host. */
import { spawn } from 'node:child_process'
import { mkdtemp, mkdir, realpath, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { createRequire } from 'node:module'

const ROOT = resolve(import.meta.dirname, '../..')
const args = parseArgs(process.argv.slice(2))
const payloadRoot = resolve(args['payload-root'] ?? join(ROOT, 'glass/ci/dsh-backend-payload'))
const output = resolve(args.output ?? join(ROOT, 'glass/Sources/Core/Resources/official-authenticated-host-fixtures.json'))
const dshBin = join(payloadRoot, 'node_modules/.bin/dsh')
const require = createRequire(join(payloadRoot, 'package.json'))
const WebSocket = require('ws')

const sandbox = await mkdtemp(join(tmpdir(), 'dsh-auth-fixture-'))
const homePath = join(sandbox, 'home')
const workspacePath = join(sandbox, 'workspace-a')
await mkdir(join(homePath, '.dsh'), { recursive: true })
await mkdir(workspacePath, { recursive: true })
const [home, workspace] = await Promise.all([realpath(homePath), realpath(workspacePath)])

let child
try {
  const launch = await startHost()
  const base = new URL(launch.url)
  base.search = ''
  const bootstrap = await fetch(launch.url, { redirect: 'manual' })
  if (bootstrap.status !== 303 || bootstrap.headers.get('location') !== '/') {
    throw new Error(`unexpected bootstrap response ${bootstrap.status}`)
  }
  const setCookie = bootstrap.headers.get('set-cookie')
  if (!setCookie) throw new Error('bootstrap omitted Set-Cookie')
  const cookie = setCookie.split(';', 1)[0]
  const root = await fetch(base, { headers: { Cookie: cookie } })
  if (root.status !== 200) throw new Error(`authenticated root returned ${root.status}`)

  const unary = await remoteCall(base, cookie, 'session/list', { _request: {} }, 'fixture-session-list')
  assertResponse(unary, 'fixture-session-list', true)
  if (JSON.stringify(unary.body.result.value) !== '{"items":[]}') {
    throw new Error(`fresh Host session/list was not empty: ${JSON.stringify(unary.body.result.value)}`)
  }

  const businessError = await remoteCall(
    base,
    cookie,
    'session/cancel',
    { request: { sessionId: 'fixture-missing-session' } },
    'fixture-business-error',
  )
  assertResponse(businessError, 'fixture-business-error', false)
  if (businessError.body.result.error?.code !== 'session/not-found') {
    throw new Error(`unexpected business error ${JSON.stringify(businessError.body.result.error)}`)
  }

  const socketURL = new URL(base)
  socketURL.protocol = socketURL.protocol === 'https:' ? 'wss:' : 'ws:'
  socketURL.pathname = '/api/remote.mux'
  const socket = new WebSocket(socketURL, { headers: { Cookie: cookie } })
  await onceSocket(socket, 'open')
  const frames = []
  socket.on('message', data => frames.push(JSON.parse(String(data))))

  socket.send(JSON.stringify({ type: 'open', streamId: 'fixture-events', endpoint: '$events', payload: { args: {} } }))
  const eventReady = await waitFrame(frames, frame => frame.streamId === 'fixture-events' && frame.type === 'item')
  if (eventReady.value?.type !== 'ready') throw new Error(`unexpected $events opening ${JSON.stringify(eventReady)}`)

  socket.send(JSON.stringify({ type: 'open', streamId: 'fixture-workspaces', endpoint: 'workspace/follow', payload: { args: {} } }))
  const workspaceOpening = await waitFrame(frames, frame => frame.streamId === 'fixture-workspaces' && frame.type === 'item')
  if (workspaceOpening.value?.type !== 'baseline') throw new Error(`unexpected workspace opening ${JSON.stringify(workspaceOpening)}`)

  const workspaceCreate = await remoteCall(
    base,
    cookie,
    'workspace/create',
    { request: { path: workspace } },
    'fixture-workspace-create',
  )
  assertResponse(workspaceCreate, 'fixture-workspace-create', true)
  const workspaceID = workspaceCreate.body.result.value?.workspace?.workspaceId
  if (typeof workspaceID !== 'string' || workspaceID.length === 0) throw new Error('workspace/create omitted workspaceId')
  const workspaceDeltas = [
    await waitFrame(frames, frame => frame.streamId === 'fixture-workspaces' && frame.type === 'item'),
    await waitFrame(frames, frame => frame.streamId === 'fixture-workspaces' && frame.type === 'item'),
  ]
  if (workspaceDeltas[0].value?.type !== 'upsert' || workspaceDeltas[1].value?.type !== 'order') {
    throw new Error(`unexpected workspace delta sequence ${JSON.stringify(workspaceDeltas)}`)
  }

  const sessionCreate = await remoteCall(
    base,
    cookie,
    'session/create',
    { request: { cwd: workspace, sessionId: 'fixture-session' } },
    'fixture-session-create',
  )
  assertResponse(sessionCreate, 'fixture-session-create', true)

  const commands = await remoteCall(
    base,
    cookie,
    'commands/list',
    { agentId: 'fixture-session' },
    'fixture-commands-list',
  )
  assertResponse(commands, 'fixture-commands-list', true)
  const commandNames = commands.body.result.value?.map(command => command.name)
  if (JSON.stringify(commandNames) !== JSON.stringify(['compact', 'export', 'feedback', 'goal', 'permission', 'plan'])) {
    throw new Error(`fresh Host commands/list drifted: ${JSON.stringify(commands.body.result.value)}`)
  }

  const skills = await remoteCall(
    base,
    cookie,
    'skills/list',
    { request: { sessionId: 'fixture-session' } },
    'fixture-skills-list',
  )
  assertResponse(skills, 'fixture-skills-list', true)
  if (JSON.stringify(skills.body.result.value) !== '{"skills":[]}') {
    throw new Error(`fresh Host skills/list drifted: ${JSON.stringify(skills.body.result.value)}`)
  }

  const downloadURL = new URL('/api/session.export?sessionId=fixture-session', base)
  const downloadHead = await fetch(downloadURL, { method: 'HEAD', headers: { Cookie: cookie } })
  const downloadGet = await fetch(downloadURL, { headers: { Cookie: cookie } })
  const zip = new Uint8Array(await downloadGet.arrayBuffer())
  if (downloadHead.status !== 200 || downloadGet.status !== 200 || hex(zip.slice(0, 4)) !== '504b0304') {
    throw new Error(`session export did not return a ZIP (${downloadHead.status}/${downloadGet.status})`)
  }
  socket.close()

  const fixture = normalize({
    schemaVersion: 1,
    authentication: {
      bootstrapStatus: bootstrap.status,
      redirectLocation: bootstrap.headers.get('location'),
      cookieInstalled: true,
      authenticatedRootStatus: root.status,
    },
    unary: {
      endpoint: 'session/list',
      request: remoteRequest('fixture-session-list', 'session/list', { _request: {} }),
      httpStatus: unary.status,
      contentType: contentType(unary.contentType),
      response: unary.body,
    },
    streamOpening: {
      eventRequest: { type: 'open', streamId: 'fixture-events', endpoint: '$events', payload: { args: {} } },
      eventReady,
      workspaceRequest: { type: 'open', streamId: 'fixture-workspaces', endpoint: 'workspace/follow', payload: { args: {} } },
      workspaceBaseline: workspaceOpening,
    },
    streamDelta: {
      trigger: remoteRequest('fixture-workspace-create', 'workspace/create', { request: { path: workspace } }),
      frames: workspaceDeltas,
    },
    controllerCatalogs: {
      commands: {
        endpoint: 'commands/list',
        request: remoteRequest('fixture-commands-list', 'commands/list', { agentId: 'fixture-session' }),
        httpStatus: commands.status,
        contentType: contentType(commands.contentType),
        response: commands.body,
      },
      skills: {
        endpoint: 'skills/list',
        request: remoteRequest('fixture-skills-list', 'skills/list', { request: { sessionId: 'fixture-session' } }),
        httpStatus: skills.status,
        contentType: contentType(skills.contentType),
        response: skills.body,
      },
    },
    businessError: {
      endpoint: 'session/cancel',
      request: remoteRequest('fixture-business-error', 'session/cancel', { request: { sessionId: 'fixture-missing-session' } }),
      httpStatus: businessError.status,
      contentType: contentType(businessError.contentType),
      response: businessError.body,
    },
    download: {
      request: { method: 'GET', path: '/api/session.export?sessionId=fixture-session' },
      head: responseFacts(downloadHead),
      get: { ...responseFacts(downloadGet), zipMagicHex: hex(zip.slice(0, 4)) },
    },
  }, { home, workspace, workspaceID, eventClientID: eventReady.value.clientId })
  await mkdir(dirname(output), { recursive: true })
  await writeFile(output, `${JSON.stringify(fixture, null, 2)}\n`)
  console.log(`captured authenticated Host fixture: ${output}`)
} finally {
  if (child && child.exitCode === null) {
    const exited = new Promise(resolveExit => child.once('exit', resolveExit))
    child.kill('SIGTERM')
    await Promise.race([exited, new Promise(resolveWait => setTimeout(resolveWait, 2_000))])
  }
  await rm(sandbox, { recursive: true, force: true })
}

async function startHost() {
  child = spawn(dshBin, ['web', '--port', '0', '--no-open'], {
    cwd: workspace,
    env: { ...process.env, HOME: home, DSH_HOME: join(home, '.dsh') },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  let buffer = ''
  const launchPattern = /(https?:\/\/127\.0\.0\.1:(\d+)\/\?token=\S+)/
  return await new Promise((resolveStart, rejectStart) => {
    const timeout = setTimeout(() => rejectStart(new Error('timed out waiting for Host launch URL')), 15_000)
    const accept = chunk => {
      buffer += String(chunk)
      const match = buffer.match(launchPattern)
      if (!match) return
      clearTimeout(timeout)
      resolveStart({ url: match[1], port: Number(match[2]) })
    }
    child.stdout.on('data', accept)
    child.stderr.on('data', accept)
    child.once('exit', code => {
      clearTimeout(timeout)
      rejectStart(new Error(`Host exited before launch (${code ?? 'signal'})`))
    })
    child.once('error', rejectStart)
  })
}

async function remoteCall(base, cookie, method, argsValue, rpcId) {
  const response = await fetch(new URL(`/api/${method}`, base), {
    method: 'POST',
    headers: { Cookie: cookie, 'content-type': 'application/json' },
    body: JSON.stringify(remoteRequest(rpcId, method, argsValue)),
  })
  return { status: response.status, contentType: response.headers.get('content-type'), body: await response.json() }
}

function remoteRequest(rpcId, method, argsValue) {
  return { type: 'client-request', rpcId, method, payload: { args: argsValue } }
}

function assertResponse(record, rpcId, expectedOK) {
  if (record.status !== 200 || record.body?.type !== 'server-response' || record.body?.rpcId !== rpcId || record.body?.result?.ok !== expectedOK) {
    throw new Error(`unexpected Remote response ${JSON.stringify(record)}`)
  }
}

function responseFacts(response) {
  return {
    status: response.status,
    contentType: contentType(response.headers.get('content-type')),
    contentDisposition: response.headers.get('content-disposition'),
  }
}

function contentType(value) { return value?.split(';', 1)[0] ?? null }
function hex(bytes) { return Buffer.from(bytes).toString('hex') }
function onceSocket(socket, event) { return new Promise((resolveEvent, reject) => { socket.once(event, resolveEvent); socket.once('error', reject) }) }
async function waitFrame(queue, predicate, timeoutMs = 5_000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const index = queue.findIndex(predicate)
    if (index >= 0) return queue.splice(index, 1)[0]
    await new Promise(resolveWait => setTimeout(resolveWait, 20))
  }
  throw new Error(`timed out waiting for mux frame; pending=${JSON.stringify(queue)}`)
}

function normalize(value, replacements) {
  const rewrite = current => {
    if (Array.isArray(current)) return current.map(rewrite)
    if (current && typeof current === 'object') return Object.fromEntries(Object.entries(current).map(([key, item]) => [key, rewrite(item)]))
    if (typeof current !== 'string') return current
    if (current === replacements.home) return '<fixture-home>'
    if (current === replacements.workspace) return '<fixture-workspace>'
    if (current === replacements.workspaceID) return '<fixture-workspace-id>'
    if (current === replacements.eventClientID) return '<fixture-client-id>'
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(current)) return '<fixture-time>'
    return current
  }
  return rewrite(value)
}

function parseArgs(argv) {
  const parsed = {}
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index]
    if (!item.startsWith('--')) throw new Error(`unexpected argument ${item}`)
    const key = item.slice(2)
    const next = argv[index + 1]
    if (next === undefined || next.startsWith('--')) throw new Error(`missing value for ${item}`)
    parsed[key] = next
    index += 1
  }
  return parsed
}
