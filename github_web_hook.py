from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer
import SocketServer
import sys
import os
import socket


PORT = None
TOKEN = None
FOLDER = None

address = [l for l in ([ip for ip in socket.gethostbyname_ex(socket.gethostname())[2] if not ip.startswith("127.")][:1], [[(s.connect(('8.8.8.8', 53)), s.getsockname()[0], s.close()) for s in [socket.socket(socket.AF_INET, socket.SOCK_DGRAM)]][0][1]]) if l][0][0]

try:
	PORT = int(sys.argv[1])
	TOKEN = sys.argv[2]
	FOLDER = os.path.expanduser(sys.argv[3])
except:
	print("Usage: %s [PORT] [TOKEN] [PATH-TO-REPOSITORY]" % (__file__,))
	print("i.e.: %s 8431 8sd89f9s8df9 ~/code/checkout/" % (__file__,))
	sys.exit()


class S(BaseHTTPRequestHandler):
    def _set_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()

    def do_POST(self):
        self._set_headers()
	print self.path
        self.wfile.write("")
	if self.path == "/hook/%s" % (TOKEN,):
		os.system("""cd %s
git reset --hard
git pull""" % (FOLDER,))

print("webhook url: http://%s:%s/hook/%s" % (address, PORT, TOKEN))
server_address = ('', PORT)
httpd = HTTPServer(server_address, S)
httpd.serve_forever()

