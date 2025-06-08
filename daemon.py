import os
import subprocess
import threading
from flask import Flask, request, jsonify

app = Flask(__name__)
RANK = int(os.environ.get("RANK", "0"))

process = None
process_lock = threading.Lock()


def start_process(cmd):
    global process
    with process_lock:
        if process and process.poll() is None:
            return False, "process already running"
        process = subprocess.Popen(cmd, shell=True)
    return True, f"started: {cmd}"


def stop_process():
    global process
    with process_lock:
        if process and process.poll() is None:
            process.terminate()
            process.wait()
            return True
    return False


@app.route('/run', methods=['POST'])
def run_cmd():
    data = request.get_json(force=True)
    cmd = data.get('command')
    if not cmd:
        return jsonify({'error': 'command required'}), 400
    ok, msg = start_process(cmd)
    if ok:
        return jsonify({'rank': RANK, 'status': 'started'})
    else:
        return jsonify({'rank': RANK, 'status': 'failed', 'message': msg}), 409


@app.route('/stop', methods=['POST'])
def stop_cmd():
    stopped = stop_process()
    return jsonify({'rank': RANK, 'stopped': stopped})


@app.route('/status', methods=['GET'])
def status():
    running = process is not None and process.poll() is None
    return jsonify({'rank': RANK, 'running': running})


if __name__ == '__main__':
    port = int(os.environ.get('DAEMON_PORT', 8000 + RANK))
    app.run(host='0.0.0.0', port=port)
