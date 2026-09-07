from pathlib import Path

path = Path("glass/Sources/UI/Shell/NativeSplitContainer.swift")
text = path.read_text()

source = '''SessionRuntime(
                    controller: controllers.sessions,
                    generation: connection.context.events.generation,
                    address: .session(sessionID: selectedSessionID)
                )'''
target = '''SessionRuntime(
                    controller: controllers.sessions,
                    generation: connection.context.events.generation,
                    address: .session(sessionID: selectedSessionID),
                    controlRuntime: sessionControlRuntime,
                    interactions: eventRuntime,
                    subagents: controllers.subagents
                )'''
if text.count(source) != 1:
    raise SystemExit(f"existing-session runtime anchor count: {text.count(source)}")
text = text.replace(source, target, 1)

source = '''SessionRuntime(
                    controller: controllers.sessions,
                    generation: remoteGeneration,
                    address: .session(sessionID: sessionID)
                )'''
target = '''SessionRuntime(
                    controller: controllers.sessions,
                    generation: remoteGeneration,
                    address: .session(sessionID: sessionID),
                    controlRuntime: sessionControlRuntime,
                    interactions: eventRuntime,
                    subagents: controllers.subagents
                )'''
if text.count(source) != 1:
    raise SystemExit(f"selected-session runtime anchor count: {text.count(source)}")
text = text.replace(source, target, 1)

path.write_text(text)
