"""Optional authoritative DNS observer. No query/access logging or disk persistence."""
import hmac
import ipaddress
import json
import os
import re
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit
from dnslib import A, NS, SOA, QTYPE, RCODE, RR
from dnslib.server import BaseResolver, DNSLogger, DNSServer

DOMAIN = os.environ.get('DNS_TEST_DOMAIN', '').strip('.').lower()
TOKEN = os.environ.get('DNS_TEST_TOKEN', '')
TARGET = os.environ.get('DNS_TEST_IPV4', '')
TTL = 59
MAX_SESSIONS = 256
MAX_RESOLVERS = 64
sessions = {}
lock = threading.Lock()


def cleanup():
    now = time.monotonic()
    for sid in list(sessions):
        if sessions[sid]['expires'] <= now:
            del sessions[sid]


def reaper():
    while True:
        time.sleep(.5)
        with lock:
            cleanup()


class QuietLogger(DNSLogger):
    def log_recv(self, *args): pass
    def log_send(self, *args): pass
    def log_request(self, *args): pass
    def log_reply(self, *args): pass
    def log_truncated(self, *args): pass
    def log_error(self, *args): pass
    def log_data(self, *args): pass
    def log_pass(self, *args): pass


class Observer(BaseResolver):
    def resolve(self, request, handler):
        reply = request.reply()
        reply.header.aa = 1
        reply.header.ra = 0  # Never operate as an open recursive resolver.
        name = str(request.q.qname).rstrip('.').lower()
        qtype = request.q.qtype
        if name != DOMAIN and not name.endswith('.' + DOMAIN):
            reply.header.rcode = RCODE.REFUSED
            reply.header.aa = 0
            return reply
        apex = DOMAIN + '.'
        ns = 'ns1.' + apex
        if name == DOMAIN:
            if qtype in (QTYPE.NS, QTYPE.ANY):
                reply.add_answer(RR(apex, QTYPE.NS, ttl=60, rdata=NS(ns)))
            if qtype in (QTYPE.SOA, QTYPE.ANY):
                reply.add_answer(RR(apex, QTYPE.SOA, ttl=0, rdata=SOA(ns, 'hostmaster.' + apex, (1, 60, 60, 60, 0))))
            return reply
        if name == 'ns1.' + DOMAIN:
            if qtype == QTYPE.A:
                reply.add_answer(RR(name, QTYPE.A, ttl=60, rdata=A(TARGET)))
            return reply
        match = re.fullmatch(r'([a-f0-9]{32})-([0-7])\.' + re.escape(DOMAIN), name)
        if not match:
            reply.header.rcode = RCODE.NXDOMAIN
            return reply
        with lock:
            cleanup()
            session = sessions.get(match[1])
            if session is None:
                reply.header.rcode = RCODE.NXDOMAIN
                return reply
            source = handler.client_address[0]
            # Bound cardinality, and keep only resolver addresses + query kinds.
            if source in session['resolvers'] or len(session['resolvers']) < MAX_RESOLVERS:
                entry = session['resolvers'].setdefault(source, {'ip': source, 'queryTypes': set(), 'probes': set()})
                entry['queryTypes'].add(QTYPE.get(qtype, str(qtype)))
                entry['probes'].add(int(match[2]))
        if qtype == QTYPE.A:
            reply.add_answer(RR(name, QTYPE.A, ttl=0, rdata=A(TARGET)))
        # AAAA and HTTPS/SVCB get authoritative NODATA, not fabricated addresses.
        return reply


class API(BaseHTTPRequestHandler):
    server_version = 'DNSObserver'
    def log_message(self, *args): pass
    def log_error(self, *args): pass

    def send_json(self, code, payload):
        data = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if not hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + TOKEN):
            return self.send_json(401, {'error': 'Unauthorized'})
        url = urlsplit(self.path)
        with lock:
            cleanup()
            if url.path == '/start':
                if len(sessions) >= MAX_SESSIONS:
                    return self.send_json(429, {'error': 'Session limit; retry in 60 seconds'})
                sid = secrets.token_hex(16)
                sessions[sid] = {'expires': time.monotonic() + TTL, 'resolvers': {}}
                return self.send_json(200, {'id': sid, 'hosts': [f'{sid}-{i}.{DOMAIN}' for i in range(8)], 'expiresIn': TTL})
            if url.path == '/result':
                sid = parse_qs(url.query).get('id', [''])[0]
                session = sessions.get(sid) if re.fullmatch('[a-f0-9]{32}', sid) else None
                if session is None:
                    return self.send_json(404, {'error': 'Unknown or expired session'})
                result = [{**r, 'queryTypes': sorted(r['queryTypes']), 'probes': sorted(r['probes'])} for r in session['resolvers'].values()]
                return self.send_json(200, {'resolvers': result, 'observedResolvers': len(result), 'expiresIn': max(0, int(session['expires'] - time.monotonic())), 'interpretation': 'Compare these recursive resolver IPs with your expected VPN DNS. This observation alone does not prove a leak.'})
        self.send_json(404, {'error': 'Not found'})


class QuietHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    def handle_error(self, request, client_address): pass


def main():
    if not re.fullmatch(r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}', DOMAIN):
        raise SystemExit('Set DNS_TEST_DOMAIN to a delegated domain, e.g. dnscheck.example.com')
    if len(TOKEN) < 32:
        raise SystemExit('DNS_TEST_TOKEN must contain at least 32 characters')
    try:
        ipaddress.IPv4Address(TARGET)
    except ValueError:
        raise SystemExit('Set DNS_TEST_IPV4 to the public address of your DNS host')
    threading.Thread(target=reaper, daemon=True).start()
    resolver = Observer()
    port = int(os.environ.get('DNS_PORT', '53'))
    udp = DNSServer(resolver, port=port, address='0.0.0.0', logger=QuietLogger())
    tcp = DNSServer(resolver, port=port, address='0.0.0.0', tcp=True, logger=QuietLogger())
    udp.start_thread()
    tcp.start_thread()
    # Bind privately; expose through a TLS reverse proxy with access logs disabled.
    http = QuietHTTPServer((os.environ.get('HTTP_HOST', '127.0.0.1'), int(os.environ.get('HTTP_PORT', '8053'))), API)
    try:
        http.serve_forever()
    finally:
        http.server_close()
        udp.stop()
        tcp.stop()
        sessions.clear()


if __name__ == '__main__':
    main()
