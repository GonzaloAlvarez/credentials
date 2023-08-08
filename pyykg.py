#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""launch small http server
"""

import threading
import json
import daemon

try:
    from BaseHTTPServer import BaseHTTPRequestHandler
    from SocketServer import TCPServer as HTTPServer
except ImportError:
    from http.server import BaseHTTPRequestHandler, HTTPServer

DEFAULT_SERVER_PORT = 12116

class WeakHttpServer(HTTPServer):
    allow_reuse_address = True
    def finish_request(self, request, client_address):
        request.settimeout(5) # Really short timeout as there is only 1 thread
        HTTPServer.finish_request(self, request, client_address)

class S(BaseHTTPRequestHandler):
    def _set_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()

    def do_GET(self):
        self._set_headers()
        print('here')
        print(context)
        attribute = self.path[1:]
        try:
            self.wfile.write(bytes("{}".format(context[attribute]), 'utf-8'))
        except:
            self.wfile.write("")
            pass

    def do_HEAD(self):
        self._set_headers()

    def do_POST(self):
        if self.path.startswith('/kill_server'):
            print("Server is going down, run it again manually!")
            def kill_me_please(server):
                server.shutdown()
            threading.Thread(target=kill_me_please, args=(httpd,)).start()
            thread.start_new_thread(kill_me_please, (httpd,))
            self.send_error(500)

def run( handler_class=S, port=DEFAULT_SERVER_PORT):
    global httpd
    server_address = ('', port)
    httpd = WeakHttpServer(server_address, handler_class)

    print("Starting httpd...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()

if __name__ == "__main__":
    from sys import argv
    global context
    context={}
    if len(argv) == 2:
        import json
        context = json.loads(argv[1])
    context['status'] = "Running"

    with daemon.DaemonContext(stdout = open('/home/local/ANT/gonalv/out.log', 'w'), stderr=open('/home/local/ANT/gonalv/err.log', 'w')):
    #with daemon.DaemonContext():
        run()
