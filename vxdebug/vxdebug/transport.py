import socket
from vxdebug.utils import *


################################################################################
# Transport
# Implementations for different transport layers (e.g. TCP)
################################################################################

class Transport:
    def __init__(self, name):
        self.name = name
        self.timeout = 10  # default timeout in seconds

    def connect(self, **kwargs):
        raise NotImplementedError("Subclasses should implement this!")

    def disconnect(self):
        raise NotImplementedError("Subclasses should implement this!")

    def is_connected(self):
        raise NotImplementedError("Subclasses should implement this!")

    def reg_read(self, addr, num=1):
        raise NotImplementedError("Subclasses should implement this!")

    def reg_write(self, addr, value, num=1):
        raise NotImplementedError("Subclasses should implement this!")

    # Low level send/receive
    def _send(self, data):
        raise NotImplementedError("Subclasses should implement this!")

    def _receive(self, bufsize=None):
        raise NotImplementedError("Subclasses should implement this!")
    

class TCPTransport(Transport):
    def __init__(self):
        super().__init__("TCP")
        self.sock = None
        self.log = Logger("TCP", debug_threshold=4)

    def connect(self, **kwargs):
        host = kwargs.get('host', None)
        port = kwargs.get('port', None)
        if host is None or port is None:
            raise ValueError("Host and port must be specified for TCP connection.")

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            self.sock.connect((host, port))
            self.log.info(f"Connected to {host}:{port}")
            return True
        except Exception as e:
            self.log.error(f"Failed to connect to {host}:{port} - {e}")
            self.sock = None
            return False
        
    def disconnect(self):
        if self.sock:
            self.sock.close()
            self.log.info("Disconnected from TCP server.")
            self.sock = None

    def is_connected(self):
        return self.sock is not None
    
    def _send(self, data):
        if not self.sock:
            self.log.error("Not connected to any TCP server.")
            return
        try:
            self.sock.sendall((data + "\n").encode())
            self.log.debug(f"TX: {data}", threshold=5)
        except Exception as e:
            self.log.error(f"Failed to send data - {e}")
            self.disconnect()

    def _receive(self, bufsize=4096):
        if not self.sock:
            self.log.error("Not connected to any TCP server.")
            return None
        try:
            if self.timeout is not None:
                self.sock.settimeout(self.timeout)
            data = self.sock.recv(bufsize)
            if data:
                self.log.debug(f"RX: {data.decode().strip()}", threshold=5)
                return data.decode().strip()
            else:
                self.log.warn("Connection closed by the server.")
                self.disconnect()
                return None
        except socket.timeout:
            return None
        except Exception as e:
            self.log.error(f"Failed to receive data - {e}")
            self.disconnect()
            return None
        
    def reg_read(self, addr, num=1):
        rvals = []
        for regaddr in range(addr, addr + num):
            self._send(f"r {regaddr:04x}")   # Read register command
            resp = self._receive()
            if resp and resp.startswith("ACK"):
                try:
                    rvals.append(int(resp.replace("ACK ", "").strip(), 16))
                except ValueError:
                    self.log.error(f"Invalid response for reg read: {resp}")
                    rvals.append(None)
            else:
                self.log.warn(f"Failed to read register at {regaddr:04x}")
                rvals.append(None)
        return rvals if num > 1 else rvals[0]

    def reg_write(self, addr, value, num=1):
        if num > 1 and not isinstance(value, list):
            raise ValueError("Value must be a list when writing multiple registers.")
        
        for regaddr in range(addr, addr + num):
            self._send(f"w {regaddr:04X} {value:08X}")
            resp = self._receive()
            if not (resp and resp.startswith("ACK")):
                self.log.warn(f"Failed to write register at {regaddr:04x}")
                return False
        return True
