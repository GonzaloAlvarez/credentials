#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""launch small http server
"""

import thread
import json
import daemon

try:
    from BaseHTTPServer import BaseHTTPRequestHandler
    from SocketServer import TCPServer as HTTPServer
except ImportError:
    from http.server import BaseHTTPRequestHandler, HTTPServer

DEFAULT_SERVER_PORT = 12116

class S(BaseHTTPRequestHandler):
    def _set_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()

    def do_GET(self):
        self._set_headers()
        attribute = self.path[1:]
        try:
            self.wfile.write("{}".format(context[attribute]))
        except:
            self.wfile.write("")
            pass

    def do_HEAD(self):
        self._set_headers()
        
    def do_POST(self):
        if self.path.startswith('/kill_server'):
            print "Server is going down, run it again manually!"
            def kill_me_please(server):
                server.shutdown()
            thread.start_new_thread(kill_me_please, (httpd,))
            self.send_error(500)
        
def run(server_class=HTTPServer, handler_class=S, port=DEFAULT_SERVER_PORT):
    global httpd
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print 'Starting httpd...'
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()

if __name__ == "__main__":
    from sys import argv
    global context
    if len(argv) == 2:
        import json
        context = json.loads(argv[1])
    context['status'] = "Running"

    with daemon.DaemonContext():
        run()
