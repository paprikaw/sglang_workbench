import argparse
import requests

def main():
    parser = argparse.ArgumentParser(description="Start sglang on all daemons")
    parser.add_argument('--hosts', nargs='+', required=True,
                        help='list of host:port for each daemon')
    parser.add_argument('--command', required=True, help='command to execute')
    args = parser.parse_args()
    for host in args.hosts:
        url = f'http://{host}/run'
        try:
            r = requests.post(url, json={'command': args.command}, timeout=5)
            print(f'{host}: {r.status_code} {r.text}')
        except Exception as e:
            print(f'{host}: failed to send request: {e}')

if __name__ == '__main__':
    main()
