from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer
import SocketServer
import sys
import os

PORT = None
TOKEN = None
FOLDER = None

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

    def do_GET(self):
        self._set_headers()
	print self.path
	if self.path == "/hook/%s" % (TOKEN,):
		self.wfile.write("")
		os.system("""
cd %s
git reset --hard
git pull
""" % (FOLDER,)
	else:
		self.wfile.write("")

server_address = ('', PORT)
httpd = HTTPServer(server_address, S)
httpd.serve_forever()

