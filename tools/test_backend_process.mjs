import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

// On Windows a venv python.exe can be a launcher with a child interpreter.
// Stop this test-owned subtree before removing its SQLite files.
export async function stopTestBackend(backend) {
  if (backend.exitCode !== null) return;
  const closed = new Promise(resolve => backend.once('close', resolve));
  if (process.platform === 'win32') {
    await promisify(execFile)('taskkill', ['/PID', String(backend.pid), '/T', '/F'], { windowsHide: true });
  } else {
    backend.kill('SIGTERM');
  }
  await closed;
}
